---
name: debug
description: Use when a cyoda-go call returns an error code, a transition doesn't fire or fails, an entity is stuck or in an unexpected state or has disappeared, a processor, criterion or compute node fails or times out, the instance seems unreachable, or the developer asks for an entity's history, audit trail or state at a past time.
allowed-tools: Bash(*cyoda-call.sh *) Bash(*cyoda-help.sh *) Bash(*cyoda-status.sh*) Bash(jq *) Bash(cat *)
---

# Cyoda debugging and observation

Find out why something happened, from the instance's own records, then explain it with the help section that covers it. Two modes: **debugging** (something failed or looks wrong) and **observation** (what happened to an entity, and when). If the request doesn't say which, ask.

**Facts come from `cyoda help`, not from this file.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` (stderr shows `SOURCE=instance|binary|web`). Exit 2: unknown topic; exit 6: unknown section (stderr lists the sections). Name the section you used.

**Every API call** goes through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh <METHOD> <PATH> [curl args...]`. PATH is relative to `<endpoint>/api`. The body goes to stdout and `HTTP_STATUS=<code>` to stderr. Never build a URL or auth header yourself.

| Exit | Meaning | What you do |
|---|---|---|
| 0 | 2xx | continue |
| 22 | HTTP ≥ 400, or `HTTP_STATUS=000` | `000` means curl never got a response (bad `@file` path, connection refused): fix the call, it isn't server evidence. 401/403: the script already retried once with a fresh token. Show the error and say "next, type `/cyoda:auth`". Otherwise the error is evidence: read it (Path A) |
| 3 | production refusal (any non-GET) | search and stats POSTs are reads: say so, ask "Run this read-only query on production? (yes/no)", and only on yes re-run with `--confirm-production` |
| 4 | the profile's tokenCommand failed | show stderr and say "next, type `/cyoda:auth`" |
| 5 | no endpoint configured | "next, type `/cyoda:setup`" |

**Read-only by default.** Diagnose with GETs and query POSTs. A fix that changes the instance is handed off or confirmed:
- A model or workflow change (new state, criterion, transition, changeLevel, new model version): "Next, type `/cyoda:build` to make this change: <one line>."
- A change to one entity (a loopback to re-evaluate, firing a transition, a delete): show the exact call and ask "Apply this to `<id>`? (yes/no)". Run it only after an explicit yes; on production, add `--confirm-production` only after that yes.

## Step 0 — Connection

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. Show its status line and every `WARN=` line.
- `STATUS=not_configured`: "next, type `/cyoda:setup`". Stop.
- `STATUS=unreachable`: the endpoint didn't answer. Read `run --section "HEALTH PROBES"`: the API port serves `GET /api/health` (`{"status":"UP"}`, or 503 `DOWN` after a recovered panic, latched until the node is replaced); `/livez` and `/readyz` are only on the admin listener (`127.0.0.1:9091` by default), and `cyoda health` checks the local one. Ask whether the server is running and the profile's endpoint is right; switching profiles is "next, type `/cyoda:setup`".
- `ENV=production`: say so up front.

## Debugging

Ask for what's missing, one item at a time: the entity id, the model name and version, the transition, and the exact error body if the developer has it.

### Path A — a call returned an error

