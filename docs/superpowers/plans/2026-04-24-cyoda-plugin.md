# Cyoda Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `cyoda` Claude Code plugin with 11 skills and plugin scaffold that replaces AI Studio for Cyoda application development.

**Architecture:** Each skill is a self-contained `SKILL.md` + supporting files. No shared code between skills — they coordinate via skill invocation. Connection state is shared via `~/.config/cyoda/cyoda-plugin-config.json` (named profiles, home directory) read at invocation time using dynamic context injection (`!`command``). The plugin follows the `.claude-plugin/plugin.json` standard.

**Tech Stack:** Claude Code plugin format (SKILL.md, YAML frontmatter), JSON (evals, plugin manifest, templates), Bash (dynamic context injection, `allowed-tools`), Markdown (supporting docs)

---

## File Map

```
cyoda/
├── .claude-plugin/plugin.json
├── README.md
├── skills/status/SKILL.md
├── skills/status/evaluations/eval-1-local-connected.json
├── skills/status/evaluations/eval-2-cloud-production.json
├── skills/status/evaluations/eval-3-not-connected.json
├── skills/docs/SKILL.md
├── skills/docs/evaluations/eval-1-cli-installed.json
├── skills/docs/evaluations/eval-2-cli-not-installed.json
├── skills/docs/evaluations/eval-3-synthesize-search-answer.json
├── skills/setup/SKILL.md
├── skills/setup/evaluations/eval-1-local-install.json
├── skills/setup/evaluations/eval-2-cloud-setup.json
├── skills/setup/evaluations/eval-3-already-running.json
├── skills/auth/SKILL.md
├── skills/auth/evaluations/eval-1-dev-env.json
├── skills/auth/evaluations/eval-2-production-confirmed.json
├── skills/auth/evaluations/eval-3-production-declined.json
├── skills/design/SKILL.md
├── skills/design/resources/patterns.md
├── skills/design/evaluations/eval-1-newcomer-chess-app.json
├── skills/design/evaluations/eval-2-experienced-risk-system.json
├── skills/design/evaluations/eval-3-compute-node-optional.json
├── skills/build/SKILL.md
├── skills/build/templates/workflow.json
├── skills/build/templates/entity-model.json
├── skills/build/examples/hello-world.md
├── skills/build/evaluations/eval-1-new-entity.json
├── skills/build/evaluations/eval-2-add-transition.json
├── skills/build/evaluations/eval-3-production-guard.json
├── skills/compute/SKILL.md
├── skills/compute/resources/grpc-patterns.md
├── skills/compute/examples/processor.md
├── skills/compute/examples/criteria.md
├── skills/compute/evaluations/eval-1-processor-implementation.json
├── skills/compute/evaluations/eval-2-criteria-implementation.json
├── skills/compute/evaluations/eval-3-no-compute-needed.json
├── skills/test/SKILL.md
├── skills/test/templates/smoke-test.sh
├── skills/test/evaluations/eval-1-local-smoke-test.json
├── skills/test/evaluations/eval-2-transition-verification.json
├── skills/test/evaluations/eval-3-point-in-time.json
├── skills/debug/SKILL.md
├── skills/debug/evaluations/eval-1-failed-transition.json
├── skills/debug/evaluations/eval-2-entity-history.json
├── skills/debug/evaluations/eval-3-processor-timeout.json
├── skills/migrate/SKILL.md
├── skills/migrate/templates/migration-checklist.md
├── skills/migrate/evaluations/eval-1-full-migration.json
├── skills/migrate/evaluations/eval-2-no-local-instance.json
├── skills/migrate/evaluations/eval-3-import-conflict.json
├── skills/app/SKILL.md
└── skills/app/evaluations/eval-1-newcomer-full-journey.json
    skills/app/evaluations/eval-2-skip-to-build.json
    skills/app/evaluations/eval-3-cloud-first.json
```

---

## Eval Format Standard

> **All eval files use this format.** The per-task eval blocks below were written before the official Anthropic skill-creator format was adopted — treat them as content reference only. The canonical schema is here.

Each skill's evaluations live in a single file per skill: `evaluations/evals.json`.

```json
{
  "skill_name": "<skill-name>",
  "evals": [
    {
      "id": 1,
      "prompt": "The user message that triggers the skill",
      "expected_output": "One-sentence description of the correct response",
      "files": {
        ".cyoda/config": "CYODA_ENDPOINT=http://localhost:8080\nCYODA_ENV=development"
      },
      "assertions": [
        { "id": "assertion-id", "text": "Objectively verifiable check", "type": "behavior" },
        { "id": "assertion-id-2", "text": "Does NOT do X", "type": "behavior" },
        { "id": "assertion-id-3", "text": "Output includes Y", "type": "format" }
      ]
    }
  ]
}
```

**Field guide:**
- `files` — filesystem state to mock before running the eval. Use this to provide `.cyoda/config`, stub responses, or any file the skill reads at invocation. Solves the "needs a running instance" problem for most evals.
- `assertions[].type` — use `behavior` for what the skill does/avoids, `format` for output structure. Subjective quality checks should be `expected_output` prose, not forced assertions.
- `antiPatterns` from the old format become negative `behavior` assertions phrased as "Does NOT…".
- Cover: happy path (id=1), edge case (id=2), failure/guard scenario (id=3).

**Example — `cyoda:status` skill:**

```json
{
  "skill_name": "status",
  "evals": [
    {
      "id": 1,
      "prompt": "What's my Cyoda status?",
      "expected_output": "Reports 'Connected to Local cyoda-go — vX.X.X' without a PRODUCTION marker",
      "files": {
        ".cyoda/config": "CYODA_ENDPOINT=http://localhost:8080\nCYODA_ENV=development"
      },
      "assertions": [
        { "id": "reads-config", "text": "Reads .cyoda/config for endpoint", "type": "behavior" },
        { "id": "calls-health", "text": "Calls health endpoint on localhost", "type": "behavior" },
        { "id": "reports-version", "text": "Reports version number in output", "type": "format" },
        { "id": "no-production-marker", "text": "Does NOT show PRODUCTION warning", "type": "behavior" }
      ]
    },
    {
      "id": 2,
      "prompt": "Check my connection",
      "expected_output": "Reports connection with prominent PRODUCTION marker and version",
      "files": {
        ".cyoda/config": "CYODA_ENDPOINT=https://api.eu.cyoda.net\nCYODA_ENV=production\nCYODA_TOKEN=eyJ..."
      },
      "assertions": [
        { "id": "reads-env", "text": "Reads CYODA_ENV=production from config", "type": "behavior" },
        { "id": "production-marker", "text": "Shows PRODUCTION marker prominently", "type": "format" },
        { "id": "includes-version", "text": "Includes version number", "type": "format" }
      ]
    },
    {
      "id": 3,
      "prompt": "Am I connected to Cyoda?",
      "expected_output": "Reports not connected and directs user to run /cyoda:setup",
      "files": {},
      "assertions": [
        { "id": "detects-missing-config", "text": "Detects missing .cyoda/config", "type": "behavior" },
        { "id": "reports-not-connected", "text": "Reports 'Not connected'", "type": "format" },
        { "id": "suggests-setup", "text": "Directs user to run /cyoda:setup", "type": "behavior" }
      ]
    }
  ]
}
```

---

## Task 1: Plugin Scaffold

**Files:**
- Create: `cyoda/.claude-plugin/plugin.json`
- Create: `cyoda/README.md`

- [ ] **Step 1: Create plugin manifest**

```json
{
  "name": "cyoda",
  "description": "Build, test, and run applications on Cyoda EDBMS. Covers local cyoda-go development, Cyoda Cloud, entity/workflow design, compute nodes, testing, debugging, and lift-and-shift migration.",
  "version": "0.1.0",
  "author": {
    "name": "Cyoda Platform"
  },
  "homepage": "https://docs.cyoda.net/",
  "repository": "https://github.com/Cyoda-platform/cyoda-docs"
}
```

Save to `cyoda/.claude-plugin/plugin.json`.

- [ ] **Step 2: Create README.md**

```markdown
# Cyoda Plugin for Claude Code

Helps you build applications on [Cyoda](https://docs.cyoda.net/) — an Entity Database Management System (EDBMS).

## Skills

| Skill | Purpose |
|---|---|
| `/cyoda:app` | Start here if you're new — walks the full journey |
| `/cyoda:setup` | Install cyoda-go locally or connect to Cyoda Cloud |
| `/cyoda:auth` | Authenticate to Cyoda Cloud (obtain JWT) |
| `/cyoda:design` | Brainstorm entities and workflows for your app |
| `/cyoda:build` | Incrementally build and register entity models and workflows |
| `/cyoda:compute` | Implement compute node processors via gRPC |
| `/cyoda:test` | Smoke-test your running Cyoda instance |
| `/cyoda:debug` | Diagnose failures and browse entity history |
| `/cyoda:migrate` | Lift-and-shift from local cyoda-go to Cyoda Cloud |
| `/cyoda:docs` | Look up Cyoda documentation |
| `/cyoda:status` | Check connection status |

## Connection Config

Skills share connection state via `.cyoda/config` (always gitignored):

```
CYODA_ENDPOINT=http://localhost:8080
CYODA_TOKEN=eyJ...
CYODA_ENV=development
```

Run `/cyoda:setup` then `/cyoda:auth` to populate this file.
```

Save to `cyoda/README.md`.

- [ ] **Step 3: Commit**

```bash
git add cyoda/
git commit -m "feat: scaffold cyoda plugin — manifest and README"
```

---

## Task 2: cyoda:status Skill

**Files:**
- Create: `cyoda/skills/status/SKILL.md`
- Create: `cyoda/skills/status/evaluations/eval-1-local-connected.json`
- Create: `cyoda/skills/status/evaluations/eval-2-cloud-production.json`
- Create: `cyoda/skills/status/evaluations/eval-3-not-connected.json`

- [ ] **Step 1: Check the Cyoda OpenAPI spec for the health/version endpoint**

Fetch https://docs.cyoda.net/openapi/openapi.json and search for endpoints returning version or health info. Note the exact path for use in the SKILL.md. Common candidates: `/api/v1/info`, `/api/version`, `/readyz` (admin port 9091).

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: status
description: Reports current Cyoda connection status. Shows "Connected to Local cyoda-go — vX.X.X", "Connected to Cyoda Cloud — vX.X.X [PRODUCTION]", or "Not connected". Use before any operation requiring an active Cyoda instance.
when_to_use: When the user asks about their Cyoda connection, at session start when Cyoda work is mentioned, or before build/test/migrate operations.
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *)
---

## Cyoda Connection Status

Current config:
```!
cat .cyoda/config 2>/dev/null || echo "CYODA_ENDPOINT=none"
```

Checking reachability:
```!
ENDPOINT=$(grep -E '^CYODA_ENDPOINT=' .cyoda/config 2>/dev/null | cut -d= -f2-);
ENV=$(grep -E '^CYODA_ENV=' .cyoda/config 2>/dev/null | cut -d= -f2-);
if [ -z "$ENDPOINT" ] || [ "$ENDPOINT" = "none" ]; then
  echo "STATUS=not_configured";
else
  RESULT=$(curl -sf --max-time 3 "${ENDPOINT%/}/readyz" 2>/dev/null || echo "unreachable");
  if [ "$RESULT" = "unreachable" ]; then
    echo "STATUS=unreachable ENDPOINT=$ENDPOINT";
  else
    VERSION=$(curl -sf --max-time 3 "${ENDPOINT%/}/api/v1/info" 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4);
    echo "STATUS=connected ENDPOINT=$ENDPOINT VERSION=${VERSION:-unknown} ENV=${ENV:-development}";
  fi;
fi
```

Report based on output:

- `STATUS=not_configured` → **"Not connected to Cyoda — run `/cyoda:setup` to get started"**
- `STATUS=unreachable` → **"Cyoda instance unreachable at {ENDPOINT} — is it running? Try `cyoda health`"**
- `STATUS=connected`, `ENV=production` → **"⚠️ Connected to Cyoda Cloud [PRODUCTION] — v{VERSION}"**
- `STATUS=connected`, endpoint contains `localhost` → **"Connected to Local cyoda-go — v{VERSION}"**
- `STATUS=connected`, cloud endpoint → **"Connected to Cyoda Cloud — v{VERSION}"**

Note: The exact health and version endpoint paths should be verified against the Cyoda OpenAPI spec at https://docs.cyoda.net/openapi/openapi.json.
```

Save to `cyoda/skills/status/SKILL.md`.

- [ ] **Step 3: Write evaluations**

`eval-1-local-connected.json`:
```json
{
  "name": "local-cyoda-go-connected",
  "description": "User has local cyoda-go running and .cyoda/config set to localhost",
  "input": {
    "userMessage": "What's my Cyoda status?"
  },
  "expectedBehavior": [
    "Skill reads .cyoda/config",
    "Calls health endpoint on localhost",
    "Reports 'Connected to Local cyoda-go — vX.X.X'",
    "Does not show PRODUCTION warning"
  ],
  "antiPatterns": [
    "Reporting not connected when instance is running",
    "Showing PRODUCTION marker for local instance"
  ]
}
```

`eval-2-cloud-production.json`:
```json
{
  "name": "cloud-production-instance",
  "description": "User connected to Cyoda Cloud with CYODA_ENV=production",
  "input": {
    "userMessage": "Check my connection"
  },
  "expectedBehavior": [
    "Reads CYODA_ENV=production from config",
    "Reports connection with prominent PRODUCTION marker",
    "Includes version number"
  ],
  "antiPatterns": [
    "Missing production warning",
    "Treating production as development"
  ]
}
```

`eval-3-not-connected.json`:
```json
{
  "name": "no-config-file",
  "description": "User has no .cyoda/config — fresh project",
  "input": {
    "userMessage": "Am I connected to Cyoda?"
  },
  "expectedBehavior": [
    "Detects missing config file",
    "Reports 'Not connected'",
    "Directs user to run /cyoda:setup"
  ],
  "antiPatterns": [
    "Crashing or showing error instead of helpful message",
    "Not suggesting next step"
  ]
}
```

- [ ] **Step 4: Verify by invoking the skill**

In a Claude Code session with the plugin loaded (`claude --plugin-dir ./cyoda`):
```
/cyoda:status
```
Expected: status report based on current `.cyoda/config`.

- [ ] **Step 5: Commit**

```bash
git add cyoda/skills/status/
git commit -m "feat: add cyoda:status skill"
```

---

## Task 3: Remove monitors, add 401/403 retry to API skills

**Rationale:** The background monitor that watched `.cyoda/config` was removed because it fired unexpectedly during active sessions, interrupting the conversation. Token freshness is now handled reactively: any API-calling skill that gets a 401 or 403 invokes `cyoda:auth` to refresh the token and retries once.

**Files:**
- Delete: `cyoda/monitors/monitors.json`
- Delete: `cyoda/monitors/evaluations/` (whole directory)
- Modify: `cyoda/skills/status/SKILL.md`
- Modify: `cyoda/skills/status/evaluations/evals.json` (add eval id=4)
- Modify: `cyoda/skills/build/SKILL.md`
- Modify: `cyoda/skills/build/evaluations/evals.json` (add eval id=11)
- Modify: `cyoda/skills/test/SKILL.md`
- Modify: `cyoda/skills/test/evaluations/evals.json` (add eval id=4)
- Modify: `cyoda/skills/debug/SKILL.md`
- Modify: `cyoda/skills/debug/evaluations/evals.json` (add eval id=4)
- Modify: `cyoda/skills/migrate/SKILL.md`
- Modify: `cyoda/skills/migrate/evaluations/evals.json` (add eval id=5)

---

- [ ] **Step 1: Remove monitors directory**

```bash
rm -rf cyoda/monitors/
```

---

- [ ] **Step 2: Add auth error rule to `cyoda/skills/status/SKILL.md`**

After the closing ` ``` ` of the "Checking reachability and version" code block (before the "Report based on output" section), insert:

```markdown
**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. Do not retry on any other error code.
```

---

- [ ] **Step 3: Add eval id=4 to `cyoda/skills/status/evaluations/evals.json`**

Append to the `"evals"` array (before the closing `]`):

```json
{
  "id": 4,
  "prompt": "What's my Cyoda status?",
  "expected_output": "Detects 401 on health check, invokes cyoda:auth to refresh, then retries the status check",
  "files": {
    ".cyoda/config": "{\"endpoint\": \"https://api.eu.cyoda.net\", \"env\": \"development\", \"token\": \"eyJexpired...\"}"
  },
  "assertions": [
    { "id": "invokes-auth-on-401", "text": "Invokes cyoda:auth when the health check returns 401 or 403", "type": "behavior" },
    { "id": "retries-after-refresh", "text": "Retries the health check once after cyoda:auth completes", "type": "behavior" },
    { "id": "no-unreachable-on-401", "text": "Does NOT report 'unreachable' on a 401 — treats it as an auth error, not a connectivity error", "type": "behavior" }
  ]
}
```

---

- [ ] **Step 4: Add auth error rule to `cyoda/skills/build/SKILL.md`**

After the existing "API rule:" line at the top of the skill body, append to that paragraph:

```markdown
**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. Do not retry on any other error code.
```

---

- [ ] **Step 5: Add eval id=11 to `cyoda/skills/build/evaluations/evals.json`**

Append to the `"evals"` array (after id=10, before the closing `]`):

```json
{
  "id": 11,
  "prompt": "/cyoda:build — add a Product entity",
  "expected_output": "Detects 401 on GET /api/model, invokes cyoda:auth to refresh, retries the model inspection once",
  "files": {
    ".cyoda/config": "{\"endpoint\": \"https://api.eu.cyoda.net\", \"env\": \"development\", \"token\": \"eyJexpired...\"}"
  },
  "assertions": [
    { "id": "invokes-auth-on-401", "text": "Invokes cyoda:auth when any API call returns 401 or 403", "type": "behavior" },
    { "id": "retries-once-after-refresh", "text": "Retries the failed call exactly once after auth refresh", "type": "behavior" },
    { "id": "no-retry-on-other-errors", "text": "Does NOT retry on 404 or 5xx — only on 401/403", "type": "behavior" }
  ]
}
```

---

- [ ] **Step 6: Add auth error rule to `cyoda/skills/test/SKILL.md`**

After the `If "endpoint":"none"` stop condition (before "If `.env` equals `production`"), insert:

```markdown
**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. Do not retry on any other error code.
```

---

- [ ] **Step 7: Add eval id=4 to `cyoda/skills/test/evaluations/evals.json`**

Append to the `"evals"` array (after id=3, before the closing `]`):

