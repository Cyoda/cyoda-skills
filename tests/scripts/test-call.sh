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
# Hermetic: no project binding from the caller's working directory.
cd "$T" || exit 1
umask 022
unset CYODA_PROFILE

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

test_call_no_config_uses_default_endpoint() {
  local rc
  CYODA_PLUGIN_CONFIG="$T/none.json" CYODA_DEFAULT_ENDPOINT="$EP" bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>"$T/err"; rc=$?
  assert_status 0 "$rc" "no config: GET /model/ goes to the default endpoint"
  assert_contains "$(cat "$T/err")" "HTTP_STATUS=200" "default endpoint answered"
}

test_call_header_quoting() {
  # R10: the token must not appear in curl's argv (ps-visible); it arrives via
  # -H @<0600 file>. The shim records argv and the contents of any @file header.
  mkdir -p "$T/shim"
  cat >"$T/shim/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$SMOKE_TMP/curl-args"
: >"$SMOKE_TMP/curl-headers"
prev=""
for a in "$@"; do
  if [ "$prev" = "-H" ] && [ "${a#@}" != "$a" ]; then
    f="${a#@}"
    cat "$f" >>"$SMOKE_TMP/curl-headers"
    stat -f '%Lp' "$f" 2>/dev/null >"$SMOKE_TMP/curl-header-mode" || stat -c '%a' "$f" >"$SMOKE_TMP/curl-header-mode"
    printf '%s\n' "$f" >"$SMOKE_TMP/curl-header-path"
  fi
  prev="$a"
done
echo '{}'
printf '200'
SH
  chmod +x "$T/shim/curl"
  printf '#!/usr/bin/env bash\necho "a b"\n' >"$T/tok.sh"; chmod +x "$T/tok.sh"
  cfg "{\"endpoint\":\"$EP\",\"tokenCommand\":\"$T/tok.sh\"}"
  SMOKE_TMP="$T" PATH="$T/shim:$PATH" bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>&1
  assert_eq "$(grep -c 'Bearer' "$T/curl-args")" 0 "token absent from curl argv"
  assert_eq "$(grep -c 'a b' "$T/curl-args")" 0 "token value absent from curl argv"
  assert_eq "$(grep -c '^Authorization: Bearer a b$' "$T/curl-headers")" 1 "header arrives intact via @file"
  assert_eq "$(grep -c '^Authorization' "$T/curl-headers")" 1 "only one Authorization line"
  assert_eq "$(cat "$T/curl-header-mode")" 600 "header file is 0600"
  if [ -e "$(cat "$T/curl-header-path")" ]; then _bad "header file left behind"; else _ok; fi
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

test_call_project_relative_token_command() {
  local pd; pd="$(mkdir -p "$HOME/proj/scripts" "$HOME/proj/.cyoda" "$HOME/proj/src" && cd "$HOME/proj" && pwd -P)"
  cat >"$pd/scripts/tok.sh" <<SH
#!/usr/bin/env bash
echo "\$PWD|\$CYODA_ENDPOINT|\$1" >"$T/seen-project"
echo tok
SH
  chmod +x "$pd/scripts/tok.sh"
  echo "{\"endpoint\":\"$EP\",\"env\":\"development\",\"tokenCommand\":\"scripts/tok.sh token\"}" >"$pd/.cyoda/instance.json"
  cfg "{\"endpoint\":\"http://localhost:1\"}"   # the global active profile must not be used
  local rc
  (cd "$pd/src" && bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>"$T/err"); rc=$?
  assert_status 0 "$rc" "project binding: GET /model/ ok"
  assert_eq "$(cat "$T/seen-project" 2>/dev/null)" "$pd|$EP|token" "relative tokenCommand runs from projectDir and sees CYODA_ENDPOINT"
  echo "{\"endpoint\":\"$EP\",\"env\":\"production\"}" >"$pd/.cyoda/instance.json"
  (cd "$pd/src" && bash "$S/cyoda-call.sh" POST /model/x/1/lock >/dev/null 2>&1); rc=$?
  assert_status 3 "$rc" "production guard applies to a project binding"
  rm -rf "$pd/.cyoda"
}

test_call_project_token_command_quoting() {
  local pd rc; pd="$(mkdir -p "$HOME/quoted/scripts" "$HOME/quoted/.cyoda" && cd "$HOME/quoted" && pwd -P)"
  cat >"$pd/scripts/tok.sh" <<SH
#!/usr/bin/env bash
printf '%s|%s\n' "\$TOKARG" "\$1" >"$T/seen-quoted"
echo tok
SH
  chmod +x "$pd/scripts/tok.sh"
  jq -n --arg ep "$EP" --arg tc "TOKARG='two words' scripts/tok.sh \"it's \\\$HOME\"" \
    '{endpoint: $ep, tokenCommand: $tc}' >"$pd/.cyoda/instance.json"
  (cd "$pd" && bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>&1); rc=$?
  assert_status 0 "$rc" "tokenCommand with spaces and quotes: ok"
  assert_eq "$(cat "$T/seen-quoted" 2>/dev/null)" "two words|it's \$HOME" "tokenCommand with spaces and quotes runs as written"
  rm -rf "$pd/.cyoda"
}

test_call_untrusted_project_file_ignored() {
  # A planted, group-writable shared/.cyoda/instance.json is ignored entirely:
  # its tokenCommand never runs and its endpoint is never called.
  local pd rc; pd="$(mkdir -p "$HOME/shared/.cyoda" "$HOME/shared/work/sub" && cd "$HOME/shared" && pwd -P)"
  rm -f "$T/pwned"
  jq -n --arg tc "touch $T/pwned; echo tok" '{endpoint: "http://localhost:1", tokenCommand: $tc}' >"$pd/.cyoda/instance.json"
  chmod 664 "$pd/.cyoda/instance.json"
  cfg "{\"endpoint\":\"$EP\"}"
  (cd "$pd/work/sub" && bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>&1); rc=$?
  if [ -e "$T/pwned" ]; then _bad "untrusted project tokenCommand was executed"; else _ok; fi
  assert_status 0 "$rc" "call goes to the machine-wide profile, not the planted endpoint"
  rm -rf "$pd"
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
test_call_no_config_uses_default_endpoint
test_call_header_quoting
test_call_token_command_sees_endpoint
test_call_project_relative_token_command
test_call_project_token_command_quoting
test_call_untrusted_project_file_ignored
test_call_retries_once_on_401
report
