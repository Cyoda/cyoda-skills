#!/usr/bin/env bash
# get-token.sh (the auth skill's template) against a jwt-mode cyoda-go
# with a bootstrap M2M client.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S="$ROOT/cyoda/scripts"
GT="$ROOT/cyoda/skills/auth/templates/get-token.sh"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
# shellcheck source=../lib/server.sh
source "$ROOT/tests/lib/server.sh"
trap 'stop_server; rm -rf "${T:-}"' EXIT

T="$(mktemp -d)"
EP="http://localhost:${SMOKE_HTTP_PORT}"

# start_server makes its own SMOKE_TMP, so the key lives in $T.
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$T/k.pem" 2>/dev/null

start_jwt_server() {
  start_server CYODA_IAM_MODE=jwt CYODA_JWT_SIGNING_KEY_FILE="$T/k.pem" \
    CYODA_BOOTSTRAP_CLIENT_ID=smoke CYODA_BOOTSTRAP_CLIENT_SECRET=s3cret
}

is_jwt() { # 3 base64url parts
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$'
}

test_template_exists() {
  if [ -f "$GT" ]; then _ok; else _bad "get-token.sh template exists at $GT"; fi
}

test_prints_jwt() {
  local out rc=0
  out="$(CYODA_ENDPOINT="$EP" CYODA_CLIENT_ID=smoke CYODA_CLIENT_SECRET=s3cret bash "$GT" 2>"$T/err")" || rc=$?
  assert_status 0 "$rc" "get-token exits 0 (stderr: $(cat "$T/err"))"
  if is_jwt "$out"; then _ok; else _bad "prints a 3-part JWT and nothing else" "actual: $out"; fi
  assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1" "stdout is one line"
}

test_secret_cmd() {
  local out rc=0
  out="$(CYODA_ENDPOINT="$EP" CYODA_CLIENT_ID=smoke CYODA_CLIENT_SECRET=wrong \
    CYODA_CLIENT_SECRET_CMD='printf %s s3cret' bash "$GT" 2>/dev/null)" || rc=$?
  assert_status 0 "$rc" "CYODA_CLIENT_SECRET_CMD takes precedence over CYODA_CLIENT_SECRET"
  if is_jwt "$out"; then _ok; else _bad "secret-cmd path prints a JWT" "actual: $out"; fi
}

test_call_with_token_command() {
  # Negative control: without a tokenCommand the jwt server refuses.
  echo "{\"active\":\"j\",\"profiles\":{\"j\":{\"endpoint\":\"$EP\",\"env\":\"development\"}}}" >"$T/n.json"
  local rc=0
  CYODA_PLUGIN_CONFIG="$T/n.json" bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>"$T/err" || rc=$?
  assert_status 22 "$rc" "no tokenCommand → 401 on a jwt instance (control)"
  assert_contains "$(cat "$T/err")" "HTTP_STATUS=401" "control is a 401"

  # With tokenCommand: CYODA_ENDPOINT comes from cyoda-call.sh (R1), not the caller.
  jq -n --arg ep "$EP" --arg tc "$GT" \
    '{active:"j",profiles:{j:{endpoint:$ep,env:"development",tokenCommand:$tc}}}' >"$T/j.json"
  rc=0
  (unset CYODA_ENDPOINT; CYODA_CLIENT_ID=smoke CYODA_CLIENT_SECRET=s3cret \
    CYODA_PLUGIN_CONFIG="$T/j.json" bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>"$T/err") || rc=$?
  assert_status 0 "$rc" "cyoda-call.sh GET /model/ with tokenCommand=get-token.sh (stderr: $(cat "$T/err"))"

  # Per-profile credentials set in front of the script (auth skill, Step 6).
  jq -n --arg ep "$EP" --arg tc "CYODA_CLIENT_ID=smoke CYODA_CLIENT_SECRET_CMD='printf %s s3cret' $GT" \
    '{active:"j",profiles:{j:{endpoint:$ep,env:"development",tokenCommand:$tc}}}' >"$T/p.json"
  rc=0
  (unset CYODA_ENDPOINT CYODA_CLIENT_ID CYODA_CLIENT_SECRET CYODA_CLIENT_SECRET_CMD
    CYODA_PLUGIN_CONFIG="$T/p.json" bash "$S/cyoda-call.sh" GET /model/ >/dev/null 2>"$T/err") || rc=$?
  assert_status 0 "$rc" "tokenCommand with per-profile env prefix (stderr: $(cat "$T/err"))"
}

test_wrong_secret() {
  local out rc=0
  out="$(CYODA_ENDPOINT="$EP" CYODA_CLIENT_ID=smoke CYODA_CLIENT_SECRET=nope bash "$GT" 2>"$T/err")" || rc=$?
  assert_status 1 "$rc" "wrong secret → exit 1"
  assert_eq "$out" "" "wrong secret → nothing on stdout"
  assert_contains "$(cat "$T/err")" "401" "wrong secret → stderr names the 401"
}

test_missing_inputs() {
  local rc=0
  (unset CYODA_ENDPOINT; CYODA_CLIENT_ID=smoke CYODA_CLIENT_SECRET=s3cret bash "$GT" >/dev/null 2>"$T/err") || rc=$?
  assert_status 1 "$rc" "no CYODA_ENDPOINT → exit 1"
  assert_contains "$(cat "$T/err")" "CYODA_ENDPOINT" "no endpoint → stderr names CYODA_ENDPOINT"
  rc=0
  (unset CYODA_CLIENT_ID; CYODA_ENDPOINT="$EP" CYODA_CLIENT_SECRET=s3cret bash "$GT" >/dev/null 2>"$T/err") || rc=$?
  assert_status 1 "$rc" "no CYODA_CLIENT_ID → exit 1"
  assert_contains "$(cat "$T/err")" "CYODA_CLIENT_ID" "no client id → stderr names CYODA_CLIENT_ID"
  rc=0
  (unset CYODA_CLIENT_SECRET CYODA_CLIENT_SECRET_CMD; CYODA_ENDPOINT="$EP" CYODA_CLIENT_ID=smoke \
    bash "$GT" >/dev/null 2>"$T/err") || rc=$?
  assert_status 1 "$rc" "no secret → exit 1"
  rc=0
  CYODA_ENDPOINT="$EP" CYODA_CLIENT_ID=smoke CYODA_CLIENT_SECRET_CMD=false bash "$GT" >/dev/null 2>"$T/err" || rc=$?
  assert_status 1 "$rc" "failing CYODA_CLIENT_SECRET_CMD → exit 1"
}

test_unreachable() {
  local rc=0
  CYODA_ENDPOINT=http://localhost:1 CYODA_CLIENT_ID=smoke CYODA_CLIENT_SECRET=s3cret bash "$GT" >/dev/null 2>"$T/err" || rc=$?
  assert_status 1 "$rc" "unreachable endpoint → exit 1"
  assert_contains "$(cat "$T/err")" "localhost:1" "unreachable → stderr names the endpoint"
}

test_template_exists
test_missing_inputs
test_unreachable
if start_jwt_server; then
  test_prints_jwt
  test_secret_cmd
  test_call_with_token_command
  test_wrong_secret
  stop_server
else
  _bad "jwt-mode server failed to start"
fi
report
