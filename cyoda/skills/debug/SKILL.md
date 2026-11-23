---
name: debug
description: Use when a cyoda-go call returns an error code, a transition doesn't fire or fails, an entity is stuck or in an unexpected state or has disappeared, a processor, criterion or compute node fails or times out, the instance seems unreachable, or the developer asks for an entity's history, audit trail or state at a past time.
allowed-tools: Bash(*cyoda-ports.sh *) Bash(*cyoda-call.sh *) Bash(*cyoda-help.sh *) Bash(*cyoda-status.sh*) Bash(jq *) Bash(cat *) Bash(cyoda *) Bash(docker *) Bash(kill *) Bash(curl *) Bash(*cyoda-config-write.sh *) Bash(*get-token.sh*) Bash(ls *) Bash(cp *) Bash(chmod *) Bash(cmp *) Bash(mkdir *) Bash(find *) Bash(grep *) Bash(mktemp *) Bash(rm *)
---

# Cyoda debugging and observation

Two modes: **debugging** (something failed or looks wrong) and **observation** (what happened to an entity, and when).

**Facts come from `cyoda help`, not from this file.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` (stderr shows `SOURCE=instance|binary|web`). Exit 2: unknown topic; exit 6: unknown section (stderr lists the sections). Name the section you used.

**Every API call** goes through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh <METHOD> <PATH> [curl args...]`. PATH is relative to `<endpoint>/api`. The body goes to stdout and `HTTP_STATUS=<code>` to stderr.

| Exit | Meaning | What you do |
|---|---|---|
| 0 | 2xx | continue |
| 1 | invalid config file, or `CYODA_PROFILE` names a profile that doesn't exist | show stderr and stop; the plugin config is covered by `cyoda:setup` |
| 22 | HTTP ≥ 400, or `HTTP_STATUS=000` | `000` means curl never got a response (bad `@file` path, connection refused): fix the call, it isn't server evidence. 401/403: the script already retried once with a fresh token. Show the error and carry out `cyoda:auth`'s procedure yourself (read `${CLAUDE_PLUGIN_ROOT}/skills/auth/SKILL.md`), explaining the error from `auth tokens --section ERRORS` (and `auth clients --section "REQUEST FLOW"` for a rejected client) with the section named; once a call succeeds, re-run the failed call and go on. Otherwise the error is evidence: read it (Path A) |
| 4 | the profile's tokenCommand failed | show stderr and carry out `cyoda:auth`'s procedure, as for a 401 |
| 5 | no endpoint configured | say so; starting or linking an instance is covered by `cyoda:setup` |
| 64 | usage error (a leading `-` or a missing method/path) | fix the call form |

**Repair.** Diagnose with GETs and query POSTs, then repair:
- A model or workflow change (new state, criterion, transition, changeLevel, new model version): state it in one line. When the request asks for the change, carry out `cyoda:build`'s procedure yourself (read `${CLAUDE_PLUGIN_ROOT}/skills/build/SKILL.md`); otherwise name `cyoda:build` as where it is made.
- A change to one entity (a loopback to re-evaluate, firing a transition): send it through `cyoda-call.sh`, then show the exact call you made and its response.

## Step 0 — Connection

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. Show its status line and every `WARN=` line.
- `STATUS=not_configured`: say no instance is configured; starting or linking one is covered by `cyoda:setup`. Stop.
- `STATUS=unreachable`: the endpoint didn't answer. Read `run --section "HEALTH PROBES"`: the API port serves `GET /api/health` (`{"status":"UP"}`, or 503 `DOWN` after a recovered panic, latched until the node is replaced); `/livez` and `/readyz` are only on the admin listener (`127.0.0.1:9091` by default), and `cyoda health` checks the local one. State that the instance at the endpoint isn't answering; switching profiles or starting an instance is covered by `cyoda:setup`.

## Debugging

### Path A — a call returned an error

