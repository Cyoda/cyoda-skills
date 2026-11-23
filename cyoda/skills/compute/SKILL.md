---
name: compute
description: Use when a cyoda-go workflow needs the developer's own code (a processor, a function criterion, or a schedule function served by a compute node over gRPC), when deciding whether a compute node is needed at all, or when a compute node won't connect, isn't routed requests, is evicted, or times out.
allowed-tools: Bash(*cyoda-ports.sh *) Bash(*cyoda-help.sh *) Bash(cyoda help *) Bash(jq *) Bash(cyoda *) Bash(docker *) Bash(kill *) Bash(curl *) Bash(mktemp *) Bash(rm *)
---

# Cyoda compute nodes

A compute node is the developer's own process: it holds a gRPC stream open to cyoda-go and answers the processor, criteria and function requests that workflows send it. Write real code in the language the developer uses; if they haven't named one, give pseudocode.

**Facts come from `cyoda help`, not from this file or memory.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` (stderr shows `SOURCE=instance|binary|web`). Exit 2: unknown topic; exit 6: unknown section (stderr lists the sections). Name the section you used.

## Is a compute node needed?

Many workflows need none. Read `workflows --section CRITERIA` and `workflows --section "SCHEDULED TRANSITIONS"` first.

| The developer needs | Without a compute node | With one |
|---|---|---|
| A condition on the entity's own data or state | `simple`, `lifecycle`, `group`, `array` criteria | - |
| A check that needs other data, or a rejection reason the user sees | - | Function criterion |
| A fixed delay or timeout | `schedule` with `delayMs` | - |
| A fire time computed per entity | - | `schedule.function` (a function callout) |
| Calling another system, computing and writing data | - | Processor |
| Moving a linked entity when this one changes | - | Processor that fires the linked entity's transition |

If none apply, say so and stop. Wiring a processor or criterion into the workflow is a workflow change, covered by `cyoda:build`.

## Step 1 — Get the contract

Before writing code, fetch the authoritative definitions. Field names come from these, never from the examples here:
- **Service and messages**: `cyoda-help.sh grpc proto` prints the `.proto` source as is. Generate stubs from it in the developer's language. `cyoda-help.sh grpc json` gives the descriptor set.
- **Message schemas**: `cyoda-help.sh cloudevents json | jq '.schemas["processing/<Name>.json"]'`, for `CalculationMemberJoinEvent`, `EntityProcessorCalculationRequest`/`Response`, `EntityCriteriaCalculationRequest`/`Response`, `EntityFunctionCalculationRequest`/`Response`, `EventAckResponse`. List them with `jq -r '.schemas | keys[]'`.

## Step 2 — Connect and join

Read `grpc --section CONNECTION` and `grpc --section "COMPUTE MEMBER PROTOCOL"`, then implement:

1. Open `CloudEventsService.startStreaming` on the gRPC port (`localhost:9090` by default, plaintext; TLS ends at an ingress). Metadata `authorization: Bearer <token>`. Only the node's own M2M client's `client_credentials` token opens a stream: an on-behalf-of token or a `cyoda token` is refused (`auth integration --section "STEP 6 — CONNECT A COMPUTE NODE"`). For a JWT instance, the node gets it the way the `auth` skill's `get-token.sh` does (tenant-scoped token endpoint), from its own client's credentials in its environment, renews it before expiry and keeps the stream open. Mock mode needs no token while `CYODA_IAM_MOCK_KIND` is `service` (`config auth --section OPTIONS`).
2. Send `CalculationMemberJoinEvent` first, with the node's tags and `joinedLegalEntityId` equal to the token's tenant (`mock-tenant` in mock mode).
3. The first event back is `CalculationMemberGreetEvent`. Keep its `memberId` and acknowledge it with `EventAckResponse`.
4. The full lifecycle and event envelope: [resources/grpc-patterns.md](resources/grpc-patterns.md).

Client settings, by the `CYODA_COMPUTE_*` convention in `config grpc --section OPTIONS` (endpoint, HTTP base, tenant, client id and secret). The node reads them; the server doesn't.

## Step 3 — Keep-alive and eviction

Read `grpc --section KEEPALIVE` and `cyoda help config grpc`, and take the defaults you quote from there. The server sends `CalculationMemberKeepAliveEvent` every `CYODA_KEEPALIVE_INTERVAL` seconds. It evicts a member that sends nothing for `CYODA_KEEPALIVE_TIMEOUT` seconds, or whose stream write stalls that long. Any response or `EventAckResponse` counts as activity. On eviction every call in flight on that member fails with `COMPUTE_MEMBER_DISCONNECTED`.

## Step 4 — Tag routing

Read `grpc --section "TAG ROUTING"`:
- A request goes to a member whose tags **overlap** the processor's or criterion's `calculationNodesTags` (a comma-separated string): one shared tag is enough.
- Several matching members: round robin. To reach one particular member, give it a tag of its own.
- Empty `calculationNodesTags`: any member of the tenant.
- No match: the callout waits `CYODA_DISPATCH_WAIT_TIMEOUT` for one to join, then `NO_COMPUTE_MEMBER_FOR_TAG` (503).

Spell tags exactly the same on both sides.

## Step 5 — Handle requests

| Request | Pattern | Answer with |
|---|---|---|
| `EntityProcessorCalculationRequest` | [examples/processor.md](examples/processor.md) | optional `payload.data` that replaces the entity's data |
| `EntityCriteriaCalculationRequest` | [examples/criteria.md](examples/criteria.md) | `matches` (required), and on `false` an optional `reason` |
| `EntityFunctionCalculationRequest` | `grpc` COMPUTE MEMBER PROTOCOL, function callout | `result` plus `resultKind: "Schedule"` |

Every response carries its own new `id`, the request's `requestId` and the `entityId`. Every try of one callout carries the same `requestId`: deduplicate on it, a repeat must return the same answer.

**Success and failure** (`grpc` COMPUTE MEMBER PROTOCOL). An omitted `success` is a success; report a failure with an explicit `success: false` (an `error` object alone is a success). A criteria answer without `matches`, or any answer cyoda can't read, fails the operation with `400 WORKFLOW_FAILED`. A `success: false` is never tried on another member.

**Criteria and schedule functions may run more than once** for one callout, on different members: they must have no effects. Work with effects belongs in a processor (`workflows` PROCESSORS, **Repeating a processor**).

**Identity.** `authid`/`authtype` name who the work is for, `authexecid`/`authexectype` who executes it; `authclaims` are the executor's roles, never the user's (`auth integration --section "READING IDENTITY IN A COMPUTE NODE"`).

**Rejection reason.** A function criterion may return `matches: false` with a `reason` (Cyoda keeps the first 2048 characters). For a manual transition it appears in the `400 WORKFLOW_FAILED` detail as `transition "<name>" criterion not matched: <reason>`. For automated transitions and workflow selection it's in the `TRANSITION_NOT_MATCH_CRITERION` / `WORKFLOW_SKIP` audit events' `data.reason`. When the function condition sits in a group or has a pre-check, the reason lists each function condition reached (`workflows --section CRITERIA`, *Function conditions*). Inline criteria can't give one.

## Step 6 — Execution mode and timeout

Read `workflows --section PROCESSORS`. `executionMode` is set per processor in the workflow:

| Mode | Use when |
|---|---|
| `SYNC` (default) | The result must be applied before the transition completes. A failed callout fails the operation; the entity stays in the source state |
| `ASYNC_SAME_TX` | Same failure semantics as `SYNC` |
| `ASYNC_NEW_TX` | A side effect whose failure must not block the transition (sending a message). Failure is only logged, and returned data is discarded |
| `COMMIT_BEFORE_DISPATCH` | Slow external work. The pre-callout state is committed first and is visible to readers; the processor **must be idempotent** because replays happen. `startNewTxOnDispatch: true` (beside `executionMode`, not in `config`) gives it a transaction for callbacks |

**Timeout.** `responseTimeoutMs` on the processor's config. Unset or `0` means the server's `CYODA_CALLOUT_RESPONSE_TIMEOUT_MS`; import refuses a value above `CYODA_CALLOUT_RESPONSE_TIMEOUT_MAX_MS` (defaults in `config grpc --section OPTIONS`). One try with no answer is `DISPATCH_TIMEOUT` (503), several failed tries `CALLOUT_FAILED` (503). Prefer raising `responseTimeoutMs` with `COMMIT_BEFORE_DISPATCH` over long `SYNC` calls.

**Repeats.** Cyoda gives a processor that got no answer to another compute member, and repeats it in a scheduled run, only when it is declared `idempotent: true` in its `config`; without it, the callout or the scheduled task fails. `retryPolicy` sets the number of tries (`workflows` PROCESSORS, **Tries, waiting and time**). Best practice *Declare `idempotent: true` only where a repeat is harmless everywhere*; `workflows` PROCESSORS (**Repeating a processor**).

**Behaviour help doesn't settle.** When help doesn't settle how the execution mode, timeout and callbacks combine, say what it leaves open and ask whether to spike it on a throwaway cyoda-go (in-memory with mock auth, per `cyoda help run`, or the stack in Docker; ports from `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-ports.sh pick` on a temp dir, or `CYODA_PORT_BASE` for a separate range, with a stub compute node); `cyoda` always loads `~/.config/cyoda/cyoda.env`, so set storage and auth explicitly.

## Step 7 — Calling back into Cyoda

A processor may read or write other entities over REST (`CYODA_COMPUTE_HTTP_BASE`) or the gRPC entity services, with the node's own current client token as the bearer. The callback rules are in `grpc` COMPUTE MEMBER PROTOCOL (*What a compute member must do*).
- **Joining the transaction.** Each dispatched request carries a signed token in the CloudEvent extension `cyodatxtoken`, valid for that one try. Echo it as the `X-Tx-Token` HTTP header or `tx-token` gRPC metadata, and the callback runs inside the originating transaction: it sees the cascade's uncommitted writes and commits or rolls back with it (`cluster --section "COMPUTE CALLBACK TRANSACTION ROUTING"`). Without the echo, the callback is a standalone transaction. Which modes supply a usable transaction is in `workflows` PROCESSORS (`startNewTxOnDispatch`).
- **Callbacks of one transaction go in series**; each is all-or-nothing. A callback write refused with a non-retryable error fails the whole operation (`409 TRANSACTION_ROLLBACK_ONLY`). On `410 CALLOUT_SUPERSEDED` (another member got the work, or the callout ended) stop working on that request.
- **Never write or delete the entity you're processing**, nor any entity whose workflow is running in the same transaction; return the changes instead (`workflows` PROCESSORS, *Design rule*). The same holds for criteria and schedule functions.
- **Moving a linked entity (event cascade).** Keep the linked entity's id in this entity's data. The processor fires a transition on it: `PATCH <http-base>/api/entity/JSON/{linkedId}/{transition}` with `Content-Type: application/merge-patch+json`, `If-Match: *` and body `{}` (`crud --section ENDPOINTS`). Mark that transition `manual: true` in the linked workflow. With the tx-token the two moves commit together; without it they commit separately. Best practice *Use manual transitions for steps the outside world triggers* (`cyoda-help.sh design`).
- **Worked cascade:** [examples/cascade/](examples/cascade/) holds the workflow side only. An `order`'s manual `confirm` carries the function criterion `has-address` and the processor `create-shipment`, tagged `smoke-compute`. The processor creates a `shipment` linked by `$.orderId`, stores its id in `$.shipmentId` and fires the shipment's manual `dispatch`. The files keep `"version": "${SCHEMA_VERSION}"`; importing them is a workflow change (`cyoda:build`). No node code is included; write it in the developer's language from Steps 1–7. The order sample declares `shipmentId`, so the processor's returned data passes the locked (strict) model.

## Node checklist

- Idempotent on `requestId`. A `COMMIT_BEFORE_DISPATCH` replay is a new callout with a new `requestId` (the client ran the operation again), so key its side effects on a natural id (a write-once external id), not only `requestId`.
- After a reconnect, join again; the member id changes.
- Keep answering within `CYODA_KEEPALIVE_TIMEOUT`, even while work is in progress.
- The server's `cyoda_dispatch_*` and `cyoda_callout_*` metrics are on `:9091/metrics` when telemetry is on (`telemetry --section "METRICS ENDPOINT"`).

**Not available in cyoda-go 0.9.0** (`workflows` PROCESSORS): processor `type: "internalized"`, `asyncResult: true` and `crossoverToAsyncMs` (all rejected at import).

For a failing node, use the `cyoda:debug` skill (Path C).
