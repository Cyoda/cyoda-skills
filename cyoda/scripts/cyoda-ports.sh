#!/usr/bin/env bash
# Name a project's cyoda-go instance and pick a free port block for it.
#   cyoda-ports.sh name <root>  -> <basename>-<hash6>  (sanitised basename, sha256 of the real path)
#   cyoda-ports.sh pick <root>  -> HTTP=<p> GRPC=<p> ADMIN=<p> STATE=ours|free
# Blocks k=0..19: HTTP=B+100k, GRPC=B+1010+100k, ADMIN=B+1011+100k, B=${CYODA_PORT_BASE:-8080}.
# Free: no port of the block listens and no other project's entry records one.
# The project's recorded block comes first; STATE=ours needs evidence (binary: dataDir/cyoda.pid
# is a live process listening on the HTTP port; docker: a cyoda-docker-instances.sh line with
# COMPOSE_PROJECT=<instance> WORKDIR=<dataDir> on that HTTP port). Otherwise a busy block is skipped.
# Config: CYODA_PLUGIN_CONFIG (default ~/.config/cyoda/cyoda-plugin-config.json).
# A port also counts as busy when a TCP connect to 127.0.0.1 succeeds (lsof misses other users' listeners).
# Exit: 0 ok, 1 invalid plugin config, 3 no free block, 5 lsof missing (pick), 64 usage.
set -euo pipefail

CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"
BASE="${CYODA_PORT_BASE:-8080}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { echo "usage: cyoda-ports.sh name|pick <root>" >&2; exit 64; }
[ $# -eq 2 ] || usage
CMD="$1"
ROOT="$(cd "$2" 2>/dev/null && pwd -P)" || { echo "no such directory: $2" >&2; exit 64; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}

instance_name() {
  local base hash
  base="$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed -e 's/^-*//' -e 's/-*$//')"
  [ -n "$base" ] || base=cyoda
  hash="$(printf '%s' "$ROOT" | sha256 | cut -c1-6)"
  printf '%s-%s\n' "$base" "$hash"
}

listening() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1 && return 0
  if command -v timeout >/dev/null 2>&1; then
    timeout 1 bash -c ">/dev/tcp/127.0.0.1/$1" >/dev/null 2>&1
  else
    (exec 3>/dev/tcp/127.0.0.1/"$1") >/dev/null 2>&1
  fi
}

have_config() { [ -f "$CONFIG" ]; }

# Ports recorded by projects other than this one, one per line.
others_ports() {
  have_config || return 0
  jq -r --arg k "$ROOT" '(.projects // {}) | to_entries[] | select(.key != $k)
    | (.value.ports // {}) | select(type == "object" and ([.http, .grpc, .admin] | all(type == "number")))
    | [.http, .grpc, .admin][]' "$CONFIG"
}

entry() { # field -> value of this project's entry or ""
  have_config || return 0
  jq -r --arg k "$ROOT" --arg f "$1" '(.projects // {})[$k][$f] // "" | tostring' "$CONFIG"
}
rec_port() {
  have_config || return 0
  jq -r --arg k "$ROOT" --arg f "$1" '(.projects // {})[$k].ports
    | if type == "object" and ([.http, .grpc, .admin] | all(type == "number")) then .[$f] | tostring else "" end' "$CONFIG"
}

# Does this project's own instance run on HTTP port $1?
is_ours() {
  local http="$1" run dd inst pid
  run="$(entry run)"; dd="$(entry dataDir)"; inst="$(entry instance)"
  [ -n "$dd" ] || return 1
  case "$run" in
    binary)
      [ -f "$dd/cyoda.pid" ] || return 1
      pid="$(tr -dc '0-9' <"$dd/cyoda.pid")"
      [ -n "$pid" ] || return 1
      lsof -nP -a -p "$pid" -iTCP:"$http" -sTCP:LISTEN >/dev/null 2>&1
      ;;
    docker)
      command -v docker >/dev/null 2>&1 || return 1
      bash "$HERE/cyoda-docker-instances.sh" 2>/dev/null \
        | grep -F -e "COMPOSE_PROJECT=$inst WORKDIR=$dd ENDPOINT=" \
        | grep -qE "ENDPOINT=http://[^ ]*:$http IMAGE="
      ;;
    *) return 1 ;;
  esac
}

pick() {
  command -v lsof >/dev/null 2>&1 || { echo "cyoda-ports.sh: lsof is required" >&2; exit 5; }
  if have_config && ! jq -e 'type == "object"' "$CONFIG" >/dev/null 2>&1; then
    echo "invalid plugin config: $CONFIG" >&2; exit 1
  fi
  local others k http grpc admin cand=() rh
  others="$(others_ports)"
  rh="$(rec_port http)"
  if [ -n "$rh" ]; then cand+=("$(rec_port http) $(rec_port grpc) $(rec_port admin)"); fi
  for k in $(seq 0 19); do
    cand+=("$((BASE + 100 * k)) $((BASE + 1010 + 100 * k)) $((BASE + 1011 + 100 * k))")
  done
  local c p clash
  for c in "${cand[@]}"; do
    read -r http grpc admin <<<"$c"
    [ -n "$http" ] && [ -n "$grpc" ] && [ -n "$admin" ] || continue
    clash=""
    for p in $http $grpc $admin; do
      if grep -qx "$p" <<<"$others"; then clash=1; fi
    done
    [ -z "$clash" ] || continue
    if listening "$http" || listening "$grpc" || listening "$admin"; then
      if [ "$http" = "$rh" ] && is_ours "$http"; then
        echo "HTTP=$http GRPC=$grpc ADMIN=$admin STATE=ours"; return 0
      fi
      continue
    fi
    echo "HTTP=$http GRPC=$grpc ADMIN=$admin STATE=free"; return 0
  done
  echo "no free port block (base $BASE)" >&2
  return 3
}

case "$CMD" in
  name) instance_name ;;
  pick) pick ;;
  *) usage ;;
esac
