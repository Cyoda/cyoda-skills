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

  # Helpers for fix-round cases: manifests with absolute paths into the fixture.
  local s_order="$fx/src/data/order-v1-sample.json" w_order="$fx/src/workflows/order-v1-workflow.json"
  local c_order="$fx/src/config/order-v1-config.json"
  # entry <name> <sample> <workflow> <config> -> one manifest entity (JSON)
  entry() { jq -nc --arg n "$1" --arg s "$2" --arg w "$3" --arg c "$4" \
    '{name:$n, modelVersion:1, sample:$s, workflow:$w, config:$c}'; }
  # manifest <file> <entry>... -> writes a manifest
  manifest() { local f="$1"; shift; printf '%s\n' "$@" | jq -s '{manifestVersion:1, entities:.}' > "$f"; }
  model_state() { curl -s "$BASE/model/" | jq -r --arg n "$1" '[.[] | select(.modelName == $n)][0].currentState // "MISSING"'; }
  post_code() { curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "$2" "$BASE/entity/JSON/$1/1"; }
  local extra='{"orderId":"X-1","customerId":"CUST-1","amount":1,"giftWrap":true}'

  # 9. A bad changeLevel fails before any write, even for entities listed before it.
  printf '{"uniqueKeys":[],"changeLevel":"STRUCTRAL","env":{}}' > "$tmp/bad-cl.json"
  manifest "$tmp/badcl-manifest.json" "$(entry firstok "$s_order" "$w_order" "$c_order")" \
    "$(entry badcl "$s_order" "$w_order" "$tmp/bad-cl.json")"
  out="$(CYODA_ENDPOINT="$ep" bash "$tpl/seed.sh" --manifest "$tmp/badcl-manifest.json" --env development 2>&1)"; rc=$?
  assert_status 1 "$rc" "bad changeLevel: seed exits 1"
  assert_contains "$out" "STRUCTRAL" "bad changeLevel: the value is named"
  assert_eq "$(model_state firstok),$(model_state badcl)" "MISSING,MISSING" "bad changeLevel: nothing written to the instance"

  # 10. A malformed workflow fails before the model is touched (no lock).
  printf '{"nope":1}' > "$tmp/bad-workflow.json"
  manifest "$tmp/badwf-manifest.json" "$(entry badwf "$s_order" "$tmp/bad-workflow.json" "$c_order")"
  out="$(CYODA_ENDPOINT="$ep" bash "$tpl/seed.sh" --manifest "$tmp/badwf-manifest.json" --env development 2>&1)"; rc=$?
  assert_status 1 "$rc" "malformed workflow: seed exits 1"
  assert_eq "$(model_state badwf)" "MISSING" "malformed workflow: model not imported or locked"

  # 11. A run that died after the lock (changeLevel not applied) is completed by a re-run.
  curl -s -o /dev/null -X POST -H 'Content-Type: application/json' --data-binary @"$s_order" "$BASE/model/import/JSON/SAMPLE_DATA/relock/1"
  curl -s -o /dev/null -X PUT "$BASE/model/relock/1/lock"
  assert_status 400 "$(post_code relock "$extra")" "relock: strict before the re-run (control)"
  manifest "$tmp/relock-manifest.json" "$(entry relock "$s_order" "$w_order" "$c_order")"
  out="$(CYODA_ENDPOINT="$ep" bash "$tpl/seed.sh" --manifest "$tmp/relock-manifest.json" --env development 2>&1)"; rc=$?
  assert_status 0 "$rc" "relock: re-run exits 0"
  assert_contains "$out" "SKIPPED-MODEL relock v1 (locked)" "relock: model steps skipped"
  assert_status 200 "$(post_code relock "$extra")" "relock: re-run applied changeLevel STRUCTURAL"

  # 12. --env development on a fresh model: base STRUCTURAL applies (the production
  #     null override doesn't), so a field outside the sample is accepted.
  manifest "$tmp/dev-manifest.json" "$(entry orderdev "$s_order" "$w_order" "$c_order")"
  out="$(CYODA_ENDPOINT="$ep" bash "$tpl/seed.sh" --manifest "$tmp/dev-manifest.json" --env development 2>&1)"; rc=$?
  assert_status 0 "$rc" "env development: seed exits 0"
  assert_contains "$out" "SEEDED orderdev v1" "env development: seeded"
  assert_status 200 "$(post_code orderdev "$extra")" "env development: field outside the sample accepted"

  # 13. The token never reaches curl's command line (it is read from a header file).
  mkdir -p "$tmp/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexec %q "$@"\n' "$tmp/curl-argv.log" "$(command -v curl)" > "$tmp/bin/curl"
  chmod +x "$tmp/bin/curl"
  out="$(PATH="$tmp/bin:$PATH" CYODA_ENDPOINT="$ep" CYODA_TOKEN_COMMAND="echo tok-NOT-IN-ARGV-42" \
    bash "$tpl/seed.sh" --manifest "$fx/cyoda-manifest.json" --env production 2>&1)"; rc=$?
  assert_status 0 "$rc" "argv check: seed exits 0"
  out="$(PATH="$tmp/bin:$PATH" CYODA_ENDPOINT="$ep" CYODA_TOKEN_COMMAND="echo tok-NOT-IN-ARGV-42" \
    bash "$tpl/verify.sh" --manifest "$fx/cyoda-manifest.json" 2>&1)"; rc=$?
  assert_status 0 "$rc" "argv check: verify exits 0"
  assert_eq "$(grep -c 'tok-NOT-IN-ARGV-42' "$tmp/curl-argv.log")" 0 "token not on curl's command line"
  assert_contains "$(cat "$tmp/curl-argv.log")" "-H @" "curl reads the auth header from a file"
  : > "$tmp/curl-argv.log"
  CYODA_ENDPOINT="$ep" PATH="$tmp/bin:$PATH" bash "$tpl/seed.sh" --manifest "$fx/cyoda-manifest.json" --env production >/dev/null 2>&1
  assert_eq "$(grep -c -e '-H @' -e 'Authorization' "$tmp/curl-argv.log")" 0 "no auth header when CYODA_TOKEN_COMMAND is unset"
  unset -f entry manifest model_state post_code

  # 14. JWT-mode server configured like compose.shared.yaml (key and bootstrap
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
