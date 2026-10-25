#!/usr/bin/env bash
# Resolve the Cyoda connection for this directory and print it as one JSON object:
# {profile, endpoint, env, tokenCommand, warnings, source, projectDir?}.
# Lookup order:
#   1. CYODA_PROFILE=<name>: that machine-wide profile, over everything (unknown: exit 1).
#   2. Project binding: the nearest <dir>/.cyoda/instance.json (or the legacy
#      .cyoda/config, endpoint and env only) from $PWD upwards. The search stops
#      at the git repo root or below $HOME, whichever comes first; $HOME itself
#      and its ancestors are never searched. Outside $HOME with no git repo, only
#      $PWD is checked. source "project", profile = basename. Its tokenCommand is
#      dropped, with a warning, unless the file is yours, not group/world-writable
#      and not tracked by git.
#   3. The active profile in CYODA_PLUGIN_CONFIG (source "profile").
#   4. No config file: an implicit `default` for the local instance (source
#      "default"). CYODA_DEFAULT_ENDPOINT overrides its endpoint; it exists for tests only.
# A config file that exists is used as it is (no implicit endpoint).
# Exit 0, except invalid JSON or an unknown CYODA_PROFILE (exit 1).
set -euo pipefail

CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"
WANT="${CYODA_PROFILE:-}"

check_json() { # file
  if ! jq -e 'type == "object"' "$1" >/dev/null 2>&1; then
    echo "invalid config: $1" >&2
    exit 1
  fi
}

stored_token_warning() { # label
  printf '%s contains a stored token, which this plugin no longer reads; you can remove it' "$1"
}

has_binding() { [ -f "$1/.cyoda/instance.json" ] || [ -f "$1/.cyoda/config" ]; }

# Echo the physical path of the nearest project dir with a binding file, or nothing.
find_project() {
  local dir home top=""
  dir="$(pwd -P)"
  home="$(cd "$HOME" 2>/dev/null && pwd -P)" || home="${HOME%/}"
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
  # Outside $HOME and outside any git repo there is no safe upper bound: $PWD only.
  if [ -z "$top" ]; then
    case "$dir/" in
      "$home"/*) ;;
      *) case "$home/" in "$dir"/*) return 0 ;; esac
         if has_binding "$dir"; then printf '%s\n' "$dir"; fi
         return 0 ;;
    esac
  fi
  while :; do
    # $HOME and every ancestor of it are out of bounds.
    if [ "$dir" = "/" ] || [ "$dir" = "$home" ]; then return 0; fi
    case "$home/" in "$dir"/*) return 0 ;; esac
    if has_binding "$dir"; then
      printf '%s\n' "$dir"
      return 0
    fi
    if [ -n "$top" ] && [ "$dir" = "$top" ]; then return 0; fi
    dir="$(dirname "$dir")"
  done
}

# A project file's tokenCommand runs commands as the developer, so it is used only
# from a file the developer owns, that no one else can write, and that git doesn't
# track (anyone with commit access could change it). Echo why not, or nothing.
untrusted_reason() { # project-dir file
  local f="$2"
  if [ -z "$(find -H "$f" -maxdepth 0 -user "$(id -u)" 2>/dev/null)" ]; then
    echo "the file is not owned by you"
  elif [ -n "$(find -H "$f" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" ]; then
    echo "the file is group- or world-writable; run chmod 600 on it"
  elif git -C "$1" ls-files --error-unmatch -- .cyoda/instance.json >/dev/null 2>&1; then
    echo "the file is tracked by git; run git rm --cached on it and keep .cyoda/ in .gitignore"
  fi
}

has_token() { jq -e 'type == "object" and has("token")' "$1" >/dev/null 2>&1; }

project_json() { # dir
  local dir="$1" inst="$1/.cyoda/instance.json" legacy="$1/.cyoda/config" src tc="" why
  local warns=()
  if [ -f "$inst" ]; then
    # instance.json wins; the legacy file is only checked for a stored token.
    check_json "$inst"
    src="$inst"
    if [ -f "$legacy" ] && has_token "$legacy"; then warns+=("$(stored_token_warning "$legacy")"); fi
    if has_token "$inst"; then warns+=("$(stored_token_warning "$inst")"); fi
    tc="$(jq -r '.tokenCommand // empty' "$inst")"
    if [ -n "$tc" ]; then
      why="$(untrusted_reason "$dir" "$inst")"
      if [ -n "$why" ]; then warns+=("tokenCommand in $inst ignored: $why"); tc=""; fi
    fi
  else
    # Legacy .cyoda/config: endpoint and env only, never a tokenCommand.
    check_json "$legacy"
    src="$legacy"
    if has_token "$legacy"; then warns+=("$(stored_token_warning "$legacy")"); fi
  fi
  jq -c --arg name "$(basename "$dir")" --arg dir "$dir" --arg tc "$tc" \
      --argjson warnings "$(printf '%s\n' ${warns[@]+"${warns[@]}"} | jq -Rn '[inputs | select(length > 0)]')" '{
    profile: $name,
    endpoint: (.endpoint // null),
    env: (.env // "development"),
    tokenCommand: (if $tc == "" then null else $tc end),
    warnings: $warnings,
    source: "project",
    projectDir: $dir
  }' "$src"
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

default_json() {
  jq -cn --arg ep "${CYODA_DEFAULT_ENDPOINT:-http://localhost:8080}" '{
    profile: "default", endpoint: $ep, env: "development", tokenCommand: null,
    warnings: ["no saved profile; using the default local instance \($ep) — type /cyoda:setup to save it"],
    source: "default"
  }'
}

# 1. Explicit machine-wide profile.
if [ -n "$WANT" ]; then
  if [ ! -f "$CONFIG" ]; then
    if [ "$WANT" = "default" ]; then default_json; exit 0; fi
    echo "CYODA_PROFILE=$WANT: no such profile (no config at $CONFIG)" >&2
    exit 1
  fi
  check_json "$CONFIG"
  if ! jq -e --arg p "$WANT" '.profiles | has($p)' "$CONFIG" >/dev/null 2>&1; then
    echo "CYODA_PROFILE=$WANT: no such profile in $CONFIG (profiles: $(jq -r '(.profiles // {}) | keys | join(", ")' "$CONFIG"))" >&2
    exit 1
  fi
  profile_json "$WANT"
  exit 0
fi

# 2. Project binding.
PROJECT="$(find_project)"
if [ -n "$PROJECT" ]; then
  project_json "$PROJECT"
  exit 0
fi

# 3./4. Active machine-wide profile, or the implicit default.
if [ ! -f "$CONFIG" ]; then
  default_json
  exit 0
fi
check_json "$CONFIG"
profile_json "$(jq -r '.active // "default"' "$CONFIG")"
