# cyoda:test Skill Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `cyoda:test` to run inline (visible progress), discover real app entities/workflows via `cyoda:docs`, walk the full e2e happy path with per-step progress output, and offer `cyoda:debug` observation after results.

**Architecture:** Two tasks — rewrite `SKILL.md` (context, automated mode flow), then update `evals.json` (assertions for discovery, progress, debug offer). Guided mode and `smoke-test.sh` template are unchanged. Evals run last to validate the redesign.

**Tech Stack:** Markdown skill files, JSON eval files, Claude Code plugin system.

---

## Task 1: Rewrite `cyoda/skills/test/SKILL.md`

**Files:**
- Modify: `cyoda/skills/test/SKILL.md`

- [ ] **Step 1: Replace SKILL.md with the rewritten content**

Replace the entire file with:

```markdown
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

Generate a populated `smoke-test.sh` from [templates/smoke-test.sh](templates/smoke-test.sh), replacing placeholders with the actual entity name, model version, and transition name from the user's app.

Show the completed script. Instruct: *"Save this as `smoke-test.sh`, run `chmod +x smoke-test.sh`, then `./smoke-test.sh`"*

---

### Automated Mode

**Step 1 — Discover endpoints:** Invoke `cyoda:docs` to discover the correct API endpoints for: entity model listing, entity creation, entity fetch, workflow definition query, transition triggering, and entity changes/audit trail. Do not hardcode or guess any API paths.

**Step 2 — Discover entities:** Using the discovered endpoints, query the running instance for all registered entities and their versions. Print: *"Discovered N entities: [list]"*

If more than 3 entities: *"Found [list]. Which would you like to test? (Enter names or 'all')"* Wait for response.

**Step 3 — For each selected entity, run the e2e flow:**

Print: `"Testing <entity> v<N>..."`

1. Fetch the workflow definition to determine the initial state and available manual transitions.
2. Create an entity instance with a minimal valid payload inferred from the schema.
   - Print: `"  Creating entity... ✓ [id: <id>]"` on success, `"  Creating entity... ✗ <error>"` on failure.
3. Fetch the entity and verify it is in the expected initial state.
   - Print: `"  Initial state: <state> ✓"` or `"  Initial state: <actual> ✗ (expected <expected>)"`.
4. For each manual transition reachable on the happy path from the initial state:
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
```

- [ ] **Step 2: Verify the file looks correct**

```bash
head -10 cyoda/skills/test/SKILL.md
```

Expected: frontmatter shows `context: inline` and `disable-model-invocation: true`.

- [ ] **Step 3: Commit**

```bash
git add cyoda/skills/test/SKILL.md
git commit -m "feat(test): rewrite to inline context with discovery-driven e2e flow"
```

---

## Task 2: Update `cyoda/skills/test/evaluations/evals.json`

**Files:**
- Modify: `cyoda/skills/test/evaluations/evals.json`

- [ ] **Step 1: Replace evals.json with updated content**

Replace the entire file with:

```json
{
  "skill_name": "test",
  "evals": [
    {
      "id": 1,
      "prompt": "/cyoda:test",
      "expected_output": "Asks guided vs automated, in automated mode invokes cyoda:docs first, discovers entities from running instance, runs e2e flow per entity with per-step progress output, prints summary table, offers debug observation",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"
      },
      "assertions": [
        { "id": "reads-config", "text": "Reads active profile from ~/.config/cyoda/cyoda-plugin-config.json for endpoint before running", "type": "behavior" },
        { "id": "asks-mode", "text": "Asks guided vs automated mode", "type": "behavior" },
        { "id": "invokes-docs-first", "text": "In automated mode: invokes cyoda:docs to discover API endpoints before making any API calls", "type": "behavior" },
        { "id": "discovers-entities", "text": "Queries running instance for registered entities rather than hardcoding entity name or transition name", "type": "behavior" },
        { "id": "prints-progress", "text": "Prints per-step progress output (creating entity, initial state, transition result) as it runs", "type": "format" },
        { "id": "prints-summary", "text": "Prints a summary table with entity name, transitions tested, and pass/fail result", "type": "format" },
        { "id": "offers-debug", "text": "After printing results, asks whether to run debug observation", "type": "behavior" },
        { "id": "no-production-without-confirm", "text": "Does NOT run tests against production without explicit confirmation", "type": "behavior" }
      ]
    },
    {
      "id": 2,
      "prompt": "/cyoda:test — guided mode, Order entity with submit transition",
      "expected_output": "Generates a fully populated smoke-test.sh with ENTITY_NAME=order and TRANSITION_NAME=submit — no placeholders remaining — with chmod and run instructions",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"
      },
      "assertions": [
        { "id": "generates-script", "text": "Generates populated smoke-test.sh from template", "type": "behavior" },
        { "id": "fills-entity-name", "text": "Replaces ENTITY_NAME placeholder with 'order'", "type": "format" },
        { "id": "fills-transition-name", "text": "Replaces TRANSITION_NAME placeholder with 'submit'", "type": "format" },
        { "id": "no-placeholders", "text": "Does NOT leave any ${...} placeholders in the generated script", "type": "format" },
        { "id": "provides-run-instructions", "text": "Provides chmod and run instructions", "type": "behavior" },
        { "id": "no-auto-run-in-guided", "text": "Does NOT run tests automatically in guided mode", "type": "behavior" }
      ]
    },
    {
      "id": 3,
      "prompt": "/cyoda:test — automated, instance has 5 entities",
      "expected_output": "Discovers 5 entities, prints the list, asks the user which to test before proceeding",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"
      },
      "assertions": [
        { "id": "discovers-all", "text": "Discovers all 5 registered entities from the running instance", "type": "behavior" },
        { "id": "asks-confirmation", "text": "Asks the user which entities to test when more than 3 are found", "type": "behavior" },
        { "id": "does-not-run-before-confirmation", "text": "Does NOT start the e2e flow before the user has confirmed which entities to test", "type": "behavior" }
      ]
    },
    {
      "id": 4,
      "prompt": "/cyoda:test — automated, one entity has no workflow definition",
      "expected_output": "Skips the entity with no workflow, notes it in the summary, continues testing other entities",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"
      },
      "assertions": [
        { "id": "skips-no-workflow", "text": "Skips the entity that has no workflow definition rather than erroring out", "type": "behavior" },
        { "id": "notes-in-summary", "text": "Notes the skipped entity in the summary output", "type": "format" },
        { "id": "continues-other-entities", "text": "Continues testing the remaining entities after skipping the one with no workflow", "type": "behavior" }
      ]
    },
    {
      "id": 5,
      "prompt": "/cyoda:test — automated, API call returns 401",
      "expected_output": "Detects 401, invokes cyoda:auth to refresh, retries the failing call once",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://api.eu.cyoda.net\",\"token\":\"eyJexpired...\"}}}"
      },
      "assertions": [
        { "id": "invokes-auth-on-401", "text": "Invokes cyoda:auth when an API call returns 401 or 403", "type": "behavior" },
        { "id": "retries-after-refresh", "text": "Retries the failing call once after auth refresh", "type": "behavior" },
        { "id": "surfaces-error-after-second-fail", "text": "Reports the error to the user if the retry also fails", "type": "behavior" }
      ]
    }
  ]
}
```

