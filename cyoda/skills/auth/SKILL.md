---
name: auth
description: Use when the developer types /cyoda:auth to get API tokens for a cyoda-go instance that isn't running mock auth (M2M client, OIDC, trusted key, on-behalf-of), after a 401/403 or a failing tokenCommand, or to learn how their own app should obtain and renew cyoda-go tokens.
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-help.sh *) Bash(*cyoda-call.sh *) Bash(*get-token.sh*) Bash(curl *) Bash(jq *) Bash(ls *) Bash(cp *) Bash(chmod *) Bash(mv *) Bash(cmp *)
disable-model-invocation: true
---

# Cyoda auth (cyoda-go)

Sets up a **token script** in the developer's project and points the active profile's `tokenCommand` at it. The plugin's scripts run it before each API call, so every call gets a fresh JWT.

**The plugin stores no tokens or secrets.** The script reads the client credentials from the developer's own environment or keychain. A profile holds only `endpoint`, `env` and `tokenCommand`. Never ask the developer to paste a secret into the conversation, and never print a token.

**Facts come from `cyoda help`.** Read sections with `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` and say which one you used.

A Cloud or migration question: "That's not covered by this plugin."

## Step 0 — Connection

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. Show every `WARN=` line.
- `STATUS=not_configured` or `unreachable`: say "next, type `/cyoda:setup` to connect to the instance first" and stop.
- Note `PROFILE` and `ENDPOINT`; this run sets up that profile. To set up another one, the developer switches profiles with `/cyoda:setup` first.

## Step 1 — Does it need a token?

`curl -s -o /dev/null -w '%{http_code}' --max-time 5 "<ENDPOINT>/api/model/"`, with no token on purpose.

- `200`: **mock auth. No token needed.** Say so, write nothing, and stop. If the developer wants to try JWT mode locally, that's server config: read `cyoda-help.sh config auth --section OPTIONS` (subsections "JWT mode" and "Bootstrap M2M client") and give them the concrete settings. After they restart the server with it, they type `/cyoda:auth` again.
- `401` / `403`: continue.
- Anything else: show it and stop.

## Step 2 — Choose the path

Read `cyoda-help.sh auth --section "WHICH PATH DO I NEED?"`, summarise the four options in one line each, and ask which fits.

