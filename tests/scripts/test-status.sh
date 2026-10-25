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

T="$(mktemp -d)"
# Hermetic: no project binding from the caller's working directory.
cd "$T" || exit 1
unset CYODA_PROFILE

test_status_connected() {
  start_server || return
  echo "{\"active\":\"p\",\"profiles\":{\"p\":{\"endpoint\":\"http://localhost:${SMOKE_HTTP_PORT}\"}}}" >"$T/i.json"
  local out
  out="$(CYODA_PLUGIN_CONFIG="$T/i.json" bash "$S/cyoda-status.sh")"
  assert_contains "$(echo "$out" | head -n1)" "STATUS=connected" "connected"
  assert_contains "$out" "VERSION=0.8.4" "version"
  assert_contains "$out" "PROFILE=p" "profile"
  assert_contains "$(echo "$out" | head -n1)" "SOURCE=profile" "profile source"
  if [[ "$(echo "$out" | head -n1)" == *PROJECT=* ]]; then _bad "no PROJECT field for a profile"; else _ok; fi
  stop_server
}

test_status_unreachable() {
  echo '{"active":"dead","profiles":{"dead":{"endpoint":"http://localhost:1"}}}' >"$T/u.json"
  local out
  out="$(CYODA_PLUGIN_CONFIG="$T/u.json" bash "$S/cyoda-status.sh")"
  assert_contains "$(echo "$out" | head -n1)" "STATUS=unreachable" "unreachable"
  assert_contains "$out" "WARN=active profile dead is unreachable; run /cyoda:setup to switch to default" "unreachable warn"
}

test_status_not_configured() {
  # A config file that exists but has no endpoint for the active profile.
  echo '{"profiles":{}}' >"$T/empty.json"
  local out; out="$(CYODA_PLUGIN_CONFIG="$T/empty.json" bash "$S/cyoda-status.sh")"
  assert_contains "$out" "STATUS=not_configured" "not configured"
  assert_contains "$out" "ENDPOINT=none" "no endpoint"
}

test_status_no_config_local_up() {
  start_server || return
  local ep="http://localhost:${SMOKE_HTTP_PORT}" out
  out="$(CYODA_DEFAULT_ENDPOINT="$ep" CYODA_PLUGIN_CONFIG="$T/none.json" bash "$S/cyoda-status.sh")"
  assert_contains "$(echo "$out" | head -n1)" "STATUS=connected PROFILE=default ENDPOINT=$ep ENV=development VERSION=0.8.4" "implicit default connected"
  assert_contains "$(echo "$out" | head -n1)" "SOURCE=default" "implicit default source"
  assert_contains "$out" "WARN=no saved profile; using the default local instance $ep — type /cyoda:setup to save it" "implicit default warn"
  stop_server
}

test_status_no_config_nothing_listening() {
  local out
  out="$(CYODA_DEFAULT_ENDPOINT="http://localhost:1" CYODA_PLUGIN_CONFIG="$T/none.json" bash "$S/cyoda-status.sh")"
  assert_contains "$(echo "$out" | head -n1)" "STATUS=unreachable PROFILE=default ENDPOINT=http://localhost:1" "implicit default unreachable"
  assert_contains "$out" "WARN=no cyoda-go is answering at http://localhost:1 — type /cyoda:setup to install or start one" "implicit default unreachable warn"
  if [[ "$out" == *"switch to default"* ]]; then _bad "no switch-to-default offer for the implicit default"; else _ok; fi
}

test_status_version_mismatch() {
  start_server || return
  echo "{\"active\":\"p\",\"profiles\":{\"p\":{\"endpoint\":\"http://localhost:${SMOKE_HTTP_PORT}\"}}}" >"$T/i.json"
  mkdir -p "$T/shim"
  # shellcheck disable=SC2016 # literal text is intentional (written to a file/passed to envsubst/eval later)
  printf '#!/usr/bin/env bash\nif [ "$1" = "--version" ]; then echo "cyoda version 0.9.0 (commit x)"; fi\n' >"$T/shim/cyoda"
  chmod +x "$T/shim/cyoda"
  local out
  out="$(PATH="$T/shim:$PATH" CYODA_PLUGIN_CONFIG="$T/i.json" bash "$S/cyoda-status.sh")"
  assert_contains "$out" "WARN=local cyoda 0.9.0 differs from instance 0.8.4; help is read from the instance" "mismatch warn"
  assert_contains "$out" "BINARY_VERSION=0.9.0" "binary version"
  stop_server
}

