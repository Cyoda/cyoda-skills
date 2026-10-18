---
name: compute
description: Use when a cyoda-go workflow needs the developer's own code (a processor, a function criterion, or a schedule function served by a compute node over gRPC), when deciding whether a compute node is needed at all, or when a compute node won't connect, isn't routed requests, is evicted, or times out.
allowed-tools: Bash(*cyoda-help.sh *) Bash(cyoda help *) Bash(jq *)
---

# Cyoda compute nodes

A compute node is the developer's own process. It holds a gRPC stream open to cyoda-go and answers the processor, criteria and function requests that workflows send it. This skill is language-agnostic: give the protocol, the decisions and pseudocode, and write real code only in the language the developer uses.

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

If none apply, say so and stop. Wiring a processor or criterion into the workflow is a workflow change: "next, type `/cyoda:build` to add it".

## Step 1 — Get the contract

Before writing code, fetch the authoritative definitions. Field names come from these, never from the examples here:
- **Service and messages**: `cyoda-help.sh grpc proto` prints the `.proto` source as is. Generate stubs from it in the developer's language. `cyoda-help.sh grpc json` gives the descriptor set.
- **Message schemas**: `cyoda-help.sh cloudevents json | jq '.schemas["processing/<Name>.json"]'`, for `CalculationMemberJoinEvent`, `EntityProcessorCalculationRequest`/`Response`, `EntityCriteriaCalculationRequest`/`Response`, `EntityFunctionCalculationRequest`/`Response`, `EventAckResponse`. List them with `jq -r '.schemas | keys[]'`.

## Step 2 — Connect and join

Read `grpc --section CONNECTION` and `grpc --section "COMPUTE MEMBER PROTOCOL"`, then implement:

1. Open `CloudEventsService.startStreaming` on the gRPC port (`localhost:9090` by default, plaintext; TLS ends at an ingress). Metadata `authorization: Bearer <token>`. The token needs `ROLE_M2M`; mock mode grants it by default (`config auth --section OPTIONS`). For a JWT instance, the node mints its own token the way the `auth` skill's `get-token.sh` does, from credentials in its environment.
2. Send `CalculationMemberJoinEvent` first, with the node's tags and `joinedLegalEntityId` equal to the token's tenant.
3. The first event back is `CalculationMemberGreetEvent`. Keep its `memberId` and acknowledge it with `EventAckResponse`.
4. Read the stream continuously, and write to it from one place only (one goroutine, thread or task at a time). See [resources/grpc-patterns.md](resources/grpc-patterns.md) for the single-writer queue and reconnection.

Client settings, by the convention in `cyoda help config grpc`: `CYODA_COMPUTE_GRPC_ENDPOINT`, `CYODA_COMPUTE_TOKEN`, and `CYODA_COMPUTE_HTTP_BASE` for REST callbacks. The node reads them; the server doesn't.

## Step 3 — Keep-alive and eviction

Read `grpc --section KEEPALIVE` and `cyoda help config grpc`. The server sends `CalculationMemberKeepAliveEvent` every `CYODA_KEEPALIVE_INTERVAL` seconds (default 10). It evicts a member that sends nothing for `CYODA_KEEPALIVE_TIMEOUT` seconds (default 30), or whose stream write stalls that long. Any response or `EventAckResponse` counts as activity. On eviction every call in flight on that member fails with `COMPUTE_MEMBER_DISCONNECTED`.

## Step 4 — Tag routing

Read `grpc --section "TAG ROUTING"`, and only that section:
- A request goes to a member whose tags **overlap** the processor's or criterion's `calculationNodesTags` (a comma-separated string): one shared tag is enough.
- Several matching members: one is chosen at random on each dispatch. Use distinct tags per member for deterministic routing.
- Empty `calculationNodesTags`: any member of the tenant.
- No match: `NO_COMPUTE_MEMBER_FOR_TAG` (503).

`workflows --section PROCESSORS` says the node must declare *all* the tags. That's wrong; the code and `grpc` TAG ROUTING say overlap (Cyoda/cyoda-go#684 item B). Spell tags exactly the same on both sides.

## Step 5 — Handle requests

| Request | Pattern | Answer with |
|---|---|---|
| `EntityProcessorCalculationRequest` | [examples/processor.md](examples/processor.md) | `success`, and optional `payload.data` that replaces the entity's data |
| `EntityCriteriaCalculationRequest` | [examples/criteria.md](examples/criteria.md) | `matches`, and on `false` an optional `reason` |
| `EntityFunctionCalculationRequest` | `grpc` COMPUTE MEMBER PROTOCOL, function callout | `result` plus `resultKind: "Schedule"` |

