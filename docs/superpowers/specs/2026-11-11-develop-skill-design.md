# One `develop` Skill, Agent-Driven, Parallel-Safe

**Date:** 2026-11-11
**Status:** Draft, awaiting approval
**Supersedes:** the skill split and the `disable-model-invocation` rule of `2026-10-17-cyoda-go-split-and-help-first-design.md`, and the setup/app parts of `2026-11-07-dev-package-local-first-design.md`. Everything else in those documents stands.

## Intent

An agent given a requirement should go from requirement to a registered, tested cyoda-go app without a developer typing commands between steps. Today the loop is split into `app`, `design`, `setup`, `build`, `test` and `status`. Five of them are developer-typed only, and each ends with "next, type `/cyoda:<x>`", which stops every unattended or fanned-out run. Agentic engineers also run several things at once, so each project needs its own cyoda-go instance, found or started without colliding with others on the same machine.

## Skills after the change

| Skill | Trigger | Content |
|---|---|---|
| `develop` | Building or changing a cyoda-go app: a requirement, an entity, a workflow, "register", "test" | The loop: local instance → design → project files → register → test → iterate. Resources hold each step's detail (below) |
| `debug` | An error, a stuck or missing entity, history, audit | Unchanged apart from hand-offs |
| `compute` | Code a workflow calls: processor, function criterion, schedule function | Gains the node's token handling from `auth` |
| `deploy` | Deployment files for the team's pipeline | Unchanged apart from hand-offs |
| `docs` | A question about cyoda-go that isn't a task | Unchanged apart from hand-offs |

Removed: `app`, `design`, `setup`, `build`, `test`, `status`, `auth`. Their Cyoda-specific content moves into `develop` and its resources (or `compute` for the node's tokens); generic content is not carried over.

`develop` resources (loaded when that step comes up):
- `instance.md`: discovery, the run choice, starting and linking, ports (below); local JWT mode and the token script (from `auth`).
- `design.md` plus the existing `best-practices.md`, `patterns.md`, `design-guidelines.md`: the domain questions, the review against the checklist, the design summary.
- `register.md`: project files, manifest, version decision, canonical order, the call-failure table.
- `test.md`: the smoke test and its clean-up, the CI script.
- The existing templates and examples move with them.

## Rules for every skill

- No `disable-model-invocation`. Every skill can be loaded by the agent; `/cyoda:<skill>` still works for a developer who wants it.
- A skill continues into the next one itself ("continue with the `cyoda:<skill>` skill"); no "next, type …".
- The agent asks only what it can't decide: a domain gap in the requirement, and the run choice when the project doesn't define it. Everything else it decides, states in one line, and continues.
- `CLAUDE.md`'s side-effect rule is replaced by: skills are loaded by the agent; the sandbox decides what the agent may do.

## The local instance (`develop`, step 1)

Each project uses its own cyoda-go instance. The scripts' resolution order stays as today (`CYODA_PROFILE`, the project's entry, the active profile, the implicit local default). Profiles and connecting to an endpoint the developer gives stay (`2026-11-07` spec), and so do the non-mock auth paths (M2M client, OIDC, trusted key) in `instance.md`. Step 1 then runs:

