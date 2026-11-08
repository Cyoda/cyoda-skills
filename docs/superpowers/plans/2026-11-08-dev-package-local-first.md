# Dev Package: Local cyoda-go, Spikes, Cyoda-Specific Trim — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Every skill task also REQUIRES superpowers:writing-skills** (loaded before the first edit to a `SKILL.md`).

**Goal:** Remove Cloud remnants and production handling, make a local cyoda-go the expected setup, add spikes, and trim every skill to Cyoda-specific content.

**Architecture:** Scripts first (drop `env` and the production guard, with script tests). Then one task per skill, each a writing-skills RED → GREEN → REFACTOR cycle where the skill's `evals.json` is the test: change the eval cases first and see the changed ones fail against the current skill, edit `SKILL.md`, run the skill's whole suite and see it pass. Last, lint rules, docs and the version bump.

**Tech Stack:** bash scripts and tests (`tests/scripts/*.sh`, `tests/smoke/`), skill markdown, `evals.json`, eval tooling in `tests/evals/`, cyoda-go v0.8.4.

**Spec:** `docs/superpowers/specs/2026-11-07-dev-package-local-first-design.md`

## Global Constraints

- `SKILL.md` under 500 lines; instructions only: no rationale, no design discussion, no remarks on how a developer should work.
- **Cyoda-specific content only.** Test per line: would a frontier model (Opus/Sonnet 5.5 and peers) do this right without it, given `cyoda help`? If yes, cut it. Keep/cut lists: spec § "Trim every skill to Cyoda-specific content".
- No access checks or restrictions in skills or scripts.
- Never embed Cyoda docs; facts come from `cyoda help` (help-first).
- Side-effect skills keep `disable-model-invocation: true`: `setup`, `build`, `test`, `app`, `deploy`, `auth`.
- Guidance form per writing-skills "Match the Form to the Failure": a recipe or exact text, or a conditional on an observable predicate. No prohibition lists, no nuance clauses.
- Evals follow `CLAUDE.md` "Running evals": real throwaway server per eval where the skill acts on an instance, simulated instance only for fixtures a fresh server can't give. Results in `cyoda-evals-workspace/iteration-5/<skill>/` (RED runs) and `iteration-6/<skill>/` (GREEN runs). Report token cost per skill.
- Every hand-off is "next, type `/cyoda:<skill>`".
- Spike wording (half a sentence, adapt to the skill): "For complex behaviour help doesn't settle, ask whether to spike it on a throwaway cyoda-go (in-memory with mock auth, per `cyoda help run`, or the stack in Docker)."
- Commits only; pushing needs the user's go-ahead.

## Review Focus

1. **An old config with `env: "production"`** on a profile or project entry: calls run normally, nothing prints `production`. Pinned in Task 1 (`test_call_ignores_env`, `test_status_no_env_field`).
2. **A caller still passing `--confirm-production`** (an old script or a skill not yet migrated): a usage error, exit 64, not a silent pass. Pinned in Task 1 (`test_call_confirm_flag_removed`).
3. **A trim deletes a Cyoda-specific fact no eval exercises** (e.g. `/api/health` vs admin `/readyz`, the install formula, `MODEL_HAS_ENTITIES`, export reshaping, tag overlap). Each skill task ends with a keep-list grep of the facts named in its task.
4. **A spike that the developer approves is left running.** Pinned in Task 5 (design eval 7: spike on yes, instance stopped and its temp dir gone at the end).
5. **`setup` starting the wrong stack**: only the Compose project in the linked project root whose service runs `ghcr.io/cyoda/cyoda`. Pinned in Task 4 (setup eval 10).

---

### Task 1: Scripts drop `env` and the production guard

**Files:**
- Modify: `cyoda/scripts/cyoda-profile.sh` (lines 3, 25, 37, 52: drop `env`)
- Modify: `cyoda/scripts/cyoda-status.sh` (lines 3, 13, 58: drop `ENV=`)
- Modify: `cyoda/scripts/cyoda-call.sh` (lines 3–5, 11–15, 23, 33–38: drop `--confirm-production`, exit 3)
- Test: `tests/scripts/test-call.sh`, `tests/scripts/test-profile.sh`, `tests/scripts/test-status.sh`, `tests/scripts/test-config-write.sh`

