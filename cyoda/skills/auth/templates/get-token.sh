#!/usr/bin/env bash
# Print a fresh cyoda-go access token (JWT) on stdout, nothing else.
# M2M client_credentials grant: POST <endpoint>/api/oauth/token with HTTP
# Basic auth (see `cyoda help auth tokens`, REQUEST FLOW). cyoda-go issues no
# refresh token: run this again whenever you need a token.
#
# Environment:
#   CYODA_ENDPOINT           instance base URL, e.g. http://localhost:8080
#                            (the cyoda plugin sets it from the profile)
#   CYODA_CLIENT_ID          M2M client id
#   CYODA_CLIENT_SECRET      M2M client secret, or instead:
#   CYODA_CLIENT_SECRET_CMD  command that prints the secret, e.g.
#                            'security find-generic-password -s cyoda-dev -w'
#                            (takes precedence over CYODA_CLIENT_SECRET)
#
# Exit 0 with the token on stdout; exit 1 with a message on stderr.
# Stores nothing. The secret is never put on a command line.
set -eu

fail() { printf 'get-token: %s\n' "$*" >&2; exit 1; }

endpoint="${CYODA_ENDPOINT:-}"
[ -n "$endpoint" ] || fail "CYODA_ENDPOINT is not set (instance base URL, e.g. http://localhost:8080)"
endpoint="${endpoint%/}"
endpoint="${endpoint%/api}"

client_id="${CYODA_CLIENT_ID:-}"
[ -n "$client_id" ] || fail "CYODA_CLIENT_ID is not set"

if [ -n "${CYODA_CLIENT_SECRET_CMD:-}" ]; then
  secret="$(sh -c "$CYODA_CLIENT_SECRET_CMD")" || fail "CYODA_CLIENT_SECRET_CMD failed"
  [ -n "$secret" ] || fail "CYODA_CLIENT_SECRET_CMD printed nothing"
else
  secret="${CYODA_CLIENT_SECRET:-}"
  [ -n "$secret" ] || fail "set CYODA_CLIENT_SECRET or CYODA_CLIENT_SECRET_CMD"
fi

url="$endpoint/api/oauth/token"
basic="$(printf '%s:%s' "$client_id" "$secret" | base64 | tr -d '\n')"

# The Authorization header goes in on stdin (-H @-) so the secret stays out of `ps`.
if ! out="$(printf 'Authorization: Basic %s\n' "$basic" \
    | curl -sS --max-time 10 -X POST "$url" -H @- \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data 'grant_type=client_credentials' \
        -w '\n%{http_code}' 2>&1)"; then
  out="${out%
*}"
  fail "cannot reach $url: ${out%
}"
fi

code="${out##*
}"
body="${out%
*}"

if [ "$code" != "200" ]; then
  fail "token request to $url failed: HTTP $code $body"
fi

if command -v jq >/dev/null 2>&1; then
  token="$(printf '%s' "$body" | jq -r '.access_token // empty' 2>/dev/null)" || token=""
else
  token="$(printf '%s' "$body" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi
[ -n "$token" ] || fail "no access_token in the response from $url"

printf '%s\n' "$token"
