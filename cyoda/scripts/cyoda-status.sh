#!/usr/bin/env bash
# Print one STATUS line for the bound instance (cyoda-profile.sh), then WARN= lines.
# STATUS=… PROFILE=… ENDPOINT=… VERSION=… BINARY_VERSION=… SOURCE=project|profile|default [PROJECT=<dir>]
# PROFILE is double-quoted when it contains whitespace or a quote ("my shop", \" inside).
# PROJECT, when present, is last and runs to the end of the line (it may hold spaces).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROFILE_JSON="$("$HERE/cyoda-profile.sh")" || exit 1
PROFILE="$(jq -r '.profile' <<<"$PROFILE_JSON")"
ENDPOINT="$(jq -r '.endpoint // empty' <<<"$PROFILE_JSON")"
SOURCE="$(jq -r '.source // "profile"' <<<"$PROFILE_JSON")"
PROJECT="$(jq -r '.projectDir // empty' <<<"$PROFILE_JSON")"

BINVER="none"
if command -v cyoda >/dev/null 2>&1; then
  BINVER="$(cyoda --version 2>/dev/null | awk 'NR==1{print $3}')"
  [ -n "$BINVER" ] || BINVER="none"
fi

WARNS=()
while IFS= read -r w; do [ -n "$w" ] && WARNS+=("$w"); done < <(jq -r '.warnings[]' <<<"$PROFILE_JSON")

STATUS="not_configured"; VERSION="none"
if [ -n "$ENDPOINT" ]; then
  # /api/help is public: plain curl, never tokenCommand.
  body="$(curl -sS --connect-timeout 2 --max-time 5 -w $'\n%{http_code}' "${ENDPOINT%/}/api/help" 2>/dev/null)" || body=$'\n000'
  code="${body##*$'\n'}"
  body="${body%$'\n'*}"
  if [ -z "$code" ] || [ "$code" = "000" ]; then
    STATUS="unreachable"
    if [ "$SOURCE" = "default" ]; then
      WARNS+=("no cyoda-go is answering at $ENDPOINT; start or link one (cyoda:setup)")
    elif [ "$SOURCE" = "project" ]; then
      WARNS+=("project $PROFILE is bound to $ENDPOINT, which is unreachable; start it or re-link this project (cyoda:setup)")
    else
      WARNS+=("active profile $PROFILE is unreachable; switch to default or another profile (cyoda:setup)")
    fi
  else
    STATUS="connected"
    VERSION="$(jq -r '.version // "unknown"' <<<"$body" 2>/dev/null)" || VERSION="unknown"
    [ -n "$VERSION" ] || VERSION="unknown"
    if [ "$BINVER" != "none" ] && [ "$VERSION" != "unknown" ] && [ "$BINVER" != "$VERSION" ]; then
      WARNS+=("local cyoda $BINVER differs from instance $VERSION; help is read from the instance")
    fi
  fi
fi

# The plugin's MAJOR.MINOR follows the cyoda-go line it targets (plugin 0.8.x -> cyoda-go 0.8.x).
# Compare it with the instance, or with the local binary when no instance answered.
PLUGIN_VERSION="${CYODA_PLUGIN_VERSION:-$(jq -r '.version // empty' "$HERE/../.claude-plugin/plugin.json" 2>/dev/null)}"
mm() { awk -F. 'NF>=2 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {print $1"."$2}' <<<"$1"; }
PLUGIN_MM="$(mm "$PLUGIN_VERSION")"
if [ -n "$PLUGIN_MM" ]; then
  if [ "$STATUS" = "connected" ] && [ -n "$(mm "$VERSION")" ]; then
    [ "$(mm "$VERSION")" = "$PLUGIN_MM" ] ||
      WARNS+=("the cyoda plugin targets cyoda-go $PLUGIN_MM; this instance runs $VERSION. Update the plugin, or run cyoda-go $PLUGIN_MM.")
  elif [ "$STATUS" != "connected" ] && [ -n "$(mm "$BINVER")" ]; then
    [ "$(mm "$BINVER")" = "$PLUGIN_MM" ] ||
      WARNS+=("the cyoda plugin targets cyoda-go $PLUGIN_MM; local cyoda is $BINVER. Update the plugin, or install cyoda-go $PLUGIN_MM.")
  fi
fi

qval() { # value -> value, or "value" with \" when it has whitespace or a quote
  case "$1" in
    *[[:space:]]* | *\"*) local v="${1//\\/\\\\}"; v="${v//\"/\\\"}"; printf '"%s"' "$v" ;;
    *) printf '%s' "$1" ;;
  esac
}

echo "STATUS=$STATUS PROFILE=$(qval "$PROFILE") ENDPOINT=${ENDPOINT:-none} VERSION=$VERSION BINARY_VERSION=$BINVER SOURCE=$SOURCE${PROJECT:+ PROJECT=$PROJECT}"
for w in "${WARNS[@]:-}"; do [ -n "$w" ] && echo "WARN=$w"; done
exit 0