**Interfaces:**
- Produces: `cyoda-profile.sh` prints `{profile, endpoint, tokenCommand, warnings, source, projectDir?}` (no `env`). `cyoda-status.sh` line 1 is `STATUS=<s> PROFILE=<p> ENDPOINT=<e> VERSION=<v> BINARY_VERSION=<b> SOURCE=<src>[ PROJECT=<dir>]`. `cyoda-call.sh <METHOD> <PATH> [curl args...]`, exits `0` 2xx, `22` ≥400, `4` token command failed, `5` no endpoint, `1` invalid config or unknown `CYODA_PROFILE`, `64` usage.

- [ ] **Step 1: Write the failing tests**

In `test-call.sh`, replace `test_call_production_guard` (lines 34–44) and the project-entry guard check (lines 135–137) with:
```bash
test_call_ignores_env() {   # env: production in an old config changes nothing
  cfg "{\"endpoint\":\"$EP\",\"env\":\"production\"}"
  bash "$S/cyoda-call.sh" PUT /model/x/1/lock >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 3 ]; assert_status 0 "$?" "no production refusal"
}
test_call_confirm_flag_removed() {
  cfg "{\"endpoint\":\"$EP\"}"
  bash "$S/cyoda-call.sh" --confirm-production GET /model/ >/dev/null 2>&1
  assert_status 64 "$?" "flag is a usage error"
}
```
In `test-profile.sh`: every expected JSON drops `env` (line 24 becomes `{"profile":"default","endpoint":"http://localhost:8080","tokenCommand":null,…}` with the rest unchanged); line 58's `active env` assertion becomes `assert_eq "$(echo "$out" | jq 'has("env")')" false "no env key"`; line 65's assertion checks `.endpoint` only; `fields()` (line 96) drops `.env`, and lines 110 and 154–155 drop the `env` value from their expected arrays.
In `test-status.sh`: lines 54 and 108 expect `STATUS=connected PROFILE=default ENDPOINT=$ep VERSION=0.8.4` and `STATUS=connected PROFILE=shop ENDPOINT=$ep VERSION=0.8.4`; add `test_status_no_env_field` asserting the first line doesn't contain `ENV=` for a config with `"env":"production"`.
In `test-config-write.sh` line 36: drop `"env":"development"` from the fixture and the expected JSON.

- [ ] **Step 2: Run them and see them fail**

Run: `bash tests/scripts/test-call.sh; bash tests/scripts/test-profile.sh; bash tests/scripts/test-status.sh`
Expected: failures on the new and changed assertions (exit 3 still returned, `env` and `ENV=` still present).

- [ ] **Step 3: Drop `env` and the guard from the three scripts**

Remove the `env` key from every object `cyoda-profile.sh` builds; remove `ENVNAME` and ` ENV=$ENVNAME` from `cyoda-status.sh`; in `cyoda-call.sh` remove `CONFIRM`, the flag parsing, `ENVNAME` and the refusal block, and update the header comment and usage to `cyoda-call.sh <METHOD> <PATH> [curl args...]`. So that a leftover `--confirm-production` isn't taken as the method, add before the arg-count check: `case "${1:-}" in -*) echo "usage: cyoda-call.sh <METHOD> <PATH> [curl args...]" >&2; exit 64 ;; esac`.

- [ ] **Step 4: Run the script tests and the smoke suite**

Run: `bash tests/smoke/run.sh`
Expected: all script tests pass; lint passes (stale-string rules come in Task 13); scenarios pass.

- [ ] **Step 5: Commit**

```bash
git add cyoda/scripts tests/scripts
git commit -m "feat(scripts): drop env and the production guard"
```

---

### Skill tasks: shared cycle (Tasks 2–12)

