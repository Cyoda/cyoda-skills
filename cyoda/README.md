# Cyoda Plugin for Claude Code

Helps you build applications on [Cyoda](https://docs.cyoda.net/) — an Entity Database Management System (EDBMS).

## Skills

| Skill | Purpose |
|---|---|
| `/cyoda:app` | Start here if you're new — walks the full journey |
| `/cyoda:setup` | Install cyoda-go locally or connect to Cyoda Cloud |
| `/cyoda:auth` | Authenticate to Cyoda Cloud (obtain JWT) |
| `/cyoda:design` | Brainstorm entities and workflows for your app |
| `/cyoda:build` | Incrementally build and register entity models and workflows |
| `/cyoda:compute` | Implement compute node processors via gRPC |
| `/cyoda:test` | Smoke-test your running Cyoda instance |
| `/cyoda:debug` | Diagnose failures and browse entity history |
| `/cyoda:migrate` | Lift-and-shift from local cyoda-go to Cyoda Cloud |
| `/cyoda:docs` | Look up Cyoda documentation |
| `/cyoda:status` | Check connection status |

## Connection Config

Skills share connection state via `~/.config/cyoda/cyoda-plugin-config.json` — a home-directory file that is never git-tracked:

```json
{
  "active": "default",
  "profiles": {
    "default": {
      "endpoint": "http://localhost:8080",
      "env": "development"
    },
    "prod": {
      "endpoint": "https://client-abc123-prod.eu.cyoda.net",
      "token": "eyJ...",
      "env": "production"
    }
  }
}
```

The `"active"` key controls which profile all skills use. `token` is absent for local cyoda-go (mock auth).

Run `/cyoda:setup` then `/cyoda:auth` to create a profile and set it as active.
