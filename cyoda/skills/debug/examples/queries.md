# Queries: which entities are where, and what was true when

A walkthrough of the payloads in [queries/](queries/). Smoke scenario `05-queries` posts exactly these two files against v0.8.4, so they're known to work. Endpoint facts: `cyoda help crud` ENDPOINTS (statistics) and `cyoda help search` ENDPOINTS and CONDITION DSL. Each call goes through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh`.

These are reads, but search and grouped statistics are POSTs. On a `production` profile the call script refuses them (exit 3) until the developer says yes; then re-run with `--confirm-production`.

## How many entities are in each state

[queries/stats-group-by-state.json](queries/stats-group-by-state.json) is `{"groupBy": ["state"]}`.

```
cyoda-call.sh POST /entity/stats/{e}/{v}/query -H 'Content-Type: application/json' --data-binary @queries/stats-group-by-state.json
```

The response is one bucket per state: `[{"groupKey":[{"path":"state","value":"errored"}],"count":1}, ...]`. Use it first when the developer asks "how many are stuck?" or "how many errored?".

Variations (shapes in `crud` ENDPOINTS, grouped statistics):
- Add a data field to `groupBy`, e.g. `["state", "$.region"]`. Group keys must be scalar paths, no array subscripts.
- Add `aggregations`, e.g. `[{"op": "sum", "field": "$.amount"}]`.
- Add `pointInTime` (RFC 3339) to get the counts as they were then.

For a count of one or a few states only, no body is needed: `cyoda-call.sh GET '/entity/stats/states/{e}/{v}?states=errored'`.

## Which entities are in the Errored state

Grouped stats give counts, not ids. To list the entities, search with a lifecycle condition (`search` CONDITION DSL, LifecycleCondition). Write it to a temp file and post it:

```json
{ "type": "lifecycle", "field": "state", "operatorType": "EQUALS", "value": "errored" }
```

```
cyoda-call.sh POST /search/direct/{e}/{v} -H 'Content-Type: application/json' --data-binary @<file>
```

The response is NDJSON: one entity envelope per line. Read `.meta.id`, `.meta.state` and `.meta.lastUpdateTime` from each. State names are as the workflow spells them (`errored`, `Errored`, ...): check the workflow export first. Direct search is bounded: `limit` defaults to 1000 and above the cap it fails with `SEARCH_RESULT_LIMIT` rather than truncating (`search` ENDPOINTS). For larger sets, use the async search jobs in the same section.

Then, for each errored entity, read why: `GET /audit/entity/{id}?eventType=StateMachine` and look for `TRANSITION_NOT_MATCH_CRITERION` (its `data.transition` and `data.reason`). With an inline criterion the reason is the generic `criterion did not match`; only a function criterion gives a specific reason.

## What matched at an earlier time

[queries/search-point-in-time.json](queries/search-point-in-time.json) is a simple condition, `$.amount GREATER_THAN 0`. Post it twice:

```
cyoda-call.sh POST /search/direct/{e}/{v} ... --data-binary @queries/search-point-in-time.json
cyoda-call.sh POST '/search/direct/{e}/{v}?pointInTime=2026-10-17T09:00:00.000Z' ... --data-binary @queries/search-point-in-time.json
```

The first counts what matches now, the second what matched at that instant. The bound is inclusive (`crud` POINT-IN-TIME SEMANTICS). In scenario 05, five entities match now and three at the earlier instant. The same `pointInTime` parameter works on `GET /entity/{id}`, `/changes`, `/transitions`, entity lists, and the grouped statistics body.

A soft-deleted entity drops out of a current search but is still returned by a point-in-time search from before the delete.

## Re-checking a stuck entity after a data fix

Once an errored entity's data is corrected, its held transition gets another chance only when the cascade runs again. A loopback (an update without a transition name) does that; [../../build/examples/loopback/](../../build/examples/loopback/) is the smoke-tested example (scenario `02-loopback`). This changes the instance, so the debug skill does it only after the developer's explicit yes.
