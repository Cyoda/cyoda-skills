---
name: build
description: Use when the developer types /cyoda:build to add or change a cyoda-go entity model or workflow (new entity, state, transition, criterion, processor, schedule, unique key, changeLevel, new model version) and keep it as versioned project files.
allowed-tools: Bash(*cyoda-call.sh *) Bash(*cyoda-help.sh *) Bash(*cyoda-status.sh*) Bash(jq *) Bash(find *) Bash(grep *) Bash(ls *) Bash(mkdir *) Bash(cat *)
disable-model-invocation: true
---

# Cyoda incremental build

One increment per loop: inspect the instance, agree the change, write the project files, register them in the canonical order, verify, and hand off.

**Facts come from `cyoda help`, not from this file.** Each step names the help section to read. Read the section, not the whole topic: run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` (stderr shows `SOURCE=instance|binary|web`). Exit 2 means unknown topic and exit 6 means unknown section (the stderr lists the sections that exist). Tell the developer which section you used.

**Every API call** goes through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh [--confirm-production] <METHOD> <PATH> [curl args...]`. PATH is relative to `<endpoint>/api` (e.g. `/model/`). The body goes to stdout and `HTTP_STATUS=<code>` to stderr. Never build a URL or auth header yourself, and never guess a path that the named help section doesn't list.

