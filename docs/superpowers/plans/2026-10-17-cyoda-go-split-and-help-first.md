# cyoda-go / Cloud Split, v0.8.4 Update, Help-First Skills — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the `cyoda` plugin into a cloud-agnostic cyoda-go v0.8.4 dev package whose skills are thin, smoke-tested wrappers over `cyoda help`, with the Cloud skills parked at a git tag, plus a new `deploy` skill.

**Architecture:** Skills carry conversation, step order and judgment. Three shared helper scripts under `cyoda/scripts/` handle everything mechanical:
- profile resolution
- authenticated API calls, with the production guard and token refresh
- help lookup: instance first, then binary, then web

Skills call those scripts via `${CLAUDE_PLUGIN_ROOT}` and point at named `cyoda help` topic sections for facts. A bash smoke harness runs reference scenarios against a throwaway in-memory, mock-auth cyoda-go, and its payloads come from the skills' own `examples/` and `templates/`. A lint script guards against known-stale strings.

**Tech Stack:**
- Claude Code plugin skills (Markdown + YAML frontmatter)
- bash, `jq`, `curl`, `envsubst`, `shellcheck`
- cyoda-go v0.8.4 binary
- Go ≥ 1.26.7 (Phase B compute harness only)
- `helm` (Phase B template checks only)

**Spec:** `docs/superpowers/specs/2026-10-17-cyoda-go-split-and-help-first-design.md`. Itemized stale-claim worklist: `docs/superpowers/specs/2026-10-17-v084-audit.md`.

## Global Constraints

- **Branch:** work on `feat/cyoda-go-split-help-first`. Never push or create tags on the remote without the user's explicit go-ahead.
- **Repo rules (`CLAUDE.md`):**
  - Invoke `superpowers:writing-skills` before authoring or editing any `SKILL.md`.
  - `SKILL.md` stays under 500 lines.
  - Every skill has `evaluations/evals.json` with ≥ 3 cases (happy, edge, failure).
