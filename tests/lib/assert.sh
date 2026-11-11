#!/usr/bin/env bash
# Assertion helpers. Source this file; counters are PASS and FAIL.
PASS=0
FAIL=0

_ok()  { PASS=$((PASS + 1)); }
_bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; shift; while [ $# -gt 0 ]; do echo "        $1" >&2; shift; done; }

assert_eq() { # actual expected msg
  if [ "$1" = "$2" ]; then _ok; else _bad "$3" "expected: $2" "actual:   $1"; fi
}

assert_contains() { # haystack needle msg
  case "$1" in *"$2"*) _ok ;; *) _bad "$3" "expected to contain: $2" "actual: $1" ;; esac
}

assert_status() { # expected_code actual_code msg
  if [ "$1" = "$2" ]; then _ok; else _bad "$3" "expected status: $1" "actual status:   $2"; fi
}

report() {
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
