#!/usr/bin/env bash
# stop.sh [--keep] [id...] — stops eval servers (default: every tests/evals/.state/s<id>).
# Kills whatever listens on each server's ports: the pid file holds a wrapper pid, not cyoda's.
# Then removes each stopped server's state dir (it holds the RSA signing key) unless --keep.
set -uo pipefail
STATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state"
KEEP=0
if [ "${1:-}" = "--keep" ]; then KEEP=1; shift; fi
ids=("$@")
if [ ${#ids[@]} -eq 0 ]; then
  for d in "$STATE"/s*/; do [ -d "$d" ] || continue; n="$(basename "$d")"; ids+=("${n#s}"); done
fi
listening() { lsof -nP -t -iTCP:"$1" -sTCP:LISTEN 2>/dev/null; }
for id in ${ids[@]+"${ids[@]}"}; do
  base=$((20000 + id * 100))
  for port in $((base + 80)) $((base + 90)) $((base + 91)); do
    for pid in $(listening "$port"); do kill "$pid" 2>/dev/null; done
  done
  rm -f "$STATE/s$id/pid"
done
sleep 1
left=0
for id in ${ids[@]+"${ids[@]}"}; do
  listening $((20000 + id * 100 + 80)) >/dev/null && left=$((left + 1))
done
removed=0
if [ "$KEEP" -eq 0 ]; then
  for id in ${ids[@]+"${ids[@]}"}; do
    if [ -d "$STATE/s$id" ]; then rm -rf "${STATE:?}/s$id"; removed=$((removed + 1)); fi
  done
fi
echo "stopped ${#ids[@]} (still listening: $left; state dirs removed: $removed)"