```json
{
  "id": 4,
  "prompt": "/cyoda:test",
  "expected_output": "Detects 401 on test API call, invokes cyoda:auth to refresh, retries the failing call once",
  "files": {
    ".cyoda/config": "{\"endpoint\": \"https://api.eu.cyoda.net\", \"env\": \"development\", \"token\": \"eyJexpired...\"}"
  },
  "assertions": [
    { "id": "invokes-auth-on-401", "text": "Invokes cyoda:auth when a test API call returns 401 or 403", "type": "behavior" },
    { "id": "retries-after-refresh", "text": "Retries the failing call once after auth refresh", "type": "behavior" },
    { "id": "surfaces-error-after-second-fail", "text": "Reports the error to the user if the retry also fails, rather than silently dropping it", "type": "behavior" }
  ]
}
```

---

- [ ] **Step 8: Add auth error rule to `cyoda/skills/debug/SKILL.md`**

After the closing ` ``` ` of the dynamic config injection block (before "Are you **debugging a problem**"), insert:

```markdown
**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. Do not retry on any other error code.
```

---

- [ ] **Step 9: Add eval id=4 to `cyoda/skills/debug/evaluations/evals.json`**

Append to the `"evals"` array (after id=3, before the closing `]`):

```json
{
  "id": 4,
  "prompt": "Show me the history for entity abc-123",
  "expected_output": "Detects 401 when fetching entity history, invokes cyoda:auth to refresh, retries the history request once",
  "files": {
    ".cyoda/config": "{\"endpoint\": \"https://api.eu.cyoda.net\", \"env\": \"development\", \"token\": \"eyJexpired...\"}"
  },
  "assertions": [
    { "id": "invokes-auth-on-401", "text": "Invokes cyoda:auth when the entity API call returns 401 or 403", "type": "behavior" },
    { "id": "retries-after-refresh", "text": "Retries the entity history fetch once after auth refresh", "type": "behavior" },
    { "id": "no-not-found-on-401", "text": "Does NOT report 'entity not found' on a 401 — treats it as an auth error", "type": "behavior" }
  ]
}
```

---

- [ ] **Step 10: Add auth error rule to `cyoda/skills/migrate/SKILL.md`**

After the `If not pointing to a local instance` guard (before "### Step 1 — Verify local instance is working"), insert:

```markdown
**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. Do not retry on any other error code.
```

---

- [ ] **Step 11: Add eval id=5 to `cyoda/skills/migrate/evaluations/evals.json`**

Append to the `"evals"` array (after id=4, before the closing `]`):

```json
{
  "id": 5,
  "prompt": "/cyoda:migrate",
  "expected_output": "Detects 401 during export, invokes cyoda:auth to refresh, retries the export call once",
  "files": {
    ".cyoda/config": "{\"endpoint\": \"http://localhost:8080\", \"env\": \"development\", \"token\": \"eyJexpired...\"}"
  },
  "assertions": [
    { "id": "invokes-auth-on-401", "text": "Invokes cyoda:auth when any export or import call returns 401 or 403", "type": "behavior" },
    { "id": "retries-after-refresh", "text": "Retries the failed call exactly once after auth refresh", "type": "behavior" },
    { "id": "no-retry-on-other-errors", "text": "Does NOT retry on 404 or 5xx — only on 401/403", "type": "behavior" }
  ]
}
```

---

- [ ] **Step 12: Run evals for all 5 affected skills**

Use the skill-creator parallel Executor + Grader pipeline (same as Task 14). Run all 5 skills in parallel; within each skill run all evals in parallel (including the new id=4/5/11 evals).

For each skill, spawn:
- **Executor**: receives `SKILL.md` + eval `prompt` + eval `files` → saves output to `eval-workspace/<skill>/eval-<id>/output.md`
- **Grader**: receives `output.md` + `assertions[]` + `expected_output` → saves `{ "id": "...", "passed": true|false, "evidence": "..." }` per assertion to `eval-workspace/<skill>/eval-<id>/grades.json`

Aggregate results into a summary table:

| Skill | Eval | Assertion | Passed | Evidence |
|-------|------|-----------|--------|----------|
| status | 4 | invokes-auth-on-401 | ? | ... |
| build | 11 | retries-once-after-refresh | ? | ... |
| ... | | | | |

Flag every `passed: false`. For each failure: check if `SKILL.md` clearly states the rule; if yes, update the assertion; if not, update `SKILL.md` and re-run that skill's evals only.

---

- [ ] **Step 13: Commit**

```bash
git add cyoda/skills/status/SKILL.md cyoda/skills/status/evaluations/evals.json
git add cyoda/skills/build/SKILL.md cyoda/skills/build/evaluations/evals.json
git add cyoda/skills/test/SKILL.md cyoda/skills/test/evaluations/evals.json
git add cyoda/skills/debug/SKILL.md cyoda/skills/debug/evaluations/evals.json
git add cyoda/skills/migrate/SKILL.md cyoda/skills/migrate/evaluations/evals.json
git rm -r cyoda/monitors/
git commit -m "feat: remove monitor, add 401/403 token-refresh retry to API skills"
```

---

## Task 4: cyoda:docs Skill

**Files:**
- Create: `cyoda/skills/docs/SKILL.md`
- Create: `cyoda/skills/docs/evaluations/eval-1-cli-installed.json`
- Create: `cyoda/skills/docs/evaluations/eval-2-cli-not-installed.json`
- Create: `cyoda/skills/docs/evaluations/eval-3-synthesize-search-answer.json`

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: docs
description: Look up Cyoda documentation. Uses local `cyoda help` (version-specific, preferred for API details) with https://docs.cyoda.net/help/ as fallback. Synthesizes direct answers — never dumps raw output. Auto-invoked when Cyoda API questions arise.
when_to_use: When the user asks how to use a Cyoda API, what an endpoint does, how a concept works, or needs schema/protocol details.
allowed-tools: Bash(cyoda *) Bash(which *)
---

## Cyoda Documentation Lookup

Checking for local cyoda CLI:
```!
which cyoda 2>/dev/null && cyoda help 2>/dev/null | head -50 || echo "CYODA_CLI_NOT_INSTALLED"
```

**If output contains `CYODA_CLI_NOT_INSTALLED`:**

Ask the user once per session: *"Local `cyoda` CLI is not installed. It's recommended for development — run `/cyoda:setup` (local mode) to install it. Would you like to do that now, or should I use the online help at https://docs.cyoda.net/help/ to answer your question?"*

- If user wants to install: invoke `/cyoda:setup` (local mode), then re-invoke this skill.
- If user prefers online help (or already answered "no" earlier in this conversation): fetch `https://docs.cyoda.net/help/index.json` to discover available topics, then fetch `https://docs.cyoda.net/help/<slug>.md` for the relevant topic. URL mapping: `cyoda help A B C` → `https://docs.cyoda.net/help/a/b/c/`. This surface is a mirror of the CLI help, designed for agent access.

**If cyoda CLI is installed:**

1. Use the `cyoda help` output above as the primary source to answer the user's question.
2. If the answer is not fully covered by local help, supplement with web docs: fetch `https://docs.cyoda.net/llms.txt` first to identify the relevant page, then fetch that page directly.
3. For gRPC/schema details, reference: https://github.com/Cyoda-platform/cyoda-docs/tree/main/src/schemas
4. For REST API details, reference: https://docs.cyoda.net/openapi/openapi.json

**Always:**
- Synthesize a direct, specific answer to the question asked
- Never paste raw `cyoda help` output without explanation
- Prefer local CLI output over web docs for API-level specifics
```

Save to `cyoda/skills/docs/SKILL.md`.

- [ ] **Step 2: Write evaluations**

`eval-1-cli-installed.json`:
```json
{
  "name": "cli-installed-api-question",
  "description": "User asks about the search API and cyoda CLI is installed locally",
  "input": {
    "userMessage": "How do I search for entities created in the last 7 days?"
  },
  "expectedBehavior": [
    "Runs cyoda help to get local docs",
    "Synthesizes a direct answer with the correct endpoint and filter syntax",
    "Shows example curl or code snippet",
    "Does not dump raw help output"
  ],
  "antiPatterns": [
    "Pasting raw cyoda help output without synthesis",
    "Saying 'I don't know' when local docs cover it"
  ]
}
```

`eval-2-cli-not-installed.json`:
```json
{
  "name": "cli-not-installed",
  "description": "User asks a Cyoda API question but cyoda CLI is not installed",
  "input": {
    "userMessage": "What's the endpoint to trigger a transition?"
  },
  "expectedBehavior": [
    "Detects CLI is not installed",
    "Asks user whether to install via /cyoda:setup or use the online help at https://docs.cyoda.net/help/",
    "If user says online: fetches /help/index.json to discover topics, then fetches relevant /help/<slug>.md",
    "Synthesizes answer from web help content"
  ],
  "antiPatterns": [
    "Silently falling back to web docs without asking (first time)",
    "Asking again if user already declined install earlier in the conversation",
    "Refusing to help until CLI is installed"
  ]
}
```

`eval-3-synthesize-search-answer.json`:
```json
{
  "name": "synthesize-search-query-answer",
  "description": "User with existing risk management app asks how to query entities by time period",
  "input": {
    "userMessage": "I want to find all applications submitted in Q1 2026 in my Cyoda Cloud instance"
  },
  "expectedBehavior": [
    "Identifies this as a search/query question",
    "Provides the correct search endpoint (direct or async)",
    "Shows how to filter by createdAt date range",
    "Explains sync vs async search trade-offs for large result sets",
    "Includes a concrete curl example"
  ],
  "antiPatterns": [
    "Answering with only conceptual info and no concrete endpoint/example",
    "Suggesting Trino SQL when simple REST search suffices"
  ]
}
```

- [ ] **Step 3: Verify**

```
/cyoda:docs How do I trigger a manual transition via REST?
```

Expected: synthesized answer with endpoint, method, and example.

- [ ] **Step 4: Commit**

```bash
git add cyoda/skills/docs/
git commit -m "feat: add cyoda:docs skill"
```

---

## Task 5: cyoda:setup Skill

**Files:**
- Create: `cyoda/skills/setup/SKILL.md`
- Create: `cyoda/skills/setup/evaluations/eval-1-local-install.json`
- Create: `cyoda/skills/setup/evaluations/eval-2-cloud-setup.json`
- Create: `cyoda/skills/setup/evaluations/eval-3-already-running.json`

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: setup
description: Provision a Cyoda instance. Two modes — local (install and start cyoda-go) or cloud (configure connection to Cyoda Cloud). Run this first before any other cyoda skills.
disable-model-invocation: true
allowed-tools: Bash(brew *) Bash(cyoda *) Bash(curl *) Bash(mkdir *) Bash(tee *) Bash(grep *) Bash(cat *)
---

## Cyoda Instance Setup

Are you setting up a **local** cyoda-go instance or connecting to **Cyoda Cloud**?

Wait for the user to choose, then follow the appropriate path.

---

### Local cyoda-go

**Step 1 — Check if already installed:**
```!
which cyoda 2>/dev/null && cyoda --version 2>/dev/null || echo "NOT_INSTALLED"
```

If already installed, skip to Step 4 (start and verify).

**Step 2 — Install via Homebrew:**

Run:
```bash
brew tap cyoda-platform/cyoda-go
brew install cyoda
```

If the user is not on macOS/Linux with Homebrew, check https://docs.cyoda.net/ for alternative installers.

**Step 3 — Initialize (first time only):**

```bash
cyoda init
```

This creates SQLite storage at `~/.local/share/cyoda/cyoda.db` and writes a starter config.

**Step 4 — Start the server:**

```bash
cyoda
```

The server runs in the foreground. Open a new terminal for subsequent commands.

**Step 5 — Verify:**
```!
curl -sf --max-time 5 http://localhost:8080/readyz 2>/dev/null || curl -sf --max-time 5 http://localhost:9091/readyz 2>/dev/null || echo "UNREACHABLE"
```

If `UNREACHABLE`: ask the user to start cyoda in a separate terminal with `cyoda` and try again.

**Step 6 — Write config:**

```bash
mkdir -p .cyoda
cat > .cyoda/config << 'EOF'
CYODA_ENDPOINT=http://localhost:8080
CYODA_ENV=development
EOF
grep -qxF '.cyoda/config' .gitignore 2>/dev/null || echo '.cyoda/config' >> .gitignore
echo '.cyoda/' >> .gitignore
```

Confirm: **"Local cyoda-go is running. REST on port 8080, gRPC on port 9090. Run `/cyoda:auth` is not needed for local — mock auth is active."**

---

### Cyoda Cloud

**Step 1 — Check for existing account:**

Ask: *"Do you have a Cyoda Cloud account? If not, sign up at https://docs.cyoda.net/ before continuing."*

Wait for confirmation.

**Step 2 — Collect endpoint URL:**

Ask: *"What is your Cyoda Cloud endpoint URL? (e.g., https://api.eu.cyoda.net)"*

**Step 3 — Write endpoint to config:**

```bash
# Claude substitutes the endpoint URL the user provided in Step 2
mkdir -p .cyoda
cat > .cyoda/config << EOF
CYODA_ENDPOINT=${USER_PROVIDED_ENDPOINT}
EOF
grep -qxF '.cyoda/config' .gitignore 2>/dev/null || echo '.cyoda/config' >> .gitignore
echo '.cyoda/' >> .gitignore
```

**Step 4 — Prompt for auth:**

*"Endpoint saved. Now run `/cyoda:auth` to authenticate and obtain your JWT token."*

After login, verify connectivity:
```bash
curl -sf --max-time 5 -H "Authorization: Bearer $(grep CYODA_TOKEN .cyoda/config | cut -d= -f2-)" \
  "$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)/readyz" || echo "Check your endpoint and token"
```
```

Save to `cyoda/skills/setup/SKILL.md`.

- [ ] **Step 2: Write evaluations**

`eval-1-local-install.json`:
```json
{
  "name": "fresh-local-install",
  "description": "User has nothing installed and wants to run cyoda-go locally",
  "input": {
    "userMessage": "/cyoda:setup"
  },
  "expectedBehavior": [
    "Asks local vs cloud",
    "Runs brew install commands",
    "Runs cyoda init",
    "Verifies health endpoint responds",
    "Writes .cyoda/config with localhost endpoint",
    "Adds .cyoda/config to .gitignore",
    "Notes mock auth is active for local"
  ],
  "antiPatterns": [
    "Asking for credentials on local setup",
    "Forgetting to write .cyoda/config",
    "Forgetting to gitignore the config"
  ]
}
```

`eval-2-cloud-setup.json`:
```json
{
  "name": "cloud-connection-setup",
  "description": "User wants to connect to Cyoda Cloud",
  "input": {
    "userMessage": "/cyoda:setup — I want to use Cyoda Cloud"
  },
  "expectedBehavior": [
    "Asks if user has an account",
    "Collects endpoint URL",
    "Writes only CYODA_ENDPOINT (no token yet)",
    "Directs user to /cyoda:auth next",
    "Gitignores .cyoda/config"
  ],
  "antiPatterns": [
    "Asking for credentials during setup (that's login's job)",
    "Completing setup without prompting for login"
  ]
}
```

`eval-3-already-running.json`:
```json
{
  "name": "cyoda-already-installed",
  "description": "User already has cyoda-go installed and running",
  "input": {
    "userMessage": "/cyoda:setup"
  },
  "expectedBehavior": [
    "Detects existing installation",
    "Skips brew install",
    "Verifies health",
    "Updates .cyoda/config if needed",
    "Reports already ready"
  ],
  "antiPatterns": [
    "Re-installing when already installed",
    "Running cyoda init again without --force"
  ]
}
```

- [ ] **Step 3: Verify**

```
/cyoda:setup
```

Choose local. Expected: walks through install steps and writes `.cyoda/config`.

- [ ] **Step 4: Commit**

```bash
git add cyoda/skills/setup/
git commit -m "feat: add cyoda:setup skill"
```

---

## Task 6: cyoda:auth Skill

**Files:**
- Create: `cyoda/skills/auth/SKILL.md`
- Create: `cyoda/skills/auth/evaluations/eval-1-dev-env.json`
- Create: `cyoda/skills/auth/evaluations/eval-2-production-confirmed.json`
- Create: `cyoda/skills/auth/evaluations/eval-3-production-declined.json`

- [ ] **Step 1: Find the OAuth token endpoint**

Fetch the OpenAPI spec at https://docs.cyoda.net/openapi/openapi.json and locate the OAuth 2.0 token endpoint path and required parameters. Note the exact URL pattern for use in the SKILL.md.

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: auth
description: Authenticate to Cyoda Cloud using OAuth 2.0 client credentials. Obtains a JWT token and saves it to .cyoda/config. Includes production safety guard requiring explicit confirmation before storing production credentials.
disable-model-invocation: true
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(tee *) Bash(echo *)
---

## Cyoda Login

Reading current endpoint:
```!
grep -E '^CYODA_ENDPOINT=' .cyoda/config 2>/dev/null | cut -d= -f2- || echo "none"
```

If endpoint is `none`: *"No Cyoda endpoint configured. Run `/cyoda:setup` first."* Stop.

**Step 1 — Confirm environment type:**

Ask: *"Is this a development or production environment?"*

If **production**: display this warning and require explicit confirmation:

> ⚠️ **Security warning**: You are about to store production credentials in `.cyoda/config` on disk. This file will be gitignored, but it remains in plain text on your filesystem. Anyone with access to this machine can read it.
>
> Do you accept this risk? (yes/no)

If user answers anything other than `yes`: stop. Do not write any credentials.

**Step 2 — Collect credentials:**

Ask for `client_id` and `client_secret` (collect separately, one at a time).

Do not echo the secret back in the conversation.

**Step 3 — Obtain JWT token:**

```bash
ENDPOINT=$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)
TOKEN_RESPONSE=$(curl -sf -X POST "${ENDPOINT%/}/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}")
echo "$TOKEN_RESPONSE"
```

Note: Verify the exact OAuth token endpoint path against the Cyoda OpenAPI spec. Common paths: `/oauth/token`, `/auth/token`, `/api/auth/token`.

If the curl fails or returns an error: show the error and stop. Do not write partial credentials.

**Step 4 — Extract and write token:**

```bash
TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
ENV_VALUE="${ENVIRONMENT_CHOICE}"  # development or production

# Update .cyoda/config
grep -v 'CYODA_TOKEN\|CYODA_ENV' .cyoda/config > .cyoda/config.tmp
echo "CYODA_TOKEN=${TOKEN}" >> .cyoda/config.tmp
echo "CYODA_ENV=${ENV_VALUE}" >> .cyoda/config.tmp
mv .cyoda/config.tmp .cyoda/config

grep -qxF '.cyoda/config' .gitignore 2>/dev/null || echo '.cyoda/config' >> .gitignore
```

**Step 5 — Confirm:**

