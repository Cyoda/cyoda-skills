#!/usr/bin/env bash
# Scenario 08: deploy's seed.sh and verify.sh templates against a real server.
# Seeds the two-entity fixture project twice (the second run must be a no-op
# for the models), checks unique keys and the production schema override,
# then repeats the seed against a JWT-mode server via auth's get-token.sh.
scenario_main() {
  local root tpl fx ep out rc tmp states cur code
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  tpl="$root/cyoda/skills/deploy/templates"
  fx="$root/tests/smoke/fixtures/seed-project"
  ep="http://localhost:${SMOKE_HTTP_PORT}"
  for f in seed.sh verify.sh; do
    [ -f "$tpl/$f" ] || { _bad "template missing: cyoda/skills/deploy/templates/$f"; return 1; }
  done
  tmp="$(mktemp -d)"

  # 1. First run, production env: models seeded, workflows imported.
  out="$(CYODA_ENDPOINT="$ep" bash "$tpl/seed.sh" --manifest "$fx/cyoda-manifest.json" --env production 2>&1)"; rc=$?
  assert_status 0 "$rc" "first seed run exits 0"
  assert_contains "$out" "SEEDED order v1" "first run seeds order"
  assert_contains "$out" "SEEDED customer v1" "first run seeds customer"
  assert_eq "$(grep -c '^WORKFLOW ' <<<"$out")" 2 "first run imports 2 workflows"

  # 2. Both models LOCKED; workflow version substituted from help.
  states="$(curl -s "$BASE/model/" | jq -r '[.[] | select(.modelVersion == 1) | "\(.modelName)=\(.currentState)"] | sort | join(",")')"
  assert_eq "$states" "customer=LOCKED,order=LOCKED" "GET /model/ shows both LOCKED"
  cur="$(curl -s "$ep/api/help/workflows/schema-version/versions" | jq -r .current)"
  assert_eq "$(curl -s "$BASE/model/order/1/workflow/export" | jq -r '.workflows[0].version')" "$cur" \
    "workflow imported with the current schema version"

  # 3. Unique key from order's config.
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d '{"orderId":"ORD-7","customerId":"CUST-1","amount":1}' "$BASE/entity/JSON/order/1")"
  assert_status 200 "$code" "first order with ORD-7 is created"
  code="$(curl -s -o "$tmp/dup.json" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d '{"orderId":"ORD-7","customerId":"CUST-2","amount":2}' "$BASE/entity/JSON/order/1")"
  assert_status 409 "$code" "second order with ORD-7 is rejected"
  assert_contains "$(cat "$tmp/dup.json")" "UNIQUE_VIOLATION" "rejection is a unique-key conflict"

  # 4. production override changeLevel: null wins over the base STRUCTURAL.
  code="$(curl -s -o "$tmp/strict.json" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d '{"orderId":"ORD-8","customerId":"CUST-1","amount":3,"giftWrap":true}' "$BASE/entity/JSON/order/1")"
  assert_status 400 "$code" "field absent from the sample is rejected in production"
  assert_contains "$(cat "$tmp/strict.json")" "VALIDATION_FAILED" "strict schema rejection"

  # 5. Second run: models skipped, workflows re-imported, exit 0.
  out="$(CYODA_ENDPOINT="$ep" bash "$tpl/seed.sh" --manifest "$fx/cyoda-manifest.json" --env production 2>&1)"; rc=$?
  assert_status 0 "$rc" "second seed run exits 0"
  assert_contains "$out" "SKIPPED-MODEL order v1 (locked)" "second run skips order"
  assert_contains "$out" "SKIPPED-MODEL customer v1 (locked)" "second run skips customer"
  assert_eq "$(grep -c '^SEEDED ' <<<"$out")" 0 "second run seeds no model"
  assert_eq "$(grep -c '^WORKFLOW ' <<<"$out")" 2 "second run re-imports 2 workflows"

  # 6. Token command sees CYODA_ENDPOINT (Ruling R1).
  out="$(CYODA_ENDPOINT="$ep" CYODA_TOKEN_COMMAND="printf %s \"\$CYODA_ENDPOINT\" > $tmp/seen; echo dummy" \
    bash "$tpl/seed.sh" --manifest "$fx/cyoda-manifest.json" --env production 2>&1)"; rc=$?
  assert_status 0 "$rc" "seed with a token command exits 0 (mock auth ignores it)"
  assert_eq "$(cat "$tmp/seen" 2>/dev/null)" "$ep" "token command runs with CYODA_ENDPOINT set"

  # 7. verify.sh: pass with the same manifest; fail (negative control) on a missing entity.
  out="$(CYODA_ENDPOINT="$ep" CYODA_ADMIN_URL="http://localhost:${SMOKE_ADMIN_PORT}" \
    bash "$tpl/verify.sh" --manifest "$fx/cyoda-manifest.json" 2>&1)"; rc=$?
  assert_status 0 "$rc" "verify.sh exits 0"
  assert_contains "$out" "OK readyz" "verify checks /readyz on the admin port"
  assert_eq "$(grep -c '^FAIL' <<<"$out")" 0 "verify prints no FAIL line"
  jq '.entities += [{name:"ghost", modelVersion:1, sample:"x", workflow:"x", config:"x"}]' \
    "$fx/cyoda-manifest.json" > "$tmp/ghost-manifest.json"
  out="$(CYODA_ENDPOINT="$ep" bash "$tpl/verify.sh" --manifest "$tmp/ghost-manifest.json" 2>&1)"; rc=$?
  assert_status 1 "$rc" "verify.sh exits 1 when a manifest entity is missing"
  assert_contains "$out" "FAIL model ghost v1" "verify names the missing model"

  # 8. First HTTP >= 400 stops the seed with exit 1 and the response body.
  mkdir -p "$tmp/broken"
  printf '[1, 2' > "$tmp/broken/sample.json"
  printf '{"workflows":[]}' > "$tmp/broken/workflow.json"
  printf '{"uniqueKeys":[],"changeLevel":null,"env":{}}' > "$tmp/broken/config.json"
  printf '{"manifestVersion":1,"entities":[{"name":"broken","modelVersion":1,"sample":"broken/sample.json","workflow":"broken/workflow.json","config":"broken/config.json"},{"name":"never","modelVersion":1,"sample":"broken/sample.json","workflow":"broken/workflow.json","config":"broken/config.json"}]}' \
    > "$tmp/broken-manifest.json"
  out="$(CYODA_ENDPOINT="$ep" bash "$tpl/seed.sh" --manifest "$tmp/broken-manifest.json" --env development 2>&1)"; rc=$?
  assert_status 1 "$rc" "seed exits 1 on HTTP >= 400"
  assert_contains "$out" '"status":400' "seed prints the response body"
  case "$out" in *never*) _bad "seed stops at the first failure" "output: $out" ;; *) _ok ;; esac

  # 9. JWT-mode server configured like compose.shared.yaml (key and bootstrap
  #    secret from files): no token -> 401 and exit 1; get-token.sh -> seeded.
  stop_server
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$tmp/signing.pem" 2>/dev/null \
    || { _bad "openssl genpkey"; rm -rf "$tmp"; return 1; }
  printf 'smoke-only-secret\n' > "$tmp/bootstrap-client-secret"
  start_server CYODA_IAM_MODE=jwt CYODA_REQUIRE_JWT=true CYODA_JWT_SIGNING_KEY_FILE="$tmp/signing.pem" \
    CYODA_BOOTSTRAP_CLIENT_ID=seed-ci CYODA_BOOTSTRAP_CLIENT_SECRET_FILE="$tmp/bootstrap-client-secret" \
    || { _bad "start JWT-mode server"; rm -rf "$tmp"; return 1; }
  out="$(CYODA_ENDPOINT="$ep" bash "$tpl/seed.sh" --manifest "$fx/cyoda-manifest.json" --env production 2>&1)"; rc=$?
  assert_status 1 "$rc" "JWT server, no token command: seed exits 1"
  assert_contains "$out" "401" "JWT server, no token command: 401 shown"
  local tokcmd
  tokcmd="bash $(printf %q "$root/cyoda/skills/auth/templates/get-token.sh")"
  out="$(CYODA_ENDPOINT="$ep" CYODA_TOKEN_COMMAND="$tokcmd" CYODA_CLIENT_ID=seed-ci CYODA_CLIENT_SECRET=smoke-only-secret \
    bash "$tpl/seed.sh" --manifest "$fx/cyoda-manifest.json" --env production 2>&1)"; rc=$?
  assert_status 0 "$rc" "JWT server, get-token.sh: seed exits 0"
  assert_contains "$out" "SEEDED order v1" "JWT server: order seeded"
  assert_eq "$(grep -c '^WORKFLOW ' <<<"$out")" 2 "JWT server: 2 workflows imported"
  out="$(CYODA_ENDPOINT="$ep" CYODA_TOKEN_COMMAND="$tokcmd" CYODA_CLIENT_ID=seed-ci CYODA_CLIENT_SECRET=smoke-only-secret \
    bash "$tpl/verify.sh" --manifest "$fx/cyoda-manifest.json" 2>&1)"; rc=$?
  assert_status 0 "$rc" "JWT server, get-token.sh: verify exits 0"

  rm -rf "$tmp"
}
