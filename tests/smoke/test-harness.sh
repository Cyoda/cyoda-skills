#!/usr/bin/env bash
# Tests for the smoke harness itself.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
# shellcheck source=../lib/server.sh
source "$ROOT/tests/lib/server.sh"

TMPS=()
cleanup() { stop_server 2>/dev/null; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

mktree() { local d; d="$(mktemp -d)"; TMPS+=("$d"); mkdir -p "$d/cyoda/skills/design" "$d/cyoda/skills/compute" "$d/cyoda/skills/x/evaluations"; echo "$d"; }
port_free() { ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

test_server_starts_and_stops() {
  start_server || { assert_eq "start failed" "started" "server starts"; return; }
  assert_eq "$(curl -s "$BASE/health")" '{"status":"UP"}' "health is UP"
  stop_server
  assert_eq "$(port_free 18080 && echo free)" "free" "port 18080 free after stop"
}

test_runner_ignores_user_cyoda_env() {
  local fx; fx="$(mktemp -d)"; TMPS+=("$fx")
  mkdir -p "$fx/.config/cyoda"
  echo "CYODA_IAM_MODE=jwt" > "$fx/.config/cyoda/cyoda.env"
  local saved="$HOME"
  HOME="$fx"; export HOME
  start_server || { HOME="$saved"; assert_eq "start failed" "started" "server starts"; return; }
  local code; code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/model/")"
  assert_status 200 "$code" "model list without auth"
  assert_contains "$(cat "$SMOKE_TMP/server.log")" "IAM mock" "log says IAM mock"
  stop_server
  assert_eq "$HOME" "$fx" "HOME restored after stop"
  HOME="$saved"; export HOME
}

test_start_server_extra_env_overrides() {
  start_server CYODA_IAM_MODE=mock CYODA_LOG_LEVEL=debug || { assert_eq "start failed" "started" "start with extra env"; return; }
  assert_eq "$(curl -s "$BASE/health")" '{"status":"UP"}' "healthy with extra env"
  stop_server
}

test_start_server_refuses_busy_port() {
  nc -l 18080 >/dev/null 2>&1 & local ncpid=$!
  sleep 0.5
  local out rc
  out="$(start_server 2>&1)"; rc=$?
  kill "$ncpid" 2>/dev/null; wait "$ncpid" 2>/dev/null
  assert_eq "$rc" "1" "start_server fails on busy port"
  assert_contains "$out" "in use" "message says port in use"
  stop_server 2>/dev/null
}

# lint_case <rule> <relative path> <bad line>: rule must fire on bad line
lint_fires() {
  local rule="$1" rel="$2" line="$3" d out rc
  d="$(mktree)"; mkdir -p "$(dirname "$d/$rel")"; printf '%s\n' "$line" > "$d/$rel"
  out="$(LINT_SKIP_SHELLCHECK=1 bash "$ROOT/tests/smoke/lint.sh" --root "$d" 2>&1)"; rc=$?
  assert_eq "$rc" "1" "$rule: exit 1 on bad line"
  assert_contains "$out" "$rule" "$rule: reported"
}
# lint_quiet <rel> <clean line>: no rule fires
lint_quiet() {
  local rel="$1" line="$2" d out rc
  d="$(mktree)"; mkdir -p "$(dirname "$d/$rel")"; printf '%s\n' "$line" > "$d/$rel"
  out="$(LINT_SKIP_SHELLCHECK=1 bash "$ROOT/tests/smoke/lint.sh" --root "$d" 2>&1)"; rc=$?
  assert_eq "$rc" "0" "clean line passes: $line ($out)"
}

test_lint_flags_stale_strings() {
  local d out rc
  d="$(mktree)"
  printf 'brew tap cyoda-platform/cyoda-go\n{"version": "1"}\n' > "$d/cyoda/skills/design/SKILL.md"
  out="$(LINT_SKIP_SHELLCHECK=1 bash "$ROOT/tests/smoke/lint.sh" --root "$d" 2>&1)"; rc=$?
  assert_eq "$rc" "1" "lint exits 1"
  assert_contains "$out" "stale-tap" "stale-tap reported"
  assert_contains "$out" "workflow-version-1" "workflow-version-1 reported"
  assert_contains "$out" "SKILL.md:1: stale-tap" "file:line: rule format"
}

test_lint_every_rule_fires() {
  local D=cyoda/skills/design/SKILL.md C=cyoda/skills/compute/SKILL.md
  lint_fires stale-tap "$D" 'brew tap cyoda-platform/cyoda-go'
  lint_fires stale-org-url "$D" 'see https://github.com/Cyoda-platform/foo'
  lint_fires workflow-version-1 "$D" '  "version": "1",'
  lint_fires readyz-api-port "$D" 'curl localhost:8080/readyz'
  lint_fires discover-mode "$D" 'use Discover mode here'
  lint_fires discover-mode "$D" 'use discover mode here'
  lint_fires timeout-60s "$C" 'default timeout is 60s'
  lint_fires timeout-60s cyoda/skills/debug/SKILL.md 'waits 60 seconds'
  lint_fires cloud "$D" 'deploy to Cyoda Cloud'
  lint_fires cloud "$D" 'host foo.cyoda.net is used'
  lint_fires invoke-flagged "$D" 'Invoke /cyoda:build next'
  # shellcheck disable=SC2016 # literal text is intentional (written to a file/passed to envsubst/eval later)
  lint_fires invoke-flagged "$D" 'invoke `/cyoda:setup`'
  # shellcheck disable=SC2016 # literal text is intentional (written to a file/passed to envsubst/eval later)
  lint_fires model-list-no-slash "$D" 'curl $BASE/api/model"'
  lint_fires model-list-no-slash "$D" 'GET /api/model '
}

test_lint_clean_lines_pass() {
  local D=cyoda/skills/design/SKILL.md
  lint_quiet "$D" 'brew install cyoda-platform/cyoda/cyoda'
  lint_quiet "$D" '"version": "2"'
  lint_quiet "$D" 'curl localhost:9091/readyz'
  lint_quiet "$D" 'admin port serves /readyz'
  lint_quiet "$D" 'use the import mode'
  lint_quiet "$D" 'timeout is 60s'   # outside compute/debug
  lint_quiet cyoda/skills/compute/SKILL.md 'timeout 600s or 160s'
  lint_quiet "$D" 'see https://docs.cyoda.net/foo'
  lint_quiet "$D" 'Invoke /cyoda:docs for help'
  lint_quiet "$D" 'GET /api/model/ lists models'
  lint_quiet "$D" 'GET /api/model/export/SIMPLE_VIEW'
}

test_lint_excludes_evaluations() {
  lint_quiet cyoda/skills/x/evaluations/evals.json 'brew tap cyoda-platform/cyoda-go'
}

test_lint_shellcheck_rule() {
  local d out rc
  d="$(mktree)"; mkdir -p "$d/cyoda/scripts"
  # shellcheck disable=SC2016 # fixture script must contain a literal $1
  printf '#!/usr/bin/env bash\necho $1\n' > "$d/cyoda/scripts/bad.sh"
  out="$(bash "$ROOT/tests/smoke/lint.sh" --root "$d" 2>&1)"; rc=$?
  assert_eq "$rc" "1" "shellcheck rule exit 1"
  if command -v shellcheck >/dev/null 2>&1 || command -v uvx >/dev/null 2>&1; then
    assert_contains "$out" "[shellcheck]" "bad script flagged by shellcheck (local or uvx fallback)"
  else
    assert_contains "$out" "brew install shellcheck" "missing shellcheck gives install hint"
  fi
  # LINT_SHELLCHECK_CMD selects the checker; lint passes -x -P SCRIPTDIR -f gcc and the files.
  printf '#!/usr/bin/env bash\necho "ARGS: $*"; exit 1\n' >"$d/fakesc"; chmod +x "$d/fakesc"
  out="$(LINT_SHELLCHECK_CMD="$d/fakesc" bash "$ROOT/tests/smoke/lint.sh" --root "$d" 2>&1)"; rc=$?
  assert_eq "$rc" "1" "override checker failing -> lint exit 1"
  assert_contains "$out" "ARGS: -x -P SCRIPTDIR -f gcc" "override checker invoked with -x -P SCRIPTDIR -f gcc"
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  echo "== $t"
  "$t"
done
report
