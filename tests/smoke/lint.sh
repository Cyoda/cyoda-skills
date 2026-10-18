#!/usr/bin/env bash
# Stale-string lint over cyoda/ content. Usage: lint.sh [--root DIR]
# Exit 1 listing "file:line: rule" per hit. Works with BSD grep -E (no -P).
# LINT_SKIP_SHELLCHECK=1 skips the shellcheck rule (used by harness fixtures).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    *) echo "usage: lint.sh [--root DIR]" >&2; exit 2 ;;
  esac
done

RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT

FILES=()
T60=()
if [ -d "$ROOT/cyoda" ]; then
  while IFS= read -r f; do
    FILES+=("$f")
    case "$f" in
      */cyoda/skills/compute/* | */cyoda/skills/debug/*) T60+=("$f") ;;
    esac
  done < <(find "$ROOT/cyoda" -type f \
      \( -name '*.md' -o -name '*.json' -o -name '*.sh' -o -name '*.yaml' -o -name '*.yml' -o -name '*.txt' -o -name '*.env' \) \
      -not -path '*/skills/*/evaluations/*' | sort)
fi

# record <rule>: stdin is grep -nH output; appends "relpath:line: rule"
record() {
  local rule="$1" l
  while IFS= read -r l; do
    l="${l#"$ROOT"/}"
    echo "$(printf '%s' "$l" | cut -d: -f1,2): $rule" >> "$RESULTS"
  done
}

# scan <rule> <pattern> <files...>
scan() {
  local rule="$1" pat="$2"
  shift 2
  [ $# -eq 0 ] && return 0
  grep -nHE -e "$pat" "$@" 2>/dev/null | record "$rule"
}

scan stale-tap 'cyoda-platform/cyoda-go' ${FILES[@]+"${FILES[@]}"}
scan stale-org-url 'github\.com/Cyoda-platform' ${FILES[@]+"${FILES[@]}"}
scan workflow-version-1 '"version": *"1"' ${FILES[@]+"${FILES[@]}"}
if [ ${#FILES[@]} -gt 0 ]; then
  grep -nHE -e '/readyz' "${FILES[@]}" 2>/dev/null \
    | grep -vE '^[^:]*:[0-9]+:.*(9091|admin|ADMIN)' | record readyz-api-port
fi
scan discover-mode '[Dd]iscover mode' ${FILES[@]+"${FILES[@]}"}
scan timeout-60s '(^|[^0-9A-Za-z_])60 ?s(ec(ond)?s?)?($|[^0-9A-Za-z_])' ${T60[@]+"${T60[@]}"}
scan cloud 'Cyoda Cloud' ${FILES[@]+"${FILES[@]}"}
if [ ${#FILES[@]} -gt 0 ]; then
  grep -nHE -e '\.cyoda\.net' "${FILES[@]}" 2>/dev/null \
    | grep -v 'docs\.cyoda\.net' | record cloud
fi
scan invoke-flagged '[Ii]nvoke .?/cyoda:(app|setup|build|test|deploy|auth)' ${FILES[@]+"${FILES[@]}"}
scan model-list-no-slash "/api/model[\"' )]" ${FILES[@]+"${FILES[@]}"}

HITS=0
if [ -s "$RESULTS" ]; then
  sort -u "$RESULTS"
  HITS=$(sort -u "$RESULTS" | wc -l | tr -d ' ')
fi

if [ "${LINT_SKIP_SHELLCHECK:-}" != "1" ]; then
  # Prefer a local shellcheck; else uvx's shellcheck-py; else fail with a hint.
  # LINT_SHELLCHECK_CMD overrides the choice (used by harness tests).
  SCBIN=()
  if [ -n "${LINT_SHELLCHECK_CMD:-}" ]; then
    read -r -a SCBIN <<<"$LINT_SHELLCHECK_CMD"
  elif command -v shellcheck >/dev/null 2>&1; then
    SCBIN=(shellcheck)
  elif command -v uvx >/dev/null 2>&1; then
    SCBIN=(uvx --from shellcheck-py shellcheck)
  fi
  if [ ${#SCBIN[@]} -eq 0 ]; then
    echo "shellcheck: not installed; run: brew install shellcheck"
    HITS=$((HITS + 1))
  else
    SC=()
    while IFS= read -r f; do SC+=("$f"); done < <(
      {
        ls "$ROOT"/cyoda/scripts/*.sh "$ROOT"/cyoda/skills/*/templates/*.sh 2>/dev/null
        [ -d "$ROOT/tests" ] && find "$ROOT/tests" -name '*.sh'
      } | sort -u)
    if [ ${#SC[@]} -gt 0 ]; then
      if ! SCOUT="$("${SCBIN[@]}" -x -P SCRIPTDIR -f gcc "${SC[@]}" 2>&1)"; then
        printf '%s\n' "$SCOUT" | sed "s#^$ROOT/##; s#\$# [shellcheck]#"
        HITS=$((HITS + 1))
      fi
    fi
  fi
fi

[ "$HITS" -eq 0 ] || exit 1
exit 0
