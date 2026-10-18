# Cyoda Plugin: cyoda-go / Cloud Split, v0.8.4 Update, Help-First Refinement

**Date:** 2026-10-17
**Status:** Draft, awaiting approval
**Supersedes:** cloud-related parts of `2026-04-24-cyoda-plugin-design.md`. That doc stays as history; this one is the source of truth for the plugin's shape from here on.

## Intent

Cyoda Cloud is paused and will look very different when it comes back. The current `cyoda` plugin mixes cloud into most skills: `auth` and `migrate` are cloud-only, and `setup`, `status`, `app`, `compute` and `debug` have cloud branches. The skills were also written against cyoda-go ~v0.6.3. Against v0.8.4 several of their core examples fail outright: workflow `"version": "1"` gives 400, entity creation without a locked model gives 404 or 409, an empty-PUT transition gives 400, health probes go to the wrong port, and compute tag routing is described backwards.

This work has three steps, done in order:

1. **Segregation.** Two separate packages. The **dev** package covers developing and running cyoda-go and is completely cloud-agnostic. The **cloud** package is parked and can't be installed until the service is re-established.
2. **Update.** Bring the dev package to cyoda-go **v0.8.4**.
3. **Refinement.** Make the skills **help-first**: a smart wrapper over `cyoda help`. Fold in the fact-checked workflow best practices, add a `deploy` skill, rewrite every eval, and add runnable smoke tests.

The why behind help-first: almost everything that broke between v0.6.3 and v0.8.4 was a platform fact copied into a skill. `cyoda help` ships with the binary and matches its version, so a skill that defers to it survives upgrades. What the skills keep is what help can't know: the conversation with the developer, the order of steps across topics, side effects, and judgment.

## Goals

- Two installable identities. `cyoda` (dev) is installable from this repo's marketplace. `cyoda-cloud` is present in the repo but **not** listed in `marketplace.json`.
- The dev package contains no mention of Cyoda Cloud: no cloud branches, no "move to Cloud later", no cloud URLs, no Cloud OAuth. A reader shouldn't be able to tell a cloud product exists.
- Every concrete instruction in the dev package works against cyoda-go v0.8.4. Wherever possible the skills get there by **pointing at the right `cyoda help` topic** rather than restating facts.
- A new `cyoda:deploy` skill takes an app developer from a working local app to a self-hosted cyoda-go: Docker Compose, then Helm. It produces artifacts a devops person can script from.
- The corrected best practices are reachable from `design`, `build` and `debug`.
- Evals are rewritten for every dev-package skill. They run in slices, with the token cost reported after each slice.
- Smoke tests run reference scenarios against a real cyoda-go v0.8.4 (in-memory storage, mock auth) and exercise exactly what the skills teach.

## Non-goals

- Updating, redesigning or re-testing the cloud skills. They're frozen as-is.
- Making Terraform a guided deploy path. `Cyoda/cyoda-go-terraform` describes itself as "early build, not yet ready for production", so it only gets a pointer.
- Running smoke tests in CI. They're local and on demand, and need the `cyoda` binary installed.
- Carrying corrections for wrong `cyoda help` content inside the skills. Help bugs get fixed upstream (see Upstream work).
- Changing the Gemini extension beyond keeping it consistent with the dev package.

## Anti-goals: failing even if it technically works

- The dev package still leaks cloud, e.g. `app` suggesting "move to Cloud when ready", `status` printing "Cyoda Cloud", or a profile `env: production` path that talks about Cloud.
- Skills re-grow embedded reference material (endpoint tables, env-var lists, schema JSON) that duplicates `cyoda help`. That rebuilds the drift problem this work exists to remove.
- The cloud package is accidentally installable, e.g. by appearing in `marketplace.json` or being reachable via a `source` path.
- Smoke tests that test their own fixtures rather than the skills' templates and recipes.
- Hard-coding the workflow schema version anywhere it could instead be read from `cyoda help workflows schema-version versions`.

## Constraints

- Repo rules from `CLAUDE.md`:
  - `SKILL.md` stays under 500 lines.
  - Skills don't embed Cyoda docs.
  - Skills with side effects carry `disable-model-invocation: true`.
  - Each skill has `evaluations/evals.json` with 3+ cases (happy path, edge case, failure).
  - `superpowers:writing-skills` is invoked before authoring or editing skills.
  - The eval process follows `CLAUDE.md` ("Running evals").
