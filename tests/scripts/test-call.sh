#!/usr/bin/env bash
# shellcheck disable=SC2119 # start_server args are optional env overrides; none needed here
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S="$ROOT/cyoda/scripts"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
# shellcheck source=../lib/server.sh
source "$ROOT/tests/lib/server.sh"
trap 'stop_server; rm -rf "${T:-}"' EXIT

start_server || exit 1
T="$SMOKE_TMP"

cfg() { # name json-profile
  echo "{\"active\":\"p\",\"profiles\":{\"p\":$1}}" >"$T/cfg.json"
  export CYODA_PLUGIN_CONFIG="$T/cfg.json"
}
# "http://localhost:18080" is the endpoint for the mock server
EP="http://localhost:${SMOKE_HTTP_PORT}"

test_call_get_model_list_mock() {
  cfg "{\"endpoint\":\"$EP\"}"
  bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>"$T/err"; local rc=$?
  assert_status 0 "$rc" "GET /model/ ok"
  assert_contains "$(cat "$T/err")" "HTTP_STATUS=200" "status on stderr"
}

test_call_production_guard() {
  cfg "{\"endpoint\":\"$EP\",\"env\":\"production\"}"
  local err rc
  err="$(bash "$S/cyoda-call.sh" POST /model/x/1/lock 2>&1 >/dev/null)"; rc=$?
  assert_status 3 "$rc" "non-GET refused on production"
  assert_contains "$err" "PRODUCTION: ask the user to confirm, then re-run with --confirm-production" "refusal text"
  if grep -q "/model/x/1/lock" "$T/server.log" 2>/dev/null; then _bad "server saw guarded request"; else _ok; fi
  bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>&1; rc=$?
  assert_status 0 "$rc" "GET allowed on production"
  bash "$S/cyoda-call.sh" --confirm-production PUT /model/x/1/lock >/dev/null 2>&1; rc=$?
  assert_status 22 "$rc" "confirmed call reaches server (404 -> 22)"
}

test_call_token_command_failure() {
  cfg "{\"endpoint\":\"$EP\",\"tokenCommand\":\"false\"}"
  local err rc
  err="$(bash "$S/cyoda-call.sh" GET /model/ 2>&1 >/dev/null)"; rc=$?
  assert_status 4 "$rc" "failing tokenCommand"
  assert_contains "$err" "token command failed: false" "failure message"
  cfg "{\"endpoint\":\"$EP\",\"tokenCommand\":\"true\"}"
  bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>&1; rc=$?
  assert_status 4 "$rc" "empty tokenCommand output"
}

test_call_no_endpoint() {
  cfg '{}'
  bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>&1; local rc=$?
  assert_status 5 "$rc" "no endpoint"
}

test_call_header_quoting() {
  mkdir -p "$T/shim"
  cat >"$T/shim/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$SMOKE_TMP/curl-args"
echo '{}'
printf '200'
SH
  chmod +x "$T/shim/curl"
  printf '#!/usr/bin/env bash\necho "a b"\n' >"$T/tok.sh"; chmod +x "$T/tok.sh"
  cfg "{\"endpoint\":\"$EP\",\"tokenCommand\":\"$T/tok.sh\"}"
  SMOKE_TMP="$T" PATH="$T/shim:$PATH" bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>&1
  assert_eq "$(grep -c '^Authorization: Bearer a b$' "$T/curl-args")" 1 "single header line"
  assert_eq "$(grep -c '^Authorization' "$T/curl-args")" 1 "only one Authorization line"
  rm -rf "$T/shim"
}

test_call_token_command_sees_endpoint() {
  cat >"$T/tok2.sh" <<SH
#!/usr/bin/env bash
echo "\$CYODA_ENDPOINT" >"$T/seen-endpoint"
echo tok
SH
  chmod +x "$T/tok2.sh"
  cfg "{\"endpoint\":\"$EP\",\"tokenCommand\":\"$T/tok2.sh\"}"
  bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>&1
  assert_eq "$(cat "$T/seen-endpoint")" "$EP" "CYODA_ENDPOINT exported as stored"
}

test_call_retries_once_on_401() {
  python3 "$HERE/stub401.py" "$T/stub.port" "$T/stub.hits" &
  local spid=$!
  local _; for _ in $(seq 1 20); do [ -s "$T/stub.port" ] && break; sleep 0.25; done
  local port; port="$(cat "$T/stub.port")"
  cat >"$T/tok3.sh" <<SH
#!/usr/bin/env bash
echo x >>"$T/tok-count"
echo tok
SH
  chmod +x "$T/tok3.sh"
  rm -f "$T/tok-count"
  cfg "{\"endpoint\":\"http://127.0.0.1:$port\",\"tokenCommand\":\"$T/tok3.sh\"}"
  bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>&1; local rc=$?
  kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
  assert_status 0 "$rc" "succeeds after retry"
  assert_eq "$(wc -l <"$T/tok-count" | tr -d ' ')" 2 "tokenCommand run twice"
  assert_eq "$(wc -l <"$T/stub.hits" | tr -d ' ')" 2 "two requests made"
}

test_call_get_model_list_mock
test_call_production_guard
test_call_token_command_failure
test_call_no_endpoint
test_call_header_quoting
test_call_token_command_sees_endpoint
test_call_retries_once_on_401
report