Each skill task runs this cycle. Load superpowers:writing-skills first. Finish and verify each skill before starting the next (writing-skills "STOP before moving to next skill").

1. **RED: change the evals.** Edit `cyoda/skills/<skill>/evaluations/evals.json` as the task lists: remove every `no-cloud`/Cloud assertion and every production assertion; rewrite and add the listed cases. Keep 3+ cases. `jq empty` must pass.
2. **RED: run the changed and new cases against the current skill** (iteration-5), per `CLAUDE.md`. Expected: the task's "RED expectation" fails. Pure removals and trims have no RED run; the existing suite is their regression test.
3. **GREEN: edit `SKILL.md`** (and the listed resources): the task's behaviour changes, then the trim per Global Constraints. Record `wc -w` before and after.
4. **GREEN: run the skill's whole suite** (iteration-6), grade, aggregate. Expected: 100%. A failing case after a trim: put back only what that case needs (REFACTOR), re-run that case.
5. **Keep-list check:** `grep` the task's keep-list facts in the skill dir; each must still be present.
6. **Commit** `cyoda/skills/<skill>` and the eval changes: `git commit -m "refactor(<skill>): cyoda-specific trim, <change summary>"`. Report pass rate, token cost and word counts.

### Task 2: `status`

- Changes: remove the `[PRODUCTION]` tag rule (line 23) and its example (line 53), `ENV=` from the parsed line (line 14), the Cloud row (line 66); the `Labels such as "Local cyoda-go"` row stays only if eval 1 needs it.
- Evals: status 1 drop `no-production-tag`; status 3 rewrite: fixture profile `staging` at `https://cyoda-staging.example.com`, no `env`, simulated `STATUS=connected` line without `ENV=`; assertions: status line `Connected to cyoda-go v0.8.4 — https://cyoda-staging.example.com [profile: staging]`, no `[PRODUCTION]`. Drop `self-hosted-wording` if it only guarded Cloud wording.
- RED expectation: none (removal).
- Keep-list: `cyoda-status.sh`, `SOURCE=project`, `[project:`, `/api/help`.

### Task 3: `auth`

- Changes: remove `env` from the config description (line 12) and from any profile write; remove the Cloud line (16). Trim: credential-hygiene prose, the shell-quoting explanation in Step 6, the `pipefail` explanation (line 85), common-mistakes rows that restate them.
- Evals: drop `no-cloud` everywhere.
- RED expectation: none.
- Keep-list: `POST /api/oauth/token`, `auth clients`, `auth tokens`, `tokenCommand`, `CYODA_CLIENT_SECRET_CMD`, `cyoda-config-write.sh`, `get-token.sh`.

### Task 4: `setup`

