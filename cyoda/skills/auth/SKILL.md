---
name: auth
description: Use when a cyoda-go call gets a 401/403 or the tokenCommand fails, when a cyoda-go instance that isn't running mock auth needs API tokens (M2M client, `cyoda token`, on-behalf-of), or when the developer's own app must obtain and renew cyoda-go tokens.
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-help.sh *) Bash(*cyoda-config-write.sh *) Bash(*cyoda-call.sh *) Bash(*get-token.sh*) Bash(curl *) Bash(jq *) Bash(ls *) Bash(cp *) Bash(chmod *) Bash(mv *) Bash(cmp *) Bash(*cyoda-local.sh *) Bash(*cyoda-docker-instances.sh*) Bash(cyoda *) Bash(brew *) Bash(command -v *) Bash(git rev-parse *) Bash(pwd *) Bash(cd * && pwd -P) Bash(sh)
---

# Cyoda auth (cyoda-go)

Sets up a **token script** in the developer's project and points the current binding's `tokenCommand` at it (this project's entry in the plugin config's `projects` map, or else the active profile). The plugin's scripts run it before each API call, so every call gets a fresh JWT.

The plugin stores no tokens or secrets: a profile or project entry holds only `endpoint` and `tokenCommand`, and the script reads the client credentials from the developer's environment or keychain.

Only M2M clients reach cyoda-go, each in one tenant; the first admin token comes from `cyoda token`, signed with the instance's signing key (`auth --section "ACCESS MODEL"`).

**Facts come from `cyoda help`.** Read sections with `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` and say which one you used.

## Step 0 — Connection

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. Show every `WARN=` line.
- `STATUS=not_configured` or `unreachable`: carry out `cyoda:setup`'s procedure yourself (read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`, *Getting an instance*), then run `cyoda-status.sh` again and go on.
- Note `PROFILE`, `ENDPOINT` and `SOURCE`; this run sets up that binding. `SOURCE=project`: it is this project's `projects` entry (`PROJECT=<dir>`, the entry's key). Another binding is set up after switching profiles or linking the project (`cyoda:setup`).

## Step 1 — Does it need a token?

`curl -s -o /dev/null -w '%{http_code}' --max-time 5 "<ENDPOINT>/api/model/"`, with no token on purpose.

- `200`: **mock auth. No token needed.** Say so, write nothing, and stop. If the developer wants to try JWT mode locally, that's server config: read `cyoda-help.sh config auth --section OPTIONS` (subsections "JWT mode" and "First admin token") and give them the concrete settings. Once the server runs with them, this procedure applies.
- `401` / `403`: continue.
- Anything else: show it and stop.

## Step 2 — Choose the path

Read `cyoda-help.sh auth --section "WHICH PATH DO I NEED?"`. The plugin's own calls use one of these; ask which fits unless the request already says:

| Path | Read | `tokenCommand` |
|---|---|---|
| M2M client (`client_id` / secret, tenant) | `auth clients` PREREQUISITES; `auth tokens` REQUEST FLOW | the template, as below |
| The developer holds the instance's signing key (e.g. their own local JWT instance) | `cli token` | `CYODA_JWT_SIGNING_KEY_FILE=<key file> cyoda token --tenant <TENANT> --roles ROLE_ADMIN,ROLE_M2M`: skip to Step 5, testing that command instead of the script |

