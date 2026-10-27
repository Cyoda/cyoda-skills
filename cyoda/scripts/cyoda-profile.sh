#!/usr/bin/env bash
# Resolve the Cyoda connection for this directory and print it as one JSON object:
# {profile, endpoint, env, tokenCommand, warnings, source, projectDir?}.
# Everything comes from CYODA_PLUGIN_CONFIG (default ~/.config/cyoda/cyoda-plugin-config.json):
#   1. CYODA_PROFILE=<name>: that profile, over everything (unknown: exit 1).
#   2. A "projects" entry whose key (a project dir) is $PWD or its nearest ancestor,
#      compared with -ef (same inode, so symlinks and letter case don't matter).
#      Keys whose dir is gone are skipped. source "project", profile = key's basename.
#   3. The active profile (source "profile").
#   4. No config, or one with no "active" and no "profiles": an implicit `default`
#      for the local instance (source "default"). CYODA_DEFAULT_ENDPOINT overrides
#      its endpoint; it exists for tests only.
# Nothing in the project tree is read. Exit 0, except invalid JSON or an unknown
# CYODA_PROFILE (exit 1).
set -euo pipefail

CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"
WANT="${CYODA_PROFILE:-}"

default_json() {
  jq -cn --arg ep "${CYODA_DEFAULT_ENDPOINT:-http://localhost:8080}" '{
    profile: "default", endpoint: $ep, env: "development", tokenCommand: null,
    warnings: ["no saved profile; using the default local instance \($ep) — type /cyoda:setup to save it"],
    source: "default"
  }'
}

profile_json() { # name
  jq -c --arg p "$1" '
    (.profiles[$p] // {}) as $prof
    | {
        profile: $p,
        endpoint: ($prof.endpoint // null),
        env: ($prof.env // "development"),
        tokenCommand: ($prof.tokenCommand // null),
        warnings: (if ($prof | has("token")) then
          ["profile \($p) contains a stored token, which this plugin no longer reads; you can remove it"]
        else [] end),
        source: "profile"
      }' "$CONFIG"
}

project_json() { # key
  jq -c --arg k "$1" --arg name "$(basename "$1")" '
    .projects[$k] as $e
    | {
        profile: $name,
        endpoint: ($e.endpoint // null),
        env: ($e.env // "development"),
        tokenCommand: ($e.tokenCommand // null),
        warnings: [],
        source: "project",
        projectDir: $k
      }' "$CONFIG"
}

# Echo the projects key for $PWD or its nearest ancestor, or nothing.
find_project() {
  local keys=() k dir
  while IFS= read -r k; do [ -n "$k" ] && [ -d "$k" ] && keys+=("$k"); done \
    < <(jq -r '(.projects // {}) | keys[]' "$CONFIG")
  [ ${#keys[@]} -gt 0 ] || return 0
  dir="$(pwd -P)"
  while :; do
    for k in "${keys[@]}"; do
      if [ "$dir" -ef "$k" ]; then printf '%s\n' "$k"; return 0; fi
    done
    [ "$dir" = / ] && return 0
    dir="$(dirname "$dir")"
  done
}

if [ ! -f "$CONFIG" ]; then
  if [ -n "$WANT" ] && [ "$WANT" != "default" ]; then
    echo "CYODA_PROFILE=$WANT: no such profile (no config at $CONFIG)" >&2
    exit 1
  fi
  default_json
  exit 0
fi

if ! jq -e 'type == "object"' "$CONFIG" >/dev/null 2>&1; then
  echo "invalid config: $CONFIG" >&2
  exit 1
fi

if [ -n "$WANT" ]; then
  if ! jq -e --arg p "$WANT" '(.profiles // {}) | has($p)' "$CONFIG" >/dev/null; then
    echo "CYODA_PROFILE=$WANT: no such profile in $CONFIG (profiles: $(jq -r '(.profiles // {}) | keys | join(", ")' "$CONFIG"))" >&2
    exit 1
  fi
  profile_json "$WANT"
  exit 0
fi

KEY="$(find_project)"
if [ -n "$KEY" ]; then
  project_json "$KEY"
  exit 0
fi

if ! jq -e 'has("active") or has("profiles")' "$CONFIG" >/dev/null; then
  default_json
  exit 0
fi
profile_json "$(jq -r '.active // "default"' "$CONFIG")"