| Exit | Meaning | What you do |
|---|---|---|
| 0 | 2xx | continue |
| 22 | HTTP ≥ 400 | 401/403: the script already retried once with a fresh token. Show the error, stop, and say "next, type `/cyoda:auth`". Anything else: see [When a call fails](#when-a-call-fails) |
| 3 | production refusal | see [Production guard](#production-guard) |
| 4 | the profile's tokenCommand failed | show stderr, stop, and say "next, type `/cyoda:auth`" |
| 5 | no endpoint configured | stop and say "next, type `/cyoda:setup`" |

Request bodies are files: pass `--data-binary @<file>`, never stdin (a token retry would resend an empty body).

## Step 0 — Connection

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`.
- `STATUS=not_configured`: say "No cyoda-go instance is configured. Next, type `/cyoda:setup`." Stop.
- `STATUS=unreachable`: show the `WARN=` line and stop.
- `ENV=production`: tell the developer up front: "Profile `<PROFILE>` (`<ENDPOINT>`) is a **production** instance. I'll ask before every change."
- Show any other `WARN=` lines as they are.

## Step 1 — Inspect

Run `cyoda-call.sh GET /model/` (help: `models --section ENDPOINTS`). Show each model's name, version and `currentState` (UNLOCKED / LOCKED).

Then read the project's `cyoda-manifest.json` at the project root, if there is one, and the files it lists. These files are the source of truth for what `build` has written. If a model is on the instance but has no project files, offer to export its workflow (`GET /model/{e}/{v}/workflow/export`) and save it, reshaped as in Step 6.

Fresh instance and empty project: suggest the hello-world increment ([examples/hello-world.md](examples/hello-world.md)).

## Step 2 — Agree the increment

Ask what to add or change: a new entity with a workflow, a state, a transition, a criterion, a processor, a scheduled transition, unique keys, or the changeLevel. Ask the minimum questions, one at a time. Skip questions the request already answers.

Judgment calls (read the named section before proposing):

| Topic | Read | Guidance |
|---|---|---|
| States and transitions | `workflows --section TRANSITIONS` | Keep to the states the developer named, plus at least one terminal state. Use `manual: true` only for user-triggered actions |
| Criteria | `workflows --section CRITERIA`, `search --section "CONDITION DSL"` | Prefer a built-in `simple`/`group` criterion. Use a function criterion only when it needs data that isn't on the entity |
| Processors | `workflows --section PROCESSORS` | Tags match by **overlap** (any one shared tag). Use `grpc --section "TAG ROUTING"` for routing, not PROCESSORS (#684-B). The processor code itself is a compute node: see the `cyoda:compute` skill |
| Time-based moves | `workflows --section "SCHEDULED TRANSITIONS"` | A `schedule` object on an automated transition, not a separate processor |
| Loop limits | `workflows --section "ENGINE EXECUTION"` | Mind the per-state visit limit when a cycle is intentional |

For **error states, terminal states, loopback, validation cycles and rejection reasons**, follow the shared best practices. Probe the help topic first: `cyoda-help.sh workflows best-practices`, then `cyoda-help.sh design` (both exit 2 until #684-L ships). Fall back to `${CLAUDE_PLUGIN_ROOT}/skills/design/resources/best-practices.md` and name the bullets you applied.

Smoke-tested patterns to start from (each dir has `sample.json`, `workflow.json` and `config.json`):

| Pattern | Example |
|---|---|
| Linear, fully automated | [examples/hello-world/](examples/hello-world/) |
| Manual step, then a criterion re-evaluated on update (loopback) | [examples/loopback/](examples/loopback/) |
| Validation, `errored` state, retry, unique key, two terminal states | [examples/error-states/](examples/error-states/) |
| Scheduled transition | [examples/scheduled/](examples/scheduled/) |

## Step 3 — Version decision

Read `models --section LIFECYCLE`. Then decide:

| Change | Model state | Version |
|---|---|---|
| New entity | — | `1` |
| Workflow only (states, transitions, criteria, processors, schedules) | any | same version; re-import the workflow |
| Sample / schema or unique keys | UNLOCKED | same version |
| Sample / schema or unique keys | LOCKED, 0 entities | same version: unlock, then redo the model steps |
| Sample / schema or unique keys | LOCKED, entities exist | **propose version N+1** |

Count entities with `cyoda-call.sh GET /entity/stats/{e}/{v}` (`.count`; help: `crud --section ENDPOINTS`). If entities exist, say: "`{e}` v{N} has {count} entities, so it can't be unlocked (`MODEL_HAS_ENTITIES`, see `cyoda-help.sh errors MODEL_HAS_ENTITIES`). I propose v{N+1}; v{N} and its entities stay as they are." Wait for the answer. Never unlock a model to find out.

## Step 4 — Schema settings

Ask, and record the answers in the entity's `-config.json` (schema: [templates/entity-config.json](templates/entity-config.json)):

1. **Unique keys**: any field or field combination that must be unique? Shape and limits: `models --section ENDPOINTS` (unique-keys). Record them in `uniqueKeys` (`[]` for none).
2. **changeLevel**: read the values from `models --section ENDPOINTS` (changeLevel) and `models --section LIFECYCLE`. Then ask: "Which changeLevel do you want? None keeps the schema strict: entities and processor output may only use the sample's fields. Or one of the values listed there, from least to most permissive." Ask whether any processor writes fields that aren't in the sample, because a strict schema rejects them. Record the choice in `changeLevel`, or `null` for none.
3. Leave `env` as `{}`. Per-environment overrides are recorded when the developer deploys.

## Step 5 — Generate and confirm

Build the three files from [templates/](templates/) and the closest example:
- `-sample.json`: one realistic entity with every field the model needs (types matter: the schema is inferred from it).
- `-workflow.json`: `{"workflows":[...]}` only, shaped per `workflows --section "WORKFLOW SCHEMA"`. Keep `"version": "${SCHEMA_VERSION}"` in the file. The value is substituted at import time.
- `-config.json`: the Step 4 answers.

Show all three, plus the list of API calls you'll make, and ask: "Does this look right? (yes to proceed, or describe changes)". Wait for yes.

## Step 6 — Save the files

**Detect the layout** (scan first, then fall back):
```bash
if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then echo java
elif [ -f package.json ] && [ -f tsconfig.json ]; then echo typescript
elif [ -f package.json ]; then echo javascript
elif [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; then echo python
else find . -maxdepth 4 -type d \( -name workflow -o -name workflows \) -not -path '*/node_modules/*' | head -1; fi
```

| Detected | Workflow | Sample | Config | Model class (only if asked) |
|---|---|---|---|---|
| Java | `src/main/resources/workflow/` | `src/main/resources/data/` | `src/main/resources/config/` | `src/main/java/{pkg}/model/` |
| TypeScript/JS | `src/workflows/` | `src/data/` | `src/config/` | `src/models/` |
| Python | `{package}/workflows/` | `resources/data/` | `resources/config/` | `{package}/models/` |
| Existing `workflow/` or `workflows/` dir | mirror it; sibling `data/` and `config/` | | | |
| Nothing found | TypeScript defaults | | | |

Java `{pkg}`: `grep -rh "^package " src/main/java/ | head -1 | sed 's/^package //; s/;.*//' | tr . /` (fallback `src/main/java/model/`).

**Naming — `{entity}-v{version}-{type}.json`** with the entity in kebab-case: `order-v1-sample.json`, `order-v1-workflow.json`, `order-v1-config.json`. Code classes follow language casing (`OrderV1.java`, `OrderV1.ts`, `order_v1_model.py`). A same-version change updates that version's files in place. A new version is written next to the old files; never edit or delete the old version's files.

**Manifest** (`cyoda-manifest.json` at the project root; schema: [templates/cyoda-manifest.json](templates/cyoda-manifest.json)). Create it if it's missing: `{"manifestVersion":1,"entities":[]}`. Then upsert the entry for this entity version, keyed by `name` + `modelVersion` (an integer). Paths are relative to the project root:
```bash
jq --arg n order --argjson v 1 --arg s src/data/order-v1-sample.json \
   --arg w src/workflows/order-v1-workflow.json --arg c src/config/order-v1-config.json \
   '.entities = ([.entities[] | select(.name != $n or .modelVersion != $v)]
                 + [{name:$n, modelVersion:$v, sample:$s, workflow:$w, config:$c}])' \
   cyoda-manifest.json > cyoda-manifest.json.tmp && mv cyoda-manifest.json.tmp cyoda-manifest.json
```

Tell the developer each relative path saved.

**Reshaping an export.** An export is `{entityName, modelVersion, workflows}`, and the import rejects unknown fields (#684-I). Save only `jq '{workflows}'` of it.

## Step 7 — Register (canonical order)

Read `models --section ENDPOINTS` and `workflows --section "IMPORT REQUEST"`. Then run only the steps the Step 3 decision needs, in this order, stopping at the first failure:

1. `POST /model/import/JSON/SAMPLE_DATA/{e}/{v}` with `-H 'Content-Type: application/json' --data-binary @<sample>`. On a locked model with no entities, first `PUT /model/{e}/{v}/unlock`.
2. Only if `uniqueKeys` isn't empty, and only while the model is UNLOCKED: `PUT /model/{e}/{v}/unique-keys` with body `{"uniqueKeys": [...]}`.
3. `PUT /model/{e}/{v}/lock`
4. Only if `changeLevel` isn't null: `POST /model/{e}/{v}/changeLevel/{changeLevel}`
5. Workflow import. Read the schema version: `cyoda-help.sh workflows schema-version versions`, then `.current`. If that exits 2, use `cyoda-call.sh GET /help/workflows/schema-version/versions`, which is the same JSON from the instance. Substitute it into a temp copy, then post that:
   ```bash
   jq --arg v "<current>" '{importMode: "MERGE", workflows: (.workflows | map(.version = $v))}' <workflow-file> > "${TMPDIR:-/tmp}/<e>-v<v>-import.json"
   ```
   `POST /model/{e}/{v}/workflow/import` with `-H 'Content-Type: application/json' --data-binary @"${TMPDIR:-/tmp}/<e>-v<v>-import.json"`. MERGE replaces workflows by name. Use REPLACE only when the developer wants other workflows on the model removed.

Entities are created only after the workflow is imported. Creating them is `/cyoda:test`'s job, not this skill's.

### Production guard

Exit 3 means the profile has `env: production` and the call mutates. Don't add `--confirm-production` before you've asked. On exit 3, list the remaining calls of this increment (method and path) and ask: "This changes production instance `<ENDPOINT>`. Proceed? (yes/no)". Only after an explicit yes, re-run those calls with `--confirm-production`. The next increment needs a new yes. GET calls never need it.

### When a call fails

Exit 22 with a status other than 401/403:
1. Read `errorCode` from the body (`.properties.errorCode`) and run `cyoda-help.sh errors <errorCode>`. For model calls, also check `models --section ERRORS`. The full index is `errors --section "ERROR CODE INDEX"`, and some codes are listed only under SEE ALSO.
2. Explain the cause using the help text and the response `detail`. Fix the **payload**. The path stays as the help section gives it: don't try alternate URLs.
3. Common causes: `WORKFLOW_SCHEMA_VERSION_UNSUPPORTED` (version not substituted); `BAD_REQUEST` "unknown field" (export posted verbatim: reshape, #684-I); `VALIDATION_FAILED` (the `detail` names the workflow, state or transition); `MODEL_ALREADY_LOCKED` (go back to Step 3).
4. Show the corrected file, update the saved project file to match, and re-run from the failed step after a yes.
5. If it still fails, offer the `cyoda:debug` skill with the call, status and body.

## Step 8 — Verify and hand off

Run `cyoda-call.sh GET /model/` and `cyoda-call.sh GET /model/{e}/{v}/workflow/export`. Show that the model is LOCKED and that the workflow has the expected states.

Close with: "Registered `{e}` v{v}. Files: `<paths>`, manifest updated. Next, type `/cyoda:test` to smoke-test this increment, or tell me the next change." For the next change, start again at Step 1.

## Common mistakes

| Mistake | Instead |
|---|---|
| Creating an entity before the workflow import, or leaving the model unlocked | Canonical order, Step 7. Entities need a LOCKED model |
| Hard-coding the workflow `version` | `${SCHEMA_VERSION}` in the file, substituted from `workflows schema-version versions` |
| Re-importing a sample into a LOCKED model with entities | New model version (Step 3) |
| Posting a workflow export as is | `{importMode, workflows}` only (#684-I) |
| Retrying a 4xx with a guessed path | `cyoda-help.sh errors <code>`, fix the payload |
| Passing `--confirm-production` pre-emptively | Only after exit 3 and an explicit yes |
| Handling 401 by re-running the token command | The script already did. Say "next, type `/cyoda:auth`" |
