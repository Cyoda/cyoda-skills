# Common Cyoda Workflow Patterns

Reference this file when designing entity workflows. Present relevant patterns during the domain brainstorm. Facts about how the engine runs them come from `cyoda help workflows`, by the section named in each pattern.

## Approval Flow

Entity moves from submitted → under_review → approved/rejected. Manual transitions for review actions. Criteria guard the approval transition (e.g., reviewer must be assigned).

States: `draft` → `submitted` → `under_review` → `approved` | `rejected`
Key transitions: `submit` (manual), `assign` (manual), `approve` (manual + criteria), `reject` (manual)

Facts: `cyoda help workflows` TRANSITIONS and CRITERIA. Closest smoke-tested start: [build/examples/loopback/](../../build/examples/loopback/) (manual submit, criterion-gated approval).

## Scheduled Transition (timeout, expiry, escalation)

After entering a waiting state, the entity moves on by itself after a delay if nothing else has moved it, e.g. `reserved` → `expired` after 15 minutes, or `errored` → `escalated` after 30 minutes.

This is a `schedule` on an automated transition out of the waiting state: a fixed `delayMs`, or a per-entity time from a function. It isn't a processor, and it can't be fired by name. Any write that leaves the entity in the same state re-arms the timer. To retry until a condition holds, use the polling form.

Facts: `cyoda help workflows` SCHEDULED TRANSITIONS (including "One-shot vs. polling"). Smoke-tested start: [build/examples/scheduled/](../../build/examples/scheduled/).

## Auto-Transition Cascade

Entity auto-advances through several states as soon as criteria are met, without manual intervention. Useful for processing pipelines.

States: `received` → `validated` → `enriched` → `ready`
All transitions are automatic with criteria on each.

Safety: cascades are bounded (depth and per-state visits, `CYODA_MAX_STATE_VISITS`). Exceeding a limit aborts and rolls back the write. Unguarded automated cycles are rejected at import unless the workflow allows cycles. Facts: `cyoda help workflows` ENGINE EXECUTION.

## Error State with Retry

The straight-through path has an explicit error state. Its exit transition is held by a criterion, and a backward transition (or a loopback re-evaluation) retries. See the best practices *Model error states explicitly*, *Add backward transitions for retries and corrections* and *Re-trigger evaluation with a loopback, not by firing an automated transition*.

Smoke-tested starts: [build/examples/error-states/](../../build/examples/error-states/) (errored state with a criterion-held retry), [build/examples/loopback/](../../build/examples/loopback/) (an update with no transition name re-evaluates a criterion-gated transition).

## Saga-Style Coordination

Multiple entities coordinate across a process. Each entity manages its own state; a coordinator entity tracks the overall saga state and triggers transitions on participants.

Cyoda has no built-in saga support. Implement it with compute-node processors that create or transition related entities. Whether those calls join the parent transaction depends on the processor's execution mode and on echoing the transaction token. Facts: `cyoda help workflows` PROCESSORS, and the `cyoda:compute` skill for the processor code.

## External Trigger

An outside system (a webhook handler, a batch job, another service) moves an entity by calling the transition API on it. Model the transition as manual. See the best practice *Use manual transitions for external triggers*.

Edge messages (`cyoda help messages`) are a separate store and never fire a transition.
