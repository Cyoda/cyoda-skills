# One `develop` Skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Every task that edits a `SKILL.md` also REQUIRES superpowers:writing-skills.**

**Goal:** Replace `app`, `design`, `setup`, `build`, `test`, `status` and `auth` with one agent-driven `develop` skill that runs requirement → registered, tested app without typed hand-offs, on a project-own cyoda-go instance that never collides with other instances on the machine.

**Architecture:** Mechanical parts become scripts with tests (instance naming, port picking with ownership evidence, starting/stopping a project's instance). `develop`'s `SKILL.md` holds the loop; each step's detail lives in a resource loaded when the step comes up. The other four skills lose their typed hand-offs. Evals: fail-first runs only for the new discovery, port and loop cases; migrated cases whose expectation changed get one run after the edit.

**Tech Stack:** bash + jq scripts and tests (`tests/scripts`, `tests/lib/assert.sh`, `tests/lib/server.sh`), skill markdown, `evals.json`, eval tooling in `tests/evals/`, cyoda-go 0.8.4, Docker for the Docker mode.

**Spec:** `docs/superpowers/specs/2026-11-11-develop-skill-design.md`

## Global Constraints

- Skill text: Cyoda-specific instructions only, compact, no rationale, no choreography, no access checks; `SKILL.md` under 500 lines; facts from `cyoda help`.
- No `disable-model-invocation` on any skill. Hand-offs between skills: "continue with the `cyoda:<skill>` skill". No "next, type …".
- The agent asks only a domain gap in the requirement and, when the project doesn't define it, the one run question (spec § The local instance, step 3, exact wording there).
- The plugin config stays private (`cyoda-config-write.sh` for every write); nothing is written into the developer's repo except the app's own project files (samples, workflows, configs, manifest).
- Never stop or remove another process or container.
- Plugin version `0.8.1` in `cyoda/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `cyoda/gemini-extension.json`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; no push without the user's go-ahead.
- Evals per `CLAUDE.md` "Running evals"; results in `cyoda-evals-workspace/iteration-9/` (fail-first) and `iteration-10/` (after); token cost reported per task.

## Interfaces (decided here)

**Project entry** (`projects[<real path>]` in the plugin config), fields added to today's `endpoint`, `tokenCommand`:
```
run:      "binary" | "docker" | "repo" | "existing"   # how the instance is started; "existing" = an instance the developer chose (e.g. the one at localhost:8080)
instance: "<basename>-<hash6>"                        # see name below
dataDir:  "<CYODA_LOCAL_DATA_ROOT>/<instance>"         # absent for "existing"
ports:    {"http": N, "grpc": N, "admin": N}           # absent for "existing"
storage:  "memory" | "sqlite"                          # binary and docker only
compose:  "<path to the repo's compose file>"          # "repo" only
```

**`cyoda/scripts/cyoda-ports.sh`**
- `cyoda-ports.sh name <root>` → prints `<instance>`: lowercase basename with characters outside `[a-z0-9-]` replaced by `-`, then `-`, then the first 6 hex chars of `sha256(real path)`.
- `cyoda-ports.sh pick <root>` → prints `HTTP=<p> GRPC=<p> ADMIN=<p> STATE=ours|free`. Exit 0; exit 3 when no block in the sequence is free.
- Blocks: k = 0..19, HTTP = B + 100k, gRPC = B + 1010 + 100k, admin = B + 1011 + 100k, with B = `${CYODA_PORT_BASE:-8080}` (so k=0 is 8080/9090/9091).
- Free = none of the three ports listens (`lsof -nP -iTCP:<p> -sTCP:LISTEN`) and no other project's entry records any of them.
- Order: the project's recorded block first, then k = 0, 1, ….
- `STATE=ours` only with evidence: run `binary` → `<dataDir>/cyoda.pid` names a live process that listens on the HTTP port; run `docker` → a line of `cyoda-docker-instances.sh` with `COMPOSE_PROJECT=<instance>` and `WORKDIR=<dataDir>` whose `ENDPOINT` port is the HTTP port. A busy recorded block without that evidence → the next free block.

**`cyoda/scripts/cyoda-docker-instances.sh`**: each line gains ` WORKDIR=<com.docker.compose.project.working_dir label or ->` after `COMPOSE_PROJECT=`.

**`cyoda/scripts/cyoda-local.sh`**
- `cyoda-local.sh start <root> [--run binary|docker] [--storage memory|sqlite]`: `--run` defaults to the entry's `run`; usage error (exit 64) when neither is given. Picks ports (`cyoda-ports.sh pick`); `STATE=ours` → no start. Otherwise starts: binary — `cyoda` with `HOME`/`XDG_CONFIG_HOME` under `dataDir`, `CYODA_STORAGE_BACKEND`, `CYODA_IAM_MODE=mock`, the three port vars, pid in `dataDir/cyoda.pid`, log in `dataDir/cyoda.log`, detached; docker — renders `cyoda/skills/deploy/templates/compose.single-user.yaml` into `dataDir/compose.yaml` (storage per `--storage`) and runs `docker compose -p <instance> -f <dataDir>/compose.yaml up -d` with `CYODA_HOST_HTTP_PORT`/`_GRPC_`/`_ADMIN_` set. Waits up to 30 s for `/api/health` = UP. Writes the entry (`run`, `instance`, `dataDir`, `ports`, `storage`, `endpoint=http://localhost:<http>`). Prints `ENDPOINT=<url> HTTP=<p> GRPC=<p> ADMIN=<p> RUN=<run> STATE=started|ours`. Exits: 0, 3 no free block, 4 did not become healthy (log tail on stderr), 5 docker unavailable, 64 usage.
- `cyoda-local.sh start-repo <root> <compose-file>`: when the file's published host ports clash (busy and not ours), writes `dataDir/compose.override.yaml` with a free block and runs `docker compose -p <instance> -f <compose-file> -f <dataDir>/compose.override.yaml up -d`; otherwise `docker compose -f <compose-file> up -d`. Records `run: "repo"`, `compose`, `ports`, `endpoint`. Same output and exits.
- `cyoda-local.sh stop <root>`: binary — kills the pid in `dataDir/cyoda.pid` only if it is the process listening on the recorded HTTP port; docker — `docker compose -p <instance> -f <dataDir>/compose.yaml down`; repo — `docker compose -p <instance> ... down` with the same files. Exit 0 also when nothing runs.
- `CYODA_LOCAL_DATA_ROOT` (default `~/.local/share/cyoda/projects`) and `CYODA_PORT_BASE` make tests and evals hermetic.

## Review Focus

1. **Two projects started at the same moment race for the same free block.** Expected: the second start fails health or binds a different block, never two entries with one block. Pinned in Task 2 (`test_local_two_projects_distinct_blocks`), and `start` re-checks the block right before launching.
2. **A stale pid file whose pid was reused by an unrelated process.** Expected: not treated as ours unless that pid listens on the recorded HTTP port. Pinned in Task 1 (`test_pick_stale_pid_not_ours`).
3. **Another project's recorded block while that project is stopped.** Expected: skipped. Pinned in Task 1 (`test_pick_skips_other_project_block`).
4. **A repo checkout under a path with spaces, or a basename with dots/uppercase.** Expected: a valid instance name and data dir; scripts quote paths. Pinned in Task 1 (`test_name_sanitised`) and Task 2 (`test_local_path_with_spaces`).
5. **A developer's existing `localhost:8080` instance with models.** Expected: offered in the one question, never restarted or stopped by `develop`. Pinned in Task 3 (eval `develop-existing-8080`).

---

### Task 1: `cyoda-ports.sh` and the docker listing's `WORKDIR`

**Files:** Create `cyoda/scripts/cyoda-ports.sh`, `tests/scripts/test-ports.sh`. Modify `cyoda/scripts/cyoda-docker-instances.sh`, `tests/scripts/test-docker-instances.sh`, `tests/smoke/run.sh` (run the new test file).

- [ ] **Step 1: Write the failing tests** in `tests/scripts/test-ports.sh` (bind ports with `python3 -m http.server --bind 127.0.0.1 <p>` in the background; hermetic config via `CYODA_PLUGIN_CONFIG`, `CYODA_PORT_BASE=31000`, `CYODA_LOCAL_DATA_ROOT=$T/data`):
  - `test_name_stable_and_distinct`: same path → same name; two dirs both named `shop` in different parents → different names; output matches `^shop-[0-9a-f]{6}$`.
  - `test_name_sanitised`: dir `My Shop.v2` → `^my-shop-v2-[0-9a-f]{6}$`.
  - `test_pick_free_default`: nothing listening → `HTTP=31000 GRPC=32010 ADMIN=32011 STATE=free`.
  - `test_pick_skips_busy`: 31000 listening → `HTTP=31100 GRPC=32110 ADMIN=32111 STATE=free`.
  - `test_pick_skips_other_project_block`: another project's entry records 31000/32010/32011 (nothing listening) → the 31100 block.
  - `test_pick_recorded_ours_binary`: entry `run: binary`, ports 31200…, pid file with the pid of a listener on 31200 → `HTTP=31200 … STATE=ours`.
  - `test_pick_stale_pid_not_ours`: recorded 31200 busy, pid file names a live process that does not listen on 31200 → next free block, `STATE=free`.
  - `test_pick_none_free` with `CYODA_PORT_BASE` set so all 20 blocks are made busy or recorded → exit 3. (Recording 20 blocks in other entries is enough; no need to bind 20 ports.)
  - In `test-docker-instances.sh`, extend the fake `docker` to return a `com.docker.compose.project.working_dir` label and assert `WORKDIR=<that path>` on the line; `WORKDIR=-` without the label.
- [ ] **Step 2: Run** `bash tests/scripts/test-ports.sh; bash tests/scripts/test-docker-instances.sh` — Expected: FAIL (script missing; no `WORKDIR=`).
- [ ] **Step 3: Implement** `cyoda-ports.sh` per Interfaces (read the config the way `cyoda-profile.sh` does, `CYODA_PLUGIN_CONFIG` override; docker ownership via `cyoda-docker-instances.sh`, skipped when docker is absent) and the `WORKDIR` field. shellcheck-clean.
- [ ] **Step 4: Run** both test files and `bash tests/smoke/lint.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(scripts): cyoda-ports.sh picks a free port block with ownership evidence; docker listing shows WORKDIR`.

### Task 2: `cyoda-local.sh`

**Files:** Create `cyoda/scripts/cyoda-local.sh`, `tests/scripts/test-local.sh`. Modify `tests/smoke/run.sh`.

- [ ] **Step 1: Write the failing tests** (`CYODA_PORT_BASE=31000`, `CYODA_LOCAL_DATA_ROOT=$T/data`, temp `CYODA_PLUGIN_CONFIG`, project dirs under `$T`; every test stops what it starts; docker tests return early with `_ok "docker unavailable: skipped"` when `docker info` fails):
  - `test_local_start_binary`: `start <root> --run binary` → exit 0, `STATE=started`, `/api/health` UP at the printed endpoint, entry has `run=binary`, `instance`, `dataDir`, `ports`, `storage=memory`, `endpoint`; pid file exists.
  - `test_local_start_again_is_ours`: second `start <root>` → `STATE=ours`, same ports, no second process.
  - `test_local_restart_same_ports`: `stop` then `start <root>` (no `--run`) → same ports as recorded.
  - `test_local_two_projects_distinct_blocks`: two projects started → different blocks, both healthy.
  - `test_local_busy_default_block`: 31000 bound by an unrelated listener → project starts on the 31100 block; the listener is still running afterwards.
  - `test_local_path_with_spaces`: project root `"$T/my shop"` → starts and stops cleanly.
  - `test_local_stop_leaves_others`: stopping project A leaves project B healthy.
  - `test_local_usage`: `start <root>` with no entry and no `--run` → exit 64.
  - `test_local_docker` (skips without docker): `start --run docker` → healthy on the picked block; `docker ps` shows Compose project `<instance>`; `stop` removes it.
  - `test_local_repo_override` (skips without docker): a repo compose file publishing `127.0.0.1:31000:8080` while 31000 is busy with an unrelated listener → `start-repo` writes `dataDir/compose.override.yaml`, starts on another block, the repo file is unchanged (checksum).
- [ ] **Step 2: Run** `bash tests/scripts/test-local.sh` — Expected: FAIL (script missing).
- [ ] **Step 3: Implement** `cyoda-local.sh` per Interfaces (entry writes through `cyoda-config-write.sh`; re-check the picked block immediately before launch).
- [ ] **Step 4: Run** the test file, then `bash tests/smoke/run.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(scripts): cyoda-local.sh starts and stops a project-own cyoda-go (command line, Docker, repo stack)`.

### Task 3: `develop` skill — the loop and the local instance

**Files:** Create `cyoda/skills/develop/SKILL.md`, `cyoda/skills/develop/resources/instance.md`, `cyoda/skills/develop/evaluations/evals.json`.

**Content source:** the instance step comes from `setup` (install, discovery, link, Compose start) and `auth` (local JWT mode, token script, non-mock auth paths), rewritten on top of `cyoda-ports.sh`/`cyoda-local.sh`; `status`'s status-line contract (the `cyoda-status.sh` line and WARN handling) moves into `instance.md`. Only Cyoda-specific content carries over.

- [ ] **Step 1: Write the eval cases** (new ids in `develop`): `develop-e2e` (real server bound as the active profile; requirement for a small app → design summary shown, registered and smoke-tested with no developer turn after the requirement); `develop-repo-stack` (simulated Docker; repo with a stopped cyoda Compose stack → started and bound, no question); `develop-ask-run` ×2 (no definition; answers "command line" / "Docker" → `cyoda-local.sh start --run …` used, entry recorded; Docker simulated); `develop-port-conflict` (real; 31000 bound by another listener with `CYODA_PORT_BASE=31000` → picks the next block, other listener untouched); `develop-own-instance` (real; project already started via `cyoda-local.sh` → reused, `STATE=ours`); `develop-existing-8080` (simulated: an instance answers at localhost:8080, no project entry → the one question offers it); `develop-design-only` ("how should I model X" → design summary, no instance started); `develop-401` (simulated 401 in the loop → local JWT path from `instance.md`, no typed hand-off). Assertions observe outcomes; fixtures don't name the behaviour under test.
- [ ] **Step 2: Fail-first run** (controller): run these cases against the current plugin (old skills present, `develop` absent). Expected: failures on chaining (typed hand-offs), the run question, port picking and reuse.
- [ ] **Step 3: Write** `develop/SKILL.md` (the loop; when each resource is loaded; hand-offs to `debug`/`compute`/`deploy`/`docs`) and `resources/instance.md` (spec § The local instance: resolution order, the one question with its two wordings, starting via `cyoda-local.sh`, binding, ports, identity, repo-stack override, local JWT and token script, non-mock auth paths with their help sections). `allowed-tools` covers the scripts, `cyoda`, `docker compose`, `curl`, `jq`.
- [ ] **Step 4: Run the cases again** (controller). Expected: all pass.
- [ ] **Step 5: Commit** `feat(develop): the agent-driven loop and parallel-safe local instances`.

### Task 4: `develop` — design, register, test

**Files:** Create `cyoda/skills/develop/resources/design.md`, `register.md`, `test.md`. Move (git mv) `design/resources/{best-practices,patterns,design-guidelines}.md` → `develop/resources/`; `build/templates/*` and `build/examples/*` → `develop/templates/`, `develop/examples/`; `test/templates/smoke-test.sh` → `develop/templates/`. Modify `develop/SKILL.md`, `develop/evaluations/evals.json`.

- [ ] **Step 1: Migrate eval cases** from `design` (10), `build` (8), `test` (5), `app` (4), `setup` (10), `status` (5), `auth` (4) into `develop/evaluations/evals.json`: keep each case whose behaviour survives (renumber, keep the old id in a `"was"` field), replace hand-off and `no-invoke` assertions with "continues with the next step" or drop them, drop cases that only tested typed hand-offs or a removed mode. List every case kept, changed, dropped in the report.
- [ ] **Step 2: Write** the three resources from `design`, `build` and `test` `SKILL.md` content (Cyoda-specific only; best-practices review against the checklist; registration in canonical order with the call-failure table; smoke test and CI script), and wire them into `develop/SKILL.md`. Fix every relative link and `${CLAUDE_PLUGIN_ROOT}/skills/...` path to the moved files.
- [ ] **Step 3: Run** (controller) the migrated cases whose assertions changed. Expected: pass. A failure caused by the move puts back only what that case needs.
- [ ] **Step 4: Commit** `feat(develop): design, register and test resources; migrated evals`.

### Task 5: Remove the old skills; hand-offs in the remaining four

**Files:** Delete `cyoda/skills/{app,design,setup,build,test,status,auth}/`. Move `auth/templates/get-token.sh` → `develop/templates/get-token.sh`. Modify `debug`, `compute`, `deploy`, `docs` `SKILL.md` and evals; `compute` gains the node's token handling (from `auth` Step 7, Cyoda-specific only). Update paths in `tests/smoke/scenarios/01-hello-world.sh`, `08-seed.sh`, `tests/scripts/test-get-token.sh`, `test-two-projects.sh`, `tests/smoke/test-harness.sh`, `cyoda/GEMINI.md`, and any `${CLAUDE_PLUGIN_ROOT}/skills/...` reference. `tests/smoke/test-segregation.sh` `test_flags`: no skill has `disable-model-invocation`; the skill set is exactly `develop debug compute deploy docs`. `tests/smoke/lint.sh`: the `invoke-flagged` rule becomes a `typed-handoff` rule matching `next, type .?/cyoda:` (all hand-offs are now skill loads).

- [ ] **Step 1:** Change the segregation test and lint rule first; run them — Expected: FAIL (old skills and flags present, typed hand-offs present).
- [ ] **Step 2:** Make the changes above.
- [ ] **Step 3:** `bash tests/smoke/run.sh` and `bash tests/smoke/test-harness.sh` — Expected: PASS. `grep -rn "cyoda:\(app\|design\|setup\|build\|test\|status\|auth\)" cyoda tests` → no hits outside history.
- [ ] **Step 4:** Run (controller) the `debug`, `compute`, `deploy`, `docs` cases whose hand-off assertions changed. Expected: pass.
- [ ] **Step 5: Commit** `refactor: five skills; no typed hand-offs`.

### Task 6: Rules, docs, version

**Files:** `CLAUDE.md` (side-effect rule replaced per spec § Rules; skill list), `README.md` and `cyoda/README.md` (skills table, Versioning stays, 0.8.1 release notes naming the removed commands and `/cyoda:develop`), version `0.8.1` in the three files, header pointer in `2026-10-17-…-design.md` and `2026-11-07-…-design.md` to this spec.

- [ ] **Step 1:** Edit. **Step 2:** `bash tests/smoke/run.sh` — Expected: PASS. **Step 3: Commit** `docs: develop skill, 0.8.1`. Ask the user before pushing; afterwards rebase `feat/cyoda-go-0.9.0` onto it.