Report: *"Authenticated successfully. Token written to `.cyoda/config`. Run `/cyoda:status` to verify the connection."*

If `CYODA_ENV=production`: add prominent reminder — *"⚠️ You are now connected to a PRODUCTION instance. Changes made via `/cyoda:build` will affect live data."*
```

Save to `cyoda/skills/auth/SKILL.md`.

- [ ] **Step 3: Write evaluations**

`eval-1-dev-env.json`:
```json
{
  "name": "dev-environment-login",
  "description": "User logs into a development Cyoda Cloud instance",
  "input": {
    "userMessage": "/cyoda:auth"
  },
  "expectedBehavior": [
    "Asks dev vs production",
    "Collects client_id and client_secret",
    "Calls OAuth token endpoint",
    "Writes token and CYODA_ENV=development to .cyoda/config",
    "Confirms success",
    "Does not show production warning"
  ],
  "antiPatterns": [
    "Echoing the client_secret in the conversation",
    "Writing credentials without asking dev vs production first"
  ]
}
```

`eval-2-production-confirmed.json`:
```json
{
  "name": "production-login-confirmed",
  "description": "User explicitly confirms production credential storage",
  "input": {
    "userMessage": "/cyoda:auth — production environment, I accept the risk"
  },
  "expectedBehavior": [
    "Shows security warning",
    "Requires explicit 'yes'",
    "After confirmation: collects credentials and writes token",
    "Writes CYODA_ENV=production",
    "Shows prominent production reminder after success"
  ],
  "antiPatterns": [
    "Skipping the warning for production",
    "Accepting any response other than explicit 'yes'"
  ]
}
```

`eval-3-production-declined.json`:
```json
{
  "name": "production-login-declined",
  "description": "User declines to store production credentials",
  "input": {
    "userMessage": "/cyoda:auth — production, but I'm not sure about storing credentials"
  },
  "expectedBehavior": [
    "Shows security warning",
    "User responds with something other than 'yes'",
    "Skill stops — does not write any credentials",
    "Suggests alternatives (use env var, use cyoda CLI directly)"
  ],
  "antiPatterns": [
    "Writing credentials after a non-yes response",
    "Not stopping when user declines"
  ]
}
```

- [ ] **Step 4: Commit**

```bash
git add cyoda/skills/auth/
git commit -m "feat: add cyoda:auth skill with production safety guard"
```

---

## Task 7: cyoda:design Skill + Patterns Resource

**Files:**
- Create: `cyoda/skills/design/SKILL.md`
- Create: `cyoda/skills/design/resources/patterns.md`
- Create: `cyoda/skills/design/evaluations/eval-1-newcomer-chess-app.json`
- Create: `cyoda/skills/design/evaluations/eval-2-experienced-risk-system.json`
- Create: `cyoda/skills/design/evaluations/eval-3-compute-node-optional.json`

- [ ] **Step 1: Write patterns.md**

```markdown
# Common Cyoda Workflow Patterns

Reference this file when designing entity workflows. Present relevant patterns during the domain brainstorm.

## Approval Flow

Entity moves from submitted → under_review → approved/rejected. Manual transitions for review actions. Criteria guard the approval transition (e.g., reviewer must be assigned).

States: `draft` → `submitted` → `under_review` → `approved` | `rejected`
Key transitions: `submit` (manual), `assign` (manual), `approve` (manual + criteria), `reject` (manual)

## Scheduled Retry / Timeout

After entering a waiting state, automatically transition to `timed_out` after a delay if no response arrives.

Use a scheduled processor: `{ "type": "scheduled", "config": { "delayMs": 3600000, "transition": "timeout" } }`

## Auto-Transition Cascade

Entity auto-advances through several states as soon as criteria are met, without manual intervention. Useful for processing pipelines.

States: `received` → `validated` → `enriched` → `ready`
All transitions are automatic with criteria on each.

Safety: Cyoda limits cascades to 100 steps and 10 visits per state (CYODA_MAX_STATE_VISITS).

## Multi-Workflow Model

Entity participates in multiple independent workflows (e.g., a lifecycle workflow AND a compliance workflow). Platform evaluates active workflows in order, uses first whose criterion matches.

Use when: different aspects of an entity's lifecycle need independent state machines.

## Saga-Style Coordination

Multiple entities coordinate across a process. Each entity manages its own state; a coordinator entity tracks the overall saga state and triggers transitions on participants.

Note: Cyoda does not have built-in saga support — implement by having compute nodes create/transition related entities via REST API calls.

## External Event Trigger

Incoming external events (webhooks, messages) drive entity transitions. Register a message-based transition that fires when a CloudEvent of a specific type arrives.
```

Save to `cyoda/skills/design/resources/patterns.md`.

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: design
description: Brainstorm and design a Cyoda application. Guides entity modeling, workflow design, and compute node decisions following Cyoda philosophy. Auto-invoked when the user describes an app idea or asks how to model their domain in Cyoda.
when_to_use: When the user describes an application they want to build on Cyoda, asks how to model their domain, or needs help designing entities and workflows.
---

## Cyoda Application Design

### Phase 1 — Orientation (skip if user is already familiar with Cyoda)

Assess whether the user needs orientation: if they haven't described Cyoda concepts (entities, workflows, transitions) in their message, give a brief orientation first.

**Orientation (2-3 sentences maximum):**

Cyoda is an Entity Database Management System (EDBMS). Instead of storing rows in tables, you define **entities** — domain objects like Orders or Users — each with a **workflow**: a set of named states and the transitions between them. Nothing in Cyoda is overwritten; every transition produces a new immutable revision, so you always have the full history of every entity. Think of it as a database where every record is a state machine.

After orientation, ask: *"Does that make sense? Ready to design your app?"*

### Phase 2 — Domain Brainstorm

Ask one question at a time. Wait for the answer before asking the next.

**Q1:** *"What are the main domain objects in your application that have an independent lifecycle — things that change over time on their own clock?"*

For each entity identified, continue:

**Q2:** *"For [entity name]: what states does it move through from creation to completion? (e.g., for an Order: draft → submitted → processing → shipped → delivered)"*

**Q3:** *"For each transition: what triggers it? Manual action by a user, an incoming event/message, a time delay, or automatically when a condition is met?"*

**Q4:** *"Do any transitions need to call external code — to validate data, call a third-party API, or run a calculation? If yes, that's where a compute node comes in. But many apps don't need them at all."*

Present the compute node option neutrally — it is **optional**. Many workflows work purely with Cyoda's built-in criteria and processors.

**Q5:** *"Are you building this as a prototype (discover mode — schema evolves automatically) or production (lock mode — schema is fixed)?"*

### Phase 3 — Output Design Summary

Present a structured summary:

```
Entities:
  - [EntityName]: states=[...], key transitions=[...]
  - ...

Compute nodes needed: yes/no
  - If yes: which transitions call external code and why

Schema mode: discover (prototype) / lock (production)

Suggested first increment for /cyoda:build: [EntityName] with [minimal workflow]
```

Reference patterns from [patterns.md](resources/patterns.md) when relevant (e.g., if the user describes an approval process, mention the Approval Flow pattern).

Offer to proceed: *"Ready to build this? Run `/cyoda:build` to start registering these models in your running Cyoda instance."*
```

Save to `cyoda/skills/design/SKILL.md`.

- [ ] **Step 3: Write evaluations**

`eval-1-newcomer-chess-app.json`:
```json
{
  "name": "newcomer-chess-app-design",
  "description": "User with no Cyoda knowledge wants to build a chess app with online rooms and game history",
  "input": {
    "userMessage": "I want to build a chess app where players can create rooms and games are saved in Cyoda Cloud"
  },
  "expectedBehavior": [
    "Detects newcomer (no Cyoda concepts mentioned)",
    "Gives brief EDBMS/entity/workflow orientation",
    "Asks about domain objects one question at a time",
    "Identifies Room, Game, Move as likely entities",
    "Asks about states for each entity",
    "Asks about transitions and triggers",
    "Notes compute nodes are optional",
    "Produces structured design summary"
  ],
  "antiPatterns": [
    "Skipping orientation for a newcomer",
    "Asking multiple questions at once",
    "Forcing compute nodes into the design",
    "Generating workflow JSON before design is confirmed"
  ]
}
```

`eval-2-experienced-risk-system.json`:
```json
{
  "name": "experienced-user-risk-system",
  "description": "Experienced Cyoda user wants to design a risk management entity",
  "input": {
    "userMessage": "I need to model a risk assessment entity with states for pending, under_review, and approved. It needs a scheduled timeout."
  },
  "expectedBehavior": [
    "Skips orientation (user clearly knows Cyoda)",
    "Asks clarifying questions about transitions and triggers",
    "Recognizes scheduled timeout pattern",
    "References the scheduled retry pattern from patterns.md",
    "Asks about compute node needs"
  ],
  "antiPatterns": [
    "Giving orientation to an experienced user",
    "Missing the scheduled timeout pattern reference"
  ]
}
```

`eval-3-compute-node-optional.json`:
```json
{
  "name": "compute-node-optional-presentation",
  "description": "Design session where compute nodes are not needed",
  "input": {
    "userMessage": "I want a simple document approval workflow — nothing fancy"
  },
  "expectedBehavior": [
    "Asks about domain objects and states",
    "When asking about compute nodes, presents them as optional",
    "Accepts 'no compute nodes needed' gracefully",
    "Does not push compute nodes if not needed",
    "Produces design summary without compute nodes"
  ],
  "antiPatterns": [
    "Insisting on compute nodes when not needed",
    "Framing compute nodes as required"
  ]
}
```

- [ ] **Step 4: Commit**

```bash
git add cyoda/skills/design/
git commit -m "feat: add cyoda:design skill with patterns resource"
```

---

## Task 8: cyoda:build Skill + Templates

**Files:**
- Create: `cyoda/skills/build/SKILL.md`
- Create: `cyoda/skills/build/templates/workflow.json`
- Create: `cyoda/skills/build/templates/entity-model.json`
- Create: `cyoda/skills/build/examples/hello-world.md`
- Create: `cyoda/skills/build/evaluations/eval-1-new-entity.json`
- Create: `cyoda/skills/build/evaluations/eval-2-add-transition.json`
- Create: `cyoda/skills/build/evaluations/eval-3-production-guard.json`

- [ ] **Step 1: Check the Cyoda OpenAPI spec for model/workflow endpoints**

Fetch https://docs.cyoda.net/openapi/openapi.json and note:
- `GET` endpoint to list existing entity models
- `POST` endpoint to create/import a workflow for a model
- `POST` endpoint to create an entity
- `PUT` endpoint to trigger a transition
- The exact URL patterns (e.g., `/api/model/{entityName}/{modelVersion}/workflow/import`)

- [ ] **Step 2: Write workflow.json template**

```json
{
  "workflows": [
    {
      "version": "1",
      "name": "${WORKFLOW_NAME}",
      "initialState": "${INITIAL_STATE}",
      "active": true,
      "states": {
        "${INITIAL_STATE}": {
          "transitions": [
            {
              "name": "${TRANSITION_NAME}",
              "next": "${NEXT_STATE}",
              "manual": true
            }
          ]
        },
        "${NEXT_STATE}": {}
      }
    }
  ]
}
```

Save to `cyoda/skills/build/templates/workflow.json`.

- [ ] **Step 3: Write entity-model.json template**

```json
{
  "entityName": "${ENTITY_NAME}",
  "modelVersion": "1",
  "schemaMode": "discover"
}
```

Save to `cyoda/skills/build/templates/entity-model.json`.

- [ ] **Step 4: Write hello-world.md example**

```markdown
# Hello World — Minimal Cyoda App

The minimal first increment: one entity (`hello`) with a two-state workflow.

## Workflow config

```json
{
  "workflows": [
    {
      "version": "1",
      "name": "hello-wf",
      "initialState": "draft",
      "active": true,
      "states": {
        "draft": {
          "transitions": [
            { "name": "submit", "next": "submitted", "manual": true }
          ]
        },
        "submitted": {}
      }
    }
  ]
}
```

## Register

```bash
curl -X POST http://localhost:8080/api/model/hello/1/workflow/import \
  -H 'Content-Type: application/json' \
  -d @workflow.json
```

## Create entity

```bash
curl -X POST http://localhost:8080/api/entity/JSON/hello/1 \
  -H 'Content-Type: application/json' \
  -d '{"message": "Hello, Cyoda!"}'
```

## Trigger transition

```bash
curl -X PUT http://localhost:8080/api/entity/JSON/${ENTITY_ID}/submit
```
```

Save to `cyoda/skills/build/examples/hello-world.md`.

- [ ] **Step 5: Write SKILL.md**

```markdown
---
name: build
description: Incrementally build Cyoda entity models and workflows. Inspects the running instance, brainstorms the next change, generates config, and registers it. Supports new entities, new states, new transitions, criteria, and schema mode changes.
disable-model-invocation: true
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(echo *) Bash(tee *)
---

## Cyoda Incremental Build

Reading connection config:
```!
cat .cyoda/config 2>/dev/null || echo "CYODA_ENDPOINT=none"
```

If `CYODA_ENDPOINT=none`: *"No Cyoda instance configured. Run `/cyoda:setup` first."* Stop.

If `CYODA_ENV=production`: display **"⚠️ Operating against a PRODUCTION Cyoda instance. All changes will affect live data. You will be asked to confirm before each registration."**

### Step 1 — Inspect current state

```!
ENDPOINT=$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)
TOKEN=$(grep CYODA_TOKEN .cyoda/config 2>/dev/null | cut -d= -f2-)
AUTH_HEADER=$([ -n "$TOKEN" ] && echo "Authorization: Bearer $TOKEN" || echo "X-Mock-Auth: true")
curl -sf -H "$AUTH_HEADER" "${ENDPOINT%/}/api/model" 2>/dev/null || echo "[]"
```

Show the user what entity models currently exist in the instance.

If this is a fresh instance with no models: suggest starting with the hello world increment. Reference [examples/hello-world.md](examples/hello-world.md) for the minimal starting point.

### Step 2 — Brainstorm next increment

Ask: *"What would you like to add or change? Options:*
- *New entity model with workflow*
- *New state to an existing entity*
- *New transition between states*
- *Add criteria to a transition*
- *Add a processor to a transition*
- *Lock schema (move from discover to strict mode)*
- *Something else"*

Wait for the user's choice.

### Step 3 — Clarify and generate config

Based on the chosen increment, ask the minimum clarifying questions (one at a time) and generate the JSON config. Show it to the user:

*"Here's the config I'll register:"*
```json
[generated config here]
```
*"Does this look right? (yes to proceed, or describe changes)"*

Use [templates/workflow.json](templates/workflow.json) and [templates/entity-model.json](templates/entity-model.json) as starting points.

### Step 4 — Register

If `CYODA_ENV=production`: *"You're about to register this change to PRODUCTION. Type 'confirm' to proceed."* Wait for explicit `confirm`.

```bash
ENDPOINT=$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)
TOKEN=$(grep CYODA_TOKEN .cyoda/config 2>/dev/null | cut -d= -f2-)
AUTH_HEADER=$([ -n "$TOKEN" ] && echo "-H 'Authorization: Bearer $TOKEN'" || echo "")

# Example for workflow import — adjust endpoint per the Cyoda OpenAPI spec:
curl -X POST ${AUTH_HEADER} \
  -H 'Content-Type: application/json' \
  -d '${GENERATED_CONFIG}' \
  "${ENDPOINT%/}/api/model/${ENTITY_NAME}/${MODEL_VERSION}/workflow/import"
```

Show the response. If error: delegate to `/cyoda:debug` for diagnosis.

### Step 5 — Verify and loop

*"Registration complete. Run `/cyoda:test` to verify, or tell me the next increment to add."*

Repeat from Step 2 for the next increment.

For API details on any endpoint, invoke `/cyoda:docs`.
```

Save to `cyoda/skills/build/SKILL.md`.

- [ ] **Step 6: Write evaluations**

`eval-1-new-entity.json`:
```json
{
  "name": "register-new-entity-workflow",
  "description": "User wants to register a new Order entity with a draft→submitted workflow",
  "input": {
    "userMessage": "/cyoda:build — add an Order entity with draft and submitted states"
  },
  "expectedBehavior": [
    "Reads .cyoda/config",
    "Inspects existing models",
    "Asks clarifying questions (transition name, triggers)",
    "Generates workflow JSON",
    "Shows config for user confirmation",
    "Registers via POST to workflow import endpoint",
    "Reports success and suggests /cyoda:test"
  ],
  "antiPatterns": [
    "Registering without showing config for confirmation",
    "Not checking for production env before registering",
    "Skipping inspection step"
  ]
}
```

`eval-2-add-transition.json`:
```json
{
  "name": "add-transition-to-existing-workflow",
  "description": "User wants to add a 'cancel' transition to an existing Order workflow",
  "input": {
    "userMessage": "/cyoda:build — add a cancel transition to the Order entity"
  },
  "expectedBehavior": [
    "Inspects existing Order entity models",
    "Shows current states/transitions",
    "Asks which state 'cancel' transitions from",
    "Generates updated workflow config",
    "Shows diff/update for confirmation",
    "Registers the update"
  ],
  "antiPatterns": [
    "Creating a brand new entity instead of modifying",
    "Not showing current state before proposing changes"
  ]
}
```

`eval-3-production-guard.json`:
```json
{
  "name": "production-registration-guard",
  "description": "User tries to register a change against a production instance",
  "input": {
    "userMessage": "/cyoda:build — add approval state to RiskAssessment"
  },
  "expectedBehavior": [
    "Detects CYODA_ENV=production",
    "Shows PRODUCTION warning at start",
    "Generates config and shows for confirmation as normal",
    "Before registering: requires explicit 'confirm' from user",
    "Only registers after 'confirm' received"
  ],
  "antiPatterns": [
    "Registering to production without explicit confirmation",
    "Blocking the build loop entirely for production — just adds confirmation step"
  ]
}
```

- [ ] **Step 7: Commit**

```bash
git add cyoda/skills/build/
git commit -m "feat: add cyoda:build skill with templates and examples"
```

---

## Task 9: cyoda:compute Skill + Resources

**Files:**
- Create: `cyoda/skills/compute/SKILL.md`
- Create: `cyoda/skills/compute/resources/grpc-patterns.md`
- Create: `cyoda/skills/compute/examples/processor.md`
- Create: `cyoda/skills/compute/examples/criteria.md`
- Create: `cyoda/skills/compute/evaluations/eval-1-processor-implementation.json`
- Create: `cyoda/skills/compute/evaluations/eval-2-criteria-implementation.json`
- Create: `cyoda/skills/compute/evaluations/eval-3-no-compute-needed.json`

- [ ] **Step 1: Fetch gRPC schemas**

