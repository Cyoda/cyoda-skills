---
name: setup
description: Use when a cyoda-go instance is needed or asked about — starting or finding one for this project, whether Cyoda is connected, which instance, project binding, profile or version is active, why the connection fails, connecting to a self-hosted cyoda-go, or linking or unlinking a project.
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-local.sh *) Bash(*cyoda-ports.sh *) Bash(*cyoda-docker-instances.sh*) Bash(*cyoda-config-write.sh *) Bash(*cyoda-help.sh *) Bash(cyoda *) Bash(brew *) Bash(docker compose *) Bash(curl *) Bash(jq *) Bash(command -v *) Bash(git rev-parse *) Bash(pwd *) Bash(cd * && pwd -P) Bash(sh)
---

# Cyoda setup

The scripts resolve the instance in this order: `CYODA_PROFILE=<name>`, the `projects` entry for the working directory or its nearest ancestor, the active profile, the implicit local default `http://localhost:8080`. All of it lives in the plugin config, `$CONFIG` = `${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}`; a profile or entry never holds a token or secret. Facts come from `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` (before `cyoda` is installed, https://docs.cyoda.net/help/).

**The project** is `<ROOT>`: the real path (`cd <dir> && pwd -P`) of `git rev-parse --show-toplevel`, else of the working directory. `<NAME>` is its basename. Each git worktree and clone is its own project. `$HOME` is not a project: ask which directory.

## Status

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. A non-zero exit (an invalid config or `projects` entry, an unknown `CYODA_PROFILE`): show its stderr and stop.

Line 1 is `STATUS=<s> PROFILE=<P> ENDPOINT=<E> VERSION=<V> BINARY_VERSION=<B> SOURCE=<src>`, plus ` PROJECT=<dir>` when `SOURCE=project` (always last, to the end of the line; it is the entry's key). `PROFILE` is in double quotes when it holds a space or a quote: report it without them, `\"` as `"`. Then `WARN=<text>` lines. Report exactly one line:

| `STATUS` | Report |
|---|---|
| `connected` | `Connected to cyoda-go v<V> — <E> <TAG>` |
| `unreachable` | `cyoda-go unreachable — <E> <TAG>` |
| `not_configured` | `Not connected — profile <P> has no endpoint` |

- `<TAG>`: `SOURCE=project` → `[project: <P>]`; `profile` or `default` → `[profile: <P>]`.
- `VERSION=unknown`: `version unknown` in place of `v<V>`. `<V>` is the instance; `BINARY_VERSION` is the local `cyoda`.
- After the line, each `WARN=<text>` as `Warning: <text>`.

A question about the connection (is it connected, which instance, binding, profile or version) ends with this report: nothing changed, nothing asked.

## Getting an instance

A request to connect to a named URL, to link, re-link or unlink this project goes to [Connect](#connect), [Link](#link) or [Unlink](#unlink). For every other request (an instance is needed, `/cyoda:setup`, "get cyoda running"), go by the status line. Say in one line what you start or bind and why, then do it. `SOURCE=profile` with `PROFILE=default` is the old machine-wide local default: treat it as `SOURCE=default`.

1. **Bound and answering:** `STATUS=connected` with `SOURCE=project` or `SOURCE=profile` → use it; [Finish](#finish). `SOURCE=profile` not answering (or `not_configured`): the profile stays as it is; say so in one line and go on with step 3, which gives this project its own entry.
2. **This project's entry, not answering** (`SOURCE=project`, `STATUS=unreachable`; the entry is `jq --arg k '<PROJECT>' '.projects[$k]' "$CONFIG"`):
   - `run` is `binary` or `docker` → `cyoda-local.sh start '<PROJECT>'`; `run` is `repo` → `cyoda-local.sh start-repo '<PROJECT>' '<compose>'`. It comes back on the recorded ports.
   - no `run`, and `<PROJECT>` has a [cyoda Compose stack](#a-repos-compose-stack) → `cyoda-local.sh start-repo '<PROJECT>' '<PROJECT>/<file>'`.
   - otherwise (`existing`, or a link to an instance that runs elsewhere): report it and stop; [Link](#link) re-binds it when asked.
3. **Defined by the project:** `<ROOT>` has a cyoda Compose stack → `cyoda-local.sh start-repo '<ROOT>' '<ROOT>/<file>'`. A Makefile or script target, or README instructions, that run cyoda-go → run it that way, poll `<endpoint>/api/health` every second for up to 30 s until `{"status":"UP"}`, and [record](#changing-the-config) `{run: "existing", endpoint}` for `<ROOT>`.
4. **Not defined:** ask once, the only question:
   - `SOURCE=default`, `STATUS=connected` and `VERSION` not `unknown`: "Use the cyoda-go already running on localhost:8080, or start one for this project from the command line or in Docker?" (with `<E>`'s host and port in place of localhost:8080)
   - otherwise: "Run cyoda-go for local development and testing from the command line or in Docker?"

   Then:
   - **The running one:** [record](#changing-the-config) `{run: "existing", endpoint: "<E>"}` for `<ROOT>`. That instance is the developer's: never stop, restart or reconfigure it.
   - **Command line:** `command -v cyoda`; nothing → [install](#install). Then `cyoda-local.sh start '<ROOT>' --run binary`.
   - **Docker:** `cyoda-local.sh start '<ROOT>' --run docker`.
   - Storage is in-memory; add `--storage sqlite` when the requirement needs data to survive a restart.

Then [Finish](#finish). A `WARN=` from the first status run that this procedure resolves (an endpoint not answering, no saved profile) is not repeated; show the others as `Warning: <text>`.

### `cyoda-local.sh`

`${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-local.sh start <root> [--run binary|docker] [--storage memory|sqlite]`, `start-repo <root> <compose-file>`, `stop <root>`. It picks a free port block (HTTP, gRPC, admin; `cyoda help run --section "PORT LAYOUT"`), names the instance after the project, keeps its data, config, pid file, log and Compose files under `~/.local/share/cyoda/projects/<instance>` (never in the repo), runs `start` with mock auth, waits for `/api/health` and records the project's entry (`run`, `instance`, `dataDir`, `ports`, `storage` or `compose`, `endpoint`). It prints `ENDPOINT=<url> HTTP=<p> GRPC=<p> ADMIN=<p> RUN=<run> STATE=started|ours` (`ours`: this project's instance already runs and is reused).

| Exit | Then |
|---|---|
| 1 | invalid plugin config: show stderr, stop |
| 3 | no free port block: show stderr, stop |
| 4 | did not become healthy (it cleaned up): show stderr, stop |
| 5 | `cyoda` missing → [install](#install) and run it again; `docker` or `lsof` missing → show stderr, stop |
| 64 | usage error (a missing or wrong argument, no such directory): fix the call |

- A busy port belongs to someone else: the script takes the next block. Never stop, kill or reconfigure a process or container to free a port.
- `start-repo` whose `HTTP` differs from the host port the repo's file publishes: say in one line that those ports were taken, so the stack runs on `<HTTP>`/`<GRPC>`/`<ADMIN>` through an override file in the project's data dir and the repo's files are unchanged.
- Stopping this project's instance, when asked: `cyoda-local.sh stop '<ROOT>'`.

### A repo's Compose stack

A directory has one when its `compose.yaml`, `compose.yml`, `docker-compose.yaml` or `docker-compose.yml` has a service whose image is `ghcr.io/cyoda/cyoda` (any tag). Start it only through `cyoda-local.sh start-repo`.

### Install

`brew install cyoda/cyoda-go/cyoda`. If it fails, `curl -fsSL https://github.com/cyoda/cyoda-go/releases/latest/download/install.sh | sh`. If both fail, show their errors and the other ways (release binaries https://github.com/cyoda/cyoda-go/releases, or Docker with the image `ghcr.io/cyoda/cyoda`) and stop.

<!-- #684-K workaround: `cyoda help` has no install section yet. Remove this list and point to the help topic once Cyoda/cyoda-go#684 item K ships. -->

## Connect

A machine-wide profile for a cyoda-go the developer names by URL (e.g. one made with `cyoda:deploy`).

1. Store `https://host[:port]`: strip a trailing `/` and `/api` (the scripts add `/api`).
2. `curl -sS --max-time 5 "<endpoint>/api/health"`; not `{"status":"UP"}`: show what came back and stop without writing.
3. Name the profile after the host's first label (`cyoda-dev.internal.example.com` → `cyoda-dev`), adding `-2`, `-3`… when that name holds another endpoint; never `default` (reserved for the local default).
4. [Write the profile](#changing-the-config) and make it active.
5. `curl -s -o /dev/null -w '%{http_code}' --max-time 5 "<endpoint>/api/model/"` without a token: `200` mock auth; `401`/`403` report "This instance needs a token; token setup for it is covered by `cyoda:auth`."; anything else: show it, see `cyoda help errors --section "ERROR CODE INDEX"`.
6. [Finish](#finish).

## Link

Binds `<ROOT>` to an instance this plugin doesn't start (a running stack, a URL). Re-linking: the key is the status line's `PROJECT`, so the entry is replaced.

1. **Legacy file:** `<ROOT>/.cyoda/config` or `<ROOT>/.cyoda/instance.json` (older plugins wrote them): read only `jq -r .endpoint <file>`, never its `token` or `tokenCommand`, and use that endpoint. After the write, say the file is no longer read and can be removed.
2. **Instance:** a URL from the developer, else, when `command -v docker` succeeds, `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-docker-instances.sh`: one line `CONTAINER=… COMPOSE_PROJECT=… WORKDIR=… ENDPOINT=… IMAGE=…` per running cyoda-go container (`ENDPOINT=none`: REST port not published, unusable).
   - The line whose `COMPOSE_PROJECT` equals `<NAME>` ignoring case, or whose `WORKDIR` is `<ROOT>`: take it.
   - None, and `<ROOT>` has a cyoda Compose stack: `cyoda-local.sh start-repo` instead, then [Finish](#finish).
   - Otherwise list the lines as `<COMPOSE_PROJECT> (<CONTAINER>) — <ENDPOINT>` and ask which, or for a URL.
3. **Probe:** `curl -sS --max-time 5 "<E>/api/health"` must return `{"status":"UP"}`; the version is `curl -s --max-time 5 "<E>/api/help" | jq -r .version`. Not UP: show what came back and stop without writing.
4. **Tokens:** `curl -s -o /dev/null -w '%{http_code}' --max-time 5 "<E>/api/model/"` without a token.
   - `200`: mock auth, no `tokenCommand`.
   - `401`/`403`: re-linking keeps the entry's `tokenCommand`; otherwise ask how the project gets tokens (`cyoda-help.sh auth --section "WHICH PATH DO I NEED?"`), e.g. `scripts/auth.sh token`. The plugin runs it from `<ROOT>` with `CYODA_ENDPOINT` set, so a project-relative path works; a secret enters through the `*_CMD` form (`CYODA_CLIENT_SECRET_CMD='security find-generic-password -s shop-cyoda -w' scripts/get-token.sh`), never as a literal. Run it that way once without showing the token; it becomes `tokenCommand` only if it exits 0 and prints three dot-separated parts. None yet: no `tokenCommand`; report "This instance needs a token; token setup for it is covered by `cyoda:auth`."
5. **Write** `projects[<KEY>]` (`<CMD>` empty for no `tokenCommand`):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh \
     '.projects[$k] = ({endpoint: $ep} + (if $tc == "" then {} else {tokenCommand: $tc} end))' \
     --arg k '<KEY>' --arg ep '<E>' --arg tc '<CMD>'
   ```
6. [Finish](#finish).

## Unlink

`SOURCE=project` and the developer wants this project off its own instance: if the entry's `run` is `binary` or `docker`, or `repo` with `managed: true`, `cyoda-local.sh stop '<PROJECT>'` first. Then delete the entry by its `PROJECT` key and [Finish](#finish):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh 'del(.projects[$k])' --arg k '<PROJECT>'
```

Not linked: say so and change nothing.

## Changing the config

Every change goes through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh '<jq filter>' --arg <name> '<value>' …`, values only as `--arg`; it writes atomically and keeps the file 0600. Non-zero exit: show its stderr.

- **Record an instance** for `<ROOT>`: `cyoda-config-write.sh '.projects[$k] = ((.projects[$k] // {}) + {run: $run, endpoint: $ep})' --arg k '<ROOT>' --arg run existing --arg ep '<E>'`
- **Write a profile** (keeps the other profiles and its `tokenCommand`): `cyoda-config-write.sh '.profiles[$p] = ((.profiles[$p] // {}) + {endpoint: $ep}) | .active = $p' --arg p '<PROFILE>' --arg ep '<ENDPOINT>'`
- A profile with a stored token (a `WARN=` says so): don't read or use it; remove it only when the developer asks: `cyoda-config-write.sh 'del(.profiles[$p].token)' --arg p '<P>'`.

## Finish

Run `cyoda-status.sh` again and report as in [Status](#status). After `cyoda-local.sh start` started or reused the instance: mock auth, no token needed. After `start-repo`: tokens as in [Link](#link) step 4. After connect while `SOURCE=project`: "This project is bound to `<ENDPOINT>` (its `projects` entry), which takes precedence here; the profile applies in other directories."
