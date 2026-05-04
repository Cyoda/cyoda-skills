---
name: status
description: Reports current Cyoda connection status. Shows "Connected to Local cyoda-go — vX.X.X", "Connected to Cyoda Cloud — vX.X.X [PRODUCTION]", or "Not connected". Use before any operation requiring an active Cyoda instance.
when_to_use: When the user asks about their Cyoda connection, at session start when Cyoda work is mentioned, or before build/test/migrate operations.
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(jq *)
---

## Cyoda Connection Status

Current config:
```!
jq . .cyoda/config 2>/dev/null || echo '{"endpoint":"none"}'
```

Checking reachability and version:
```!
ENDPOINT=$(jq -r '.endpoint // "none"' .cyoda/config 2>/dev/null || echo "none");
ENV=$(jq -r '.env // "development"' .cyoda/config 2>/dev/null || echo "development");
if [ -z "$ENDPOINT" ] || [ "$ENDPOINT" = "none" ]; then
  echo "STATUS=not_configured";
else
  VERSION=$(curl -sf --max-time 3 "${ENDPOINT%/}/api/help" 2>/dev/null | jq -r '.version // ""' 2>/dev/null);
  if [ -z "$VERSION" ]; then
    echo "STATUS=unreachable ENDPOINT=$ENDPOINT";
  else
    echo "STATUS=connected ENDPOINT=$ENDPOINT VERSION=$VERSION ENV=${ENV:-development}";
  fi;
fi
```

**Auth error rule:** If any API call returns 401 or 403, invoke `cyoda:auth` to refresh the token, then retry the request once. If the retry also fails, surface the error to the user. Do not retry on any other error code.

Report based on output:

- `STATUS=not_configured` → **"Not connected to Cyoda — run `/cyoda:setup` to get started"**
- `STATUS=unreachable` → **"Cyoda instance unreachable at {ENDPOINT} — is it running?"**
- `STATUS=connected`, `ENV=production` → **"⚠️ Connected to Cyoda Cloud [PRODUCTION] — v{VERSION}"**
- `STATUS=connected`, endpoint contains `localhost` → **"Connected to Local cyoda-go — v{VERSION}"**
- `STATUS=connected`, cloud endpoint → **"Connected to Cyoda Cloud — v{VERSION}"**
