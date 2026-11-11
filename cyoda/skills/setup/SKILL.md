---
name: setup
description: Use when the developer types /cyoda:setup to install and start a local cyoda-go, to connect the plugin to an existing self-hosted cyoda-go instance, to link or unlink the current project to its own instance (e.g. its Docker Compose stack), or to switch away from an unreachable or outdated connection profile.
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-help.sh *) Bash(*cyoda-docker-instances.sh*) Bash(*cyoda-config-write.sh *) Bash(brew *) Bash(cyoda *) Bash(command -v *) Bash(curl *) Bash(jq *) Bash(sleep *) Bash(git rev-parse *) Bash(pwd *) Bash(ls *) Bash(docker compose *)
disable-model-invocation: true
---

# Cyoda setup

Three modes: **local** (install and run cyoda-go on this machine, profile `default`), **connect** (a machine-wide profile for a cyoda-go instance that runs elsewhere, e.g. one made with `/cyoda:deploy`) and **link** (bind this project directory to its own instance: an entry in the plugin config's `projects` map, keyed by the directory's real path; nothing is written into the project). The scripts resolve the instance in this order: `CYODA_PROFILE=<name>`, the `projects` entry for the working directory or its nearest ancestor, the active profile, the local default `http://localhost:8080`.

Facts come from `cyoda help`: `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` once the binary is installed (before that, https://docs.cyoda.net/help/).

A profile or project entry holds only `endpoint` and, optionally, `tokenCommand`: no tokens or secrets.

## Step 0 — Where things stand

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. Line 1 is `STATUS=… PROFILE=… ENDPOINT=… VERSION=… BINARY_VERSION=… SOURCE=… [PROJECT=…]`, then `WARN=` lines.

- Show every `WARN=` line as it is. A profile with a stored token: don't read or use the token; remove it only on a yes, with `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh 'del(.profiles[$p].token)' --arg p '<P>'`.
- `SOURCE=project` (this project is linked, `PROJECT=<dir>`): the active-profile switch below doesn't apply.
  - `STATUS=connected`: say so. [Link mode](#link-mode) re-links it, [Unlink](#unlink) removes it.
  - `STATUS=unreachable`, and `<PROJECT>` has a [cyoda Compose stack](#a-projects-compose-stack): start it, poll `<ENDPOINT>/api/health` every second for up to 15 s until `{"status":"UP"}`, run `cyoda-status.sh` again and go to [Finish](#finish). Re-linking in link mode stays available if the developer asks.
  - `STATUS=unreachable` without one: ask how they start that instance and run `cyoda-status.sh` again when they say it's up, or re-link in link mode.
- `WARN=no saved profile; …` (the scripts used the local default) and the request doesn't say connect or link: if the project root (`git rev-parse --show-toplevel`, else the working directory) has a [cyoda Compose stack](#a-projects-compose-stack), go to link mode, which starts and links it; otherwise go to local mode; its checks skip what's already done.
- `STATUS=unreachable` with `SOURCE=profile`: offer to switch the active profile to `default`. On a yes, `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh '.active = "default"'` (the other profile stays), then [Finish](#finish). If `default` doesn't exist or doesn't answer either, go to local mode.
- Otherwise ask which mode, unless the request says: "Run cyoda-go **locally**, or **connect** to an instance that already runs elsewhere?" Inside a project directory (`git rev-parse --show-toplevel` succeeds, or the working directory isn't `$HOME`) add: "Or **link this project** to its own instance (e.g. its Docker Compose stack)?" A legacy `.cyoda/config` or `.cyoda/instance.json` in the project root (older plugins wrote them; nothing reads them now): mention it and suggest linking, which imports it.

## Local mode

1. **Installed?** `command -v cyoda && cyoda --version`. A version: skip to step 3.
2. **Install:** `brew install cyoda/cyoda-go/cyoda`. If it fails, show its error and the ways to install below, wait until the developer says it's installed, then check `cyoda --version` again.
   - Homebrew: `brew install cyoda/cyoda-go/cyoda`
   - Install script: `curl -fsSL https://github.com/cyoda/cyoda-go/releases/latest/download/install.sh | sh`
   - Release binaries: https://github.com/cyoda/cyoda-go/releases
   - Docker image: `ghcr.io/cyoda/cyoda` (run recipe: https://docs.cyoda.net/help/run.md, RUN MODES → Docker)

   <!-- #684-K workaround: `cyoda help` has no install section yet. Remove this list and point to the help topic once Cyoda/cyoda-go#684 item K ships. -->
3. **Initialise (first time only):** `cyoda init`; an existing user config stays (no `-force`). From `cyoda help run --section "RUN MODES"` (Binary) and `cyoda help quickstart --section DEFAULTS`, tell the developer in one or two lines what `init` set up and where the data lives.
4. **Start:** unless `curl -s --max-time 2 http://localhost:8080/api/health` already returns `{"status":"UP"}`, start `cyoda` as a background process. Port clash: `cyoda help run --section "PORT LAYOUT"`.
5. **Verify:** poll `http://localhost:8080/api/health` every second for up to 15 s until `{"status":"UP"}`. Readiness is `/api/health` on the API port; `/readyz` is on the admin port (`cyoda help run --section "HEALTH PROBES"`).
6. **Profile:** [write](#changing-the-config) `default` = `{"endpoint": "http://localhost:8080"}` and make it active. A local `default` runs mock auth: no `tokenCommand`.
7. **Report:** [Finish](#finish), adding: "Mock auth is active, so no token is needed and you don't need `/cyoda:auth` for this instance."

## Connect mode

1. **Endpoint:** ask for the base URL. Store `https://host[:port]`: strip a trailing `/` and `/api` (the scripts add `/api`).
2. **Probe:** `curl -sS --max-time 5 "<endpoint>/api/health"`. Not `{"status":"UP"}`: show what came back and stop without writing.
3. **Profile name:** ask for one (existing names: `jq -r '.profiles | keys[]' "$CONFIG"`), suggesting one from the host. `default` is reserved for local.
4. **Write** the profile and make it active ([Changing the config](#changing-the-config)).
5. **Auth check:** `curl -s -o /dev/null -w '%{http_code}' --max-time 5 "<endpoint>/api/model/"` without a token.
   - `200`: mock auth, no token needed.
   - `401` / `403`: the instance needs a token; `/cyoda:auth` sets it up.
   - Anything else: show the code; see `cyoda help errors --section "ERROR CODE INDEX"`.
6. **Report:** [Finish](#finish).

## Link mode

Binds one project directory (and everything below it) to one instance; other directories keep the machine-wide profile.

1. **Project root:** propose `git rev-parse --show-toplevel`, else the working directory; the developer confirms or changes it. `$HOME` can't be linked: offer connect mode. `<NAME>` is its basename; the key is its real path, `cd '<ROOT>' && pwd -P`. Re-linking a root that Step 0 showed as `PROJECT`: use that value as the key, so the entry is replaced.
2. **Legacy file:** if `<ROOT>/.cyoda/config` or `<ROOT>/.cyoda/instance.json` exists, read only `jq -r .endpoint <file>` (never its `token` or `tokenCommand`) and offer once to import that endpoint (still probed below). After the write, say the file is no longer read and give `rm <ROOT>/.cyoda/<file>` for the developer to run.
3. **Pick the instance:** if `command -v docker` succeeds, run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-docker-instances.sh`: one line `CONTAINER=… COMPOSE_PROJECT=… ENDPOINT=… IMAGE=…` per running cyoda-go container, `ENDPOINT` being the host side of its REST port (`cyoda help run --section "PORT LAYOUT"`).
   - Before listing: if no line's `COMPOSE_PROJECT` equals `<NAME>` ignoring case and `<ROOT>` has a [cyoda Compose stack](#a-projects-compose-stack), start it and run `cyoda-docker-instances.sh` again.
   - List the lines numbered as `<COMPOSE_PROJECT> (<CONTAINER>) — <ENDPOINT>`, suggest the one whose `COMPOSE_PROJECT` equals `<NAME>` ignoring case, and let the developer pick one or type a URL. A line with `ENDPOINT=none` (REST port not published) can't be picked.
   - Exit 4, no lines, or no docker: ask for a URL, normalised as in connect step 1.
4. **Probe:** `curl -sS --max-time 5 "<ENDPOINT>/api/health"` must return `{"status":"UP"}` (right after a start, poll every second for up to 15 s); the version is `curl -s --max-time 5 "<ENDPOINT>/api/help" | jq -r .version`. Not UP: show what came back and stop without writing.
5. **Tokens:** `curl -s -o /dev/null -w '%{http_code}' --max-time 5 "<ENDPOINT>/api/model/"` without a token.
   - `200`: mock auth, no `tokenCommand`.
   - `401` / `403`: from `cyoda-help.sh auth --section "WHICH PATH DO I NEED?"`, ask how the project gets tokens: a script in the project (e.g. `scripts/auth.sh token`), or none yet. When re-linking, offer the entry's current `tokenCommand`. The plugin runs it from `<ROOT>` with `CYODA_ENDPOINT` set, so a project-relative path works. A secret enters it through the `*_CMD` form (e.g. `CYODA_CLIENT_SECRET_CMD='security find-generic-password -s shop-cyoda -w' scripts/get-token.sh`), not as a literal value. Run it that way once without showing the token; it becomes `tokenCommand` only if it exits 0 and prints three dot-separated parts. None yet: no `tokenCommand`, and the hand-off is `/cyoda:auth`.
6. **Write** `projects[<KEY>]`, replacing an entry with that key (`<CMD>` empty for no `tokenCommand`):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh \
     '.projects[$k] = ({endpoint: $ep} + (if $tc == "" then {} else {tokenCommand: $tc} end))' \
     --arg k '<KEY>' --arg ep '<ENDPOINT>' --arg tc '<CMD>'
   ```
   A new config holds only `projects`, so other directories keep the local default.
7. **Report:** [Finish](#finish), adding: "Only this project uses it; other directories keep the machine-wide profile."

## A project's Compose stack

A directory `<DIR>` (the link root, or Step 0's `PROJECT`) has a cyoda Compose stack when its `compose.yaml`, `compose.yml`, `docker-compose.yaml` or `docker-compose.yml` has a service whose image is `ghcr.io/cyoda/cyoda` (any tag). Start it with `docker compose -f '<DIR>/<file>' up -d`, `<file>` being the file with that service. If that fails, show its output and stop.

## Unlink

When Step 0 shows `SOURCE=project` and the developer wants this project to stop using its own instance: confirm, delete the entry by its `PROJECT` key, then [Finish](#finish):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh 'del(.projects[$k])' --arg k '<PROJECT>'
```

Not linked (`SOURCE` is not `project`): say so and change nothing.

## Changing the config

Every change to the plugin config (`$CONFIG` = `${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}`) goes through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh '<jq filter>' --arg <name> '<value>' …`, values only as `--arg`. It keeps the other sections, writes atomically and keeps the file 0600. On a non-zero exit, show its stderr.

**Write the profile** (keeps the other profiles and this profile's `tokenCommand`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh \
  '.profiles[$p] = ((.profiles[$p] // {}) + {endpoint: $ep}) | .active = $p' \
  --arg p '<PROFILE>' --arg ep '<ENDPOINT>'
```

## Finish

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh` again and report:

- `Connected to cyoda-go v<VERSION> — <ENDPOINT> [profile: <PROFILE>]` (`[project: <PROFILE>]` when `SOURCE=project`), then every `WARN=` line as it is.
- After local or connect mode, if status still shows `SOURCE=project`: "This project is linked to `<ENDPOINT>` (its `projects` entry), which takes precedence here; the new profile applies in other directories."

End with one hand-off and a one-line reason:
- Needs a token (connect step 5, or link step 5 with none yet): "This instance requires a token. Next, type `/cyoda:auth` to set up a token script for `<PROFILE>`."
- Otherwise: "next, type `/cyoda:build` to create your first entity model and workflow" (or `/cyoda:app` for the guided journey).

## Common mistakes

| Mistake | Fix |
|---|---|
| `brew tap cyoda-platform/...` or another formula name | Exactly `brew install cyoda/cyoda-go/cyoda` |
| Writing a link into the project (a `.cyoda/` file, `.gitignore`) | Link mode writes only `projects[<KEY>]` in the plugin config |
| A second entry for a re-linked project | Reuse the `PROJECT` key from Step 0 |
| Deleting an old profile or stored token unasked | Show the warning; change it only on a yes |
