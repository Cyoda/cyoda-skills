---
name: build
description: Incrementally build Cyoda entity models and workflows. Inspects the running instance, brainstorms the next change, generates config, and registers it. Supports new entities, new states, new transitions, criteria, and schema mode changes.
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(echo *) Bash(tee *) Bash(jq *)
---

## Cyoda Incremental Build

**API rule:** Never construct or guess an API URL that is not explicitly listed in this skill. For any endpoint not listed here, invoke `cyoda:docs` to look up the correct path before making the call. Do not use curl OPTIONS for CORS diagnostics — if a SPA can't reach Cyoda, direct the user to `/cyoda:setup`.

**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. If the retry also fails, surface the error to the user. Do not retry on any other error code.

Reading connection config:
```!
jq . .cyoda/config 2>/dev/null || echo '{"endpoint":"none"}'
```

If `"endpoint":"none"` or config is absent: *"No Cyoda instance configured. Run `/cyoda:setup` first."* Stop.

If `.env` equals `production`: display **"⚠️ Operating against a PRODUCTION Cyoda instance. All changes will affect live data. You will be asked to confirm before each registration."**

### Step 1 — Inspect current state

```!
ENDPOINT=$(jq -r '.endpoint' .cyoda/config)
TOKEN=$(jq -r '.token // ""' .cyoda/config)
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

### Step 4 — Register

If `.env` equals `production`: *"You're about to register this change to PRODUCTION. Type 'confirm' to proceed."* Wait for explicit `confirm`.

```bash
ENDPOINT=$(jq -r '.endpoint' .cyoda/config)
TOKEN=$(jq -r '.token // ""' .cyoda/config)
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
ENDPOINT=$(jq -r '.endpoint' .cyoda/config)
TOKEN=$(jq -r '.token // ""' .cyoda/config)
AUTH_HEADER=$([ -n "$TOKEN" ] && echo "Authorization: Bearer $TOKEN" || echo "X-Mock-Auth: true")
curl -sf -H "$AUTH_HEADER" "${ENDPOINT%/}/api/model" 2>/dev/null || echo "[]"
```

Show the updated model state. Offer: *"Run `/cyoda:test` to smoke-test this increment, or tell me the next increment to add."*

Repeat from Step 2 for the next increment.

For any endpoint not listed in this skill, invoke `/cyoda:docs` before making the call — never guess.
