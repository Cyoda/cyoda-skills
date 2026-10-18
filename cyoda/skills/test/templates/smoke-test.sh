#!/usr/bin/env bash
# Cyoda smoke test: create one entity, fire one transition, check the state.
#
# Required env:
#   ENTITY_NAME       model name, e.g. order
#   MODEL_VERSION     model version (integer), e.g. 1
#   TRANSITION_NAME   a transition that is available after the create cascade
# Optional env:
#   CYODA_ENDPOINT       instance root, no /api (default http://localhost:8080)
#   CYODA_TOKEN_COMMAND  command that prints a JWT (omit for mock auth); it runs
#                        with CYODA_ENDPOINT set, like the plugin's cyoda-call.sh
#   SAMPLE_FILE          JSON payload to create; default: the sample listed
#                        for ENTITY_NAME/MODEL_VERSION in ./cyoda-manifest.json
#   EXPECTED_STATE       state the entity must be in after the transition
#
# Facts: cyoda help crud ENDPOINTS (create, read, transitions, PATCH),
# cyoda help models ENDPOINTS (model list). Exit 0 on PASS, 1 on FAIL.
set -euo pipefail

: "${ENTITY_NAME:?set ENTITY_NAME}"
: "${MODEL_VERSION:?set MODEL_VERSION}"
: "${TRANSITION_NAME:?set TRANSITION_NAME}"
ENDPOINT="${CYODA_ENDPOINT:-http://localhost:8080}"
ENDPOINT="${ENDPOINT%/}"
ENDPOINT="${ENDPOINT%/api}"
API="$ENDPOINT/api"

fail() {
  echo "    $*"
  echo ""
  echo "=== FAIL ==="
  exit 1
}

AUTH=()
if [ -n "${CYODA_TOKEN_COMMAND:-}" ]; then
  # Same contract as cyoda-call.sh: the token command sees CYODA_ENDPOINT.
  TOKEN="$(CYODA_ENDPOINT="$ENDPOINT" bash -c "$CYODA_TOKEN_COMMAND")" || fail "token command failed: $CYODA_TOKEN_COMMAND"
  [ -n "$TOKEN" ] || fail "token command printed nothing: $CYODA_TOKEN_COMMAND"
  AUTH=(-H "Authorization: Bearer $TOKEN")
fi

# req <METHOD> <URL> [curl args...]: body -> $BODY, status -> $CODE.
# A 2xx body that isn't JSON (a proxy page, a wrong endpoint) is a FAIL.
req() {
  local m="$1" u="$2" out
  shift 2
  out="$(curl -sS -X "$m" ${AUTH[@]+"${AUTH[@]}"} -w $'\n%{http_code}' "$@" "$u")" || fail "cannot reach $u"
  CODE="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
  case "$CODE" in
    2??) jq -e . >/dev/null 2>&1 <<<"$BODY" || fail "$m $u -> $CODE with a non-JSON body: $(printf '%s' "$BODY" | head -c 200)" ;;
  esac
}

if [ -z "${SAMPLE_FILE:-}" ]; then
  [ -f cyoda-manifest.json ] || fail "no SAMPLE_FILE and no ./cyoda-manifest.json"
  SAMPLE_FILE="$(jq -r --arg n "$ENTITY_NAME" --argjson v "$MODEL_VERSION" \
    '[.entities[] | select(.name == $n and .modelVersion == $v)][0].sample // empty' cyoda-manifest.json 2>/dev/null)" \
    || fail "cannot read ./cyoda-manifest.json"
  [ -n "$SAMPLE_FILE" ] || fail "cyoda-manifest.json lists no sample for $ENTITY_NAME v$MODEL_VERSION"
fi
[ -f "$SAMPLE_FILE" ] || fail "sample file not found: $SAMPLE_FILE"

echo "=== Cyoda Smoke Test ==="
echo "Endpoint: $ENDPOINT"
echo "Entity: $ENTITY_NAME v$MODEL_VERSION, transition: $TRANSITION_NAME"
echo ""

echo "--- Checking model..."
req GET "$API/model/"
[ "$CODE" = 200 ] || fail "GET /api/model/ -> $CODE $BODY"
MSTATE="$(jq -r --arg n "$ENTITY_NAME" --argjson v "$MODEL_VERSION" \
  '[.[] | select(.modelName == $n and .modelVersion == $v)][0].currentState // "MISSING"' <<<"$BODY" 2>/dev/null)" \
  || fail "unexpected model list: $(printf '%s' "$BODY" | head -c 200)"
echo "Model: $MSTATE"
[ "$MSTATE" = LOCKED ] || fail "model must be registered and LOCKED (type /cyoda:build)"

echo "--- Creating entity..."
req POST "$API/entity/JSON/$ENTITY_NAME/$MODEL_VERSION" -H 'Content-Type: application/json' --data-binary @"$SAMPLE_FILE"
[ "$CODE" = 200 ] || fail "create -> $CODE $BODY"
ENTITY_ID="$(jq -r '.[0].entityIds[0] // empty' <<<"$BODY" 2>/dev/null)" || ENTITY_ID=""
[ -n "$ENTITY_ID" ] || fail "no entity id in: $BODY"
echo "Created entity: $ENTITY_ID"

echo "--- Checking state after create..."
req GET "$API/entity/$ENTITY_ID"
[ "$CODE" = 200 ] || fail "read -> $CODE $BODY"
STATE="$(jq -r '.meta.state // empty' <<<"$BODY" 2>/dev/null)" || STATE=""
[ -n "$STATE" ] || fail "no meta.state in: $(printf '%s' "$BODY" | head -c 200)"
echo "State: $STATE (automated transitions may already have run)"

echo "--- Checking available transitions..."
req GET "$API/entity/$ENTITY_ID/transitions"
[ "$CODE" = 200 ] || fail "transitions -> $CODE $BODY"
AVAIL="$(jq -r 'join(", ")' <<<"$BODY" 2>/dev/null)" || fail "unexpected transitions list: $(printf '%s' "$BODY" | head -c 200)"
echo "Available: $AVAIL"
jq -e --arg t "$TRANSITION_NAME" 'index($t) != null' >/dev/null 2>&1 <<<"$BODY" \
  || fail "$TRANSITION_NAME is not available from $STATE"

echo "--- Firing $TRANSITION_NAME (PATCH {}, data unchanged)..."
req PATCH "$API/entity/JSON/$ENTITY_ID/$TRANSITION_NAME" \
  -H 'Content-Type: application/merge-patch+json' -H 'If-Match: *' -d '{}'
[ "$CODE" = 200 ] || fail "transition -> $CODE $BODY"

echo "--- Checking new state..."
req GET "$API/entity/$ENTITY_ID"
[ "$CODE" = 200 ] || fail "read -> $CODE $BODY"
NEW_STATE="$(jq -r '.meta.state // empty' <<<"$BODY" 2>/dev/null)" || NEW_STATE=""
[ -n "$NEW_STATE" ] || fail "no meta.state in: $(printf '%s' "$BODY" | head -c 200)"
echo "New state: $NEW_STATE"
if [ -n "${EXPECTED_STATE:-}" ] && [ "$NEW_STATE" != "$EXPECTED_STATE" ]; then
  fail "expected state $EXPECTED_STATE, got $NEW_STATE"
fi

echo ""
echo "=== PASS ==="
