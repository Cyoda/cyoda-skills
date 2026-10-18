#!/usr/bin/env bash
# Verify a deployed cyoda-go instance from outside, after seed.sh.
#
# Usage: verify.sh [--manifest <path/to/cyoda-manifest.json>]  (default ./cyoda-manifest.json)
#
# Checks, in order (cyoda help run HEALTH PROBES, cyoda help models ENDPOINTS):
#   1. GET <endpoint>/api/health is {"status":"UP"}
#   2. GET <admin>/readyz on the admin port is 200, only if CYODA_ADMIN_URL is set
#      (the admin port is loopback by default; check it where it is reachable)
#   3. GET <endpoint>/api/model/ lists every manifest entity version as LOCKED
#
# Environment:
#   CYODA_ENDPOINT       instance base URL, no /api (required)
#   CYODA_TOKEN_COMMAND  command that prints a JWT, run with CYODA_ENDPOINT set
#                        (optional; unset = no auth header, for mock auth)
#   CYODA_ADMIN_URL      admin listener base URL, e.g. http://localhost:9091 (optional)
#
# Prints one OK or FAIL line per check. Exit 0 if all pass, 1 otherwise, 2 on usage.
set -uo pipefail

usage() { echo "usage: verify.sh [--manifest <cyoda-manifest.json>]" >&2; exit 2; }

MANIFEST="cyoda-manifest.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) [ $# -ge 2 ] || usage; MANIFEST="$2"; shift 2 ;;
    *) usage ;;
  esac
done

ENDPOINT="${CYODA_ENDPOINT:-}"
[ -n "$ENDPOINT" ] || { echo "verify: CYODA_ENDPOINT is not set" >&2; exit 2; }
ENDPOINT="${ENDPOINT%/}"
ENDPOINT="${ENDPOINT%/api}"
API="$ENDPOINT/api"

FAILS=0
ok() { echo "OK $*"; }
bad() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }

# get <URL> [curl args...]: body -> $BODY, status -> $CODE ("000" if unreachable)
get() {
  local u="$1" out
  shift
  out="$(curl -sS --max-time 10 -w $'\n%{http_code}' "$@" "$u" 2>&1)" || out="(unreachable)"$'\n000'
  CODE="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

# 1. API health (public).
get "$API/health"
if [ "$CODE" = 200 ] && [ "$(jq -r '.status // empty' <<<"$BODY" 2>/dev/null)" = UP ]; then
  ok "health $API/health UP"
else
  bad "health $API/health -> HTTP $CODE $BODY"
fi

# 2. Readiness on the admin port, only where reachable.
if [ -n "${CYODA_ADMIN_URL:-}" ]; then
  ADMIN="${CYODA_ADMIN_URL%/}"
  get "$ADMIN/readyz"
  if [ "$CODE" = 200 ]; then ok "readyz $ADMIN/readyz"; else bad "readyz $ADMIN/readyz -> HTTP $CODE $BODY"; fi
fi

# 3. Every manifest entity version is LOCKED.
AUTH=()
if [ -n "${CYODA_TOKEN_COMMAND:-}" ]; then
  if TOKEN="$(CYODA_ENDPOINT="$ENDPOINT" bash -c "$CYODA_TOKEN_COMMAND")" && [ -n "$TOKEN" ]; then
    AUTH=(-H "Authorization: Bearer $TOKEN")
  else
    bad "token command failed or printed nothing: $CYODA_TOKEN_COMMAND"
  fi
fi

if [ ! -f "$MANIFEST" ]; then
  bad "manifest not found: $MANIFEST"
elif [ "$(jq '.entities | length' "$MANIFEST" 2>/dev/null || echo 0)" -eq 0 ]; then
  bad "manifest lists no entities: $MANIFEST"
else
  get "$API/model/" ${AUTH[@]+"${AUTH[@]}"}
  if [ "$CODE" != 200 ]; then
    bad "models GET $API/model/ -> HTTP $CODE $BODY"
  else
    while IFS=$'\t' read -r n v; do
      [ -n "$n" ] || continue
      s="$(jq -r --arg n "$n" --argjson v "$v" \
        '[.[] | select(.modelName == $n and .modelVersion == $v)][0].currentState // "MISSING"' <<<"$BODY" 2>/dev/null)" || s="UNREADABLE"
      if [ "$s" = LOCKED ]; then ok "model $n v$v LOCKED"; else bad "model $n v$v $s (expected LOCKED; run seed.sh)"; fi
    done < <(jq -r '.entities[] | [.name, (.modelVersion | tostring)] | @tsv' "$MANIFEST" 2>/dev/null)
  fi
fi

if [ "$FAILS" -eq 0 ]; then
  echo "OK all checks passed"
  exit 0
fi
echo "FAIL $FAILS check(s) failed"
exit 1
