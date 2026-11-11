#!/usr/bin/env bash
# cyoda-ports.sh: stable instance names and free port blocks with ownership evidence.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S="$ROOT/cyoda/scripts"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
T="$(mktemp -d)"
PIDS=()
cleanup() {
  local p
  for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT

export CYODA_PLUGIN_CONFIG="$T/config.json"
export CYODA_PORT_BASE=31000
export CYODA_LOCAL_DATA_ROOT="$T/data"

listen() { # port -> sets LPID
  python3 -m http.server --bind 127.0.0.1 "$1" >/dev/null 2>&1 &
  LPID=$!
  PIDS+=("$LPID")
  for _ in $(seq 1 50); do
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    sleep 0.1
  done
}
unlisten() { kill "$1" 2>/dev/null; wait "$1" 2>/dev/null; }

mkproj() { # name -> prints real path
  mkdir -p "$T/p/$1" && (cd "$T/p/$1" && pwd -P)
}
# config <json>
config() { printf '%s\n' "$1" >"$CYODA_PLUGIN_CONFIG"; }
pick() { bash "$S/cyoda-ports.sh" pick "$1"; }

test_name_stable_and_distinct() {
  local a b c d
  a="$(mkproj a/shop)"; b="$(mkproj b/shop)"
  c="$(bash "$S/cyoda-ports.sh" name "$a")"; d="$(bash "$S/cyoda-ports.sh" name "$a")"
  assert_eq "$c" "$d" "same path, same name"
  assert_eq "$(bash "$S/cyoda-ports.sh" name "$b" | grep -c '^shop-[0-9a-f]\{6\}$')" 1 "name shape"
  if [ "$c" != "$(bash "$S/cyoda-ports.sh" name "$b")" ]; then _ok; else _bad "same basename, different parents must differ"; fi
  assert_eq "$(echo "$c" | grep -c '^shop-[0-9a-f]\{6\}$')" 1 "name shape (a)"
}

test_name_sanitised() {
  local d n
  d="$(mkproj 'My Shop.v2')"
  n="$(bash "$S/cyoda-ports.sh" name "$d")"
  assert_eq "$(echo "$n" | grep -c '^my-shop-v2-[0-9a-f]\{6\}$')" 1 "sanitised name: $n"
}

test_pick_free_default() {
  local d; d="$(mkproj free)"; config '{}'
  assert_eq "$(pick "$d")" "HTTP=31000 GRPC=32010 ADMIN=32011 STATE=free" "first block"
}

test_pick_no_config_file() {
  local d; d="$(mkproj noconf)"; rm -f "$CYODA_PLUGIN_CONFIG"
  assert_eq "$(pick "$d")" "HTTP=31000 GRPC=32010 ADMIN=32011 STATE=free" "no config"
}

test_pick_skips_busy() {
  local d; d="$(mkproj busy)"; config '{}'
  listen 31000; local p=$LPID
  assert_eq "$(pick "$d")" "HTTP=31100 GRPC=32110 ADMIN=32111 STATE=free" "busy http port skipped"
  unlisten "$p"
  listen 32011; p=$LPID
  assert_eq "$(pick "$d")" "HTTP=31100 GRPC=32110 ADMIN=32111 STATE=free" "busy admin port skipped"
  unlisten "$p"
}

test_pick_skips_other_project_block() {
  local d; d="$(mkproj mine)"
  config '{"projects":{"/nonexistent/other":{"endpoint":"http://localhost:31000","ports":{"http":31000,"grpc":32010,"admin":32011}}}}'
  assert_eq "$(pick "$d")" "HTTP=31100 GRPC=32110 ADMIN=32111 STATE=free" "other project's recorded block skipped"
}

test_pick_recorded_ours_binary() {
  local d n dd; d="$(mkproj ours)"; n="$(bash "$S/cyoda-ports.sh" name "$d")"; dd="$T/data/$n"
  mkdir -p "$dd"
  listen 31200; local p=$LPID
  echo "$p" >"$dd/cyoda.pid"
  config "$(jq -n --arg k "$d" --arg dd "$dd" --arg n "$n" '{projects:{($k):{endpoint:"http://localhost:31200",run:"binary",instance:$n,dataDir:$dd,ports:{http:31200,grpc:32210,admin:32211}}}}')"
  assert_eq "$(pick "$d")" "HTTP=31200 GRPC=32210 ADMIN=32211 STATE=ours" "recorded block with live listener pid"
  unlisten "$p"
}

test_pick_stale_pid_not_ours() {
  local d n dd; d="$(mkproj stale)"; n="$(bash "$S/cyoda-ports.sh" name "$d")"; dd="$T/data/$n"
  mkdir -p "$dd"
  listen 31200; local p=$LPID
  sleep 300 & local sp=$!; PIDS+=("$sp")
  echo "$sp" >"$dd/cyoda.pid"
  config "$(jq -n --arg k "$d" --arg dd "$dd" --arg n "$n" '{projects:{($k):{endpoint:"http://localhost:31200",run:"binary",instance:$n,dataDir:$dd,ports:{http:31200,grpc:32210,admin:32211}}}}')"
  assert_eq "$(pick "$d")" "HTTP=31000 GRPC=32010 ADMIN=32011 STATE=free" "pid not listening on the port: not ours"
  unlisten "$p"
}

test_pick_recorded_ours_docker() {
  local d n dd; d="$(mkproj dock)"; n="$(bash "$S/cyoda-ports.sh" name "$d")"; dd="$T/data/$n"
  mkdir -p "$dd" "$T/shim"
  cat >"$T/shim/docker" <<SH
#!/usr/bin/env bash
case "\$1" in
  ps) echo aaa ;;
  inspect) cat <<'J'