1. Read `.properties.errorCode` and `.detail` from the body (RFC 9457 problem JSON; `errors --section DESCRIPTION`).
2. Run `cyoda-help.sh errors <errorCode>`. Every code has its own page.
3. Explain the cause from that page plus the `detail`, then take the matching path:

| errorCode | Look at |
|---|---|
| `WORKFLOW_FAILED` (400) | Path B. A `detail` of `transition "<t>" criterion not matched: <reason>` is a criterion; `processor X failed` is Path C |
| `TRANSITION_NOT_FOUND` | `GET /entity/{id}/transitions`: the name isn't available from the current state |
| `MODEL_NOT_FOUND` (404), `MODEL_NOT_LOCKED` (409) | Path D: the model lifecycle wasn't completed |
| `VALIDATION_FAILED`, `INCOMPATIBLE_TYPE` (400) | Path D: the payload doesn't fit the locked schema |
| `NO_COMPUTE_MEMBER_FOR_TAG`, `COMPUTE_MEMBER_DISCONNECTED`, `DISPATCH_TIMEOUT`, `CALLOUT_FAILED` (503), `TRANSACTION_ROLLBACK_ONLY` (409) | Path C |
| `ENTITY_MODIFIED` (412), `PRECONDITION_REQUIRED` (428), `CONFLICT` (409, retryable) | `crud --section "OPTIMISTIC CONCURRENCY"`: stale or missing `If-Match`; `CONFLICT` is a lost write race, so run the operation again |
| `BAD_REQUEST` (400) | An unknown or misspelt body member or query parameter: `openapi --section "REQUEST BODIES"` / `"QUERY PARAMETERS"`. An empty `PUT /entity/JSON/{id}/{t}`: fire it with PATCH `{}`, `If-Match: *`, `application/merge-patch+json` (`crud --section ENDPOINTS`) |
| `CONDITION_TYPE_MISMATCH`, `INVALID_CONDITION` (400) | The condition's operator doesn't fit the field's type, or its shape is wrong (`search --section ERRORS`). In a workflow criterion this surfaces as `WORKFLOW_FAILED` |
| `POINT_IN_TIME_AFTER_CONSISTENCY_TIME` (400) | The `pointInTime` is later than the consistency time: read at or before `GET /entity/consistency-time` (`crud --section "POINT-IN-TIME SEMANTICS"`) |

### Path B — a transition didn't fire, or the entity is in the wrong state

1. `GET /entity/{id}`: `.meta.state` and `.meta.transactionId`.
2. `GET /model/{e}/{v}/workflow/export`: does the current state declare the transition? Is it `manual`, `disabled`, or `schedule`d? Read `workflows --section TRANSITIONS`.
3. `GET /entity/{id}/transitions`: what can fire now. This read can itself fail with `WORKFLOW_FAILED` when the selected workflow doesn't declare the current state, or when a selection criterion can't be evaluated (`errors WORKFLOW_FAILED`).
4. `GET '/audit/entity/{id}?eventType=StateMachine&limit=100'` (help: `audit --section ENDPOINTS`). Newest first. Look for:
   - `TRANSITION_NOT_MATCH_CRITERION`: `data.transition` was held by its criterion; `data.reason` says why (specific only for function criteria).
   - `TRANSITION_ABORTED` (`data.transition`, `expectedTxId` vs `actualTxId`), `WORKFLOW_SKIP`.
   - `TRANSITION_MAKE`: what did fire, in order. `STATE_MACHINE_FINISH` `data.stopReason` says why the run stopped.
   - Scheduled transitions: the `SCHEDULED_TRANSITION_*` events (`audit` ENDPOINTS, *Event data*). A task that won't run again ends `FAILED` (`SCHEDULED_TRANSITION_FAIL`): `GET '/scheduled-tasks?entityId=<id>'` shows each task's `status`, `failureReason` and `lastError` (`cyoda help scheduled-tasks`). A write in the source state, e.g. a loopback (step 6), arms it afresh (`workflows --section "SCHEDULED TRANSITIONS"`).
