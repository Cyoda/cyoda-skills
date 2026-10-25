#!/usr/bin/env bash
# Print one STATUS line for the bound instance (cyoda-profile.sh), then WARN= lines.
# STATUS=… PROFILE=… ENDPOINT=… ENV=… VERSION=… BINARY_VERSION=… SOURCE=project|profile|default [PROJECT=<dir>]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROFILE_JSON="$("$HERE/cyoda-profile.sh")" || exit 1
PROFILE="$(jq -r '.profile' <<<"$PROFILE_JSON")"
ENDPOINT="$(jq -r '.endpoint // empty' <<<"$PROFILE_JSON")"
ENVNAME="$(jq -r '.env' <<<"$PROFILE_JSON")"
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
      WARNS+=("no cyoda-go is answering at $ENDPOINT — type /cyoda:setup to install or start one")
    elif [ "$SOURCE" = "project" ]; then
      WARNS+=("project $PROFILE is bound to $ENDPOINT, which is unreachable; start that instance, or type /cyoda:setup to link this project to another one")
    else
      WARNS+=("active profile $PROFILE is unreachable; run /cyoda:setup to switch to default")
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

echo "STATUS=$STATUS PROFILE=$PROFILE ENDPOINT=${ENDPOINT:-none} ENV=$ENVNAME VERSION=$VERSION BINARY_VERSION=$BINVER SOURCE=$SOURCE${PROJECT:+ PROJECT=$PROJECT}"
for w in "${WARNS[@]:-}"; do [ -n "$w" ] && echo "WARN=$w"; done
exit 0