Fetch the schema index at https://github.com/Cyoda-platform/cyoda-docs/tree/main/src/schemas and note:
- The CloudEvents envelope format
- `CalculationMemberJoinEvent` fields
- `CalculationMemberGreetEvent` fields
- `EntityProcessorCalculationRequest` fields
- `EntityProcessorCalculationResponse` fields
- `EntityCriteriaCalculationRequest` fields
- `EntityCriteriaCalculationResponse` fields

Use these exact field names in all examples below.

- [ ] **Step 2: Write grpc-patterns.md**

```markdown
# Cyoda Compute Node gRPC Patterns

## Connection Lifecycle

All compute nodes connect via a persistent bidirectional gRPC stream to `CloudEventsService.startStreaming`.

### 1. Join Handshake

Send `CalculationMemberJoinEvent` with your tags:
```json
{
  "type": "CalculationMemberJoinEvent",
  "tags": ["my-processor-tag", "environment-tag"]
}
```

Receive `CalculationMemberGreetEvent` with your assigned `memberId`. Store this ID.

### 2. Keep-Alive

Respond to periodic heartbeat probes within the configured timeout (default 60s). Failure to respond causes disconnection.

### 3. Reconnection

Implement exponential backoff on disconnection:
- Attempt 1: wait 1s
- Attempt 2: wait 2s
- Attempt 3: wait 4s
- Cap at 60s

On reconnect, send `CalculationMemberJoinEvent` again (new `memberId` will be assigned).

## Tag-Based Routing

The platform routes requests only to members whose registered tags form a **superset** of the tags configured on the workflow processor/criterion.

Example: if workflow processor has tags `["payment", "eu"]`, your compute node must register with at least `["payment", "eu"]` (plus any additional tags you want).

Tags are case-insensitive.

## Authentication

Include a JWT bearer token in gRPC metadata headers:
```
Authorization: Bearer eyJ...
```

## Thread Safety

All `StreamObserver.onNext()` calls must be synchronized. The gRPC stream is not thread-safe.

## Idempotency

Use the `requestId` field in every request to deduplicate retries. If you receive a request with a `requestId` you've already processed, return the same response.
```

Save to `cyoda/skills/compute/resources/grpc-patterns.md`.

- [ ] **Step 3: Write processor.md example**

```markdown
# Compute Node Processor Implementation

## What you receive

`EntityProcessorCalculationRequest`:
- `requestId` — deduplicate with this
- `entityId` — ID of the entity being processed
- `entityData` — current entity JSON payload
- `transitionName` — the transition that triggered this processor

## What you return

`EntityProcessorCalculationResponse`:
- `requestId` — echo the same requestId
- `entityId` — echo the same entityId
- `entityData` — modified entity JSON (or unchanged if no modification needed)
- `success` — boolean

## Pseudocode (language-agnostic)

```
function handleProcessorRequest(request):
  if alreadyProcessed(request.requestId):
    return cachedResponse(request.requestId)

  entity = parseJSON(request.entityData)

  // your business logic here
  entity.processedAt = now()
  entity.status = "enriched"

  response = {
    requestId: request.requestId,
    entityId: request.entityId,
    entityData: toJSON(entity),
    success: true
  }

  cacheResponse(request.requestId, response)
  return response
```

## Timeout

Complete the response within 60 seconds (default). For long operations, use async processing and return a "processing started" response, then trigger a transition when complete.
```

Save to `cyoda/skills/compute/examples/processor.md`.

- [ ] **Step 4: Write criteria.md example**

```markdown
# Compute Node Criteria Implementation

## What you receive

`EntityCriteriaCalculationRequest`:
- `requestId` — deduplicate with this
- `entityId` — ID of the entity being evaluated
- `entityData` — current entity JSON payload
- `criteriaName` — the criteria being evaluated

## What you return

`EntityCriteriaCalculationResponse`:
- `requestId` — echo the same requestId
- `entityId` — echo the same entityId
- `result` — boolean (true = criteria met, transition may fire)

## Pseudocode

```
function handleCriteriaRequest(request):
  if alreadyEvaluated(request.requestId):
    return cachedResponse(request.requestId)

  entity = parseJSON(request.entityData)

  // your boolean logic here
  result = entity.amount > 1000 AND entity.currency == "EUR"

  return {
    requestId: request.requestId,
    entityId: request.entityId,
    result: result
  }
```
```

Save to `cyoda/skills/compute/examples/criteria.md`.

- [ ] **Step 5: Write SKILL.md**

```markdown
---
name: compute
description: Guide implementation of Cyoda compute nodes — external gRPC processors and criteria services. Language-agnostic. Covers connection lifecycle, tag routing, processor and criteria patterns, and production requirements. Auto-invoked when compute node implementation is discussed.
when_to_use: When the user needs to implement a compute node processor or criteria service, asks about gRPC integration, or needs to connect external code to Cyoda workflows.
---

## Cyoda Compute Node Implementation

Compute nodes are **optional** — many Cyoda workflows work entirely with built-in processors and criteria. Only add a compute node when you need custom logic that Cyoda cannot express natively.

### Do you need a compute node?

A compute node is needed when a workflow transition requires:
- Calling an external API or service
- Running custom validation or calculation logic
- Modifying entity data in a way built-in processors don't support

If your workflow only needs state changes, simple field criteria, or scheduled transitions — you likely don't need a compute node.

### Implementation Guide

Refer to the detailed patterns reference: [resources/grpc-patterns.md](resources/grpc-patterns.md)

**Connection steps:**
1. Connect to `CloudEventsService.startStreaming` via gRPC
2. Send `CalculationMemberJoinEvent` with your tags — see [grpc-patterns.md](resources/grpc-patterns.md)
3. Receive `CalculationMemberGreetEvent` with your `memberId`
4. Handle incoming requests (processors or criteria)
5. Maintain keep-alive, implement reconnection

**For processor implementation:** see [examples/processor.md](examples/processor.md)
**For criteria implementation:** see [examples/criteria.md](examples/criteria.md)

### Authentication

Use the JWT token from `.cyoda/config`:
```!
grep CYODA_TOKEN .cyoda/config 2>/dev/null | cut -d= -f2- || echo "no token — local mock auth"
```
Include as bearer token in gRPC metadata: `Authorization: Bearer {token}`

For local cyoda-go with mock auth, authentication may not be required — check with `/cyoda:docs`.

### Schema Details

For exact field names in request/response messages, use `/cyoda:docs` to fetch the current gRPC schemas from https://github.com/Cyoda-platform/cyoda-docs/tree/main/src/schemas

### Production Requirements

- Idempotency: deduplicate using `requestId`
- Thread safety: synchronize all stream writes
- Timeout: respond within 60 seconds
- Reconnection: exponential backoff (see grpc-patterns.md)
- Monitoring: track request latency, keep-alive intervals, reconnection count
```

Save to `cyoda/skills/compute/SKILL.md`.

- [ ] **Step 6: Write evaluations**

`eval-1-processor-implementation.json`:
```json
{
  "name": "processor-implementation-guidance",
  "description": "User needs to implement a processor that enriches entity data by calling an external API",
  "input": {
    "userMessage": "I need to implement a processor that calls our pricing API when an order transitions to submitted"
  },
  "expectedBehavior": [
    "Explains the gRPC connection lifecycle",
    "Shows how to register with the right tags",
    "Provides processor request/response pattern",
    "Notes idempotency requirement via requestId",
    "Mentions 60s timeout and suggests async for slow operations",
    "Points to grpc-patterns.md and processor.md examples"
  ],
  "antiPatterns": [
    "Providing language-specific code (skill is language-agnostic)",
    "Framing compute node as required when it's optional",
    "Omitting idempotency guidance"
  ]
}
```

`eval-2-criteria-implementation.json`:
```json
{
  "name": "criteria-implementation-guidance",
  "description": "User needs a criteria function that checks if an entity meets a complex condition",
  "input": {
    "userMessage": "I need to guard a transition with a check that the entity's amount is over 10000 and it's been validated by our fraud system"
  },
  "expectedBehavior": [
    "Explains criteria vs built-in criteria options",
    "Shows criteria request/response pattern",
    "Notes boolean return semantics",
    "Points to criteria.md example"
  ],
  "antiPatterns": [
    "Not explaining when built-in criteria could suffice",
    "Generating language-specific code"
  ]
}
```

`eval-3-no-compute-needed.json`:
```json
{
  "name": "compute-node-not-needed",
  "description": "User asks about compute nodes but their use case doesn't require one",
  "input": {
    "userMessage": "Do I need a compute node for my order approval workflow? Transitions are triggered by users clicking buttons."
  },
  "expectedBehavior": [
    "Assesses the use case",
    "Explains that manual transitions don't need compute nodes",
    "Explains what would require a compute node",
    "Concludes: no compute node needed for this case"
  ],
  "antiPatterns": [
    "Recommending a compute node when one is not needed",
    "Not explaining when compute nodes ARE needed for future reference"
  ]
}
```

- [ ] **Step 7: Commit**

```bash
git add cyoda/skills/compute/
git commit -m "feat: add cyoda:compute skill with gRPC patterns and examples"
```

---

## Task 10: cyoda:test Skill + Template

**Files:**
- Create: `cyoda/skills/test/SKILL.md`
- Create: `cyoda/skills/test/templates/smoke-test.sh`
- Create: `cyoda/skills/test/evaluations/eval-1-local-smoke-test.json`
- Create: `cyoda/skills/test/evaluations/eval-2-transition-verification.json`
- Create: `cyoda/skills/test/evaluations/eval-3-point-in-time.json`

- [ ] **Step 1: Write smoke-test.sh template**

```bash
#!/usr/bin/env bash
# Cyoda smoke test — edit ENTITY_NAME, MODEL_VERSION, and TRANSITION_NAME
set -euo pipefail

ENDPOINT="${CYODA_ENDPOINT:-http://localhost:8080}"
TOKEN="${CYODA_TOKEN:-}"
AUTH_HEADER=$([ -n "$TOKEN" ] && echo "-H 'Authorization: Bearer $TOKEN'" || echo "")
ENTITY_NAME="${ENTITY_NAME:-my-entity}"
MODEL_VERSION="${MODEL_VERSION:-1}"
TRANSITION_NAME="${TRANSITION_NAME:-submit}"

echo "=== Cyoda Smoke Test ==="
echo "Endpoint: $ENDPOINT"
echo "Entity: $ENTITY_NAME v$MODEL_VERSION"
echo ""

# 1. Create entity
echo "--- Creating entity..."
RESPONSE=$(curl -sf -X POST $AUTH_HEADER \
  -H 'Content-Type: application/json' \
  -d '{"test": true}' \
  "${ENDPOINT}/api/entity/JSON/${ENTITY_NAME}/${MODEL_VERSION}")
ENTITY_ID=$(echo "$RESPONSE" | grep -o '"entityIds":\["[^"]*"' | cut -d'"' -f4)
echo "Created entity: $ENTITY_ID"

# 2. Verify initial state
echo "--- Checking initial state..."
STATE=$(curl -sf $AUTH_HEADER "${ENDPOINT}/api/entity/${ENTITY_ID}" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
echo "Initial state: $STATE"

# 3. Trigger transition
echo "--- Triggering transition: $TRANSITION_NAME..."
curl -sf -X PUT $AUTH_HEADER "${ENDPOINT}/api/entity/JSON/${ENTITY_ID}/${TRANSITION_NAME}"
echo "Transition triggered"

# 4. Verify new state
echo "--- Checking new state..."
NEW_STATE=$(curl -sf $AUTH_HEADER "${ENDPOINT}/api/entity/${ENTITY_ID}" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
echo "New state: $NEW_STATE"

echo ""
echo "=== PASS ==="
```

Save to `cyoda/skills/test/templates/smoke-test.sh`.

- [ ] **Step 2: Write SKILL.md**

Note: this skill uses `context: fork` — the SKILL.md content becomes the task for a forked subagent.

```markdown
---
name: test
description: Smoke-test a running Cyoda instance. Generates and runs tests for entity creation, transitions, state verification, and point-in-time history. Runs in an isolated subagent to keep test output out of the main conversation.
disable-model-invocation: true
context: fork
agent: general-purpose
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(chmod *) Bash(bash *)
---

## Cyoda Smoke Test

Reading connection config:
```!
cat .cyoda/config 2>/dev/null || echo "CYODA_ENDPOINT=none"
```

If `CYODA_ENDPOINT=none`: report *"No Cyoda instance configured. Run `/cyoda:setup` first."* Stop.

If `CYODA_ENV=production`: report *"⚠️ This will run tests against a PRODUCTION instance. Tests create real entities and trigger real transitions. Proceed? (yes/no)"* Wait for explicit `yes`.

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
ENDPOINT=$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)
TOKEN=$(grep CYODA_TOKEN .cyoda/config 2>/dev/null | cut -d= -f2-)
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
```

Save to `cyoda/skills/test/SKILL.md`.

- [ ] **Step 3: Write evaluations**

`eval-1-local-smoke-test.json`:
```json
{
  "name": "local-smoke-test-automated",
  "description": "User runs automated smoke test against local cyoda-go",
  "input": {
    "userMessage": "/cyoda:test"
  },
  "expectedBehavior": [
    "Reads .cyoda/config for endpoint",
    "Asks guided vs automated",
    "In automated mode: creates entity, verifies state, triggers transition, checks new state",
    "Reports pass/fail per test",
    "Suggests /cyoda:debug on failure"
  ],
  "antiPatterns": [
    "Running tests against production without confirmation",
    "Not checking .cyoda/config before running"
  ]
}
```

`eval-2-transition-verification.json`:
```json
{
  "name": "transition-state-verification",
  "description": "User wants to verify their workflow transitions work correctly",
  "input": {
    "userMessage": "/cyoda:test — guided mode, Order entity with submit transition"
  },
  "expectedBehavior": [
    "Generates populated smoke-test.sh with ENTITY_NAME=order, TRANSITION_NAME=submit",
    "Shows complete script with no placeholders remaining",
    "Provides chmod and run instructions"
  ],
  "antiPatterns": [
    "Leaving ${ENTITY_NAME} placeholders in the generated script",
    "Running tests automatically in guided mode"
  ]
}
```

`eval-3-point-in-time.json`:
```json
{
  "name": "point-in-time-verification",
  "description": "User wants to verify point-in-time query returns correct historical state",
  "input": {
    "userMessage": "/cyoda:test — I want to check that point-in-time queries work"
  },
  "expectedBehavior": [
    "Runs the transition test first (creates history)",
    "Then queries entity at a timestamp before the transition",
    "Verifies the historical state matches pre-transition state"
  ],
  "antiPatterns": [
    "Skipping the point-in-time test",
    "Testing point-in-time before creating any history"
  ]
}
```

- [ ] **Step 4: Commit**

```bash
git add cyoda/skills/test/
git commit -m "feat: add cyoda:test skill with smoke-test template"
```

---

## Task 11: cyoda:debug Skill

**Files:**
- Create: `cyoda/skills/debug/SKILL.md`
- Create: `cyoda/skills/debug/evaluations/eval-1-failed-transition.json`
- Create: `cyoda/skills/debug/evaluations/eval-2-entity-history.json`
- Create: `cyoda/skills/debug/evaluations/eval-3-processor-timeout.json`

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: debug
description: Diagnose Cyoda failures and observe entity history. Two modes — debugging (fix problems) and observation (audit trail, point-in-time lookup). Auto-invoked when transition failures, processor errors, or entity history questions arise.
when_to_use: When a transition fails, a processor throws an error, an entity is in an unexpected state, connectivity is broken, or when investigating entity history and audit trails.
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *)
---

## Cyoda Debug and Observation

Reading connection config:
```!
cat .cyoda/config 2>/dev/null || echo "CYODA_ENDPOINT=none"
```

Are you **debugging a problem** or **observing entity history**?

---

### Debugging Mode

Identify the failure category and follow the relevant path:

#### Failed Transition

1. Fetch the entity and check current state:
```bash
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}"
```
2. Check if the transition is valid from the current state (compare against workflow definition)
3. Check criteria: if the transition has criteria, evaluate them manually
4. Look at entity changes for previous errors:
```bash
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}/changes"
```
5. If a processor is attached, check processor execution logs

#### Processor Error

1. Check gRPC connectivity: is your compute node registered?
2. Check tag routing: do the node's registered tags form a superset of the transition's required tags?
3. Check timeout: did the processor respond within 60s?
4. Check response format: does it include `requestId` and `entityId`?
5. Check idempotency: is the processor handling duplicate `requestId` correctly?

#### Schema Rejection

1. Check schema mode: discover (widening) vs lock (strict)
2. In discover mode: type conflicts cause polymorphic fields — check what happened
3. In lock mode: compare incoming entity fields against the locked schema
4. Use `/cyoda:docs` for schema management API details

#### Connectivity Issues

1. Check `.cyoda/config` has correct `CYODA_ENDPOINT`
2. For cloud: check `CYODA_TOKEN` is not expired — re-run `/cyoda:auth` if needed
3. Test endpoint directly:
```!
ENDPOINT=$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)
curl -sf --max-time 5 "${ENDPOINT}/readyz" || echo "UNREACHABLE"
```

---

### Observation Mode

Investigate an entity's history for audit, compliance, or investigation purposes.

**Browse entity lifecycle:**
```bash
ENDPOINT=$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)
TOKEN=$(grep CYODA_TOKEN .cyoda/config 2>/dev/null | cut -d= -f2-)
AUTH=$([ -n "$TOKEN" ] && echo "-H 'Authorization: Bearer $TOKEN'" || echo "")

# Entity change history
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}/changes"
```

**Point-in-time state lookup:**
```bash
# What state was this entity in at a specific time?
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}?pointInTime=2026-01-15T10:00:00Z"
```

**Questions to answer with observation:**
- Which transitions fired and when?
- Which processors ran for each transition?
- What was the entity's state at time T?
- Has this entity been in an error state before?

