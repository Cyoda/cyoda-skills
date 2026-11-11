# Entity Lifecycle Design Guidelines

Lifecycle judgment that the best practices (`cyoda help workflows best-practices`, `cyoda help design`, or [best-practices.md](best-practices.md) until Cyoda/cyoda-go#684 item L ships) and the anti-patterns in SKILL.md don't cover. Where it names a `cyoda help` section, read that section and give the developer the result.

## States and Guards

- **State or guard** — If the difference is about what the entity is, add a state. If it's about how something happens, put a criterion (guard) on the transition.
- **Persisted vs derived** — Persist a state only when it records a business decision, milestone or fact. A status that can be derived from the entity's data is a query, not a state.

## Processors, Async Work & Failure

- **Continuing later** — A processor doesn't pause the state machine and resume it. Work that finishes later continues the lifecycle by firing a transition on the entity (best practice *Use manual transitions for external triggers*).

## Parallel Activities

- One state machine has no parallel transitions. Parallel work is sub-entities linked to the parent by entity id.
- **Join** on the parent by either (a) a processor on each sub-entity's final transition firing a transition on the parent whose body records that sub-entity as done, with the parent's criterion reading only the parent's own record (best practice *Pass the anchor's facts down the cascade*), or (b) a poll on the parent (best practice *Poll for a condition that can become true without a write*).
