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
umask 022
# Hermetic: temp HOME, and every config is a temp CYODA_PLUGIN_CONFIG.
mkdir -p "$T/home"
cd "$T" || exit 1
export HOME="$T/home"
unset CYODA_PROFILE

test_profile_default_when_no_config() {
  local out
  out="$(unset CYODA_DEFAULT_ENDPOINT; CYODA_PLUGIN_CONFIG="$T/none.json" bash "$S/cyoda-profile.sh")"; local rc=$?
  assert_status 0 "$rc" "exit 0 with no config"
  assert_eq "$(echo "$out" | jq -c .)" '{"profile":"default","endpoint":"http://localhost:8080","env":"development","tokenCommand":null,"warnings":["no saved profile; using the default local instance http://localhost:8080 — type /cyoda:setup to save it"],"source":"default"}' "implicit default profile"
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
  assert_eq "$(echo "$out" | jq -c '[.source, has("projectDir")]')" '["profile",false]' "profile source, no projectDir"
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

# --- project bindings: the "projects" map in the machine-wide config ---

W="$HOME/work"
mkdir -p "$W"
# real <dir>: mkdir -p and echo the physical path
real() { mkdir -p "$1" && (cd "$1" && pwd -P); }
# cfg <projects-json>: config with an active profile g, a profile stg, and the projects map
cfg() {
  jq -n --argjson pr "$1" '{active: "g", profiles: {g: {endpoint: "http://global", env: "development"},
    stg: {endpoint: "http://stg", env: "production", tokenCommand: "/x/stg.sh"}}, projects: $pr}' >"$T/p.json"
}
# prof <cwd> [VAR=VAL ...]: cyoda-profile.sh from <cwd> with that config
prof() { local d="$1"; shift; (cd "$d" && env CYODA_PLUGIN_CONFIG="$T/p.json" "$@" bash "$S/cyoda-profile.sh"); }
fields() { jq -c '[.source, .profile, .endpoint, .env, .tokenCommand, .projectDir]'; }

test_project_wins_over_active() {
  local pd out; pd="$(real "$W/shop")"
  cfg "$(jq -n --arg k "$pd" '{($k): {endpoint: "http://localhost:8082", tokenCommand: "scripts/auth.sh token"}}')"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | fields)" "[\"project\",\"shop\",\"http://localhost:8082\",\"development\",\"scripts/auth.sh token\",\"$pd\"]" "project entry wins over the active profile; env defaults to development"
  assert_eq "$(echo "$out" | jq -c .warnings)" '[]' "no warnings"
}

test_project_subdirectory_matches() {
  local pd out; pd="$(real "$W/sub")"; mkdir -p "$pd/src/deep"
  cfg "$(jq -n --arg k "$pd" '{($k): {endpoint: "http://localhost:8084", env: "production"}}')"
  out="$(prof "$pd/src/deep")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint, .env, .projectDir]')" "[\"project\",\"http://localhost:8084\",\"production\",\"$pd\"]" "a subdirectory of a project matches"
}

test_project_nested_nearest_wins() {
  local outer inner out; outer="$(real "$W/outer")"; inner="$(real "$W/outer/inner")"; mkdir -p "$inner/src" "$outer/src"
  cfg "$(jq -n --arg o "$outer" --arg i "$inner" '{($o): {endpoint: "http://outer"}, ($i): {endpoint: "http://inner"}}')"
  out="$(prof "$inner/src")"
  assert_eq "$(echo "$out" | jq -c '[.endpoint, .profile]')" '["http://inner","inner"]' "the nearest of nested projects wins"
  out="$(prof "$outer/src")"
  assert_eq "$(echo "$out" | jq -r .endpoint)" http://outer "outside the inner project, the outer one applies"
}

test_project_symlinked_cwd() {
  local pd out; pd="$(real "$W/realdir")"; mkdir -p "$pd/src"
  ln -s "$pd" "$W/alias"
  cfg "$(jq -n --arg k "$pd" '{($k): {endpoint: "http://real"}}')"
  out="$(prof "$W/alias/src")"
  assert_eq "$(echo "$out" | jq -c '[.source, .projectDir]')" "[\"project\",\"$pd\"]" "a symlinked cwd matches via -ef"
  cfg "$(jq -n --arg k "$W/alias" '{($k): {endpoint: "http://alias"}}')"
  out="$(prof "$pd/src")"
  assert_eq "$(echo "$out" | jq -c '[.endpoint, .projectDir]')" "[\"http://alias\",\"$W/alias\"]" "a symlink key matches the real cwd; projectDir is the key"
}

