# Agent-Loaded Technique Skills, Parallel-Safe Local Instances

**Date:** 2026-11-11
**Status:** Draft, awaiting approval
**Supersedes:** the `disable-model-invocation` rule and the typed hand-offs of `2026-10-17-cyoda-go-split-and-help-first-design.md`, the `app` skill, and the setup parts of `2026-11-07-dev-package-local-first-design.md`. Everything else in those documents stands.

## Intent

An agent working on a cyoda-go app should never stop to ask the developer to type a command. Today six skills can only be started by the developer (`disable-model-invocation`), every skill ends with "next, type `/cyoda:<x>`", and `app` sequences the others. That stops unattended runs, fan-out, and process frameworks such as superpowers, whose flows (brainstorming, writing-plans, subagent-driven development, test-driven development, git worktrees) do the sequencing themselves and need focused know-how per step.

Agentic engineers also run several things at once, so each project (and each worktree) needs its own cyoda-go instance, found or started without colliding with other instances on the machine.

## Shape: technique skills, no process

| Skill | Trigger | Change |
|---|---|---|
| `design` | Modelling a domain as entities and workflows; reviewing a design | Ends with the design summary; no hand-off |
| `setup` | A cyoda-go instance is needed or asked about: start, find, link, which instance, connection problems | Absorbs `status`; gains discovery, the run question and parallel-safe ports (below) |
| `build` | Adding or changing a model or workflow on the instance | Without a usable instance, follows `setup`'s procedure itself, then continues |
| `test` | Smoke-testing models and workflows on the instance; a CI test script | Same as `build` for the instance |
| `auth` | Tokens: a 401/403, the app's token handling, local JWT mode | Model-invocable |
| `compute`, `debug`, `deploy`, `docs` | As today | Typed hand-offs removed |

Removed: `app` (sequencing belongs to the agent or the developer's process framework) and `status` (folded into `setup`).

## Rules for every skill

- No `disable-model-invocation`. `/cyoda:<skill>` keeps working for a developer who types it.
- A skill does its job and returns. It never tells the developer to type a command and never prescribes what comes after it.
- When a skill needs another skill's result to finish (an instance for `build`, a token for a 401), it carries out that part itself and continues; otherwise it names where the know-how lives ("`cyoda:setup` covers starting an instance").
- The agent asks only a domain gap in the requirement and, when the project doesn't define it, the run question. Everything else it decides, states in one line, and continues.
- `CLAUDE.md`'s side-effect rule is replaced by: every skill is loadable by the agent; the sandbox decides what the agent may do.

## Composition

- **Plain agent:** loads `design` for the model, `setup` when it needs an instance, `build` to register, `test` to check.
- **superpowers:** brainstorming draws on `design` (modelling questions, best-practice checklist) for the design doc; writing-plans breaks the work into tasks that each use one technique skill; a subagent executing "register Order v1" loads `build` (and, if no instance answers, carries out `setup`'s procedure), nothing else; test-driven development uses `test`'s recipe against the project's instance; each git worktree gets its own instance (identity below).

## The local instance (`setup`)

The scripts' resolution order stays as today (`CYODA_PROFILE`, the project's entry, the active profile, the implicit local default). Profiles, connecting to an endpoint the developer gives, and the non-mock auth paths stay.

1. **Already bound:** `CYODA_PROFILE`, the project's entry, or an explicitly active profile resolves and answers → use it.
2. **Defined by the project:** the repo says how it runs cyoda-go (a Compose file with a `ghcr.io/cyoda/cyoda` service, a Makefile or script target, README instructions) → start it that way if it isn't running, then bind it.
3. **Not defined:** ask once. When a cyoda-go already answers at the implicit `localhost:8080` and the project has no entry: "Use the cyoda-go already running on localhost:8080, or start one for this project from the command line or in Docker?" Otherwise: "Run cyoda-go for local development and testing from the command line or in Docker?" Then:
   - **Command line:** start `cyoda` for this project only, with mock auth, its own data and config dir outside the repo, a pid file there, and the ports below. `cyoda` always loads `~/.config/cyoda/cyoda.env`, so storage, auth and ports are set explicitly.
   - **Docker:** a Compose file rendered from the deploy single-user template into the project's data dir (the repo stays untouched), the project's instance name as Compose project name, the ports below.
   - **Storage, both modes:** in-memory by default; sqlite when the requirement needs data to survive a restart.
   Record the choice and the ports in the project's entry, so a later session restarts the same way on the same ports.

**Identity.** A project is its real path, so each git worktree and each clone is its own project. Its instance name, data dir (`~/.local/share/cyoda/projects/<instance name>`) and Compose project name are the directory's basename plus a short hash of the real path.

**Ports.** cyoda-go needs three: HTTP, gRPC, admin (`cyoda help run` PORT LAYOUT).
- A block is free when nothing listens on any of its three ports and no other project's entry has recorded it.
- Prefer the project's recorded block, then the default block (8080/9090/9091), then the next free block in a fixed sequence.
- A busy port is ours only with evidence: command line, the pid file in the project's data dir names a live process listening on that port; Docker, the listening container's Compose project is the project's instance name and its working-dir label is the project's data dir. Otherwise pick another block. Never stop another process or container.
- A stack the repo defines with fixed host ports or a fixed `name:` that clash: run it with a Compose override file in the project's data dir (free host ports, the instance name as `-p`), alongside the repo's file, and say so in one line. The repo's files stay unchanged.

Two scripts carry the mechanics, so every skill and spike gets the same answer: one picks a port block with ownership evidence, one starts and stops a project's instance in each mode.

## Evals

- `setup`: repo with a cyoda Compose stack, not running → started and bound, no question; nothing defined → the run question once, for each answer the instance starts on free ports and the choice is recorded; default ports busy with another listener → next block, the other untouched; this project's own instance running → reused; recorded entry → a new session restarts on the same ports; a cyoda-go at localhost:8080 and no entry → the question offers it; `status`'s cases migrated.
- `build` and `test`: no usable instance → carries out `setup`'s procedure and finishes the task, no typed command.
- Composition: a subagent-style task "register Order v1" given as a superpowers plan task → loads `build` (plus `setup`'s procedure if needed), completes the task, loads no unrelated cyoda skill.
- Every skill: hand-off and `no-invoke` assertions become "continues without asking the developer to type a command"; cases that only tested `app`'s sequencing are dropped.
- Script tests for both scripts (free, busy by ours via pid file, busy by another, recorded by another project, two projects in parallel, restart on the same ports, override for a fixed-port stack, path with spaces).

## Release

Plugin `0.8.1`. README release notes: every skill can now be used by the agent itself; `/cyoda:app` and `/cyoda:status` are gone (`/cyoda:setup` covers status); local instances are per project with automatic ports. `feat/cyoda-go-0.9.0` is rebased onto it afterwards.

## Left to the builder

The exact port sequence after the default block; the hash length; the project-entry fields for the run choice, ports and data dir; how the composition eval presents the superpowers context to the executor.
