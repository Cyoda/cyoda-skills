#!/usr/bin/env bash
# List running cyoda-go containers (image ghcr.io/cyoda/cyoda, any tag), one per line:
#   CONTAINER=<name> COMPOSE_PROJECT=<label or -> ENDPOINT=http://<host>:<port>|none IMAGE=<image>
# ENDPOINT is the host side of the container's REST port (CYODA_HTTP_PORT from the
# container env, else 8080); IPv6 hosts are bracketed; none if unpublished.
# Read-only: runs only `docker ps` and `docker inspect`; never starts, stops or changes anything.
# Exit: 0 ok (no output when none run), 3 docker not on PATH, 4 docker ps/inspect failed.
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not on PATH" >&2
  exit 3
fi

ERR="$(mktemp "${TMPDIR:-/tmp}/cyoda-docker.XXXXXX")"
trap 'rm -f "$ERR"' EXIT

# stderr kept apart: docker prints warnings there that must not become ids.
if ! ids="$(docker ps --format '{{.ID}}' 2>"$ERR")"; then
  echo "docker ps failed: $(cat "$ERR")" >&2
  exit 4
fi
[ -n "$ids" ] || exit 0

# A container that exits between ps and inspect makes inspect exit 1 but still
# print the others: use that partial output; fail only when there is none.
# shellcheck disable=SC2086 # one id per word
json="$(docker inspect $ids 2>"$ERR")" || true
if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$json"; then
  echo "docker inspect failed: $(cat "$ERR")" >&2
  exit 4
fi

jq -r '
  .[]
  | select(.Config.Image | test("^ghcr\\.io/cyoda/cyoda([:@]|$)"))
  | ([(.Config.Env // [])[] | select(startswith("CYODA_HTTP_PORT=")) | ltrimstr("CYODA_HTTP_PORT=")] | last // "8080") as $cport
  | ((.NetworkSettings.Ports["\($cport)/tcp"] // [])[0]) as $b
  | (if $b == null then "none"
     else ($b.HostIp // "") as $ip
       | (if $ip == "" or $ip == "0.0.0.0" or $ip == "::" or $ip == "127.0.0.1" or $ip == "::1" then "localhost"
          elif ($ip | contains(":")) then "[\($ip)]"
          else $ip end) as $h
       | "http://\($h):\($b.HostPort)"
     end) as $ep
  | "CONTAINER=\(.Name | ltrimstr("/")) COMPOSE_PROJECT=\((.Config.Labels // {})["com.docker.compose.project"] // "-") ENDPOINT=\($ep) IMAGE=\(.Config.Image)"
' <<<"$json"
