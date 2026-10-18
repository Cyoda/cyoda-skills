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
}
