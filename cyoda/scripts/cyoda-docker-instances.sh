#!/usr/bin/env bash
# List running cyoda-go containers (image ghcr.io/cyoda/cyoda, any tag), one per line:
#   CONTAINER=<name> COMPOSE_PROJECT=<label or -> ENDPOINT=http://<host>:<port>|none IMAGE=<image>
# ENDPOINT is the host side of container port 8080 (the REST API); none if unpublished.
# Read-only: runs only `docker ps` and `docker inspect`; never starts, stops or changes anything.
# Exit: 0 ok (no output when none run), 3 docker not on PATH, 4 docker ps/inspect failed.
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not on PATH" >&2
  exit 3
fi

if ! ids="$(docker ps --format '{{.ID}}' 2>&1)"; then
  echo "docker ps failed: $ids" >&2
  exit 4
fi
[ -n "$ids" ] || exit 0

# shellcheck disable=SC2086 # one id per word
if ! json="$(docker inspect $ids 2>/dev/null)"; then
  echo "docker inspect failed" >&2
  exit 4
fi

jq -r '
  .[]
  | select(.Config.Image | test("^ghcr\\.io/cyoda/cyoda([:@]|$)"))
  | ((.NetworkSettings.Ports["8080/tcp"] // [])[0]) as $b
  | (if $b == null then "none"
     else ($b.HostIp // "") as $ip
       | (if $ip == "" or $ip == "0.0.0.0" or $ip == "::" or $ip == "127.0.0.1" or $ip == "::1"
          then "localhost" else $ip end) as $h
       | "http://\($h):\($b.HostPort)"
     end) as $ep
  | "CONTAINER=\(.Name | ltrimstr("/")) COMPOSE_PROJECT=\(.Config.Labels["com.docker.compose.project"] // "-") ENDPOINT=\($ep) IMAGE=\(.Config.Image)"
' <<<"$json"
