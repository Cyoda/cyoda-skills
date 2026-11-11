# Cyoda Skills for AI Coding Agents

[Cyoda](https://cyoda.org/) is an EDBMS that runs entity lifecycle management, state-machine workflows, event-driven processing, and transactional consistency as one integrated runtime.

This repository contains **Cyoda skills** — reusable instructions that teach your AI coding agent how to scaffold entities, define workflows, implement compute processors, and test your Cyoda application.

## Use Cyoda with your AI coding agent

### Claude Code (best supported)

Install via the Claude Code plugin marketplace:

```
/plugin marketplace add Cyoda/cyoda-skills
/plugin install cyoda@cyoda
/reload-plugins
```

Then describe what you want to build.

### Any agent

Point your agent to this repository and ask it to read the skill files before building:

> "Read the skills in https://github.com/Cyoda/cyoda-skills and use them to help me build a Cyoda application."

## Skills

| Skill | Purpose |
|---|---|
| `/cyoda:setup` | Install and start cyoda-go locally; connection status |
| `/cyoda:auth` | Get tokens for a self-hosted cyoda-go |
| `/cyoda:design` | Brainstorm entities and workflows for your app |
| `/cyoda:build` | Incrementally build and register entity models and workflows |
| `/cyoda:compute` | Implement compute node processors and criteria services via gRPC |
| `/cyoda:test` | Smoke-test your running Cyoda instance |
| `/cyoda:deploy` | Generate Docker Compose or Helm deploy artifacts with idempotent seed and verify scripts |
| `/cyoda:debug` | Diagnose failures and browse entity history |
| `/cyoda:docs` | Look up Cyoda documentation |

Skills are loaded by the agent and compose with your own process (e.g. superpowers).

## Connection config

The plugin keeps its connections in `~/.config/cyoda/cyoda-plugin-config.json`: machine-wide profiles (no tokens; a `tokenCommand` fetches a fresh one per call) and, under `projects`, per-project links. A local cyoda-go is the expected setup; the spike skills can use a throwaway in-memory one. `/cyoda:setup` can link a project directory to its own instance; inside it that link wins over the active profile, so several projects with their own cyoda-go stacks can be worked on at once. Nothing is written into the project. `CYODA_PROFILE=<name>` picks a machine-wide profile over both. Details: [cyoda/README.md](cyoda/README.md#connection-config).

## Versioning

The plugin's MAJOR.MINOR follows the cyoda-go release line it targets: plugin 0.8.x is written for cyoda-go 0.8.x, and its patch number counts the plugin's own revisions. `/cyoda:setup` warns when the instance (or, without one, the local `cyoda`) runs a different line.

## Release notes — 0.8.1

- Every skill can be used by the agent itself, not only typed; they compose with your own process (e.g. superpowers).
- `/cyoda:app` and `/cyoda:status` are gone; `/cyoda:setup` covers status.
- Local instances are per project, on automatic free ports.
- Run `/plugin marketplace update cyoda` to pick up this release.

## Release notes — 0.9.0 (unreleased, needs cyoda-go 0.9.0)

- Workflow best practices updated for cyoda-go 0.9.0: function conditions may nest (*Put the cheap test before the callout*), `idempotent: true` processors, scheduled-transition `timeoutMs` retries, `WORKFLOW_SKIP`.
- Run `/plugin marketplace update cyoda` to pick up this release.

## Release notes — 0.8.0

- Versions now follow cyoda-go (see Versioning): 0.8.0 is 0.5.0 renumbered for cyoda-go 0.8.4.
- `/cyoda:status` warns when your cyoda-go's MAJOR.MINOR differs from the plugin's.
- The workflow best practices are updated (44 practices with a review checklist); `design`, `build`, `debug` and `compute` cite them by name.
- Run `/plugin marketplace update cyoda` to pick up this release.

## Release notes — 0.5.0

- A local cyoda-go is the expected setup; `/cyoda:setup` starts and links a project's own Compose stack.
- `design`, `build`, `compute` and `debug` can offer a spike on a throwaway in-memory cyoda-go.
- Profiles and project links no longer have `env`, and the production guard (`--confirm-production`) is gone.
- Skills are trimmed to Cyoda-specific content.
- `debug` repairs a single entity (a loopback or a fired transition) without a confirmation round, and shows the call it made and the response.
- `deploy` asks which stage the deployment is for and whether its schema is strict, records a per-stage `changeLevel`, and no longer offers to write a profile for the new instance.
- Run `/plugin marketplace update cyoda` to pick up this release.

## Release notes — 0.4.0

- Cloud support and `migrate` are removed (parked; see `docs/history/cloud-skills.md`).
- Run `/plugin marketplace update cyoda` to pick up this release.
- Stored tokens in ~/.config/cyoda/cyoda-plugin-config.json are no longer read.
- New `deploy` skill.
- Skills with side effects now start only when you type them.

## Links

- [Cyoda docs](https://docs.cyoda.net/)