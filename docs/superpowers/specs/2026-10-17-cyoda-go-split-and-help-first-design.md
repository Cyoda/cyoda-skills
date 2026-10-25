# Cyoda Plugin: cyoda-go / Cloud Split, v0.8.4 Update, Help-First Refinement

**Date:** 2026-10-17
**Status:** Draft, awaiting approval
**Supersedes:** cloud-related parts of `2026-04-24-cyoda-plugin-design.md`. That doc stays as history; this one is the source of truth for the plugin's shape from here on.

## Intent

Cyoda Cloud is paused and will look very different when it comes back. The current `cyoda` plugin mixes cloud into most skills: `auth` and `migrate` are cloud-only, and `setup`, `status`, `app`, `compute` and `debug` have cloud branches. The skills were also written against cyoda-go ~v0.6.3. Against v0.8.4 several of their core examples fail outright: workflow `"version": "1"` gives 400, entity creation without a locked model gives 404 or 409, an empty-PUT transition gives 400, health probes go to the wrong port, and compute tag routing is described backwards.

This work has three steps, done in order:

1. **Segregation.** Two separate packages. The **dev** package covers developing and running cyoda-go and is completely cloud-agnostic. The **cloud** package is parked as a git tag on the last pre-split commit and removed from `main`, so it can't be installed until the service is re-established.
2. **Update.** Bring the dev package to cyoda-go **v0.8.4**.
3. **Refinement.** Make the skills **help-first**: a smart wrapper over `cyoda help`. Fold in the fact-checked workflow best practices, add a `deploy` skill, rewrite every eval, and add runnable smoke tests.

The why behind help-first: almost everything that broke between v0.6.3 and v0.8.4 was a platform fact copied into a skill. `cyoda help` ships with the binary and matches its version, so a skill that defers to it survives upgrades. What the skills keep is what help can't know: the conversation with the developer, the order of steps across topics, side effects, and judgment.

## Goals

- `cyoda` (dev) is the only plugin on `main` and in `marketplace.json`. The cloud skills survive unchanged at the tag `cloud-frozen-0.3.0`, which points at `d977dd9` (plugin v0.3.0, the last commit before this work). Nothing cloud is on `main`.
- The dev package's own content never offers or recommends Cyoda Cloud: no cloud branches, no "move to Cloud later", no cloud URLs, no Cloud OAuth. (See Evals for what counts.)
- Every concrete instruction in the dev package works against cyoda-go v0.8.4. Wherever possible the skills get there by **pointing at the right `cyoda help` topic** rather than restating facts.
- A new `cyoda:deploy` skill takes an app developer from a working local app to a self-hosted cyoda-go: Docker Compose, then Helm. It produces artifacts a devops person can script from.
- The corrected best practices are reachable from `design`, `build` and `debug`.
- Evals are rewritten for every dev-package skill. They run in slices, with the token cost reported after each slice.
- Smoke tests run reference scenarios against a real cyoda-go v0.8.4 (in-memory storage, mock auth) and exercise exactly what the skills teach.

## Non-goals

- Updating, redesigning or re-testing the cloud skills. They're frozen as-is.
- Making Terraform a guided deploy path. `Cyoda/cyoda-go-terraform` describes itself as "early build, not yet ready for production", so it only gets a pointer.
- Running smoke tests in CI. They're local and on demand, and need the `cyoda` binary installed.
- Carrying corrections for wrong `cyoda help` content inside the skills. Help bugs get fixed upstream. **Exception:** a workaround is allowed only if it's listed in the Upstream table with its issue number. It gets removed when that issue ships.
- Changing the Gemini extension beyond keeping it consistent with the dev package.

## Anti-goals: failing even if it technically works