For deeper audit data (who changed what, when), use `/cyoda:docs` to look up the audit endpoints.
```

Save to `cyoda/skills/debug/SKILL.md`.

- [ ] **Step 2: Write evaluations**

`eval-1-failed-transition.json`:
```json
{
  "name": "failed-transition-diagnosis",
  "description": "User reports a transition is not firing as expected",
  "input": {
    "userMessage": "My 'approve' transition isn't firing — the entity just stays in under_review"
  },
  "expectedBehavior": [
    "Asks for entity ID",
    "Fetches current entity state",
    "Checks if 'approve' transition is valid from under_review",
    "Checks criteria attached to the approve transition",
    "Checks processor logs if processor is attached",
    "Provides specific diagnosis, not generic advice"
  ],
  "antiPatterns": [
    "Generic debugging advice without checking actual entity state",
    "Not checking criteria as a cause"
  ]
}
```

`eval-2-entity-history.json`:
```json
{
  "name": "entity-history-observation",
  "description": "User wants to audit the full lifecycle of a specific entity",
  "input": {
    "userMessage": "Show me the full history of entity abc-123 — I need to audit what happened to it"
  },
  "expectedBehavior": [
    "Switches to observation mode",
    "Calls entity history endpoint for abc-123",
    "Presents the transition history in readable format",
    "Shows states, timestamps, and processor invocations",
    "Offers to do point-in-time lookup if needed"
  ],
  "antiPatterns": [
    "Treating an audit request as a debugging problem",
    "Not showing the actual history data"
  ]
}
```

`eval-3-processor-timeout.json`:
```json
{
  "name": "processor-timeout-diagnosis",
  "description": "User's compute node processor is timing out",
  "input": {
    "userMessage": "My processor keeps timing out — transitions hang for 60 seconds then fail"
  },
  "expectedBehavior": [
    "Identifies timeout as the root cause",
    "Explains 60s default timeout",
    "Suggests async processing pattern for long-running operations",
    "Checks tag routing to ensure processor is receiving requests",
    "Points to grpc-patterns.md for reconnection guidance"
  ],
  "antiPatterns": [
    "Not mentioning the async processing option for long operations",
    "Suggesting increasing timeout without explaining the pattern"
  ]
}
```

- [ ] **Step 3: Commit**

```bash
git add cyoda/skills/debug/
git commit -m "feat: add cyoda:debug skill with observation mode"
```

---

## Task 12: cyoda:migrate Skill + Template

**Files:**
- Create: `cyoda/skills/migrate/SKILL.md`
- Create: `cyoda/skills/migrate/templates/migration-checklist.md`
- Create: `cyoda/skills/migrate/evaluations/eval-1-full-migration.json`
- Create: `cyoda/skills/migrate/evaluations/eval-2-no-local-instance.json`
- Create: `cyoda/skills/migrate/evaluations/eval-3-import-conflict.json`

- [ ] **Step 1: Write migration-checklist.md template**

```markdown
# Cyoda Lift-and-Shift Checklist

## Pre-Migration

- [ ] Local cyoda-go instance is running (`cyoda health`)
- [ ] Cyoda Cloud account exists
- [ ] All entity models and workflows working locally (run `/cyoda:test` to verify)
- [ ] Application code does NOT hardcode `localhost:8080` — uses `CYODA_ENDPOINT` from config

## Export from Local

- [ ] List all entity models: `GET /api/model`
- [ ] Export each workflow: `GET /api/model/{name}/{version}/workflow`
- [ ] Save exported configs to `migration/` directory

## Cyoda Cloud Setup

- [ ] Run `/cyoda:setup` (cloud mode) — endpoint configured
- [ ] Run `/cyoda:auth` — JWT token obtained
- [ ] Run `/cyoda:status` — confirm cloud connection

## Import to Cloud

- [ ] Import each workflow: `POST /api/model/{name}/{version}/workflow/import`
- [ ] Verify models exist in cloud: `GET /api/model`

## Verification

- [ ] Run `/cyoda:test` against cloud endpoint
- [ ] All smoke tests pass
- [ ] Point-in-time queries work

## App Config Update

- [ ] Update application environment config to point to cloud endpoint
- [ ] Update auth token handling in application
- [ ] Deploy updated application
```

Save to `cyoda/skills/migrate/templates/migration-checklist.md`.

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: migrate
description: Lift-and-shift a Cyoda application from local cyoda-go to Cyoda Cloud. Exports entity models and workflows from local, sets up cloud instance, imports, and verifies. No code changes required — same API surface on both tiers.
disable-model-invocation: true
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(mkdir *) Bash(tee *)
---

## Cyoda Lift-and-Shift Migration

This migrates your entity models and workflows from local cyoda-go to Cyoda Cloud. Your application code does not change — just the `CYODA_ENDPOINT` and auth config.

Reading current local config:
```!
cat .cyoda/config 2>/dev/null || echo "CYODA_ENDPOINT=none"
```

If not pointing to a local instance: *"This skill migrates FROM local cyoda-go. Your current config points to a non-local endpoint. Are you sure you want to proceed?"*

### Step 1 — Verify local instance is working

```bash
ENDPOINT=$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)
curl -sf --max-time 5 "${ENDPOINT}/readyz" || echo "UNREACHABLE"
```

If unreachable: *"Start local cyoda-go first (`cyoda`), then re-run this skill."* Stop.

Suggest running `/cyoda:test` against local before migrating to confirm everything works.

### Step 2 — Export entity models and workflows

```bash
mkdir -p migration
ENDPOINT=$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)

# List all models
MODELS=$(curl -sf "${ENDPOINT}/api/model")
echo "$MODELS" | tee migration/models.json

# For each model, export workflow (run for each entity name and version)
curl -sf "${ENDPOINT}/api/model/${ENTITY_NAME}/${MODEL_VERSION}/workflow/export" \
  | tee migration/${ENTITY_NAME}_${MODEL_VERSION}_workflow.json
```

Show the user what was exported.

### Step 3 — Set up Cyoda Cloud

*"Now let's connect to Cyoda Cloud. I'll invoke `/cyoda:setup` (cloud mode)."*

Invoke `cyoda:setup` for cloud setup, then `cyoda:auth` for authentication.

After setup: re-read `.cyoda/config` to confirm cloud endpoint is active.

### Step 4 — Import to cloud

```bash
ENDPOINT=$(grep CYODA_ENDPOINT .cyoda/config | cut -d= -f2-)
TOKEN=$(grep CYODA_TOKEN .cyoda/config | cut -d= -f2-)

# Import each workflow
curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d @migration/${ENTITY_NAME}_${MODEL_VERSION}_workflow.json \
  "${ENDPOINT}/api/model/${ENTITY_NAME}/${MODEL_VERSION}/workflow/import"
```

Repeat for each exported workflow. Show success/failure per import.

### Step 5 — Verify

Invoke `/cyoda:test` against the cloud endpoint. All tests should pass identically to local.

### Step 6 — Update app config

*"Migration complete. Update your application to use:*
- *`CYODA_ENDPOINT`: {cloud endpoint}*
- *`CYODA_TOKEN`: (from `/cyoda:auth`)*

*The API surface is identical — no code changes needed."*

Show [templates/migration-checklist.md](templates/migration-checklist.md) as a reference.
```

Save to `cyoda/skills/migrate/SKILL.md`.

- [ ] **Step 3: Write evaluations**

`eval-1-full-migration.json`:
```json
{
  "name": "full-local-to-cloud-migration",
  "description": "User has working local cyoda-go app and wants to move to Cyoda Cloud",
  "input": {
    "userMessage": "/cyoda:migrate"
  },
  "expectedBehavior": [
    "Verifies local instance is running",
    "Exports all entity models and workflows to migration/ directory",
    "Invokes cyoda:setup (cloud mode) then cyoda:auth",
    "Imports each workflow to cloud",
    "Runs /cyoda:test against cloud",
    "Instructs user to update app config"
  ],
  "antiPatterns": [
    "Migrating without verifying local instance first",
    "Skipping /cyoda:test after import",
    "Not exporting before switching .cyoda/config to cloud"
  ]
}
```

`eval-2-no-local-instance.json`:
```json
{
  "name": "migration-without-local-instance",
  "description": "User tries to migrate but local cyoda-go is not running",
  "input": {
    "userMessage": "/cyoda:migrate"
  },
  "expectedBehavior": [
    "Detects local instance is unreachable",
    "Tells user to start cyoda-go first",
    "Stops gracefully — does not attempt export"
  ],
  "antiPatterns": [
    "Attempting export when local is unreachable",
    "Silently proceeding to cloud setup without local data"
  ]
}
```

`eval-3-import-conflict.json`:
```json
{
  "name": "workflow-already-exists-in-cloud",
  "description": "Entity model already exists in Cyoda Cloud — potential conflict during import",
  "input": {
    "userMessage": "/cyoda:migrate — my order entity already exists in cloud with an old workflow"
  },
  "expectedBehavior": [
    "Checks what already exists in cloud before importing",
    "Shows the conflict to the user",
    "Asks whether to overwrite or skip",
    "Proceeds based on user choice"
  ],
  "antiPatterns": [
    "Silently overwriting existing cloud workflows",
    "Failing without asking the user"
  ]
}
```

- [ ] **Step 4: Commit**

```bash
git add cyoda/skills/migrate/
git commit -m "feat: add cyoda:migrate skill with migration checklist"
```

---

## Task 13: cyoda:app Skill

**Files:**
- Create: `cyoda/skills/app/SKILL.md`
- Create: `cyoda/skills/app/evaluations/eval-1-newcomer-full-journey.json`
- Create: `cyoda/skills/app/evaluations/eval-2-skip-to-build.json`
- Create: `cyoda/skills/app/evaluations/eval-3-cloud-first.json`

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: app
description: Start here if you're new to Cyoda. Walks through the full development journey — Cyoda orientation, app design, instance setup, incremental build, and testing. Experienced users can invoke individual skills directly.
disable-model-invocation: true
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

If you're already familiar with Cyoda, skip ahead: `/cyoda:design`, `/cyoda:build`, `/cyoda:setup`, etc.

---

### Step 1 — Design your app

Let's figure out what entities and workflows your app needs.

Invoke `/cyoda:design` — describe your application and I'll guide you through the domain model.

*(After design is complete, continue here.)*

---

### Step 2 — Set up your Cyoda instance

First, check if you're already connected:

Invoke `/cyoda:status`. If already connected, confirm with the user whether to use that environment and skip to Step 3.

If not connected, present both options as co-equal:

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
```

Save to `cyoda/skills/app/SKILL.md`.

- [ ] **Step 2: Write evaluations**

`eval-1-newcomer-full-journey.json`:
```json
{
  "name": "newcomer-full-journey",
  "description": "Brand new user with no Cyoda knowledge starts with cyoda:app",
  "input": {
    "userMessage": "/cyoda:app I want to build a task management app"
  },
  "expectedBehavior": [
    "Gives brief Cyoda orientation",
    "Directs to /cyoda:design for domain brainstorm",
    "After design: guides to /cyoda:setup",
    "After setup: guides to /cyoda:build",
    "After build: guides to /cyoda:test",
    "Offers /cyoda:migrate when ready for cloud"
  ],
  "antiPatterns": [
    "Skipping orientation for a newcomer",
    "Trying to design AND build in the same skill invocation",
    "Not guiding step-by-step"
  ]
}
```

`eval-2-skip-to-build.json`:
```json
{
  "name": "experienced-user-skips-to-build",
  "description": "Experienced Cyoda user invokes cyoda:app but already has a design",
  "input": {
    "userMessage": "/cyoda:app — I already know Cyoda, just want to start building"
  },
  "expectedBehavior": [
    "Notes experienced users can skip to individual skills",
    "Points directly to /cyoda:build",
    "Does not force through orientation or design"
  ],
  "antiPatterns": [
    "Forcing the full journey on an experienced user",
    "Giving orientation when user says they already know Cyoda"
  ]
}
```

`eval-3-cloud-first.json`:
```json
{
  "name": "cloud-first-no-local-install",
  "description": "User wants to build for Cyoda Cloud without installing cyoda-go locally",
  "input": {
    "userMessage": "/cyoda:app — I want to use Cyoda Cloud, not install anything locally"
  },
  "expectedBehavior": [
    "Accepts cloud-first approach",
    "Guides to /cyoda:setup (cloud mode) then /cyoda:auth",
    "Does not insist on local cyoda-go installation",
    "Full journey works with cloud endpoint"
  ],
  "antiPatterns": [
    "Insisting on local installation before cloud use",
    "Skipping auth guidance for cloud setup"
  ]
}
```

- [ ] **Step 3: Commit**

```bash
git add cyoda/skills/app/
git commit -m "feat: add cyoda:app newcomer orchestrator skill"
```

---

## Task 14: Eval Suite

**Goal:** Verify all 11 skills behave correctly against their eval assertions. Uses the Anthropic skill-creator parallel Executor + Grader pipeline — no running Cyoda instance required for most evals (environment is mocked via `files[]`).

- [ ] **Step 1: Confirm eval files use the canonical format**

All `evaluations/evals.json` files must follow the [Eval Format Standard](#eval-format-standard) above. If any skill still has the old per-file format (`expectedBehavior` / `antiPatterns`), migrate it first.

- [ ] **Step 2: Run evals — parallel Executor + Grader per skill**

For each of the 11 skills, spawn two parallel subagents:

**Executor** — receives:
- The skill's `SKILL.md` content
- The eval's `prompt` as the user message
- The eval's `files` as mock filesystem state

Saves full skill output to `eval-workspace/<skill>/eval-<id>/output.md`.

**Grader** — receives:
- `output.md` from the Executor
- The eval's `assertions[]` and `expected_output`

For each assertion, records `{ "id": "...", "passed": true|false, "evidence": "..." }`.
Saves to `eval-workspace/<skill>/eval-<id>/grades.json`.

Run all 11 skills in parallel. Within each skill, run all evals in parallel.

- [ ] **Step 3: Collect and review results**

Aggregate all `grades.json` files into a summary table:

| Skill | Eval | Assertion | Passed | Evidence |
|-------|------|-----------|--------|----------|
| status | 1 | reads-config | ✓ | Calls `cat .cyoda/config` |
| status | 1 | no-production-marker | ✓ | No ⚠️ in output |
| build | 3 | production-guard | ✗ | Registered without waiting for 'confirm' |
| ... | | | | |

Flag every `passed: false` for immediate fix.

- [ ] **Step 4: Iterate on failures**

For each failing assertion:
1. Is the expected behavior clearly specified in `SKILL.md`? If not — update `SKILL.md`, re-run.
2. Is `SKILL.md` correct but the assertion wrong? Update the assertion, re-run.
3. Re-run only the affected skill's evals after each fix.

- [ ] **Step 5: Smoke-check plugin loading**

```bash
claude --plugin-dir ./cyoda
```

In the session:
```
/help
```

Expected: all 11 skills appear under the `cyoda` namespace:
`cyoda:status`, `cyoda:docs`, `cyoda:setup`, `cyoda:auth`, `cyoda:design`, `cyoda:build`, `cyoda:compute`, `cyoda:test`, `cyoda:debug`, `cyoda:migrate`, `cyoda:app`

- [ ] **Step 6: Final commit**

```bash
git add cyoda/
git commit -m "feat: complete cyoda plugin — 11 skills, scaffold, eval suite passing"
```

---

## Post-Launch Improvements (2026-04-29)

Identified from real user session (`_developer/conversation.md`). All changes applied to spec, skill files, and evals.

### 1. Q5 — Discover vs lock mode explanation (`cyoda:design`)

**Problem:** Users didn't understand what discover/lock mode meant, where it applied, or whether they could switch later.

**Fix:** Q5 now explains both modes in plain terms (discover = schema evolves automatically; lock = schema fixed, mismatches rejected), and states that discover→lock switch is supported.

### 2. Status-first check in `cyoda:app`

**Problem:** Step 2 asked "local or cloud?" without checking if Cyoda was already configured, leaving users who weren't sure to say "I don't know if I have a Cyoda instance running."

**Fix:** Step 2 now invokes `/cyoda:status` first. If already connected, confirms with user. Only asks local/cloud if not connected.

### 3. Schema export missing in `cyoda:migrate`

**Problem:** Step 2 exported workflows but not JSON Schema (field definitions), causing incomplete migrations. User had to notice and ask.

**Fix:** Step 2 now exports both workflow and JSON Schema via `GET /api/model/export/JSON_SCHEMA/{entity}/{version}` for each entity, and confirms both files exist before proceeding.

### 4. M2M credential explanation in `cyoda:auth`

**Problem:** Skill asked for `client_id`/`client_secret` without explaining what they are or where to get them.

**Fix:** Step 2 now explains M2M credentials (machine-to-machine, identify the application not a user), asks if user already has them, and notes that credentials may be deleted on environment redeploy.

### 5. Correct endpoint format in `cyoda:setup`

**Problem:** Cloud step 1 pointed to `https://docs.cyoda.net/` for sign-up (wrong) and used `https://api.eu.cyoda.net` as the endpoint example (wrong format).

**Fix:** Cloud step 1 now shows a coming soon notice for managed environments. Endpoint example updated to correct format: `https://client-<hash>-<env>.eu.cyoda.net`. Users who already have a provisioned endpoint can continue by entering it directly.

### 6. Cloud credential guidance (`cyoda:auth` + `cyoda:setup`)

**Problem:** No guidance on how to obtain M2M credentials when cloud self-service is unavailable.

**Fix:** Both skills now explain that Cyoda Cloud credential self-service is coming soon and direct users to contact the Cyoda team to get a `client_id` and `client_secret`. Also covers the post-redeploy case where credentials may need to be recreated by contacting the team.

### 7. Proactive `cyoda help` lookup in `cyoda:build` Step 4

**Problem:** Step 4 showed a hardcoded curl example for workflow import without first establishing the entity model. Claude attempted the wrong sequence, received 404s, and only consulted `cyoda help` after failure.

**Fix:** Step 4 now runs `cyoda help models` + `cyoda help workflows` as a mandatory first sub-step before issuing any curl commands. The skill retains conceptual descriptions (create model → import workflow → lock) but no hardcoded endpoint paths. `Bash(cyoda *)` added to `allowed-tools`. Eval #4 added asserting docs are consulted before any POST.

---

## Post-Launch Improvements (2026-05-01)

Identified from real user session (`_developer/conversation.md`). Three recurring failures observed when building a sample Cyoda application. All changes applied to skill files and evals.

### 1. Correct OAuth endpoint and Basic auth in `cyoda:auth`

**Problem:** Step 3 listed several possible OAuth endpoint paths ("Common paths: /oauth/token, /auth/token, /api/auth/token"), causing Claude to iterate through 6+ paths before finding the correct one. The Cyoda Cloud OAuth endpoint requires credentials in the `Authorization: Basic` header (Base64-encoded `client_id:client_secret`), not in the request body.

**Fix:** Step 3 now uses the known-good pattern as the primary attempt: `POST {endpoint}/api/oauth/token` with `Authorization: Basic base64(client_id:client_secret)` header and `grant_type=client_credentials` in the form body (no credentials in body). Vague "try these paths" note replaced with a self-correction rule: "If this returns 4xx/5xx, run `cyoda help config auth` (or fetch `https://docs.cyoda.net/help/config/auth.md` if CLI is absent) — do NOT try alternate paths." Added eval #5 asserting Basic auth header and `/api/oauth/token` on first attempt.

### 2. Model creation before workflow import in `cyoda:build`

