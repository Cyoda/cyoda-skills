#!/usr/bin/env bash
# timing.sh <iteration> <skill> <id> <total_tokens> <duration_ms>
# Writes with_skill/timing.json from the executor's task notification.
set -euo pipefail
[ $# -eq 5 ] || { echo "usage: timing.sh <iteration> <skill> <id> <total_tokens> <duration_ms>" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
dir="$REPO/cyoda-evals-workspace/$1/$2/eval-$3/with_skill"; mkdir -p "$dir"
secs="$(awk -v ms="$5" 'BEGIN { printf "%.1f", ms / 1000 }')"
printf '{"total_tokens": %s, "duration_ms": %s, "total_duration_seconds": %s}\n' "$4" "$5" "$secs" > "$dir/timing.json"
mkdir -p "$HERE/.state"; echo "$1 $2 $3 $4 $5" >> "$HERE/.state/tokens.log"
echo "$dir/timing.json"
