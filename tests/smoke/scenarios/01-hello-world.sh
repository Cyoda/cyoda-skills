#!/usr/bin/env bash
# Scenario 01: hello-world reaches a terminal state via automated transitions.
scenario_main() {
  # shellcheck source=../lib/load.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/load.sh"
  load_example build hello-world || { _bad "load example"; return 1; }
  local code id

  # Entity on an unimported model
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"title":"x"}' "$BASE/entity/JSON/hello/1")"
  assert_status 404 "$code" "entity on unimported model -> 404"
  assert_contains "$(curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"x"}' "$BASE/entity/JSON/hello/1")" MODEL_NOT_FOUND "error code MODEL_NOT_FOUND"

  # Workflow version "1" is rejected (needs a model: import sample + lock first)
  curl -s -o /dev/null -X POST -H 'Content-Type: application/json' --data-binary @"$EX_DIR/sample.json" "$BASE/model/import/JSON/SAMPLE_DATA/hello/1"
  curl -s -o /dev/null -X PUT "$BASE/model/hello/1/lock"
  local out
  out="$(SCHEMA_VERSION=1 envsubst '${SCHEMA_VERSION}' <"$EX_DIR/workflow.json" | curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary @- "$BASE/model/hello/1/workflow/import")"
  assert_eq "${out##*$'\n'}" 400 'workflow version "1" -> 400'
  assert_contains "$out" WORKFLOW_SCHEMA_VERSION_UNSUPPORTED 'version "1" error code'

  # Real import with current version, then create
  code="$(envsubst '${SCHEMA_VERSION}' <"$EX_DIR/workflow.json" | curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' --data-binary @- "$BASE/model/hello/1/workflow/import")"
  assert_status 200 "$code" "workflow import with current schema version"
  id="$(create_entity hello 1 "$(cat "$EX_DIR/sample.json")")"
  assert_eq "$(entity_state "$id")" completed "automated transitions reach completed"
  # Creation runs the whole cascade in one save (one version); a later update adds the second.
  loopback "$id" '{"message":"updated"}' >/dev/null
  local n; n="$(curl -s "$BASE/entity/$id/changes" | jq 'length')"
  [ "${n:-0}" -ge 2 ] && _ok || _bad "changes lists >= 2 versions" "got: $n"

  # test skill's smoke-test.sh template: run from a project dir holding a
  # cyoda-manifest.json, fire the manual `archive` transition. The token
  # command proves the auth header survives as one argument (mock ignores it).
  local proj out rc
  proj="$(mktemp -d)"
  cp "$EX_DIR/sample.json" "$proj/hello-v1-sample.json"
  printf '{"manifestVersion":1,"entities":[{"name":"hello","modelVersion":1,"sample":"hello-v1-sample.json"}]}\n' >"$proj/cyoda-manifest.json"
  # CYODA_ENDPOINT is given with an /api/ suffix; the token command must see
  # it normalised (no /api), as cyoda-call.sh passes it (Ruling R1).
  local tc
  tc='[ "$CYODA_ENDPOINT" = "'"${BASE%/api}"'" ] && echo smoke-token'
  out="$(cd "$proj" && env -u CYODA_CONFIG ENTITY_NAME=hello MODEL_VERSION=1 TRANSITION_NAME=archive \
    EXPECTED_STATE=archived CYODA_ENDPOINT="$BASE/" CYODA_TOKEN_COMMAND="$tc" \
    bash "$_LOAD_ROOT/cyoda/skills/test/templates/smoke-test.sh" 2>"$proj/stderr")"; rc=$?
  assert_eq "$rc" 0 "smoke-test.sh exits 0"
  [ "$rc" -eq 0 ] || { echo "        stdout: $out" >&2; echo "        stderr: $(cat "$proj/stderr")" >&2; }
  assert_eq "$(printf '%s\n' "$out" | tail -n1)" "=== PASS ===" "smoke-test.sh stdout ends === PASS ==="
  assert_contains "$out" archived "smoke-test.sh reports the archived state"

  # A 200 with a non-JSON body (wrong endpoint, proxy page) is a clean FAIL.
  mkdir -p "$proj/www/api/model"
  echo '<html>not cyoda</html>' >"$proj/www/api/model/index.html"
  local hp=18099 hpid
  ( cd "$proj/www" && exec python3 -m http.server "$hp" --bind 127.0.0.1 >/dev/null 2>&1 ) &
  hpid=$!
  local i; for i in $(seq 1 20); do curl -s -o /dev/null "http://127.0.0.1:$hp/" && break; sleep 0.25; done
  out="$(cd "$proj" && ENTITY_NAME=hello MODEL_VERSION=1 TRANSITION_NAME=archive \
    CYODA_ENDPOINT="http://127.0.0.1:$hp" bash "$_LOAD_ROOT/cyoda/skills/test/templates/smoke-test.sh" 2>"$proj/stderr")"; rc=$?
  kill "$hpid" 2>/dev/null; wait "$hpid" 2>/dev/null
  assert_eq "$rc" 1 "non-JSON 200 -> exit 1"
  assert_eq "$(printf '%s\n' "$out" | tail -n1)" "=== FAIL ===" "non-JSON 200 -> === FAIL ==="
  assert_contains "$out" "non-JSON body" "non-JSON 200 reason"
  rm -rf "$proj"
}