**Problem:** The `hello-world.md` example and Step 4 guidance implied Claude could call `POST /api/model/{entity}/1/workflow/import` as the first API call. On a fresh instance with no model, this returns 404. The `entity-model.json` template documented `{"entityName": "...", "schemaMode": "discover"}` — a format matching no real Cyoda API endpoint.

**Fix:** `hello-world.md` rewritten with the correct 3-step flow: (1) `POST /api/entity/JSON/{entity}/1` with a sample payload to auto-create the model in discover mode, (2) `POST /api/model/{entity}/1/workflow/import` with workflow JSON, (3) trigger a state transition. `entity-model.json` deleted and replaced with `sample-entity.json` containing `{"field1": "example", "field2": 0}` — the actual body for creating a model in discover mode. Added eval #5 asserting sample entity POST precedes workflow import.

### 3. Discover mode as default in `cyoda:build`

**Problem:** Step 2 brainstorm menu listed "Lock schema" as a standard option. Claude locked the schema after posting minimal sample data. When the application later posted richer entities, Cyoda rejected fields not in the locked schema (`BAD_REQUEST: unexpected field not present in model`).

**Fix:** "Lock schema" removed from the Step 2 brainstorm menu. Discover-mode note added: "Schema stays in **discover mode** during development — Cyoda infers it automatically from the entities you post. Only consider locking when you're confident all fields are known and you're moving to production." Step 4 self-correction rule added: "If any API call returns 4xx/5xx, run `cyoda help models` before retrying — do not guess alternate endpoints." Added eval #6 asserting no lock suggestion during a normal development build session.

---

## Post-Launch Improvements (2026-05-02)

Identified from real user session (`_developer/conversation.md`). Three recurring failures observed when building a sample Cyoda chat SPA. All changes applied to skill files and evals.

### 1. URL guessing in `cyoda:build`

**Problem:** The build skill guessed API URL patterns (e.g. `/api/model`, `/api/v1/entity-model`, `/model/`, `/api/model/export/JSON/SIMPLE_VIEW/{entity}/1`) before checking the spec, causing multiple 404 cycles before finding the correct paths.

**Fix:** Added a mandatory API rule at the top of `SKILL.md`: "Never construct or guess an API URL not explicitly listed in this skill. For any other endpoint, invoke `cyoda:docs` first." The self-correction rule in Step 4 changed from "run `cyoda help models`" to "invoke `cyoda:docs`" — which handles the binary-not-found case gracefully via `cyoda:docs`'s own web fallback. Added eval #7 asserting no URL guessing for non-listed endpoints, and eval #8 asserting `cyoda:docs` is invoked on 4xx rather than retrying with guessed paths.

### 2. Model version handling in `cyoda:build`

**Problem:** API calls hardcoded version `1` (e.g. `/api/entity/JSON/{entity}/1`). The `1` is the model version — if an entity already exists, blindly using version 1 may conflict with an existing model or miss a newer version.

**Fix:** Step 1 now explicitly notes to capture the version number from the `GET /api/model` response. Step 2 adds a version decision prompt when the target entity already exists: "Update existing version N, or create a new version N+1?" New entities default to version 1. All subsequent API calls use the resolved `{version}` variable. Updated design doc to reflect `{version}` instead of `1` in endpoint examples. Added eval #9 asserting the version decision is surfaced when an entity already exists.

---

## Post-Launch Improvements (2026-05-04)

### 1. Remove monitor, add reactive 401/403 token refresh to API skills

**Problem:** `monitors/monitors.json` ran a background polling loop watching `.cyoda/config` for changes. When the config file changed (e.g., after `cyoda:auth` or `cyoda:setup`), it injected "Cyoda config updated — connection status may have changed" into the active conversation. This fired at unexpected moments during sessions, interrupting the conversation flow.

The monitor's intended value was token freshness — ensuring Claude knew when credentials changed. But skills already re-read `.cyoda/config` via dynamic context injection at invocation time, so the monitor added noise without adding real freshness guarantees. The actual failure case it should have guarded against (expired JWT mid-session) was not handled by file-watching at all.

**Fix:** Removed `cyoda/monitors/` entirely. Added an auth error rule to the five skills that make authenticated API calls (`cyoda:status`, `cyoda:build`, `cyoda:test`, `cyoda:debug`, `cyoda:migrate`): if any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token and retry the request once. If the retry also fails, surface the error to the user. Added eval #4 (or #11 for build, #5 for migrate) to each affected skill asserting the 401/403 retry behavior. See Task 3 for the full implementation steps.

---

## Post-Launch Improvements (2026-05-07)

### 1. Move config to home directory with named profiles

**Problem:** Connection config (endpoint, JWT token, env) was stored in a project-local `.cyoda/config` file. Even though gitignored, users risked accidentally committing JWT tokens to the repository — a common mistake when `.gitignore` is misconfigured or the file is explicitly staged.

**Fix:** Replace `.cyoda/config` with `~/.config/cyoda/cyoda-plugin-config.json` — a home-directory file that is never git-tracked. The file uses a named-profile format with an `"active"` pointer, allowing multiple Cyoda connections (e.g. local dev + cloud production) without file-switching:

```json
{
  "active": "default",
  "profiles": {
    "default": {
      "endpoint": "http://localhost:8080",
      "env": "development"
    },
    "prod": {
      "endpoint": "https://client-abc123-prod.eu.cyoda.net",
      "token": "eyJ...",
      "env": "production"
    }
  }
}
```

**Files to update:**

- [ ] **`cyoda/README.md`** — Update Connection Config section to reference `~/.config/cyoda/cyoda-plugin-config.json` and explain the profile format.

- [ ] **`cyoda/skills/setup/SKILL.md`** — Add profile selection step (list existing profiles, ask for name). Update write commands to use `~/.config/cyoda/cyoda-plugin-config.json`. Remove all `.gitignore` steps.

- [ ] **`cyoda/skills/auth/SKILL.md`** — Add profile selection step. Update read/write commands to use `~/.config/cyoda/cyoda-plugin-config.json`. Update security warning (no gitignore mention). Remove `.gitignore` steps. Update description frontmatter.

- [ ] **`cyoda/skills/status/SKILL.md`** — Update dynamic context injection to read active profile. Update status messages to include `[profile: <name>]`.

- [ ] **`cyoda/skills/build/SKILL.md`** — Update all three dynamic context injection blocks to read active profile from `~/.config/cyoda/cyoda-plugin-config.json`.

- [ ] **`cyoda/skills/test/SKILL.md`** — Update dynamic context injection to read active profile.

- [ ] **`cyoda/skills/debug/SKILL.md`** — Update dynamic context injection blocks and connectivity section to reference new config path.

- [ ] **`cyoda/skills/migrate/SKILL.md`** — Update all dynamic context injection blocks. Update the "re-read config" step after cloud setup.

- [ ] **`cyoda/skills/compute/SKILL.md`** — Update token read to use active profile from `~/.config/cyoda/cyoda-plugin-config.json`.

- [ ] **`cyoda/skills/auth/evaluations/evals.json`** — Update `files` fixtures: replace `".cyoda/config"` key with `"~/.config/cyoda/cyoda-plugin-config.json"` and JSON profile format. Update assertions referencing `.cyoda/config` path. Add assertion that no `.gitignore` entries are written.

- [ ] **`cyoda/skills/setup/evaluations/evals.json`** — Same fixture and assertion updates. Add profile-selection assertion.

- [ ] **`cyoda/skills/status/evaluations/evals.json`** — Update `files` fixtures to profile format. Update assertions to expect `[profile: <name>]` in output.

- [ ] **`cyoda/skills/build/evaluations/evals.json`** — Update `files` fixtures to profile format.

- [ ] **`cyoda/skills/test/evaluations/evals.json`** — Update `files` fixtures to profile format.

- [ ] **`cyoda/skills/debug/evaluations/evals.json`** — Update `files` fixtures to profile format.

- [ ] **`cyoda/skills/migrate/evaluations/evals.json`** — Update `files` fixtures to profile format.

- [ ] **`cyoda/skills/app/evaluations/evals.json`** — Update `files` fixtures to profile format.

**Dynamic context injection pattern (used by all reading skills):**

```bash
PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "default")
jq --arg p "$PROFILE" '.profiles[$p] // {"endpoint":"none"}' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo '{"endpoint":"none"}'
```

**Write pattern (used by `cyoda:setup` and `cyoda:auth`):**

```bash
mkdir -p ~/.config/cyoda
CONFIG_FILE=~/.config/cyoda/cyoda-plugin-config.json
EXISTING=$(cat "$CONFIG_FILE" 2>/dev/null || echo "{\"active\":\"$PROFILE_NAME\",\"profiles\":{}}")
echo "$EXISTING" | jq --arg p "$PROFILE_NAME" --argjson data "$NEW_DATA" \
  '.profiles[$p] = $data | .active = $p' > "$CONFIG_FILE"
```

- [ ] **Commit:** `git commit -m "feat: move config to ~/.config/cyoda/cyoda-plugin-config.json with named profiles"`

---

## Config Migration: Detailed Implementation Tasks

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `.cyoda/config` with `~/.config/cyoda/cyoda-plugin-config.json` (named profiles, home directory) across all skill files, README, and evaluations.

**Architecture:** Pure find-and-replace across 9 SKILL.md files + README + 8 eval files. No shared code — each file is self-contained. Two patterns govern everything: the read pattern (active profile lookup) and the write pattern (profile upsert). All other file content stays unchanged.

**Tech Stack:** Markdown (SKILL.md), JSON (evals), bash/jq (inline skill commands)

**Read pattern** — replaces every `jq . .cyoda/config 2>/dev/null || echo '{"endpoint":"none"}'` block:
```bash
PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "default")
jq --arg p "$PROFILE" '.profiles[$p] // {"endpoint":"none"}' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo '{"endpoint":"none"}'
```

**Scalar read** — replaces every `jq -r '.endpoint' .cyoda/config` pattern:
```bash
PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "default")
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint // "none"' ~/.config/cyoda/cyoda-plugin-config.json)
TOKEN=$(jq -r --arg p "$PROFILE" '.profiles[$p].token // ""' ~/.config/cyoda/cyoda-plugin-config.json)
ENV=$(jq -r --arg p "$PROFILE" '.profiles[$p].env // "development"' ~/.config/cyoda/cyoda-plugin-config.json)
```

**Write pattern** — replaces every block that writes to `.cyoda/config`:
```bash
CONFIG_FILE=~/.config/cyoda/cyoda-plugin-config.json
mkdir -p ~/.config/cyoda
EXISTING=$(cat "$CONFIG_FILE" 2>/dev/null || echo "{\"active\":\"${PROFILE_NAME}\",\"profiles\":{}}")
echo "$EXISTING" | jq --arg p "$PROFILE_NAME" --argjson data "$NEW_DATA" \
  '.profiles[$p] = $data | .active = $p' > "$CONFIG_FILE"
```

**Eval fixture pattern** — replaces every `".cyoda/config": "{...}"` in `files` blocks:
- Old key: `".cyoda/config"`
- New key: `"~/.config/cyoda/cyoda-plugin-config.json"`
- Old value (local): `"{\"endpoint\": \"http://localhost:8080\", \"env\": \"development\"}"`
- New value (local): `"{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"`
- Old value (cloud+token): `"{\"endpoint\": \"https://...\", \"env\": \"development\", \"token\": \"eyJ...\"}"`
- New value (cloud+token): `"{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://...\",\"env\":\"development\",\"token\":\"eyJ...\"}}}"`

---

### Task A: README

**Files:**
- Modify: `cyoda/README.md`

- [ ] **Step 1: Replace the Connection Config section**

Replace:
```markdown
## Connection Config

Skills share connection state via `.cyoda/config` (always gitignored):

```json
{
  "endpoint": "http://localhost:8080",
  "token": "eyJ...",
  "env": "development"
}
```

Run `/cyoda:setup` then `/cyoda:auth` to populate this file.
```

With:
```markdown
## Connection Config

Skills share connection state via `~/.config/cyoda/cyoda-plugin-config.json` — a home-directory file that is never git-tracked:

```json
{
  "active": "default",
  "profiles": {
    "default": {
      "endpoint": "http://localhost:8080",
      "env": "development"
    },
    "prod": {
      "endpoint": "https://client-abc123-prod.eu.cyoda.net",
      "token": "eyJ...",
      "env": "production"
    }
  }
}
```

The `"active"` key controls which profile all skills use. `token` is absent for local cyoda-go (mock auth).

Run `/cyoda:setup` then `/cyoda:auth` to create a profile and set it as active.
```

- [ ] **Step 2: Commit**
```bash
git add cyoda/README.md
git commit -m "docs(readme): update Connection Config for home-dir profile format"
```

---

### Task B: cyoda:setup SKILL.md

**Files:**
- Modify: `cyoda/skills/setup/SKILL.md`

- [ ] **Step 1: Add profile selection before local write (Step 6)**

Replace the local Step 6 block:
```markdown
**Step 6 — Write config:**

```bash
mkdir -p .cyoda
echo '{"endpoint": "http://localhost:8080", "env": "development"}' | jq . > .cyoda/config
grep -qxF '.cyoda/config' .gitignore 2>/dev/null || echo '.cyoda/config' >> .gitignore
grep -qxF '.cyoda/' .gitignore 2>/dev/null || echo '.cyoda/' >> .gitignore
```

Confirm: **"Local cyoda-go is running. REST on port 8080, gRPC on port 9090. `/cyoda:auth` is not needed for local — mock auth is active."**
```

With:
```markdown
**Step 6 — Write config:**

List existing profiles (if any):
```bash
jq -r '.profiles | keys[]' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "(none yet)"
```

Ask: *"Which profile name should this connection be saved under? (e.g. `default`, `local`)"*

```bash
CONFIG_FILE=~/.config/cyoda/cyoda-plugin-config.json
mkdir -p ~/.config/cyoda
NEW_DATA='{"endpoint": "http://localhost:8080", "env": "development"}'
EXISTING=$(cat "$CONFIG_FILE" 2>/dev/null || echo "{\"active\":\"${PROFILE_NAME}\",\"profiles\":{}}")
echo "$EXISTING" | jq --arg p "$PROFILE_NAME" --argjson data "$NEW_DATA" \
  '.profiles[$p] = $data | .active = $p' > "$CONFIG_FILE"
```

Confirm: **"Local cyoda-go is running. REST on port 8080, gRPC on port 9090. `/cyoda:auth` is not needed for local — mock auth is active."**
```

- [ ] **Step 2: Update cloud Step 3**

Replace the cloud Step 3 block:
```markdown
**Step 3 — Write endpoint to config:**

```bash
mkdir -p .cyoda
# Claude substitutes the endpoint URL the user provided
echo "{\"endpoint\": \"<USER_PROVIDED_ENDPOINT>\"}" | jq . > .cyoda/config
grep -qxF '.cyoda/config' .gitignore 2>/dev/null || echo '.cyoda/config' >> .gitignore
grep -qxF '.cyoda/' .gitignore 2>/dev/null || echo '.cyoda/' >> .gitignore
```
```

With:
```markdown
**Step 3 — Write endpoint to config:**

List existing profiles (if any):
```bash
jq -r '.profiles | keys[]' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "(none yet)"
```

Ask: *"Which profile name should this connection be saved under? (e.g. `default`, `cloud`, `prod`)"*

```bash
CONFIG_FILE=~/.config/cyoda/cyoda-plugin-config.json
mkdir -p ~/.config/cyoda
# Claude substitutes the endpoint URL the user provided
NEW_DATA="{\"endpoint\": \"<USER_PROVIDED_ENDPOINT>\"}"
EXISTING=$(cat "$CONFIG_FILE" 2>/dev/null || echo "{\"active\":\"${PROFILE_NAME}\",\"profiles\":{}}")
echo "$EXISTING" | jq --arg p "$PROFILE_NAME" --argjson data "$NEW_DATA" \
  '.profiles[$p] = $data | .active = $p' > "$CONFIG_FILE"
```
```

- [ ] **Step 3: Update cloud verify step (after auth)**

Replace:
```bash
curl -sf --max-time 5 \
  -H "Authorization: Bearer $(jq -r '.token // ""' .cyoda/config)" \
  "$(jq -r '.endpoint' .cyoda/config)/readyz" || echo "Check your endpoint and token"
```

With:
```bash
PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "default")
TOKEN=$(jq -r --arg p "$PROFILE" '.profiles[$p].token // ""' ~/.config/cyoda/cyoda-plugin-config.json)
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint' ~/.config/cyoda/cyoda-plugin-config.json)
curl -sf --max-time 5 \
  -H "Authorization: Bearer ${TOKEN}" \
  "${ENDPOINT}/readyz" || echo "Check your endpoint and token"
```

- [ ] **Step 4: Commit**
```bash
git add cyoda/skills/setup/SKILL.md
git commit -m "feat(setup): write profile to ~/.config/cyoda/cyoda-plugin-config.json"
```

---

### Task C: cyoda:auth SKILL.md

**Files:**
- Modify: `cyoda/skills/auth/SKILL.md`

- [ ] **Step 1: Update description frontmatter**

Replace:
```
description: Authenticate to Cyoda Cloud using OAuth 2.0 client credentials. Obtains a JWT token and saves it to .cyoda/config. Includes production safety guard requiring explicit confirmation before storing production credentials. Only trigger for Cyoda-specific authentication — do not trigger for generic /login commands unrelated to Cyoda.
```

With:
```
description: Authenticate to Cyoda Cloud using OAuth 2.0 client credentials. Obtains a JWT token and saves it to ~/.config/cyoda/cyoda-plugin-config.json under a named profile. Includes production safety guard requiring explicit confirmation before storing production credentials. Only trigger for Cyoda-specific authentication — do not trigger for generic /login commands unrelated to Cyoda.
```

Also add `Bash(mkdir *)` to `allowed-tools`.

- [ ] **Step 2: Update opening read and add profile step**

Replace:
```markdown
## Cyoda Login

Reading current endpoint:
```!
jq -r '.endpoint // "none"' .cyoda/config 2>/dev/null || echo "none"
```

If endpoint is `none`: *"No Cyoda endpoint configured. Run `/cyoda:setup` first."* Stop.

**Step 1 — Confirm environment type:**
```

With:
```markdown
## Cyoda Login

Reading current config:
```!
PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "default"); jq --arg p "$PROFILE" '.profiles[$p] // {"endpoint":"none"}' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo '{"endpoint":"none"}'
```

If `endpoint` is `none`: *"No Cyoda endpoint configured. Run `/cyoda:setup` first."* Stop.

**Step 1 — Select profile:**

List existing profiles:
```bash
jq -r '.profiles | keys[]' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "(none yet)"
```

Ask: *"Which profile should this token be saved under? Enter a name (e.g. `default`, `prod`) — existing profiles are updated, new names create a new profile."*

Set `PROFILE_NAME` to the user's answer.

**Step 2 — Confirm environment type:**
```

