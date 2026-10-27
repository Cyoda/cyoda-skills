---
name: setup
description: Use when the developer types /cyoda:setup to install and start a local cyoda-go, to connect the plugin to an existing self-hosted cyoda-go instance, to link or unlink the current project to its own instance (e.g. its Docker Compose stack), or to switch away from an unreachable or outdated connection profile.
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-help.sh *) Bash(*cyoda-docker-instances.sh*) Bash(*cyoda-config-write.sh *) Bash(brew *) Bash(cyoda *) Bash(command -v *) Bash(curl *) Bash(mkdir *) Bash(jq *) Bash(mv *) Bash(cat *) Bash(sleep *) Bash(git rev-parse *) Bash(pwd *) Bash(ls *) Bash(chmod *)
disable-model-invocation: true
---

# Cyoda setup

Three modes: **local** (install and run cyoda-go on this machine, profile `default`), **connect** (add a machine-wide profile for a cyoda-go instance that already runs somewhere, e.g. one made with `/cyoda:deploy`) and **link** (bind this project directory to its own instance: an entry in the plugin config's `projects` map, keyed by the directory's real path, so it stays private to this developer and nothing is written into the project). The scripts every other skill uses read, in order: `CYODA_PROFILE=<name>` if set, the `projects` entry for the working directory or its nearest ancestor, the active profile, the local default.