- The dev package still leaks cloud, e.g. `app` suggesting "move to Cloud when ready", `status` printing "Cyoda Cloud", or a profile `env: production` path that talks about Cloud.
- Skills re-grow embedded reference material (endpoint tables, env-var lists, schema JSON) that duplicates `cyoda help`. That rebuilds the drift problem this work exists to remove.
- Cloud content remains anywhere on `main`, where it could be loaded with `--plugin-dir` or a git-subdir marketplace source.
- Smoke tests that test their own fixtures rather than the skills' templates and recipes.
- Hard-coding the workflow schema version anywhere it could instead be read from `cyoda help workflows schema-version versions`.

## Constraints

- Repo rules from `CLAUDE.md`:
  - `SKILL.md` stays under 500 lines.
  - Skills don't embed Cyoda docs.
  - Skills with side effects carry `disable-model-invocation: true` (enforced by this work; see Side-effect skills).
  - Each skill has `evaluations/evals.json` with 3+ cases (happy path, edge case, failure).
  - `superpowers:writing-skills` is invoked before authoring or editing skills.
  - The eval process follows `CLAUDE.md` ("Running evals").
- Target is cyoda-go **v0.8.4**: tag `v0.8.4` at github.com/Cyoda/cyoda-go, and the installed binary reports `0.8.4`.
- **Source-of-truth order when references disagree:** cyoda-go code at v0.8.4, then `cyoda help`, then docs.cyoda.net. The docs getting-started page is known-wrong (cyoda-docs #134).
- GitHub org is now `Cyoda` (was `Cyoda-platform`), so all repo URLs need updating.
- Smoke tests use `CYODA_STORAGE_BACKEND=memory` and `CYODA_IAM_MODE=mock` (decided by the user).

## Decisions made with the user

- **Two separate installs.** Dev and cloud are distinct plugins, following the kebab-case plugin naming convention.
- **Cloud package parked, not installable** until the service is back. It's parked as the tag `cloud-frozen-0.3.0` and removed from `main`, not kept as an unlisted folder.
- **Enforce the `CLAUDE.md` side-effect rule.** Skills with side effects get `disable-model-invocation: true`, and hand-offs between them become "next, type `/cyoda:<x>`".
- **Add a `deploy` skill.** It's for the app developer first, and its output should be a basis a dev or devops person can script from.
- **Delegate as much as possible to `cyoda help`.** The skills are mainly a smart wrapper over the help feature. Best practices should ultimately live in `cyoda help` too.
- **Notifications** are phrased as "coming soon — check `cyoda help` for availability". Use the same phrasing for any other unshipped feature.
- **Evals:** rewrite for every skill, run the suite in slices, and report token cost per slice.
- **Smoke tests** cover a number of reference scenarios. The proposed set (below) was accepted as "a good start".

## Upstream work (filed 2026-10-17)

| Issue | What | Effect on this work |
|---|---|---|
| Cyoda/cyoda-docs#134 | Getting-started fails on v0.8.4 (version, lock, empty PUT) | `docs` skill's web fallback is unreliable for these until fixed. Skills must not derive recipes from that page |
| Cyoda/cyoda-go#684 (v0.9.0) | Consolidated `cyoda help` issue; supersedes #677, #679, #680, #681, #682, #683. Items: A helm chart "unpublished, 0.1.0"; B `workflows` says tags match ALL (code: ANY); C `crud` says empty-body PUT is fine (it's 400); D `run` Helm minimal install has no bootstrap client; E `config` profile files `cyoda.N.env` (code: `.env.N`); F `audit` missing `SCHEDULED_TRANSITION_*` events; G `helm` empty `gateway.parentRefs` doesn't fail; H `helm` VALUES missing `migrate.postgres.existingSecret`; I `workflows` import strictness / export not re-importable undocumented; J `responseTimeoutMs` 0 = 30 s server default; K no install section; L design best-practices topic; M `deploy/docker/compose.yaml` commented production hint is missing `CYODA_IAM_MODE: jwt` and passes the signing key inline; N `errors` ERROR CODE INDEX is incomplete (some codes have a page but no index row) | A, D, G: `deploy` uses the published repo, always sets the bootstrap client, sets gateway or ingress explicitly. B: `compute`/`debug` cite `cyoda help grpc` TAG ROUTING only. C: skills use PATCH `{}`. I: `build`/`deploy` reshape exports to `{importMode, workflows}`. J: `compute`/`debug` state 30 s. K: `setup` carries a short install list. L: `design` uses the topic when present, else the bundled copy. M: the `deploy` skill writes its own correct compose. N: `docs`/`debug` look every code up with `errors <CODE>`, never conclude from the index that a code doesn't exist. E, F, H: avoid relying on those sections |

**Help audit pass (first implementation task).** Before any skill defers to a help topic, check every topic and section the skills will point to against the v0.8.4 code. Each mismatch either gets filed and added to this table, or the skill points elsewhere.

## Target layout

```
.claude-plugin/marketplace.json     ← lists ONLY "cyoda" (source ./cyoda)
cyoda/                              ← dev package (plugin name "cyoda")
  .claude-plugin/plugin.json        ← description cloud-free, version 0.4.0, repository → github.com/Cyoda/cyoda-skills
  README.md  GEMINI.md  gemini-extension.json
  skills/
    app/ setup/ status/ auth/ docs/ design/ build/ compute/ test/ debug/ deploy/
tests/
  smoke/                            ← runnable reference scenarios (see Smoke tests)
docs/superpowers/specs/…            ← this doc
```

### Why the dev plugin keeps the name `cyoda` (builder's call, confirmed in playback)

Existing installs (`cyoda@cyoda`) and skill names (`cyoda:build`, etc.) keep working. When Cloud returns, its redesigned package takes the new name `cyoda-cloud`.

## Step 1: Segregation

### Dev package (`cyoda/`)

Skills: `app`, `setup`, `status`, `auth`, `docs`, `design`, `build`, `compute`, `test`, `debug`, plus the new `deploy`. `migrate` leaves the dev package entirely.

Cloud content removed per skill:
- `app`: drop the Cloud option in Step 2, Step 6 ("Move to Cyoda Cloud"), and "same API works locally and on Cloud". The journey ends with an optional `deploy` step instead.
- `setup`: local only. A second mode, **connect to an existing self-hosted cyoda-go** (e.g. one created by `deploy`), replaces the cloud mode.
- `status`: report "Connected to cyoda-go vX.Y.Z — <endpoint> [profile: P]" for any instance. A self-hosted instance marked production shows a `[PRODUCTION]` tag. No "Cloud" wording.
- `auth`: **rewritten** for cyoda-go's own auth (see Step 3). The current Cloud OAuth version stays only at the tag.
- `compute`, `debug`: remove cloud mentions.
- `README.md`, top-level `README.md`, `plugin.json` description, `GEMINI.md`: no cloud.

**Connection config** stays at `~/.config/cyoda/cyoda-plugin-config.json` with named profiles, now generalized to cyoda-go instances:
- `default` is local with mock auth and no token.
- **Project binding.** A developer with several apps, each on its own cyoda-go (e.g. its own Compose stack and ports), binds each project privately with `<project>/.cyoda/instance.json` = `{endpoint, env, tokenCommand?}` (no secrets; a relative `tokenCommand` runs from the project root). `setup`'s "link this project" mode writes it (0600, `.cyoda/` added to `.gitignore`), listing running `ghcr.io/cyoda/cyoda` containers read-only. The legacy `.cyoda/config` is read for `endpoint`/`env` only (a `token` in it is ignored with a warning); `instance.json` wins over it. The search runs from `$PWD` up to the git root, never `$HOME` or above.
- **Lookup order:** `CYODA_PROFILE=<name>` (an explicit machine-wide profile; unknown is an error), then the project binding, then the active profile, then the implicit default. `cyoda-profile.sh` reports `source` (`project` | `profile` | `default`) and `projectDir`; `status` shows `[project: <dir name>]` for a binding.
- **Implicit default.** With no config file, the scripts use an unsaved `default` profile (`http://localhost:8080`, `development`, no `tokenCommand`) and warn "no saved profile; using the default local instance http://localhost:8080 — type /cyoda:setup to save it"; if nothing answers there, the unreachable warning says "no cyoda-go is answering at http://localhost:8080 — type /cyoda:setup to install or start one". A config file that exists is used as it is: a profile without an endpoint stays `not_configured`.
- A self-hosted instance is added by `setup` (connect mode) or `deploy`. It carries `endpoint`, `env` (`development` | `production`) and, for non-mock auth, `tokenCommand`. `tokenCommand` is the path to a script (generated by `auth`) that prints a fresh JWT.
- **The plugin stores no tokens or secrets.** The token script reads client credentials from the developer's own env or keychain. Skills run `TOKEN=$(<tokenCommand>)` before each API call. This handles the 1 h token expiry, and an `export` doesn't carry between the agent's shell calls anyway. Each profile has its own command, so a staging token can't go to prod.
- **401/403 rule** (replaces "invoke `auth` to refresh"): re-run `tokenCommand` once and retry. If that fails, surface the error and suggest `/cyoda:auth`.
- **Existing configs.** Current users' files may contain `token` fields and old endpoints, possibly on the active profile. `status` and `setup` detect a stored `token` and say neutrally: "profile P contains a stored token, which this plugin no longer reads; you can remove it". An unreachable active profile gets an offer to switch to `default`. The config schema belongs to the dev package.
- The production safety guard stays, as a generic self-hosted concern: an explicit confirmation before any skill sends a mutating API call to a profile with `env: production`.

### Parked cloud package (git tag)

- **First task of segregation:** create the annotated tag `cloud-frozen-0.3.0` on `d977dd9`, with the message "Cyoda Cloud skills as of plugin v0.3.0, parked while Cloud is paused". Push it only with the user's go-ahead.
  - The tag holds the complete, working pre-split plugin, cloud parts included: `auth`, `migrate`, and the cloud branches of `setup`, `status` and `app`, with their evals.
  - Nothing is extracted or edited, so the frozen content is exactly what worked.
- Then delete from `main`: `cyoda/skills/migrate/` and its evals, the Cloud OAuth `auth` (replaced by the rewrite), `migration-checklist.md`, and every cloud branch in the remaining skills.
- **Pointer, the only cloud reference on `main`:** a short "History" note in `docs/` (not in the plugin) saying the Cloud skills are parked at `cloud-frozen-0.3.0` and will be redesigned, not revived, when the service returns. It isn't in `cyoda/` or the install instructions.

## Step 2: Update to v0.8.4

The itemized worklist is the audit at `docs/superpowers/specs/2026-10-17-v084-audit.md`. It cites file and line in the v0.8.4 source, plus help topics, for every stale claim in the current skills.

### Breaking items: each must be fixed and covered by a smoke scenario

1. **Workflow schema version.** It must be `MAJOR.MINOR` within the supported range (current `1.4`). Templates read it from `cyoda help workflows schema-version versions` or state "use the current version from that command".
2. **Model lifecycle before entities.** The order is:
   1. `POST /api/model/import/JSON/SAMPLE_DATA/{e}/{v}`
   2. optional `PUT /api/model/{e}/{v}/unique-keys`. This is only allowed while the model is UNLOCKED.
   3. `PUT /api/model/{e}/{v}/lock`
   4. optional `changeLevel`
   5. import the workflow
   6. create the entity

   This is the canonical order everywhere: `build`, the seed script, smoke tests. "Discover mode" is removed everywhere. The workflow must be imported before the first entity. Evolving a model that already has entities means a new model version (`MODEL_HAS_ENTITIES`), and `build` says so.
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
1. the active profile's own instance, `GET {endpoint}/api/help/<topic>` (no auth needed), so help matches the server being targeted
2. local binary
3. `https://docs.cyoda.net/help/` mirror (same content as the binary, pinned to the docs' version)
4. the docs site, with a caution that getting-started is known-wrong until cyoda-docs#134 closes

`status` warns when the local binary's version differs from the active instance's.

**Read sections, not whole topics.** Topics are large: `crud` and `workflows` are each ~12k tokens. The documented lookup primitive is section-level, e.g. `cyoda help models --format=json | jq '.sections[] | select(.name=="LIFECYCLE")'`. Skills name the topic *and* the section.

Update stale references, e.g. the schemas link becomes `cyoda help cloudevents json` / `grpc proto` / `openapi json`.

**If the binary isn't installed:** `docs` and `design` work from the web help mirror. `setup` offers install. Side-effecting skills require an instance.

### Best practices

- Canonical copy: `cyoda/skills/design/resources/best-practices.md`. Its content is the corrected list in Cyoda/cyoda-go#684 item L, which is the fact-checked version of `ctcc-management/docs/workflow-best-practices.md`. The file is marked "Temporary — superseded by `cyoda help <topic>` once cyoda-go#684 item L ships".
- `design` checks for the help topic first. Probe `cyoda help workflows best-practices` and `cyoda help design`, falling back to the bundled file. When the help topic ships, a follow-up removes the bundled file.
- Merge it with the existing `design/resources/design-guidelines.md`. Remove overlap and drop anything in `design-guidelines.md` that contradicts v0.8.4.
- `build` references it when generating states, transitions and criteria: error states, terminal states, loopback, validation cycles, rejection reasons. `debug` references it when diagnosing: loopback to re-evaluate, error-state queries, soft delete bypassing the workflow.
- Notifications: "coming soon — check `cyoda help` for availability". Today's options are state queries, `ASYNC_NEW_TX` processors, and scheduled transitions for escalation.

### Side-effect skills (enforcing the `CLAUDE.md` rule)

With `disable-model-invocation: true`, only the user can start a skill, by typing `/cyoda:<x>`. Claude can't start it on its own or from another skill, and the skill's description isn't loaded into Claude's context. Today only `test` has the flag, which breaks the repo's own rule.

| Skill | Flag | Why |
|---|---|---|
| `app` | yes | orchestrates side-effecting steps |
| `setup` | yes | installs software, starts a server, writes config |
| `build` | yes | writes project files, registers models and workflows on the instance |
| `test` | yes (already) | creates entities, fires transitions |
| `deploy` | yes | writes deployment files into the project |
| `auth` | yes | writes the token script, updates the profile |
| `status`, `docs`, `design`, `compute`, `debug` | no | read-only or advisory; Claude may use them whenever relevant |

**Consequences:**
- **Hand-offs** (`app`→`setup`/`build`/`test`/`deploy`, `docs`→`setup`, `setup`→`auth`, the 401 rule→`auth`) are written as "next, type `/cyoda:<x>`", with a one-line reason. They never say "invoke".
- `debug` stays auto-invocable, so any fix it proposes that would change the instance is handed off to `/cyoda:build`, or done only after an explicit yes.
- Update `CLAUDE.md`'s list to `setup`, `build`, `test`, `app`, `deploy`, `auth`. `migrate` is gone.
- Evals for flagged skills assert that hand-offs say "type `/cyoda:<x>`" rather than invoking.

### `cyoda:deploy` (new)

Frontmatter: `disable-model-invocation: true` (see Side-effect skills).

Audience: the app developer first. **The skill writes deployment files. It doesn't run them.** Its output is a set of files in the developer's project that the developer, or a devops person, runs and scripts from. The skill never runs `docker compose`, `helm`, `kubectl` or secret generation itself. It ends by listing the exact commands to run, in order. If the developer then asks the agent to run them, that's an ordinary request outside the skill.

**Scope: cyoda-go only, not the developer's own services (my call).** This follows the existing plugin principle that Cyoda is the platform, not the application. `deploy` makes the instance reachable for compute nodes:
- it exposes gRPC (the compose port, or a Helm GRPCRoute / gRPC ingress with TLS at the edge)
- it records the values a compute node needs (`CYODA_COMPUTE_GRPC_ENDPOINT`, token source) in the generated artifacts

It doesn't build or package the developer's compute-node images. Verification of processors therefore only happens if the developer's compute node is already running against the new instance.

The flow:

1. **Preconditions.** A working app on local cyoda-go (`status`), with the project's versioned model and workflow files written by `build` present.
2. **Choose a target.**
   - **Docker Compose:** a single shared or team instance. Based on `compose.yaml` and `examples/compose-with-observability` **from the tag matching the binary** (`v0.8.4`), not `main`. Facts from `cyoda help run`. The upstream compose file is mock auth on loopback, which would give anyone who can reach it full admin rights. So the skill asks: **single-user** (loopback, mock auth, labelled as such) or **shared** (JWT mode, `CYODA_JWT_SIGNING_KEY_FILE` mounted `:ro`, a bootstrap client, per `cyoda help run` and `cyoda help config auth`).
   - **Helm on Kubernetes:** facts from `cyoda help helm` and `cyoda help config`. Chart from `helm repo add cyoda https://cyoda.github.io/cyoda-go`, pinned to the chart release whose **appVersion** matches the binary (`helm search repo cyoda/cyoda --versions`), not to an assumed chart version. The image is `ghcr.io/cyoda/cyoda:<X.Y.Z>`. The skill walks through the values: storage (postgres), secrets (bootstrap client, HMAC, metrics), gateway vs ingress, replicas and HPA, and the migration job.
   - **Terraform:** a pointer to `Cyoda/cyoda-go-terraform`, marked early and AWS-first. Not guided.
3. **Generate artifacts** into the developer's project. Scan first for an existing deploy dir, matching the scan-first placement convention used by `build`. Artifacts:
   - a compose file or Helm values file
   - a secrets checklist: what to create, and the env var or Kubernetes Secret each one is read from. Never real secret values in files.
   - a `verify` script that checks `/api/health` from outside. It checks `/readyz` only where reachable: inside compose, or through `kubectl port-forward`. The admin port is loopback by default, and the chart's NetworkPolicy limits it to the monitoring namespace. After seeding it runs a minimal smoke check.
   - a **seed script** that loads models and workflows over REST in the canonical order (Step 2 item 2). There's no other seeding mechanism.
     - **Source (my call):** the project's versioned files written by `build`: `{entity}-v{version}-sample.json`, `-workflow.json` and `-config.json`. Not live exports. Model import only accepts `SAMPLE_DATA`, so a model export can't be re-imported. Live workflow exports are offered only as a fallback, and get reshaped for the strict import.
     - **Finding the files:** `build` keeps a small manifest at the project root, `cyoda-manifest.json`, listing each entity version's three files. `deploy` reads it, and falls back to `build`'s scan if it's missing.
     - **`-config.json` schema (defined in `build/templates/`):**
       - `uniqueKeys`
       - `changeLevel`
       - an optional `env` map of per-environment overrides, e.g. `{"production": {"changeLevel": null}}`
     - **Per-environment schema settings (my call):** the seed takes an env argument and applies the recorded `changeLevel` unless that env overrides it. When `deploy` targets `production`, it asks whether any processor writes fields not in the sample, because a strict schema rejects those. It records the answer as the production override. A permissive dev schema never reaches production without that question being asked.
     - **Idempotent:** the seed checks each model's state first. A model already LOCKED at that version is skipped. Workflows are re-imported with `importMode: REPLACE`.
4. **Hand over.** List the commands, in order: create secrets → `docker compose up` / `helm install` → health check → seed → `verify` smoke check. Explain what each artifact is for, so a devops person can fold it into their own pipeline.
5. **Optionally register a profile** for the new instance (endpoint and env only, see Connection config), so `status`, `build` and `debug` can target it later.

Known upstream inconsistencies the skill must not trip over:
- help says the chart is unpublished (cyoda-go#684 item A)
- the compose file's commented "production" block sets `CYODA_REQUIRE_JWT=true` without `CYODA_IAM_MODE=jwt`, and passes the PEM inline instead of via `CYODA_JWT_SIGNING_KEY_FILE`

Follow help, not that block. *Builder's call: file a cyoda-go issue for the compose block if not already filed.*

### `cyoda:auth` (rewritten for cyoda-go)

Facts come from `cyoda help auth` and its subtopics (clients, tokens, oidc, trusted-keys) and `cyoda help config auth`. The skill helps the developer **write** what their app and scripts need:
- choosing the auth path (M2M client, OIDC, trusted key) and the server-side config for it
- a small token script, e.g. `get-token.sh`. It reads the client id and secret from the developer's env or keychain, calls cyoda-go's token endpoint, and prints the JWT. Its path is saved as the profile's `tokenCommand`. The same script is what the seed and verify scripts use.
- how their own app obtains and renews tokens (cyoda-go issues no refresh token)

Nothing is persisted by the plugin. Mock auth (the local default) needs no token, and the skill says so. The production guard becomes a confirmation before any skill sends a *mutating* API call to a profile with `env: production`.

### `setup`

- **Local:** install via Homebrew (`brew install cyoda/cyoda-go/cyoda`). If Homebrew fails, keep today's "ask the user to run it verbatim" behaviour. Help doesn't list install routes and isn't available before install, so `setup` carries a short list itself until the upstream issue ships: brew, `install.sh`, the GitHub release page, Docker. The lint checks it. Then `cyoda init` (sqlite) and start, verify `/api/health`, and write the `default` profile.
- **Connect to existing:** ask for the endpoint, probe `/api/health`, and create a profile. If the instance isn't mock auth, hand off to `auth`.

## Evals

- Every dev-package skill gets `evaluations/evals.json` rewritten, with ≥3 cases (happy, edge, failure), including `deploy` and the rewritten `auth`. Assertions check help-first behaviour: the skill consults the named help topic rather than asserting a fact from memory.
- Every skill gets at least one assertion that it doesn't mention Cyoda Cloud.
  - **What counts (my call):** the skill's *own* wording and recommendations. Real identifiers that contain "cloud" (the proto package `org.cyoda.cloud.api.grpc`, `cyoda-cloud-api.proto`) are fine. So is help content quoted in answer to a direct question.
  - **When the user asks about Cloud or migration**, a dev skill says "not covered by this plugin" and nothing more. This is the single rule. It doesn't contradict the Goals bullet, because the user raised Cloud, not the skill.
  - **Cloud-only features** (SQL analytics via `cyoda help analytics`) are described as "not available in cyoda-go".
- Process per `CLAUDE.md`, results in `cyoda-evals-workspace/iteration-N/<skill>/`.
- **Executors run against a real throwaway cyoda-go per eval** (in-memory, mock or JWT; help lookups real too), and simulate the instance only when the fixture needs specific entity ids/histories or a compute node; tooling and process in `tests/evals/` (README) and `CLAUDE.md`.
- **Run in slices**, pausing after each for the user's go-ahead. Report each slice's summed executor and grader `total_tokens`, `duration_ms`, and the pass rate. Proposed order:
  1. `setup` + `status`
  2. `design`
  3. `build`
  4. `deploy` + `auth`
  5. `compute` + `debug`
  6. `test` + `docs` + `app`
- Cloud evals: preserved at the tag, not run.

## Smoke tests

Location: `tests/smoke/`, with a README.

Runner:
- A shell script that starts `cyoda` with `CYODA_STORAGE_BACKEND=memory` and `CYODA_IAM_MODE=mock` on non-default ports, so it doesn't collide with the developer's own instance (e.g. HTTP 18080, gRPC 19090, admin 19091).
- It waits for `/api/health`, runs the scenarios, reports pass/fail per scenario, and stops the server.
- It fails fast if `cyoda --version` isn't 0.8.4. This can be overridden to try newer versions; scenario 7's Go stubs stay pinned to v0.8.4, so a proto mismatch there means "re-pin".
- **Isolation:** the runner points `HOME` and `XDG_CONFIG_HOME` at a temp dir, because the binary auto-loads `~/.config/cyoda/cyoda.env` and a developer's own settings there (e.g. `CYODA_REQUIRE_JWT=true`) would break a mock run.
- **Prerequisites:** `cyoda` 0.8.4, `jq`, `curl`; `shellcheck` for the lint; Go ≥ 1.26.7 for scenario 7.

**Breaking items with no live scenario (my call).** Three of the Step 2 items can't be tested by running the binary:
- item 9, the Homebrew tap: installing has side effects
- item 10, header quoting: a property of the scripts
- item 7, timeouts: proving them means waits of over 30 s

These get a **static check** in `tests/smoke/lint.sh` instead:
- grep the dev package for known-stale strings (`cyoda-platform/cyoda-go` tap, `"version": "1"`, `/readyz` on the API port, "discover mode", 60 s timeouts, "Cyoda Cloud"), excluding `evaluations/`, whose prompts and assertions mention these on purpose
- `shellcheck` on shipped scripts

There's no slow timeout scenario.

Each scenario loads payloads **from the skill's `templates/` and `examples/`**, not private copies, so a skill teaching something the binary rejects makes a scenario fail. Where a skill gives a recipe in prose, the scenario follows it and the skill's example file is the shared source.

Most of these example files don't exist yet. The current workflow template has `${…}` placeholders and `"version": "1"`. Creating them is part of the work: one example per scenario, owned by the skill that teaches it, mostly `build/examples/` and `design/resources/`. Placeholders are filled with `envsubst`, and the schema version comes from `cyoda help workflows schema-version versions` at run time. These are skill content the developer also sees, not private fixtures, so they don't conflict with the anti-goal.

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
8. **Seed script:** generate `deploy`'s seed for two entities, one with unique keys, and run it twice against the in-memory server. The second run must be a no-op.
   - **Stubs (my call):** import the generated packages from the cyoda-go module pinned at v0.8.4 (`github.com/cyoda-platform/cyoda-go/api/grpc/...`; the module path at that tag still uses the old org). No protoc prerequisite.
   - **Shared files:** the "load from skill files" rule applies to the workflow and criteria JSON and the tag names, which come from `compute/examples/`. The Go code is test harness and stays out of the language-agnostic `compute` skill.

## What's left to the builder

- Exact skill wording, section structure inside each `SKILL.md`, and how much short inline recipe vs. pointer to help, within the help-first shape above.
- Eval case design and assertion wording.
- Smoke runner implementation details (shell vs. Go harness for scenarios 1–6, output format).
- Merge strategy between `design-guidelines.md`, `patterns.md` and the best-practices file.
- Version bump: dev package to `0.4.0` in `plugin.json`, Gemini manifest kept in step.
- Commit granularity. Suggested: one commit per step (segregation, update, refinement), with evals and smoke tests as their own commits.

## Phasing (my call)

One plan, delivered in two phases, so the largest and most help-dependent pieces don't hold up the rest:
- **Phase A:**
  - help audit pass
  - segregation
  - v0.8.4 update
  - help-first rewrite of all dev skills
  - `deploy` with Docker Compose
  - `auth`
  - smoke scenarios 1–6 and 8, plus the lint
  - eval rewrite, and eval slices 1–3
- **Phase B:**
  - `deploy` Helm path
  - smoke scenario 7 (compute node)
  - eval slices 4–6

## Release

- Bump the dev package to `0.4.0`.
- Release notes in the top-level README. They cover: `migrate` and Cloud support are removed from this plugin; existing users run `/plugin marketplace update cyoda` (third-party marketplaces don't auto-update); stored tokens in the config are no longer read.
- Fix the README install command and all repo URLs to `Cyoda/cyoda-skills`.
- `GEMINI.md`: drop `migrate`. Note that Claude Code's ```` ```! ```` blocks don't execute under Gemini, so those skills say what to run instead.