- Changes: connect mode keeps endpoint, probe, name, write, auth check; remove its step 3 (environment) and `env` from every write (lines 14, 53, 90, 112); link mode remove step 5 (environment) and the "Docker is only read…" paragraph; add to link step 3: when no running cyoda-go container matches and `<ROOT>` has a Compose file whose service image is `ghcr.io/cyoda/cyoda`, run `docker compose up -d` in `<ROOT>`, then re-run `cyoda-docker-instances.sh`. Add `Bash(docker compose *)` to `allowed-tools`. Finish: drop `[PRODUCTION]`. Remove the Cloud line (28). Trim: the Homebrew-failure ceremony (keep the install commands list, a #684-K workaround), the quoting rules and write-denied message in "Changing the config" (keep: every write goes through `cyoda-config-write.sh '<filter>' --arg …`), the token-test pipeline explanation, common-mistakes rows 2, 5, 6.
- Evals: setup 3 and 5 drop `asks-env`; add **setup 10** (simulated Docker): project `/work/shop` with `compose.yaml` (service `cyoda`, image `ghcr.io/cyoda/cyoda:0.8.4`, port `127.0.0.1:18080:8080`), `cyoda-docker-instances.sh` prints nothing until `docker compose up -d` runs in `/work/shop`, then `CONTAINER=shop-cyoda-1 COMPOSE_PROJECT=shop ENDPOINT=http://127.0.0.1:18080 IMAGE=ghcr.io/cyoda/cyoda:0.8.4`; prompt `/cyoda:setup — link this project`. Assertions: runs `docker compose up -d` in `/work/shop` (no other Compose dir), re-lists, links `projects["/work/shop"]` to `http://127.0.0.1:18080`, writes no `env`.
- RED expectation: setup 10 fails (`starts-stack`: current skill hands the command to the developer).
- Keep-list: `brew install cyoda/cyoda-go/cyoda`, `/api/health`, `/readyz`, `cyoda init`, `cyoda-docker-instances.sh`, `projects[`, `pwd -P`.

### Task 5: `design`

- Changes: line 9: replace "so it works without an instance and without the binary" with: when `cyoda-help.sh` reports `SOURCE=web`, say once "Next, type `/cyoda:setup` to install cyoda-go locally" and continue. Add the spike half-sentence to Phase 3. `allowed-tools`: add `Bash(cyoda *) Bash(docker *) Bash(kill *) Bash(curl *)`. Remove the Cloud line (111). Trim: Phase 2 "one question at a time / skip answered", Phase 4 "Revise until yes", the error-state-exits prose that the best-practices bullet already states, `resources/design-guidelines.md` sections the best practices and anti-patterns already cover, common-mistakes rows restating cuts.
- Evals: drop `no-cloud`; design 4 (no binary) add `recommends-install`: says once to type `/cyoda:setup` to install cyoda-go and still delivers the design summary. Add **design 6**: prompt "Order: when `submitted`, a function criterion checks stock via our node; if the node is down, a scheduled transition should move it to `review` after 10 minutes. Will the schedule still fire while the criterion call is failing?"; developer answers "no" to a spike. Assertions: reads `workflows` SCHEDULED TRANSITIONS and CRITERIA, asks whether to spike, on "no" answers from help and names what help leaves open. Add **design 7**: same prompt, developer answers "yes". Assertions: starts a throwaway cyoda-go with in-memory storage and mock auth on ports other than the project's, reports the observed behaviour in a line or two, the process is stopped and its temp dir removed at the end.
- RED expectation: design 4 `recommends-install`, design 6 `asks-spike`, design 7 fail.
- Keep-list: `workflows best-practices`, `best-practices.md`, `Notifications are coming soon`, `schedule`, `ASYNC_NEW_TX`, `changeLevel`, the anti-pattern names.

### Task 6: `docs`

- Changes: the "Binary missing" paragraph (line 23) becomes: on `SOURCE=web`, say once "Next, type `/cyoda:setup` to install cyoda-go locally", and the mirror's differences as one list: whole pages (`--section` ignored), no actions (`cloudevents json`, `grpc proto`, `openapi …`, `workflows schema-version versions`), version from the mirror's `index.json`. Remove the Cloud row (73). Trim: "Answering" bullets a model already follows (keep: end with the source line format and the version-mismatch rule).
- Evals: drop `no-cloud`; docs 3 rewrite the prompt to "Can I run Trino SQL reports over my entities?" with assertions: says SQL analytics isn't available in cyoda-go 0.8.4 and gives the grouped stats or search request; drop `cloud-not-covered`. docs 2 add `recommends-install`.
- RED expectation: docs 2 `recommends-install` fails if the current text doesn't produce it; otherwise none.
- Keep-list: the errata table items B, C, I, J, A, E/F/H; `errors <CODE>`; `cloudevents json`; `grpc proto`; `openapi json`.

### Task 7: `build`

- Changes: remove the `--confirm-production` form (line 14), exit-3 row (21), the `ENV=production` bullet (32), "Production guard" (153–155) and its common-mistakes row (181). Add the spike half-sentence to Step 2. `allowed-tools`: add `Bash(cyoda *) Bash(docker *) Bash(kill *) Bash(curl *)`. Trim: the language-detection script (keep the layout table and naming rule), the `jq` manifest upsert (keep the manifest schema and upsert key `name`+`modelVersion`), "Ask the minimum questions, one at a time", "Tell the developer each relative path saved", "'Register this' is a request to start", When-a-call-fails steps 2, 4, 5 (keep step 1 and the common causes), common-mistakes rows restating cuts.
- Evals: drop `no-cloud`; rewrite **build 6**: fixture `riskassessment` v1 LOCKED on the local default; prompt "/cyoda:build — RiskAssessment needs an `approved` state reached when a function criterion on our scoring node passes; if the node keeps timing out, does the transition fail or retry?"; developer says "no" to a spike. Assertions: reads `workflows` CRITERIA and PROCESSORS, asks whether to spike, on "no" proceeds with the increment from help; drop `production-warning`, `flag-after-yes`, `handles-exit-3`.
- RED expectation: build 6 `asks-spike` fails.
- Keep-list: canonical order (`SAMPLE_DATA`, `lock`, `changeLevel`, `workflow/import`), `MODEL_HAS_ENTITIES`, `${SCHEMA_VERSION}`, `schema-version versions`, `{importMode, workflows}`, `#684-I`, `#684-B`, `cyoda-manifest.json`, `-v{version}-`.

### Task 8: `test`

- Changes: remove the `--confirm-production` form (14), exit-3 row (21), Step 0 `ENV=production` bullet (33), Step 3 "Production" paragraph (52), Guided-mode quoting rules (88–89, keep the run command shape), the Cloud row (104). Trim choreography and restating common-mistakes rows.
- Evals: drop `no-cloud`; test 3 rewrite: profile `default` local, orders v1 LOCKED and invoice v2 UNLOCKED; assertions: tests `orders` v1, reports `invoice` v2 as not testable until locked; drop `production-confirm`, `stops-on-no`. test 5: rename profile `prod-ci` to `ci`.
- RED expectation: none.
- Keep-list: `If-Match: *`, `application/merge-patch+json`, `PATCH`, `scripts/smoke-test.sh`, `CYODA_TOKEN_COMMAND`, entity clean-up.

### Task 9: `debug`

- Changes: remove the exit-3 row (20), the `ENV=production` bullet (33), the "Apply this to `<id>`? (yes/no)" rule (26; it now runs the repair and shows the call), the Cloud row (121). Add the spike half-sentence to Paths B and C. `allowed-tools`: add `Bash(cyoda *) Bash(docker *) Bash(kill *) Bash(curl *)`. Path E: "read each one's reason from its own audit (one audit call per id; never assume…)" becomes "read each errored entity's audit: `GET '/audit/entity/<id>?eventType=StateMachine'` per id". Trim restating common-mistakes rows.
- Evals: drop `no-cloud`; debug 1 replace `asks-before-change` with `applies-loopback`: sends the loopback PATCH and shows the call it made.
- RED expectation: debug 1 `applies-loopback` fails.
- Keep-list: `#684-J`, `DISPATCH_TIMEOUT`, `COMPUTE_MEMBER_DISCONNECTED`, `/changes`, `point-in-time`, `pageNumber` or the audit cursor, `Prefer a ledger to deletion`.

### Task 10: `compute`

- Changes: remove the Cloud line (102). Add the spike half-sentence near Step 6 (execution mode and timeout). `allowed-tools`: add `Bash(cyoda *) Bash(docker *) Bash(kill *) Bash(curl *)`. Production checklist: keep idempotency on `requestId` and `COMMIT_BEFORE_DISPATCH` replays, member id changes on reconnect, `cyoda_dispatch_*` metrics; cut one-writer, backoff, latency tracking. `resources/grpc-patterns.md`: keep the event envelope, lifecycle and `cyodatxtoken`; cut the single-writer queue and reconnection sections. Trim `examples/` prose a model writes itself.
- Evals: drop `no-cloud`.
- RED expectation: none.
- Keep-list: `ROLE_M2M`, `joinedLegalEntityId`, `cyodatxtoken`, `X-Tx-Token`, `responseTimeoutMs`, `#684-J`, `COMMIT_BEFORE_DISPATCH`, `calculationNodesTags`.

### Task 11: `deploy`

- Changes: Step 3 "Is this instance **production**?" becomes "Which stage is this for, and is its schema strict?"; ask the verbatim per-entity question for a strict stage (drop the rationale parenthesis); record `env.<stage>.changeLevel`; `seed.sh --env <stage>`. Remove Step 7 (175–192), the Step 6 `/cyoda:auth` hand-off (190), the "(and, with this instance's client in front, in the profile's `tokenCommand`: Step 7)" clause (116), common-mistakes row "Production without the processor-fields question" (212, rephrase for a strict stage), the Cloud line (18). Trim choreography and restating rows; keep the #684 items D, M.
- Evals: drop `no-cloud`; rewrite **deploy 3**: developer names stage `prod`, strict; assertions `records-override` on `env.prod.changeLevel`, `seed --env prod`, no profile offer; drop `env-production`, `profile-inactive`. Add **deploy 7**: stages `int`, `uat`, `prod`, `prod` strict, shared Compose; assertions: strict question asked only for `prod`, `env.prod.changeLevel` recorded, the hand-over lists seed/verify per stage with `--env <stage>`. Check deploy 2, 5, 6 for assertions on the `/cyoda:auth` hand-off or a profile and remove them.
- RED expectation: deploy 3 `records-override` and deploy 7 fail.
- Keep-list: `compose.single-user.yaml`, `compose.shared.yaml`, `values.yaml`, `seed.sh`, `verify.sh`, `secrets-checklist.md`, `https://cyoda.github.io/cyoda-go`, `ghcr.io/cyoda/cyoda`, `#684`.

### Task 12: `app`

- Changes: journey line (15) becomes **design → local cyoda-go → build → test → iterate → deploy files (optional)**; Step 2 names `/cyoda:setup` for the local step; remove the `[PRODUCTION]` profile bullet (48) and the Cloud line (77). Trim orientation to the Cyoda definition, and choreography.
- Evals: drop `no-cloud`, `no-same-api-cloud`, `cloud-not-covered`; app 3 rewrite assertions: hands off to `/cyoda:deploy` for deployment files, doesn't say "not covered by this plugin". app 2 add `local-step`: names the local cyoda-go step before build.
- RED expectation: app 3 (current reply contains "not covered by this plugin") fails.
- Keep-list: the journey line, the EDBMS definition, the side-effect skills' "next, type" hand-offs.

### Task 13: Lint, docs, version

**Files:**
- Modify: `tests/smoke/lint.sh` (next to `scan cloud 'Cyoda Cloud' …`)
- Modify: `README.md`, `cyoda/README.md`, `cyoda/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `docs/superpowers/specs/2026-10-17-cyoda-go-split-and-help-first-design.md` (header)

- [ ] **Step 1: Add the stale-string rules**
```bash
scan stale-production-flag '--confirm-production' ${FILES[@]+"${FILES[@]}"}
scan stale-production-tag '\[PRODUCTION\]' ${FILES[@]+"${FILES[@]}"}
scan stale-cloud-line 'not covered by this plugin' ${FILES[@]+"${FILES[@]}"}
```
- [ ] **Step 2: Run** `bash tests/smoke/lint.sh` — Expected: exit 0 (Tasks 2–12 removed every hit). A hit names the skill to fix.
- [ ] **Step 3: Docs.** READMEs: config without `env`, no production guard, a local cyoda-go as the expected setup, one line on spikes. 2026-10-17 spec header: "Parts superseded by `2026-11-07-dev-package-local-first-design.md`." Version `0.5.0` in `plugin.json` and `marketplace.json`, with a 0.5.0 release-notes entry in `README.md`.
- [ ] **Step 4: Run** `bash tests/smoke/run.sh` — Expected: all pass. `bash tests/smoke/test-harness.sh` — Expected: pass.
- [ ] **Step 5: Commit** `git commit -m "chore: stale-string lint, docs, 0.5.0"`. Ask the user before pushing.
