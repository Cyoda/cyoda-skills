#!/usr/bin/env bash
# Scenario 04: scheduled transition fires on its own.
scenario_main() {
  # shellcheck source=../lib/load.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/load.sh"
  load_example build scheduled || { _bad "load example"; return 1; }
  seed_model tickets 1 "$EX_DIR" || { _bad "seed_model"; return 1; }
  local id
  id="$(create_entity tickets 1 "$(cat "$EX_DIR/sample.json")")"
  assert_eq "$(entity_state "$id")" waiting "starts in waiting"
  assert_eq "$(wait_state "$id" expired 10)" expired "scheduled transition fires within 10s"
}
