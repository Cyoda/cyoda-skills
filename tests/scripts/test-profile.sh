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
# Hermetic: no project binding from the caller's working directory, no real HOME.
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

# --- project binding (.cyoda/instance.json, legacy .cyoda/config) ---

GLOBAL="$T/global.json"
echo '{"active":"g","profiles":{"g":{"endpoint":"http://global","env":"development"},"stg":{"endpoint":"http://stg","env":"production","tokenCommand":"/x/stg.sh"}}}' >"$GLOBAL"

# mkproj <dir>: creates <dir>/.cyoda and echoes the physical path of <dir>
mkproj() { mkdir -p "$1/.cyoda" && (cd "$1" && pwd -P); }
# prof <cwd> [VAR=VAL ...]: runs cyoda-profile.sh from <cwd> with the global config
prof() { local d="$1"; shift; (cd "$d" && env CYODA_PLUGIN_CONFIG="$GLOBAL" "$@" bash "$S/cyoda-profile.sh"); }

test_profile_project_wins_over_active() {
  local pd out; pd="$(mkproj "$HOME/work/shop")"
  echo '{"endpoint":"http://localhost:8082","env":"development","tokenCommand":"scripts/auth.sh token"}' >"$pd/.cyoda/instance.json"
  mkdir -p "$pd/src/deep"
  out="$(prof "$pd/src/deep")"
  assert_eq "$(echo "$out" | jq -c '[.profile, .endpoint, .env, .tokenCommand, .source, .projectDir]')" \
    "[\"shop\",\"http://localhost:8082\",\"development\",\"scripts/auth.sh token\",\"project\",\"$pd\"]" "project file wins, found from a subdirectory"
  assert_eq "$(echo "$out" | jq -c .warnings)" '[]' "no warnings for a clean project file"
}

test_profile_project_env_defaults() {
  local pd out; pd="$(mkproj "$HOME/work/envless")"
  echo '{"endpoint":"http://localhost:8084"}' >"$pd/.cyoda/instance.json"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -c '[.env, .tokenCommand]')" '["development",null]' "project env defaults to development, no tokenCommand"
}

test_profile_project_production() {
  local pd out; pd="$(mkproj "$HOME/work/live")"
  echo '{"endpoint":"https://live.example.com","env":"production"}' >"$pd/.cyoda/instance.json"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -r .env)" production "project production env"
}

test_profile_legacy_config() {
  local pd out; pd="$(mkproj "$HOME/work/sioms")"
  echo '{"endpoint":"http://localhost:8080","env":"development","token":"eyJsecret","tokenCommand":"/evil.sh"}' >"$pd/.cyoda/config"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -c '[.profile, .endpoint, .env, .tokenCommand, .source, .projectDir]')" \
    "[\"sioms\",\"http://localhost:8080\",\"development\",null,\"project\",\"$pd\"]" "legacy .cyoda/config: endpoint and env only"
  assert_eq "$(echo "$out" | jq -r '.warnings[0]')" "$pd/.cyoda/config contains a stored token, which this plugin no longer reads; you can remove it" "legacy token warning"
  if [[ "$out" == *eyJsecret* ]]; then _bad "legacy token echoed"; else _ok; fi
}

test_profile_instance_wins_over_legacy() {
  local pd out; pd="$(mkproj "$HOME/work/both")"
  echo '{"endpoint":"http://localhost:8080"}' >"$pd/.cyoda/config"
  echo '{"endpoint":"http://localhost:8086","env":"development"}' >"$pd/.cyoda/instance.json"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -r .endpoint)" http://localhost:8086 "instance.json wins over legacy config"
}

test_profile_search_stops_at_git_root() {
  local outer out; outer="$(mkproj "$HOME/work/outer")"
  echo '{"endpoint":"http://outer"}' >"$outer/.cyoda/instance.json"
  mkdir -p "$outer/repo/sub"
  git -C "$outer/repo" init -q
  out="$(prof "$outer/repo/sub")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint]')" '["profile","http://global"]' ".cyoda above the git root is not used"
  mkdir -p "$outer/repo/.cyoda"
  echo '{"endpoint":"http://repo"}' >"$outer/repo/.cyoda/instance.json"
  out="$(prof "$outer/repo/sub")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint]')" '["project","http://repo"]' ".cyoda at the git root is used"
}