5. Evaluate the criterion against the entity's data yourself (`workflows --section CRITERIA`, `search --section "CONDITION DSL"`) and say which field fails.
6. Two common causes:
   - **The data was fixed, but the held transition never ran again.** Automated transitions are evaluated only when the entity is written. Best practice *Re-evaluate with a loopback, not by naming an automated transition* (`cyoda-help.sh design`): `PATCH /entity/JSON/{id}` with `{}` (or the corrected fields), `-H 'Content-Type: application/merge-patch+json' -H 'If-Match: *'`. Smoke-tested example: [../build/examples/loopback/](../build/examples/loopback/) (scenario `02-loopback`).
   - **A cycle hit the per-state visit limit** (`workflows --section "ENGINE EXECUTION"`). The fix is a workflow change (see Repair above).
7. When help doesn't settle how the engine features involved combine (e.g. a cascade through several automated transitions), say what it leaves open and ask whether to spike it on a throwaway cyoda-go (in-memory with mock auth, per `cyoda help run`, or the stack in Docker; ports from `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-ports.sh pick` on a temp dir, or `CYODA_PORT_BASE` for a separate range); `cyoda` always loads `~/.config/cyoda/cyoda.env`, so set storage and auth explicitly; send the spike's calls with `curl` to its own HTTP port (`cyoda help run` PORT LAYOUT), since `cyoda-call.sh` always targets the bound instance.

### Path C — a processor, function criterion or compute node

1. Read `grpc --section "TAG ROUTING"` for routing. A processor reaches a member whose tags **overlap** its `calculationNodesTags` (one shared tag is enough); several matches are picked round robin; empty tags match any member of the tenant. Tags are matched as exact, case-sensitive strings.
2. Timeout: `DISPATCH_TIMEOUT` means no answer within `responseTimeoutMs`; `CALLOUT_FAILED` means several tries failed, and its message lists them. Unset or `0` is the server's `CYODA_CALLOUT_RESPONSE_TIMEOUT_MS`, and import refuses a value above `CYODA_CALLOUT_RESPONSE_TIMEOUT_MAX_MS` (defaults in `config grpc --section OPTIONS`). For slow work: raise `responseTimeoutMs` and consider `executionMode: COMMIT_BEFORE_DISPATCH`, whose processor must be idempotent (`workflows --section PROCESSORS`). A processor that got no answer goes to another compute member only when it is declared `idempotent: true`; otherwise the callout fails. Changing either is a workflow change (see Repair above).
3. Eviction: read `grpc --section KEEPALIVE` and `cyoda help config grpc` for `CYODA_KEEPALIVE_INTERVAL` / `CYODA_KEEPALIVE_TIMEOUT` (defaults 10 s / 30 s). A member that stops reading or answering for the timeout is evicted, and its in-flight calls fail with `COMPUTE_MEMBER_DISCONNECTED`.
4. Join failures (`grpc --section ERRORS`, `auth integration --section "STEP 6 — CONNECT A COMPUTE NODE"`): `PermissionDenied` means the stream wasn't opened with the node's own M2M client's `client_credentials` token (an on-behalf-of token, a `cyoda token`, no `ROLE_M2M`; in mock mode `CYODA_IAM_MOCK_KIND` other than `service`) or `joinedLegalEntityId` isn't the token's tenant. `Unauthenticated` on an open stream: the client was deleted or its secret reset.
5. There is no endpoint that lists connected members. The evidence is the 503 code, the server log (raise it with `CYODA_LOG_LEVEL=debug`, or `POST /admin/log-level` from `admin --section ENDPOINTS`), and `cyoda_dispatch_*` / `cyoda_callout_*` metrics on `:9091/metrics` when telemetry is on (`telemetry --section "METRICS ENDPOINT"`).
6. `success: false` from the processor, an answer cyoda can't read (a criteria answer without `matches`, `"success": null`), or returned data that the schema rejects, is `WORKFLOW_FAILED` and rolls back (`workflows --section PROCESSORS`, `grpc --section "COMPUTE MEMBER PROTOCOL"`). An `error` object without `success: false` counts as success. `TRANSACTION_ROLLBACK_ONLY`: a callback write of the node was refused, which fails the operation whatever the node answered.
7. Writing or changing the compute node itself: the `cyoda:compute` skill.
8. When help doesn't settle how dispatch behaves here, say what it leaves open and ask whether to spike it on a throwaway cyoda-go (in-memory with mock auth, per `cyoda help run`, or the stack in Docker; ports from `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-ports.sh pick` on a temp dir, or `CYODA_PORT_BASE` for a separate range, with a stub compute node); `cyoda` always loads `~/.config/cyoda/cyoda.env`, so set storage and auth explicitly; send the spike's calls with `curl` to its own HTTP port (`cyoda help run` PORT LAYOUT), since `cyoda-call.sh` always targets the bound instance.

