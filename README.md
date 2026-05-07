# Cyoda Skills for AI Coding Agents

[Cyoda](https://cyoda.org/) is an EDBMS that runs entity lifecycle management, state-machine workflows, event-driven processing, and transactional consistency as one integrated runtime.

This repository contains **Cyoda skills** — reusable instructions that teach your AI coding agent how to scaffold entities, define workflows, implement compute processors, and test your Cyoda application.

## Use Cyoda with your AI coding agent

### Claude Code (best supported)

Install via the Claude Code plugin marketplace:

```
/plugin marketplace add Cyoda-platform/cyoda-skills
/plugin install cyoda@cyoda
/reload-plugins
```

Then start building:

```
/cyoda:app
```

### Any agent

Point your agent to this repository and ask it to read the skill files before building:

> "Read the skills in https://github.com/Cyoda-platform/cyoda-skills and use them to help me build a Cyoda application."

## Skills

| Skill | Purpose |
|---|---|
| `/cyoda:app` | Start here — walks the full build journey |
| `/cyoda:setup` | Install cyoda-go locally or connect to Cyoda Cloud |
| `/cyoda:auth` | Authenticate to Cyoda Cloud (obtain JWT) |
| `/cyoda:design` | Brainstorm entities and workflows for your app |
| `/cyoda:build` | Incrementally build and register entity models and workflows |
| `/cyoda:compute` | Implement compute node processors and criteria services via gRPC |
| `/cyoda:test` | Smoke-test your running Cyoda instance |
| `/cyoda:debug` | Diagnose failures and browse entity history |
| `/cyoda:migrate` | Lift-and-shift from local cyoda-go to Cyoda Cloud |
| `/cyoda:docs` | Look up Cyoda documentation |
| `/cyoda:status` | Check connection status |

## Links

- [Cyoda docs](https://docs.cyoda.net/)