#!/usr/bin/env bash
# Scenario 07: a Go compute member (tests/smoke/compute) serves the function
# criterion has-address and the processor create-shipment for compute's
# examples/cascade. A rejected manual transition carries the criterion's
# reason in its 400; an accepted one cascades into the linked shipment.
# Skipped (not failed) when Go is missing, or older than 1.26.7 without
# GOTOOLCHAIN=auto to fetch a newer toolchain.

_C7_PID=""

# _c7_stop: stop the compute member if it is running (idempotent).
_c7_stop() {
  if [ -n "$_C7_PID" ]; then
    kill "$_C7_PID" 2>/dev/null
    local _
    for _ in $(seq 1 20); do
      kill -0 "$_C7_PID" 2>/dev/null || break
      sleep 0.25
    done
    kill -9 "$_C7_PID" 2>/dev/null
    wait "$_C7_PID" 2>/dev/null
    _C7_PID=""
  fi
  return 0
}

# _c7_go <args>: run go with the developer's HOME and XDG_CONFIG_HOME, not the
# throwaway ones start_server sets (server.sh keeps the real values), so the
# module cache, build cache and any auto-downloaded toolchain are the usual ones.
_c7_go() {
  if [ -n "${_SMOKE_HAD_XDG-}" ]; then
    HOME="${_SMOKE_REAL_HOME:-$HOME}" XDG_CONFIG_HOME="$_SMOKE_REAL_XDG" go "$@"
  else
    env -u XDG_CONFIG_HOME HOME="${_SMOKE_REAL_HOME:-$HOME}" go "$@"
  fi
}

# _c7_go_ok: 0 if `go` can build a module that needs go >= 1.26.7.
_c7_go_ok() {
  command -v go >/dev/null 2>&1 || { _C7_SKIP="go not found on PATH"; return 1; }
  local v tc
  v="$(_c7_go env GOVERSION 2>/dev/null)"; v="${v#go}"
  tc="$(_c7_go env GOTOOLCHAIN 2>/dev/null)"
  # sort -V puts the lower version first; equal versions are fine.
  if [ "$(printf '%s\n%s\n' "$v" 1.26.7 | sort -V | head -n1)" = 1.26.7 ]; then return 0; fi
  case "$tc" in auto | *+auto) return 0 ;; esac
  _C7_SKIP="go $v < 1.26.7 and GOTOOLCHAIN=$tc (set GOTOOLCHAIN=auto or install go >= 1.26.7)"
  return 1
}

scenario_main() {
  # shellcheck source=../lib/load.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/load.sh"
  local root src tmp log e out code id ship _
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  src="$root/tests/smoke/compute"

  _C7_SKIP=""
  if ! _c7_go_ok; then
    echo "  SKIP 07-compute: $_C7_SKIP"
    return 0
  fi

  load_example compute cascade || { _bad "load example"; return 1; }
  tmp="$(mktemp -d)"
  log="$tmp/member.log"

  # Always stop the member: on return from this function, and on exit
  # (Ctrl-C, set -e callers) together with the server run.sh started.
  trap '_c7_stop; stop_server' EXIT
  trap '_c7_stop; rm -rf "$tmp"; trap - RETURN; trap stop_server EXIT' RETURN

  # 1. Build and start the member; it prints READY once joined (greet received).
  out="$(cd "$src" && _c7_go build -o "$tmp/compute-member" . 2>&1)" \
    || { _bad "go build tests/smoke/compute" "$out"; return 1; }
  "$tmp/compute-member" --grpc "localhost:${SMOKE_GRPC_PORT}" --http "$BASE" >"$log" 2>&1 &
  _C7_PID=$!
  for _ in $(seq 1 40); do
    grep -qx READY "$log" 2>/dev/null && break
    kill -0 "$_C7_PID" 2>/dev/null || break
    sleep 0.25
  done
  if grep -qx READY "$log" 2>/dev/null; then _ok; else
    _bad "compute member prints READY within 10s" "$(tail -n 20 "$log")"; return 1
  fi

  # 2. Seed both models from the skill-owned example (shared config.json).
  for e in order shipment; do
    mkdir -p "$tmp/$e"
    cp "$EX_DIR/$e-sample.json" "$tmp/$e/sample.json"
    cp "$EX_DIR/$e-workflow.json" "$tmp/$e/workflow.json"
    cp "$EX_DIR/config.json" "$tmp/$e/config.json"
    seed_model "$e" 1 "$tmp/$e" || { _bad "seed_model $e"; return 1; }
  done

  # 3. No address: the function criterion rejects the manual confirm with its reason.
  id="$(create_entity order 1 '{"orderId":"ORD-1"}')"
  assert_eq "$(entity_state "$id")" draft "order without address created in draft"
  code="$(curl -s -o "$tmp/reject.json" -w '%{http_code}' -X PATCH \
    -H 'Content-Type: application/merge-patch+json' -H 'If-Match: *' -d '{}' \
    "$BASE/entity/JSON/$id/confirm")"
  assert_status 400 "$code" "confirm without address -> 400"
  assert_contains "$(cat "$tmp/reject.json")" "missing shipping address" "400 body carries the criterion's reason"
  assert_eq "$(entity_state "$id")" draft "rejected order stays in draft"

  # 4. With an address: confirm runs create-shipment, which creates the linked
  #    shipment and fires its manual dispatch in the same transaction.
  id="$(create_entity order 1 '{"orderId":"ORD-2","address":"1 Main St"}')"
  out="$(patch_transition "$id" confirm)"
  assert_eq "$(entity_state "$id")" confirmed "order with address -> confirmed"
  ship="$(curl -s "$BASE/entity/$id" | jq -r '.data.shipmentId // empty')"
  if [ -n "$ship" ]; then _ok; else
    _bad "order.\$.shipmentId is set" "confirm response: $out" "member log: $(tail -n 10 "$log")"; return 1
  fi
  assert_eq "$(entity_state "$ship")" dispatched "linked shipment fired dispatch"
  assert_eq "$(curl -s "$BASE/entity/$ship" | jq -r '.data.orderId')" ORD-2 "shipment linked by \$.orderId"
}