1. **Already bound:** `CYODA_PROFILE`, the project's entry, or an explicitly active profile resolves and answers → use it.
2. **Defined by the project:** the repo says how it runs cyoda-go (a Compose file with a `ghcr.io/cyoda/cyoda` service, a Makefile or script target, README instructions). Start it the way the repo says if it isn't running, then bind it.
3. **Not defined:** ask once. When a cyoda-go already answers at the implicit `localhost:8080` (an earlier machine-wide setup that may hold this project's models), the question offers it too: "Use the cyoda-go already running on localhost:8080, or start one for this project from the command line or in Docker?" Otherwise: "Run cyoda-go for local development and testing from the command line or in Docker?" Then:
   - **Command line:** start `cyoda` for this project only, with mock auth, its own data and config dir outside the repo, a pid file there, and the ports below. `cyoda` always loads `~/.config/cyoda/cyoda.env`, so set storage, auth and ports explicitly.
   - **Docker:** write a Compose file for the project from the deploy single-user template into the project's data dir (outside the repo; the repo stays untouched), with the project's instance name as the Compose project name and the ports below, and start it.
   - **Storage, both modes:** in-memory by default; sqlite when the requirement needs data to survive a restart.
   Record the choice and the ports in the project's entry, so a later session restarts the same way on the same ports.

**Identity.** A project is its real path (as today), so each git worktree and each clone is its own project. Its instance name, data dir (`~/.local/share/cyoda/projects/<instance name>`) and Compose project name are the directory's basename plus a short hash of the real path, so two checkouts with the same basename never share or mistake each other's instance.

**Ports.** cyoda-go needs three: HTTP, gRPC, admin (`cyoda help run` PORT LAYOUT). Several instances may run on one machine.
- A block is free when nothing listens on any of its three ports and no other project's entry has recorded it.
- Prefer the project's recorded block. Otherwise try the default block (8080/9090/9091), then the next free block in a fixed sequence.
- A busy port is ours only when the evidence says so: command line, the pid file in the project's data dir names a live process listening on that port; Docker, the listening container's Compose project is the project's instance name and its working-dir label is the project's data dir or root. Otherwise pick another block. Never stop another process or container.
- **A stack the repo defines (step 2) with fixed host ports or a fixed `name:` that clash:** run it with a Compose override file in the project's data dir (free host ports, the project's instance name as `-p`), passed with `-f` alongside the repo's file, and say so in one line. The repo's files stay unchanged.
- A helper script does the probing and picking (`cyoda-ports.sh`), so every skill gets the same answer; spikes use it too.
- Changing the project's ports updates its entry; a compute node or app config that holds the old endpoint is updated by the agent in the same step.

## The loop

- A design-only request ("how should I model X", "review this design") ends with the design summary and starts no instance; recommend installing cyoda-go once if it's missing.
- A request to build runs the whole loop. The design summary is shown and the agent continues into registering without waiting for approval; the developer can interrupt. The local instance is resolved before the first registration, not before design.

## Evals

Rewritten around outcomes, under `develop` where the old skills folded in:
- Requirement → registered and tested app, no developer turn between steps (real server).
- Repo with a cyoda Compose stack, not running → started and bound, no question asked.
- Repo with nothing defined → asks command line or Docker once; for each answer, the instance starts on free ports and the choice is recorded.
- Default ports busy with another project's instance → picks another block, binds it, leaves the other untouched.
- Busy ports that are this project's own instance → reuses it.
- Recorded entry → a new session restarts on the same ports.
- A stopped project's recorded block is not taken by another project; a busy port with another project's pid or container is not treated as ours.
- Two checkouts with the same basename get different instance names.
- A repo-defined stack with clashing fixed ports → started with an override file outside the repo on free ports.
- A cyoda-go already at localhost:8080 with no project entry → the one question offers it.
- A design-only request → design summary, no instance started.
- A 401 in the loop → local JWT path from `instance.md`, no hand-off to a typed command.
- Existing design, build and test cases are kept as `develop` cases where the behaviour survives; hand-off and `no-invoke` assertions are replaced by "continues with the next step".
- `debug`, `compute`, `deploy`, `docs`: hand-off assertions updated.
- Script tests for `cyoda-ports.sh` (free, busy by ours via pid file, busy by another, recorded by another project, override for a fixed-port stack).

## Release

Plugin `0.8.1` (same cyoda-go line). README release notes: the typed commands `/cyoda:app`, `/cyoda:design`, `/cyoda:setup`, `/cyoda:build`, `/cyoda:test`, `/cyoda:status`, `/cyoda:auth` are gone; `/cyoda:develop` replaces them. `feat/cyoda-go-0.9.0` is rebased onto it afterwards.

## Left to the builder

The exact port sequence after the default block; the hash length; the project-entry fields for the run choice, ports and data dir; file names of the `develop` resources; which existing eval cases survive as `develop` cases versus being replaced.