test_profile_search_never_uses_home() {
  mkdir -p "$HOME/.cyoda" "$HOME/plain"
  echo '{"endpoint":"http://home"}' >"$HOME/.cyoda/instance.json"
  local out; out="$(prof "$HOME/plain")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint]')" '["profile","http://global"]' "\$HOME/.cyoda is never a project binding"
  out="$(prof "$HOME")"
  assert_eq "$(echo "$out" | jq -r .source)" profile "not even from \$HOME itself"
  rm -rf "$HOME/.cyoda"
}

test_profile_env_override() {
  local pd out; pd="$(mkproj "$HOME/work/ovr")"
  echo '{"endpoint":"http://localhost:8082"}' >"$pd/.cyoda/instance.json"
  out="$(prof "$pd" CYODA_PROFILE=stg)"
  assert_eq "$(echo "$out" | jq -c '[.profile, .endpoint, .env, .tokenCommand, .source, has("projectDir")]')" \
    '["stg","http://stg","production","/x/stg.sh","profile",false]' "CYODA_PROFILE wins over the project file and the active profile"
}

test_profile_env_override_unknown() {
  local err rc
  err="$(prof "$T" CYODA_PROFILE=nope 2>&1 >/dev/null)"; rc=$?
  assert_status 1 "$rc" "unknown CYODA_PROFILE exits 1"
  assert_contains "$err" "CYODA_PROFILE=nope: no such profile in $GLOBAL (profiles: g, stg)" "unknown CYODA_PROFILE message"
  err="$(cd "$T" && CYODA_PLUGIN_CONFIG="$T/none.json" CYODA_PROFILE=nope bash "$S/cyoda-profile.sh" 2>&1 >/dev/null)"; rc=$?
  assert_status 1 "$rc" "unknown CYODA_PROFILE without a config exits 1"
  assert_contains "$err" "CYODA_PROFILE=nope: no such profile" "message without a config"
}

test_profile_invalid_project_file() {
  local pd err rc; pd="$(mkproj "$HOME/work/broken")"
  echo '{oops' >"$pd/.cyoda/instance.json"
  err="$(prof "$pd" 2>&1 >/dev/null)"; rc=$?
  assert_status 1 "$rc" "invalid project file exits 1"
  assert_contains "$err" "invalid config: $pd/.cyoda/instance.json" "invalid project file message"
}

test_profile_symlinked_cwd() {
  local pd out; pd="$(mkproj "$HOME/work/real")"
  echo '{"endpoint":"http://localhost:8088"}' >"$pd/.cyoda/instance.json"
  mkdir -p "$pd/src"
  ln -s "$pd" "$HOME/work/alias"
  out="$(prof "$HOME/work/alias/src")"
  assert_eq "$(echo "$out" | jq -c '[.source, .profile, .projectDir]')" "[\"project\",\"real\",\"$pd\"]" "symlinked working dir: binding found, projectDir is the physical path"
}

test_profile_outside_home_no_git_no_climb() {
  local out base; base="$(mkdir -p "$T/outside/proj/sub" && cd "$T/outside" && pwd -P)"
  mkdir -p "$base/proj/.cyoda"
  echo '{"endpoint":"http://outside"}' >"$base/proj/.cyoda/instance.json"
  out="$(prof "$base/proj/sub")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint]')" '["profile","http://global"]' "outside \$HOME without git: a parent .cyoda is not used"
  out="$(prof "$base/proj")"
  assert_eq "$(echo "$out" | jq -c '[.source, .endpoint]')" '["project","http://outside"]' "outside \$HOME without git: \$PWD itself is used"
}

test_profile_corrupt_legacy_next_to_instance() {
  local pd out rc; pd="$(mkproj "$HOME/work/corrupt")"
  echo '{oops' >"$pd/.cyoda/config"
  echo '{"endpoint":"http://localhost:8090"}' >"$pd/.cyoda/instance.json"
  out="$(prof "$pd" 2>/dev/null)"; rc=$?
  assert_status 0 "$rc" "corrupt legacy file next to a valid instance.json: exit 0"
  assert_eq "$(echo "$out" | jq -r .endpoint)" http://localhost:8090 "instance.json used despite a corrupt legacy file"
}

