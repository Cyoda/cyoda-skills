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

**Per-project binding.** When you work on several apps, each with its own cyoda-go (e.g. its own Docker Compose stack on its own ports), `/cyoda:setup` can link a project to its instance: it writes `<project>/.cyoda/instance.json` (`endpoint`, `env`, optional `tokenCommand`, which may be relative to the project root; never a token) and adds `.cyoda/` to `.gitignore`. Inside that project (searched from the working directory up to the git root, never `$HOME`) it wins over the active profile. The file is used only if it is yours, not writable by others and not tracked by git; otherwise it is ignored with a warning. Lookup order: `CYODA_PROFILE=<name>` (an explicit machine-wide profile), then the project file, then the active profile, then the local default `http://localhost:8080`.
