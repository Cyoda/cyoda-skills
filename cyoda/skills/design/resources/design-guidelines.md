# Entity Lifecycle Design Guidelines

Lifecycle judgment that the best practices (`cyoda help workflows best-practices`, `cyoda help design`, or [best-practices.md](best-practices.md) until Cyoda/cyoda-go#684 item L ships) and the anti-patterns in SKILL.md don't cover. Where it names a `cyoda help` section, read that section and give the developer the result.

## States and Guards

- **State or guard** — If the difference is about what the entity is, add a state. If it's about how something happens, put a criterion (guard) on the transition.
- **Graph integrity** — Exactly one initial state; states mutually exclusive; every state reachable from the initial state; every cycle intentional.
- **Persisted vs derived** — Persist a state only when it records a business decision, milestone or fact. A status that can be derived from the entity's data is a query, not a state.

## Processors, Async Work & Failure

- **A processor is not a state** — It is computation attached to a transition and doesn't mark a lifecycle position.
- **Design for the execution mode** — What a failed processor does to the lifecycle depends on its `executionMode`: an `ASYNC_NEW_TX` failure still completes the transition (its returned data is discarded), a `SYNC` failure rolls the whole write back. Each mode's failure behaviour is in `cyoda help workflows` PROCESSORS.
- **Continuing later** — A processor doesn't pause the state machine and resume it. Work that finishes later continues the lifecycle by firing a transition on the entity (best practice *Use manual transitions for external triggers*).
- **Timeouts** — Processor and function-criterion calls time out. For slow external work, read the `COMMIT_BEFORE_DISPATCH` mode in `cyoda help workflows` PROCESSORS.

## Parallel Activities

- One state machine has no parallel transitions. Parallel work is sub-entities linked to the parent by entity id.
- **Join** on the parent by either (a) a processor on each sub-entity's final transition firing a transition on the parent, whose criterion checks that all are done, or (b) a polling scheduled transition on the parent that re-checks the condition (`cyoda help workflows` SCHEDULED TRANSITIONS, "One-shot vs. polling").

## Workflow Selection

One entity type may have several conditional workflows, but they are alternatives: each call runs the first active workflow whose criterion matches. Selection is re-evaluated on every call, so select on fields that don't change, or an edit can re-bind the entity to another workflow and strand its state. Facts: `cyoda help workflows` CRITERIA (workflow-level selection).
