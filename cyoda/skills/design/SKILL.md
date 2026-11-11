---
name: design
description: Use when the developer describes an application idea for cyoda-go, asks how to model their domain as Cyoda entities and workflows, or wants a proposed entity or workflow design reviewed before building it.
allowed-tools: Bash(*cyoda-help.sh *) Read Bash(cyoda *) Bash(docker *) Bash(kill *) Bash(curl *) Bash(mktemp *) Bash(rm *)
---

# Cyoda application design

Turn an app idea into entities and workflows, review them against the Cyoda best practices, and hand a summary to `/cyoda:build`. This skill writes no project files and calls no project instance.

**Facts come from `cyoda help`, not from this file or from memory.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> [--section "<NAME>"]`. It prints the topic or section body, and stderr line 1 is `SOURCE=instance|binary|web VERSION=<v>`. Exit 2 means unknown topic; exit 6 means unknown section (stderr lists the sections that exist). With no binary installed it falls back to the web help mirror by itself. The mirror ignores `--section` and prints the whole page, so find the section by its heading there. If a topic you know exists still exits 2 (offline), carry on with the design and tell the developer which facts you couldn't check.

**You read help; the developer gets the result.** Before you propose a query or any pattern whose shape depends on the API or the workflow schema (a stats query, a search, a schedule, a criterion), read the named section yourself. Then write the concrete example for the developer's own entity and fields in the shape that section gives, e.g. the grouped stats request for their Order data. Never copy endpoint or field text from best-practices.md or this file, and never tell the developer to go read help. In your reply, name the sections your facts come from.

## Step 0 — Load the best practices

Before Phase 1, load the list Phase 3 reviews against:

1. Run `cyoda-help.sh workflows best-practices`. Exit 0: that text is the list.
2. Exit 2: run `cyoda-help.sh design`. Exit 0: that text is the list.
3. Both exit 2: read [resources/best-practices.md](resources/best-practices.md), the bundled copy kept until Cyoda/cyoda-go#684 item L ships.

Tell the developer in one line which source you used, e.g. "Best practices: bundled copy (the `cyoda help` topic hasn't shipped yet)."

## Phase 1 — Orientation

Skip it if the developer's message contains any of: `entity`, `entities`, `workflow`, `workflows`, `state`, `states`, `transition`, `transitions`, `compute node`, `changeLevel`. Otherwise, orient in 2-3 sentences:

Cyoda is an Entity Database Management System (EDBMS): a database where every record is a state machine. You define **entities** (domain objects like Orders or Users), each with a **workflow**: named states and the transitions between them. Nothing is overwritten; every write produces a new immutable revision, so each entity keeps its full history.

## Phase 2 — Domain brainstorm

**Q1:** *"What are the main things in your app that have their own lifecycle, changing over time on their own clock?"*

For each entity:

**Q2:** *"For [entity]: what states does it move through, from creation to every way it can end? What can go wrong along the way?"* Listen for the error path and for several distinct endings (best practices *Model error states explicitly*, *Define precise terminal states*).

**Q3:** *"What moves it from one state to the next: a person or another system acting, a condition on its data becoming true, or time passing?"* Map the answers:

| Developer says | Model it as | Facts |
|---|---|---|
| A user, a batch job, another system, a webhook arriving | Manual transition, fired through the API by that caller | `workflows --section TRANSITIONS` |
| "When X is true" | Automated transition with a criterion | `workflows --section CRITERIA` |
| "After N minutes", "expires", "escalate if stuck" | Scheduled transition ([patterns.md](resources/patterns.md) § Scheduled Transition) | `workflows --section "SCHEDULED TRANSITIONS"` |
| "When the child/linked entity finishes" | A processor on that entity's transition fires a transition here | best practice *Use manual transitions for external triggers* |

Edge messages (`cyoda help messages`) never fire a transition, so a "message-triggered transition" is a caller firing a manual transition.

**Q4:** *"Do any steps need your own code: calling a third-party API, a calculation, or a check that needs data not on the entity? That's a compute node. Many apps don't need one."* A compute node is also how a criterion returns a rejection reason (best practice *Give a rejection reason when a criterion fails*).

**Q5:** *"Must any field, or combination of fields, be unique across all [entity]s, such as an order number or an email? May a [parent] have only one live [entity] at a time?"* These are unique keys, set before the model is locked (`models --section ENDPOINTS`, unique-keys; best practices *Enforce uniqueness with a unique key, never a criterion*, *"Exactly one live X per Y" is a unique key with a retirement number*).

**Q6:** Read `models --section LIFECYCLE` first. Explain from it: the schema is taken from sample data, and the model is locked before any entity exists. The choice is how much the schema may still grow on writes: none (strict, only the sample's fields), or one of the changeLevel values listed there, from least to most permissive. Ask: *"Do you expect to add fields while you build, and will any processor write fields that aren't in your sample?"* Prototype: a permissive level. It can be changed later.

## Phase 3 — Design review

Check the proposed design against two lists, then fix it:

1. **The Review checklist of the best-practices list from Step 0** (no checklist: its bullets, by bold name). Show one line per checklist line: `- <practice name>: ok | changed: <what> | n/a`.
2. **The anti-patterns below.** List only the ones you found.

For each violation, change the design and say so in one plain sentence that names the practice or anti-pattern, e.g. *"I've removed `processing`: a processor runs on a transition and is not a business state (anti-pattern: technical states)."* Give the reasoning yourself, drawing on the practice and [design-guidelines.md](resources/design-guidelines.md).

**Proposals that map to a best practice:**

| Developer proposes | Best practice | Produce instead (from the section you read) |
|---|---|---|
| A running total, counter or summary entity updated on each write | *Compute aggregations; don't maintain them* | The concrete grouped stats query for their entity, on scalar fields (`crud --section ENDPOINTS`) |
| SQL or reporting queries | *Compute aggregations; don't maintain them* | The concrete stats query or search for their question (`crud` or `search --section ENDPOINTS`). SQL analytics is not available in cyoda-go |
| A `retry` state, or "re-run the check" | *Add backward transitions for retries and corrections*, *Re-trigger evaluation with a loopback, not by firing an automated transition* | A backward transition, or a loopback |
| A criterion that searches for a duplicate; "only one active X per Y" | *Enforce uniqueness with a unique key, never a criterion*, *"Exactly one live X per Y" is a unique key with a retirement number* | The unique key, and for "one live" the retirement-number field and the processor that sets it on entry to each terminal state |
| Kinds or variants of one entity, each with its own lifecycle | *End the list with a catch-all workflow*, *Select on a field that you refuse to change* | One workflow per kind selected on the kind field, then the catch-all workflow (`workflows --section CRITERIA`, workflow-level selection) |
| Who may do what; a limit that needs a more senior role; "cancel" from several states | *Declare who may fire a transition in its annotations*, *Give a transition name one set of permitted roles*, *Declare a general action once per state it is legal from* | `roles` on each transition, one transition name per role set, the general action declared in each state |
| Deleting an entity to end it | *End a lifecycle in a terminal state; never delete* | A terminal state |

**Notifications.** If the developer asks for notifications, alerts, webhooks or subscriptions when an entity enters a state, say: "Notifications are coming soon — check `cyoda help` for availability." Then offer today's options:
1. Find entities needing action by querying the state: give the concrete state-count or search request for their entity (`crud --section ENDPOINTS`, `search --section ENDPOINTS`).
2. An `ASYNC_NEW_TX` processor on the transition into the state, whose compute node sends the message. Show the processor entry (`workflows --section PROCESSORS`).
3. A scheduled transition for escalation, e.g. `errored` → `escalated` after 30 minutes. Show the transition (`workflows --section "SCHEDULED TRANSITIONS"`).

**Behaviour help doesn't settle.** When help doesn't settle how engine features combine (e.g. a failing criterion and a schedule on the same state), say what it leaves open and ask whether to spike it on a throwaway cyoda-go (in-memory with mock auth, per `cyoda help run`, or the stack in Docker); `cyoda` always loads `~/.config/cyoda/cyoda.env`, so set storage and auth explicitly.

**Other features help doesn't document.** "Coming soon" is only for features known to be planned, which today means notifications. For anything else the developer asks for that `cyoda help` doesn't document, say: "Not available in cyoda-go <VERSION> — check `cyoda help`." `<VERSION>` is the `VERSION=` that `cyoda-help.sh` reported. Then offer the closest documented way, if there is one.

**Anti-patterns:**

| Anti-pattern | Signal | Fix |
|---|---|---|
| Technical states | `processing`, `calling_*`, `retry`, `queued`, `waiting_for_response` | Remove, unless best practice *Add a technical state only where the platform needs one* keeps it |
| Orthogonal dimensions as states | Priority, assignment, ownership, visibility, payment status, SLA as lifecycle states | Attributes or sub-entities |
| Orthogonal lifecycles collapsed | Independent concerns (different rules, ownership, reporting) in one lifecycle | Separate entities |
| Parallel workflows on one entity | "a lifecycle workflow AND a compliance workflow" | Separate entities: each call runs one selected workflow (`workflows --section CRITERIA`, workflow-level selection) |
| Combinatorial wait states | `WaitingForAAndB`, `WaitingForAOnly` | Progress sub-entities plus a join ([design-guidelines.md](resources/design-guidelines.md) § Parallel Activities) |
| Super entity | One entity spans several independent business activities | Split |
| Low-value or stateless states | No change in allowed actions, validation, permissions or reporting | Remove or merge |
| State classification overuse | active/suspended/expired/archived… with identical behaviour | Consolidate |
| Dead-end state | Non-terminal state with no path to an outcome | Add a transition, or flag it |
| Generic transitions | `changeState`, `update`, `modify`, `process` | Rename with a business verb |

Mention a pattern from [patterns.md](resources/patterns.md) when it fits (approval, scheduled transition, cascade, error state with retry, saga, external trigger).

## Phase 4 — Design summary

Present the reviewed design in this shape. Don't write the full workflow files; `build` generates them from this summary. Short fragments that show a proposal (a query, one transition) are fine.

```
Best practices: <source from Step 0>

