---
name: app
description: Use when the developer types /cyoda:app to be guided through building a cyoda-go application end to end (orientation, design, local instance, incremental build, smoke test, optional deployment), especially when they are new to Cyoda.
argument-hint: [describe your app idea]
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-help.sh *)
disable-model-invocation: true
---

# Cyoda development journey

$ARGUMENTS

A guide, not a doer. This skill writes nothing and calls no instance API. Each step names the skill that does the work. Steps with side effects are started by the developer: say "next, type `/cyoda:<x>`" with a one-line reason, then wait. Never say you'll invoke or run them yourself.

The journey: **design → setup → build → test → iterate → deploy (optional)**.

## Step 0 — Where the developer is

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh` and keep the result for Step 2. Print its status line and any `WARN=` lines as they are.

Ask one question: "Is Cyoda new to you, do you already have a design, or do you have models registered and want to continue building?"

| Answer | Start at |
|---|---|
| New to Cyoda | Orientation, then Step 1 |
| Has a design (entities, states, transitions) | Step 2 |
| Has models on a connected instance | Step 3 |

Before the first step, tell the developer the journey in one line and where they are in it, e.g. "The journey is design → setup → build → test → iterate → deploy (optional); you're at design."

## Orientation (new developers only)

Two or three sentences, then ask "Does that make sense? Ready to design your app?":

Cyoda is an Entity Database Management System (EDBMS): a database where every record is a state machine. You define **entities** (domain objects like Orders or Users), each with a **workflow**: named states and the transitions between them. Nothing is overwritten: every write produces a new immutable version, so each entity keeps its full history. Compute nodes (your own code, called by a workflow) are optional; many apps need none.

For anything beyond that, use the `cyoda:docs` skill rather than explaining from memory.

## Step 1 — Design

Use the `cyoda:design` skill with the developer's idea (`$ARGUMENTS` if given). It ends with a design summary and a first increment. Continue when the developer has agreed the summary.

## Step 2 — Instance

From Step 0's status:
- `STATUS=connected`: confirm "Use `<ENDPOINT>` [profile: `<PROFILE>`] for this app? (yes/no)". On yes, go to Step 3. On no, "next, type `/cyoda:setup` to start a local instance or connect to another one".
- `STATUS=not_configured` or `unreachable`: "Next, type `/cyoda:setup` to install and start cyoda-go locally (or connect to an instance you already run)." Wait. When the developer is back, re-run `cyoda-status.sh` and show the line.
- A `[PRODUCTION]` profile: suggest a development instance for building, and leave the choice to the developer.

If the instance needs a token: "next, type `/cyoda:auth`". Setup and auth detect it with an unauthenticated `GET /api/model/` that returns 401 or 403; the status line doesn't report it.

## Step 3 — Build

"Next, type `/cyoda:build` to turn the first increment into project files and register it." The first increment is the smallest working one: one entity, its sample data, and a workflow from its initial state to a terminal state. `build` registers it in the canonical order (sample data, lock, workflow) from `cyoda help models` LIFECYCLE; entities come only after that.

## Step 4 — Test

"Next, type `/cyoda:test` to create an entity and walk its transitions." If it fails, use the `cyoda:debug` skill on the reported entity or error.

## Step 5 — Iterate

Repeat Steps 3 and 4, one increment at a time: a new state, transition, criterion, processor, schedule, or entity. When an increment needs your own code (an external call or a check on data that isn't on the entity), use the `cyoda:compute` skill.

## Step 6 — Deploy (optional)

When the app runs locally and the developer wants it elsewhere: "next, type `/cyoda:deploy` to write deployment files and a seed script for your models into the project". `deploy` writes files only; the developer runs them.

## Other skills

| Skill | Use it for |
|---|---|
| `cyoda:docs` | Any API, concept or error code (reads `cyoda help`) |
| `cyoda:compute` | Writing a compute node: processors and function criteria over gRPC |
| `cyoda:debug` | A failed transition or call, an unexpected state, or an entity's history |
| `cyoda:status` | Which instance is connected |

Cloud, hosted offerings or migration: reply only "That's not covered by this plugin." Don't name or describe the product or offer alternatives for it.

## Common mistakes

| Mistake | Instead |
|---|---|
| "I'll run `/cyoda:build` for you" | "Next, type `/cyoda:build`" with a one-line reason, then wait |
| Explaining Cyoda APIs from memory | The `cyoda:docs` skill |
| Skipping design for a new developer | Step 1 before Step 3 |
| A first increment with many entities | One entity, initial to terminal state |
