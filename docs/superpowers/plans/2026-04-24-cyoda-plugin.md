# Cyoda Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `cyoda` Claude Code plugin with 11 skills, a connection monitor, and plugin scaffold that replaces AI Studio for Cyoda application development.

**Architecture:** Each skill is a self-contained `SKILL.md` + supporting files. No shared code between skills — they coordinate via skill invocation. Connection state is shared via a `.cyoda/config` file read at invocation time using dynamic context injection (`!`command``). The plugin follows the `.claude-plugin/plugin.json` standard.

**Tech Stack:** Claude Code plugin format (SKILL.md, YAML frontmatter), JSON (evals, plugin manifest, templates), Bash (dynamic context injection, `allowed-tools`), Markdown (supporting docs)

---

## File Map

```
cyoda/
├── .claude-plugin/plugin.json
├── README.md
├── monitors/monitors.json
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

## Task 3: monitors/monitors.json

**Files:**
- Create: `cyoda/monitors/monitors.json`

- [ ] **Step 1: Write monitors config**

```json
[
  {
    "name": "cyoda-config-watcher",
    "command": "while true; do inotifywait -qq -e modify,create .cyoda/config 2>/dev/null || fswatch -1 .cyoda/config 2>/dev/null || sleep 5; cat .cyoda/config 2>/dev/null | grep -E 'CYODA_ENDPOINT|CYODA_ENV' | tr '\\n' ' '; echo '— config updated'; done",
    "description": "Watches .cyoda/config for changes and reports new connection config when setup or login completes"
  }
]
```

Save to `cyoda/monitors/monitors.json`.

Note: `inotifywait` is Linux (inotify-tools), `fswatch` is macOS. The monitor attempts both and falls back to polling every 5 seconds. During implementation, verify this works cross-platform or simplify to polling-only for reliability.

- [ ] **Step 2: Commit**

```bash
git add cyoda/monitors/
git commit -m "feat: add cyoda config watcher monitor"
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
description: Look up Cyoda documentation. Uses local `cyoda help` (version-specific, preferred for API details) with web docs as fallback. Synthesizes direct answers — never dumps raw output. Auto-invoked when Cyoda API questions arise.
when_to_use: When the user asks how to use a Cyoda API, what an endpoint does, how a concept works, or needs schema/protocol details.
allowed-tools: Bash(cyoda *) Bash(which *)
---

## Cyoda Documentation Lookup

Checking for local cyoda CLI:
```!
which cyoda 2>/dev/null && cyoda help 2>/dev/null | head -50 || echo "CYODA_CLI_NOT_INSTALLED"
```

**If output contains `CYODA_CLI_NOT_INSTALLED`:**

Ask the user: *"Local `cyoda` CLI is not installed. Local docs are version-specific and more accurate for API-level questions — I recommend installing it. Run `/cyoda:setup` to install cyoda-go locally, or I can proceed with the online docs (which reflect the latest version). What would you prefer?"*

- If user wants to install: invoke `/cyoda:setup` (local mode), then re-invoke this skill.
- If user prefers web docs: fetch from https://docs.cyoda.net/ and synthesize the answer.

**If cyoda CLI is installed:**

1. Use the `cyoda help` output above as the primary source.
2. For the specific question asked, also run:
```!
cyoda help 2>/dev/null
```
3. If the answer is not fully covered by local help, supplement with web docs at https://docs.cyoda.net/
4. For gRPC/schema details, reference: https://github.com/Cyoda-platform/cyoda-docs/tree/main/src/schemas
5. For REST API details, reference: https://docs.cyoda.net/openapi/openapi.json