Entities:
  - <Entity>
      states: initial=<s>; others=[...]; error=[...]; terminal=[...]
      transitions: <name>: <from> → <to> (manual | automated, criterion: <what> | scheduled: <when>); roles: [...]
      key fields: <tree-shaped fields>; links: <field> → <Entity> id
      unique keys: [...] | none
  - ...

Compute nodes: none | <entity.transition>: <processor or function criterion>, and why

Schema evolution: none (strict) | <changeLevel>, and why

Review: <each checklist line changed, one line each; the rest ok or n/a>

First increment: <Entity> with <minimal workflow>
```

Ask: *"Does this match what you want? (yes, or tell me what to change)"*

Then hand off:
- If `cyoda-help.sh` reported `SOURCE=instance`: "Next, type `/cyoda:build` to turn the first increment into project files and register it on your instance."
- `SOURCE=binary`: "Next, type `/cyoda:setup` to start cyoda-go locally, then `/cyoda:build` to register the first increment."
- `SOURCE=web`: "Next, type `/cyoda:setup` to install and start cyoda-go, then `/cyoda:build` to register the first increment."
- If the developer already has an instance running, `/cyoda:build` alone.

## Common mistakes

| Mistake | Instead |
|---|---|
| Saying entities can be posted before the model is locked | Q6: sample data, lock, then a changeLevel |
| A "scheduled processor" | A `schedule` on an automated transition |