[{"Id":"aaa","Name":"/${n}-cyoda-1","Config":{"Image":"ghcr.io/cyoda/cyoda:0.8.4","Labels":{"com.docker.compose.project":"${n}","com.docker.compose.project.working_dir":"${dd}"}},
 "NetworkSettings":{"Ports":{"8080/tcp":[{"HostIp":"0.0.0.0","HostPort":"31300"}]}}}]
J
  ;;
esac
SH
  chmod +x "$T/shim/docker"
  listen 31300; local p=$LPID
  config "$(jq -n --arg k "$d" --arg dd "$dd" --arg n "$n" '{projects:{($k):{endpoint:"http://localhost:31300",run:"docker",instance:$n,dataDir:$dd,ports:{http:31300,grpc:32310,admin:32311}}}}')"
  assert_eq "$(PATH="$T/shim:$PATH" pick "$d")" "HTTP=31300 GRPC=32310 ADMIN=32311 STATE=ours" "docker container with matching project and workdir"
  # same container, different working dir: not ours
  sed -i.bak "s#$dd#/elsewhere#" "$T/shim/docker"
  assert_eq "$(PATH="$T/shim:$PATH" pick "$d")" "HTTP=31000 GRPC=32010 ADMIN=32011 STATE=free" "docker container from another working dir is not ours"
  unlisten "$p"
}

test_pick_none_free() {
  local d rc entries="{" k; d="$(mkproj full)"
  for k in $(seq 0 19); do
    entries+="\"/x/p$k\":{\"endpoint\":\"e\",\"ports\":{\"http\":$((31000 + 100 * k)),\"grpc\":$((32010 + 100 * k)),\"admin\":$((32011 + 100 * k))}},"
  done
  config "{\"projects\":${entries%,}}}"
  pick "$d" >/dev/null 2>&1; rc=$?
  assert_status 3 "$rc" "no free block: exit 3"
}

test_name_stable_and_distinct
test_name_sanitised
test_pick_free_default
test_pick_no_config_file
test_pick_skips_busy
test_pick_skips_other_project_block
test_pick_recorded_ours_binary
test_pick_stale_pid_not_ours
test_pick_recorded_ours_docker
test_pick_none_free
report