**Always:**
- Synthesize a direct, specific answer to the question asked
- Never paste raw `cyoda help` output without explanation
- Prefer local CLI output over web docs for API-level specifics
- Note if the web docs may differ from the installed version
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
    "Asks user whether to install via /cyoda:setup or use web docs",
    "Does not proceed without user choice",
    "Explains why local docs are preferred"
  ],
  "antiPatterns": [
    "Silently falling back to web docs without asking",
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

Will you develop locally with cyoda-go, or connect straight to Cyoda Cloud?

- **Local (recommended for development):** Run `/cyoda:setup` → choose local
- **Cloud:** Run `/cyoda:setup` → choose cloud, then `/cyoda:auth`

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
git commit -m "feat: complete cyoda plugin — 11 skills, monitor, scaffold, eval suite passing"
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

**Fix:** Step 2 now explains M2M credentials (machine-to-machine, identify the application not a user), asks if user already has them, directs to AI Studio if not, and notes that credentials may be deleted on environment redeploy.

### 5. AI Studio guidance + correct URLs in `cyoda:setup`

**Problem:** Cloud step 1 pointed to `https://docs.cyoda.net/` for sign-up (wrong) and used `https://api.eu.cyoda.net` as the endpoint example (wrong format).

**Fix:** Cloud step 1 now directs to `https://ai.cyoda.net/` and explains that the user can prompt AI Studio to create/list/redeploy environments. Endpoint example updated to correct format: `https://client-<hash>-<env>.eu.cyoda.net`.

### 6. Technical user creation via AI Studio (`cyoda:auth` + `cyoda:setup`)

**Problem:** No guidance on how to create M2M credentials through AI Studio.

**Fix:** Both skills now explain that AI Studio at `https://ai.cyoda.net/` accepts conversational prompts for credential management ("create a technical user"). Also covers the post-redeploy case where credentials may need to be recreated.

### 7. Proactive `cyoda help` lookup in `cyoda:build` Step 4

**Problem:** Step 4 showed a hardcoded curl example for workflow import without first establishing the entity model. Claude attempted the wrong sequence, received 404s, and only consulted `cyoda help` after failure.

**Fix:** Step 4 now runs `cyoda help models` + `cyoda help workflows` as a mandatory first sub-step before issuing any curl commands. The skill retains conceptual descriptions (create model → import workflow → lock) but no hardcoded endpoint paths. `Bash(cyoda *)` added to `allowed-tools`. Eval #4 added asserting docs are consulted before any POST.

---

## Post-Launch Improvements (2026-05-01)

Identified from real user session (`_developer/conversation.md`). Three recurring failures observed when building a sample Cyoda application. All changes applied to skill files and evals.

### 1. Correct OAuth endpoint and Basic auth in `cyoda:auth`

**Problem:** Step 3 listed several possible OAuth endpoint paths ("Common paths: /oauth/token, /auth/token, /api/auth/token"), causing Claude to iterate through 6+ paths before finding the correct one. The Cyoda Cloud OAuth endpoint requires credentials in the `Authorization: Basic` header (Base64-encoded `client_id:client_secret`), not in the request body.

**Fix:** Step 3 now uses the known-good pattern as the primary attempt: `POST {endpoint}/api/oauth/token` with `Authorization: Basic base64(client_id:client_secret)` header and `grant_type=client_credentials` in the form body (no credentials in body). Vague "try these paths" note replaced with a self-correction rule: "If this returns 4xx/5xx, run `cyoda help config auth` — do NOT try alternate paths." Added eval #5 asserting Basic auth header and `/api/oauth/token` on first attempt.

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

### 2. CORS/OPTIONS diagnostics in `cyoda:build`

**Problem:** The build skill used `curl -X OPTIONS` to probe CORS headers in anticipation of a file:// SPA use case. The OPTIONS probe returned misleading results (405 Method Not Allowed), triggering a long search for the cyoda binary to inspect CORS config — a 90-line dead end.

**Fix:** Added explicit prohibition: "Do not use curl OPTIONS for CORS diagnostics — CORS issues are a setup concern, not a build concern. Direct the user to `/cyoda:setup`." Mirrored in design doc under `cyoda:build` API rule.

### 3. Model version handling in `cyoda:build`

**Problem:** API calls hardcoded version `1` (e.g. `/api/entity/JSON/{entity}/1`). The `1` is the model version — if an entity already exists, blindly using version 1 may conflict with an existing model or miss a newer version.

**Fix:** Step 1 now explicitly notes to capture the version number from the `GET /api/model` response. Step 2 adds a version decision prompt when the target entity already exists: "Update existing version N, or create a new version N+1?" New entities default to version 1. All subsequent API calls use the resolved `{version}` variable. Updated design doc to reflect `{version}` instead of `1` in endpoint examples. Added eval #9 asserting the version decision is surfaced when an entity already exists.