**Facts come from `cyoda help`.** Read sections with `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` once the binary is installed (before that, the help mirror at https://docs.cyoda.net/help/ has the same content).

**The plugin stores no tokens or secrets.** A profile or project entry holds only `endpoint`, `env` (`development` | `production`) and `tokenCommand`.

## Step 0 — Where things stand

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. It prints `STATUS=… PROFILE=… ENDPOINT=… ENV=… VERSION=… BINARY_VERSION=… SOURCE=… [PROJECT=…]` and then `WARN=` lines.

- Show every `WARN=` line as it is, e.g. "profile old contains a stored token, which this plugin no longer reads; you can remove it". Don't read, print or reuse a stored token. Remove it only if the developer says yes: `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh 'del(.profiles[$p].token)' --arg p '<P>'` ([Changing the config](#changing-the-config)).
- `SOURCE=project` (this project is linked, `PROJECT=<dir>`). Never offer the active-profile switch below for it: that changes the machine-wide config, and this project would still use its own binding.
  - `STATUS=connected`: say so. [Link mode](#link-mode) re-links it (replacing the entry) and [unlink](#unlink) removes it, each only on a yes.
  - `STATUS=unreachable`: the project's own instance isn't answering. Offer two ways: (1) start it: if `<PROJECT>` has a Compose file (`ls <PROJECT>/compose.yaml <PROJECT>/compose.yml <PROJECT>/docker-compose.yml <PROJECT>/docker-compose.yaml`), give `cd <PROJECT> && docker compose up -d` for the developer to run in their own terminal (you don't run it); with no Compose file, ask how they start it, or offer a re-link; when they say it's up, run `cyoda-status.sh` again and go to [Finish](#finish); or (2) re-link the project to another instance in [link mode](#link-mode).
- `WARN=no saved profile; …`: there is no active profile and no linked project here (no config file, or `active` names no saved profile, e.g. a config with only `projects`), so the scripts used the local default `http://localhost:8080`. Unless the request says connect or link: `STATUS=connected` means a local cyoda-go already answers, so go to local mode to save it as `default` (its checks skip what's done); `STATUS=unreachable` (`WARN=no cyoda-go is answering at …`) means nothing runs locally yet, so go to local mode.
- `STATUS=unreachable` for a saved profile (`SOURCE=profile`): offer to switch the active profile to `default`: on a yes, `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh '.active = "default"'`, leaving the unreachable profile in place, then go to [Finish](#finish). If `default` doesn't exist or isn't running either, continue with local mode.
- Otherwise ask which mode, unless the request already says: "Run cyoda-go **locally**, or **connect** to an instance that already runs elsewhere?" Inside a project directory (`git rev-parse --show-toplevel` succeeds, or the working directory isn't `$HOME`), add: "Or **link this project** to an instance (only this project uses it, e.g. its Docker Compose stack)?" If the project root has a legacy `.cyoda/config` or `.cyoda/instance.json` (older plugin versions wrote them; the scripts no longer read them), mention it and suggest linking, which can import it.

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
6. **Profile:** [write](#changing-the-config) `default` = `{"endpoint": "http://localhost:8080", "env": "development"}` and make it active. A local `default` runs mock auth, so it gets no `tokenCommand`.
7. **Report:** go to [Finish](#finish). Add: "Mock auth is active, so no token is needed and you don't need `/cyoda:auth` for this instance."

## Connect mode

1. **Endpoint:** ask for the instance's base URL. Strip a trailing `/` and a trailing `/api`: the profile stores `https://host[:port]`, and the scripts add `/api`.
2. **Probe:** `curl -sS --max-time 5 "<endpoint>/api/health"`. Anything other than `{"status":"UP"}`: show what came back (or the curl error), say the instance isn't reachable or isn't ready, and stop. Write no profile for an endpoint that doesn't answer.
3. **Environment:** ask "Is this a **development** or **production** instance?" For production, say: "I'll mark it `production`. Skills will then ask before every call that changes data on it."
4. **Profile name:** list existing names (`jq -r '.profiles | keys[]' "$CONFIG"`). Ask for a name; suggest one from the host. `default` is reserved for local. If the name exists, ask before replacing its endpoint and env.
5. **Write** the profile with `endpoint` and `env` only, and make it active ([Changing the config](#changing-the-config)).
6. **Auth check:** `curl -s -o /dev/null -w '%{http_code}' --max-time 5 "<endpoint>/api/model/"` with no token.
   - `200`: mock auth, no token needed.
   - `401` or `403`: the instance needs a token. Don't ask for credentials here; `/cyoda:auth` handles them.
   - Anything else: show the code and point to `cyoda help errors --section "ERROR CODE INDEX"`.
7. **Report:** go to [Finish](#finish).

## Link mode

Binds one project directory (and everything below it) to one instance. Other directories keep the machine-wide profile. The binding is an entry in the plugin config; nothing is written into the project.

1. **Project root:** propose `git rev-parse --show-toplevel`, else the working directory, and let the developer confirm or change it. If it is `$HOME`, say a link needs a project directory and offer connect mode instead. If its path contains a line break, refuse: the plugin can't link it. `<NAME>` is its basename. The key is its real path: `cd '<ROOT>' && pwd -P`. Re-linking: when Step 0 showed `SOURCE=project` for this root, use its `PROJECT` value as the key, so the entry is replaced, not duplicated.
2. **Legacy file (once):** if `<ROOT>/.cyoda/config` or `<ROOT>/.cyoda/instance.json` exists, read only `jq '{endpoint, env}' <file>`: never print or take its `token` or `tokenCommand`. Offer: "This project has an old binding file, which the plugin no longer reads. Import its endpoint `<E>` and env `<env>`?" On a yes, use them below (still probed and confirmed). After the write, say the file is no longer read and give `rm <ROOT>/.cyoda/<file>` for the developer to run.
3. **Pick the instance:** if `command -v docker` succeeds, run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-docker-instances.sh`. Each line is `CONTAINER=… COMPOSE_PROJECT=… ENDPOINT=… IMAGE=…`, one running cyoda-go container with the host side of its REST port (container port `8080`: `cyoda help run --section "PORT LAYOUT"`). List them numbered as `<COMPOSE_PROJECT> (<CONTAINER>) — <ENDPOINT>`, suggest the one whose compose project matches `<NAME>`, and ask the developer to pick one or type a URL. `ENDPOINT=none`: its REST port isn't published, so it can't be picked. Exit 4 or no lines: say what came back and ask for a URL. Without docker: ask for a URL. Normalise a typed URL as in connect step 1.

   Docker is only read. Never run `docker run`, `start`, `stop`, `restart`, `rm` or `docker compose` anything: if the stack isn't up, the developer starts it and says when.
4. **Probe:** `curl -sS --max-time 5 "<ENDPOINT>/api/health"` must return `{"status":"UP"}` (`cyoda help run --section "HEALTH PROBES"`); then `curl -s --max-time 5 "<ENDPOINT>/api/help" | jq -r .version` for the version. Not UP: show what came back and stop; write nothing.
5. **Environment:** ask as in connect step 3.
6. **Tokens:** `curl -s -o /dev/null -w '%{http_code}' --max-time 5 "<ENDPOINT>/api/model/"` with no token.
   - `200`: mock auth, no `tokenCommand`.
   - `401` / `403`: read `cyoda-help.sh auth --section "WHICH PATH DO I NEED?"` and ask: "How does this project get tokens: a **script in the project** (e.g. `scripts/auth.sh token`), or **none yet**?" When re-linking, offer the entry's current `tokenCommand`. A project script may be relative to `<ROOT>`: the plugin runs it from there, with `CYODA_ENDPOINT` set. A command that assigns a literal value to a `…SECRET`, `…PASSWORD` or `…TOKEN` variable (e.g. `CYODA_CLIENT_SECRET=abc scripts/auth.sh`) would store a secret: refuse it and suggest the `*_CMD` form instead, e.g. `CYODA_CLIENT_SECRET_CMD='security find-generic-password -s shop-cyoda -w' scripts/get-token.sh`. Test it before saving, without showing the token (placeholders in single quotes, as in [Changing the config](#changing-the-config)):
     ```bash
     ( set -o pipefail; cd '<ROOT>' && CYODA_ENDPOINT='<ENDPOINT>' bash -c '<CMD>' | awk -F. '{print NF " parts, " length($0) " chars"}' ); echo "exit=$?"
     ```
     `exit=0` and `3 parts`: use it as `tokenCommand`. Otherwise show the script's stderr, don't save it, and treat it as none yet. None yet: no `tokenCommand`; the hand-off is `/cyoda:auth`.
7. **Write** `projects[<KEY>]`, replacing any entry with that key (`<CMD>` empty when there is no `tokenCommand`):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh \
     '.projects[$k] = ({endpoint: $ep, env: $env} + (if $tc == "" then {} else {tokenCommand: $tc} end))' \
     --arg k '<KEY>' --arg ep '<ENDPOINT>' --arg env '<ENV>' --arg tc '<CMD>'
   ```
   A new config holds only `projects`, so other directories keep the local default. Never a token, client id or secret in it.
8. **Report:** go to [Finish](#finish), and add: "Only this project uses it; other directories keep the machine-wide profile."

## Unlink

When Step 0 shows `SOURCE=project` and the developer wants this project to stop using its own instance: confirm, then delete the entry by its `PROJECT` key and go to [Finish](#finish):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh 'del(.projects[$k])' --arg k '<PROJECT>'
```

Not linked (`SOURCE` is not `project`): say so and change nothing.

## Changing the config

Every change to `${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}` goes through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh '<jq filter>' --arg <name> '<value>' …`; never write the file with `jq … > file` or `echo`. The script keeps every other section, writes atomically, leaves the file 0600 and creates a missing config dir 0700. Values go in only as `--arg`, never spliced into the filter. Every placeholder sits in single quotes, copied character for character, with each `'` in it written as `'\''` (a path like `paul's app` becomes `'paul'\''s app'`). Exit 1: show its stderr (invalid config, or a filter error). Exit 3: the write is denied (below).

**Write the profile** (keeps other profiles and the profile's existing `tokenCommand`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh \
  '.profiles[$p] = ((.profiles[$p] // {}) + {endpoint: $ep, env: $env}) | .active = $p' \
  --arg p '<PROFILE>' --arg ep '<ENDPOINT>' --arg env '<ENV>'
```

Never write `token`, `clientSecret` or any other credential into it. If the write is denied (exit 3), don't try `sudo`, `chmod` or `chown`. Show:

> Couldn't write to `~/.config/cyoda/`. You may be running in a sandbox or restricted environment. Please allow write access to that directory and try again.

## Finish

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh` again and report in the `status` form:

- `Connected to cyoda-go v<VERSION> — <ENDPOINT> [profile: <PROFILE>]` (`[project: <PROFILE>]` when `SOURCE=project`), plus ` [PRODUCTION]` when `ENV=production`.
- Then every `WARN=` line, as it is.
- After local or connect mode, if the status still shows `SOURCE=project`, say: "This project is linked to `<ENDPOINT>` (its `projects` entry), which takes precedence here (status shows `[project: <PROFILE>]`); the new profile applies in other directories."

End with one hand-off and a one-line reason:
- Needs a token (connect step 6, or link step 6 with none yet): "This instance requires a token. Next, type `/cyoda:auth` to set up a token script for `<PROFILE>`."
- Otherwise: "next, type `/cyoda:build` to create your first entity model and workflow" (or `/cyoda:app` for the guided journey).

## Common mistakes

| Mistake | Fix |
|---|---|
| `brew tap cyoda-platform/...` or another formula name | Exactly `brew install cyoda/cyoda-go/cyoda` |
| Fixing Homebrew after an install failure | Show the verbatim message and wait |
| Checking `/readyz` on port 8080 | `/api/health` on the API port; `/readyz` is on the admin port |
| Storing `.../api` as the endpoint | Store the base URL; scripts add `/api` |
| Asking for a client secret in connect mode | Hand off: "next, type `/cyoda:auth`" |
| Starting or stopping containers in link mode | Docker is read only; the developer runs the stack |
| Writing a link into the project (a `.cyoda/` file, `.gitignore`) | Link mode writes only `projects[<KEY>]` in the plugin config |
| A second entry for a re-linked project | Reuse the `PROJECT` key from Step 0 |
| Deleting an old profile or stored token unasked | Show the warning; change it only on a yes |
