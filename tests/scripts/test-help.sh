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
export CYODA_PLUGIN_CONFIG="$T/none.json"

test_help_section_from_binary() {
  local out err
  out="$(bash "$S/cyoda-help.sh" models --section LIFECYCLE 2>"$T/err")"
  assert_contains "$out" LOCKED "section body"
  assert_contains "$(cat "$T/err")" "SOURCE=binary" "binary source"
}

test_help_unknown_topic() {
  bash "$S/cyoda-help.sh" no such topic >/dev/null 2>&1; assert_status 2 "$?" "unknown topic"
}

test_help_unknown_section() {
  local err rc
  err="$(bash "$S/cyoda-help.sh" models --section NOPE 2>&1 >/dev/null)"; rc=$?
  assert_status 6 "$rc" "unknown section"
  assert_contains "$err" LIFECYCLE "lists sections"
}

test_help_prefers_instance() {
  start_server || return
  echo "{\"active\":\"p\",\"profiles\":{\"p\":{\"endpoint\":\"http://localhost:${SMOKE_HTTP_PORT}\"}}}" >"$T/i.json"
  local out
  out="$(CYODA_PLUGIN_CONFIG="$T/i.json" bash "$S/cyoda-help.sh" auth tokens 2>"$T/err")"; local rc=$?
  assert_status 0 "$rc" "instance help ok"
  assert_contains "$(head -n1 "$T/err")" "SOURCE=instance VERSION=0.8.4" "instance source"
  [ -n "$out" ] && _ok || _bad "empty body"
  CYODA_PLUGIN_CONFIG="$T/i.json" bash "$S/cyoda-help.sh" no such topic >/dev/null 2>&1
  assert_status 2 "$?" "unknown topic via instance"
  stop_server
}

test_help_ignores_broken_token_command() {
  start_server || return
  echo "{\"active\":\"p\",\"profiles\":{\"p\":{\"endpoint\":\"http://localhost:${SMOKE_HTTP_PORT}\",\"tokenCommand\":\"false\"}}}" >"$T/b.json"
  CYODA_PLUGIN_CONFIG="$T/b.json" bash "$S/cyoda-help.sh" auth tokens >/dev/null 2>"$T/err"
  assert_contains "$(head -n1 "$T/err")" "SOURCE=instance VERSION=0.8.4" "broken tokenCommand ignored"
  stop_server
}

test_help_action_from_binary() {
  local out rc
  out="$(bash "$S/cyoda-help.sh" workflows schema-version versions 2>"$T/err")"; rc=$?
  assert_status 0 "$rc" "action via binary"
  assert_eq "$(jq -r .current <<<"$out")" "1.4" "action JSON verbatim"
  assert_contains "$(head -n1 "$T/err")" "SOURCE=binary" "binary source for action"
  bash "$S/cyoda-help.sh" workflows schema-version versions --section X >/dev/null 2>&1
  assert_status 6 "$?" "--section rejected for action"
}

test_help_action_from_instance() {
  start_server || return
  echo "{\"active\":\"p\",\"profiles\":{\"p\":{\"endpoint\":\"http://localhost:${SMOKE_HTTP_PORT}\"}}}" >"$T/a.json"
  local out rc
  out="$(CYODA_PLUGIN_CONFIG="$T/a.json" bash "$S/cyoda-help.sh" workflows schema-version versions 2>"$T/err")"; rc=$?
  assert_status 0 "$rc" "action via instance"
  assert_eq "$(jq -r .current <<<"$out")" "1.4" "instance action JSON verbatim"
  assert_contains "$(head -n1 "$T/err")" "SOURCE=instance VERSION=0.8.4" "instance source for action"
  stop_server
}

test_help_section_from_binary
test_help_action_from_binary
test_help_action_from_instance
test_help_ignores_broken_token_command
test_help_unknown_topic
test_help_unknown_section
test_help_prefers_instance
report