1. Read `.properties.errorCode` and `.detail` from the body (RFC 9457 problem JSON; `errors --section DESCRIPTION`).
2. Run `cyoda-help.sh errors <errorCode>`. Every code has its own page; `errors` ERROR CODE INDEX is incomplete (cyoda-go#684 item N), so a code missing from it isn't missing from help.
3. Explain the cause from that page plus the `detail`, then take the matching path:

| errorCode | Look at |
|---|---|
| `WORKFLOW_FAILED` (400) | Path B. A `detail` of `transition "<t>" criterion not matched: <reason>` is a criterion; `processor X failed` is Path C |
| `TRANSITION_NOT_FOUND` | `GET /entity/{id}/transitions`: the name isn't available from the current state |
| `MODEL_NOT_FOUND` (404), `MODEL_NOT_LOCKED` (409) | Path D: the model lifecycle wasn't completed |
| `VALIDATION_FAILED`, `INCOMPATIBLE_TYPE` (400) | Path D: the payload doesn't fit the locked schema |
| `NO_COMPUTE_MEMBER_FOR_TAG`, `COMPUTE_MEMBER_DISCONNECTED`, `DISPATCH_TIMEOUT` (503) | Path C |
| `ENTITY_MODIFIED` (412), `PRECONDITION_REQUIRED` (428), `CONFLICT` (409, retryable) | `crud --section "OPTIMISTIC CONCURRENCY"`: stale or missing `If-Match` |
| `BAD_REQUEST` on `PUT /entity/JSON/{id}/{t}` with no body | An empty PUT is a 400 (#684-C). Fire it with PATCH `{}`, `If-Match: *`, `application/merge-patch+json` (`crud --section ENDPOINTS`) |

### Path B — a transition didn't fire, or the entity is in the wrong state

1. `GET /entity/{id}`: `.meta.state` and `.meta.transactionId`.
2. `GET /model/{e}/{v}/workflow/export`: does the current state declare the transition? Is it `manual`, `disabled`, or `schedule`d? Read `workflows --section TRANSITIONS`.
3. `GET /entity/{id}/transitions`: what can fire now. This read can itself fail with `WORKFLOW_FAILED` when the selected workflow doesn't declare the current state, or when a selection criterion can't be evaluated (`errors WORKFLOW_FAILED`).
4. `GET '/audit/entity/{id}?eventType=StateMachine&limit=100'` (help: `audit --section ENDPOINTS`). Newest first. Look for:
   - `TRANSITION_NOT_MATCH_CRITERION`: `data.transition` was held by its criterion; `data.reason` says why (specific only for function criteria).
   - `TRANSITION_ABORTED` (`data.reason`, expected vs actual tx), `WORKFLOW_SKIP`, `WORKFLOW_NOT_FOUND`.
   - `TRANSITION_MAKE`: what did fire, in order.
   - Scheduled transitions: the `SCHEDULED_TRANSITION_*` events. The `audit` list omits them (#684-F); read `workflows --section "SCHEDULED TRANSITIONS"`.
5. Evaluate the criterion against the entity's data yourself (`workflows --section CRITERIA`, `search --section "CONDITION DSL"`) and say which field fails.
6. Two common causes, from the best practices (`cyoda-help.sh workflows best-practices`, else `${CLAUDE_PLUGIN_ROOT}/skills/design/resources/best-practices.md`):
   - **The data was fixed, but the held transition never ran again.** Automated transitions are evaluated only when the entity is written. Re-trigger with a loopback, not by firing the automated transition: `PATCH /entity/JSON/{id}` with `{}` (or the corrected fields), `-H 'Content-Type: application/merge-patch+json' -H 'If-Match: *'`. Smoke-tested example: [../build/examples/loopback/](../build/examples/loopback/) (scenario `02-loopback`). It's an instance change: ask first.
   - **A cycle hit the per-state visit limit** (`workflows --section "ENGINE EXECUTION"`). The fix is a workflow change: "next, type `/cyoda:build`".

### Path C — a processor, function criterion or compute node

1. Read `grpc --section "TAG ROUTING"` for routing. A processor reaches a member whose tags **overlap** its `calculationNodesTags` (one shared tag is enough); several matches are picked at random; empty tags match any member of the tenant. `workflows` PROCESSORS says "all required tags"; that's wrong (#684-B). Tags are matched as exact, case-sensitive strings.
2. Timeout: `DISPATCH_TIMEOUT` means no answer within `responseTimeoutMs`. Unset or `0` is the server default of 30 s, not a node default (#684-J). For slow work: raise `responseTimeoutMs` and consider `executionMode: COMMIT_BEFORE_DISPATCH`, whose processor must be idempotent (`workflows --section PROCESSORS`). Changing either is a workflow change: "next, type `/cyoda:build`".
3. Eviction: read `grpc --section KEEPALIVE` and `cyoda help config grpc` for `CYODA_KEEPALIVE_INTERVAL` / `CYODA_KEEPALIVE_TIMEOUT` (defaults 10 s / 30 s). A member that stops reading or answering for the timeout is evicted, and its in-flight calls fail with `COMPUTE_MEMBER_DISCONNECTED`.
4. Join failures (`grpc --section ERRORS`): `PermissionDenied` means the token lacks `ROLE_M2M` or the tenant doesn't match `joinedLegalEntityId`.
5. There is no endpoint that lists connected members. The evidence is the 503 code, the server log (raise it with `CYODA_LOG_LEVEL=debug`, or `POST /admin/log-level` from `admin --section ENDPOINTS`: an instance change, so ask), and `cyoda_dispatch_*` metrics on `:9091/metrics` when telemetry is on (`telemetry --section "METRICS ENDPOINT"`).
6. `success: false` from the processor, or returned data that the schema rejects, is `WORKFLOW_FAILED` and rolls back (`workflows --section PROCESSORS`).
7. Writing or changing the compute node itself: the `cyoda:compute` skill.

### Path D — schema and model lifecycle

Read `models --section LIFECYCLE` and `models --section ERRORS`.
- Entities need a LOCKED model, and the workflow must be imported before the first entity. Finishing that is "next, type `/cyoda:build`".
- Dry-run a payload with `POST /model/validate/{e}/{v}` (`models --section ENDPOINTS`). It answers 200 either way: `.success` is the verdict and `.message` names each rejected field.
- A new field on a locked model needs a `changeLevel` that allows it. A locked model takes no new sample import (`MODEL_ALREADY_LOCKED`) and can't be unlocked while it has entities (`MODEL_HAS_ENTITIES`): a bigger schema change is a new model version, via `/cyoda:build`.

### Path E — entities in an Errored state

Count them per state, then list them and read each one's reason: [examples/queries.md](examples/queries.md) walks through [examples/queries/](examples/queries/) (grouped stats by state, a lifecycle-state search, point-in-time). Pass those files as `--data-binary @"${CLAUDE_PLUGIN_ROOT}/skills/debug/examples/queries/<file>"`. Best practice *Model error states explicitly*: the exit transition's criterion holds the entity until its data is fixed, then a loopback (Path B, step 6) lets it leave.

### Path F — an entity disappeared

`GET /entity/{id}` returns 404 after a delete. The evidence is a `DELETE` entry in `GET /entity/{id}/changes` and in the audit's `EntityChange` events.

Tell the developer: the delete is soft (history kept; `/changes` shows the DELETE; a point-in-time read from before the delete still returns the entity, so the data is recoverable by reading it there), it **bypassed the workflow** (no transition, criterion or processor ran, so no state records it), and it can't be undone through the API, so recreating is their call. Best practice *Prefer a ledger to deletion*: end lifecycles in terminal states.

## Observation

Read `crud --section ENDPOINTS`, `crud --section "POINT-IN-TIME SEMANTICS"` and `audit --section ENDPOINTS`, then combine:

| Question | Call |
|---|---|
| Every version: when and by whom | `GET /entity/{id}/changes`: newest first, `changeType` `CREATE`/`UPDATE`/`DELETE`, with `transactionId` |
| Which transitions, criteria and processors ran | `GET '/audit/entity/{id}?eventType=StateMachine'`. Filters: `severity`, `fromUtcTime`, `toUtcTime`, `transactionId`; `limit` up to 1000; follow `pagination.nextCursor` with `cursor` |
| One transaction's outcome | `GET /audit/entity/{id}/workflow/{transactionId}/finished` |
| The entity at a past time | `GET '/entity/{id}?pointInTime=<RFC 3339>'` (inclusive), or `?transactionId=<tx>`; never both |

Leave `eventType=System` out: open-source cyoda-go doesn't emit those events. Present a timeline, newest first: time, change or event, state, transition, transaction, and the reason where there is one. Then offer a point-in-time read at any moment of interest.

## Common mistakes

| Mistake | Instead |
|---|---|
| Generic advice before reading the entity, workflow and audit | Steps 1-4 of Path B first |
| "The node must declare all the tags" | Overlap, per `grpc` TAG ROUTING (#684-B) |
| A 60-second timeout | `responseTimeoutMs`, default 30 s (#684-J) |
| Probing `/readyz` on the API port | `GET /api/health`; `/readyz` is on the admin port |
| Re-firing the automated transition to retry | A loopback, after the developer's yes |
| Changing the workflow or model from here | "Next, type `/cyoda:build`" |
| `?level=DEBUG` on the audit API | No such parameter; filter with `severity` and `eventType` |
| A Cloud or migration question | Reply only "That's not covered by this plugin." Don't name or describe the product or offer alternatives for it |
