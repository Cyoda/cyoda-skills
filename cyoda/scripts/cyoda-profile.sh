#!/usr/bin/env bash
# Resolve the active Cyoda connection profile and print it as one JSON object.
# Honours CYODA_PLUGIN_CONFIG. Exit 0 always, except invalid JSON (exit 1).
# No config file: an implicit `default` profile for the local instance.
# CYODA_DEFAULT_ENDPOINT overrides its endpoint; it exists for tests only.
# A config file that exists is used as it is (no implicit endpoint).
set -euo pipefail

CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"

if [ ! -f "$CONFIG" ]; then
  jq -cn --arg ep "${CYODA_DEFAULT_ENDPOINT:-http://localhost:8080}" '{
    profile: "default", endpoint: $ep, env: "development", tokenCommand: null,
    warnings: ["no saved profile; using the default local instance \($ep) — type /cyoda:setup to save it"]
  }'
  exit 0
fi

if ! jq -e . "$CONFIG" >/dev/null 2>&1; then
  echo "invalid config: $CONFIG" >&2
  exit 1
fi

jq -c '
  (.active // "default") as $p
  | (.profiles[$p] // {}) as $prof
  | {
      profile: $p,
      endpoint: ($prof.endpoint // null),
      env: ($prof.env // "development"),
      tokenCommand: ($prof.tokenCommand // null),
      warnings: (if ($prof | has("token")) then
        ["profile \($p) contains a stored token, which this plugin no longer reads; you can remove it"]
      else [] end)
    }' "$CONFIG"