- **`disable-model-invocation: true`** on exactly `app`, `setup`, `build`, `test`, `deploy`, `auth`. Not on `status`, `docs`, `design`, `compute`, `debug`.
- **Hand-offs:** a hand-off to a flagged skill is written as "next, type `/cyoda:<x>`" with a one-line reason. It never says "invoke".
- **No Cloud in `cyoda/`:** skill wording never offers or recommends Cyoda Cloud. Identifiers like `org.cyoda.cloud.api.grpc` are fine. If the user asks about Cloud or migration, the answer is "not covered by this plugin". Trino SQL analytics is "not available in cyoda-go".
- **Unshipped features:** Notifications are phrased "coming soon — check `cyoda help` for availability".
- **Source of truth when references disagree:** cyoda-go code at `v0.8.4`, then `cyoda help`, then docs.cyoda.net. The docs getting-started page is known-wrong (cyoda-docs#134).
- **No embedded reference material in skills.** No endpoint tables, env-var lists or schema JSON. Point at `cyoda help <topic>` plus a section name.
- **Help-bug workarounds** are allowed only when listed in the spec's Upstream table, with an issue number.
- **Canonical model order:** import `SAMPLE_DATA` → unique keys (UNLOCKED only) → lock → `changeLevel` (optional) → workflow import → entities.
- **Pinned facts:**
  - workflow schema version is read from `cyoda help workflows schema-version versions` (current `1.4`), never hard-coded in `SKILL.md`
  - health is `GET /api/health` on the API port; `/livez` and `/readyz` are on the admin listener only
  - model list is `GET /api/model/` (trailing slash; `/api/model` is 404)
  - fire a transition without changing data with `PATCH /api/entity/JSON/{id}/{t}`, `Content-Type: application/merge-patch+json`, `If-Match: *`, body `{}`
  - Homebrew is `brew install cyoda/cyoda-go/cyoda`
  - tag routing is any-one-overlap, exact and case-sensitive (`cyoda help grpc` TAG ROUTING)
  - default response timeout 30 s; keep-alive 10 s interval, 30 s timeout
  - image `ghcr.io/cyoda/cyoda:<X.Y.Z>`; Helm repo `https://cyoda.github.io/cyoda-go`, pinned by appVersion
- **Plugin config:** `${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}`. Profile fields are `endpoint`, `env` (`development`|`production`) and optional `tokenCommand`. The plugin never writes tokens or secrets.
- **Repo URLs** use the `Cyoda` org: `github.com/Cyoda/cyoda-skills`, `github.com/Cyoda/cyoda-go`.
- **Version:** dev plugin `0.4.0` (`cyoda/.claude-plugin/plugin.json`, kept in step in `cyoda/gemini-extension.json`).
- **Smoke server:** `CYODA_STORAGE_BACKEND=memory`, `CYODA_IAM_MODE=mock`, ports HTTP 18080, gRPC 19090, admin 19091, with `HOME` and `XDG_CONFIG_HOME` set to a temp dir.

## Review Focus

1. **Stale user config.** An existing config whose active profile has a stored `token` and an unreachable or old endpoint. Expect a neutral warning and an offer to switch to `default`; no crash and no Cloud wording. Owner: Task 4 (`test_profile_stale_token`, `test_status_unreachable`).
2. **Production profile plus a mutating call without confirmation.** Expect a refusal with exit 3 and nothing sent. A GET still works. Owner: Task 4 (`test_call_production_guard`).
3. **Failing token command.** A `tokenCommand` that fails or prints nothing. Expect exit 4 and a clear message, and never a request with an empty `Bearer` header. Owner: Task 4 (`test_call_token_command_failure`).
4. **Local binary version differs from the targeted instance.** Expect help to come from the instance and `status` to print a version-mismatch warning. Owner: Task 4 (`test_help_prefers_instance`, `test_status_version_mismatch`).
5. **Developer's own `~/.config/cyoda/cyoda.env`.** A file that sets `CYODA_IAM_MODE=jwt` (or similar) must not affect smoke runs. Owner: Task 3 (`test_runner_ignores_user_cyoda_env`).

---

## File Structure

```
.claude-plugin/marketplace.json            modify: owner/description cloud-free (still lists only "cyoda")
CLAUDE.md                                  modify: side-effect list; eval note; smoke/lint commands
README.md                                  modify: Cyoda/cyoda-skills URL, skills table, release notes
docs/history/cloud-skills.md               create: pointer to tag cloud-frozen-0.3.0
docs/superpowers/specs/2026-10-17-help-map.md   create (Task 2): skill → help topic/section map + help audit verdicts
cyoda/.claude-plugin/plugin.json           modify: description, version 0.4.0, repository URL
cyoda/gemini-extension.json  cyoda/GEMINI.md  cyoda/README.md   modify
cyoda/scripts/cyoda-profile.sh             create: resolve active profile → JSON
cyoda/scripts/cyoda-call.sh                create: authenticated API call + prod guard + token refresh
cyoda/scripts/cyoda-help.sh                create: help lookup instance → binary → web, section extraction
cyoda/scripts/cyoda-status.sh              create: one-line status + warnings
cyoda/skills/{app,setup,status,auth,docs,design,build,compute,test,debug}/SKILL.md   rewrite
cyoda/skills/*/evaluations/evals.json      rewrite (all), create for deploy
cyoda/skills/build/templates/workflow.json             rewrite (placeholders; ${SCHEMA_VERSION})
cyoda/skills/build/templates/sample-entity.json        keep
cyoda/skills/build/templates/entity-config.json        create: -config.json schema example
cyoda/skills/build/templates/cyoda-manifest.json       create: manifest example
cyoda/skills/build/examples/hello-world/               create: sample.json, workflow.json, config.json (scenario 1)
cyoda/skills/build/examples/loopback/                  create (scenario 2)
cyoda/skills/build/examples/error-states/              create (scenario 3)
cyoda/skills/build/examples/scheduled/                 create (scenario 4)
cyoda/skills/build/examples/hello-world.md             rewrite: walkthrough referencing hello-world/ files
cyoda/skills/debug/examples/queries.md + queries/      create (scenarios 5, 6: stats, point-in-time, soft delete payloads)
cyoda/skills/design/resources/best-practices.md        create (content = cyoda-go#684 item L draft)
cyoda/skills/design/resources/design-guidelines.md     modify: dedupe vs best-practices, fix v0.8.4 contradictions
cyoda/skills/design/resources/patterns.md              modify: remove 3 non-existent patterns, add scheduled transitions
cyoda/skills/compute/{examples,resources}/*            modify: tag routing, timeouts, help pointers
cyoda/skills/test/templates/smoke-test.sh              rewrite: uses canonical order, PATCH, quoted header
cyoda/skills/auth/templates/get-token.sh               create
cyoda/skills/deploy/SKILL.md                           create
cyoda/skills/deploy/templates/seed.sh                  create
cyoda/skills/deploy/templates/verify.sh                create
cyoda/skills/deploy/templates/compose.single-user.yaml create
cyoda/skills/deploy/templates/compose.shared.yaml      create
cyoda/skills/deploy/templates/secrets-checklist.md     create
cyoda/skills/deploy/templates/values.yaml              create (Phase B)
cyoda/skills/migrate/                                  delete
tests/lib/assert.sh                        create: assert_eq, assert_contains, assert_status, fail/pass counters
tests/lib/server.sh                        create: start_server/stop_server for the in-memory instance
tests/scripts/test-*.sh                    create: unit tests for cyoda/scripts/*
tests/smoke/run.sh                         create: runs lint, script tests, scenarios; summary
tests/smoke/lint.sh                        create
tests/smoke/scenarios/0{1..8}-*.sh         create
tests/smoke/compute/                       create (Phase B): go.mod, main.go, scenario 07 driver
tests/smoke/README.md                      create
```

Each scenario script is `source`d by `run.sh`, with `assert.sh` and `server.sh` already loaded and `$BASE` set to `http://localhost:18080/api`. Each defines a single function `scenario_main` that returns non-zero on failure.

---

# Phase A

### Task 1: Park the Cloud skills at a tag

**Files:**
- Create: `docs/history/cloud-skills.md`

**Interfaces:**
- Produces: local annotated tag `cloud-frozen-0.3.0` on `d977dd9`.

- [ ] **Step 1: Create the tag locally**

```bash
git tag -a cloud-frozen-0.3.0 d977dd9 -m "Cyoda Cloud skills as of plugin v0.3.0, parked while Cloud is paused"
```

- [ ] **Step 2: Verify the tag holds the cloud skills**

Run: `git show cloud-frozen-0.3.0:cyoda/skills/migrate/SKILL.md | head -3 && git show cloud-frozen-0.3.0:cyoda/skills/auth/SKILL.md | grep -c "Cyoda Cloud"`
Expected: frontmatter `name: migrate` printed; count ≥ 1.

- [ ] **Step 3: Write `docs/history/cloud-skills.md`**

Under 15 lines, covering:
- the Cloud skills (`auth`, `migrate`, the cloud branches of `setup`, `status` and `app`) are parked at tag `cloud-frozen-0.3.0`
- they'll be redesigned, not revived, when the service returns
- how to inspect them: `git checkout cloud-frozen-0.3.0`

It must not include install instructions.

- [ ] **Step 4: Commit**

```bash
git add docs/history/cloud-skills.md
git commit -m "docs: record cloud skills parked at tag cloud-frozen-0.3.0"
```

- [ ] **Step 5: Ask the user for go-ahead to push the tag** (`git push origin cloud-frozen-0.3.0`). Don't push without it, and carry on with Task 2 either way.

### Task 2: Help audit and help map

Every later skill task points at the help sections listed here, so they must be verified first.

**Files:**
- Create: `docs/superpowers/specs/2026-10-17-help-map.md`

**Interfaces:**
- Produces: a table with columns `skill | step | help path (e.g. models) | section (e.g. LIFECYCLE) | verdict (ok / wrong → issue # / missing)`. Skill tasks 7–12 use only rows marked `ok`, or rows marked wrong with an issue number listed in the spec's Upstream table.

- [ ] **Step 1: List the steps each dev skill needs facts for**

Use the spec's per-skill sections and the audit §1. Starting set of help paths:
- `models` (LIFECYCLE, ENDPOINTS, ERRORS)
- `crud` (ENDPOINTS, OPTIMISTIC CONCURRENCY, POINT-IN-TIME SEMANTICS, ERRORS)
- `workflows` (WORKFLOW SCHEMA, TRANSITIONS, PROCESSORS, SCHEDULED TRANSITIONS, CRITERIA, IMPORT REQUEST, EXPORT RESPONSE, ENGINE EXECUTION)
- `workflows schema-version versions`
- `grpc` (CONNECTION, COMPUTE MEMBER PROTOCOL, KEEPALIVE, TAG ROUTING)
- `search` (CONDITION DSL, ENDPOINTS)
- `audit` (ENDPOINTS)
- `errors` (ERROR CODE INDEX)
- `run` (RUN MODES, HEALTH PROBES, PORT LAYOUT)
- `helm` (VALUES, SECRETS PROVISIONING, INSTALL / UPGRADE / UNINSTALL)
- `auth`, `auth tokens`, `auth clients`
- `config auth`, `config grpc`
- `quickstart` (DEFAULTS, PRODUCTION CHECKLIST)

- [ ] **Step 2: Check each row against the v0.8.4 code**

Source: `git clone --depth 1 --branch v0.8.4 https://github.com/Cyoda/cyoda-go.git` into the scratchpad. Read the section with `cyoda help <path> --format=json | jq -r '.sections[] | select(.name=="<SECTION>") | .body'`. Record the verdict. Known-wrong rows are already filed: #677, #679, #681, #682, #683.

- [ ] **Step 3: For each new mismatch, add a row "wrong → TO FILE" and stop to ask the user** whether to file it (the user has approved filing quick help fixes against milestone v0.9.0 so far). After filing, add the issue to the spec's Upstream table.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-10-17-help-map.md docs/superpowers/specs/2026-10-17-cyoda-go-split-and-help-first-design.md
git commit -m "docs(spec): help map and help audit for v0.8.4"
```

### Task 3: Test harness, server lifecycle, lint

**Files:**
- Create: `tests/lib/assert.sh`, `tests/lib/server.sh`, `tests/smoke/run.sh`, `tests/smoke/lint.sh`, `tests/smoke/README.md`
- Create: `tests/smoke/test-harness.sh` (tests for the harness itself)
- Modify: `CLAUDE.md`: add a "Smoke tests" section with `tests/smoke/run.sh [--only NN] [--allow-version]` and `tests/smoke/lint.sh`

**Interfaces:**
- Produces, in `assert.sh`:
  - `assert_eq <actual> <expected> <msg>`
  - `assert_contains <haystack> <needle> <msg>`
  - `assert_status <expected_code> <actual_code> <msg>`
  - globals `PASS` / `FAIL`
  - `report` (prints the summary, returns 1 if `FAIL>0`)
- Produces, in `server.sh`:
  - `start_server` sets `SMOKE_TMP` (temp dir), `HOME=$SMOKE_TMP/home`, `XDG_CONFIG_HOME=$SMOKE_TMP/home/.config`, `BASE=http://localhost:18080/api`. It starts `cyoda` with the Global Constraints env, waits up to 15 s for `$BASE/health`, and returns 1 with the last 20 log lines on timeout.
  - `stop_server` kills that PID and removes `SMOKE_TMP`.
- Produces, in `run.sh`:
  - checks `cyoda --version` contains `0.8.4` (exit 2 otherwise, unless `--allow-version`)
  - runs `lint.sh`, then `tests/scripts/test-*.sh`, then sources each `tests/smoke/scenarios/*.sh` in order and calls `scenario_main` against a fresh server per scenario
  - `--only NN` restricts to one scenario
- Produces, in `lint.sh`: exit 1 listing `file:line: <rule>` for every hit under `cyoda/` (excluding `cyoda/skills/*/evaluations/`). The rules:

| rule id | pattern (extended grep) |
|---|---|
| `stale-tap` | `cyoda-platform/cyoda-go` |
| `stale-org-url` | `github.com/Cyoda-platform` |
| `workflow-version-1` | `"version": *"1"` |
| `readyz-api-port` | lines matching `/readyz` that contain neither `9091` nor `admin`/`ADMIN` |
| `discover-mode` | `[Dd]iscover mode` |
| `timeout-60s` | `\b60 ?s(ec(ond)?s?)?\b` in files under `cyoda/skills/compute/` or `cyoda/skills/debug/` |
| `cloud` | `Cyoda Cloud`, or lines matching `\.cyoda\.net` that don't contain `docs.cyoda.net` (BSD-grep compatible: two greps) |
| `invoke-flagged` | `[Ii]nvoke .?/cyoda:(app\|setup\|build\|test\|deploy\|auth)` |
| `model-list-no-slash` | `/api/model["' )]` |
| `shellcheck` | `shellcheck` on `cyoda/scripts/*.sh cyoda/skills/*/templates/*.sh tests/**/*.sh` (missing `shellcheck` → exit 1 with `brew install shellcheck`) |

- [ ] **Step 1: Write `tests/smoke/test-harness.sh`**

Tests:
- `test_server_starts_and_stops`: `start_server`; `curl -s $BASE/health` equals `{"status":"UP"}`; `stop_server`; the port is free afterwards.
- `test_runner_ignores_user_cyoda_env` (Review Focus 5):
  - write `CYODA_IAM_MODE=jwt` to `$REAL_HOME_FIXTURE/.config/cyoda/cyoda.env`, export `HOME` to that fixture, then `start_server`
  - assert `GET $BASE/model/` returns 200 without an Authorization header
  - assert the server log contains `IAM mock`
- `test_lint_flags_stale_strings`: copy a fixture file containing `brew tap cyoda-platform/cyoda-go` and `"version": "1"` into a temp `cyoda/` tree. Run `lint.sh --root <tmp>`. Assert exit 1 and that the output contains both `stale-tap` and `workflow-version-1`.

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/smoke/test-harness.sh`
Expected: FAIL. `assert.sh` / `server.sh` / `lint.sh` aren't found.

- [ ] **Step 3: Implement `assert.sh`, `server.sh`, `lint.sh` (with `--root <dir>`, default repo root), and `run.sh`**

- [ ] **Step 4: Run the harness tests**

Run: `bash tests/smoke/test-harness.sh`
Expected: `3 passed, 0 failed`.

- [ ] **Step 5: Run lint against the current repo to record the baseline**

Run: `bash tests/smoke/lint.sh; echo "exit=$?"`
Expected: `exit=1`, with hits for at least `stale-tap`, `workflow-version-1`, `readyz-api-port`, `discover-mode`, `cloud`. Later tasks drive this to zero.

- [ ] **Step 6: Commit**

```bash
git add tests/ CLAUDE.md
git commit -m "test: smoke harness, in-memory server lifecycle, stale-string lint"
```

### Task 4: Shared helper scripts

**Files:**
- Create: `cyoda/scripts/cyoda-profile.sh`, `cyoda/scripts/cyoda-call.sh`, `cyoda/scripts/cyoda-help.sh`, `cyoda/scripts/cyoda-status.sh`
- Test: `tests/scripts/test-profile.sh`, `tests/scripts/test-call.sh`, `tests/scripts/test-help.sh`, `tests/scripts/test-status.sh`

**Interfaces:**
- `cyoda-profile.sh`
  - prints one JSON object to stdout: `{"profile": str, "endpoint": str|null, "env": "development"|"production", "tokenCommand": str|null, "warnings": [str]}`
  - when there is no config, prints `{"profile":"default","endpoint":null,"env":"development","tokenCommand":null,"warnings":[]}`
  - stored-token warning text, exactly: `profile <P> contains a stored token, which this plugin no longer reads; you can remove it`
  - honours `CYODA_PLUGIN_CONFIG`
  - always exits 0, unless the JSON is invalid: then exit 1 and `invalid config: <path>`
- `cyoda-call.sh [--confirm-production] <METHOD> <PATH> [curl-data/header args...]`
  - `PATH` is relative to `<endpoint>/api`, e.g. `/model/`
  - prints the response body to stdout and `HTTP_STATUS=<code>` to stderr
  - exit codes:
    - 0: 2xx
    - 22: ≥ 400, after the auth retry
    - 3: production refusal (non-GET on `env=production` without the flag), with stderr `PRODUCTION: ask the user to confirm, then re-run with --confirm-production`
    - 4: `tokenCommand` failed or printed nothing, with stderr `token command failed: <cmd>`
    - 5: no endpoint configured
  - auth header passed as one quoted argument `-H "Authorization: Bearer $TOKEN"`; no header at all when there's no `tokenCommand`
  - on 401/403, re-runs `tokenCommand` once and retries once
- `cyoda-help.sh <path...> [--section <NAME>]`
  - path words match `cyoda help` (e.g. `auth tokens`)
  - prints the topic `body`, or the section's `body` when `--section` is given
  - order:
    1. active profile instance `GET <endpoint>/api/help/<a>/<b>`
    2. local `cyoda help <a> <b> --format=json`
    3. `https://docs.cyoda.net/help/<a>/<b>.md` (whole page; `--section` ignored, with a stderr note)
  - stderr first line: `SOURCE=instance|binary|web VERSION=<v>`
  - exit 2 for an unknown topic (all sources 404)
  - exit 6 if `--section` isn't found, listing the available section names
- `cyoda-status.sh`
  - prints `STATUS=connected|unreachable|not_configured PROFILE=<p> ENDPOINT=<e> ENV=<env> VERSION=<server> BINARY_VERSION=<local|none>`, then zero or more `WARN=<text>` lines
  - server version comes from `GET <endpoint>/api/help` `.version`
  - mismatch warning text: `local cyoda <b> differs from instance <s>; help is read from the instance`
  - forwards profile warnings
  - unreachable adds `WARN=active profile <p> is unreachable; run /cyoda:setup to switch to default`

- [ ] **Step 1: Write the four test files**

They use `tests/lib/assert.sh` and `tests/lib/server.sh`, with config fixtures written to `$SMOKE_TMP` and `CYODA_PLUGIN_CONFIG` pointed at them. Tests:
- `test_profile_default_when_no_config`
- `test_profile_active_selected`
- `test_profile_stale_token`: a fixture profile with `"token":"eyJ..."` gives the exact warning text (Review Focus 1)
- `test_call_get_model_list_mock`: `cyoda-call.sh GET /model/` exits 0
- `test_call_production_guard`: `env=production`; `POST /model/x/1/lock` exits 3 and the server log shows no request to `/model/x/1/lock`; the same profile with `GET /model/` exits 0 (Review Focus 2)
- `test_call_token_command_failure`: `tokenCommand` set to `false` exits 4; `tokenCommand` set to `true` (empty output) exits 4 (Review Focus 3)
- `test_call_header_quoting`: put a shim `curl` first on `PATH` that writes each of its arguments on its own line to `$SMOKE_TMP/curl-args`. A `tokenCommand` printing `a b` → the args file contains exactly one line `Authorization: Bearer a b`.
- `test_call_retries_once_on_401`: point at a stub HTTP server (`python3 -m http.server`-style stub script in `tests/scripts/stub401.py`) that returns 401 then 200, with a `tokenCommand` that counts its invocations into a file. Assert 2 token calls, exit 0.
- `test_help_section_from_binary`: no config; `cyoda-help.sh models --section LIFECYCLE` stdout contains `LOCKED`; stderr contains `SOURCE=binary`
- `test_help_prefers_instance`: with the in-memory server as the active profile, stderr contains `SOURCE=instance VERSION=0.8.4` (Review Focus 4)
- `test_help_unknown_topic`: exits 2
- `test_help_unknown_section`: exits 6 and lists `LIFECYCLE`
- `test_status_connected`: the line starts `STATUS=connected` and contains `VERSION=0.8.4`
- `test_status_unreachable`: endpoint `http://localhost:1` gives `STATUS=unreachable` plus the unreachable WARN (Review Focus 1)
- `test_status_version_mismatch`: put a shim `cyoda` script first on `PATH` that prints `cyoda version 0.9.0` for `--version`, and assert the mismatch WARN text (Review Focus 4)

- [ ] **Step 2: Run them to see them fail**

Run: `for t in tests/scripts/test-*.sh; do bash "$t"; done`
Expected: FAIL (scripts missing).

- [ ] **Step 3: Implement the four scripts per the Interfaces block** (bash, `set -euo pipefail`, `jq` for JSON).

- [ ] **Step 4: Run the tests and shellcheck**

Run: `for t in tests/scripts/test-*.sh; do bash "$t" || exit 1; done && shellcheck cyoda/scripts/*.sh`
Expected: all pass, shellcheck clean.

- [ ] **Step 5: Check that `${CLAUDE_PLUGIN_ROOT}` expands inside a `` ```! `` block**

Create a throwaway skill `cyoda/skills/_probe/SKILL.md` whose body has a `` ```! `` block running `"${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh"`. Run: `claude -p "/cyoda:_probe" --plugin-dir ./cyoda`.

Expected: output contains `STATUS=`. If the variable isn't expanded in `` ```! `` blocks:
- use a plain fenced instruction instead ("Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`"), which is substituted in skill markdown
- record that in `CLAUDE.md` under Skill authoring

Delete `_probe/` afterwards.

- [ ] **Step 6: Commit**

```bash
git add cyoda/scripts tests/scripts CLAUDE.md
git commit -m "feat(scripts): shared profile, call, help and status helpers"
```

### Task 5: Segregation — remove Cloud from `main`, enforce flags

**Files:**
- Delete: `cyoda/skills/migrate/` (all files)
- Modify: `.claude-plugin/marketplace.json`, `cyoda/.claude-plugin/plugin.json`, `cyoda/gemini-extension.json`, `cyoda/GEMINI.md`, `cyoda/README.md`, `README.md`, `CLAUDE.md`
- Modify (frontmatter and cloud removal only; full rewrites come in later tasks): `cyoda/skills/{app,setup,status,auth,compute,debug,build,test}/SKILL.md`

**Interfaces:**
- Produces: a skill set with the flags from Global Constraints. Later tasks rewrite bodies but keep the frontmatter flags.

- [ ] **Step 1: Write the failing check `tests/smoke/test-segregation.sh`**

Tests:
- `test_no_migrate_skill`: `cyoda/skills/migrate` doesn't exist
- `test_flags`: for each of `app setup build test deploy auth`, `SKILL.md` frontmatter contains `disable-model-invocation: true` (skip `deploy` until Task 11 creates it, via an existence check); for each of `status docs design compute debug`, it doesn't
- `test_marketplace_single_plugin`: `jq '.plugins | length' .claude-plugin/marketplace.json` = 1, and `.plugins[0].name` = `cyoda`
- `test_plugin_version`: `cyoda/.claude-plugin/plugin.json` `.version` = `0.4.0`, `.repository` = `https://github.com/Cyoda/cyoda-skills`, and `.description` has no `Cloud`
- `test_lint_cloud_clean`: `lint.sh` output has no `cloud` rule hits

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/smoke/test-segregation.sh` → Expected: FAIL on every test.

- [ ] **Step 3: Apply the changes**

- Delete `migrate/`.
- Remove all Cloud branches and wording from the listed skills:
  - `app`: Step 2 cloud option, Step 6, "same API works locally and on Cyoda Cloud"
  - `setup`: the cloud mode; leave a placeholder line "Connect to an existing instance — see Task 9"
  - `status`: the cloud lines
  - `auth`: replace the body with a one-line stub "Being rewritten for cyoda-go auth (Task 9)"
  - `compute` and `debug`: cloud mentions
- Set the frontmatter flags.
- `plugin.json`: description "Build, test, and run applications on cyoda-go: entity and workflow design, compute nodes, testing, debugging, and self-hosted deployment.", version `0.4.0`, repository `https://github.com/Cyoda/cyoda-skills`.
- `gemini-extension.json`: version `0.4.0`.
- `GEMINI.md`: drop `migrate`, and add one line saying that `` ```! `` blocks in the skills don't execute under Gemini, so run the referenced `scripts/*.sh` command yourself.
- `README.md` (both):
  - skills table without `migrate`; `auth` described as "Get tokens for a self-hosted cyoda-go"
  - install command `/plugin marketplace add Cyoda/cyoda-skills`
  - drop the Cloud config example
- `CLAUDE.md` side-effect list: `setup`, `build`, `test`, `app`, `deploy`, `auth`.

- [ ] **Step 4: Run the checks**

Run: `bash tests/smoke/test-segregation.sh && bash tests/smoke/lint.sh | grep -c ': cloud' || true`
Expected: segregation tests pass; the `cloud` hit count is `0`.

- [ ] **Step 5: Commit**

```bash
git add -A cyoda .claude-plugin README.md CLAUDE.md tests/smoke/test-segregation.sh
git commit -m "refactor: remove Cloud from dev plugin; enforce side-effect skill flags"
```

### Task 6: Example payloads and smoke scenarios 1–6

The payloads are skill content that later skill tasks reference. Each scenario fails until its example exists and v0.8.4 accepts it.

**Files:**
- Create: `cyoda/skills/build/examples/{hello-world,loopback,error-states,scheduled}/{sample.json,workflow.json,config.json}`
- Create: `cyoda/skills/debug/examples/queries/{stats-group-by-state.json,search-point-in-time.json}`
- Rewrite: `cyoda/skills/build/templates/workflow.json`. It keeps `${…}` placeholders, and `"version": "${SCHEMA_VERSION}"` replaces the literal.
- Create: `cyoda/skills/build/templates/entity-config.json`, `cyoda/skills/build/templates/cyoda-manifest.json`
- Create: `tests/smoke/lib/load.sh`, `tests/smoke/scenarios/01-hello-world.sh` … `06-soft-delete.sh`

**Interfaces:**
- `entity-config.json` schema, used by `build` (Task 7) and `seed.sh` (Task 11):
  `{"uniqueKeys":[{"id":str,"fields":[str]}], "changeLevel": "ARRAY_LENGTH"|"ARRAY_ELEMENTS"|"TYPE"|"STRUCTURAL"|null, "env": {"<envName>": {"changeLevel": ...|null, "uniqueKeys": [...]?}}}`
- `cyoda-manifest.json` schema, used by Tasks 7 and 11:
  `{"manifestVersion":1,"entities":[{"name":str,"modelVersion":int,"sample":relpath,"workflow":relpath,"config":relpath}]}`. Paths are relative to the manifest's directory.
- `tests/smoke/lib/load.sh` provides:
  - `load_example <skill> <name>`: sets `EX_DIR` and exports `SCHEMA_VERSION` from `cyoda help workflows schema-version versions | jq -r .current`
  - `seed_model <entity> <version> <dir>`: canonical order via plain `curl`, so it doesn't depend on `seed.sh`
  - `create_entity <entity> <version> <json>`: echoes the id
  - `entity_state <id>`: echoes `.meta.state`
  - `patch_transition <id> <name> [json]`: PATCH merge-patch `If-Match: *`, default `{}`
  - `loopback <id> <json>`: PATCH without a transition name

  Workflow files go through `envsubst '${SCHEMA_VERSION}'` before import.

Scenario assertions:

| Scenario | Example dir | Assertions |
|---|---|---|
| `01-hello-world` | `build/examples/hello-world` | Entity created via `create_entity` reaches a terminal state through automated transitions only (`entity_state` = `completed`). `GET /entity/{id}/changes` (per `cyoda help crud`) lists ≥ 2 versions. Importing the workflow with `"version":"1"` returns 400 `WORKFLOW_SCHEMA_VERSION_UNSUPPORTED` (pins the breaking item). Creating an entity on an unimported model returns 404 `MODEL_NOT_FOUND`. |
| `02-loopback` | `build/examples/loopback` | A manual `patch_transition id submit` moves the entity to `submitted`. The automated `approve` (criterion `$.amount <= 1000`, built-in simple criterion) doesn't fire for amount 5000, so the state stays `submitted`. `loopback id '{"amount":500}'` makes the state `approved`. A PUT with an empty body returns 400. |
| `03-error-states` | `build/examples/error-states` | Invalid data (`$.email` missing) goes automatically to `errored`. `loopback` with a valid email goes back through `validating` to `ready`. A manual `cancel` from `ready` reaches `cancelled`. A second entity reaches `completed`. The workflow has ≥ 2 terminal states. |
| `04-scheduled` | `build/examples/scheduled` | A transition with a `schedule` delay of ≤ 3 s (shape per `cyoda help workflows` SCHEDULED TRANSITIONS) fires. State goes `waiting` → `expired` within 10 s (poll every 500 ms). |
| `05-queries` | `debug/examples/queries` | Create 5 entities across 2 states. `stats-group-by-state.json` posted to the stats query endpoint returns counts 3 and 2. A search with `pointInTime` set to the timestamp captured before entities 4–5 were created returns 3. No counter entity exists in the example. |
| `06-soft-delete` | `build/examples/hello-world` | `DELETE /entity/{id}` succeeds, then `GET /entity/{id}` returns 404. A `GET` with `pointInTime` before the delete returns the entity. `/changes` shows a `DELETE` entry. `cyoda help audit` ENDPOINTS for the entity lists no transition event after the delete. |

- [ ] **Step 1: Write `load.sh` and scenarios 01–06** with the assertions above. Endpoints and payload shapes come from the `cyoda help` sections in the help map (Task 2), not from memory.

- [ ] **Step 2: Run them to see them fail**

Run: `bash tests/smoke/run.sh --only 01` (then 02 … 06)
Expected: FAIL — example files missing.

- [ ] **Step 3: Write the example files and the two templates**

Rules:
- Workflows use `"version": "${SCHEMA_VERSION}"`.
- Criteria in 02 and 03 are built-in (no compute node).
- Terminal state names come from the best-practices list: `completed`, `cancelled`.

- [ ] **Step 4: Run all six**

Run: `bash tests/smoke/run.sh` → Expected: lint may still fail (later tasks); scenarios `01`–`06` PASS.

- [ ] **Step 5: Commit**

```bash
git add cyoda/skills/build/examples cyoda/skills/build/templates cyoda/skills/debug/examples tests/smoke
git commit -m "test(smoke): reference scenarios 1-6 with skill-owned example payloads"
```

### Task 7: Rewrite `build` (help-first)

Invoke `superpowers:writing-skills` first.

**Files:**
- Rewrite: `cyoda/skills/build/SKILL.md`, `cyoda/skills/build/examples/hello-world.md`
- Rewrite: `cyoda/skills/build/evaluations/evals.json`

**Interfaces:**
- Consumes:
  - `cyoda-call.sh` and `cyoda-help.sh` (Task 4)
  - the example dirs and `entity-config.json` / `cyoda-manifest.json` schemas (Task 6)
  - the help-map rows for `build` (Task 2)
- Produces:
  - `build` writes `{entity}-v{version}-{sample,workflow,config}.json`, keeping the current scan-first placement table and naming
  - `build` creates or updates `cyoda-manifest.json` at the project root

**Content requirements:**
- Steps follow the canonical model order. Each step names its help path and section (e.g. "`cyoda-help.sh models --section LIFECYCLE`").
- All API calls go through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh`. On exit 3, ask the user for confirmation and re-run with `--confirm-production`.
- Inline content is limited to order, judgment and links to `examples/`. Keep it well under 500 lines.
- When a changed model already has entities (`MODEL_HAS_ENTITIES`), the skill proposes a new model version.
- The skill asks which `changeLevel` the developer wants and records it in `-config.json`.
- It points at `design/resources/best-practices.md` (or the help topic once #684 item L ships) for: error states, terminal states, loopback, validation cycles, rejection reasons.
- Hand-offs: "next, type `/cyoda:test`".

- [ ] **Step 1: Write `evals.json`**

At least 6 cases:
- happy: new entity from scratch → canonical order with help consulted
- edge: add a state to an existing workflow
- edge: model already has entities → new version
- edge: Java project layout → placement table, plus manifest updated
- failure: import returns 400 → consults `errors` via help, doesn't guess paths
- production profile → exit 3 handled with confirmation

Each case includes assertions for:
- `consults-help`: names the help path and section used
- `no-cloud`: does not mention Cyoda Cloud
- `no-invoke`: hand-off says "type `/cyoda:test`"

- [ ] **Step 2: Write `SKILL.md` and `hello-world.md`** per the content requirements. `hello-world.md` walks through `examples/hello-world/` and contains no JSON copies.

- [ ] **Step 3: Verify**

Run: `wc -l cyoda/skills/build/SKILL.md && bash tests/smoke/lint.sh --root . 2>&1 | grep 'skills/build' ; bash tests/smoke/run.sh --only 01`
Expected: < 500 lines; no lint hits under `skills/build`; scenario 01 PASS.

- [ ] **Step 4: Commit**

```bash
git add cyoda/skills/build
git commit -m "feat(build): help-first rewrite for v0.8.4; manifest and entity config"
```

### Task 8: Rewrite `design` and best practices

Invoke `superpowers:writing-skills` first.

**Files:**
- Rewrite: `cyoda/skills/design/SKILL.md`, `cyoda/skills/design/evaluations/evals.json`
- Create: `cyoda/skills/design/resources/best-practices.md`. Its content is the "Draft content" block in section "L." of Cyoda/cyoda-go#684 (`gh issue view 684 -R Cyoda/cyoda-go --json body`). Header line: `> Temporary — superseded by cyoda help once Cyoda/cyoda-go#684 item L ships.`
- Modify: `cyoda/skills/design/resources/design-guidelines.md`. Remove anything duplicated in best-practices and anything contradicting v0.8.4 (audit §1 design rows).
- Modify: `cyoda/skills/design/resources/patterns.md`. Remove "scheduled processor", "message-triggered transition" and "one entity in several parallel workflows". Add "scheduled transition" with a pointer to `cyoda help workflows` SCHEDULED TRANSITIONS and to `build/examples/scheduled/`.

**Content requirements:**
- The skill first runs `cyoda-help.sh workflows best-practices`, then `cyoda-help.sh design`, and on exit 2 for both uses `resources/best-practices.md`.
- The design review phase checks the proposal against each best-practice bullet by name.
- Notifications use the Global Constraints wording.
- The skill keeps its 4 phases, with no cloud.

- [ ] **Step 1: Write `evals.json`**

At least 4 cases:
- happy: describe an app → entities and workflows with explicit error and terminal states
- edge: user proposes a running-total counter entity → suggests stats queries instead, naming the best practice
- edge: user asks for notifications on errors → "coming soon — check `cyoda help`" plus today's options
- failure: binary not installed → uses the web help mirror, and the design still completes

All cases carry `no-cloud`.

- [ ] **Step 2: Write the skill and resource changes.**

- [ ] **Step 3: Verify**

Run: `wc -l cyoda/skills/design/SKILL.md && bash tests/smoke/lint.sh 2>&1 | grep 'skills/design'`
Expected: < 500 lines; no hits.

- [ ] **Step 4: Commit**

```bash
git add cyoda/skills/design
git commit -m "feat(design): help-first design with fact-checked best practices"
```

### Task 9: Rewrite `setup`, `status`, `auth`

Invoke `superpowers:writing-skills` first.

**Files:**
- Rewrite: `cyoda/skills/{setup,status,auth}/SKILL.md` and their `evaluations/evals.json`
- Create: `cyoda/skills/auth/templates/get-token.sh`
- Test: `tests/scripts/test-get-token.sh`

**Interfaces:**
- Consumes: `cyoda-profile.sh`, `cyoda-status.sh`, `cyoda-help.sh` (Task 4).
- Produces:
  - `get-token.sh`:
    - reads `CYODA_CLIENT_ID` and `CYODA_CLIENT_SECRET` from env, or, if `CYODA_CLIENT_SECRET_CMD` is set, from that command's output (e.g. a keychain lookup)
    - reads `CYODA_ENDPOINT` from env
    - POSTs `grant_type=client_credentials` to `<endpoint>/api/oauth/token` with basic auth, per `cyoda help auth tokens` REQUEST FLOW
    - prints only the `access_token`
    - exits 1 with a stderr message on failure
  - Profiles written by `setup`/`auth` contain only `endpoint`, `env`, `tokenCommand`.

**Content requirements:**
- `setup`:
  - **Local mode:**
    - install via `brew install cyoda/cyoda-go/cyoda`
    - on failure, show the verbatim "run it yourself" message, and an install list of brew, `curl -fsSL https://github.com/cyoda/cyoda-go/releases/latest/download/install.sh | sh`, the release page and Docker `ghcr.io/cyoda/cyoda`, marked as a #684-K workaround
    - `cyoda init`, start, check `/api/health`, write the `default` profile
  - **Connect mode:** endpoint → probe `/api/health` → `env` → profile. For non-mock auth: "next, type `/cyoda:auth`".
  - Surfaces `cyoda-profile.sh` warnings (stale token).
- `status`:
  - a `` ```! `` block (or the fallback from Task 4 Step 5) running `cyoda-status.sh`
  - output lines `Connected to cyoda-go v<V> — <endpoint> [profile: <P>]`, a `[PRODUCTION]` tag when `ENV=production`, `Not connected — type /cyoda:setup`, and the unreachable form
  - prints every WARN
- `auth`:
  - path choice via `cyoda help auth` WHICH PATH DO I NEED?
  - writes `get-token.sh` into the project (scan for `scripts/`, else project root) and sets the profile's `tokenCommand` to its absolute path
  - explains that the app itself must renew tokens (no refresh token), pointing at `cyoda help auth tokens`
  - mock auth → "no token needed"

- [ ] **Step 1: Write `tests/scripts/test-get-token.sh`**

Run a jwt-mode server with a bootstrap client. Use `CYODA_IAM_MODE=jwt`, a signing key generated with `openssl genpkey -algorithm RSA -out $SMOKE_TMP/k.pem`, `CYODA_JWT_SIGNING_KEY_FILE`, `CYODA_BOOTSTRAP_CLIENT_ID=smoke`, `CYODA_BOOTSTRAP_CLIENT_SECRET=s3cret`; exact var names from `cyoda help config auth`. `start_server` takes an optional extra-env argument for this.

Assertions:
- `get-token.sh` prints a 3-part JWT
- `cyoda-call.sh GET /model/` with `tokenCommand` set to it exits 0
- a wrong secret → `get-token.sh` exits 1

- [ ] **Step 2: Run it to see it fail** (`get-token.sh` missing).

- [ ] **Step 3: Write `get-token.sh`, then the three skills and their evals**

Eval cases:
- setup: local happy; brew fails → verbatim message; connect to existing JWT instance → hand-off text; stale-token config → warning shown
- status: connected; unreachable; production tag; version mismatch
- auth: M2M happy; mock instance → no token; token endpoint 401 → clear error

All cases carry `no-cloud` and, where relevant, `no-invoke`.

- [ ] **Step 4: Verify**

Run: `bash tests/scripts/test-get-token.sh && bash tests/smoke/lint.sh 2>&1 | grep -E 'skills/(setup|status|auth)'`
Expected: PASS; no lint hits.

- [ ] **Step 5: Commit**

```bash
git add cyoda/skills/setup cyoda/skills/status cyoda/skills/auth tests/scripts/test-get-token.sh tests/lib/server.sh
git commit -m "feat(setup,status,auth): local + connect setup, script-backed status, cyoda-go token script"
```

### Task 10: Rewrite `docs`, `debug`, `compute`, `test`, `app`

Invoke `superpowers:writing-skills` first.

**Files:**
- Rewrite: `cyoda/skills/{docs,debug,compute,test,app}/SKILL.md` and their `evaluations/evals.json`
- Modify: `cyoda/skills/compute/examples/{processor,criteria}.md`, `cyoda/skills/compute/resources/grpc-patterns.md`
- Rewrite: `cyoda/skills/test/templates/smoke-test.sh`
- Create: `cyoda/skills/debug/examples/queries.md` (walkthrough of the `queries/` payloads)

**Content requirements:**
- `docs`:
  - the lookup strategy is exactly `cyoda-help.sh`'s order
  - section-level reads
  - a known-wrong caution for docs getting-started (cyoda-docs#134)
  - schema references via `cyoda help cloudevents json`, `grpc proto`, `openapi json`
  - Cloud questions → "not covered by this plugin"
  - Trino analytics → "not available in cyoda-go"
  - binary missing → web mirror; for install: "next, type `/cyoda:setup`"
- `debug`:
  - health checks via `cyoda-status.sh`
  - failure diagnosis via `cyoda help errors` and `audit`
  - re-evaluation via loopback (pointing at `build/examples/loopback/`)
  - Errored-state queries via `examples/queries/`
  - states that soft delete bypasses the workflow
  - instance-changing fixes are handed to "type `/cyoda:build`" or applied only after an explicit yes
- `compute`:
  - tag routing exactly per `cyoda help grpc` TAG ROUTING, with a #684-B note that `help workflows` wording is wrong
  - 30 s timeout and keep-alive values via `cyoda help grpc` KEEPALIVE / `config grpc`
  - execution modes and tx-token joining via `cyoda help workflows` PROCESSORS
  - function-criterion rejection `reason` (≤ 2 KiB)
  - processor-triggered manual transitions on linked entities
  - stays language-agnostic
- `test`:
  - discovery via `cyoda-call.sh GET /model/`
  - `smoke-test.sh` is rewritten to take `ENTITY_NAME`, `MODEL_VERSION`, `TRANSITION_NAME`, `CYODA_ENDPOINT` and `CYODA_TOKEN_COMMAND` (optional)
  - it fires the transition via PATCH `{}` and passes the auth header as one quoted argument
  - it no longer reads `.cyoda/config`
- `app`:
  - the journey `design` → `setup` → `build` → `test` → iterate → optional `deploy`
  - every flagged step as "next, type `/cyoda:<x>`"
  - the orientation text loses "same API on Cloud"

- [ ] **Step 1: Add a check to `tests/smoke/scenarios/01-hello-world.sh`**

It runs `cyoda/skills/test/templates/smoke-test.sh` with `ENTITY_NAME=hello` and the scenario's ids (point the template at a manual transition in `hello-world/workflow.json`; add one `manual: true` transition `archive` from `completed` to `archived` if the example lacks one). Assert exit 0 and that stdout ends `=== PASS ===`.

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/smoke/run.sh --only 01` → Expected: FAIL (old template uses an empty PUT and reads `.cyoda/config`).

- [ ] **Step 3: Write the five skills, the compute resources and the template.** Evals: ≥ 3 cases per skill, covering the content requirements above, each with `consults-help` and `no-cloud`; flagged-skill hand-offs with `no-invoke`.

- [ ] **Step 4: Verify**

Run: `bash tests/smoke/run.sh --only 01 && bash tests/smoke/lint.sh 2>&1 | grep -E 'skills/(docs|debug|compute|test|app)'`
Expected: PASS; no lint hits.

- [ ] **Step 5: Commit**

```bash
git add cyoda/skills/docs cyoda/skills/debug cyoda/skills/compute cyoda/skills/test cyoda/skills/app tests/smoke/scenarios/01-hello-world.sh
git commit -m "feat(docs,debug,compute,test,app): help-first rewrites for v0.8.4"
```

### Task 11: `deploy` skill, Docker Compose path, seed script, scenario 8

Invoke `superpowers:writing-skills` first.

**Files:**
- Create: `cyoda/skills/deploy/SKILL.md`, `cyoda/skills/deploy/evaluations/evals.json`
- Create: `cyoda/skills/deploy/templates/{seed.sh,verify.sh,compose.single-user.yaml,compose.shared.yaml,secrets-checklist.md}`
- Create: `tests/smoke/scenarios/08-seed.sh`, `tests/smoke/fixtures/seed-project/` (two entities)

**Interfaces:**
- Consumes:
  - the `cyoda-manifest.json` and `entity-config.json` schemas (Task 6)
  - `get-token.sh` (Task 9)
- Produces:
  - `seed.sh --manifest <path> --env <name>`
    - env: `CYODA_ENDPOINT` (required); `CYODA_TOKEN_COMMAND` (optional; no auth header when unset)
    - per entity, in canonical order:
      1. `GET /model/` → if this entity version is `LOCKED`, skip the model steps
      2. otherwise import the sample, then `PUT unique-keys` if any, lock, then `changeLevel` (the env override wins over the base value; `null` means none)
      3. always import the workflow with `{"importMode":"REPLACE","workflows":[…]}`, with `${SCHEMA_VERSION}` substituted from `GET /help/workflows/schema-version/versions` `.current`
    - prints `SEEDED <entity> v<n>` or `SKIPPED-MODEL <entity> v<n> (locked)`, then `WORKFLOW <entity> v<n>`
    - exit 1 on the first HTTP ≥ 400, with the response body
  - `verify.sh`
    - env: `CYODA_ENDPOINT`, optional `CYODA_TOKEN_COMMAND`, `CYODA_ADMIN_URL` (optional)
    - checks `/api/health` (UP), then `/readyz` only if `CYODA_ADMIN_URL` is set, then `GET /api/model/` contains every manifest entity as LOCKED
    - prints `OK`/`FAIL` lines, exit 0/1
  - compose templates
    - `compose.single-user.yaml`: based on `deploy/docker/compose.yaml` at tag `v0.8.4`, ports bound to `127.0.0.1`, a header comment "single-user: mock auth — anyone who can reach these ports is admin"
    - `compose.shared.yaml`: `CYODA_IAM_MODE=jwt`, signing key mounted `:ro` via `CYODA_JWT_SIGNING_KEY_FILE`, bootstrap client from env, postgres service as in `examples/compose-with-observability` at `v0.8.4`
    - both use image `ghcr.io/cyoda/cyoda:${CYODA_VERSION:-0.8.4}`

**Content requirements (`SKILL.md`):**
- Writes files only; never runs docker, helm, kubectl or openssl.
- Preconditions: `cyoda-status.sh` connected; `cyoda-manifest.json` exists, else falls back to `build`'s scan and offers to write the manifest.
- Target choice: Compose single-user or shared, Helm (Phase B: until then "coming in the next release of this skill"), Terraform (a pointer to `Cyoda/cyoda-go-terraform`, early/AWS-first).
- Production target: asks whether processors write fields not in the sample, and records the answer as `env.production.changeLevel` in each entity's `-config.json`.
- Output dir: scan for an existing `deploy/` or `ops/`, else `deploy/cyoda/`.
- Ends with the ordered command list: secrets → up → health → seed → verify.
- Optionally registers a profile (`endpoint`, `env`, `tokenCommand`).
- Exposes gRPC (compose port 9090) and records `CYODA_COMPUTE_GRPC_ENDPOINT` for compute nodes in `secrets-checklist.md`.
- Helm/compose known-issue notes cite #684 items A, D and G from the Upstream table.

- [ ] **Step 1: Write `08-seed.sh`**

Fixture project: `order` with `uniqueKeys` `[{"id":"by-order-id","fields":["$.orderId"]}]` and `changeLevel` `STRUCTURAL` with `env.production.changeLevel: null`, plus `customer` with no keys. Assertions:
- the first `seed.sh --env production` run prints `SEEDED order v1`, `SEEDED customer v1` and 2 `WORKFLOW` lines
- `GET /model/` shows both LOCKED
- creating two `order`s with the same `orderId` → the second fails with a unique-key conflict
- a second `seed.sh` run prints `SKIPPED-MODEL` for both and exits 0
- `verify.sh` with the same manifest exits 0
- writing a field absent from the sample on `order` is rejected (strict schema in production, since the env override is `null`)

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/smoke/run.sh --only 08` → Expected: FAIL (templates missing).

- [ ] **Step 3: Write the templates, `SKILL.md` and evals**

Eval cases (≥ 4):
- happy: compose single-user → files written, command list given, no commands run
- edge: shared compose → JWT plus a secrets checklist, no secret values in files
- edge: production target → asks the processor-fields question and records the override
- failure: no manifest and no build files → explains, hand-off "type `/cyoda:build`"

All with `no-cloud`, `no-invoke` and `writes-only` ("does not run docker/helm/kubectl").

- [ ] **Step 4: Verify**

Run: `bash tests/smoke/run.sh --only 08 && shellcheck cyoda/skills/deploy/templates/*.sh && bash tests/smoke/lint.sh 2>&1 | grep 'skills/deploy'`
Expected: PASS; shellcheck clean; no lint hits.

- [ ] **Step 5: Commit**

```bash
git add cyoda/skills/deploy tests/smoke/scenarios/08-seed.sh tests/smoke/fixtures
git commit -m "feat(deploy): compose deploy artifacts, idempotent seed and verify scripts"
```

### Task 12: Phase A release check

**Files:**
- Modify: `README.md`: "Release notes — 0.4.0" section:
  - Cloud support and `migrate` removed (parked; see `docs/history/cloud-skills.md`)
  - `/plugin marketplace update cyoda` needed
  - stored tokens no longer read
  - new `deploy`
  - side-effect skills now start only when typed
- Modify: `CLAUDE.md`: Running evals gets the line "Executors may run read-only `cyoda help …` against the installed binary; all other commands stay simulated."

- [ ] **Step 1: Run everything**

Run: `bash tests/smoke/run.sh`
Expected: lint exit 0, all script tests pass, scenarios 01–06 and 08 PASS, summary `0 failed`.

- [ ] **Step 2: Check every skill's line count and eval coverage**

Run: `for d in cyoda/skills/*/; do printf "%s %s %s\n" "$d" "$(wc -l < $d/SKILL.md)" "$(jq '.evals|length' $d/evaluations/evals.json)"; done`
Expected: each line count < 500 and each eval count ≥ 3.

- [ ] **Step 3: Load the plugin for real**

Run: `claude -p "/cyoda:status" --plugin-dir ./cyoda` with a local cyoda running.
Expected: `Connected to cyoda-go v0.8.4 — http://localhost:8080 [profile: default]`.

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: 0.4.0 release notes; eval executors may read real cyoda help"
```

### Task 13: Eval slices 1–3 (pause after each)

Follow `CLAUDE.md` → Running evals, with `iteration-1` as N. Slices:
1. `setup` + `status`
2. `design`
3. `build`

- [ ] **Step 1: Run slice 1.** Executors in parallel, then graders in parallel, then aggregate and generate the viewer.
- [ ] **Step 2: Report to the user**
  - summed executor + grader `total_tokens`
  - summed `duration_ms`
  - pass rate per skill
  - the failing assertions, each with a one-line cause

  Then wait for go-ahead.
- [ ] **Step 3: Fix any skill defects the slice exposed.** Re-run only the affected evals as `iteration-1b`, commit (`fix(<skill>): …`), and report.
- [ ] **Step 4: Repeat Steps 1–3 for slices 2 and 3.**

---

# Phase B

### Task 14: `deploy` Helm path

**Files:**
- Create: `cyoda/skills/deploy/templates/values.yaml`
- Modify: `cyoda/skills/deploy/SKILL.md` (Helm branch), `cyoda/skills/deploy/templates/secrets-checklist.md`, `cyoda/skills/deploy/evaluations/evals.json`
- Create: `tests/smoke/test-helm-template.sh`

**Content requirements:**
- Chart: `helm repo add cyoda https://cyoda.github.io/cyoda-go`, with the version chosen as the chart whose appVersion equals the local binary version (`helm search repo cyoda/cyoda --versions -o json | jq`).
- `values.yaml`:
  - `postgres.existingSecret`, `jwt.existingSecret`
  - `bootstrap.clientId` set (#684-D); gateway or ingress set explicitly (#684-G)
  - gateway vs ingress chosen by the developer
  - replicas and HPA left at chart defaults, with comments
  - the migration job is left enabled
- Verify via `kubectl port-forward` for `/readyz`.
- Never run helm or kubectl. The command list includes `helm install cyoda cyoda/cyoda --version <v> -f values.yaml -n <ns>`.

- [ ] **Step 1: Write `test-helm-template.sh`**

`helm repo add`/`update` into a temp `HELM_REPOSITORY_CONFIG`, then `helm template cyoda cyoda/cyoda --version 0.8.4 -f cyoda/skills/deploy/templates/values.yaml`. Assertions:
- exit 0
- the rendered output contains `kind: StatefulSet`
- it contains a bootstrap Secret reference
- the image is `ghcr.io/cyoda/cyoda:0.8.4`

- [ ] **Step 2: Run it to see it fail** (values file missing).
- [ ] **Step 3: Write `values.yaml`, the Helm branch of `SKILL.md`, and 2 Helm eval cases.** The cases: happy Helm with gateway; edge, an existing-ingress cluster.
- [ ] **Step 4: Run** `bash tests/smoke/test-helm-template.sh` → Expected: PASS.
- [ ] **Step 5: Commit** `feat(deploy): Helm values and guided Helm path`.

### Task 15: Smoke scenario 7 — compute node

**Files:**
- Create: `tests/smoke/compute/go.mod`, `tests/smoke/compute/main.go`
- Create: `tests/smoke/scenarios/07-compute.sh`
- Create: `cyoda/skills/compute/examples/cascade/{order-workflow.json,shipment-workflow.json,order-sample.json,shipment-sample.json,config.json}`

**Interfaces:**
- `go.mod` requires `github.com/cyoda-platform/cyoda-go v0.8.4` and imports the generated packages under `api/grpc/...`. It needs Go ≥ 1.26.7; `GOTOOLCHAIN=auto` is acceptable.
- `main.go` is a compute member that:
  - joins with tags `["smoke-compute"]` (per `cyoda help grpc` COMPUTE MEMBER PROTOCOL)
  - processor `create-shipment`: on `order`, calls the REST transition API to create a `shipment` linked by `$.orderId` → the shipment entity id stored in `order.$.shipmentId`, then fires the manual transition `dispatch` on the shipment
  - function criterion `has-address`: returns `matches:false` with reason `missing shipping address` when `$.address` is absent
  - flags `--grpc localhost:19090 --http http://localhost:18080/api`; prints `READY` once joined

**Scenario 7 assertions:**
- after `go build` and starting the member, wait for `READY`
- an order without an address: the manual transition `confirm` returns 400, and the body contains `missing shipping address`
- an order with an address: it reaches `confirmed`; `order.$.shipmentId` is set; that shipment's state is `dispatched`

- [ ] **Step 1: Write `07-compute.sh`** with the assertions above. It's skipped with a clear message if `go version` < 1.26.7 and `GOTOOLCHAIN` isn't `auto`.
- [ ] **Step 2: Run it to see it fail** (`bash tests/smoke/run.sh --only 07`).
- [ ] **Step 3: Write the example workflows** (tags `smoke-compute`, `config.json` per the Task 6 schema), then `main.go`.
- [ ] **Step 4: Run** `bash tests/smoke/run.sh --only 07` → Expected: PASS.
- [ ] **Step 5: Update `compute/SKILL.md`** to reference `examples/cascade/` for the event-cascade pattern, then commit `test(smoke): compute-node cascade scenario with function-criterion reason`.

### Task 16: Eval slices 4–6 and final checks

Slices:
4. `deploy` + `auth`
5. `compute` + `debug`
6. `test` + `docs` + `app`

- [ ] **Step 1: Run slices 4–6** as in Task 13 Steps 1–3, pausing after each with the token report.
- [ ] **Step 2: Run** `bash tests/smoke/run.sh` → Expected: everything, including 07, PASS.
- [ ] **Step 3: Request a whole-branch review** (superpowers:requesting-code-review), then superpowers:finishing-a-development-branch.