- [ ] **Step 2: Verify JSON is valid**

```bash
jq . cyoda/skills/test/evaluations/evals.json > /dev/null && echo "valid"
```

Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add cyoda/skills/test/evaluations/evals.json
git commit -m "test(test): update evals for discovery-driven e2e flow"
```

---

## Task 3: Run Evals

**Files:** Read-only — runs existing eval infrastructure.

- [ ] **Step 1: Create eval workspace directory**

```bash
mkdir -p cyoda-evals-workspace/iteration-1/test
```

- [ ] **Step 2: Spawn executor subagents (one per eval, all in parallel background)**

For each of the 5 evals:
- Read `cyoda/skills/test/SKILL.md`
- Simulate the skill executing the eval prompt using the fixture files from the `files` block
- Write transcript to `cyoda-evals-workspace/iteration-1/test/eval-<id>-<slug>/with_skill/outputs/transcript.md`
- Save `total_tokens` and `duration_ms` as `cyoda-evals-workspace/iteration-1/test/eval-<id>-<slug>/with_skill/timing.json`

Eval slugs:
- eval-1: `automated-happy-path`
- eval-2: `guided-mode`
- eval-3: `too-many-entities`
- eval-4: `no-workflow`
- eval-5: `auth-retry`

- [ ] **Step 3: Spawn grader subagents (one per eval, all in parallel background, after executors complete)**

Read grader instructions from `~/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator/agents/grader.md`. Grade each assertion in the eval's `assertions` array against the transcript. Save `grading.json` to the same `with_skill/` dir.

- [ ] **Step 4: Fix null fields and create run-1 structure**

```bash
for f in cyoda-evals-workspace/iteration-1/test/eval-*/with_skill/grading.json; do
  jq '.execution_metrics.total_tool_calls //= 0 | .execution_metrics.output_chars //= 0' "$f" > /tmp/g.json && mv /tmp/g.json "$f"
  mkdir -p "$(dirname $f)/run-1"
  cp "$f" "$(dirname $f)/run-1/grading.json"
  cp "$(dirname $f)/timing.json" "$(dirname $f)/run-1/timing.json" 2>/dev/null || true
done
```

- [ ] **Step 5: Aggregate results**

```bash
cd ~/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator
python3 -m scripts.aggregate_benchmark /Users/user/Dev/cyoda/agent-skills/cyoda-evals-workspace/iteration-1/test --skill-name cyoda-test
```

Expected: benchmark.json and benchmark.md written to the workspace.

- [ ] **Step 6: Generate and open HTML review**

```bash
SC=~/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator
python3 "$SC/eval-viewer/generate_review.py" \
  /Users/user/Dev/cyoda/agent-skills/cyoda-evals-workspace/iteration-1/test \
  --skill-name "cyoda:test" \
  --benchmark /Users/user/Dev/cyoda/agent-skills/cyoda-evals-workspace/iteration-1/test/benchmark.json \
  --static /tmp/cyoda-test-review.html
open /tmp/cyoda-test-review.html
```

Expected: browser opens showing per-eval pass/fail breakdown.
