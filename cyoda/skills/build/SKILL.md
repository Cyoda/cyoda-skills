---
name: build
description: Incrementally build Cyoda entity models and workflows. Inspects the running instance, brainstorms the next change, generates config, and registers it. Supports new entities, new states, new transitions, criteria, and schema mode changes.
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(echo *) Bash(tee *) Bash(jq *) Bash(find *) Bash(mkdir *) Bash(ls *)
---

## Cyoda Incremental Build

**API rule:** Never construct or guess an API URL that is not explicitly listed in this skill. For any endpoint not listed here, invoke `cyoda:docs` to look up the correct path before making the call.

**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. If the retry also fails, surface the error to the user. Do not retry on any other error code.

Reading connection config:
```!
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default"); jq --arg p "$PROFILE" '.profiles[$p] // {"endpoint":"none"}' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo '{"endpoint":"none"}'
```

If `"endpoint":"none"` or config is absent: *"No Cyoda instance configured. Run `/cyoda:setup` first."* Stop.

If `.env` equals `production`: display **"⚠️ Operating against a PRODUCTION Cyoda instance. All changes will affect live data. You will be asked to confirm before each registration."**

### Step 1 — Inspect current state

```!
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default")
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint // "none"' "$HOME/.config/cyoda/cyoda-plugin-config.json")
TOKEN=$(jq -r --arg p "$PROFILE" '.profiles[$p].token // ""' "$HOME/.config/cyoda/cyoda-plugin-config.json")
AUTH_HEADER=$([ -n "$TOKEN" ] && echo "Authorization: Bearer $TOKEN" || echo "X-Mock-Auth: true")
curl -sf -H "$AUTH_HEADER" "${ENDPOINT%/}/api/model" 2>/dev/null || echo "[]"
```

Show the user what entity models currently exist in the instance, including the version number for each.

If this is a fresh instance with no models: suggest starting with the hello world increment. Reference [examples/hello-world.md](examples/hello-world.md) for the minimal starting point.

### Step 2 — Brainstorm next increment

Ask: *"What would you like to add or change? Options:*
- *New entity model with workflow*
- *New state to an existing entity*
- *New transition between states*
- *Add criteria to a transition*
- *Add a processor to a transition*
- *Something else"*

> Schema stays in **discover mode** during development — Cyoda infers it automatically from the entities you post. Only lock the schema when you're confident all fields are known and you're moving to production.

**Version decision:** If the user's chosen increment targets an entity that already exists (visible in Step 1), ask: *"This entity is already registered at version {N}. Do you want to (a) update the existing version, or (b) create a new version {N+1}?"* Use the chosen version in all subsequent API calls. If the entity is new, default to version 1.

Wait for the user's choice.

### Step 3 — Clarify and generate config

Based on the chosen increment, ask the minimum clarifying questions (one at a time) and generate the JSON config. Show it to the user:

*"Here's the config I'll register:"*
```json
[generated config here]
```
*"Does this look right? (yes to proceed, or describe changes)"*

Use [templates/workflow.json](templates/workflow.json) and [templates/sample-entity.json](templates/sample-entity.json) as starting points.

### Step 3b — Save generated files

After the user confirms the config, detect the project layout and save all generated files before registering via API.

**Detect language:**
```bash
if [ -f "pom.xml" ] || [ -f "build.gradle" ]; then echo "java"
elif [ -f "package.json" ] && [ -f "tsconfig.json" ]; then echo "typescript"
elif [ -f "package.json" ]; then echo "javascript"
elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "setup.py" ]; then echo "python"
else find . -maxdepth 4 -type d \( -name "workflow" -o -name "workflows" \) | head -1; fi
```

**Resolve target directories:**

| Detected | Workflow | Data | Config | Model |
|---|---|---|---|---|
| Java | `src/main/resources/workflow/` | `src/main/resources/data/` | `src/main/resources/config/` | `src/main/java/{pkg}/model/` |
| TypeScript/JS | `src/workflows/` | `src/data/` | `src/config/` | `src/models/` |
| Python | `{package}/workflows/` | `resources/data/` | `resources/config/` | `{package}/models/` |
| Existing `workflow/` dir found | mirror it; derive siblings for `data/` and `config/` | | | |
| Nothing found | fall back to TypeScript defaults | | | |

For Java, detect `{pkg}` from existing source files:
```bash
grep -r "^package " src/main/java/ 2>/dev/null | head -1 | sed 's/^package //; s/;.*//' | tr '.' '/'
```
If not found, use `src/main/java/model/`.

**File naming — `{entity}-v{version}-{type}`:**

| Resource | Example (`Order`, v`1`) |
|---|---|
| Workflow JSON | `{workflow-dir}/order-v1-workflow.json` |
| Sample entity JSON | `{data-dir}/order-v1-sample.json` |
| Import/export config | `{config-dir}/order-v1-config.json` |
| Java model | `{model-dir}/OrderV1.java` |
| TypeScript model | `{model-dir}/OrderV1.ts` |
| Python model | `{model-dir}/order_v1_model.py` |

Entity name in JSON filenames uses kebab-case; code files follow language casing conventions.

**Write files:**
```bash
mkdir -p "${TARGET_DIR}"
echo "${GENERATED_JSON}" | tee "${TARGET_DIR}/${FILENAME}"
```

Tell the user: *"Saved to `{relative-path}`."*

When a new model version is created, existing versioned files are left untouched — new files are written alongside them.

### Step 4 — Register

If `.env` equals `production`: *"You're about to register this change to PRODUCTION. Type 'confirm' to proceed."* Wait for explicit `confirm`.

```bash
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default")
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint // "none"' "$HOME/.config/cyoda/cyoda-plugin-config.json")
TOKEN=$(jq -r --arg p "$PROFILE" '.profiles[$p].token // ""' "$HOME/.config/cyoda/cyoda-plugin-config.json")
AUTH_HEADER=$([ -n "$TOKEN" ] && echo "-H 'Authorization: Bearer $TOKEN'" || echo "")

# Known endpoint — invoke cyoda:docs for any other endpoint:
curl -X POST ${AUTH_HEADER} \
  -H 'Content-Type: application/json' \
  -d '${GENERATED_CONFIG}' \
  "${ENDPOINT%/}/api/model/${ENTITY_NAME}/${MODEL_VERSION}/workflow/import"
```

Show the response. If the call returns 4xx/5xx: invoke `cyoda:docs` to look up the correct endpoint — do not guess alternate paths. Then delegate to `/cyoda:debug` for persistent issues.

### Step 5 — Verify and loop

*"Registration complete."*

Re-inspect the current entity/workflow state to show what changed:

```!
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default")
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint // "none"' "$HOME/.config/cyoda/cyoda-plugin-config.json")
TOKEN=$(jq -r --arg p "$PROFILE" '.profiles[$p].token // ""' "$HOME/.config/cyoda/cyoda-plugin-config.json")
AUTH_HEADER=$([ -n "$TOKEN" ] && echo "Authorization: Bearer $TOKEN" || echo "X-Mock-Auth: true")
curl -sf -H "$AUTH_HEADER" "${ENDPOINT%/}/api/model" 2>/dev/null || echo "[]"
```

Show the updated model state. Offer: *"Run `/cyoda:test` to smoke-test this increment, or tell me the next increment to add."*

Repeat from Step 2 for the next increment.

For any endpoint not listed in this skill, invoke `/cyoda:docs` before making the call — never guess.
