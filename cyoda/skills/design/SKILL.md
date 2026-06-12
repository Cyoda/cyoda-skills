---
name: design
description: Brainstorm and design a Cyoda application. Guides entity modeling, workflow design, and compute node decisions following Cyoda philosophy. Auto-invoked when the user describes an app idea or asks how to model their domain in Cyoda.
when_to_use: When the user describes an application they want to build on Cyoda, asks how to model their domain, or needs help designing entities and workflows.
---

## Cyoda Application Design

### Phase 1 — Orientation (skip if user is already familiar with Cyoda)

Assess whether the user needs orientation. **Skip orientation if the user's message contains any of these Cyoda-specific terms:** `entity`, `entities`, `workflow`, `workflows`, `state`, `states`, `transition`, `transitions`, `compute node`, `discover mode`, `lock mode`. If the user already speaks Cyoda — go straight to Phase 2.

If none of those terms appear, give a brief orientation first:

**Orientation (2-3 sentences maximum):**

Cyoda is an Entity Database Management System (EDBMS) — a database where every record is a state machine. Instead of storing rows in tables, you define **entities** — domain objects like Orders or Users — each with a **workflow**: a set of named states and the transitions between them. Nothing in Cyoda is overwritten; every transition produces a new immutable revision, giving you the full history of every entity.

After orientation, ask: *"Does that make sense? Ready to design your app?"*

### Phase 2 — Domain Brainstorm

Ask one question at a time. Wait for the answer before asking the next.

**Q1:** *"What are the main domain objects in your application that have an independent lifecycle — things that change over time on their own clock?"*

For each entity identified, continue:

**Q2:** *"For [entity name]: what states does it move through from creation to completion? (e.g., for an Order: draft → submitted → processing → shipped → delivered)"*

**Q3:** *"For each transition: what triggers it? Manual action by a user, an incoming event/message, a time delay, or automatically when a condition is met?"*

**Q4:** *"Do any transitions need to call external code — to validate data, call a third-party API, or run a calculation? If yes, that's where a compute node comes in. But many apps don't need them at all."*

Present the compute node option neutrally — it is **optional**. Many workflows work purely with Cyoda's built-in criteria and processors.

**Q5:** *"Are you building this as a prototype or targeting production? This determines the schema mode:*
- *Discover mode (prototype): Cyoda infers and evolves the schema automatically as data is posted — no upfront field definitions needed.*
- *Lock mode (production): The schema is fixed. Data that doesn't match is rejected. Use this when the model is stable.*

*You can always start with discover and switch to lock when you're ready to go live. Which fits where you are now?"*

### Phase 3 — Design Review

Before presenting the output summary, apply this checklist to the proposed design (entities, states, transitions gathered through Q1–Q5). For each violation found, fix the design and note the change in one plain-language sentence inline — for example: *"I've removed `processing` — Cyoda models that as an async processor, not a business state."* Then produce the corrected Phase 4 summary. When a deeper explanation is useful, point the user to the guidelines: *"See [Entity Lifecycle & State Machine Design Guidelines](resources/design-guidelines.md) — § Async Processing."*

**Core principles to apply:**
- States represent business meaning, not process steps
- Guards represent decision logic, not lifecycle changes — prefer a guard over a new state when only the path differs, not the business condition
- Async processors represent deferred computation, not states
- Business clarity over process completeness — fewer clear states beat many low-value intermediate ones

**Anti-patterns to catch and fix:**

| Anti-pattern | Signal | Fix |
|---|---|---|
| Technical states | State named `processing`, `calling_*`, `retry`, `queued`, `waiting_for_response` | Remove; model as async processor |
| Orthogonal dimensions as states | Priority, assignment, ownership, visibility, payment status, SLA as lifecycle states | Extract to attributes or sub-entities |
| Orthogonal lifecycles collapsed | Independent business concerns (different rules, ownership, reporting) in one lifecycle | Split into separate entities |
| Combinatorial wait states | `WaitingForAAndB`, `WaitingForAOnly`, etc. | Replace with progress sub-entity or join condition |
| Super entity | Single entity spans multiple independent business activities | Split |
| Low-value states | State with no clear business value | Remove or merge |
| Stateless states | No observable business consequence (no change in allowed actions, validation, permissions, reporting) | Remove or merge |
| State classification overuse | active/waiting/suspended/cancelled/rejected/expired/archived used as distinct states with identical business behavior | Consolidate |
| Dead-end state | Non-terminal state with no valid path to a business outcome | Add a transition or flag for review |
| Generic transitions | Named `changeState`, `update`, `modify`, `process` | Rename with a business verb |
| Async failure unmodelled | Async processor present but no retry/compensation/manual path | Prompt user to define failure handling |

### Phase 4 — Output Design Summary

Present a structured summary:

```
Entities:
  - [EntityName]: states=[...], key transitions=[...]
  - ...

Compute nodes needed: yes/no
  - If yes: which transitions call external code and why

Schema mode: discover (prototype) / lock (production)

Suggested first increment for /cyoda:build: [EntityName] with [minimal workflow]
```

Reference patterns from [patterns.md](resources/patterns.md) when relevant (e.g., if the user describes an approval process, mention the Approval Flow pattern).

Offer to proceed: *"Ready to build this? Run `/cyoda:build` to start registering these models in your running Cyoda instance."*

For users who want to understand the reasoning behind design decisions, share [Entity Lifecycle & State Machine Design Guidelines](resources/design-guidelines.md).