# trust <name>: a project with a tokenCommand; echoes its physical dir
trusted_proj() {
  local pd; pd="$(mkproj "$HOME/work/$1")"
  echo '{"endpoint":"http://localhost:8092","tokenCommand":"scripts/auth.sh token"}' >"$pd/.cyoda/instance.json"
  chmod 600 "$pd/.cyoda/instance.json"
  echo "$pd"
}

test_profile_token_command_trusted() {
  local pd out; pd="$(trusted_proj trusted)"
  git -C "$pd" init -q
  echo '.cyoda/' >"$pd/.gitignore"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -c '[.tokenCommand, .warnings]')" '["scripts/auth.sh token",[]]' "own, 0600, untracked: tokenCommand used"
}

test_profile_token_command_not_owned() {
  local pd out; pd="$(trusted_proj notmine)"
  mkdir -p "$T/idshim"
  # shellcheck disable=SC2016 # literal script text
  printf '#!/usr/bin/env bash\nif [ "$1" = -u ]; then echo 4242; else exec /usr/bin/id "$@"; fi\n' >"$T/idshim/id"
  chmod +x "$T/idshim/id"
  out="$(prof "$pd" PATH="$T/idshim:$PATH")"
  assert_eq "$(echo "$out" | jq -c '[.endpoint, .tokenCommand]')" '["http://localhost:8092",null]' "file not owned by you: tokenCommand dropped"
  assert_eq "$(echo "$out" | jq -r '.warnings[0]')" "tokenCommand in $pd/.cyoda/instance.json ignored: the file is not owned by you" "not-owned warning"
}

test_profile_token_command_group_writable() {
  local pd out; pd="$(trusted_proj shared)"
  chmod 664 "$pd/.cyoda/instance.json"
  mkdir -p "$pd/work/sub"
  out="$(prof "$pd/work/sub")"
  assert_eq "$(echo "$out" | jq -r .tokenCommand)" null "group-writable file: tokenCommand dropped"
  assert_eq "$(echo "$out" | jq -r '.warnings[0]')" "tokenCommand in $pd/.cyoda/instance.json ignored: the file is group- or world-writable; run chmod 600 on it" "group-writable warning"
  chmod 606 "$pd/.cyoda/instance.json"
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -r .tokenCommand)" null "world-writable file: tokenCommand dropped"
}

test_profile_token_command_tracked() {
  local pd out; pd="$(trusted_proj tracked)"
  git -C "$pd" init -q
  git -C "$pd" add -f .cyoda/instance.json
  out="$(prof "$pd")"
  assert_eq "$(echo "$out" | jq -r .tokenCommand)" null "tracked instance.json: tokenCommand dropped"
  assert_eq "$(echo "$out" | jq -r '.warnings[0]')" "tokenCommand in $pd/.cyoda/instance.json ignored: the file is tracked by git; run git rm --cached on it and keep .cyoda/ in .gitignore" "tracked warning"
  assert_eq "$(echo "$out" | jq -r .endpoint)" http://localhost:8092 "tracked: endpoint still used"
}

test_profile_default_when_no_config
test_profile_existing_config_without_endpoint
test_profile_active_selected
test_profile_stale_token
test_profile_invalid_json
test_profile_project_wins_over_active
test_profile_project_env_defaults
test_profile_project_production
test_profile_legacy_config
test_profile_instance_wins_over_legacy
test_profile_search_stops_at_git_root
test_profile_search_never_uses_home
test_profile_env_override
test_profile_env_override_unknown
test_profile_invalid_project_file
test_profile_symlinked_cwd
test_profile_outside_home_no_git_no_climb
test_profile_corrupt_legacy_next_to_instance
test_profile_token_command_trusted
test_profile_token_command_not_owned
test_profile_token_command_group_writable
test_profile_token_command_tracked
report