| Path | Read | Token script |
|---|---|---|
| M2M client (`client_id` / secret) | `auth clients` PREREQUISITES; `auth tokens` REQUEST FLOW | the template, as below |
| On behalf of a user (token exchange) | `auth tokens` REQUEST FLOW (token-exchange) | the template covers the M2M actor; the app does the exchange itself |
| Existing IdP (OIDC) | `auth oidc` PREREQUISITES, REQUEST FLOW | any command that prints an IdP JWT (e.g. the IdP's CLI) |
| Self-signed tokens (trusted key) | `auth trusted-keys` PREREQUISITES, REQUEST FLOW | the developer's own signing command |

For OIDC and trusted keys, help the developer write a command that prints one JWT on stdout, then continue at Step 5 with that command as the `tokenCommand`.

**No client yet (M2M)?** The operator either sets a bootstrap client in the server config (`config auth --section OPTIONS`, "Bootstrap M2M client") or creates one through `auth clients` REQUEST FLOW with an admin token. Creating one is a mutating call: send it through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh`, and on a production profile only after an explicit yes.

## Step 3 — Credentials stay with the developer

The script reads:

| Variable | Holds |
|---|---|
| `CYODA_CLIENT_ID` | client id |
| `CYODA_CLIENT_SECRET` | secret, **or** instead: |
| `CYODA_CLIENT_SECRET_CMD` | a command that prints the secret, e.g. `security find-generic-password -s cyoda-<profile> -w` (macOS Keychain), `secret-tool lookup service cyoda-<profile>` (Linux), `pass show cyoda/<profile>`. Takes precedence |
| `CYODA_ENDPOINT` | set automatically from the profile by the plugin's scripts |

Ask whether they're already set; don't echo their values to check. If not, tell the developer to set them **in the shell they start Claude Code from** (shell profile, or a gitignored `.envrc` with direnv), then restart the session. The plugin's shell inherits that environment, and an `export` run inside the session doesn't carry between calls. Prefer `CYODA_CLIENT_SECRET_CMD` with a keychain over a plain secret in a file.

## Step 4 — Write the script into the project

1. **Where:** if the project root has a `scripts/` dir (`ls -d scripts`), use `scripts/get-token.sh`; otherwise `get-token.sh` at the project root.
2. **Copy** `${CLAUDE_PLUGIN_ROOT}/skills/auth/templates/get-token.sh` there and `chmod +x` it. If a file with that name exists and differs (`cmp`), show the difference and ask before replacing it.
3. Tell the developer it holds no secret and can be committed. Their seed, verify and CI scripts can call it too.

## Step 5 — Test before saving

Run it once without showing the token:

```bash
CYODA_ENDPOINT="<ENDPOINT>" "<ABS_PATH>" | awk -F. '{print NF " parts, " length($0) " chars"}'
```

`3 parts`: it works. On exit 1, show the `get-token:` line from stderr and explain it in a line or two. **Don't save the `tokenCommand` and don't retry in a loop.** Wait for the developer to fix it, then test again.

| stderr says | Meaning |
|---|---|
| `HTTP 401 … invalid_client` | id or secret rejected: check the env or keychain values; the client may be deleted or its secret rotated (`auth clients` REQUEST FLOW) |
| `HTTP 400` | malformed request or grant (`auth tokens --section ERRORS`) |
| `HTTP 404` | wrong endpoint, or the instance has no token endpoint (check the profile's endpoint) |
| `… is not set` / `CYODA_CLIENT_SECRET_CMD failed` | the variable isn't in the session's environment: see Step 3 |
| `cannot reach` | endpoint down or wrong: type `/cyoda:status` |

## Step 6 — Point the profile at it

Set `tokenCommand` to the script's **absolute** path, on the profile from Step 0 only:

```bash
CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"
jq --arg p "<PROFILE>" --arg tc "<ABS_PATH>" '.profiles[$p].tokenCommand = $tc' \
  "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
```

If another profile needs other credentials, its `tokenCommand` can set them in front of the same script, for example `CYODA_CLIENT_ID=prod-ci CYODA_CLIENT_SECRET_CMD='security find-generic-password -s cyoda-prod -w' /abs/path/get-token.sh`. That keeps a staging secret away from prod, and still stores no secret.

Then verify with `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh GET /model/`. Exit 0: done. Exit 4: the token command failed in the plugin's shell (back to Step 3). Exit 22 with 403: the client lacks a role (`auth tokens --section ERRORS`).

## Step 7 — The developer's own app

Read `cyoda-help.sh auth tokens --section "REQUEST FLOW"` and `--section TOKEN`, then explain:
- **cyoda-go issues no refresh token** (`cyoda help auth tokens`, REQUEST FLOW). The app mints a new token with the same grant before the current one expires (`expires_in` in the response), and on a 401 it mints a new one once and retries.
- It sends the token as `Authorization: Bearer <token>` on REST. A compute node sends it in gRPC metadata (`cyoda help grpc --section CONNECTION`).
- The app reads the credentials from its own runtime config or secret store, not from this script.

## Finish

Report: the script's path, the profile and its `tokenCommand`, and the verify result. Then hand off with a one-line reason: "next, type `/cyoda:build` to register your entity models", or "type `/cyoda:status`" to re-check the connection.

## Common mistakes

| Mistake | Fix |
|---|---|
| Asking for the secret in chat, or writing it to a file | Env var or `CYODA_CLIENT_SECRET_CMD` in the developer's shell |
| Printing the token to check it | Count its parts with `awk` |
| Relative `tokenCommand` | Absolute path; the scripts run from any directory |
| Saving `tokenCommand` before the test passes | Test first (Step 5) |
| Writing a token script for a mock instance | Mock: "no token needed", stop |
| Telling the app to use a refresh token | There is none; mint again before expiry |
