#!/usr/bin/env bash
# Checks that Cloud is removed from the dev plugin and every skill is agent-loadable.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

has_flag() { awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1{print}' "$1" | grep -q '^disable-model-invocation: true'; }

test_no_migrate_skill() {
  [ ! -e "$ROOT/cyoda/skills/migrate" ]; assert_status 0 $? "migrate skill removed"
}

test_flags() {
  local s f names=""
  for f in "$ROOT"/cyoda/skills/*/; do names="$names $(basename "$f")"; done
  assert_eq "$names" " auth build compute debug deploy design docs setup test" "skill set"
  for f in "$ROOT"/cyoda/skills/*/SKILL.md; do
    s="$(basename "$(dirname "$f")")"
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
  local v target
  v="$(jq -r .version "$p")"
  target="$(cat "$ROOT/tests/smoke/cyoda-go.version")"
  # Plugin MAJOR.MINOR follows the targeted cyoda-go line; PATCH is the plugin's own.
  assert_eq "${v%.*}" "${target%.*}" "plugin MAJOR.MINOR matches cyoda-go $target"
  assert_eq "$(jq -r .repository "$p")" https://github.com/Cyoda/cyoda-skills "plugin repository"
  jq -r .description "$p" | grep -q Cloud; assert_status 1 $? "description has no Cloud"
  assert_eq "$(jq -r .version "$ROOT/cyoda/gemini-extension.json")" "$v" "gemini version matches plugin"
  assert_eq "$(jq -r '.plugins[0].version' "$ROOT/.claude-plugin/marketplace.json")" "$v" "marketplace version matches plugin"
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
