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

Then start building:

```
/cyoda:app
```

### Any agent

Point your agent to this repository and ask it to read the skill files before building:

> "Read the skills in https://github.com/Cyoda/cyoda-skills and use them to help me build a Cyoda application."

## Skills

| Skill | Purpose |
|---|---|
| `/cyoda:app` | Start here — walks the full build journey |
| `/cyoda:setup` | Install and start cyoda-go locally |
| `/cyoda:auth` | Get tokens for a self-hosted cyoda-go |
| `/cyoda:design` | Brainstorm entities and workflows for your app |
| `/cyoda:build` | Incrementally build and register entity models and workflows |
| `/cyoda:compute` | Implement compute node processors and criteria services via gRPC |
| `/cyoda:test` | Smoke-test your running Cyoda instance |
| `/cyoda:deploy` | Generate compose deploy artifacts with idempotent seed and verify scripts |
| `/cyoda:debug` | Diagnose failures and browse entity history |
| `/cyoda:docs` | Look up Cyoda documentation |
| `/cyoda:status` | Check connection status |

## Release notes — 0.4.0

- Cloud support and `migrate` are removed (parked; see `docs/history/cloud-skills.md`).
- Run `/plugin marketplace update cyoda` to pick up this release.
-X
- New `deploy` skill.
- Skills with side effects now start only when you type them.

## Links

- [Cyoda docs](https://docs.cyoda.net/)