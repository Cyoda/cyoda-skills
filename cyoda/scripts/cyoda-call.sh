#!/usr/bin/env bash
# Authenticated call to the active instance's API.
# Usage: cyoda-call.sh [--confirm-production] <METHOD> <PATH> [curl args...]
# PATH is relative to <endpoint>/api. Body to stdout, HTTP_STATUS=<code> to stderr.
# Exit: 0 2xx, 22 >=400, 3 production refusal, 4 token command failed, 5 no endpoint.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIRM=0
if [ "${1:-}" = "--confirm-production" ]; then CONFIRM=1; shift; fi
if [ $# -lt 2 ]; then
  echo "usage: cyoda-call.sh [--confirm-production] <METHOD> <PATH> [curl args...]" >&2
  exit 64
fi
METHOD="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
APIPATH="$2"
shift 2

PROFILE_JSON="$("$HERE/cyoda-profile.sh")"
ENDPOINT="$(jq -r '.endpoint // empty' <<<"$PROFILE_JSON")"
ENVNAME="$(jq -r '.env' <<<"$PROFILE_JSON")"
TOKEN_CMD="$(jq -r '.tokenCommand // empty' <<<"$PROFILE_JSON")"

if [ -z "$ENDPOINT" ]; then
  echo "no endpoint configured; run /cyoda:setup" >&2
  exit 5
fi

if [ "$ENVNAME" = "production" ] && [ "$CONFIRM" -eq 0 ]; then
  case "$METHOD" in
    GET|HEAD) ;;
    *) echo "PRODUCTION: ask the user to confirm, then re-run with --confirm-production" >&2; exit 3 ;;
  esac
fi

# The token never goes into curl's argv (visible in ps): it is written to a
# 0600 header file in a private temp dir and curl reads it with -H @file.
HDR_DIR=""
trap '[ -z "$HDR_DIR" ] || rm -rf "$HDR_DIR"' EXIT

run_token() {
  local t
  if ! t="$(CYODA_ENDPOINT="$ENDPOINT" bash -c "$TOKEN_CMD" 2>/dev/null)" || [ -z "$t" ]; then
    echo "token command failed: $TOKEN_CMD" >&2
    exit 4
  fi
  [ -n "$HDR_DIR" ] || HDR_DIR="$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/cyoda-call.XXXXXX")"
  (umask 077 && printf 'Authorization: Bearer %s\n' "$t" >"$HDR_DIR/auth-header")
}

URL="${ENDPOINT%/}/api/${APIPATH#/}"
[ -n "$TOKEN_CMD" ] && run_token

do_request() {
  local args=(-sS -X "$METHOD" -w $'\n%{http_code}')
  [ -n "$HDR_DIR" ] && args+=(-H @"$HDR_DIR/auth-header")
  args+=("$@" "$URL")
  local out rc=0
  out="$(curl "${args[@]}")" || rc=$?
  if [ "$rc" -ne 0 ]; then CODE="000"; BODY=""; return; fi
  CODE="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

do_request "$@"
if { [ "$CODE" = 401 ] || [ "$CODE" = 403 ]; } && [ -n "$TOKEN_CMD" ]; then
  run_token
  do_request "$@"
fi

[ -n "$BODY" ] && printf '%s\n' "$BODY"
echo "HTTP_STATUS=$CODE" >&2
case "$CODE" in
  2??) exit 0 ;;
  *) exit 22 ;;
esac
