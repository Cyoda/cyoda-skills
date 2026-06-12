# Design Review Phase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Phase 3 Design Review to `cyoda:design` that applies an anti-pattern checklist before presenting the output summary, flagging and correcting issues inline.

**Architecture:** Single file edit to `SKILL.md` — insert Phase 3 (Design Review with anti-pattern checklist) between the existing Phase 2 (Domain Brainstorm) and rename the current Phase 3 (Output Design Summary) to Phase 4. Resource file `design-guidelines.md` and updated evals are already in place.

**Tech Stack:** Markdown skill file

---

### Task 1: Add Phase 3 — Design Review to SKILL.md

**Files:**
- Modify: `cyoda/skills/design/SKILL.md:43-63`

- [ ] **Step 1: Rename current Phase 3 heading to Phase 4**

In `cyoda/skills/design/SKILL.md`, change line 43:

```
### Phase 3 — Output Design Summary
```

to:

```
### Phase 4 — Output Design Summary
```

- [ ] **Step 2: Insert Phase 3 — Design Review before Phase 4**

Insert the following block immediately before the `### Phase 4 — Output Design Summary` heading:

```markdown
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

```

- [ ] **Step 3: Add guidelines reference to Phase 4 output**

At the end of `SKILL.md`, after the `Offer to proceed` line, add:

```markdown

For users who want to understand the reasoning behind design decisions, share [Entity Lifecycle & State Machine Design Guidelines](resources/design-guidelines.md).
```

- [ ] **Step 4: Verify SKILL.md line count stays under 500**

Run:
```bash
wc -l cyoda/skills/design/SKILL.md
```
Expected: under 500 lines

- [ ] **Step 5: Commit**

```bash
git add cyoda/skills/design/SKILL.md
git commit -m "feat(design): add Phase 3 design review with anti-pattern checklist"
```
