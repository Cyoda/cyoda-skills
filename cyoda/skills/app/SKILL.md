---
name: app
description: Use when the developer types /cyoda:app to be guided through building a cyoda-go application end to end (orientation, design, local instance, incremental build, smoke test, optional deployment), especially when they are new to Cyoda.
argument-hint: [describe your app idea]
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-help.sh *)
disable-model-invocation: true
---

# Cyoda development journey

$ARGUMENTS

A guide: this skill writes nothing and calls no instance API. Each step names the skill that does the work. The developer starts each step that has side effects; hand it over as "next, type `/cyoda:<skill>` to <one-line reason>", then wait.

The journey: **design → local cyoda-go → build → test → iterate → deploy files (optional)**.

## Step 0 — Where the developer is

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh` and keep the result for Step 2.

Where the developer is, from their message or by asking "Is Cyoda new to you, do you already have a design, or do you have models registered and want to continue building?":

| Answer | Start at |
|---|---|
| New to Cyoda | Orientation, then Step 1 |
| Has a design (entities, states, transitions) | Step 2 |
| Has models on a connected instance | Step 3 |

Tell the developer the journey line and where they are in it, e.g. "The journey is design → local cyoda-go → build → test → iterate → deploy files (optional); you're at design."

## Orientation (new developers only)

Cyoda is an Entity Database Management System (EDBMS): a database where every record is a state machine. You define **entities** (domain objects like Orders or Users), each with a **workflow**: named states and the transitions between them. Nothing is overwritten: every write produces a new immutable version, so each entity keeps its full history. Compute nodes (your own code, called by a workflow) are optional; many apps need none.

For anything beyond that, use the `cyoda:docs` skill.

## Step 1 — Design

Use the `cyoda:design` skill with the developer's idea (`$ARGUMENTS` if given). It ends with a design summary and a first increment.

## Step 2 — Local cyoda-go

From Step 0's status:
- `STATUS=connected`: ask "Use `<ENDPOINT>` [profile: `<PROFILE>`] for this app?" (`[project: <PROFILE>]` when `SOURCE=project`), and in the same message: "If yes, next, type `/cyoda:build` to turn the first increment into project files and register it. If no, next, type `/cyoda:setup` to start a local cyoda-go or connect to another instance."
- `STATUS=not_configured` or `unreachable`: "Next, type `/cyoda:setup` to install and start cyoda-go locally (or connect to an instance you already run)." When the developer is back, re-run `cyoda-status.sh`.

If the instance needs a token: "next, type `/cyoda:auth`".

## Step 3 — Build

"Next, type `/cyoda:build` to turn the first increment into project files and register it." The first increment: one entity, its sample data, and a workflow from its initial state to a terminal state. `build` registers it in the canonical order (sample data, lock, workflow) from `cyoda help models` LIFECYCLE; entities come only after that.

## Step 4 — Test

"Next, type `/cyoda:test` to create an entity and walk its transitions." If it fails, use the `cyoda:debug` skill on the reported entity or error.

## Step 5 — Iterate

Repeat Steps 3 and 4, one increment at a time: a new state, transition, criterion, processor, schedule, or entity. When an increment needs your own code (an external call or a check on data that isn't on the entity), use the `cyoda:compute` skill.

## Step 6 — Deploy files (optional)

"Next, type `/cyoda:deploy` to write deployment files and a seed script for your models into the project." `deploy` writes files only; the developer's pipeline runs them.

## Other skills

| Skill | Use it for |
|---|---|
| `cyoda:docs` | Any API, concept or error code (reads `cyoda help`) |
| `cyoda:compute` | A compute node: processors and function criteria over gRPC |
| `cyoda:debug` | A failed transition or call, an unexpected state, or an entity's history |
| `cyoda:status` | Which instance is connected |
