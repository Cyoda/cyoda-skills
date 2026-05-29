---
name: test
description: E2e test a running Cyoda instance. Discovers registered entities and workflows, runs a full automated e2e flow with live progress output, and offers debug observation after results. Also generates reusable test scripts (guided mode).
context: inline
disable-model-invocation: true
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(chmod *) Bash(bash *) Bash(jq *)
---

## Cyoda E2e Test

Reading connection config:
```!
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default"); jq --arg p "$PROFILE" '.profiles[$p] // {"endpoint":"none"}' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo '{"endpoint":"none"}'
```

If `"endpoint":"none"` or config is absent: report *"No Cyoda instance configured. Run `/cyoda:setup` first."* Stop.

**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. If the retry also fails, surface the error to the user. Do not retry on any other error code.

If `.env` equals `production`: report *"⚠️ This will run tests against a PRODUCTION instance. Tests create real entities and trigger real transitions. Proceed? (yes/no)"* Wait for explicit `yes`.

### Mode Selection

Ask: *"Which test mode?
- Guided — I generate a test script you can save and re-run
- Automated — I discover your app's entities and run the full e2e flow now"*

---

### Guided Mode

Generate a populated `smoke-test.sh` from [templates/smoke-test.sh](templates/smoke-test.sh), replacing all three variable defaults with hardcoded values from the user's app: `ENTITY_NAME="<name>"`, `MODEL_VERSION="<version>"`, `TRANSITION_NAME="<transition>"`. No `${VAR:-default}` forms should remain in the generated script.

Show the completed script. Instruct: *"Save this as `smoke-test.sh`, run `chmod +x smoke-test.sh`, then `./smoke-test.sh`"*

---

### Automated Mode

**Step 1 — Discover endpoints:** Invoke `cyoda:docs` to discover the correct API endpoints for: entity model listing, entity schema, entity creation, entity fetch, workflow definition query, transition triggering, and entity changes/audit trail. Do not hardcode or guess any API paths.

**Step 2 — Discover entities:** Using the discovered endpoints, query the running instance for all registered entities and their versions. Print: *"Discovered N entities: [list]"*

If more than 3 entities: *"Found [list]. Which would you like to test? (Enter names or 'all')"* Wait for response.

**Step 3 — For each selected entity, run the e2e flow:**

Print: `"Testing <entity> v<N>..."`

1. Fetch the workflow definition to determine the initial state and available manual transitions.
2. Create an entity instance with a minimal valid payload inferred from the schema.
   - Print: `"  Creating entity... ✓ [id: <id>]"` on success, `"  Creating entity... ✗ <error>"` on failure.
3. Fetch the entity and verify it is in the expected initial state.
   - Print: `"  Initial state: <state> ✓"` or `"  Initial state: <actual> ✗ (expected <expected>)"`.
4. For each manual transition reachable on the happy path from the initial state (if transitions branch, take the first transition listed for that state in the workflow definition):
   - Print: `"  Triggering <transition>..."`
   - Trigger the transition.
   - Fetch the entity and verify the new state matches the workflow definition.
   - Print: `"  State after <transition>: <state> ✓"` or `"  State after <transition>: <actual> ✗ (expected <expected>)"`.
5. On any step failure: print `✗` with actual vs expected, continue remaining steps — do not abort.
6. If an entity has no workflow definition: skip it and note it in the summary.

**Step 4 — Print summary:**

```
Entity       | Transitions tested | Result
-------------|-------------------|-------
<entity>     | N                 | PASS / FAIL (N failed)
```

**Step 5 — Offer debug observation:**

Ask: *"Run debug observation to validate the audit trail? (yes/no)"*

If yes: invoke `cyoda:debug` in observation mode for the last tested entity.
