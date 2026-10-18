#!/usr/bin/env bash
# shellcheck disable=SC2119 # start_server args are optional env overrides; none needed here
# Smoke runner. Usage: run.sh [--only NN] [--allow-version]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
# shellcheck source=../lib/server.sh
source "$ROOT/tests/lib/server.sh"

ONLY=""
ALLOW_VERSION=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --allow-version) ALLOW_VERSION=1; shift ;;
    *) echo "usage: run.sh [--only NN] [--allow-version]" >&2; exit 2 ;;
  esac
done

trap stop_server EXIT

VERSION="$(cyoda --version 2>&1 | head -n1)"
case "$VERSION" in
  *0.8.4*) ;;
  *)
    if [ "$ALLOW_VERSION" -eq 0 ]; then
      echo "cyoda version mismatch: got '$VERSION', need 0.8.4 (use --allow-version to override)" >&2
      exit 2
    fi
    echo "warning: running against '$VERSION' (expected 0.8.4)" >&2 ;;
esac

RC=0

if [ -z "$ONLY" ]; then
  echo "== lint"
  bash "$HERE/lint.sh" || RC=1

  echo "== script tests"
  for t in "$ROOT"/tests/scripts/test-*.sh; do
    [ -e "$t" ] || continue
    echo "-- $(basename "$t")"
    bash "$t" || RC=1
  done
fi

for s in "$HERE"/scenarios/*.sh; do
  [ -e "$s" ] || continue
  name="$(basename "$s" .sh)"
  if [ -n "$ONLY" ]; then
    case "$name" in "$ONLY"*) ;; *) continue ;; esac
  fi
  echo "== scenario $name"
  start_server || { RC=1; stop_server; continue; }
  # shellcheck disable=SC1090
  source "$s"
  scenario_main || RC=1
  unset -f scenario_main
  stop_server
done

report || RC=1
exit "$RC"
