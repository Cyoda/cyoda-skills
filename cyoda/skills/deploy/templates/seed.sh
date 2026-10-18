#!/usr/bin/env bash
# Seed a cyoda-go instance with the project's entity models and workflows.
# Idempotent: a model already LOCKED at that version is skipped; workflows are
# always re-imported with importMode REPLACE.
#
# Usage: seed.sh --manifest <path/to/cyoda-manifest.json> --env <name>
#
# Source: the files `/cyoda:build` keeps, listed in cyoda-manifest.json (paths
# relative to the manifest's directory). Per entity, in canonical order
# (cyoda help models LIFECYCLE / ENDPOINTS, cyoda help workflows IMPORT REQUEST):
#   1. GET /model/: LOCKED at this version -> skip steps 2-5
#   2. import the sample (SAMPLE_DATA)
#   3. PUT unique-keys, if any (allowed only while UNLOCKED)
#   4. lock
#   5. changeLevel, if not null. The config's env.<name> value wins over the
#      base value; null means none (strict schema).
#   6. import the workflow as {"importMode":"REPLACE","workflows":[...]}, with
#      ${SCHEMA_VERSION} set from GET /help/workflows/schema-version/versions
#
# Environment:
#   CYODA_ENDPOINT       instance base URL, no /api (required)
#   CYODA_TOKEN_COMMAND  command that prints a JWT, run once with CYODA_ENDPOINT
#                        set (optional; unset = no auth header, for mock auth)
#
# Output: "SEEDED <entity> v<n>" or "SKIPPED-MODEL <entity> v<n> (locked)",
# then "WORKFLOW <entity> v<n>". Exit 1 on the first HTTP >= 400, with the
# response body; exit 2 on a usage error.
set -euo pipefail

usage() { echo "usage: seed.sh --manifest <cyoda-manifest.json> --env <name>" >&2; exit 2; }
fail() { echo "seed: $*" >&2; exit 1; }

