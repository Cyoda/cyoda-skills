# Entity Lifecycle & State Machine Design Guidelines

Reference this document when reviewing a proposed entity design, or share it with users who want to understand the reasoning behind design decisions.

## Core Summary Principles

- States represent **business meaning**, not process steps.
- Guards represent **decision logic**, not lifecycle changes.
- Async processors represent **deferred computation + continuation**, not states.
- Entities must remain **simple, decomposed, and responsibility-focused**.
- Lifecycle design must avoid **state explosion and technical leakage**.
- Business clarity is more important than process completeness.

---

## 1. Philosophy & Entity Boundaries

- **Business-Driven Definitions** — Define entity lifecycles in business terms, not technical implementation terms.

- **Business Truth Over Process Representation** — Lifecycle states should represent the business status of an entity. Do not model technical workflow execution, retries, queue processing, integrations, or orchestration steps as lifecycle states unless they are meaningful business concepts.

- **Single Responsibility Entities** — Design entities around a single business responsibility. Avoid "super entities" that aggregate multiple unrelated business activities.

- **Responsibility-Oriented Modeling** — If different activities have independent business rules, ownership, reporting requirements, or lifecycles, model them as separate entities.

- **Behavior-Altering States** — Every state must represent a distinct business condition. Entering a state should have observable business consequences, such as changing allowed actions, validation requirements, permissions, reporting interpretation, or business behavior.

- **Orthogonal Lifecycles** — Use separate entities or separate lifecycle dimensions when independent business concerns exist. Avoid combining unrelated concerns into a single lifecycle.

- **Strict Attribute Separation** — Lifecycle state should represent progression through a business process. Do not encode independent business dimensions such as ownership, assignment, priority, visibility, categorization, payment tracking, or SLA monitoring as lifecycle states. Model these as separate attributes, supporting entities, or independent lifecycles to avoid state explosion and preserve clear lifecycle semantics.

- **Value-Driven States** — Prefer fewer meaningful states over many low-value intermediate states. Every state should have clear business value and purpose.

- **State Classification Awareness** — Distinguish active, waiting, suspended, completed, cancelled, rejected, expired, and archived conditions only when they represent genuinely different business meanings.

---

## 2. Structural & Graph Integrity

- **Boundary States** — Every lifecycle must have exactly one initial state. Lifecycles may have one or more terminal states.

- **State Exclusivity** — States must be mutually exclusive and unambiguous.

- **Reachability** — Every state should be reachable through a valid lifecycle path.

- **Terminal Accessibility** — Every non-terminal state should have at least one valid path to a business outcome.

- **Graph Validation** — Validate lifecycle graphs for: unreachable states, accidental dead ends, invalid loops, missing completion paths.

- **Intentional Loops** — Cycles and return paths should be intentional and explicitly documented.

---

## 3. State Definitions & Data Invariants

- **State Definitions** — Every state must have a documented business definition.

- **Entry Criteria** — Define explicit criteria required before entering a state.

- **Exit Criteria** — Define explicit conditions under which a state may be exited.

- **Persisted vs Derived State** — Persist lifecycle state only when it represents a business decision, milestone, or historical fact. Do not persist statuses that can be deterministically derived from existing data.

- **Conditional Guards** — Prefer transition guards over creating additional states for minor business variations.

- **Semantic Distinctions** — Model rejection, cancellation, expiration, suspension, archival, and similar concepts as separate states only when they imply different business behavior, reporting, or rules.

---

## 4. Transition & Event Modeling

- **Verb-Based Events** — Transitions should be triggered by explicit business events.

- **State-Oriented Naming** — States represent conditions. Events represent actions.

- **No Generic State Changes** — Avoid generic "Change State" operations. Every transition should have explicit business meaning.

- **Multiple Transitions from a Single State** — Multiple transitions may originate from the same state. Transition selection may be based on entity data or externalized condition evaluation. Conditions should ideally be mutually exclusive. If multiple transitions may match simultaneously, the first one will win.

- **Avoid Overlapping Guards** — Guard conditions should ideally be mutually exclusive. If multiple transitions may match simultaneously, precedence rules must be clearly documented.

- **Prefer Guards Over State Proliferation** — Use transition conditions when business variations do not represent distinct business states. If the business difference is about how something happens, use a transition condition (guard). If the business difference is about what the entity is, use a new state.

- **Explicit Reopening** — Returning from terminal states should occur only through explicitly defined transitions.

---

## 5. Async Processing, External Execution & State Continuation

- **No Technical States for Processing** — It is not recommended to model execution states such as: processing, calling external system, retry, queue waiting.

- **Async Processors (Core Platform Concept)** — A transition may trigger a fully asynchronous processor. The processor may complete later, return a result, or resume/restart the state machine with new input. Use it only when necessary. If an async processor fails, the entity remains in the state reached before execution — lifecycle design must account for this explicitly.

- **Async Processor is NOT a State** — It is externalized business computation. It does not define lifecycle position.

- **Failure Recovery Must Be Modelled** — Designers must define: retry paths, compensation actions, alternative transitions, and manual intervention paths.

- **Do Not Assume Completion** — Async processors are not guaranteed to succeed.

- **Async Continuation Rule** — When a fully async processor completes, it may re-enter or continue the state machine as a new lifecycle event.

- **Timeout Awareness** — Async processors must consider timeout behavior explicitly.

---

## 6. Parallel Activities & Business Progress

- **Parallel Execution** — Parallel activities may be designed externally; there are no parallel transitions in the state machine.

- **Do Not Encode Parallelism in States** — Avoid combinatorial states such as: `WaitingForAAndB`, `WaitingForAOnly`, `WaitingForBOnly`.

- **Track Progress Separately** — Use supporting structures or sub-entities.

- **Explicit Join Conditions** — If you run parallel execution using sub-entities, you can add a scheduled loop and condition that checks for all tasks to complete — for example, by checking flags on the entity level or by calling an externalized processor.

---

## 7. Lifecycle Evolution & Complexity Control

- **Stable State Semantics** — State meaning must remain stable over time.

- **Additive Evolution** — Prefer adding new states or transitions over redefining existing ones.

- **Lifecycle Review Required** — Major lifecycle changes require domain review.

- **Complexity Control** — If a lifecycle becomes difficult to understand, reconsider entity boundaries.

- **State Explosion Prevention** — Avoid encoding unrelated dimensions as states.

- **Prefer Composition** — Multiple simple lifecycles are preferred over one complex lifecycle. It is possible to define multiple conditional workflows for the same entity type.
