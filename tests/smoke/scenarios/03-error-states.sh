#!/usr/bin/env bash
# Scenario 03: error state, recovery via loopback, manual terminals.
scenario_main() {
  # shellcheck source=../lib/load.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/load.sh"
  load_example build error-states || { _bad "load example"; return 1; }
  seed_model registrations 1 "$EX_DIR" || { _bad "seed_model"; return 1; }
  local a b
  a="$(create_entity registrations 1 '{"name":"No Email"}')"
  assert_eq "$(entity_state "$a")" errored "missing email -> errored"
  loopback "$a" '{"email":"fixed@example.com"}' >/dev/null
  assert_eq "$(entity_state "$a")" ready "loopback with valid email -> validating -> ready"
  patch_transition "$a" cancel >/dev/null
  assert_eq "$(entity_state "$a")" cancelled "manual cancel from ready"
  b="$(create_entity registrations 1 '{"name":"Grace","email":"grace@example.com"}')"
  assert_eq "$(entity_state "$b")" ready "valid entity -> ready"
  patch_transition "$b" complete >/dev/null
  assert_eq "$(entity_state "$b")" completed "second entity completes"
  local terminals
  terminals="$(envsubst '${SCHEMA_VERSION}' <"$EX_DIR/workflow.json" | jq '[.workflows[0].states[] | select((.transitions // []) | length == 0)] | length')"
  [ "$terminals" -ge 2 ] && _ok || _bad "workflow has >= 2 terminal states" "got: $terminals"
}