- Target is cyoda-go **v0.8.4**: tag `v0.8.4` at github.com/Cyoda/cyoda-go, and the installed binary reports `0.8.4`.
- **Source-of-truth order when references disagree:** cyoda-go code at v0.8.4, then `cyoda help`, then docs.cyoda.net. The docs getting-started page is known-wrong (cyoda-docs #134).
- GitHub org is now `Cyoda` (was `Cyoda-platform`), so all repo URLs need updating.
- Smoke tests use `CYODA_STORAGE_BACKEND=memory` and `CYODA_IAM_MODE=mock` (decided by the user).

## Decisions made with the user

- **Two separate installs.** Dev and cloud are distinct plugins, following the kebab-case plugin naming convention.
- **Cloud package parked, not installable** until the service is back.
- **Add a `deploy` skill.** It's for the app developer first, and its output should be a basis a dev or devops person can script from.
- **Delegate as much as possible to `cyoda help`.** The skills are mainly a smart wrapper over the help feature. Best practices should ultimately live in `cyoda help` too.
- **Notifications** are phrased as "coming soon — check `cyoda help` for availability". Use the same phrasing for any other unshipped feature.
- **Evals:** rewrite for every skill, run the suite in slices, and report token cost per slice.
- **Smoke tests** cover a number of reference scenarios. The proposed set (below) was accepted as "a good start".

## Upstream work (filed 2026-10-17)

| Issue | What | Effect on this work |
|---|---|---|
| Cyoda/cyoda-docs#134 | Getting-started fails on v0.8.4 (version, lock, empty PUT) | `docs` skill's web fallback is unreliable for these until fixed. Skills must not derive recipes from that page |
| Cyoda/cyoda-go#677 (v0.9.0) | `help helm` / `help run` say chart unpublished, 0.1.0 | `deploy` uses the published repo `https://cyoda.github.io/cyoda-go` regardless of what help says |
| Cyoda/cyoda-go#679 (v0.9.0) | `help workflows` says tags match ALL, code matches ANY | `compute` points at `cyoda help grpc` TAG ROUTING specifically |
| Cyoda/cyoda-go#680 (v0.9.0) | New help topic for design best practices | `design` uses it when present, otherwise falls back to a bundled copy |

## Target layout

```
.claude-plugin/marketplace.json     ← lists ONLY "cyoda" (source ./cyoda)
cyoda/                              ← dev package (plugin name "cyoda")
  .claude-plugin/plugin.json        ← description cloud-free, version 0.4.0, repository → github.com/Cyoda/cyoda-skills
  README.md  GEMINI.md  gemini-extension.json
  skills/
    app/ setup/ status/ auth/ docs/ design/ build/ compute/ test/ debug/ deploy/
parked/
  cyoda-cloud/                      ← parked package (plugin name "cyoda-cloud"), NOT in marketplace.json
    .claude-plugin/plugin.json
    README.md                       ← "PARKED — do not install; will be redesigned when Cyoda Cloud returns"
    skills/
      auth/ setup/ status/ migrate/ ← frozen snapshots
tests/
  smoke/                            ← runnable reference scenarios (see Smoke tests)
docs/superpowers/specs/…            ← this doc
```

### Why the dev plugin keeps the name `cyoda` (builder's call, confirmed in playback)

Existing installs (`cyoda@cyoda`) and skill names (`cyoda:build`, etc.) keep working. The cloud package takes the new name `cyoda-cloud`, so its skills will be `cyoda-cloud:auth` and so on.

## Step 1: Segregation

### Dev package (`cyoda/`)

Skills: `app`, `setup`, `status`, `auth`, `docs`, `design`, `build`, `compute`, `test`, `debug`, plus the new `deploy`. `migrate` leaves the dev package entirely.

Cloud content removed per skill:
- `app`: drop the Cloud option in Step 2, Step 6 ("Move to Cyoda Cloud"), and "same API works locally and on Cloud". The journey ends with an optional `deploy` step instead.
- `setup`: local only. A second mode, **connect to an existing self-hosted cyoda-go** (e.g. one created by `deploy`), replaces the cloud mode.
- `status`: report "Connected to cyoda-go vX.Y.Z — <endpoint> [profile: P]" for any instance. A self-hosted instance marked production shows a `[PRODUCTION]` tag. No "Cloud" wording.
- `auth`: **rewritten** for cyoda-go's own auth (see Step 3). The current Cloud OAuth skill moves to the parked package.
- `compute`, `debug`: remove cloud mentions.
- `README.md`, top-level `README.md`, `plugin.json` description, `GEMINI.md`: no cloud.

**Connection config** stays at `~/.config/cyoda/cyoda-plugin-config.json` with named profiles, now generalized to cyoda-go instances:
- `default` is local with mock auth and no token.
- A self-hosted instance is added by `setup` (connect mode) or `deploy`. It carries only `endpoint` and `env` (`development` | `production`).
- **The plugin stores no tokens or secrets.** For an instance that isn't on mock auth, skills read the bearer token from the `CYODA_TOKEN` environment variable. The `auth` skill helps the developer produce that token.
- The production safety guard stays, as a generic self-hosted concern: an explicit confirmation before any skill sends a mutating API call to a profile with `env: production`.

### Parked cloud package (`parked/cyoda-cloud/`)

- Contains `auth` (current Cloud OAuth), `migrate`, and the cloud halves of `setup` and `status`, extracted as their own skills. All are **frozen snapshots** of current content with minimal edits: frontmatter `name` adjusted, plus a top-of-file note "PARKED — targets the pre-pause Cyoda Cloud; do not use".
- Evals move with their skills, unchanged and not run.
- `plugin.json` name is `cyoda-cloud`, with `"description": "PARKED — not installable. …"`.
- `README.md` says:
  - why it's parked
  - that it is not listed in the marketplace
  - that it expects the `cyoda` dev package for `docs`, `design` and `build`
  - that it will be redesigned, not revived as-is, when the service returns
- Not referenced from `marketplace.json`, the top-level README's install instructions, or anything in `cyoda/`.

## Step 2: Update to v0.8.4

The itemized worklist is the audit at `docs/superpowers/specs/2026-10-17-v084-audit.md`. It cites file and line in the v0.8.4 source, plus help topics, for every stale claim in the current skills.

### Breaking items: each must be fixed and covered by a smoke scenario

1. **Workflow schema version.** It must be `MAJOR.MINOR` within the supported range (current `1.4`). Templates read it from `cyoda help workflows schema-version versions` or state "use the current version from that command".
2. **Model lifecycle before entities.** The order is:
   1. `POST /api/model/import/JSON/SAMPLE_DATA/{e}/{v}`
   2. `PUT /api/model/{e}/{v}/lock`
   3. optional `changeLevel`
   4. import the workflow
   5. create the entity

   "Discover mode" is removed everywhere. The workflow must be imported before the first entity.
3. **Firing a transition without changing data** is `PATCH /api/entity/JSON/{id}/{t}` with merge-patch, `If-Match: *` and `{}`. A PUT replaces the payload.
4. **Workflow import is strict.** An export can't be re-posted verbatim; reshape it to `{importMode, workflows}`. This matters for `deploy` re-seeding.
5. **Health** is `GET /api/health` on the API port. `/livez` and `/readyz` are on the admin listener only (default `127.0.0.1:9091`).
6. **Compute tag routing** is overlap: any one shared tag, exact case-sensitive match, random among matches, empty matches all.
7. **Timeouts:** the response timeout defaults to 30 s (per-processor `responseTimeoutMs`). Keep-alive is a 10 s interval with a 30 s timeout.
8. **Patterns file:** remove the "scheduled processor" and "message-triggered transition" patterns and the "one entity in several parallel workflows" pattern. Scheduled transitions are a `schedule` object on a transition.
9. **Homebrew** is `brew install cyoda/cyoda-go/cyoda`. Other install routes are listed in `cyoda help run` / `quickstart`.
10. **Quote the auth header** in scripts.

### New v0.7–0.8.4 surface to reach via help, not restate

Scheduled transitions, processor execution modes and transaction-token joining, function-criteria rejection reasons, PATCH, unique keys, search and grouped statistics, point-in-time reads, conditional and soft delete, the audit API, cyoda-go JWT auth, temporal type detection, the admin listener, telemetry, and storage backends (memory, sqlite, postgres, plus the Cassandra plugin).

**Cloud-only items the dev package must not present as available:** Trino SQL analytics (`cyoda help analytics` is Cloud-only), and any accepted-but-unimplemented fields the audit lists in §5.

## Step 3: Refinement

### Help-first skill shape

Each `SKILL.md` is structured as:

1. **When and why**: frontmatter description, and when to hand off to another skill.
2. **The conversation**: what to ask the developer, what to propose, and judgment calls such as how many states and whether a compute node is needed.
3. **The steps, in order.** Each step names the **`cyoda help <topic> [subtopic]`** to consult for the facts, then the action. For example: "Read `cyoda help models` LIFECYCLE, then import sample data and lock."
4. **Side effects and safety**: what gets written or called, and the production guard.
5. **Pointers** to the shared best practices, by bullet name.

What stays inline: the order of operations and smoke-tested recipes, kept short enough that they don't restate help. Example payloads live in `templates/` or `examples/`, not in `SKILL.md`, and are exercised by smoke tests.

`docs` is the gateway. Other skills may call `cyoda help` directly, but `docs` defines the lookup strategy:
1. local binary
2. `https://docs.cyoda.net/help/` mirror (same content as the binary)
3. the docs site, with a caution that getting-started is known-wrong until cyoda-docs#134 closes

Update stale references, e.g. the schemas link becomes `cyoda help cloudevents json` / `grpc proto` / `openapi json`.

**If the binary isn't installed:** `docs` and `design` work from the web help mirror. `setup` offers install. Side-effecting skills require an instance.

### Best practices

- Canonical copy: `cyoda/skills/design/resources/best-practices.md`. Its content is the corrected list in Cyoda/cyoda-go#680, which is the fact-checked version of `ctcc-management/docs/workflow-best-practices.md`. The file is marked "Temporary — superseded by `cyoda help <topic>` once cyoda-go#680 ships".
- `design` checks for the help topic first. Probe `cyoda help workflows best-practices` and `cyoda help design`, falling back to the bundled file. When the help topic ships, a follow-up removes the bundled file.
- Merge it with the existing `design/resources/design-guidelines.md`. Remove overlap and drop anything in `design-guidelines.md` that contradicts v0.8.4.
- `build` references it when generating states, transitions and criteria: error states, terminal states, loopback, validation cycles, rejection reasons. `debug` references it when diagnosing: loopback to re-evaluate, error-state queries, soft delete bypassing the workflow.
- Notifications: "coming soon — check `cyoda help` for availability". Today's options are state queries, `ASYNC_NEW_TX` processors, and scheduled transitions for escalation.

### `cyoda:deploy` (new)

Frontmatter: `disable-model-invocation: true`. It writes files into the developer's project, so it should only run when invoked deliberately.

Audience: the app developer first. **The skill writes deployment files. It doesn't run them.** Its output is a set of files in the developer's project that the developer, or a devops person, runs and scripts from. The skill never runs `docker compose`, `helm`, `kubectl` or secret generation itself. It ends by listing the exact commands to run, in order. If the developer then asks the agent to run them, that's an ordinary request outside the skill.

**Scope: cyoda-go only, not the developer's own services (my call).** This follows the existing plugin principle that Cyoda is the platform, not the application. `deploy` makes the instance reachable for compute nodes:
- it exposes gRPC (the compose port, or a Helm GRPCRoute / gRPC ingress with TLS at the edge)
- it records the values a compute node needs (`CYODA_COMPUTE_GRPC_ENDPOINT`, token source) in the generated artifacts

It doesn't build or package the developer's compute-node images. Verification of processors therefore only happens if the developer's compute node is already running against the new instance.

The flow:

1. **Preconditions.** A working app on local cyoda-go (`status`), with the project's versioned model and workflow files written by `build` present.
2. **Choose a target.**
   - **Docker Compose:** a single shared or team instance. Based on `deploy/docker/compose.yaml` (sqlite) or `examples/compose-with-observability` (postgres + otel-lgtm), with facts from `cyoda help run`.
   - **Helm on Kubernetes:** facts from `cyoda help helm` and `cyoda help config`. Chart from `helm repo add cyoda https://cyoda.github.io/cyoda-go`, pinned to the chart version matching the binary (0.8.4). The image is `ghcr.io/cyoda/cyoda:<X.Y.Z>`. The skill walks through the values: storage (postgres), secrets (bootstrap client, HMAC, metrics), gateway vs ingress, replicas and HPA, and the migration job.
   - **Terraform:** a pointer to `Cyoda/cyoda-go-terraform`, marked early and AWS-first. Not guided.
3. **Generate artifacts** into the developer's project. Scan first for an existing deploy dir, matching the scan-first placement convention used by `build`. Artifacts:
   - a compose file or Helm values file
   - a secrets checklist: what to create, and the env var or Kubernetes Secret each one is read from. Never real secret values in files.
   - a `verify` script that checks `/api/health` (API port) and `/readyz` (admin port), then runs a minimal smoke check
   - a **seed script** that loads models and workflows over REST in the correct order (import sample, lock, `changeLevel`, unique keys, workflow). There's no other seeding mechanism.
     - **Source (my call):** the project's versioned files written by `build`: `{entity}-v{version}-sample.json`, `-workflow.json` and `-config.json`. Not live exports. Model import only accepts `SAMPLE_DATA`, so a model export can't be re-imported. Live workflow exports are offered only as a fallback, and get reshaped for the strict import.
     - **Per-environment schema settings (my call):** `build` records lock, `changeLevel` and unique keys in `{entity}-v{version}-config.json`. The seed takes an env argument. For `production` it applies **no `changeLevel`** (strict) unless the config file sets an explicit per-env override. For other envs it applies what `build` recorded. A permissive dev schema never reaches production silently.
4. **Hand over.** List the commands, in order: create secrets, `docker compose up` / `helm install`, `verify`, seed. Explain what each artifact is for, so a devops person can fold it into their own pipeline.
5. **Optionally register a profile** for the new instance (endpoint and env only, see Connection config), so `status`, `build` and `debug` can target it later.

Known upstream inconsistencies the skill must not trip over:
- help says the chart is unpublished (cyoda-go#677)
- the compose file's commented "production" block sets `CYODA_REQUIRE_JWT=true` without `CYODA_IAM_MODE=jwt`, and passes the PEM inline instead of via `CYODA_JWT_SIGNING_KEY_FILE`

Follow help, not that block. *Builder's call: file a cyoda-go issue for the compose block if not already filed.*

### `cyoda:auth` (rewritten for cyoda-go)

Facts come from `cyoda help auth` and its subtopics (clients, tokens, oidc, trusted-keys) and `cyoda help config auth`. The skill helps the developer **write** what their app and scripts need:
- choosing the auth path (M2M client, OIDC, trusted key) and the server-side config for it
- a small token script, e.g. `get-token.sh`. It reads the client id and secret from env vars, calls cyoda-go's token endpoint, and prints the JWT, so `export CYODA_TOKEN=$(./get-token.sh)` works.
- how their own app obtains and renews tokens (cyoda-go issues no refresh token)

Nothing is persisted by the plugin. Mock auth (the local default) needs no token, and the skill says so. The production guard becomes a confirmation before any skill sends a *mutating* API call to a profile with `env: production`.

### `setup`

- **Local:** install via Homebrew (`cyoda/cyoda-go` tap). If Homebrew fails, keep today's "ask the user to run it verbatim" behaviour, now pointing at `cyoda help run` for other install routes. Then `cyoda init` (sqlite) and start, verify `/api/health`, and write the `default` profile.
- **Connect to existing:** ask for the endpoint, probe `/api/health`, and create a profile. If the instance isn't mock auth, hand off to `auth`.

## Evals

- Every dev-package skill gets `evaluations/evals.json` rewritten, with ≥3 cases (happy, edge, failure), including `deploy` and the rewritten `auth`. Assertions check help-first behaviour: the skill consults the named help topic rather than asserting a fact from memory.
- Every skill gets at least one assertion that it doesn't mention Cyoda Cloud.
  - **What counts (my call):** the skill's *own* wording and recommendations. Real identifiers that contain "cloud" (the proto package `org.cyoda.cloud.api.grpc`, `cyoda-cloud-api.proto`) are fine. So is help content quoted in answer to a direct question.
  - **When the user asks about Cloud or migration**, a dev skill says "not covered by this plugin" and nothing more.
  - **Cloud-only features** (SQL analytics via `cyoda help analytics`) are described as "not available in cyoda-go".
- Process per `CLAUDE.md`, results in `cyoda-evals-workspace/iteration-N/<skill>/`.
- **Executors may run real `cyoda help` (my call).** An executor agent reads the skill, takes the eval prompt and fixture files, and writes a transcript of what it would do. Today everything in that transcript is imagined, including any `cyoda help` output.
  - Executors may run read-only `cyoda help …` against the installed binary. Every other command stays simulated, as now: brew, curl to an instance, docker/helm, file writes outside the eval output dir.
  - So a help-first assertion ("consulted `cyoda help models` before locking") grades a real lookup, and fact assertions can check the answer against real help output.
  - `CLAUDE.md`'s eval section gets a one-line note saying this.
- **Run in slices**, pausing after each for the user's go-ahead. Report each slice's summed executor and grader `total_tokens`, `duration_ms`, and the pass rate. Proposed order:
  1. `setup` + `status`
  2. `design`
  3. `build`
  4. `deploy` + `auth`
  5. `compute` + `debug`
  6. `test` + `docs` + `app`
- Parked-package evals: moved, not rewritten, not run.

## Smoke tests

Location: `tests/smoke/`, with a README.

Runner:
- A shell script that starts `cyoda` with `CYODA_STORAGE_BACKEND=memory` and `CYODA_IAM_MODE=mock` on non-default ports, so it doesn't collide with the developer's own instance (e.g. HTTP 18080, gRPC 19090, admin 19091).
- It waits for `/api/health`, runs the scenarios, reports pass/fail per scenario, and stops the server.
- It fails fast if `cyoda --version` isn't 0.8.4, overridable for trying newer versions.

**Breaking items with no live scenario (my call).** Three of the Step 2 items can't be tested by running the binary:
- item 9, the Homebrew tap: installing has side effects
- item 10, header quoting: a property of the scripts
- item 7, timeouts: proving them means waits of over 30 s

These get a **static check** in `tests/smoke/lint.sh` instead:
- grep the dev package for known-stale strings (`cyoda-platform/cyoda-go` tap, `"version": "1"`, `/readyz` on the API port, "discover mode", 60 s timeouts, "Cyoda Cloud")
- `shellcheck` on shipped scripts

There's no slow timeout scenario.

Each scenario loads payloads **from the skill's `templates/` and `examples/`**, not private copies, so a skill teaching something the binary rejects makes a scenario fail. Where a skill gives a recipe in prose, the scenario follows it and the skill's example file is the shared source.

Reference scenarios, accepted by the user as a starting set:

1. **Hello-world lifecycle:** import sample data → lock → import workflow (current schema version) → create entity → automated transitions to a terminal state. Assert final state and history.
2. **Manual transition and loopback:** fire a named transition via PATCH `{}`. A criterion-gated automated transition stays blocked; an update without a transition name (loopback) after the data changes lets it fire.
3. **Validation and error states:** a built-in criterion routes bad data to `Errored`, a correction returns it before the validation step, and it ends in one of several terminal states (`Completed` / `Cancelled`).
4. **Scheduled transition** with a short delay.
5. **Queries instead of counters:** a point-in-time search and grouped statistics over several entities.
6. **Soft delete:** a deleted entity is gone from current reads but visible via a point-in-time read or history, and no workflow ran.
7. **Compute node:** a minimal Go compute member built from cyoda-go's proto (`cyoda help grpc proto`), with:
   - a processor
   - a function criterion returning a rejection reason (asserted in the 400 detail or audit)
   - the processor firing a manual transition on a linked entity referenced by entity-id (event cascade)

   It lives in `tests/smoke/compute/` with its own `go.mod`.
   - **Stubs (my call):** import the generated packages from the cyoda-go module pinned at v0.8.4 (`github.com/cyoda-platform/cyoda-go/api/grpc/...`; the module path at that tag still uses the old org). No protoc prerequisite.
   - **Shared files:** the "load from skill files" rule applies to the workflow and criteria JSON and the tag names, which come from `compute/examples/`. The Go code is test harness and stays out of the language-agnostic `compute` skill.

## What's left to the builder

- Exact skill wording, section structure inside each `SKILL.md`, and how much short inline recipe vs. pointer to help, within the help-first shape above.
- Eval case design and assertion wording.
- Smoke runner implementation details (shell vs. Go harness for scenarios 1–6, output format).
- Merge strategy between `design-guidelines.md`, `patterns.md` and the best-practices file.
- Version bump: dev package to `0.4.0` in `plugin.json`, Gemini manifest kept in step.
- Commit granularity. Suggested: one commit per step (segregation, update, refinement), with evals and smoke tests as their own commits.
