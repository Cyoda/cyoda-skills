# Entity Lifecycle & State Machine Design Guidelines

General lifecycle-modelling judgment for reviewing a proposed entity design and explaining the reasoning behind a design decision. Where it names a `cyoda help` section, the agent reads that section and gives the developer the result.

Read it together with the shared best practices (`cyoda help workflows best-practices` or `cyoda help design` once Cyoda/cyoda-go#684 item L ships; until then [best-practices.md](best-practices.md)). Those bullets are the Cyoda-specific, fact-checked rules. Where a topic is covered there, this file points at the bullet by name instead of repeating it.

## Core Summary Principles

- States represent **business meaning**, not process steps.
- Guards represent **decision logic**, not lifecycle changes.
- Processors represent **computation attached to a transition**, not states.
- Entities must remain **simple, decomposed, and responsibility-focused**.
- Lifecycle design must avoid **state explosion and technical leakage**.
- Business clarity is more important than process completeness.

---

## 1. Philosophy & Entity Boundaries

- **Business-Driven Definitions** — Define entity lifecycles in business terms, not technical implementation terms.

- **Business Truth Over Process Representation** — Lifecycle states should represent the business status of an entity. Do not model technical workflow execution, retries, queue processing, integrations, or orchestration steps as lifecycle states unless they are meaningful business concepts.

- **Single Responsibility Entities** — Design entities around a single business responsibility. Avoid "super entities" that aggregate multiple unrelated business activities.

- **Responsibility-Oriented Modeling** — If different activities have independent business rules, ownership, reporting requirements, or lifecycles, model them as separate entities. Link them as in the best practice *Link entities by entity id*.

- **Behavior-Altering States** — Every state must represent a distinct business condition. Entering a state should have observable business consequences, such as changing allowed actions, validation requirements, permissions, reporting interpretation, or business behavior.

- **Orthogonal Lifecycles** — When independent business concerns exist, give each its own entity. An entity runs exactly one workflow at a time (see §7), so two concerns can't be two parallel state machines on one entity.

- **Strict Attribute Separation** — Lifecycle state should represent progression through a business process. Do not encode independent business dimensions such as ownership, assignment, priority, visibility, categorization, payment tracking, or SLA monitoring as lifecycle states. Model these as attributes, or as supporting entities with their own lifecycle, to avoid state explosion and preserve clear lifecycle semantics.

- **Value-Driven States** — Prefer fewer meaningful states over many low-value intermediate states. Every state should have clear business value and purpose. For the limits on cascades, see the best practice *Balance the number of states*.

- **State Classification Awareness** — Distinguish active, waiting, suspended, completed, cancelled, rejected, expired, and archived conditions only when they represent genuinely different business meanings.

---

## 2. Structural & Graph Integrity

- **Boundary States** — Every lifecycle has exactly one initial state. For end states, see the best practice *Define precise terminal states*.

- **State Exclusivity** — States must be mutually exclusive and unambiguous.

- **Reachability** — Every state should be reachable through a valid lifecycle path.

- **Terminal Accessibility** — Every non-terminal state should have at least one valid path to a business outcome.

- **Graph Validation** — Validate lifecycle graphs for unreachable states, accidental dead ends, invalid loops, and missing completion paths.

- **Intentional Loops** — Cycles and return paths should be intentional and documented. For how the engine treats them, see the best practices *Build explicit validation cycles* and *Re-trigger evaluation with a loopback, not by firing an automated transition*.

---

## 3. State Definitions & Data Invariants

- **State Definitions** — Every state must have a documented business definition.

- **Entry Criteria** — Define explicit criteria required before entering a state.

- **Exit Criteria** — Define explicit conditions under which a state may be exited.

- **Persisted vs Derived State** — Persist lifecycle state only when it represents a business decision, milestone, or historical fact. Do not persist statuses that can be deterministically derived from existing data. For totals and counts, see the best practice *Compute aggregations; don't maintain them*.

- **Conditional Guards** — Prefer transition guards over creating additional states for minor business variations.

- **Semantic Distinctions** — Model rejection, cancellation, expiration, suspension, archival, and similar concepts as separate states only when they imply different business behavior, reporting, or rules.

---

## 4. Transition & Event Modeling

- **Verb-Based Events** — Transitions should be triggered by explicit business events.

- **State-Oriented Naming** — States represent conditions. Events represent actions.

- **No Generic State Changes** — Avoid generic "Change State" operations. Every transition should have explicit business meaning.

- **Multiple Transitions from a Single State** — Several transitions may leave the same state, selected on entity data or by an externalized (function) criterion. How the engine picks among automated ones is in the best practice *Drive processing with automated transitions*; who fires the others is in *Use manual transitions for external triggers*.

- **Avoid Overlapping Guards** — Guard conditions should be mutually exclusive. If they can't be, the declaration order decides, so document why the order matters.

- **Prefer Guards Over State Proliferation** — Use transition conditions when business variations do not represent distinct business states. If the business difference is about how something happens, use a transition condition (guard). If the business difference is about what the entity is, use a new state.

- **Explicit Reopening** — Returning from terminal states should occur only through explicitly defined transitions.

---

## 5. Processors, Async Work & Failure

- **No Technical States for Processing** — Do not model execution states such as processing, calling an external system, retrying, or waiting in a queue.

- **A Processor Is NOT a State** — It is externalized business computation attached to a transition. It does not define lifecycle position.

- **Design for the Execution Mode** — What a failed processor does to the lifecycle depends on its `executionMode`: for example an `ASYNC_NEW_TX` failure still completes the transition (its returned data is discarded), while a `SYNC` failure rolls the whole write back. Pick the mode deliberately; each mode's failure behaviour is in `cyoda help workflows` PROCESSORS. Don't assume a processor succeeds.

- **Model the Failure Path** — See the best practices *Model error states explicitly* and *Add backward transitions for retries and corrections*.

- **Continuing Later** — A processor does not pause the state machine and resume it. Work that finishes later continues the lifecycle by firing a transition on the entity, as in the best practice *Use manual transitions for external triggers*.

- **Timeout Awareness** — Processor and function-criterion calls time out (30 s by default, overridable per processor). For slow external work, read the `COMMIT_BEFORE_DISPATCH` mode in `cyoda help workflows` PROCESSORS.

---

## 6. Parallel Activities & Business Progress

- **Parallel Execution** — Parallel activities are designed across entities; there are no parallel transitions within a state machine.

- **Do Not Encode Parallelism in States** — Avoid combinatorial states such as: `WaitingForAAndB`, `WaitingForAOnly`, `WaitingForBOnly`.

- **Track Progress Separately** — Use supporting structures or sub-entities, linked by entity id.

- **Explicit Join Conditions** — With parallel sub-entities, join on the parent by either (a) a processor on each sub-entity's final transition firing a transition on the parent, whose criterion checks that all are done, or (b) a polling scheduled transition on the parent that re-checks the condition. For (b), the facts are in `cyoda help workflows` SCHEDULED TRANSITIONS ("One-shot vs. polling").

---

## 7. Lifecycle Evolution & Complexity Control

- **Stable State Semantics** — State meaning must remain stable over time.

- **Additive Evolution** — Prefer adding new states or transitions over redefining existing ones.

- **Lifecycle Review Required** — Major lifecycle changes require domain review.

- **Complexity Control** — If a lifecycle becomes difficult to understand, reconsider entity boundaries.

- **State Explosion Prevention** — Avoid encoding unrelated dimensions as states.

- **Prefer Composition** — Several simple lifecycles on separate entities beat one complex lifecycle. One entity type may have several conditional workflows, but they are alternatives: each call runs the first active workflow whose criterion matches. Selection is re-evaluated on every call, so select on fields that don't change, or an edit can re-bind the entity to another workflow and strand its state. Facts: `cyoda help workflows` CRITERIA (workflow-level selection).
