#!/usr/bin/env bash
# Two projects, two throwaway cyoda-go servers (tests/evals/start.sh ids 401, 402):
# each project's entry in the plugin config's "projects" map reaches its own
# server, whatever the active profile says. Project A runs JWT with a relative
# project token script; project B runs mock auth.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S="$ROOT/cyoda/scripts"
EV="$ROOT/tests/evals"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"

IDS=(401 402)
T="$(mktemp -d)"
umask 022
cleanup() { bash "$EV/stop.sh" "${IDS[@]}" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT

for id in "${IDS[@]}"; do
  for port in $((20000 + id * 100 + 80)) $((20000 + id * 100 + 90)) $((20000 + id * 100 + 91)); do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "test-two-projects: port $port is already in use; refusing to start (not killing unknown processes)" >&2
      trap - EXIT; rm -rf "$T"; exit 1
    fi
  done
done
bash "$EV/start.sh" 401 jwt >/dev/null || exit 1
bash "$EV/start.sh" 402 mock >/dev/null || exit 1
EPA="http://localhost:$((20000 + 401 * 100 + 80))"
EPB="http://localhost:$((20000 + 402 * 100 + 80))"

# Hermetic HOME, and a machine-wide active profile that must not be used.
mkdir -p "$T/home"
export HOME="$T/home"
export CYODA_PLUGIN_CONFIG="$T/global.json"
unset CYODA_PROFILE
# Project A's token script reads the client credentials from the environment,
# as /cyoda:auth sets it up; the project entry holds only the relative command.
export CYODA_CLIENT_ID=evalclient CYODA_CLIENT_SECRET=evalsecret

PA="$HOME/work/alpha"; PB="$HOME/work/beta"
mkdir -p "$PA/scripts" "$PA/src" "$PB/src"
cp "$ROOT/cyoda/skills/auth/templates/get-token.sh" "$PA/scripts/get-token.sh"
chmod +x "$PA/scripts/get-token.sh"
jq -n --arg a "$(cd "$PA" && pwd -P)" --arg b "$(cd "$PB" && pwd -P)" --arg epa "$EPA" --arg epb "$EPB" '{
  active: "g", profiles: {g: {endpoint: "http://localhost:1"}},
  projects: {($a): {endpoint: $epa, env: "development", tokenCommand: "scripts/get-token.sh"},
             ($b): {endpoint: $epb, env: "development"}}}' >"$CYODA_PLUGIN_CONFIG"

call() { (cd "$1" && shift && bash "$S/cyoda-call.sh" "$@" 2>/dev/null); }
import_model() { # dir entity
  echo '{"name":"x","n":1}' >"$T/sample.json"
  call "$1" POST "/model/import/JSON/SAMPLE_DATA/$2/1" -H 'Content-Type: application/json' --data-binary @"$T/sample.json" >/dev/null
}

test_two_projects_reach_their_own_server() {
  local code rc
  code="$(curl -s -o /dev/null -w '%{http_code}' "$EPA/api/model/")"
  assert_status 401 "$code" "server A needs a token"
  import_model "$PA/src" alphamodel; rc=$?
  assert_status 0 "$rc" "project A: import through the relative project token script"
  import_model "$PB/src" betamodel; rc=$?
  assert_status 0 "$rc" "project B: import with mock auth"
  local la lb
  la="$(call "$PA/src" GET /model/)"; lb="$(call "$PB/src" GET /model/)"
  assert_contains "$la" alphamodel "project A sees its model"
  assert_contains "$lb" betamodel "project B sees its model"
  if [[ "$la" == *betamodel* ]]; then _bad "project A reached server B"; else _ok; fi
  if [[ "$lb" == *alphamodel* ]]; then _bad "project B reached server A"; else _ok; fi
}

test_two_projects_status() {
  local sa sb
  sa="$(cd "$PA" && bash "$S/cyoda-status.sh" | head -n1)"
  sb="$(cd "$PB/src" && bash "$S/cyoda-status.sh" | head -n1)"
  assert_contains "$sa" "STATUS=connected PROFILE=alpha ENDPOINT=$EPA" "status in project A"
  assert_contains "$sa" "SOURCE=project PROJECT=$(cd "$PA" && pwd -P)" "status A source"
  assert_contains "$sb" "STATUS=connected PROFILE=beta ENDPOINT=$EPB" "status in project B"
}

test_two_projects_reach_their_own_server
test_two_projects_status
report
