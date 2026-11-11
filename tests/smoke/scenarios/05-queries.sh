#!/usr/bin/env bash
# Scenario 05: grouped stats and point-in-time search.
scenario_main() {
  # shellcheck source=../lib/load.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/load.sh"
  load_example build loopback || { _bad "load example"; return 1; }
  local Q="$_LOAD_ROOT/cyoda/skills/debug/examples/queries"
  seed_model orders 1 "$EX_DIR" || { _bad "seed_model"; return 1; }
  local ids=() i pit body
  mk() { printf '{"orderRef":"ORD-%s","amount":5000}' "$1"; }
  for i in 1 2 3; do body="$(mk "$i")"; ids+=("$(create_entity orders 1 "$body")"); done
  sleep 0.3
  pit="$(python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]+"Z")')"
  sleep 0.3
  for i in 4 5; do body="$(mk "$i")"; ids+=("$(create_entity orders 1 "$body")"); done
  # entities 4 and 5 -> submitted; 1-3 stay draft
  patch_transition "${ids[3]}" submit >/dev/null
  patch_transition "${ids[4]}" submit >/dev/null

  local stats
  stats="$(curl -s -X POST -H 'Content-Type: application/json' --data-binary @"$Q/stats-group-by-state.json" "$BASE/entity/stats/orders/1/query")"
  assert_eq "$(jq -r '[.[]|select(.groupKey[0].value=="draft")][0].count' <<<"$stats")" 3 "3 entities in draft"
  assert_eq "$(jq -r '[.[]|select(.groupKey[0].value=="submitted")][0].count' <<<"$stats")" 2 "2 entities in submitted"

  local now_n pit_n
  now_n="$(curl -s -X POST -H 'Content-Type: application/json' --data-binary @"$Q/search-point-in-time.json" "$BASE/search/direct/orders/1" | grep -c .)"
  pit_n="$(curl -s -X POST -H 'Content-Type: application/json' --data-binary @"$Q/search-point-in-time.json" "$BASE/search/direct/orders/1?pointInTime=$pit" | grep -c .)"
  assert_eq "$now_n" 5 "search now returns 5"
  assert_eq "$pit_n" 3 "search at pointInTime returns 3"
}
