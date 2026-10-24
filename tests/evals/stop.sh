#!/usr/bin/env bash
# stop.sh [id...] — stops eval servers (default: every tests/evals/.state/s<id>).
# Kills whatever listens on each server's ports: the pid file holds a wrapper pid, not cyoda's.
set -uo pipefail
STATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state"
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
echo "stopped ${#ids[@]} (still listening: $left)"
