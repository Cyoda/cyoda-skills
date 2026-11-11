# Hello world: the first increment

A walkthrough of [hello-world/](hello-world/), the smallest entity that runs end to end on cyoda-go. Smoke scenario `01-hello-world` loads exactly these files, so they're known to work on v0.8.4.

## The three files

| File | What it holds | Saved by `build` as |
|---|---|---|
| [hello-world/sample.json](hello-world/sample.json) | One example entity with two string fields. The model's schema is inferred from it | `hello-v1-sample.json` |
| [hello-world/workflow.json](hello-world/workflow.json) | One workflow: `new` → `processing` → `completed`, then `archive` → `archived`. The first two transitions are automated (`manual: false`, no criterion), so a new entity runs straight through to `completed` and stops there. `archive` is manual: it fires only when a caller names it, which gives `/cyoda:test` a transition to fire | `hello-v1-workflow.json` |
| [hello-world/config.json](hello-world/config.json) | No unique keys, `changeLevel: null` (strict schema), no per-environment overrides | `hello-v1-config.json` |

The workflow's `version` is the placeholder `${SCHEMA_VERSION}`. It's replaced at import time with `.current` from `cyoda help workflows schema-version versions`. A hard-coded value goes stale when the server's supported range moves.

## Registering it, in canonical order

Each step follows the help section the `build` skill names (Step 7 of [../SKILL.md](../SKILL.md)):

1. **Import the sample**: `POST /model/import/JSON/SAMPLE_DATA/hello/1` with `sample.json`. The model now exists, UNLOCKED. Read `cyoda help models` ENDPOINTS.
2. **Unique keys**: skipped, because `uniqueKeys` is empty. They can only be set while the model is UNLOCKED.
3. **Lock**: `PUT /model/hello/1/lock`. Entities can only be created on a LOCKED model. Read `cyoda help models` LIFECYCLE.
4. **changeLevel**: skipped, because it's `null`.
5. **Import the workflow**: `POST /model/hello/1/workflow/import` with `{importMode, workflows}`, version substituted. Read `cyoda help workflows` IMPORT REQUEST.

Only then is an entity created. That's `/cyoda:test`'s job. The entity is created in `new`, and the cascade carries it to `completed` in the same save. Firing `archive` (PATCH `{}`, see `cyoda help crud` ENDPOINTS) moves it to `archived`; smoke scenario `01` does this with the `test` skill's `smoke-test.sh`.

## What to try next

- Add a manual step and a criterion that's re-checked on update: [loopback/](loopback/).
- Add validation with an `errored` state and a retry: [error-states/](error-states/).
- Move an entity on a timer: [scheduled/](scheduled/).

Changing the sample after entities exist needs a new model version (`hello` v2). Changing only the workflow doesn't.
