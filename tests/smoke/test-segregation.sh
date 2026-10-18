#!/usr/bin/env bash
# Checks that Cloud is removed from the dev plugin and side-effect flags are enforced.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

has_flag() { awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1{print}' "$1" | grep -q '^disable-model-invocation: true'; }

test_no_migrate_skill() {
  [ ! -e "$ROOT/cyoda/skills/migrate" ]; assert_status 0 $? "migrate skill removed"
}

test_flags() {
  local s f
  for s in app setup build test deploy auth; do
    f="$ROOT/cyoda/skills/$s/SKILL.md"
    if [ ! -f "$f" ]; then
      [ "$s" = deploy ] && continue
      _bad "$s: SKILL.md missing"; continue
    fi
    has_flag "$f"; assert_status 0 $? "$s has disable-model-invocation"
  done
  for s in status docs design compute debug; do
    f="$ROOT/cyoda/skills/$s/SKILL.md"
    has_flag "$f"; assert_status 1 $? "$s has no disable-model-invocation"
  done
}

test_marketplace_single_plugin() {
  local m="$ROOT/.claude-plugin/marketplace.json"
  assert_eq "$(jq '.plugins | length' "$m")" 1 "one plugin listed"
  assert_eq "$(jq -r '.plugins[0].name' "$m")" cyoda "plugin is cyoda"
}

test_plugin_version() {
  local p="$ROOT/cyoda/.claude-plugin/plugin.json"
  assert_eq "$(jq -r .version "$p")" 0.4.0 "plugin version"
  assert_eq "$(jq -r .repository "$p")" https://github.com/Cyoda/cyoda-skills "plugin repository"
  jq -r .description "$p" | grep -q Cloud; assert_status 1 $? "description has no Cloud"
  assert_eq "$(jq -r .version "$ROOT/cyoda/gemini-extension.json")" 0.4.0 "gemini version"
}

test_lint_cloud_clean() {
  local n
  n="$(bash "$ROOT/tests/smoke/lint.sh" 2>&1 | grep -c ': cloud' || true)"
  assert_eq "$n" 0 "lint cloud hits"
}

for t in test_no_migrate_skill test_flags test_marketplace_single_plugin test_plugin_version test_lint_cloud_clean; do
  echo "$t"; $t
done
report
