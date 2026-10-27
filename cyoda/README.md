# Cyoda Plugin for Claude Code

Helps you build applications on [Cyoda](https://docs.cyoda.net/) — an Entity Database Management System (EDBMS).

## Skills

| Skill | Purpose |
|---|---|
| `/cyoda:app` | Start here if you're new — walks the full journey |
| `/cyoda:setup` | Install and start cyoda-go locally |
| `/cyoda:auth` | Get tokens for a self-hosted cyoda-go |
| `/cyoda:design` | Brainstorm entities and workflows for your app |
| `/cyoda:build` | Incrementally build and register entity models and workflows |
| `/cyoda:compute` | Implement compute node processors via gRPC |
| `/cyoda:test` | Smoke-test your running Cyoda instance |
| `/cyoda:debug` | Diagnose failures and browse entity history |
| `/cyoda:deploy` | Write the files to deploy and seed a self-hosted cyoda-go (Docker Compose, Helm) |
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
    }
  }
}
```

The `"active"` key controls which profile all skills use. No token or secret is ever stored: a profile on an instance with auth enabled has a `tokenCommand`, a command (usually the project's `get-token.sh` from `/cyoda:auth`) that the plugin's scripts run before each API call to get a fresh JWT. It reads the client credentials from your own environment or keychain.

Run `/cyoda:setup` then `/cyoda:auth` to create a profile and set it as active.

**Per-project binding.** When you work on several apps, each with its own cyoda-go (e.g. its own Docker Compose stack on its own ports), `/cyoda:setup` can link a project directory to its instance. The link is an entry in the same config file, under `projects`, keyed by the directory's real path, so it stays private to you and nothing is written into the project: `"projects": {"/Users/you/dev/shop": {"endpoint": "http://localhost:8082", "env": "development", "tokenCommand": "scripts/auth.sh token"}}` (a relative `tokenCommand` runs from the project dir; never a token). Inside that directory or below it, the nearest linked directory wins over the active profile. Lookup order: `CYODA_PROFILE=<name>` (an explicit machine-wide profile), then the project entry, then the active profile, then the local default `http://localhost:8080`. `/cyoda:setup` also unlinks a project.
