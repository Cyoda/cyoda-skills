#!/usr/bin/env bash
# Resolve the Cyoda connection for this directory and print it as one JSON object:
# {profile, endpoint, env, tokenCommand, warnings, source, projectDir?}.
# Everything comes from CYODA_PLUGIN_CONFIG (default ~/.config/cyoda/cyoda-plugin-config.json):
#   1. CYODA_PROFILE=<name>: that profile, over everything (unknown: exit 1).
#   2. A "projects" entry whose key (a project dir) is $PWD or its nearest ancestor,
#      compared with -ef (same inode, so symlinks and letter case don't matter).
#      Only absolute keys for existing dirs owned by you count; keys whose dir is
#      gone are skipped silently, relative/~/newline/foreign keys with a warning.
#      source "project", profile = key's basename.
#   3. The active profile (source "profile").
#   4. No config, or one with no "active" and no "profiles": an implicit `default`
#      for the local instance (source "default"). CYODA_DEFAULT_ENDPOINT overrides
#      its endpoint; it exists for tests only.
# Nothing in the project tree is read. Exit 0, except invalid JSON, a malformed
# projects map, or an unknown CYODA_PROFILE (exit 1).
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

# Set KEY to the projects key for $PWD or its nearest ancestor (or ""). Only an
# absolute key for an existing dir you own can match: a relative or ~ key would
# resolve against $PWD, i.e. inside whatever repo you are in. Skipped keys warn.
WARNS=()
KEY=""
find_project() {
  local keys=() k dir
  if [ "$(jq '[(.projects // {}) | keys[] | select(test("\n"))] | length' "$CONFIG")" != 0 ]; then
    WARNS+=("a projects key contains a newline; skipped")
  fi
  while IFS= read -r k; do
    case "$k" in
      /*) if [ -d "$k" ]; then keys+=("$k"); fi ;;
      *) WARNS+=("projects key $k is not an absolute path; skipped") ;;
    esac
  done < <(jq -r '(.projects // {}) | keys[] | select(test("\n") | not)' "$CONFIG")
  [ ${#keys[@]} -gt 0 ] || return 0
  # A deleted or unreadable $PWD: no project.
  dir="$(pwd -P 2>/dev/null)" || return 0
  case "$dir" in /*) ;; *) return 0 ;; esac
  while :; do
    for k in "${keys[@]}"; do
      [ "$dir" -ef "$k" ] || continue
      if [ -O "$k" ]; then KEY="$k"; return 0; fi
      WARNS+=("projects entry $k skipped: the directory is not owned by you")
    done
    [ "$dir" = / ] && return 0
    dir="${dir%/*}"
    [ -n "$dir" ] || dir=/
  done
}

with_warns() {
  jq -c --argjson x "$(printf '%s\n' ${WARNS[@]+"${WARNS[@]}"} | jq -Rn '[inputs | select(length > 0)]')" \
    '.warnings = ($x + .warnings)'
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

BAD="$(jq -r '
  if has("projects") and (.projects | type) != "object" then "projects must be an object"
  else [(.projects // {}) | to_entries[]
        | select((.value | type) != "object" or (.value.endpoint | type) != "string")
        | "\(.key) needs an object with a string endpoint"] | first // empty
  end' "$CONFIG")"
if [ -n "$BAD" ]; then
  echo "invalid projects entry in $CONFIG: $BAD" >&2
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

find_project
if [ -n "$KEY" ]; then
  project_json "$KEY" | with_warns
  exit 0
fi

# No active profile and no profiles saved (e.g. only projects): the implicit default.
if ! jq -e 'has("active") or has("profiles")' "$CONFIG" >/dev/null; then
  default_json | with_warns
  exit 0
fi
profile_json "$(jq -r '.active // "default"' "$CONFIG")" | with_warns
