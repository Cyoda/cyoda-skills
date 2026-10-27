#!/usr/bin/env bash
# Scenario 02: manual transition, guarded automated transition, loopback re-evaluation.
scenario_main() {
  # shellcheck source=../lib/load.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/load.sh"
  load_example build loopback || { _bad "load example"; return 1; }
  seed_model orders 1 "$EX_DIR" || { _bad "seed_model"; return 1; }
  local id code
  id="$(create_entity orders 1 '{"orderRef":"ORD-1","amount":5000}')"
  assert_eq "$(entity_state "$id")" draft "created in draft"
  patch_transition "$id" submit >/dev/null
  assert_eq "$(entity_state "$id")" submitted "manual submit; approve criterion blocks at amount 5000"
  loopback "$id" '{"amount":500}' >/dev/null
  assert_eq "$(entity_state "$id")" approved "loopback with amount 500 fires approve"
  code="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$BASE/entity/JSON/$id/submit")"
  assert_status 400 "$code" "PUT with empty body -> 400"
}