- [ ] **Step 3: Update security warning (remove gitignore mention)**

Replace:
```
> ⚠️ **Security warning**: You are about to store production credentials in `.cyoda/config` on disk. This file will be gitignored, but it remains in plain text on your filesystem. Anyone with access to this machine can read it.
```

With:
```
> ⚠️ **Security warning**: You are about to store production credentials in `~/.config/cyoda/cyoda-plugin-config.json` on disk in plain text. Anyone with access to this machine can read them.
```

- [ ] **Step 4: Renumber steps 2-5 → 3-6 and update token endpoint to use profile**

In the token endpoint block (formerly Step 3), replace:
```bash
ENDPOINT=$(jq -r '.endpoint' .cyoda/config)
```

With:
```bash
PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "default")
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint' ~/.config/cyoda/cyoda-plugin-config.json)
```

- [ ] **Step 5: Replace write block and remove gitignore steps**

Replace the entire write block (formerly Step 4):
```bash
TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
ENV_VALUE="development"  # or "production" based on Step 1

# Update .cyoda/config preserving endpoint
jq --arg token "$TOKEN" --arg env "$ENV_VALUE" \
  '. + {"token": $token, "env": $env}' .cyoda/config > .cyoda/config.tmp
mv .cyoda/config.tmp .cyoda/config

grep -qxF '.cyoda/config' .gitignore 2>/dev/null || echo '.cyoda/config' >> .gitignore
grep -qxF '.cyoda/' .gitignore 2>/dev/null || echo '.cyoda/' >> .gitignore
```

With:
```bash
TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
ENV_VALUE="development"  # or "production" based on Step 2

CONFIG_FILE=~/.config/cyoda/cyoda-plugin-config.json
mkdir -p ~/.config/cyoda
EXISTING=$(cat "$CONFIG_FILE" 2>/dev/null || echo "{\"active\":\"${PROFILE_NAME}\",\"profiles\":{}}")
EXISTING_PROFILE=$(echo "$EXISTING" | jq -r --arg p "$PROFILE_NAME" '.profiles[$p] // {}')
NEW_PROFILE=$(echo "$EXISTING_PROFILE" | jq --arg token "$TOKEN" --arg env "$ENV_VALUE" \
  '. + {"token": $token, "env": $env}')
echo "$EXISTING" | jq --arg p "$PROFILE_NAME" --argjson data "$NEW_PROFILE" \
  '.profiles[$p] = $data | .active = $p' > "$CONFIG_FILE"
```

- [ ] **Step 6: Update confirm message (formerly Step 5)**

Replace:
```
Report: *"Authenticated successfully. Token written to `.cyoda/config`. Run `/cyoda:status` to verify the connection."*
```

With:
```
Report: *"Authenticated successfully. Token written to `~/.config/cyoda/cyoda-plugin-config.json` under profile `{PROFILE_NAME}`. Run `/cyoda:status` to verify the connection."*
```

- [ ] **Step 7: Commit**
```bash
git add cyoda/skills/auth/SKILL.md
git commit -m "feat(auth): write token to ~/.config/cyoda/cyoda-plugin-config.json with profile selection"
```

---

### Task D: cyoda:status SKILL.md

**Files:**
- Modify: `cyoda/skills/status/SKILL.md`

- [ ] **Step 1: Replace both dynamic injection blocks**

Replace the first block:
```markdown
Current config:
```!
jq . .cyoda/config 2>/dev/null || echo '{"endpoint":"none"}'
```
```

With:
```markdown
Current config:
```!
PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "default"); jq --arg p "$PROFILE" '.profiles[$p] // {"endpoint":"none"}' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo '{"endpoint":"none"}'
```
```

Replace the second block:
```markdown
Checking reachability and version:
```!
ENDPOINT=$(jq -r '.endpoint // "none"' .cyoda/config 2>/dev/null || echo "none");
ENV=$(jq -r '.env // "development"' .cyoda/config 2>/dev/null || echo "development");
if [ -z "$ENDPOINT" ] || [ "$ENDPOINT" = "none" ]; then
  echo "STATUS=not_configured";
else
  VERSION=$(curl -sf --max-time 3 "${ENDPOINT%/}/api/help" 2>/dev/null | jq -r '.version // ""' 2>/dev/null);
  if [ -z "$VERSION" ]; then
    echo "STATUS=unreachable ENDPOINT=$ENDPOINT";
  else
    echo "STATUS=connected ENDPOINT=$ENDPOINT VERSION=$VERSION ENV=${ENV:-development}";
  fi;
fi
```
```