MANIFEST=""
ENV_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) [ $# -ge 2 ] || usage; MANIFEST="$2"; shift 2 ;;
    --env) [ $# -ge 2 ] || usage; ENV_NAME="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$MANIFEST" ] && [ -n "$ENV_NAME" ] || usage
[ -f "$MANIFEST" ] || fail "manifest not found: $MANIFEST"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"

ENDPOINT="${CYODA_ENDPOINT:-}"
[ -n "$ENDPOINT" ] || fail "CYODA_ENDPOINT is not set (instance base URL, e.g. http://localhost:8080)"
ENDPOINT="${ENDPOINT%/}"
ENDPOINT="${ENDPOINT%/api}"
API="$ENDPOINT/api"
ROOT="$(cd "$(dirname "$MANIFEST")" && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

AUTH=()
if [ -n "${CYODA_TOKEN_COMMAND:-}" ]; then
  # Same contract as the plugin's cyoda-call.sh: the command sees CYODA_ENDPOINT.
  TOKEN="$(CYODA_ENDPOINT="$ENDPOINT" bash -c "$CYODA_TOKEN_COMMAND")" || fail "token command failed: $CYODA_TOKEN_COMMAND"
  [ -n "$TOKEN" ] || fail "token command printed nothing: $CYODA_TOKEN_COMMAND"
  AUTH=(-H "Authorization: Bearer $TOKEN")
fi

# req <METHOD> <PATH> [curl args...]: body -> $BODY. Exits 1 on HTTP >= 400.
req() {
  local m="$1" p="$2" out code
  shift 2
  out="$(curl -sS -X "$m" ${AUTH[@]+"${AUTH[@]}"} -w $'\n%{http_code}' "$@" "$API$p")" || fail "cannot reach $API$p"
  code="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
  if [ "$code" -ge 400 ] 2>/dev/null || [ "$code" = 000 ]; then
    echo "FAIL $m $p -> HTTP $code" >&2
    printf '%s\n' "$BODY" >&2
    exit 1
  fi
}

file_of() { # file_of <entity-json> <key>: absolute path of a manifest file entry
  local rel
  rel="$(jq -r --arg k "$2" '.[$k] // empty' <<<"$1")"
  [ -n "$rel" ] || return 0
  case "$rel" in /*) echo "$rel" ;; *) echo "$ROOT/$rel" ;; esac
}

req GET /help/workflows/schema-version/versions
SCHEMA_VERSION="$(jq -r '.current // empty' <<<"$BODY")"
[ -n "$SCHEMA_VERSION" ] || fail "no .current in /help/workflows/schema-version/versions: $BODY"

req GET /model/
MODELS="$BODY"

COUNT="$(jq '.entities | length' "$MANIFEST")" || fail "cannot read $MANIFEST"
i=0
while [ "$i" -lt "$COUNT" ]; do
  ENT="$(jq -c ".entities[$i]" "$MANIFEST")"
  i=$((i + 1))
  E="$(jq -r '.name' <<<"$ENT")"
  V="$(jq -r '.modelVersion' <<<"$ENT")"
  SAMPLE="$(file_of "$ENT" sample)"
  WORKFLOW="$(file_of "$ENT" workflow)"
  CONFIG="$(file_of "$ENT" config)"
  [ -n "$SAMPLE" ] && [ -f "$SAMPLE" ] || fail "$E v$V: sample file not found: ${SAMPLE:-<none in manifest>}"
  [ -n "$WORKFLOW" ] && [ -f "$WORKFLOW" ] || fail "$E v$V: workflow file not found: ${WORKFLOW:-<none in manifest>}"
  if [ -n "$CONFIG" ]; then
    [ -f "$CONFIG" ] || fail "$E v$V: config file not found: $CONFIG"
  else
    CONFIG="$TMP/empty-config.json"
    echo '{}' > "$CONFIG"
  fi

  STATE="$(jq -r --arg n "$E" --argjson v "$V" \
    '[.[] | select(.modelName == $n and .modelVersion == $v)][0].currentState // "MISSING"' <<<"$MODELS")"

  if [ "$STATE" = LOCKED ]; then
    echo "SKIPPED-MODEL $E v$V (locked)"
  else
    # Effective settings: env.<name> keys override the base values.
    jq --arg env "$ENV_NAME" '
      (.env[$env] // {}) as $o
      | {uniqueKeys: (if ($o | has("uniqueKeys")) then $o.uniqueKeys else (.uniqueKeys // []) end),
         changeLevel: (if ($o | has("changeLevel")) then $o.changeLevel else .changeLevel end)}' \
      "$CONFIG" > "$TMP/effective.json" || fail "$E v$V: cannot read config $CONFIG"

    req POST "/model/import/JSON/SAMPLE_DATA/$E/$V" -H 'Content-Type: application/json' --data-binary @"$SAMPLE"
    if [ "$(jq '.uniqueKeys | length' "$TMP/effective.json")" -gt 0 ]; then
      jq '{uniqueKeys}' "$TMP/effective.json" > "$TMP/unique-keys.json"
      req PUT "/model/$E/$V/unique-keys" -H 'Content-Type: application/json' --data-binary @"$TMP/unique-keys.json"
    fi
    req PUT "/model/$E/$V/lock"
    CL="$(jq -r '.changeLevel // empty' "$TMP/effective.json")"
    if [ -n "$CL" ]; then
      req POST "/model/$E/$V/changeLevel/$CL"
    fi
    echo "SEEDED $E v$V"
  fi

  # Strict import (#684-I): only importMode + workflows; an export's other fields are dropped.
  jq --arg v "$SCHEMA_VERSION" '{importMode: "REPLACE",
      workflows: [.workflows[] | if (.version == null or .version == "${SCHEMA_VERSION}") then .version = $v else . end]}' \
    "$WORKFLOW" > "$TMP/workflow-import.json" || fail "$E v$V: cannot read workflow $WORKFLOW"
  req POST "/model/$E/$V/workflow/import" -H 'Content-Type: application/json' --data-binary @"$TMP/workflow-import.json"
  echo "WORKFLOW $E v$V"
done