test_status_stale_token_forwarded() {
  echo '{"active":"old","profiles":{"old":{"endpoint":"http://localhost:1","token":"eyJ"}}}' >"$T/s.json"
  local out; out="$(CYODA_PLUGIN_CONFIG="$T/s.json" bash "$S/cyoda-status.sh")"
  assert_contains "$out" "WARN=profile old contains a stored token" "forwarded"
}

test_status_ignores_broken_token_command() {
  start_server || return
  echo "{\"active\":\"p\",\"profiles\":{\"p\":{\"endpoint\":\"http://localhost:${SMOKE_HTTP_PORT}\",\"tokenCommand\":\"false\"}}}" >"$T/b.json"
  local out; out="$(CYODA_PLUGIN_CONFIG="$T/b.json" bash "$S/cyoda-status.sh")"
  assert_contains "$(echo "$out" | head -n1)" "STATUS=connected" "broken tokenCommand ignored"
  stop_server
}

test_status_project_binding() {
  start_server || return
  local pd ep="http://localhost:${SMOKE_HTTP_PORT}" out
  pd="$(mkdir -p "$HOME/work/shop/.cyoda" "$HOME/work/shop/src" && cd "$HOME/work/shop" && pwd -P)"
  echo "{\"endpoint\":\"$ep\",\"env\":\"production\"}" >"$pd/.cyoda/instance.json"
  echo '{"active":"p","profiles":{"p":{"endpoint":"http://localhost:1"}}}' >"$T/g.json"
  out="$(cd "$pd/src" && CYODA_PLUGIN_CONFIG="$T/g.json" bash "$S/cyoda-status.sh")"
  assert_contains "$(echo "$out" | head -n1)" "STATUS=connected PROFILE=shop ENDPOINT=$ep ENV=production VERSION=0.8.4" "project binding connected"
  assert_contains "$(echo "$out" | head -n1)" "SOURCE=project PROJECT=$pd" "project source and dir"
  echo '{"endpoint":"http://localhost:1"}' >"$pd/.cyoda/instance.json"
  out="$(cd "$pd" && CYODA_PLUGIN_CONFIG="$T/g.json" bash "$S/cyoda-status.sh")"
  assert_contains "$(echo "$out" | head -n1)" "STATUS=unreachable PROFILE=shop" "project binding unreachable"
  assert_contains "$out" "WARN=project shop is bound to http://localhost:1, which is unreachable; start that instance, or type /cyoda:setup to link this project to another one" "project unreachable warn"
  if [[ "$out" == *"switch to default"* ]]; then _bad "no switch-to-default offer for a project binding"; else _ok; fi
  stop_server
}

test_status_unknown_env_profile() {
  echo '{"active":"p","profiles":{"p":{"endpoint":"http://localhost:1"}}}' >"$T/g.json"
  local out rc
  out="$(CYODA_PLUGIN_CONFIG="$T/g.json" CYODA_PROFILE=nope bash "$S/cyoda-status.sh" 2>&1)"; rc=$?
  assert_status 1 "$rc" "unknown CYODA_PROFILE: status exits 1"
  assert_contains "$out" "CYODA_PROFILE=nope: no such profile" "unknown CYODA_PROFILE message forwarded"
}

test_status_connected
test_status_project_binding
test_status_unknown_env_profile
test_status_ignores_broken_token_command
test_status_unreachable
test_status_not_configured
test_status_no_config_local_up
test_status_no_config_nothing_listening
test_status_version_mismatch
test_status_stale_token_forwarded
report
