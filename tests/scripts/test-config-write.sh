#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq filters are single-quoted on purpose
# cyoda-config-write.sh: the one way skills change the plugin config.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S="$ROOT/cyoda/scripts"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
T="$(mktemp -d)"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
umask 022

mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
W() { CYODA_PLUGIN_CONFIG="$CFG" bash "$S/cyoda-config-write.sh" "$@"; }

test_config_write_tightens_mode_and_preserves() {
  CFG="$T/a/cfg.json"; mkdir -p "$T/a"
  echo '{"active":"g","profiles":{"g":{"endpoint":"http://g"}},"projects":{"/old":{"endpoint":"http://old"}}}' >"$CFG"
  chmod 644 "$CFG"
  local rc; W '.projects[$k] = {endpoint: $ep, env: "development"}' --arg k "/Users/paul's app" --arg ep http://x; rc=$?
  assert_status 0 "$rc" "write ok"
  assert_eq "$(mode "$CFG")" 600 "a 644 config ends up 600"
  assert_eq "$(jq -c '[.active, .profiles.g.endpoint, .projects["/old"].endpoint, .projects["/Users/paul'"'"'s app"].endpoint]' "$CFG")" '["g","http://g","http://old","http://x"]' "other sections preserved; a value with an apostrophe arrives intact via --arg"
  assert_eq "$(ls "$T/a")" "cfg.json" "no temp file left behind"
}

test_config_write_creates_private_dir() {
  CFG="$T/new/sub/cfg.json"
  local rc; W '.profiles.default = {endpoint: "http://localhost:8080", env: "development"} | .active = "default"'; rc=$?
  assert_status 0 "$rc" "creates a missing config"
  assert_eq "$(mode "$T/new/sub")" 700 "missing config dir created 0700"
  assert_eq "$(mode "$CFG")" 600 "new config 600"
  assert_eq "$(jq -c . "$CFG")" '{"profiles":{"default":{"endpoint":"http://localhost:8080","env":"development"}},"active":"default"}' "starts from {}"
}

test_config_write_rejects_bad_filter_or_result() {
  CFG="$T/b/cfg.json"; mkdir -p "$T/b"
  echo '{"active":"g"}' >"$CFG"
  local rc err
  err="$(W '.active = ' 2>&1)"; rc=$?
  assert_status 1 "$rc" "bad filter: exit 1"
  assert_eq "$(jq -c . "$CFG")" '{"active":"g"}' "bad filter: config untouched"
  err="$(W '[.]' 2>&1)"; rc=$?
  assert_status 1 "$rc" "non-object result: exit 1"
  assert_contains "$err" "not a JSON object" "non-object result message"
  assert_eq "$(jq -c . "$CFG")" '{"active":"g"}' "non-object result: config untouched"
  echo '{oops' >"$CFG"
  err="$(W '.active = "x"' 2>&1)"; rc=$?
  assert_status 1 "$rc" "invalid existing config: exit 1"
  assert_contains "$err" "invalid config: $CFG" "invalid existing config message"
  assert_eq "$(ls "$T/b")" "cfg.json" "no temp file left behind on failure"
}

test_config_write_denied() {
  CFG="$T/ro/cfg.json"; mkdir -p "$T/ro"; echo '{}' >"$CFG"; chmod 500 "$T/ro"
  local rc err
  err="$(W '.active = "x"' 2>&1)"; rc=$?
  chmod 700 "$T/ro"
  assert_status 3 "$rc" "unwritable dir: exit 3"
  assert_contains "$err" "cannot write $CFG" "unwritable message"
  assert_eq "$(jq -c . "$CFG")" '{}' "unwritable: config untouched"
}

test_config_write_usage() {
  local rc; CFG="$T/u.json"; W >/dev/null 2>&1; rc=$?
  assert_status 64 "$rc" "no filter: usage exit 64"
}

test_config_write_tightens_mode_and_preserves
test_config_write_creates_private_dir
test_config_write_rejects_bad_filter_or_result
test_config_write_denied
test_config_write_usage
report
