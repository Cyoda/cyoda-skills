#!/usr/bin/env bash
# Resolve the Cyoda connection for this directory and print it as one JSON object:
# {profile, endpoint, env, tokenCommand, warnings, source, projectDir?}.
# Lookup order:
#   1. CYODA_PROFILE=<name>: that machine-wide profile, over everything (unknown: exit 1).
#   2. Project binding: the nearest <dir>/.cyoda/instance.json (or the legacy
#      .cyoda/config, endpoint and env only) from $PWD upwards. The search stops
#      at the git repo root or below $HOME, whichever comes first; $HOME itself
#      and its ancestors are never searched. Outside $HOME with no git repo, only
#      $PWD is checked. source "project", profile = basename. A binding that is a
#      symlink (file or .cyoda), not yours, group/world-writable (file or .cyoda),
#      inside a .cyoda repo/submodule, or tracked by git (any letter case) is
#      ignored entirely, with a warning, and the lookup falls through to 3./4.
#   3. The active profile in CYODA_PLUGIN_CONFIG (source "profile").
#   4. No config file: an implicit `default` for the local instance (source
#      "default"). CYODA_DEFAULT_ENDPOINT overrides its endpoint; it exists for tests only.
# A config file that exists is used as it is (no implicit endpoint).
# Exit 0, except invalid JSON or an unknown CYODA_PROFILE (exit 1).
set -euo pipefail

CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"
WANT="${CYODA_PROFILE:-}"

# Every git call: never run a repo's fsmonitor hook, never take optional locks.
g() { git --no-optional-locks -c core.fsmonitor=false "$@"; }

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
  top="$(g rev-parse --show-toplevel 2>/dev/null)" || top=""
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

# A project file can be planted, committed or cloned in by someone else, and it
# chooses where calls go and which command runs as the developer. Fail closed:
# echo why it is not trusted, or nothing.
owned()   { [ -n "$(find "$1" -maxdepth 0 -user "$(id -u)" 2>/dev/null)" ]; }
shared_w() { [ -n "$(find "$1" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" ]; }
# in_repo <dir>: inside a git work tree. Without git, any .git above counts as one.
in_repo() {
  if command -v git >/dev/null 2>&1; then
    [ "$(g -C "$1" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]
    return
  fi
  local d="$1"
  while :; do [ -e "$d/.git" ] && return 0; [ "$d" = / ] && return 1; d="$(dirname "$d")"; done
}
# tracked <dir> <pathspec>: 0 tracked, 1 not tracked, 2 could not tell
tracked() {
  local rc=0
  g -C "$1" ls-files --error-unmatch -- "$2" >/dev/null 2>&1 || rc=$?
  case "$rc" in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
}
untrusted_reason() { # project-dir binding-basename
  local pdir="$1" base="$2" cdir="$1/.cyoda" f="$1/.cyoda/$2" real rc
  if [ -L "$cdir" ] || [ -L "$f" ]; then echo "symlink"; return; fi
  if ! owned "$cdir"; then echo ".cyoda directory not owned by you"; return; fi
  if shared_w "$cdir"; then echo ".cyoda directory is group- or world-writable (run chmod 700 on it)"; return; fi
  if ! owned "$f"; then echo "not owned by you"; return; fi
  if shared_w "$f"; then echo "group- or world-writable (run chmod 600 on it)"; return; fi
  real="$(cd "$cdir" && pwd -P)" || { echo "cannot resolve .cyoda"; return; }
  in_repo "$real" || return 0
  command -v git >/dev/null 2>&1 || { echo "git is not available to check whether it is tracked"; return; }
  # .cyoda as its own repo or submodule root, or a gitlink in the superproject.
  if [ "$(g -C "$real" rev-parse --show-toplevel 2>/dev/null)" = "$real" ] \
     || g -C "$pdir" ls-files --stage -- ':(icase).cyoda' 2>/dev/null | grep -q '^160000 '; then
    echo ".cyoda is a git repository or submodule"; return
  fi
  # Tracked under any letter case, seen from the file's real dir and from the project root.
  for spec in "$real|:(icase)$base" "$pdir|:(icase).cyoda/$base"; do
    rc=0; tracked "${spec%%|*}" "${spec#*|}" || rc=$?
    if [ "$rc" -eq 0 ]; then echo "tracked by git (run git rm --cached on it and keep .cyoda/ in .gitignore)"; return; fi
    if [ "$rc" -eq 2 ] && in_repo "${spec%%|*}"; then echo "git could not check whether it is tracked"; return; fi
  done
}

has_token() { jq -e 'type == "object" and has("token")' "$1" >/dev/null 2>&1; }

project_json() { # dir (its binding file already passed untrusted_reason)
  local dir="$1" inst="$1/.cyoda/instance.json" legacy="$1/.cyoda/config" src tc=""
  local warns=()
  if [ -f "$inst" ]; then
    # instance.json wins; the legacy file is only checked for a stored token.
    check_json "$inst"
    src="$inst"
    if [ -f "$legacy" ] && has_token "$legacy"; then warns+=("$(stored_token_warning "$legacy")"); fi
    if has_token "$inst"; then warns+=("$(stored_token_warning "$inst")"); fi
    tc="$(jq -r '.tokenCommand // empty' "$inst")"
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

# 2. Project binding, if its file is trusted; an untrusted one is ignored entirely.
IGNORED='[]'
PROJECT="$(find_project)"
if [ -n "$PROJECT" ]; then
  BASE="instance.json"; [ -f "$PROJECT/.cyoda/$BASE" ] || BASE="config"
  REL=".cyoda/$BASE"
  WHY="$(untrusted_reason "$PROJECT" "$BASE")"
  if [ -z "$WHY" ]; then
    project_json "$PROJECT"
    exit 0
  fi
  IGNORED="$(jq -cn --arg w "ignoring $PROJECT/$REL: $WHY" '[$w]')"
fi
with_ignored() { jq -c --argjson x "$IGNORED" '.warnings = ($x + .warnings)'; }

# 3./4. Active machine-wide profile, or the implicit default.
if [ ! -f "$CONFIG" ]; then
  default_json | with_ignored
  exit 0
fi
check_json "$CONFIG"
profile_json "$(jq -r '.active // "default"' "$CONFIG")" | with_ignored
