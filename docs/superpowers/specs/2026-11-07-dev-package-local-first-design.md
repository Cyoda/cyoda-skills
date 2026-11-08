# Cyoda Dev Package: Development Only, Local First

**Date:** 2026-11-07
**Status:** Draft, awaiting approval
**Supersedes:** in `2026-10-17-cyoda-go-split-and-help-first-design.md`, everything about remote instances, the `env` field and the production guard (`setup` connect mode, `deploy` Step 7, `auth` against a team instance, the `[PRODUCTION]` tag). The rest of that document stands.

## Intent

The `cyoda` plugin is for **developing** cyoda-go applications. Today it also reaches into environments it has no business in: it can connect to a remote "team" or "production" instance, build and test against it, debug it, create machine clients on it, and add a profile for a freshly deployed server. That is the Cyoda Cloud working model (a hosted dev/prod pair the developer talks to directly), carried over after Cloud was parked.

Software delivery has three separate worlds:

1. **Development.** The developer and their agent, on their own machine, against their own local cyoda-go. They produce artifacts: entity and workflow files, application code, compute nodes, tests, and the deployment files and scripts the pipeline uses.
2. **CI/CD.** The team's pipeline takes those artifacts and promotes them through the controlled stages (integration, UAT, production, or whatever the team calls them), under the team's change control. No skill takes part in this.
3. **Support in controlled environments.** Read-mostly diagnosis under the organisation's access rules; any fix is a proposed change that goes through their process. That is a separate package, designed another day.

This work makes the plugin **development only**, and **local first**: a local cyoda-go is part of the development process. It also adds **spikes**, for the exceptional cases where trying something live settles a question faster than reading.

## Guidance, not gates

Skills guide the agent; they don't protect anything. What a coding agent can touch (files, network, installing software, Docker) is decided by the sandbox and the harness's permissions, not by a skill's wording. So:

- The skills don't add confirmation steps for safety's sake. API calls to the local instance, reads and writes, are ordinary development work for any skill and for the agent itself; writing to, deleting from or throwing away the local instance is part of developing.
- The questions that remain are workflow questions the developer should decide: running a spike (it costs time and starts throwaway instances), and the existing content choices (what to build, which entity, which version).
- **Unsandboxed sessions.** When the agent can tell it is running with permission checks bypassed ("yolo" mode, e.g. `--dangerously-skip-permissions`), `app` and `setup` say once, at the start: "This session runs without permission checks. The Cyoda skills assume the session runs in a sandbox that limits what the agent can reach." Then they carry on. Nothing else depends on the mode.
- `disable-model-invocation: true` is a workflow choice (which skills the developer starts deliberately), not a safety boundary. `CLAUDE.md`'s side-effect rule is reworded to say so: typed-only skills are the ones whose main job is doing work for the developer (`setup`, `build`, `test`, `app`, `deploy`, `auth`); the skills that start on their own (`design`, `compute`, `debug`, `docs`, `status`) read and advise, and may also call the local instance and run a spike after the developer says yes to it.
- The plugin still keeps secrets out of files, argv and the conversation, and keeps its config private (0600). That is data hygiene, not a gate on the agent.

## Goals

