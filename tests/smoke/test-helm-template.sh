#!/usr/bin/env bash
# Renders cyoda/skills/deploy/templates/values.yaml against the published chart
# (cyoda/cyoda 0.8.4 from https://cyoda.github.io/cyoda-go) with `helm template`
# only: no cluster, no kubectl. Helm's repo config, cache, config and data dirs
# are redirected to a temp dir, so the user's helm setup is untouched.
# Needs helm and network access to the chart repo. DEPLOY_VALUES=<file> renders
# another values file instead (used to check that the test catches a bad one).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=../lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

CHART_VERSION=0.8.4
VALUES="${DEPLOY_VALUES:-$ROOT/cyoda/skills/deploy/templates/values.yaml}"

command -v helm >/dev/null 2>&1 || { echo "helm is required" >&2; exit 2; }

HTMP="$(mktemp -d)"
trap 'rm -rf "$HTMP"' EXIT
export HELM_REPOSITORY_CONFIG="$HTMP/repositories.yaml"
export HELM_REPOSITORY_CACHE="$HTMP/repository"
export HELM_CACHE_HOME="$HTMP/cache"
export HELM_CONFIG_HOME="$HTMP/config"
export HELM_DATA_HOME="$HTMP/data"

helm repo add cyoda https://cyoda.github.io/cyoda-go >/dev/null 2>&1
assert_status 0 $? "helm repo add cyoda"
helm repo update cyoda >/dev/null 2>&1
assert_status 0 $? "helm repo update cyoda"

# render <out-file> [helm args...]: helm template with the skill's values file.
render() {
  local out="$1"
  shift
  helm template cyoda cyoda/cyoda --version "$CHART_VERSION" --namespace cyoda -f "$VALUES" "$@" >"$out" 2>"$out.err"
}

# next_line_after <file> <pattern>: the line after each match, trimmed.
next_line_after() { grep -A1 -E "$2" "$1" | grep -vE -e "$2" -e '^--$' | sed 's/^ *//'; }

test_gateway_render() {
  local out="$HTMP/gateway.yaml" rc
  render "$out"
  rc=$?
  assert_status 0 "$rc" "helm template exits 0 ($(head -c 400 "$out.err" 2>/dev/null))"
  [ "$rc" -eq 0 ] || return 0
  local y
  y="$(cat "$out")"
  assert_contains "$y" "kind: StatefulSet" "renders the StatefulSet"
  assert_contains "$y" "image: ghcr.io/cyoda/cyoda:$CHART_VERSION" "image is ghcr.io/cyoda/cyoda:$CHART_VERSION"
  # #684-D: a bootstrap client is always set, its secret from a pre-created Secret.
  assert_contains "$y" "CYODA_BOOTSTRAP_CLIENT_ID:" "ConfigMap sets CYODA_BOOTSTRAP_CLIENT_ID"
  assert_contains "$y" "CYODA_BOOTSTRAP_CLIENT_SECRET_FILE" "StatefulSet reads the bootstrap secret file"
  assert_eq "$(next_line_after "$out" 'name: cyoda-bootstrap$' | head -n1)" "items:" "projected volume references Secret cyoda-bootstrap"
  # Every credential comes from a Secret the developer pre-creates: the chart
  # renders none of its own (so helm template and GitOps work, no lookup needed).
  assert_eq "$(grep -c '^kind: Secret$' "$out")" 0 "chart renders no Secret of its own"
  local s
  for s in cyoda-pg cyoda-jwt cyoda-hmac cyoda-metrics-bearer; do
    grep -q "name: $s\$" "$out"
    assert_status 0 $? "references pre-created Secret $s"
  done
  # #684-G: routes attach to a Gateway (parentRefs not empty).
  assert_contains "$y" "kind: HTTPRoute" "renders the HTTPRoute"
  assert_contains "$y" "kind: GRPCRoute" "renders the GRPCRoute"
  local refs
  refs="$(next_line_after "$out" '^  parentRefs:$')"
  assert_eq "$(grep -c '^- ' <<<"$refs")" 2 "both routes have a non-empty parentRefs"
  # The migration Job stays on (pre-install/pre-upgrade hook).
  assert_contains "$y" "command: [/cyoda, migrate]" "renders the migration Job"
  # Replicas and HPA at chart defaults.
  assert_contains "$y" "replicas: 1" "replicas at chart default 1"
  case "$y" in *"kind: HorizontalPodAutoscaler"*) _bad "no HPA by default" ;; *) _ok ;; esac
}

test_ingress_render() {
  local out="$HTMP/ingress.yaml" rc
  render "$out" --set gateway.enabled=false --set ingress.enabled=true
  rc=$?
  assert_status 0 "$rc" "ingress variant: helm template exits 0 ($(head -c 400 "$out.err" 2>/dev/null))"
  [ "$rc" -eq 0 ] || return 0
  local y
  y="$(cat "$out")"
  assert_eq "$(grep -c '^kind: Ingress$' "$out")" 2 "ingress variant: HTTP and gRPC Ingress"
  case "$y" in *"kind: HTTPRoute"*) _bad "ingress variant: no HTTPRoute" ;; *) _ok ;; esac
}

test_gateway_render
test_ingress_render
report
