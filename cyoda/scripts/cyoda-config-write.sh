#!/usr/bin/env bash
# Change the plugin config with one jq filter, atomically and privately.
# Usage: cyoda-config-write.sh '<jq filter>' [--arg name value | --argjson name json ...]
# Config: ${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}.
# A missing config starts as {} in a new 0700 dir. The result must be a JSON object;
# it is written to a 0600 temp file next to the config, then moved over it, so the
# config is always 0600 and never half-written. Pass values with --arg, never by
# splicing them into the filter. Prints nothing on success.
# Exit: 0 ok, 1 invalid config / filter error / result not an object,
# 3 cannot write (dir or file not writable), 64 usage.
set -uo pipefail

if [ $# -lt 1 ] || [ -z "$1" ]; then
  echo "usage: cyoda-config-write.sh '<jq filter>' [--arg name value ...]" >&2
  exit 64
fi
FILTER="$1"; shift

CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"
DIR="$(dirname "$CONFIG")"

if [ ! -d "$DIR" ] && ! (umask 077 && mkdir -p "$DIR") 2>/dev/null; then
  echo "cannot write $CONFIG: cannot create $DIR" >&2
  exit 3
fi

if [ -f "$CONFIG" ]; then
  if ! jq -e 'type == "object"' "$CONFIG" >/dev/null 2>&1; then
    echo "invalid config: $CONFIG" >&2
    exit 1
  fi
  SRC="$CONFIG"
else
  SRC=""
fi

if ! TMP="$(umask 077 && mktemp "$CONFIG.XXXXXX" 2>/dev/null)"; then
  echo "cannot write $CONFIG: $DIR is not writable" >&2
  exit 3
fi
trap 'rm -f "$TMP"' EXIT

if [ -n "$SRC" ]; then
  jq "$@" "$FILTER" "$SRC" >"$TMP" 2>"$TMP.err" || { echo "jq: $(cat "$TMP.err")" >&2; rm -f "$TMP.err"; exit 1; }
else
  echo '{}' | jq "$@" "$FILTER" >"$TMP" 2>"$TMP.err" || { echo "jq: $(cat "$TMP.err")" >&2; rm -f "$TMP.err"; exit 1; }
fi
rm -f "$TMP.err"

if [ "$(jq -s 'length == 1 and (.[0] | type == "object")' "$TMP" 2>/dev/null)" != true ]; then
  echo "the filter's result is not a JSON object; $CONFIG left unchanged" >&2
  exit 1
fi

if ! { chmod 600 "$TMP" && mv -f "$TMP" "$CONFIG"; }; then
  echo "cannot write $CONFIG" >&2
  exit 3
fi
trap - EXIT
