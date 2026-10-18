#!/usr/bin/env bash
# Look up cyoda help. Usage: cyoda-help.sh <path...> [--section <NAME>]
# Order: active instance, local binary, docs.cyoda.net mirror.
# Topic actions (e.g. `workflows schema-version versions`) return plain JSON
# with no .body; it is printed verbatim (instance or binary only; the web
# mirror has no action JSON). --section is rejected for actions (exit 6).
# stderr line 1: SOURCE=instance|binary|web VERSION=<v>
# Exit: 0 ok, 2 unknown topic, 6 section not found / not applicable.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORDS=(); SECTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --section) SECTION="${2:-}"; shift 2 || shift ;;
    *) WORDS+=("$1"); shift ;;
  esac
done
if [ ${#WORDS[@]} -eq 0 ]; then
  echo "usage: cyoda-help.sh <path...> [--section <NAME>]" >&2
  exit 64
fi
URLPATH="$(IFS=/; echo "${WORDS[*]}")"

emit_json() { # source version json
  local source="$1" version="$2" json="$3"
  echo "SOURCE=$source VERSION=$version" >&2
  if ! jq -e 'type == "object" and has("body")' >/dev/null 2>&1 <<<"$json"; then
    # Topic action result: plain JSON, no sections.
    if [ -n "$SECTION" ]; then
      echo "'${WORDS[*]}' is an action, not a topic: its output has no sections; drop --section" >&2
      exit 6
    fi
    printf '%s\n' "$json"
    exit 0
  fi
  if [ -z "$SECTION" ]; then
    jq -r '.body' <<<"$json"
    exit 0
  fi
  local sec
  sec="$(jq -r --arg s "$SECTION" '[.sections[]? | select((.name|ascii_downcase) == ($s|ascii_downcase))][0].body // empty' <<<"$json")"
  if [ -z "$sec" ]; then
    echo "section '$SECTION' not found; available sections:" >&2
    jq -r '.sections[]?.name' <<<"$json" >&2
    exit 6
  fi
  printf '%s\n' "$sec"
  exit 0
}

# 1. Active instance. /api/help is public: plain curl, never tokenCommand.
# One fetch of /api/help gives reachability and VERSION; one fetch gets the topic.
ep="$("$HERE/cyoda-profile.sh" 2>/dev/null | jq -r '.endpoint // empty' 2>/dev/null)" || ep=""
if [ -n "$ep" ]; then
  ep="${ep%/}"
  if idx="$(curl -fsS --max-time 5 "$ep/api/help" 2>/dev/null)"; then
    ver="$(jq -r '.version // "unknown"' <<<"$idx" 2>/dev/null)" || ver=unknown
    if json="$(curl -fsS --max-time 10 "$ep/api/help/$URLPATH" 2>/dev/null)" && jq -e . >/dev/null 2>&1 <<<"$json"; then
      emit_json instance "${ver:-unknown}" "$json"
    fi
  fi
fi

# 2. Local binary
if command -v cyoda >/dev/null 2>&1; then
  if json="$(cyoda help "${WORDS[@]}" --format=json 2>/dev/null)" && jq -e . >/dev/null 2>&1 <<<"$json"; then
    ver="$(cyoda --version 2>/dev/null | awk 'NR==1{print $3}')"
    emit_json binary "${ver:-unknown}" "$json"
  fi
fi

# 3. Web mirror (whole page)
if page="$(curl -fsS --max-time 10 "https://docs.cyoda.net/help/$URLPATH.md" 2>/dev/null)" && [ -n "$page" ]; then
  ver="$(curl -fsS --max-time 10 https://docs.cyoda.net/help/index.json 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null)" || ver=unknown
  echo "SOURCE=web VERSION=${ver:-unknown}" >&2
  [ -n "$SECTION" ] && echo "note: --section is ignored for web pages; showing the whole page" >&2
  printf '%s\n' "$page"
  exit 0
fi

echo "unknown help topic: ${WORDS[*]}" >&2
exit 2
