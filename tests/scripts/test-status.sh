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

test_status_connected() {
  start_server || return
  echo "{\"active\":\"p\",\"profiles\":{\"p\":{\"endpoint\":\"http://localhost:${SMOKE_HTTP_PORT}\"}}}" >"$T/i.json"
  local out
  out="$(CYODA_PLUGIN_CONFIG="$T/i.json" bash "$S/cyoda-status.sh")"
  assert_contains "$(echo "$out" | head -n1)" "STATUS=connected" "connected"
  assert_contains "$out" "VERSION=0.8.4" "version"
  assert_contains "$out" "PROFILE=p" "profile"
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
  local out; out="$(CYODA_PLUGIN_CONFIG="$T/none.json" bash "$S/cyoda-status.sh")"
  assert_contains "$out" "STATUS=not_configured" "not configured"
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

test_status_connected
test_status_ignores_broken_token_command
test_status_unreachable
test_status_not_configured
test_status_version_mismatch
test_status_stale_token_forwarded
report
