---
name: migrate
description: Lift-and-shift a Cyoda application from local cyoda-go to Cyoda Cloud. Exports entity models and workflows from local, sets up cloud instance, imports, and verifies. No code changes required — same API surface on both tiers.
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(mkdir *) Bash(tee *) Bash(jq *) Bash(find *) Bash(ls *)
---

## Cyoda Lift-and-Shift Migration

This migrates your entity models and workflows from local cyoda-go to Cyoda Cloud. Your application code does not change — just the `endpoint` and auth config.

Reading current local config:
```!
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default"); jq --arg p "$PROFILE" '.profiles[$p] // {"endpoint":"none"}' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo '{"endpoint":"none"}'
```

If `"endpoint":"none"` or config is absent: *"No Cyoda endpoint configured. Run `/cyoda:setup` first."* Stop.

If `.env` equals `production`: display **"⚠️ Operating against a PRODUCTION Cyoda instance. Exports and imports will affect live data."**

If not pointing to a local instance (endpoint does not contain `localhost` or `127.0.0.1`): *"This skill migrates FROM local cyoda-go. Your current config points to a non-local endpoint. Are you sure you want to proceed?"*

**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. If the retry also fails, surface the error to the user. Do not retry on any other error code.

### Step 1 — Verify local instance is working

```bash
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default")
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint // "none"' "$HOME/.config/cyoda/cyoda-plugin-config.json")
curl -sf --max-time 5 "${ENDPOINT}/readyz" || echo "UNREACHABLE"
```

If unreachable: *"Start local cyoda-go first (`cyoda`), then re-run this skill."* Stop.

Suggest running `/cyoda:test` against local before migrating to confirm everything works.

### Step 2 — Detect project layout, then export

**Detect language (same scan-first logic as `cyoda:build` Step 3b):**
```bash
if [ -f "pom.xml" ] || [ -f "build.gradle" ]; then echo "java"
elif [ -f "package.json" ] && [ -f "tsconfig.json" ]; then echo "typescript"
elif [ -f "package.json" ]; then echo "javascript"
elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "setup.py" ]; then echo "python"
else find . -maxdepth 4 -type d \( -name "workflow" -o -name "workflows" \) | head -1; fi
```

Resolve target directories using the same table as `cyoda:build`. For Java, detect `{pkg}` from existing source files. Fall back to TypeScript defaults if nothing is found.

**Export entity models, schemas, and workflows:**

```bash
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default")
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint // "none"' "$HOME/.config/cyoda/cyoda-plugin-config.json")

# List all models
MODELS=$(curl -sf "${ENDPOINT}/api/model")
echo "$MODELS" | tee migration/models.json

# For each entity, export schema and workflow using {entity}-v{version}-{type} naming:

# Export JSON Schema (field definitions) → {config-dir}/{entity}-v{version}-schema.json
curl -sf "${ENDPOINT}/api/model/export/JSON_SCHEMA/${ENTITY_NAME}/${MODEL_VERSION}" \
  | tee "${CONFIG_DIR}/${ENTITY_KEBAB}-v${MODEL_VERSION}-schema.json"

# Export workflow → {workflow-dir}/{entity}-v{version}-workflow.json
curl -sf "${ENDPOINT}/api/model/${ENTITY_NAME}/${MODEL_VERSION}/workflow/export" \
  | tee "${WORKFLOW_DIR}/${ENTITY_KEBAB}-v${MODEL_VERSION}-workflow.json"
```

`ENTITY_KEBAB` is the entity name in kebab-case (e.g., `Order` → `order`, `RiskAssessment` → `risk-assessment`).

Show the user what was exported — confirm both schema and workflow files exist for each entity before proceeding.

### Step 3 — Set up Cyoda Cloud

*"Now let's connect to Cyoda Cloud. I'll invoke `/cyoda:setup` (cloud mode)."*

Invoke `cyoda:setup` for cloud setup, then `cyoda:auth` for authentication.

After setup: re-read `~/.config/cyoda/cyoda-plugin-config.json` to confirm cloud endpoint is active.

### Step 4 — Pre-check cloud, then import

**Phase 4a — Pre-check (read-only, no mutations yet)**

For each exported entity, query the cloud instance:

```bash
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default")
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint // "none"' "$HOME/.config/cyoda/cyoda-plugin-config.json")
TOKEN=$(jq -r --arg p "$PROFILE" '.profiles[$p].token // ""' "$HOME/.config/cyoda/cyoda-plugin-config.json")

curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  "${ENDPOINT}/api/model/${ENTITY_NAME}/${MODEL_VERSION}/workflow/export"
```

Classify each entity:
- **404 / no workflow**: new — will import without asking
- **200, workflow matches local**: up-to-date — will skip without asking
- **200, workflow differs**: conflicting — show a diff (state names, transition count) and ask the user: *"Overwrite or skip?"*
- **5xx**: surface the error and stop

If no conflicts exist across all entities, proceed to Phase 4b without any interruption.
If conflicts exist, show all of them in a single summary before asking — not one-by-one.

**Phase 4b — Import**

Execute imports only for entities marked new or overwrite. Skip the rest.

```bash
curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d @"${WORKFLOW_DIR}/${ENTITY_KEBAB}-v${MODEL_VERSION}-workflow.json" \
  "${ENDPOINT}/api/model/${ENTITY_NAME}/${MODEL_VERSION}/workflow/import"
```

Show success/failure per import.

### Step 5 — Verify

Invoke `/cyoda:test` against the cloud endpoint. All tests should pass identically to local.

### Step 6 — Update app config

*"Migration complete. Update your application to use:*
- *`endpoint`: {cloud endpoint}*
- *`token`: (from `/cyoda:auth`)*

*The API surface is identical — no code changes needed."*

Show [templates/migration-checklist.md](templates/migration-checklist.md) as a reference.
