---
name: auth
description: Authenticate to Cyoda Cloud using OAuth 2.0 client credentials. Obtains a JWT token and saves it to ~/.config/cyoda/cyoda-plugin-config.json under a named profile. Includes production safety guard requiring explicit confirmation before storing production credentials. Only trigger for Cyoda-specific authentication — do not trigger for generic /login commands unrelated to Cyoda.
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(tee *) Bash(echo *) Bash(jq *) Bash(mkdir *)
---

## Cyoda Login

Reading current config:
```!
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default"); jq --arg p "$PROFILE" '.profiles[$p] // {"endpoint":"none"}' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo '{"endpoint":"none"}'
```

If `endpoint` is `none`: *"No Cyoda endpoint configured. Run `/cyoda:setup` first."* Stop.

**Step 1 — Select profile:**

List existing profiles:
```bash
jq -r '.profiles | keys[]' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "(none yet)"
```

Ask: *"Which profile should this token be saved under? Enter a name (e.g. `default`, `prod`) — existing profiles are updated, new names create a new profile."*

Set `PROFILE_NAME` to the user's answer.

**Step 2 — Confirm environment type:**

Ask: *"Is this a development or production environment?"*

If **production**: display this warning and require explicit confirmation:

> ⚠️ **Security warning**: You are about to store production credentials in `~/.config/cyoda/cyoda-plugin-config.json` on disk in plain text. Anyone with access to this machine can read them.
>
> Do you accept this risk? (yes/no)

If user answers anything other than `yes`: stop. Do not write any credentials. Suggest alternatives: *"You can set `CYODA_TOKEN` as an environment variable in your shell session instead — it won't be persisted to disk. Or use the Cyoda CLI's own credential store if available."*

**Important:** Always show the warning and explicitly ask `yes/no` — even if the user appeared to pre-accept in their initial message. The confirmation must be its own step.

**Step 3 — Explain and collect credentials:**

Explain what these credentials are:

> "`client_id` and `client_secret` are **machine-to-machine (M2M) credentials** — they identify your application or service to Cyoda, not a personal user account. They are used by automated pipelines, compute nodes, and any service calling the Cyoda API."

Ask: *"Do you already have a `client_id` and `client_secret`?"*

- **If yes**: collect them and proceed.
- **If no**: direct the user to [Cyoda AI Studio](https://ai.cyoda.net/) — ask it to "create a technical user". Return once credentials are available.

**Post-redeploy note**: if the environment was recently redeployed, existing technical users may have been deleted. If authentication fails and the environment was redeployed, recreate the technical user in AI Studio before retrying.

Ask for `client_id` and `client_secret` separately, one at a time. Do not echo the secret back in the conversation.

**Step 4 — Obtain JWT token:**

If the cyoda CLI is installed, first confirm the current-version endpoint:
```bash
which cyoda >/dev/null 2>&1 && cyoda help config auth --format=markdown 2>/dev/null | head -40
```

Then call the token endpoint using Basic auth (client credentials in the `Authorization` header, not the request body):

```bash
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default")
ENDPOINT=$(jq -r --arg p "$PROFILE" '.profiles[$p].endpoint' "$HOME/.config/cyoda/cyoda-plugin-config.json")
CREDENTIALS=$(printf "%s" "${CLIENT_ID}:${CLIENT_SECRET}" | base64)
TOKEN_RESPONSE=$(curl -sf -X POST "${ENDPOINT%/}/api/oauth/token" \
  -H "Authorization: Basic ${CREDENTIALS}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials")
echo "$TOKEN_RESPONSE"
```

If this returns 4xx/5xx: run `cyoda help config auth` to get the current-version endpoint for your installation. Do NOT try alternate paths — fix the one call based on what `cyoda help` tells you.

If the curl fails or returns an error: show the error and stop. Do not write partial credentials.

**Step 5 — Extract and write token:**

```bash
TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
[ -z "$TOKEN" ] && echo "Error: could not extract access_token from response — aborting." && exit 1
ENV_VALUE="development"  # or "production" based on Step 2

CONFIG_FILE="$HOME/.config/cyoda/cyoda-plugin-config.json"
mkdir -p "$HOME/.config/cyoda"
EXISTING=$(cat "$CONFIG_FILE" 2>/dev/null || echo "{\"active\":\"${PROFILE_NAME}\",\"profiles\":{}}")
EXISTING_PROFILE=$(echo "$EXISTING" | jq -r --arg p "$PROFILE_NAME" '.profiles[$p] // {}')
NEW_PROFILE=$(echo "$EXISTING_PROFILE" | jq --arg token "$TOKEN" --arg env "$ENV_VALUE" \
  '. + {"token": $token, "env": $env}')
echo "$EXISTING" | jq --arg p "$PROFILE_NAME" --argjson data "$NEW_PROFILE" \
  '.profiles[$p] = $data | .active = $p' > "$CONFIG_FILE"
```

If the write fails with a permission error (`mkdir` fails or the redirect is denied): do NOT attempt `sudo`, `chmod`, `chown`, or any other fix. Show:

> *"Couldn't write to `~/.config/cyoda/` — you may be running in a sandbox or restricted environment. Please grant write access to that directory and try again. Would you like help with that?"*

**Step 6 — Confirm:**

Report: *"Authenticated successfully. Token written to `~/.config/cyoda/cyoda-plugin-config.json` under profile `{PROFILE_NAME}`. Run `/cyoda:status` to verify the connection."*

If `.env` equals `production`: add prominent reminder — *"⚠️ You are now connected to a PRODUCTION instance. Changes made via `/cyoda:build` will affect live data."*
