#!/usr/bin/env bash
# prompt.sh <template> <iteration> <skill> <id> [--no-cyoda]
# Prints a prompt template with {{REPO}} {{SKILL_NAME}} {{N}} {{ITERATION}} {{OUT}}
# {{SKILL_CREATOR}} filled in. --no-cyoda appends the "cyoda is not installed" rule.
set -euo pipefail
[ $# -ge 4 ] || { echo "usage: prompt.sh <template> <iteration> <skill> <id> [--no-cyoda]" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
tpl="$1"; [ -f "$tpl" ] || tpl="$HERE/$1"
OUT="$REPO/cyoda-evals-workspace/$2/$3/eval-$4/with_skill/outputs"
SC="$HOME/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator"
esc() { printf '%s' "$1" | sed 's/[|&\\]/\\&/g'; }
sed -e "s|{{REPO}}|$(esc "$REPO")|g" -e "s|{{SKILL_NAME}}|$(esc "$3")|g" -e "s|{{N}}|$(esc "$4")|g" \
    -e "s|{{ITERATION}}|$(esc "$2")|g" -e "s|{{OUT}}|$(esc "$OUT")|g" -e "s|{{SKILL_CREATOR}}|$(esc "$SC")|g" "$tpl"
if [ "${5:-}" = "--no-cyoda" ]; then
  # shellcheck disable=SC2016 # backticks are Markdown, not command substitution
  printf '\n- `cyoda` is NOT installed for this eval: prefix every command with `PATH="%s"`, which hides the binary.\n' "$(bash "$HERE/nocyoda-path.sh")"
fi
