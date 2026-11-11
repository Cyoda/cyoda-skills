#!/usr/bin/env bash
# nocyoda-path.sh — prints $PATH with the `cyoda` binary hidden, for "not installed" evals.
# Each PATH dir holding cyoda is replaced by a mirror (symlinks to everything else in it),
# so tools that share the dir (jq, curl under Homebrew) stay available.
set -euo pipefail
STATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state"
out=""; i=0
IFS=: read -r -a dirs <<<"$PATH"
for d in "${dirs[@]}"; do
  if [ -n "$d" ] && [ -e "$d/cyoda" ]; then
    i=$((i + 1)); m="$STATE/nocyoda-bin-$i"; rm -rf "$m"; mkdir -p "$m"
    for f in "$d"/*; do [ "$(basename "$f")" = cyoda ] || ln -s "$f" "$m/"; done
    d="$m"
  fi
  out="${out:+$out:}$d"
done
printf '%s\n' "$out"