test_project_case_variant() {
  local pd out; pd="$(real "$W/casey")"
  if [ ! -d "$W/CASEY" ]; then echo "  skip: case-variant match needs a case-insensitive filesystem" >&2; return; fi
  cfg "$(jq -n --arg k "$W/CASEY" '{($k): {endpoint: "http://case"}}')"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint]')" '["project","http://case"]' "a case-variant key matches on a case-insensitive filesystem"
}

test_project_missing_key_skipped() {
  local pd out; pd="$(real "$W/alive")"
  cfg "$(jq -n --arg k "$pd" '{"/nonexistent/cyoda/gone": {endpoint: "http://gone"}, ($k): {endpoint: "http://alive"}}')"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -r .endpoint)" http://alive "a missing project dir key is skipped"
  out="$(prof "$T")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint, .warnings]')" '["profile","http://global",[]]' "outside any project: the active profile, silently"
}

test_project_env_override() {
  local pd out; pd="$(real "$W/ovr")"
  cfg "$(jq -n --arg k "$pd" '{($k): {endpoint: "http://localhost:8082"}}')"
  out="$(prof "$pd" CYODA_PROFILE=stg)"
  assert_eq "$(echo "$out" | jq -c '[.profile, .endpoint, .env, .tokenCommand, .source, has("projectDir")]')" \
    '["stg","http://stg","production","/x/stg.sh","profile",false]' "CYODA_PROFILE wins over the project entry and the active profile"
}

test_project_env_override_unknown() {
  local err rc
  cfg '{}'
  err="$(prof "$T" CYODA_PROFILE=nope 2>&1 >/dev/null)"; rc=$?
  assert_status 1 "$rc" "unknown CYODA_PROFILE exits 1"
  assert_contains "$err" "CYODA_PROFILE=nope: no such profile in $T/p.json (profiles: g, stg)" "unknown CYODA_PROFILE message"
  err="$(cd "$T" && CYODA_PLUGIN_CONFIG="$T/none.json" CYODA_PROFILE=nope bash "$S/cyoda-profile.sh" 2>&1 >/dev/null)"; rc=$?
  assert_status 1 "$rc" "unknown CYODA_PROFILE without a config exits 1"
  assert_contains "$err" "CYODA_PROFILE=nope: no such profile" "message without a config"
}

test_projects_only_config_keeps_implicit_default() {
  local pd out; pd="$(real "$W/only")"
  jq -n --arg k "$pd" '{projects: {($k): {endpoint: "http://only"}}}' >"$T/only.json"
  out="$(cd "$pd" && CYODA_PLUGIN_CONFIG="$T/only.json" bash "$S/cyoda-profile.sh")"
  assert_eq "$(echo "$out" | jq -r .endpoint)" http://only "a config holding only projects: the project matches"
  out="$(cd "$T" && CYODA_PLUGIN_CONFIG="$T/only.json" CYODA_DEFAULT_ENDPOINT=http://localhost:1 bash "$S/cyoda-profile.sh")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint]')" '["default","http://localhost:1"]' "elsewhere it keeps the implicit default (no profiles saved)"
}

test_project_planted_file_never_read() {
  # Regression for the removed in-tree binding files: a planted .cyoda/ is just data.
  local pd out; pd="$(real "$W/planted")"; mkdir -p "$pd/.cyoda"
  jq -n --arg tc "touch $T/pwned; echo tok" '{endpoint: "http://attacker", tokenCommand: $tc}' >"$pd/.cyoda/instance.json"
  cp "$pd/.cyoda/instance.json" "$pd/.cyoda/config"
  cfg '{}'
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint, .tokenCommand]')" '["profile","http://global",null]' "no entry: an in-tree .cyoda/ file is ignored"
  cfg "$(jq -n --arg k "$pd" '{($k): {endpoint: "http://mine"}}')"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint, .tokenCommand]')" '["project","http://mine",null]' "with an entry: only the entry is used"
}

test_profile_default_when_no_config
test_profile_existing_config_without_endpoint
test_profile_active_selected
test_profile_stale_token
test_profile_invalid_json
test_project_wins_over_active
test_project_subdirectory_matches
test_project_nested_nearest_wins
test_project_symlinked_cwd
test_project_case_variant
test_project_missing_key_skipped
test_project_env_override
test_project_env_override_unknown
test_projects_only_config_keeps_implicit_default
test_project_planted_file_never_read
report
