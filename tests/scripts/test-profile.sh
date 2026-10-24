#!/usr/bin/env bash
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

test_profile_default_when_no_config() {
  local out
  out="$(unset CYODA_DEFAULT_ENDPOINT; CYODA_PLUGIN_CONFIG="$T/none.json" bash "$S/cyoda-profile.sh")"; local rc=$?
  assert_status 0 "$rc" "exit 0 with no config"
  assert_eq "$(echo "$out" | jq -c .)" '{"profile":"default","endpoint":"http://localhost:8080","env":"development","tokenCommand":null,"warnings":["no saved profile; using the default local instance http://localhost:8080 — type /cyoda:setup to save it"]}' "implicit default profile"
}

test_profile_existing_config_without_endpoint() {
  echo '{"profiles":{}}' >"$T/empty.json"
  local out; out="$(CYODA_PLUGIN_CONFIG="$T/empty.json" bash "$S/cyoda-profile.sh")"
  assert_eq "$(echo "$out" | jq -c '[.profile, .endpoint, .warnings]')" '["default",null,[]]' "existing config: no implicit endpoint"
}

test_profile_active_selected() {
  cat >"$T/c.json" <<'J'
{"active":"stg","profiles":{"default":{"endpoint":"http://a"},"stg":{"endpoint":"http://b","env":"production","tokenCommand":"/x/tok.sh"}}}
J
  local out; out="$(CYODA_PLUGIN_CONFIG="$T/c.json" bash "$S/cyoda-profile.sh")"
  assert_eq "$(echo "$out" | jq -r .profile)" stg "active name"
  assert_eq "$(echo "$out" | jq -r .endpoint)" http://b "active endpoint"
  assert_eq "$(echo "$out" | jq -r .env)" production "active env"
  assert_eq "$(echo "$out" | jq -r .tokenCommand)" /x/tok.sh "active tokenCommand"
  cat >"$T/d.json" <<'J'
{"profiles":{"default":{"endpoint":"http://a"}}}
J
  out="$(CYODA_PLUGIN_CONFIG="$T/d.json" bash "$S/cyoda-profile.sh")"
  assert_eq "$(echo "$out" | jq -r '.endpoint + "/" + .env')" "http://a/development" "env defaults to development"
}

test_profile_stale_token() {
  echo '{"active":"old","profiles":{"old":{"endpoint":"http://a","token":"eyJabc"}}}' >"$T/e.json"
  local out; out="$(CYODA_PLUGIN_CONFIG="$T/e.json" bash "$S/cyoda-profile.sh")"
  assert_eq "$(echo "$out" | jq -r '.warnings[0]')" "profile old contains a stored token, which this plugin no longer reads; you can remove it" "stale token warning"
  assert_eq "$(echo "$out" | jq -r 'has("token")')" false "token not echoed"
}

test_profile_invalid_json() {
  echo '{not json' >"$T/bad.json"
  local err rc
  err="$(CYODA_PLUGIN_CONFIG="$T/bad.json" bash "$S/cyoda-profile.sh" 2>&1 >/dev/null)"; rc=$?
  assert_status 1 "$rc" "invalid json exits 1"
  assert_contains "$err" "invalid config: $T/bad.json" "invalid config message"
}

test_profile_default_when_no_config
test_profile_existing_config_without_endpoint
test_profile_active_selected
test_profile_stale_token
test_profile_invalid_json
report