- The dev package talks only to cyoda-go instances on the developer's own machine (the local binary, or a container published on loopback). Nothing in it connects to, builds on, tests on, debugs or deploys to an integration, UAT or production stage, or any other remote instance.
- A local cyoda-go is a **prerequisite** from `build` onward (`build`, `test`, `compute`, `debug`), and **strongly encouraged** during `design` (and `app`'s design step) and in `docs`.
- `cyoda help` stays the primary and trusted source of platform facts. Nothing added here suggests otherwise.
- The agent can **spike**: in a complex case that help alone doesn't settle, it offers to try the thing on a throwaway local instance, and does so only after the developer says yes.
- No Cyoda Cloud remnant is left in the dev package's skills, scripts or evals.

## Non-goals

- The support package for controlled environments (later, separately).
- Changing `deploy`'s artifacts (Compose files, Helm values, `seed.sh`, `verify.sh`, secrets checklist) beyond the removals listed below. They stay as building blocks for the team's pipeline.
- Fixing docs.cyoda.net. Issues may still be filed in `Cyoda/cyoda-docs`, but no skill or script waits on one being fixed.

## Anti-goals: failing even if it technically works

- Any wording that makes an agent doubt `cyoda help` ("help may be wrong, verify live"). Spikes are for complex combinations help can't settle by reading, not a check on help.
- Spikes as a default step. A skill's normal flow never runs one, and the agent never starts one without asking.
- A dev skill that writes to, or offers to connect to, an instance that isn't on the developer's machine.
- A skill that runs `docker`, `helm`, `kubectl` or the pipeline against anything but a throwaway spike or the developer's own local stack.
- Skills written as if they were safety gates (confirmation ceremonies, "never do X" as protection). Protection is the sandbox's job.

## Constraints

Repo rules from `CLAUDE.md` apply as before: `SKILL.md` under 500 lines, no embedded Cyoda docs, `disable-model-invocation: true` on side-effect skills, 3+ evals per skill, `superpowers:writing-skills` before editing a skill, the eval process in `CLAUDE.md`. Target stays cyoda-go v0.8.4.

## Decisions made with the user

- Develop locally, test remotely: remote stages exist, but they belong to CI/CD and support, never to the dev package. Even when remote stages exist, a local cyoda-go is part of the development process.
- Strict segregation of development from CI/CD and from operations. "Nobody will ever use a cyoda skill to deploy anything to production."
- Local cyoda-go: prerequisite beyond design; strongly encouraged at design.
- Spikes: only for exceptional, complex scenarios; the agent asks first; the agent decides between an in-memory instance on the command line (default) and a full stack in Docker (when, say, the Postgres plugin is the target, and Docker is available).
- `cyoda help` is never put in doubt.
- Web help mirror: its known differences are pointed out (or handled by the helper), and the skills never depend on a cyoda-docs fix.
- Support for controlled environments: another day, another package.
- Skills are guidance, not gates; the sandbox defines what an agent can do. At most, a skill points out that the session isn't sandboxed.
- An agent with the skills loaded calls the local instance's API freely.

## The local-only boundary

### What counts as local

An endpoint is local when its host is `localhost`, an address in `127.0.0.0/8`, or `::1` (any port). This covers the local binary and Docker containers published on loopback (the per-project link case: several projects, each with its own Compose stack on its own ports).

**Builder's call, flagged for review:** dev setups where cyoda-go runs on another host the developer owns (a devcontainer sibling reached by service name, a remote dev VM) are not local by this rule. If they matter, an explicit per-machine allow-list in the plugin config (e.g. `localHosts: ["cyoda"]`) is the escape hatch, not a per-call flag. Only add it if the user asks.

### Where it is checked

In the scripts, so every skill gets the same answer. This is a scope signal (a stale remote profile or a copied project link can't quietly become the target), not security: the sandbox decides what the agent can reach.

- `cyoda-profile.sh` resolves as today (`CYODA_PROFILE`, project link, active profile, implicit `http://localhost:8080`) and adds `local: true|false` to its output.
- `cyoda-call.sh` refuses any call to a non-local endpoint: new exit code `7`, stderr `not a local cyoda-go: <endpoint>. The cyoda dev plugin works with instances on this machine only.` No override flag.
- `cyoda-status.sh` reports a non-local binding without contacting it (builder's call): `STATUS=not_local`, with `ENDPOINT=` and `SOURCE=` filled so the developer sees what's configured, `VERSION=none`, and `WARN=<profile|project> points at <endpoint>, which isn't on this machine; the dev plugin only works with local instances. Type /cyoda:setup to switch to a local one.` Skills key on `STATUS=not_local` (a new value), not on the warning text.
- `cyoda-help.sh` uses the bound instance's help only when it's local; otherwise it goes straight to the binary, then the web mirror.
- `cyoda-config-write.sh` is unchanged (it writes what a skill tells it); `setup` only ever writes local endpoints.

### What goes

| Where | Removed |
|---|---|
| All skills | The "Cloud, hosted offerings or migration: reply only 'That's not covered by this plugin.'" lines (8 skills) and their eval assertions. Cloud no longer exists, and the line catches legitimate questions ("we host on AWS, how do we deploy?") |
| Config model | The `env` field (`development` / `production`) on profiles and project entries. Existing values are ignored, never written |
| `cyoda-call.sh` | `--confirm-production` and exit `3` |
| `cyoda-status.sh` | `ENV=` in the status line |
| `setup` | Connect mode (adding a profile for an instance running elsewhere), and the development/production question |
| `status` | The `[PRODUCTION]` tag |
| `build`, `test`, `debug` | Production guards and their questions |
| `app` | "A `[PRODUCTION]` profile: suggest a development instance" (replaced by the local prerequisite) |
| `deploy` | Step 7 (adding a profile for the new instance), the hand-off to `/cyoda:auth` for a deployed instance's credentials, "Is this instance production?" as a plugin-level question |
| `auth` | Setting up tokens for, and creating machine clients on, a remote instance |

### What stays, reshaped

- **Profiles** stay, for local instances only (e.g. a second local instance on other ports). `default` is the local `http://localhost:8080`.
- **Per-project link** stays unchanged; it is the main way several local stacks coexist.
- **`deploy`** writes the same artifacts, as building blocks for the team's pipeline. One run targets one deployment kind (shared Compose or Helm), with one `compose.yaml` or `values.yaml`; only the schema setting and the seed/verify inputs vary per stage. Its hand-over (Step 6) stops being commands for a person to run against a server and becomes "what your pipeline runs, per stage": for each stage the team named, the seed and verify step with its inputs (`CYODA_ENDPOINT`, the token source, `--env <stage>`), for the devops person to wire into their pipeline (builder's call). Its per-environment schema setting stays as artifact content: the stage names come from the team (asked, or read from the repo), and the "does any processor write fields that aren't in the sample? A strict schema rejects them" question is asked for each stage the team marks as strict, not for a built-in "production". `seed.sh --env <stage>` picks the stage's settings. `deploy`'s single-user Compose stays: it is a local stack for the developer's own machine (e.g. cyoda-go with Postgres in Docker).
- **`test`**'s CI script stays: the skill writes it; the pipeline runs it with the pipeline's own endpoint and credentials (`CYODA_ENDPOINT`, `CYODA_TOKEN_COMMAND`). The skill itself runs tests only against the local instance.
- **`auth`** shrinks to development concerns (builder's calls):
  - (a) **The app's own token handling.** The agent writes the code in the developer's application that obtains and renews cyoda-go tokens (help-first: `auth tokens`, `auth clients`), in the project's language, with no per-language templates: it reads help and writes the code, as `compute` does for nodes. Credentials come from the app's environment, never from a file the skill writes.
  - (b) **JWT mode locally.** To exercise that path, the developer's own local instance (the `default` binary, or the project's linked stack) is switched to JWT mode: `auth` reads `config auth` (JWT mode, bootstrap M2M client) and gives the exact settings. Restarting the instance with them is the developer's step for the binary, or `setup`'s for a linked stack (see the decision on starting stacks). `auth` then writes the token script and sets `tokenCommand` on that same binding (`default` or the project entry), as today. No second instance, no new `setup` mode.
- **`debug`** works on the local instance only. Its "show the exact call and ask before changing one entity" rule goes: on the developer's own local instance a repair (loopback, firing a transition, a delete) is ordinary development work. It still shows what it did.

## Local first

### `setup`

Local mode stays as today (install via Homebrew or the documented alternatives, `cyoda init`, start, verify, profile `default`). Link mode stays. Two additions:

- **How does this project run cyoda-go?** Before offering modes, read what the repo says: README and `docs/`, Compose files, Makefile targets, `.env.example`, `deploy/` or `ops/`. If the project already has its own local stack (e.g. `make up` starting a Compose project with cyoda-go on port 8082), start it if it isn't running (the way the repo says: the `make` target or `docker compose up -d`) and link it (the existing Docker discovery helps find the container). If not, use local mode. Ask only about what the repo leaves unclear.
- A remote endpoint is never written. If the developer asks to connect to a remote instance, say in one line that the dev plugin works with a local cyoda-go, and continue with local or link mode.

### Prerequisite from `build` onward

`build`, `test`, `compute` (when it touches an instance) and `debug` start with `cyoda-status.sh`. Unless it reports `STATUS=connected` on a local binding, they stop and say "next, type `/cyoda:setup` to start (or link) a local cyoda-go", with a one-line reason: building means running, and the agent needs a local instance to register, run and check what it builds.

`app`'s journey becomes **design → local cyoda-go → build → test → iterate → deploy files (optional)**, with the local step required before build.

### Encouraged at design and in docs

- `design` keeps working without an instance or binary, but its opening says, once, that a local cyoda-go is strongly recommended now: lookups then come from the matching binary, and complex questions can be spiked. "Next, type `/cyoda:setup`" as the hand-off when the binary is missing. Replace "so it works without an instance and without the binary" with this.
- `docs`, binary missing: answer from the web mirror, and say once that a local cyoda-go is recommended, with the mirror's differences where they matter to the answer (below).

### The web help mirror

The helper already falls back to `https://docs.cyoda.net/help/` when there's no local binary or instance. Its known differences are documented in `docs` (and referenced where relevant), not worked around by waiting on cyoda-docs:

- Whole pages only: `--section` is ignored, so the agent finds the section by its heading.
- No actions: `cloudevents json`, `grpc proto`, `openapi …`, `workflows schema-version versions` exit 2.
- Sub-topic pages live under lowercase paths (`errors/workflow_schema_version_unsupported.md`); `cyoda-help.sh` already retries lowercase (shipped in `7ea25b7`).
- Version: the mirror's `index.json` version, which may differ from the binary the project will run.

## Spikes

A short shared guide, `cyoda/resources/spikes.md`, referenced from `design`, `build`, `compute` and `debug` (and from `docs` for questions about behaviour across features). Content:

- **When.** A complex scenario where reading help doesn't settle how things behave together: e.g. a workflow combining a scheduled transition, a function criterion and a processor in `COMMIT_BEFORE_DISPATCH`; concurrency on one entity; a migration between model versions. Not for single facts help states.
- **Ask first.** "This is hard to settle from help alone. Shall I spike it on a throwaway local instance? (yes/no)". No spike without a yes.
- **Help first, then spike.** Read the relevant help sections before proposing the spike, and design the spike from them. A spike shows how a specific combination behaves; it doesn't replace help.
- **Which instance.** The agent decides:
  - In-memory, mock auth, on the command line (the default): `cyoda` with in-memory storage and mock auth on free ports and its own temporary data and config dirs, read from `cyoda help run` and `cyoda help config`.
  - A full stack in Docker, when the question depends on it and Docker is available: e.g. the Postgres storage plugin, or a compute node in a container. Built from `cyoda help run` (Docker) and `deploy`'s Compose template, under a throwaway Compose project name.
- **Never the project's instance.** (So the spike's results aren't mixed with the developer's data, not for safety.) A spike never uses the project's linked or default instance; it gets its own ports and its own data.
- **Throwaway.** Always torn down at the end, also when the spike fails: stop the process or `docker compose down -v`, and remove its temporary dirs.
- **Report.** In a line or two, what was tried and what came back, e.g. "Spiked: criterion on a missing field → the transition stays in `submitted`, no error." Then carry the finding into the design or code. If a spike contradicts help, say so plainly and add it to the consolidated help issue (Cyoda/cyoda-go#684), as with any help defect.

Skills that may offer a spike (`design`, `build`, `compute`, `debug`, `docs`) list the commands it needs in `allowed-tools` (`cyoda *`, `docker compose *`, `kill`, `rm -rf` of the spike's own temp dir); they stay as they are with respect to `disable-model-invocation` (see "Guidance, not gates"). A helper script to start and stop an in-memory spike instance is allowed if it makes teardown more reliable; that's the builder's call.

## Evals

Rework, keeping 3+ cases per skill:

- **Drop or rewrite cases built on remote or production instances:** `setup` 3 (connect to a team dev instance), `test` 2, 3, 5 (remote dev, production, `prod-ci`), `build` 6 (production), `auth` 1, 3, 4 (`team-dev`), `debug` 6 and `status` 2 (unreachable `staging`), any `status` case showing `[PRODUCTION]`. Rewrites keep the behaviour under test where it still applies locally (a 401 on a local JWT instance, an unreachable local instance, a project linked to its own Compose stack).
- **New cases:**
  - a skill refusing a non-local binding (e.g. `build` with a project linked to `https://cyoda-uat.example.com`: stops and hands off to `/cyoda:setup`; `cyoda-call.sh` exit 7 in the transcript);
  - `setup` asked to connect to a remote instance (declines in one line, offers local or link);
  - `setup` discovering the project's own Compose stack from the repo (README/Makefile) and linking it;
  - `design` with no binary (designs, and recommends installing once);
  - a spike offer: a complex combination in `design` or `build` where the agent asks before spiking, and a case where the developer says no and the agent carries on from help;
  - a spike run (yes), in-memory, torn down at the end;
  - `deploy` with team stage names (`int`, `uat`, `prod`, `prod` marked strict).
  - `setup` in a session running with permission checks bypassed (says the one-line sandbox note, then carries on);
  - `debug` repairing an entity on the local instance without a confirmation round.
- **Remove** every Cloud assertion ("doesn't mention Cyoda Cloud", "not covered by this plugin").
- `app` 3 ("get it onto a server for my team — or move to Cyoda Cloud?") becomes: hands off to `deploy` for pipeline artifacts, says nothing about Cloud.

Run them as before, in slices, with token cost reported.

## Smoke tests and script tests

- Script tests: locality detection (localhost, 127.x, ::1, a hostname, an IPv6 non-loopback), `cyoda-call.sh` exit 7, the status warning, `cyoda-help.sh` skipping a non-local instance, `--confirm-production` gone (usage error), `env` ignored in old configs.
- Smoke scenarios: unchanged where they use the local in-memory instance; drop any that exercise the production guard.
- Lint: add stale strings (`--confirm-production`, `[PRODUCTION]`, `not covered by this plugin`, `connect mode`).

## Docs

- `README.md`, `cyoda/README.md`, `CLAUDE.md`: the plugin is development only; local first; spikes; config without `env`; remote instances are out of scope (support is a separate future package).
- The 2026-10-17 spec gets a pointer at the top to this one for the superseded parts.
- Release as `0.5.0` (breaking: connect mode and the production guard are gone; non-local bindings are refused).

## What's left to the builder

- Exact wording of the local-first prompts and the spike offer, within the rules above.
- Whether to add a spike helper script.
- How `setup` reads the repo (which files, in what order), within the list above.
- Which existing eval cases are rewritten versus replaced, as long as the coverage above exists.
- Task order, as long as scripts (the boundary) land before the skills that rely on exit 7.
