> Temporary — superseded by cyoda help once Cyoda/cyoda-go#684 item L ships.

# Entity and workflow best practices

Fact-checked against v0.8.4. Source bullets come from the CTCC workflow best-practices notes.

### Entities

- **Use tree-shaped JSON.** Nested objects and arrays are first-class in search and criteria (`[*]`, `[n]`). Don't flatten into relational tables. Caveat: grouped-stats `groupBy` and aggregation fields can't use array subscripts, so keep values you'll aggregate on at scalar paths.
- **Compute aggregations; don't maintain them.** Avoid running totals or counter entities: they conflict under snapshot isolation (retryable 409s) and duplicate what queries give you. Use point-in-time reads/searches and the stats API (`cyoda help crud`: counts by state, and grouped queries with group-by, sum/avg/min/max/stdev and `pointInTime`). Move to dedicated aggregate entities only when volumes make indexed queries too slow.
- **Link entities by entity id.** Store the referenced entity's UUID in a field for 1:1, 1:N or N:M relations. This is a convention: there is no referential integrity, no join in search, and deleting a referenced entity isn't blocked.

### Workflows

- **Treat workflows as first-class.** They are the shared language between domain experts and developers. Design them to be readable.
- **Drive processing with automated transitions.** After every write, the engine runs the first matching non-manual, non-disabled, non-scheduled transition in declaration order, repeatedly, inside the write's transaction. A criterion-less automated transition must come last in its state.
- **Use manual transitions for external triggers.** Humans, batch jobs, other systems — and processors acting on *other* entities. A processor calling the transition API on a linked entity is what creates event cascades across the system. Whether that call joins the parent transaction depends on the processor's execution mode and on echoing the transaction token (see `cyoda help workflows` execution modes). The engine doesn't enforce `manual: true`: any non-disabled, non-scheduled transition can be fired by name. "Manual-only" is a convention.
- **Balance the number of states.** Too few gives opaque, monolithic processing; too many is hard to reason about. Hard limits: `CYODA_MAX_STATE_VISITS` (default 10) visits per state per cascade, depth 100.
- **Re-trigger evaluation with a loopback, not by firing an automated transition.** A loopback is an update with no transition name (an empty merge-patch `{}` re-evaluates without changing data; see `cyoda help crud`). It re-runs the automated cascade from the current state, so criteria-gated transitions get another chance. Note that loopbacks re-arm scheduled timers. An explicit manual self-transition is also allowed. Unguarded automated self-loops are rejected at import unless `allowCycles: true`.
- **Build explicit validation cycles.** If a change makes an entity invalid, route it back to a state before the validation step. Automated back-edges need a criterion (or `allowCycles`).
- **Model error states explicitly.** Don't model only the happy path. Insert an explicit `Errored` state in the straight-through path. Any automated exit from it needs a criterion, or the entity leaves it at once; manual exits hold the entity by themselves, and a scheduled escalation is fine. Find entities needing action by querying the state (state counts from the stats API in `cyoda help crud`, or a search in `cyoda help search`). For side effects on entering the state, use an `ASYNC_NEW_TX` processor or a scheduled transition for escalation. *Notifications are coming soon — check `cyoda help` for availability.*
- **Add backward transitions for retries and corrections.** Paths back up the flow handle retries, data corrections and exception resolution.
- **Give a rejection reason when a criterion fails.** Only `function` criteria (compute node) can return one: `reason` on `matches: false`, up to 2 KiB. It surfaces in the `400 WORKFLOW_FAILED` detail for manual transitions and in the durable `TRANSITION_NOT_MATCH_CRITERION` audit event for automated ones. Inline criteria record a generic message, so describe their intent with `criterionAnnotations.description`.
- **Prefer a ledger to deletion.** Treat the store as a verifiable ledger. Delete is soft (history is kept and point-in-time reads still work) but it **bypasses the workflow** — no transition, criterion or processor runs. End lifecycles in terminal states instead.
- **Define precise terminal states.** There's no engine "terminal" flag; a state with no automated transitions is stable. Use several to say how a lifecycle ended: `Completed`, `Cancelled`, `Aborted`, `Replaced`.
