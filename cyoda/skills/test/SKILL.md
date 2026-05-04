---
name: test
description: Smoke-test a running Cyoda instance. Generates and runs tests for entity creation, transitions, state verification, and point-in-time history. Runs in an isolated subagent to keep test output out of the main conversation.
context: fork
agent: general-purpose
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(chmod *) Bash(bash *) Bash(jq *)
---

## Cyoda Smoke Test

Reading connection config:
```!
jq . .cyoda/config 2>/dev/null || echo '{"endpoint":"none"}'
```

If `"endpoint":"none"` or config is absent: report *"No Cyoda instance configured. Run `/cyoda:setup` first."* Stop.

**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. If the retry also fails, surface the error to the user. Do not retry on any other error code.

If `.env` equals `production`: report *"⚠️ This will run tests against a PRODUCTION instance. Tests create real entities and trigger real transitions. Proceed? (yes/no)"* Wait for explicit `yes`.

### Mode Selection

Ask: *"Which test mode?*
- *Guided — I generate a test script you can save and re-run*
- *Automated — I run tests directly against your running instance now"*

---

### Guided Mode

Generate a populated `smoke-test.sh` from [templates/smoke-test.sh](templates/smoke-test.sh), replacing placeholders with the actual entity name, model version, and transition name from the user's app.

Show the completed script. Instruct: *"Save this as `smoke-test.sh`, run `chmod +x smoke-test.sh`, then `./smoke-test.sh`"*

---

### Automated Mode

Run the following test sequence directly:

**Test 1 — Create entity:**
```bash
ENDPOINT=$(jq -r '.endpoint' .cyoda/config)
TOKEN=$(jq -r '.token // ""' .cyoda/config)
AUTH=$([ -n "$TOKEN" ] && echo "-H 'Authorization: Bearer $TOKEN'" || echo "")
curl -sf -X POST $AUTH -H 'Content-Type: application/json' \
  -d '{"smokeTest": true}' \
  "${ENDPOINT}/api/entity/JSON/${ENTITY_NAME}/${MODEL_VERSION}"
```
Expected: response containing `entityIds` array. Extract and store `ENTITY_ID`.

**Test 2 — Verify initial state:**
```bash
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}"
```
Expected: entity in `initialState` as defined in workflow.

**Test 3 — Trigger manual transition:**
```bash
curl -sf -X PUT $AUTH "${ENDPOINT}/api/entity/JSON/${ENTITY_ID}/${TRANSITION_NAME}"
```
Expected: 200 response. Verify new state matches workflow definition.

**Test 4 — Check entity changes:**
```bash
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}/changes"
```
Expected: changes array contains at least one entry (the transition that was just triggered).

**Test 5 — Point-in-time read:**
```bash
BEFORE_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ" -d "1 minute ago" 2>/dev/null || date -u -v-1M +"%Y-%m-%dT%H:%M:%SZ")
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}?pointInTime=${BEFORE_TIME}"
```
Expected: entity in its state before the transition.

Report pass/fail for each test. If any test fails, report the error and suggest running `/cyoda:debug`.

Note: verify exact endpoint paths against the Cyoda OpenAPI spec via `/cyoda:docs`.
