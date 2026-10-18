#!/usr/bin/env bash
# Scenario 06: delete, point-in-time read, history and audit.
scenario_main() {
  # shellcheck source=../lib/load.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/load.sh"
  load_example build hello-world || { _bad "load example"; return 1; }
  seed_model hello 1 "$EX_DIR" || { _bad "seed_model"; return 1; }
  local id pit code
  id="$(create_entity hello 1 "$(cat "$EX_DIR/sample.json")")"
  sleep 0.3
  pit="$(python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]+"Z")')"
  sleep 0.3
  code="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$BASE/entity/$id")"
  assert_status 200 "$code" "DELETE succeeds"
  code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/entity/$id")"
  assert_status 404 "$code" "GET after delete -> 404"
  assert_eq "$(curl -s "$BASE/entity/$id?pointInTime=$pit" | jq -r '.meta.state')" completed "pointInTime before delete returns the entity"
  assert_contains "$(curl -s "$BASE/entity/$id/changes")" DELETE "/changes shows a DELETE entry"
  local audit
  audit="$(curl -s "$BASE/audit/entity/$id?limit=1000")"
  local del_t after
  del_t="$(jq -r '[.items[]|select(.changeType=="DELETE")][0].microsTime' <<<"$audit")"
  after="$(jq --argjson t "${del_t:-0}" '[.items[]|select(.auditEventType=="StateMachine" and .microsTime > $t and (.eventType=="TRANSITION_MAKE"))]|length' <<<"$audit")"
  if [ "${del_t:-null}" != null ] && [ -n "$del_t" ]; then _ok; else _bad "audit lists DELETE event"; fi
  assert_eq "$after" 0 "no transition event after the delete"
}