### Path D — schema and model lifecycle

Read `models --section LIFECYCLE` and `models --section ERRORS`.
- Entities need a LOCKED model, and the workflow must be imported before the first entity. Finishing that is `cyoda:build`'s registration (canonical order).
- Dry-run a payload with `POST /model/validate/{e}/{v}` (`models --section ENDPOINTS`). It answers 200 either way: `.success` is the verdict and `.message` names each rejected field.
- A new field on a locked model needs a `changeLevel` that allows it. A locked model takes no new sample import (`MODEL_ALREADY_LOCKED`) and can't be unlocked while it has entities (`MODEL_HAS_ENTITIES`): a bigger schema change is a new model version (`cyoda:build`).

### Path E — entities in an Errored state

Count them per state, then list them and read each errored entity's audit: `GET '/audit/entity/<id>?eventType=StateMachine'` per id. [examples/queries.md](examples/queries.md) walks through [examples/queries/](examples/queries/) (grouped stats by state, a lifecycle-state search, point-in-time). Pass those files as `--data-binary @"${CLAUDE_PLUGIN_ROOT}/skills/debug/examples/queries/<file>"`. Best practice *Model error states* (`cyoda-help.sh design`): the exit transition's criterion holds the entity until its data is fixed, then a loopback (Path B, step 6) lets it leave.

### Path F — an entity disappeared

`GET /entity/{id}` returns 404 after a delete. The evidence is a `DELETE` entry in `GET /entity/{id}/changes` and in the audit's `EntityChange` events.

Tell the developer: the delete is soft (history kept; `/changes` shows the DELETE; a point-in-time read from before the delete still returns the entity), it **bypassed the workflow** (no transition, criterion or processor ran, so no state records it), and it can't be undone through the API. Best practice *Prefer a ledger to deletion* (`cyoda-help.sh design`).

## Observation

Read `crud --section ENDPOINTS`, `crud --section "POINT-IN-TIME SEMANTICS"` and `audit --section ENDPOINTS`, then combine:

| Question | Call |
|---|---|
| Every version: when and by whom | `GET /entity/{id}/changes`: newest first, one entry per transaction, `changeType` `CREATE`/`UPDATE`/`DELETE`, with `transactionId`, `user` (for whom) and `executedBy` |
| Which transitions, criteria and processors ran | `GET '/audit/entity/{id}?eventType=StateMachine'`. Filters: `severity`, `fromUtcTime`, `toUtcTime`, `transactionId`; `limit` up to 1000; follow `pagination.nextCursor` with `cursor` |
| One transaction's outcome | `GET /audit/entity/{id}/workflow/{transactionId}/finished` |
| The entity at a past time | `GET '/entity/{id}?pointInTime=<RFC 3339>'` (inclusive, at or before `GET /entity/consistency-time`), or `?transactionId=<tx>`; never both |

Leave `eventType=System` out: open-source cyoda-go doesn't emit those events. The audit API has no `level` parameter; filter with `severity` and `eventType`. Present a timeline, newest first: time, change or event, state, transition, transaction, and the reason where there is one. When the question concerns a past moment, read the entity at that time.