With:
```markdown
Checking reachability and version:
```!
PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "default");
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint // "none"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "none");
ENV=$(jq -r --arg p "$PROFILE" '.profiles[$p].env // "development"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null || echo "development");
if [ -z "$ENDPOINT" ] || [ "$ENDPOINT" = "none" ]; then
  echo "STATUS=not_configured PROFILE=$PROFILE";
else
  VERSION=$(curl -sf --max-time 3 "${ENDPOINT%/}/api/help" 2>/dev/null | jq -r '.version // ""' 2>/dev/null);
  if [ -z "$VERSION" ]; then
    echo "STATUS=unreachable ENDPOINT=$ENDPOINT PROFILE=$PROFILE";
  else
    echo "STATUS=connected ENDPOINT=$ENDPOINT VERSION=$VERSION ENV=${ENV:-development} PROFILE=$PROFILE";
  fi;
fi
```
```

- [ ] **Step 2: Update report bullets to include profile name**

Replace:
```markdown
- `STATUS=not_configured` → **"Not connected to Cyoda — run `/cyoda:setup` to get started"**
- `STATUS=unreachable` → **"Cyoda instance unreachable at {ENDPOINT} — is it running?"**
- `STATUS=connected`, `ENV=production` → **"⚠️ Connected to Cyoda Cloud [PRODUCTION] — v{VERSION}"**
- `STATUS=connected`, endpoint contains `localhost` → **"Connected to Local cyoda-go — v{VERSION}"**
- `STATUS=connected`, cloud endpoint → **"Connected to Cyoda Cloud — v{VERSION}"**
```

With:
```markdown
- `STATUS=not_configured` → **"Not connected to Cyoda — run `/cyoda:setup` to get started"**
- `STATUS=unreachable` → **"Cyoda instance unreachable at {ENDPOINT} [profile: {PROFILE}] — is it running?"**
- `STATUS=connected`, `ENV=production` → **"⚠️ Connected to Cyoda Cloud [PRODUCTION] — v{VERSION} [profile: {PROFILE}]"**
- `STATUS=connected`, endpoint contains `localhost` → **"Connected to Local cyoda-go — v{VERSION} [profile: {PROFILE}]"**
- `STATUS=connected`, cloud endpoint → **"Connected to Cyoda Cloud — v{VERSION} [profile: {PROFILE}]"**
```

- [ ] **Step 3: Commit**
```bash
git add cyoda/skills/status/SKILL.md
git commit -m "feat(status): read active profile from ~/.config/cyoda/cyoda-plugin-config.json, show profile name"
```

---

### Task E: cyoda:build, cyoda:test, cyoda:debug, cyoda:migrate, cyoda:compute SKILL.md

**Files:**
- Modify: `cyoda/skills/build/SKILL.md`
- Modify: `cyoda/skills/test/SKILL.md`
- Modify: `cyoda/skills/debug/SKILL.md`
- Modify: `cyoda/skills/migrate/SKILL.md`
- Modify: `cyoda/skills/compute/SKILL.md`

All five files share the same mechanical change: replace `.cyoda/config` reads with the home-dir profile pattern. Apply the same substitution rules in each file.

**Substitution rules:**

| Old | New |
|-----|-----|
| `jq . .cyoda/config 2>/dev/null \|\| echo '{"endpoint":"none"}'` | `PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null \|\| echo "default"); jq --arg p "$PROFILE" '.profiles[$p] // {"endpoint":"none"}' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null \|\| echo '{"endpoint":"none"}'` |
| `ENDPOINT=$(jq -r '.endpoint' .cyoda/config)` | `PROFILE=$(jq -r '.active // "default"' ~/.config/cyoda/cyoda-plugin-config.json 2>/dev/null \|\| echo "default"); ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint // "none"' ~/.config/cyoda/cyoda-plugin-config.json)` |
| `TOKEN=$(jq -r '.token // ""' .cyoda/config)` | `TOKEN=$(jq -r --arg p "$PROFILE" '.profiles[$p].token // ""' ~/.config/cyoda/cyoda-plugin-config.json)` |
| `jq -r '.endpoint' .cyoda/config` | `jq -r --arg p "$PROFILE" '.profiles[$p].endpoint' ~/.config/cyoda/cyoda-plugin-config.json` |
| `jq -r '.token' .cyoda/config` | `jq -r --arg p "$PROFILE" '.profiles[$p].token' ~/.config/cyoda/cyoda-plugin-config.json` |
| `.cyoda/config` (any remaining reference in prose) | `~/.config/cyoda/cyoda-plugin-config.json` |

Note: When `ENDPOINT` and `TOKEN` are extracted in the same block, define `PROFILE` once at the top of that block — do not repeat the `PROFILE=$(...)` lookup for each field.

**compute/SKILL.md specific:** Line 37 also has prose — replace `Use the JWT token from `.cyoda/config`:` with `Use the JWT token from the active profile in `~/.config/cyoda/cyoda-plugin-config.json`:`.

- [ ] **Step 1: Apply substitutions to `cyoda/skills/build/SKILL.md`** (3 injection blocks + 3 bash blocks)

- [ ] **Step 2: Apply substitutions to `cyoda/skills/test/SKILL.md`** (1 injection block + 1 bash block)

- [ ] **Step 3: Apply substitutions to `cyoda/skills/debug/SKILL.md`** (1 injection block + 2 bash blocks in observation mode + prose in connectivity section)

- [ ] **Step 4: Apply substitutions to `cyoda/skills/migrate/SKILL.md`** (1 injection block + 3 bash blocks)

- [ ] **Step 5: Apply substitution to `cyoda/skills/compute/SKILL.md`** (1 injection block + prose)

- [ ] **Step 6: Commit**
```bash
git add cyoda/skills/build/SKILL.md cyoda/skills/test/SKILL.md cyoda/skills/debug/SKILL.md \
  cyoda/skills/migrate/SKILL.md cyoda/skills/compute/SKILL.md
git commit -m "feat(skills): update config reads to ~/.config/cyoda/cyoda-plugin-config.json across build/test/debug/migrate/compute"
```

---

### Task F: auth + setup evaluations

**Files:**
- Modify: `cyoda/skills/auth/evaluations/evals.json`
- Modify: `cyoda/skills/setup/evaluations/evals.json`

**auth/evaluations/evals.json** — full new content:

- [ ] **Step 1: Write new auth evals.json**

```json
{
  "skill_name": "auth",
  "evals": [
    {
      "id": 1,
      "prompt": "/cyoda:auth",
      "expected_output": "Asks for profile name, asks dev vs production, explains M2M credentials, collects client_id and client_secret separately, calls OAuth token endpoint, writes token and env=development to ~/.config/cyoda/cyoda-plugin-config.json under the selected profile, confirms success without production warning",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://client-1edf4e3da14e497baf58d3aeb621ac40-dev.eu.cyoda.net\"}}}"
      },
      "assertions": [
        { "id": "asks-profile-name", "text": "Asks which profile name to save the token under before proceeding", "type": "behavior" },
        { "id": "asks-env-type", "text": "Asks whether this is development or production environment", "type": "behavior" },
        { "id": "explains-m2m", "text": "Explains that client_id/client_secret are machine-to-machine credentials identifying the application, not a personal login", "type": "behavior" },
        { "id": "asks-if-have-credentials", "text": "Asks whether user already has client_id and client_secret before collecting", "type": "behavior" },
        { "id": "handles-no-credentials", "text": "Asks whether user already has credentials — if the user says no, would explain cloud credential self-service is coming soon and direct them to contact the Cyoda team; in this eval the user says yes so that path is not exercised but the conditional check must be present", "type": "behavior" },
        { "id": "collects-credentials", "text": "Collects client_id and client_secret separately, one at a time", "type": "behavior" },
        { "id": "calls-token-endpoint", "text": "Calls OAuth token endpoint", "type": "behavior" },
        { "id": "writes-token", "text": "Writes token and env=development to ~/.config/cyoda/cyoda-plugin-config.json under the selected profile", "type": "behavior" },
        { "id": "no-echo-secret", "text": "Does NOT echo client_secret back in the conversation", "type": "behavior" },
        { "id": "no-production-warning", "text": "Does NOT show production warning for development login", "type": "behavior" },
        { "id": "no-gitignore", "text": "Does NOT write any .gitignore entry", "type": "behavior" }
      ]
    },
    {
      "id": 2,
      "prompt": "/cyoda:auth — production environment, I accept the risk",
      "expected_output": "Asks profile name, shows security warning, requires explicit 'yes', explains M2M credentials, collects credentials, writes token and env=production to ~/.config/cyoda/cyoda-plugin-config.json under the selected profile, shows prominent production reminder",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://client-1edf4e3da14e497baf58d3aeb621ac40-prod.eu.cyoda.net\"}}}"
      },
      "assertions": [
        { "id": "asks-profile-name", "text": "Asks which profile name to save the token under", "type": "behavior" },
        { "id": "shows-security-warning", "text": "Shows security warning about storing production credentials on disk", "type": "behavior" },
        { "id": "requires-explicit-yes", "text": "Requires explicit 'yes' — not any other response", "type": "behavior" },
        { "id": "confirmation-is-own-step", "text": "Shows the security warning and asks yes/no as a distinct step even though the user pre-stated acceptance in the prompt — does NOT skip the confirmation", "type": "behavior" },
        { "id": "explains-m2m", "text": "Explains that client_id/client_secret are M2M credentials for the application", "type": "behavior" },
        { "id": "writes-production-env", "text": "Writes env=production to ~/.config/cyoda/cyoda-plugin-config.json after confirmation", "type": "behavior" },
        { "id": "production-reminder", "text": "Shows prominent production reminder after successful login", "type": "format" },
        { "id": "no-gitignore", "text": "Does NOT write any .gitignore entry", "type": "behavior" }
      ]
    },
    {
      "id": 3,
      "prompt": "/cyoda:auth — production, but I'm not sure about storing credentials",
      "expected_output": "Shows security warning, stops when user does not answer 'yes', does not write any credentials, suggests alternatives",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://client-1edf4e3da14e497baf58d3aeb621ac40-prod.eu.cyoda.net\"}}}"
      },
      "assertions": [
        { "id": "shows-warning", "text": "Shows security warning before proceeding", "type": "behavior" },
        { "id": "stops-on-non-yes", "text": "Stops when user response is not explicit 'yes'", "type": "behavior" },
        { "id": "no-credentials-written", "text": "Does NOT write any credentials after a non-yes response", "type": "behavior" },
        { "id": "suggests-alternatives", "text": "Suggests CYODA_TOKEN env var as an alternative to persisting credentials on disk", "type": "behavior" }
      ]
    },
    {
      "id": 4,
      "prompt": "/cyoda:auth — my login stopped working after the environment was redeployed",
      "expected_output": "Recognises the post-redeploy scenario, notes that technical users may be deleted on redeploy, directs user to contact the Cyoda team to recreate the technical user before retrying",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://client-1edf4e3da14e497baf58d3aeb621ac40-dev.eu.cyoda.net\"}}}"
      },
      "assertions": [
        { "id": "recognises-redeploy", "text": "Recognises the post-redeploy scenario as cause of credential failure", "type": "behavior" },
        { "id": "notes-users-deleted", "text": "Notes that technical users may be deleted when an environment is redeployed", "type": "behavior" },
        { "id": "directs-to-contact-team", "text": "Directs user to contact the Cyoda team to recreate the technical user — does NOT mention AI Studio or ai.cyoda.net", "type": "behavior" },
        { "id": "completes-auth", "text": "After user provides new credentials, completes the full auth flow — calls token endpoint and writes token to ~/.config/cyoda/cyoda-plugin-config.json", "type": "behavior" }
      ]
    },
    {
      "id": 5,
      "prompt": "/cyoda:auth — connect to a Cyoda Cloud dev environment with client_id=abc123 and client_secret=xyz789",
      "expected_output": "Uses Authorization: Basic header with base64-encoded client_id:client_secret against /api/oauth/token on the first attempt, without iterating through multiple paths",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://client-1edf4e3da14e497baf58d3aeb621ac40-dev.eu.cyoda.net\"}}}"
      },
      "assertions": [
        { "id": "basic-auth-header", "text": "Uses Authorization: Basic header with base64-encoded client_id:client_secret — credentials are NOT in the request body", "type": "behavior" },
        { "id": "correct-endpoint-first", "text": "Calls /api/oauth/token as the token endpoint — does NOT try /oauth/token, /auth/token, or other guessed paths", "type": "behavior" },
        { "id": "no-path-guessing", "text": "Does NOT iterate through multiple token endpoint paths on failure — consults cyoda help config auth (or https://docs.cyoda.net/help/config/auth.md if CLI absent) instead", "type": "behavior" },
        { "id": "consults-cyoda-help-on-failure", "text": "If token call fails, runs 'cyoda help config auth' or fetches https://docs.cyoda.net/help/config/auth.md before retrying — does not guess alternate paths", "type": "behavior" }
      ]
    }
  ]
}
```

**setup/evaluations/evals.json** — full new content:

- [ ] **Step 2: Write new setup evals.json**

```json
{
  "skill_name": "setup",
  "evals": [
    {
      "id": 1,
      "prompt": "/cyoda:setup",
      "expected_output": "Walks through local install: asks local vs cloud, runs brew install, runs cyoda init, verifies health, asks for profile name, writes profile to ~/.config/cyoda/cyoda-plugin-config.json, notes mock auth is active",
      "files": {},
      "assertions": [
        { "id": "asks-local-vs-cloud", "text": "Asks whether user wants local or cloud setup", "type": "behavior" },
        { "id": "runs-brew-install", "text": "Runs brew install commands for cyoda", "type": "behavior" },
        { "id": "runs-cyoda-init", "text": "Runs cyoda init", "type": "behavior" },
        { "id": "verifies-health", "text": "Verifies health endpoint responds", "type": "behavior" },
        { "id": "asks-profile-name", "text": "Asks which profile name to save this connection under", "type": "behavior" },
        { "id": "writes-config", "text": "Writes profile with localhost endpoint to ~/.config/cyoda/cyoda-plugin-config.json and sets it as active", "type": "behavior" },
        { "id": "no-gitignore", "text": "Does NOT write any .gitignore entry", "type": "behavior" },
        { "id": "notes-mock-auth", "text": "Notes mock auth is active for local — no login needed", "type": "behavior" },
        { "id": "no-credentials", "text": "Does NOT ask for credentials on local setup", "type": "behavior" }
      ]
    },
    {
      "id": 2,
      "prompt": "/cyoda:setup — I want to use Cyoda Cloud",
      "expected_output": "Shows coming soon notice for managed cloud environments, collects endpoint URL from user (for users already provisioned by the Cyoda team), asks for profile name, writes only endpoint field to ~/.config/cyoda/cyoda-plugin-config.json as a profile, directs to /cyoda:auth next",
      "files": {},
      "assertions": [
        { "id": "shows-coming-soon", "text": "Shows a coming soon notice explaining that managed cloud environments are not yet available for self-service provisioning", "type": "behavior" },
        { "id": "allows-existing-endpoint", "text": "Still allows users who already have a provisioned endpoint to enter it and continue", "type": "behavior" },
        { "id": "does-not-direct-to-ai-studio", "text": "Does NOT direct the user to ai.cyoda.net or mention AI Studio", "type": "behavior" },
        { "id": "collects-endpoint", "text": "Collects endpoint URL from user", "type": "behavior" },
        { "id": "correct-endpoint-format", "text": "Uses correct endpoint format example (client-<hash>-<env>.eu.cyoda.net, not api.eu.cyoda.net)", "type": "format" },
        { "id": "asks-profile-name", "text": "Asks which profile name to save this connection under", "type": "behavior" },
        { "id": "writes-endpoint-only", "text": "Writes only endpoint field to ~/.config/cyoda/cyoda-plugin-config.json as a named profile — no token yet", "type": "behavior" },
        { "id": "no-gitignore", "text": "Does NOT write any .gitignore entry", "type": "behavior" },
        { "id": "directs-to-login", "text": "Directs user to run /cyoda:auth next", "type": "behavior" },
        { "id": "no-credentials-in-setup", "text": "Does NOT ask for credentials — that is login's job", "type": "behavior" },
        { "id": "no-docs-signup-url", "text": "Does NOT direct user to docs.cyoda.net for sign-up", "type": "behavior" }
      ]
    },
    {
      "id": 3,
      "prompt": "/cyoda:setup",
      "expected_output": "Detects existing installation, skips brew install, verifies health, asks for profile name, updates profile in ~/.config/cyoda/cyoda-plugin-config.json, reports already ready",
      "files": {
        "~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"
      },
      "assertions": [
        { "id": "detects-existing", "text": "Detects cyoda is already installed", "type": "behavior" },
        { "id": "skips-brew", "text": "Does NOT re-run brew install when already installed", "type": "behavior" },
        { "id": "verifies-health", "text": "Verifies health endpoint", "type": "behavior" },
        { "id": "no-force-init", "text": "Does NOT run cyoda init again without --force", "type": "behavior" },
        { "id": "reports-ready", "text": "Reports already ready", "type": "format" }
      ]
    },
    {
      "id": 4,
      "prompt": "/cyoda:setup — local install, but brew fails with a permissions error",
      "expected_output": "Attempts brew tap and brew install, detects failure, immediately shows the two commands and asks user to run them manually, waits for confirmation, then continues to cyoda init",
      "files": {},
      "assertions": [
        { "id": "attempts-brew-first", "text": "Attempts to run brew tap and brew install before giving up", "type": "behavior" },
        { "id": "no-brew-diagnosis", "text": "Does NOT run brew doctor, sudo, or any Homebrew remediation", "type": "behavior" },
        { "id": "shows-exact-commands", "text": "Shows the exact brew tap and brew install commands for the user to run manually", "type": "format" },
        { "id": "no-extra-commands", "text": "Does NOT include sudo, chown, or any commands beyond the two brew commands in the user-facing message", "type": "format" },
        { "id": "asks-user-to-run", "text": "Asks the user to run the commands in their own terminal", "type": "behavior" },
        { "id": "waits-before-continuing", "text": "Waits for user confirmation before continuing to cyoda init", "type": "behavior" },
        { "id": "continues-after-confirm", "text": "Continues to cyoda init (Step 3) after the user confirms", "type": "behavior" }
      ]
    }
  ]
}
```

- [ ] **Step 3: Commit**
```bash
git add cyoda/skills/auth/evaluations/evals.json cyoda/skills/setup/evaluations/evals.json
git commit -m "test(auth,setup): update evals for home-dir config and profile selection"
```

---

### Task G: Remaining evaluations (status, build, test, debug, migrate, app)

**Files:**
- Modify: `cyoda/skills/status/evaluations/evals.json`
- Modify: `cyoda/skills/build/evaluations/evals.json`
- Modify: `cyoda/skills/test/evaluations/evals.json`
- Modify: `cyoda/skills/debug/evaluations/evals.json`
- Modify: `cyoda/skills/migrate/evaluations/evals.json`
- Modify: `cyoda/skills/app/evaluations/evals.json`

All six files share the same mechanical change: replace `".cyoda/config"` fixture key with `"~/.config/cyoda/cyoda-plugin-config.json"` and wrap the value in the profile envelope. Apply to every `files` block in each file.

Additionally for **status evals**:
- Eval 1: Update `"reads-config"` assertion text to `"Reads active profile from ~/.config/cyoda/cyoda-plugin-config.json for endpoint"`; add assertion `{ "id": "shows-profile-name", "text": "Includes [profile: <name>] in the status output", "type": "format" }`
- Eval 3: Update `"detects-missing-config"` assertion text to `"Detects missing ~/.config/cyoda/cyoda-plugin-config.json or empty profiles"`

For **build evals** — update `"reads-config"` assertion text in eval 1 to `"Reads active profile from ~/.config/cyoda/cyoda-plugin-config.json for endpoint"`.

For **test evals** — update `"reads-config"` assertion text in eval 1 to `"Reads active profile from ~/.config/cyoda/cyoda-plugin-config.json for endpoint"`.

- [ ] **Step 1: Update `cyoda/skills/status/evaluations/evals.json`**

Apply fixture key/value substitution to evals 1, 2, 4. Update assertions in evals 1 and 3 as described above.

Fixture substitutions:
- Eval 1 `files`: `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"`
- Eval 2 `files`: `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://api.eu.cyoda.net\",\"env\":\"production\",\"token\":\"eyJfake...\"}}}"`
- Eval 3 `files`: `{}` (no change — empty means no config file)
- Eval 4 `files`: `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://api.eu.cyoda.net\",\"env\":\"development\",\"token\":\"eyJexpired...\"}}}"`

- [ ] **Step 2: Update `cyoda/skills/build/evaluations/evals.json`**

Apply fixture key/value substitution to all 11 evals. Use these per-eval fixtures:
- Evals 1–10 (local): `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"`
- Eval 3 (production): `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://api.eu.cyoda.net\",\"env\":\"production\",\"token\":\"eyJfake...\"}}}"`
- Eval 11 (expired token): `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://api.eu.cyoda.net\",\"env\":\"development\",\"token\":\"eyJexpired...\"}}}"`

Update eval 1 `"reads-config"` assertion text.

- [ ] **Step 3: Update `cyoda/skills/test/evaluations/evals.json`**

Apply fixture key/value substitution to all 4 evals:
- Evals 1–3 (local): `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"`
- Eval 4 (expired token): `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://api.eu.cyoda.net\",\"env\":\"development\",\"token\":\"eyJexpired...\"}}}"`

Update eval 1 `"reads-config"` assertion text.

- [ ] **Step 4: Update `cyoda/skills/debug/evaluations/evals.json`**

Apply fixture key/value substitution to all 4 evals:
- Evals 1–3 (local): `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"`
- Eval 4 (expired token): `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"https://api.eu.cyoda.net\",\"env\":\"development\",\"token\":\"eyJexpired...\"}}}"`

- [ ] **Step 5: Update `cyoda/skills/migrate/evaluations/evals.json`**

Apply fixture key/value substitution to all 5 evals:
- Evals 1–4 (local): `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"`
- Eval 5 (expired token): `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\",\"token\":\"eyJexpired...\"}}}"`

- [ ] **Step 6: Update `cyoda/skills/app/evaluations/evals.json`**

Only eval 4 has a `files` fixture. Replace:
- `"~/.config/cyoda/cyoda-plugin-config.json": "{\"active\":\"default\",\"profiles\":{\"default\":{\"endpoint\":\"http://localhost:8080\",\"env\":\"development\"}}}"`

- [ ] **Step 7: Commit**
```bash
git add cyoda/skills/status/evaluations/evals.json \
  cyoda/skills/build/evaluations/evals.json \
  cyoda/skills/test/evaluations/evals.json \
  cyoda/skills/debug/evaluations/evals.json \
  cyoda/skills/migrate/evaluations/evals.json \
  cyoda/skills/app/evaluations/evals.json
git commit -m "test(skills): update eval fixtures for home-dir profile config format"
```

---

## Task 15: Web Help Fallback + Cloud-First Support

**Goal:** Make the plugin usable without a locally installed `cyoda` CLI by falling back to `https://docs.cyoda.net/help/` for help content. Ask once per session to recommend local install. Present local and cloud as co-equal options in `cyoda:app`.

**Files:**
- Modify: `cyoda/skills/docs/SKILL.md`
- Modify: `cyoda/skills/docs/evaluations/evals.json`
- Modify: `cyoda/skills/auth/SKILL.md`
- Modify: `cyoda/skills/auth/evaluations/evals.json`
- Modify: `cyoda/skills/app/SKILL.md`
- Modify: `cyoda/skills/app/evaluations/evals.json`

---

- [ ] **Step 1: Update `cyoda/skills/docs/SKILL.md`**

Replace the `If output contains CYODA_CLI_NOT_INSTALLED` block with:

```markdown
**If output contains `CYODA_CLI_NOT_INSTALLED`:**

Ask the user once per session:

> *"Local `cyoda` CLI is not installed. It's recommended for development — run `/cyoda:setup` (local mode) to install it. Would you like to do that now, or should I use the online help at https://docs.cyoda.net/help/ to answer your question?"*

- If user wants to install: invoke `/cyoda:setup` (local mode), then re-invoke this skill.
- If user prefers online help (or already answered "no" earlier in this conversation): fetch `https://docs.cyoda.net/help/index.json` to discover available topics, then fetch `https://docs.cyoda.net/help/<slug>.md` for the relevant topic. URL mapping: `cyoda help A B C` → `https://docs.cyoda.net/help/a/b/c/`. This surface mirrors the CLI help and is designed for agent access.
```

Also update point 2 in the CLI-installed section — replace "fetches `https://docs.cyoda.net/llms.txt` first" supplement reference to be consistent:

```markdown
2. If the answer is not fully covered by local help, supplement: fetch `https://docs.cyoda.net/llms.txt` first to identify the relevant page, then fetch that page directly.
```

Remove the "Note if the web docs may differ from the installed version" bullet (no version pinning).

- [ ] **Step 2: Update `cyoda/skills/docs/evaluations/evals.json`**

Replace eval id=2 entirely:

```json
{
  "id": 2,
  "prompt": "What's the endpoint to trigger a transition? (cyoda CLI is not installed)",
  "expected_output": "Asks the user whether to install cyoda locally or use the online help at https://docs.cyoda.net/help/. If user chooses online: fetches /help/index.json, then fetches the relevant /help/<slug>.md page, synthesizes the answer.",
  "files": {},
  "assertions": [
    { "id": "detects-cli-missing", "text": "Detects that cyoda CLI is not installed", "type": "behavior" },
    { "id": "asks-install-or-online", "text": "Asks the user whether to install via /cyoda:setup or use the online help at https://docs.cyoda.net/help/", "type": "behavior" },
    { "id": "fetches-index-json", "text": "When user chooses online, fetches https://docs.cyoda.net/help/index.json to discover topics", "type": "behavior" },
    { "id": "fetches-slug-md", "text": "Fetches https://docs.cyoda.net/help/<slug>.md for the relevant topic using the cyoda-help URL mapping", "type": "behavior" },
    { "id": "synthesizes-answer", "text": "Synthesizes a direct answer with the transition endpoint", "type": "behavior" },
    { "id": "does-not-block", "text": "Does NOT refuse to help — proceeds with online docs if user declines install", "type": "behavior" },
    { "id": "does-not-ask-again", "text": "Does NOT ask again if the user already declined install earlier in the conversation", "type": "behavior" }
  ]
}
```

- [ ] **Step 3: Update `cyoda/skills/auth/SKILL.md`**

In **Step 4 — Obtain JWT token**, replace:

```markdown
If the cyoda CLI is installed, first confirm the current-version endpoint:
```bash
which cyoda >/dev/null 2>&1 && cyoda help config auth --format=markdown 2>/dev/null | head -40
```
```

With:

```markdown
First confirm the current-version endpoint:
```bash
which cyoda >/dev/null 2>&1 && cyoda help config auth --format=markdown 2>/dev/null | head -40 || echo "CLI_NOT_INSTALLED"
```
If the output contains `CLI_NOT_INSTALLED`: fetch `https://docs.cyoda.net/help/config/auth.md` for the current-version endpoint reference.
```

Also replace the on-failure line:

```markdown
If this returns 4xx/5xx: run `cyoda help config auth` to get the current-version endpoint for your installation. Do NOT try alternate paths — fix the one call based on what `cyoda help` tells you.
```

With:

```markdown
If this returns 4xx/5xx: run `cyoda help config auth` (or fetch `https://docs.cyoda.net/help/config/auth.md` if CLI is absent) to get the correct endpoint. Do NOT try alternate paths.
```

- [ ] **Step 4: Update `cyoda/skills/auth/evaluations/evals.json`**

In eval id=5, update the two assertions about cyoda help fallback:

```json
{ "id": "no-path-guessing", "text": "Does NOT iterate through multiple token endpoint paths on failure — consults 'cyoda help config auth' or https://docs.cyoda.net/help/config/auth.md instead", "type": "behavior" },
{ "id": "consults-help-on-failure", "text": "If token call fails, consults 'cyoda help config auth' or fetches https://docs.cyoda.net/help/config/auth.md before retrying — does not guess alternate paths", "type": "behavior" }
```

In eval id=6, update the two assertions:

```json
{ "id": "consults-cyoda-help-on-4xx", "text": "After receiving a 4xx error, consults 'cyoda help config auth' or fetches https://docs.cyoda.net/help/config/auth.md before attempting any retry", "type": "behavior" },
{ "id": "no-path-guessing-on-failure", "text": "Does NOT try /oauth/token, /auth/token, or any other alternate paths — only retries after reading cyoda help or web help output", "type": "behavior" }
```

- [ ] **Step 5: Update `cyoda/skills/app/SKILL.md`**

In **Step 2**, replace:

```markdown
- If **not connected**: ask — "Will you develop locally with cyoda-go, or connect to Cyoda Cloud?"
  - **Local (recommended for development):** Run `/cyoda:setup` → choose local
  - **Cloud:** Run `/cyoda:setup` → choose cloud, then `/cyoda:auth`
```

With:

```markdown
- If **not connected**: present both options as co-equal:
  - **Local cyoda-go** (recommended for development — full control, offline-capable): Run `/cyoda:setup` → choose local
  - **Cyoda Cloud** (coming soon — no local install needed): Run `/cyoda:setup` → choose cloud, then `/cyoda:auth`
```

- [ ] **Step 6: Update `cyoda/skills/app/evaluations/evals.json`**

In eval id=3, add assertion:

```json
{ "id": "presents-co-equal-options", "text": "Presents local cyoda-go and Cyoda Cloud as co-equal options — does not describe local as the primary default", "type": "behavior" }
```

- [ ] **Step 7: Commit**

```bash
git add cyoda/skills/docs/SKILL.md cyoda/skills/docs/evaluations/evals.json \
  cyoda/skills/auth/SKILL.md cyoda/skills/auth/evaluations/evals.json \
  cyoda/skills/app/SKILL.md cyoda/skills/app/evaluations/evals.json
git commit -m "feat: web help fallback and cloud-first support in docs, auth, app skills"
```

- [ ] **Step 8: Run evals for cyoda:docs, cyoda:auth, cyoda:app**

Follow the eval process in CLAUDE.md: spawn executor subagents (one per eval, parallel, background), then grader subagents, then aggregate. Skills to eval: `docs`, `auth`, `app`.

---

## Task: File placement conventions for `cyoda:build`

**Goal:** Generated files (entity models, workflow JSON, sample data, configs) use versioned, entity-based names (`{entity}-v{version}-{type}`) and are placed in language-standard resource folders detected at runtime.

**Design:** `docs/superpowers/specs/2026-04-24-cyoda-plugin-design.md` § `cyoda:build` → File placement

- [ ] **Step 1: Update `cyoda/skills/build/SKILL.md`**

Add a **File placement** section. The skill must:
1. Scan the project root for `pom.xml`/`build.gradle` (Java), `package.json`+`tsconfig.json` (TS), `package.json` alone (JS), `pyproject.toml`/`requirements.txt`/`setup.py` (Python)
2. If no build file: scan for existing `model/`, `workflow/`, `config/`, `data/` dirs and mirror that layout
3. If nothing found: fall back to TypeScript defaults (`src/models/`, `src/workflows/`, `src/data/`, `src/config/`)
4. Write files using pattern `{entity}-v{version}-{type}` — entity+version is the primary identifier, type suffix comes last:
   - Model: `OrderV1.java` / `OrderV1.ts` / `order_v1_model.py` (language casing)
   - Workflow JSON: `workflow/order-v1-workflow.json`
   - Sample data: `data/order-v1-sample.json`
   - Import/export config: `config/order-v1-config.json`
   - When a new model version is created, existing versioned files are left untouched; new files are written alongside (`order-v2-workflow.json`, etc.)

- [ ] **Step 2: Update `cyoda/skills/build/evaluations/evals.json`**

Add evals covering:
- Happy path: Java project (`pom.xml` present) → workflow to `src/main/resources/workflow/order.json`, model to `src/main/java/{pkg}/model/Order.java`
- Edge case: no build file, existing `workflow/` dir found → mirrors that layout, versioned naming preserved
- Edge case: multiple entities → each gets its own file (`workflow/order-v1-workflow.json`, `workflow/invoice-v1-workflow.json`)
- Edge case: entity bumped to v2 → `order-v1-workflow.json` untouched, `order-v2-workflow.json` written alongside

- [ ] **Step 3: Commit**

```bash
git add cyoda/skills/build/SKILL.md cyoda/skills/build/evaluations/evals.json
git commit -m "feat(build): scan-first file placement with entity-based naming"
```

- [ ] **Step 4: Run evals for cyoda:build**

Follow the eval process in CLAUDE.md.