On-behalf-of (token exchange for the app's signed-in users) is the app's own flow: Step 7.

**No client yet (M2M)?** Creating one needs a `ROLE_ADMIN` token of its tenant: `cyoda token --tenant <TENANT>`, run where the signing key is (`cli token` EXAMPLES: locally, `docker compose exec -T`, `kubectl exec`), by the developer or the operator who holds it (`auth clients --section PREREQUISITES`). The developer runs this in their own terminal, keeping the secret out of the conversation; it saves the response to a 0600 file outside the project and prints only `client_id`:

```bash
( umask 077; mkdir -p ~/.secrets; R=~/.secrets/cyoda-<PROFILE>-client.json
  curl -sS --fail-with-body -o "$R" -X POST "<ENDPOINT>/api/clients?clientId=<CLIENT_ID>" \
    -H @<(printf 'Authorization: Bearer %s\n' "$(<ADMIN_TOKEN_COMMAND>)") \
    && jq -r .client_id "$R" || cat "$R" )
```

`409 M2M_CLIENT_EXISTS`: the id is taken in that tenant (`auth clients --section "REQUEST FLOW"`). Then `CYODA_CLIENT_ID` is the printed id and `CYODA_CLIENT_SECRET_CMD` is `jq -r .client_secret ~/.secrets/cyoda-<PROFILE>-client.json` (or they move the secret into their keychain). Continue at Step 3.

## Step 3 — Credentials stay with the developer

The script reads:

| Variable | Holds |
|---|---|
| `CYODA_TENANT` | the client's tenant |
| `CYODA_CLIENT_ID` | client id |
| `CYODA_CLIENT_SECRET` | secret, **or** instead: |
| `CYODA_CLIENT_SECRET_CMD` | a command that prints the secret, e.g. `security find-generic-password -s cyoda-<profile> -w` (macOS Keychain), `secret-tool lookup service cyoda-<profile>` (Linux), `pass show cyoda/<profile>`. Takes precedence |
| `CYODA_ENDPOINT` | set automatically from the profile by the plugin's scripts |

The agent never receives the secret, and writes neither the secret nor a token to any file: the developer sets `CYODA_CLIENT_SECRET` or `CYODA_CLIENT_SECRET_CMD` in their own shell. Whether they are set shows in the Step 5 test (`… is not set`). If not, the developer sets them in the shell they start Claude Code from (shell profile, or `.envrc` with direnv), then restarts the session: the plugin's scripts inherit that environment.

## Step 4 — Write the script into the project

1. **Where:** if the project root has a `scripts/` dir (`ls -d scripts`), use `scripts/get-token.sh`; otherwise `get-token.sh` at the project root.
2. **Copy** `${CLAUDE_PLUGIN_ROOT}/skills/auth/templates/get-token.sh` there and `chmod +x` it. If a file with that name exists and differs (`cmp`), keep it and use it (test it as usual in Step 5), say so in one line, and never overwrite it.

## Step 5 — Test before saving

Run it once without showing the token:

```bash
( set -o pipefail; CYODA_ENDPOINT="<ENDPOINT>" "<ABS_PATH>" | awk -F. '{print NF " parts, " length($0) " chars"}' ); echo "exit=$?"
```

`exit=0` and `3 parts`: it works, go to Step 6. `exit=1`: show the `get-token:` line from stderr, explain it from the table in a line or two, then stop and wait; test again when the developer says it's fixed. Step 6 runs only after a passing test.

| stderr says | Meaning |
|---|---|
| `HTTP 401 … invalid_client` | tenant, id or secret rejected (or the client was deleted or its secret reset, `auth clients` REQUEST FLOW): the developer corrects the env or keychain value in their shell, then restarts the session |
| `HTTP 400` | malformed request or grant (`auth tokens --section ERRORS`) |
| `HTTP 404` | wrong endpoint (check the profile's endpoint) |
| `HTTP 501` | the instance runs mock auth: no token needed |
| `… is not set` / `CYODA_CLIENT_SECRET_CMD failed` | the variable isn't in the session's environment: see Step 3 |
| `cannot reach` | endpoint down or wrong: run `cyoda-status.sh` and report its line |

## Step 6 — Point the profile at it

`SOURCE=project`: set `tokenCommand` on this project's entry only, keyed by `PROJECT` from Step 0. A path relative to the project root (e.g. `scripts/get-token.sh`) works there: the plugin runs it from the project root.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh '.projects[$k].tokenCommand = $tc' --arg k '<PROJECT>' --arg tc '<PATH>'
```

Otherwise set `tokenCommand` to the script's **absolute** path (or the `cyoda token` command from Step 2, with an absolute key path), on the profile from Step 0 only:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-config-write.sh '.profiles[$p].tokenCommand = $tc' --arg p '<PROFILE>' --arg tc '<ABS_PATH>'
```

`cyoda-config-write.sh` is the only way to change the config. Exit 1: show its stderr; exit 3: the config isn't writable, say so.

If another profile needs other credentials, its `tokenCommand` sets them in front of the same script, for example `CYODA_TENANT=shop CYODA_CLIENT_ID=ci CYODA_CLIENT_SECRET_CMD='security find-generic-password -s cyoda-staging -w' /abs/path/get-token.sh`.

Then verify with `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh GET /model/`. Exit 0: done. Exit 4: the token command failed in the plugin's shell (back to Step 3). Exit 22 with 403: the token lacks `ROLE_M2M` (a `cyoda token` without `--roles ROLE_ADMIN,ROLE_M2M`; `auth --section ROLES`).

## Step 7 — The developer's own app

Read `cyoda-help.sh auth integration` (the steps for its parts: backend acting for users, jobs, compute nodes; ERRORS AND RETRIES), and `auth tokens --section "REQUEST FLOW"`, then explain for the app's parts:
- One client per part. A part acting for its signed-in users uses an on-behalf-of client and a trusted key, and exchanges a user assertion per user; jobs and compute nodes use plain clients with `client_credentials`. A compute node can't open its stream with any other token.
- **No refresh token.** Mint again with the same grant when less than about 60 s remain (`expires_in`), and once more on a 401.
- `Authorization: Bearer <token>` on REST; a compute node sends it in gRPC metadata (`grpc --section CONNECTION`).

## Finish

Report: the script's path, the profile (or project entry) and its `tokenCommand`, and the verify result.

## Common mistakes

| Mistake | Fix |
|---|---|
| Relative `tokenCommand` in a machine-wide profile | Absolute path there; only a `projects` entry may use a path relative to the project root |
| Saving `tokenCommand` before the test passes | Test first (Step 5) |
| Writing a token script for a mock instance | Mock: "no token needed", stop |
| Telling the app to use a refresh token | There is none; mint again before expiry |
| Token URL `/api/oauth/token` | `/api/tenants/<tenant>/oauth/token`: the client's tenant |
