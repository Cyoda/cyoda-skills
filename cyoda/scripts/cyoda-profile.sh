#!/usr/bin/env bash
# Resolve the active Cyoda connection profile and print it as one JSON object.
# Honours CYODA_PLUGIN_CONFIG. Exit 0 always, except invalid JSON (exit 1).
set -euo pipefail

CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"

if [ ! -f "$CONFIG" ]; then
  echo '{"profile":"default","endpoint":null,"env":"development","tokenCommand":null,"warnings":[]}'
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
