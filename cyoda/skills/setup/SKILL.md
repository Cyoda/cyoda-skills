---
name: setup
description: Use when the developer types /cyoda:setup to install and start a local cyoda-go, to connect the plugin to an existing self-hosted cyoda-go instance, or to switch away from an unreachable or outdated connection profile.
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-help.sh *) Bash(brew *) Bash(cyoda *) Bash(command -v *) Bash(curl *) Bash(mkdir *) Bash(jq *) Bash(mv *) Bash(cat *) Bash(sleep *)
disable-model-invocation: true
---

# Cyoda setup

Two modes: **local** (install and run cyoda-go on this machine, profile `default`) and **connect** (add a profile for a cyoda-go instance that already runs somewhere, e.g. one made with `/cyoda:deploy`). The result is a profile in the plugin config that every other skill reads.

**Facts come from `cyoda help`.** Read sections with `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` once the binary is installed (before that, the help mirror at https://docs.cyoda.net/help/ has the same content).

**The plugin stores no tokens or secrets.** A profile holds only `endpoint`, `env` (`development` | `production`) and, added later by `/cyoda:auth`, `tokenCommand`.

## Step 0 — Where things stand

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. It prints `STATUS=… PROFILE=… ENDPOINT=… ENV=… VERSION=… BINARY_VERSION=…` and then `WARN=` lines.

- Show every `WARN=` line as it is, e.g. "profile old contains a stored token, which this plugin no longer reads; you can remove it". Don't read, print or reuse a stored token. Remove it only if the developer says yes: `jq 'del(.profiles["<P>"].token)'` (write it back as in [Write the profile](#write-the-profile)).
- `WARN=no saved profile; …`: there is no config file, so the scripts used the local default `http://localhost:8080`. Unless the request says connect: `STATUS=connected` means a local cyoda-go already answers, so go to local mode to save it as `default` (its checks skip what's done); `STATUS=unreachable` (`WARN=no cyoda-go is answering at …`) means nothing runs locally yet, so go to local mode.
- `STATUS=unreachable` for a saved profile: offer to switch the active profile to `default`: on a yes, `jq '.active = "default"'` (written back the same way), leaving the unreachable profile in place, then go to [Finish](#finish). If `default` doesn't exist or isn't running either, continue with local mode.
- Otherwise ask which mode, unless the request already says: "Run cyoda-go **locally**, or **connect** to an instance that already runs elsewhere?"

A Cloud or migration question: say only "That's not covered by this plugin." and continue. Don't name or describe the product or offer alternatives for it.

## Local mode

1. **Installed?** `command -v cyoda && cyoda --version`. If it prints a version, skip to step 3.
2. **Install:** run `brew install cyoda/cyoda-go/cyoda`.

   If it fails in any way (non-zero exit, permission error, no Homebrew): don't diagnose or fix Homebrew, don't run `brew doctor`, `sudo`, `chmod` or `chown`, and add nothing to the message below. Show it **verbatim**, then wait until the developer says it's done:

   > I couldn't complete the installation — this usually needs to run in your own terminal. Please run this and let me know when it's done:
   > ```bash
   > brew install cyoda/cyoda-go/cyoda
   > ```
   > Other ways to install cyoda-go:
   > - Homebrew: `brew install cyoda/cyoda-go/cyoda`
   > - Install script: `curl -fsSL https://github.com/cyoda/cyoda-go/releases/latest/download/install.sh | sh`
   > - Release binaries: https://github.com/cyoda/cyoda-go/releases
   > - Docker image: `ghcr.io/cyoda/cyoda` (run recipe: https://docs.cyoda.net/help/run.md, RUN MODES → Docker)

   <!-- #684-K workaround: `cyoda help` has no install section yet. Remove this list and point to the help topic once Cyoda/cyoda-go#684 item K ships. -->

   After the developer confirms, check again with `cyoda --version`.
3. **Initialise (first time only):** run `cyoda init`. If it says a user config already exists, keep it: don't pass `-force`. Read `cyoda help run --section "RUN MODES"` (Binary) and `cyoda help quickstart --section DEFAULTS` to tell the developer, in one or two lines, what `init` set up and where the data lives.
4. **Start:** if `curl -s --max-time 2 http://localhost:8080/api/health` already returns `{"status":"UP"}`, skip this step. Otherwise start `cyoda` as a background process (the Bash tool's background mode). If the developer wants it to outlive this session, ask them to run `cyoda` in their own terminal instead. If it exits at once, show its last output. For a port clash, read `cyoda help run --section "PORT LAYOUT"`.
5. **Verify:** poll `curl -s --max-time 2 http://localhost:8080/api/health` every second for up to 15 s until it returns `{"status":"UP"}`. The health check is `/api/health` on the API port (`cyoda help run --section "HEALTH PROBES"`).
6. **Profile:** [write](#write-the-profile) `default` = `{"endpoint": "http://localhost:8080", "env": "development"}` and make it active. A local `default` runs mock auth, so it gets no `tokenCommand`.
7. **Report:** go to [Finish](#finish). Add: "Mock auth is active, so no token is needed and you don't need `/cyoda:auth` for this instance."

## Connect mode

1. **Endpoint:** ask for the instance's base URL. Strip a trailing `/` and a trailing `/api`: the profile stores `https://host[:port]`, and the scripts add `/api`.
2. **Probe:** `curl -sS --max-time 5 "<endpoint>/api/health"`. Anything other than `{"status":"UP"}`: show what came back (or the curl error), say the instance isn't reachable or isn't ready, and stop. Write no profile for an endpoint that doesn't answer.
3. **Environment:** ask "Is this a **development** or **production** instance?" For production, say: "I'll mark it `production`. Skills will then ask before every call that changes data on it."
4. **Profile name:** list existing names (`jq -r '.profiles | keys[]' "$CONFIG"`). Ask for a name; suggest one from the host. `default` is reserved for local. If the name exists, ask before replacing its endpoint and env.
5. **Write** the profile with `endpoint` and `env` only, and make it active ([Write the profile](#write-the-profile)).
6. **Auth check:** `curl -s -o /dev/null -w '%{http_code}' --max-time 5 "<endpoint>/api/model/"` with no token.
   - `200`: mock auth, no token needed.
   - `401` or `403`: the instance needs a token. Don't ask for credentials here; `/cyoda:auth` handles them.
   - Anything else: show the code and point to `cyoda help errors --section "ERROR CODE INDEX"`.
7. **Report:** go to [Finish](#finish).

## Write the profile

The config is `${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}`. Keep other profiles, and keep the profile's existing `tokenCommand`. Substitute the values you collected:

```bash
CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"
mkdir -p "$(dirname "$CONFIG")"
[ -f "$CONFIG" ] || echo '{"active":"default","profiles":{}}' > "$CONFIG"
jq --arg p "<PROFILE>" --arg ep "<ENDPOINT>" --arg env "<ENV>" \
  '.profiles[$p] = ((.profiles[$p] // {}) + {endpoint: $ep, env: $env}) | .active = $p' \
  "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
```

Never write `token`, `clientSecret` or any other credential into it. If `mkdir` or the write is denied, don't try `sudo`, `chmod` or `chown`. Show:

> Couldn't write to `~/.config/cyoda/`. You may be running in a sandbox or restricted environment. Please allow write access to that directory and try again.

## Finish

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh` again and report in the `status` form:

- `Connected to cyoda-go v<VERSION> — <ENDPOINT> [profile: <PROFILE>]`, plus ` [PRODUCTION]` when `ENV=production`.
- Then every `WARN=` line, as it is.

End with one hand-off and a one-line reason:
- Needs a token (connect mode, step 6): "This instance requires a token. Next, type `/cyoda:auth` to set up a token script for profile `<PROFILE>`."
- Otherwise: "next, type `/cyoda:build` to create your first entity model and workflow" (or `/cyoda:app` for the guided journey).

## Common mistakes

| Mistake | Fix |
|---|---|
| `brew tap cyoda-platform/...` or another formula name | Exactly `brew install cyoda/cyoda-go/cyoda` |
| Fixing Homebrew after an install failure | Show the verbatim message and wait |
| Checking `/readyz` on port 8080 | `/api/health` on the API port; `/readyz` is on the admin port |
| Storing `.../api` as the endpoint | Store the base URL; scripts add `/api` |
| Asking for a client secret in connect mode | Hand off: "next, type `/cyoda:auth`" |
| Deleting an old profile or stored token unasked | Show the warning; change it only on a yes |
