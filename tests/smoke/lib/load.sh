#!/usr/bin/env bash
# Example-loading helpers for smoke scenarios. Source after assert.sh/server.sh.
# Uses plain curl so it does not depend on seed.sh. Requires BASE (server.sh).
_LOAD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# load_example <skill> <name>  -> sets EX_DIR, exports SCHEMA_VERSION
load_example() {
  EX_DIR="$_LOAD_ROOT/cyoda/skills/$1/examples/$2"
  SCHEMA_VERSION="$(cyoda help workflows schema-version versions | jq -r .current)"
  export SCHEMA_VERSION
  [ -d "$EX_DIR" ] || { echo "load_example: missing $EX_DIR" >&2; return 1; }
}

# _req <curl args...>: prints HTTP status; response body goes to $_LOAD_BODY
_LOAD_BODY="$(mktemp)"
_req() { curl -s -o "$_LOAD_BODY" -w '%{http_code}' "$@"; }

# seed_model <entity> <version> <dir>
# Canonical order: import sample -> unique keys -> lock -> changeLevel -> workflow.
seed_model() {
  local e="$1" v="$2" d="$3" code
  code="$(_req -X POST -H 'Content-Type: application/json' --data-binary @"$d/sample.json" "$BASE/model/import/JSON/SAMPLE_DATA/$e/$v")"
  [ "$code" = 200 ] || { echo "seed_model: import sample -> $code $(cat "$_LOAD_BODY")" >&2; return 1; }
  if [ -f "$d/config.json" ]; then
    local uk; uk="$(jq -c '{uniqueKeys: (.uniqueKeys // [])}' "$d/config.json")"
    if [ "$(jq '.uniqueKeys|length' <<<"$uk")" -gt 0 ]; then
      code="$(_req -X PUT -H 'Content-Type: application/json' -d "$uk" "$BASE/model/$e/$v/unique-keys")"
      [ "$code" = 200 ] || { echo "seed_model: unique-keys -> $code $(cat "$_LOAD_BODY")" >&2; return 1; }
    fi
  fi
  code="$(_req -X PUT "$BASE/model/$e/$v/lock")"
  [ "$code" = 200 ] || { echo "seed_model: lock -> $code $(cat "$_LOAD_BODY")" >&2; return 1; }
  if [ -f "$d/config.json" ]; then
    local cl; cl="$(jq -r '.changeLevel // empty' "$d/config.json")"
    if [ -n "$cl" ]; then
      code="$(_req -X POST "$BASE/model/$e/$v/changeLevel/$cl")"
      [ "$code" = 200 ] || { echo "seed_model: changeLevel -> $code $(cat "$_LOAD_BODY")" >&2; return 1; }
    fi
  fi
  code="$(envsubst '${SCHEMA_VERSION}' <"$d/workflow.json" | _req -X POST -H 'Content-Type: application/json' --data-binary @- "$BASE/model/$e/$v/workflow/import")"
  [ "$code" = 200 ] || { echo "seed_model: workflow import -> $code $(cat "$_LOAD_BODY")" >&2; return 1; }
}

# create_entity <entity> <version> <json> -> echoes id
create_entity() {
  curl -s -X POST -H 'Content-Type: application/json' -d "$3" "$BASE/entity/JSON/$1/$2" | jq -r '.[0].entityIds[0]'
}

# entity_state <id> -> echoes .meta.state
entity_state() { curl -s "$BASE/entity/$1" | jq -r '.meta.state'; }

# patch_transition <id> <name> [json]  (default {})
patch_transition() {
  local body="${3-}"; [ -n "$body" ] || body='{}'
  curl -s -X PATCH -H 'Content-Type: application/merge-patch+json' -H 'If-Match: *' \
    -d "$body" "$BASE/entity/JSON/$1/$2"
}

# loopback <id> <json>: merge-patch without a transition name
loopback() {
  curl -s -X PATCH -H 'Content-Type: application/merge-patch+json' -H 'If-Match: *' \
    -d "$2" "$BASE/entity/JSON/$1"
}

# wait_state <id> <state> <timeout_s>: poll every 500 ms; echoes final state
wait_state() {
  local i s n=$(( $3 * 2 ))
  for i in $(seq 1 "$n"); do
    s="$(entity_state "$1")"
    [ "$s" = "$2" ] && break
    sleep 0.5
  done
  echo "$s"
}
