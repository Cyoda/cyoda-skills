---
name: app
description: Start here if you're new to Cyoda. Walks through the full development journey — Cyoda orientation, app design, instance setup, incremental build, and testing. Experienced users can invoke individual skills directly.
argument-hint: [describe your app idea]
---

## Welcome to Cyoda Development

$ARGUMENTS

I'll guide you through building your Cyoda application step by step.

### What is Cyoda? (Brief orientation)

Cyoda is an **Entity Database Management System (EDBMS)**. Instead of tables with rows, you define **entities** — domain objects like Orders or Users — each with a **workflow**: named states and the transitions between them.

Key ideas:
- Nothing is ever overwritten — every transition creates a new immutable revision
- Your entities ARE state machines
- The same API works locally (cyoda-go) and on Cyoda Cloud — move between them with no code changes
- Compute nodes are **optional** — many workflows need no external processors at all

**Already familiar with Cyoda?** Ask: "Do you already have a domain design, or do you need to go through the design process?"
- If they **have a design**: skip to Step 2 (instance setup), then Step 3 (build).
- If they **need to design**: continue to Step 1.

Otherwise, continue below for the full guided journey.

---

### Step 1 — Design your app

Let's figure out what entities and workflows your app needs.

Invoke `/cyoda:design` — describe your application and I'll guide you through the domain model.

*(After design is complete, continue here.)*

---

### Step 2 — Set up your Cyoda instance

First, let me check if you already have a Cyoda instance configured.

Invoke `/cyoda:status`.

- If **already connected**: confirm with the user whether to use that environment and skip to Step 3.
- If **not connected**: present both options as co-equal:
  - **Local cyoda-go** (recommended for development — full control, offline-capable): Run `/cyoda:setup` → choose local
  - **Cyoda Cloud** (coming soon — no local install needed): Run `/cyoda:setup` → choose cloud, then `/cyoda:auth`

*(After setup is complete, run `/cyoda:status` to confirm connection.)*

---

### Step 3 — Build incrementally

Run `/cyoda:build` to start registering your entity models and workflows one increment at a time.

Start with the smallest possible first version: one entity, two states, one transition.

---

### Step 4 — Test

Run `/cyoda:test` to smoke-test your running instance. Verify entity creation, transitions, and state changes work as designed.

---

### Step 5 — Iterate

Repeat steps 3–4 for each new entity, state, or transition in your design.

---

### Step 6 — Move to Cyoda Cloud (when ready)

When your app is working locally and you're ready to go live:

Run `/cyoda:migrate` to lift-and-shift your models and workflows to Cyoda Cloud. No code changes required.

---

### Other skills available

| Skill | When to use |
|---|---|
| `/cyoda:docs` | Look up any Cyoda API or concept |
| `/cyoda:compute` | Implement gRPC compute node processors |
| `/cyoda:debug` | Diagnose failures or browse entity history |
| `/cyoda:status` | Check current connection |