Every response echoes the `requestId`. Deduplicate on it: a retried call must return the same answer.

**Rejection reason.** A function criterion may return `matches: false` with a `reason` (up to 2 KiB). For a manual transition it appears in the `400 WORKFLOW_FAILED` detail as `transition "<name>" criterion not matched: <reason>`. For automated transitions and workflow selection it's in the `TRANSITION_NOT_MATCH_CRITERION` / `WORKFLOW_SKIP` audit events' `data.reason`. Inline criteria can't give one.

## Step 6 — Execution mode and timeout

Read `workflows --section PROCESSORS`. `executionMode` is set per processor in the workflow:

| Mode | Use when |
|---|---|
| `SYNC` (default) | The result must be applied before the transition completes. Failure or timeout is `WORKFLOW_FAILED`; the entity stays in the source state |
| `ASYNC_SAME_TX` | Same failure semantics as `SYNC` |
| `ASYNC_NEW_TX` | A side effect whose failure must not block the transition (sending a message). Failure is only logged, and returned data is discarded |
| `COMMIT_BEFORE_DISPATCH` | Slow external work. The pre-callout state is committed first and is visible to readers; the processor **must be idempotent** because replays happen. `startNewTxOnDispatch: true` gives it a transaction for callbacks |

**Timeout.** `responseTimeoutMs` on the processor's config. Unset or `0` means the server default of 30 s, not a node default (#684-J). A miss is `DISPATCH_TIMEOUT` (503). Prefer raising `responseTimeoutMs` with `COMMIT_BEFORE_DISPATCH` over long `SYNC` calls.

## Step 7 — Calling back into Cyoda

A processor may read or write other entities over REST (`CYODA_COMPUTE_HTTP_BASE`) or the gRPC entity services.
- **Joining the transaction.** Each dispatched request carries a signed token in the CloudEvent extension `cyodatxtoken`. Echo it as the `X-Tx-Token` HTTP header or `tx-token` gRPC metadata, and the callback runs inside the originating transaction: it sees the cascade's uncommitted writes and commits or rolls back with it (`cluster --section "COMPUTE CALLBACK TRANSACTION ROUTING"`). Without the echo, the callback is a standalone transaction. Which modes supply a usable transaction is in `workflows` PROCESSORS (`startNewTxOnDispatch`).
- **Don't write the entity you're processing** and also return data for it: the returned data overwrites your write (`workflows` PROCESSORS, best-practice note). Pick one.
- **Moving a linked entity (event cascade).** Keep the linked entity's id in this entity's data. The processor fires a transition on it: `PATCH <http-base>/api/entity/JSON/{linkedId}/{transition}` with `Content-Type: application/merge-patch+json`, `If-Match: *` and body `{}` (`crud --section ENDPOINTS`). Mark that transition `manual: true` in the linked workflow. With the tx-token the two moves commit together; without it they commit separately. Best practice *Use manual transitions for external triggers*.

## Production checklist

- Idempotent on `requestId`, and on replays for `COMMIT_BEFORE_DISPATCH`.
- One writer per stream.
- Reconnect with exponential backoff, a fresh token and a new join; the member id changes.
- Keep answering within `CYODA_KEEPALIVE_TIMEOUT`, even while work is in progress.
- Track request latency, timeouts, evictions and reconnects. The server's `cyoda_dispatch_*` metrics are on `:9091/metrics` when telemetry is on (`telemetry --section "METRICS ENDPOINT"`).

**Not available in cyoda-go 0.8.4** (accepted for parity, but not implemented; `workflows` PROCESSORS): processor `type: "internalized"` (fails at dispatch), `asyncResult: true` and `crossoverToAsyncMs` (rejected at import), and `retryPolicy` retries (dispatch is single-shot). Don't design around them.

For a failing node, use the `cyoda:debug` skill (Path C). Cloud or migration questions: "That's not covered by this plugin."

## Common mistakes

| Mistake | Instead |
|---|---|
| Field names from these examples or memory | `cloudevents json` and `grpc proto` |
| "Register all of the processor's tags" | Overlap, per `grpc` TAG ROUTING (#684-B) |
| A 60-second response budget | `responseTimeoutMs`; unset is 30 s (#684-J) |
| Not answering keep-alives while busy | Ack within `CYODA_KEEPALIVE_TIMEOUT` |
| Two threads writing to the stream | One writer, a send queue |
| A compute node for a plain field check or a fixed delay | Inline criterion, or `schedule.delayMs` |
| Callbacks that can't see the cascade's writes | Echo `cyodatxtoken` as `X-Tx-Token` / `tx-token` |
