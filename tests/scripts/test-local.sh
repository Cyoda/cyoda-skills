#!/usr/bin/env bash
# cyoda-local.sh: start and stop a project's own cyoda-go (binary, Docker, repo stack).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S="$ROOT/cyoda/scripts"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
T="$(mktemp -d)"
PIDS=()
STARTED=() # project roots to stop on exit
cleanup() {
  local p r
  for r in ${STARTED[@]+"${STARTED[@]}"}; do bash "$S/cyoda-local.sh" stop "$r" >/dev/null 2>&1; done
  for p in ${PIDS[@]+"${PIDS[@]}"}; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT

export CYODA_PLUGIN_CONFIG="$T/config.json"
export CYODA_PORT_BASE=31000
export CYODA_LOCAL_DATA_ROOT="$T/data"
LOCAL="$S/cyoda-local.sh"

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
mkproj() { mkdir -p "$T/p/$1" && (cd "$T/p/$1" && pwd -P); }
field() { # output key -> value
  tr ' ' '\n' <<<"$1" | sed -n "s/^$2=//p" | head -n1
}
entry() { jq -r --arg k "$1" --arg f "$2" '.projects[$k][$f] | if . == null then "" else tostring end' "$CYODA_PLUGIN_CONFIG"; }
health() { curl -s --max-time 2 "$1/api/health"; }
docker_ok() { docker info >/dev/null 2>&1; }

test_local_start_binary() {
  local d out rc; d="$(mkproj bin)"; STARTED+=("$d")
  out="$(bash "$LOCAL" start "$d" --run binary)"; rc=$?
  assert_status 0 "$rc" "start exit"
  assert_eq "$(field "$out" STATE)" started "STATE=started"
  assert_eq "$(field "$out" HTTP)" 31000 "first block"
  assert_contains "$(health "$(field "$out" ENDPOINT)")" UP "health UP at endpoint"
  assert_eq "$(entry "$d" run)" binary "entry run"
  assert_eq "$(entry "$d" storage)" memory "entry storage"
  assert_eq "$(entry "$d" endpoint)" "http://localhost:31000" "entry endpoint"
  assert_eq "$(jq -c --arg k "$d" '.projects[$k].ports' "$CYODA_PLUGIN_CONFIG")" '{"http":31000,"grpc":32010,"admin":32011}' "entry ports"
  assert_eq "$(entry "$d" instance)" "$(bash "$S/cyoda-ports.sh" name "$d")" "entry instance"
  assert_eq "$(entry "$d" dataDir)" "$T/data/$(entry "$d" instance)" "entry dataDir"
  if [ -s "$(entry "$d" dataDir)/cyoda.pid" ]; then _ok; else _bad "pid file exists"; fi
  bash "$LOCAL" stop "$d"
}

test_local_start_again_is_ours() {
  local d o1 o2 n1 n2; d="$(mkproj again)"; STARTED+=("$d")
  o1="$(bash "$LOCAL" start "$d" --run binary)"
  n1="$(cat "$(entry "$d" dataDir)/cyoda.pid")"
  o2="$(bash "$LOCAL" start "$d")"
  n2="$(cat "$(entry "$d" dataDir)/cyoda.pid")"
  assert_eq "$(field "$o2" STATE)" ours "second start is ours"
  assert_eq "$(field "$o2" HTTP)" "$(field "$o1" HTTP)" "same port"
  assert_eq "$n2" "$n1" "same process, no second one"
  bash "$LOCAL" stop "$d"
}

test_local_restart_same_ports() {
  local d o1 o2; d="$(mkproj restart)"; STARTED+=("$d")
  o1="$(bash "$LOCAL" start "$d" --run binary)"
  bash "$LOCAL" stop "$d"
  assert_eq "$(health "$(field "$o1" ENDPOINT)")" "" "stopped: no answer"
  o2="$(bash "$LOCAL" start "$d")"
  assert_eq "$(field "$o2" HTTP)/$(field "$o2" GRPC)/$(field "$o2" ADMIN)" "$(field "$o1" HTTP)/$(field "$o1" GRPC)/$(field "$o1" ADMIN)" "same ports after restart"
  assert_eq "$(field "$o2" STATE)" started "restart is started"
  bash "$LOCAL" stop "$d"
}

test_local_two_projects_distinct_blocks() {
  local a b oa ob; a="$(mkproj two-a)"; b="$(mkproj two-b)"; STARTED+=("$a" "$b")
  oa="$(bash "$LOCAL" start "$a" --run binary)" &
  ob="$(bash "$LOCAL" start "$b" --run binary)"
  wait
  oa="$(bash "$LOCAL" start "$a")"
  if [ "$(field "$oa" HTTP)" != "$(field "$ob" HTTP)" ]; then _ok; else _bad "distinct blocks" "$oa" "$ob"; fi
  assert_contains "$(health "$(field "$oa" ENDPOINT)")" UP "a healthy"
  assert_contains "$(health "$(field "$ob" ENDPOINT)")" UP "b healthy"
  bash "$LOCAL" stop "$a"; bash "$LOCAL" stop "$b"
}

test_local_busy_default_block() {
  local d out p; d="$(mkproj busy)"; STARTED+=("$d")
  rm -f "$CYODA_PLUGIN_CONFIG"; listen 31000; p=$LPID
  out="$(bash "$LOCAL" start "$d" --run binary)"
  assert_eq "$(field "$out" HTTP)" 31100 "next block"
  assert_contains "$(health "$(field "$out" ENDPOINT)")" UP "healthy"
  if kill -0 "$p" 2>/dev/null; then _ok; else _bad "unrelated listener still running"; fi
  bash "$LOCAL" stop "$d"
  if kill -0 "$p" 2>/dev/null; then _ok; else _bad "unrelated listener survives stop"; fi
  unlisten "$p"
}

test_local_path_with_spaces() {
  local d out rc; d="$(mkproj 'my shop')"; STARTED+=("$d")
  out="$(bash "$LOCAL" start "$d" --run binary)"; rc=$?
  assert_status 0 "$rc" "start with spaces"
  assert_contains "$(health "$(field "$out" ENDPOINT)")" UP "healthy"
  bash "$LOCAL" stop "$d"; rc=$?
  assert_status 0 "$rc" "stop with spaces"
  assert_eq "$(health "$(field "$out" ENDPOINT)")" "" "stopped"
}

test_local_stop_leaves_others() {
  local a b oa ob; a="$(mkproj stop-a)"; b="$(mkproj stop-b)"; STARTED+=("$a" "$b")
  oa="$(bash "$LOCAL" start "$a" --run binary)"
  ob="$(bash "$LOCAL" start "$b" --run binary)"
  bash "$LOCAL" stop "$a"
  assert_eq "$(health "$(field "$oa" ENDPOINT)")" "" "a stopped"
  assert_contains "$(health "$(field "$ob" ENDPOINT)")" UP "b still healthy"
  bash "$LOCAL" stop "$b"
}

test_local_stop_nothing_running() {
  local d rc; d="$(mkproj idle)"
  bash "$LOCAL" stop "$d"; rc=$?
  assert_status 0 "$rc" "stop with nothing running"
}

test_local_usage() {
  local d rc; d="$(mkproj usage)"
  bash "$LOCAL" start "$d" >/dev/null 2>&1; rc=$?
  assert_status 64 "$rc" "no entry, no --run"
}

test_local_docker() {
  docker_ok || { _ok; echo "  docker unavailable: skipped test_local_docker"; return 0; }
  local d out inst; d="$(mkproj dock)"; STARTED+=("$d"); rm -f "$CYODA_PLUGIN_CONFIG"
  out="$(bash "$LOCAL" start "$d" --run docker --storage memory)"
  assert_eq "$(field "$out" STATE)" started "docker STATE"
  assert_eq "$(field "$out" HTTP)" 31000 "docker block"
  assert_contains "$(health "$(field "$out" ENDPOINT)")" UP "docker healthy"
  inst="$(entry "$d" instance)"
  assert_contains "$(docker ps --filter "label=com.docker.compose.project=$inst" --format '{{.Names}}')" "$inst" "compose project listed"
  assert_eq "$(field "$(bash "$LOCAL" start "$d")" STATE)" ours "docker again is ours"
  bash "$LOCAL" stop "$d"
  assert_eq "$(docker ps -q --filter "label=com.docker.compose.project=$inst")" "" "stop removes it"
}

test_local_repo_override() {
  docker_ok || { _ok; echo "  docker unavailable: skipped test_local_repo_override"; return 0; }
  local d out p sum inst; d="$(mkproj repo)"; STARTED+=("$d")
  cat >"$d/compose.yaml" <<'YAML'
services:
  cyoda:
    image: ghcr.io/cyoda/cyoda:0.8.4
    ports:
      - "127.0.0.1:31000:8080"
    environment:
      CYODA_STORAGE_BACKEND: memory
      CYODA_IAM_MODE: mock
YAML
  sum="$(shasum "$d/compose.yaml")"
  rm -f "$CYODA_PLUGIN_CONFIG"; listen 31000; p=$LPID
  out="$(bash "$LOCAL" start-repo "$d" "$d/compose.yaml")"
  inst="$(entry "$d" instance)"
  assert_eq "$(field "$out" STATE)" started "repo STATE"
  assert_eq "$(field "$out" RUN)" repo "RUN=repo"
  if [ "$(field "$out" HTTP)" != 31000 ] && [ -n "$(field "$out" HTTP)" ]; then _ok; else _bad "repo on another block" "$out"; fi
  assert_contains "$(health "$(field "$out" ENDPOINT)")" UP "repo healthy"
  if [ -f "$T/data/$inst/compose.override.yaml" ]; then _ok; else _bad "override written"; fi
  assert_eq "$(shasum "$d/compose.yaml")" "$sum" "repo compose file unchanged"
  assert_eq "$(entry "$d" run)" repo "entry run"
  assert_eq "$(entry "$d" compose)" "$d/compose.yaml" "entry compose"
  assert_eq "$(entry "$d" managed)" true "entry managed"
  assert_eq "$(entry "$d" composeProject)" "$inst" "entry composeProject"
  assert_eq "$(field "$(bash "$LOCAL" start-repo "$d" "$d/compose.yaml")" STATE)" ours "repo again is ours"
  bash "$LOCAL" stop "$d"
  assert_eq "$(docker ps -q --filter "label=com.docker.compose.project=$inst")" "" "repo stack down"
  if kill -0 "$p" 2>/dev/null; then _ok; else _bad "unrelated listener survives"; fi
  unlisten "$p"
}

test_local_unhealthy_cleans_up() {
  local d rc out pid; d="$(mkproj sick)"; rm -f "$CYODA_PLUGIN_CONFIG"
  mkdir -p "$T/never"
  printf '#!/bin/sh\nexec sleep 300\n' >"$T/never/cyoda"; chmod +x "$T/never/cyoda"
  # no entry before: no entry after
  out="$(PATH="$T/never:$PATH" CYODA_LOCAL_HEALTH_TIMEOUT=2 bash "$LOCAL" start "$d" --run binary 2>&1)"; rc=$?
  assert_status 4 "$rc" "never healthy: exit 4"
  assert_eq "$(jq -c --arg k "$d" '.projects[$k] // null' "$CYODA_PLUGIN_CONFIG")" null "no entry left"
  # an entry before: restored as it was
  printf '%s\n' "{\"projects\":{\"$d\":{\"endpoint\":\"http://localhost:1\",\"tokenCommand\":\"x\"}}}" >"$CYODA_PLUGIN_CONFIG"
  PATH="$T/never:$PATH" CYODA_LOCAL_HEALTH_TIMEOUT=2 bash "$LOCAL" start "$d" --run binary >/dev/null 2>&1; rc=$?
  assert_status 4 "$rc" "exit 4 again"
  assert_eq "$(jq -c --arg k "$d" '.projects[$k]' "$CYODA_PLUGIN_CONFIG")" '{"endpoint":"http://localhost:1","tokenCommand":"x"}' "entry restored"
  pid="$(cat "$T/data/$(bash "$S/cyoda-ports.sh" name "$d")/cyoda.pid" 2>/dev/null)"
  assert_eq "$pid" "" "pid file removed"
  assert_contains "$out" "did not become healthy" "message"
  rm -f "$CYODA_PLUGIN_CONFIG"
}

test_local_stop_unrelated_pid() {
  local d inst dd pid; d="$(mkproj stale)"; rm -f "$CYODA_PLUGIN_CONFIG"
  inst="$(bash "$S/cyoda-ports.sh" name "$d")"; dd="$T/data/$inst"; mkdir -p "$dd"
  sleep 300 & pid=$!; PIDS+=("$pid")
  echo "$pid" >"$dd/cyoda.pid"
  printf '%s\n' "{\"projects\":{\"$d\":{\"run\":\"binary\",\"instance\":\"$inst\",\"dataDir\":\"$dd\",\"ports\":{\"http\":31000,\"grpc\":32010,\"admin\":32011},\"endpoint\":\"http://localhost:31000\"}}}" >"$CYODA_PLUGIN_CONFIG"
  bash "$LOCAL" stop "$d"
  if kill -0 "$pid" 2>/dev/null; then _ok; else _bad "unrelated process survives stop"; fi
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -f "$CYODA_PLUGIN_CONFIG"
}

test_local_docker_unhealthy_cleans_up() {
  docker_ok || { _ok; echo "  docker unavailable: skipped test_local_docker_unhealthy_cleans_up"; return 0; }
  local d rc inst; d="$(mkproj dsick)"; STARTED+=("$d"); rm -f "$CYODA_PLUGIN_CONFIG"
  inst="$(bash "$S/cyoda-ports.sh" name "$d")"
  mkdir -p "$T/nocurl"; printf '#!/bin/sh\nexit 7\n' >"$T/nocurl/curl"; chmod +x "$T/nocurl/curl"
  PATH="$T/nocurl:$PATH" CYODA_LOCAL_HEALTH_TIMEOUT=1 bash "$LOCAL" start "$d" --run docker >/dev/null 2>&1; rc=$?
  assert_status 4 "$rc" "docker not healthy in time: exit 4"
  assert_eq "$(docker ps -aq --filter "label=com.docker.compose.project=$inst")" "" "no container left"
  docker compose -p "$inst" down >/dev/null 2>&1
  assert_eq "$(jq -c --arg k "$d" '.projects[$k] // null' "$CYODA_PLUGIN_CONFIG")" null "no entry left"
}

test_local_repo_unmanaged_left_running() {
  docker_ok || { _ok; echo "  docker unavailable: skipped test_local_repo_unmanaged_left_running"; return 0; }
  local d out; d="$(mkproj extrepo)"; rm -f "$CYODA_PLUGIN_CONFIG"
  cat >"$d/compose.yaml" <<'YAML'
services:
  cyoda:
    image: ghcr.io/cyoda/cyoda:0.8.4
    ports:
      - "127.0.0.1:31000:8080"
    environment:
      CYODA_STORAGE_BACKEND: memory
      CYODA_IAM_MODE: mock
YAML
  docker compose -p extrepo -f "$d/compose.yaml" up -d >/dev/null 2>&1
  for _ in $(seq 1 60); do [ -n "$(health http://localhost:31000)" ] && break; sleep 0.5; done
  out="$(bash "$LOCAL" start-repo "$d" "$d/compose.yaml")"
  assert_eq "$(field "$out" STATE)" ours "running stack is bound"
  assert_eq "$(entry "$d" managed)" false "managed false"
  assert_eq "$(entry "$d" composeProject)" extrepo "composeProject recorded"
  bash "$LOCAL" stop "$d" >/dev/null 2>&1
  assert_contains "$(health http://localhost:31000)" UP "stack still running after stop"
  docker compose -p extrepo -f "$d/compose.yaml" down >/dev/null 2>&1
}

# PATH with every dir holding `cyoda` replaced by a mirror without it
nocyoda_path() {
  local out="" i=0 d m f dirs
  IFS=: read -r -a dirs <<<"$PATH"
  for d in "${dirs[@]}"; do
    if [ -n "$d" ] && [ -e "$d/cyoda" ]; then
      i=$((i + 1)); m="$T/nocyoda-$i"; rm -rf "$m"; mkdir -p "$m"
      for f in "$d"/*; do [ "$(basename "$f")" = cyoda ] || ln -s "$f" "$m/"; done
      d="$m"
    fi
    out="${out:+$out:}$d"
  done
  printf '%s\n' "$out"
}

test_local_missing_cyoda_keeps_entry() {
  local d rc before np; d="$(mkproj nocyoda)"; np="$(nocyoda_path)"
  printf '%s\n' "{\"projects\":{\"$d\":{\"endpoint\":\"http://localhost:1\",\"tokenCommand\":\"x\"}}}" >"$CYODA_PLUGIN_CONFIG"
  before="$(jq -c . "$CYODA_PLUGIN_CONFIG")"
  PATH="$np" bash "$LOCAL" start "$d" --run binary >/dev/null 2>&1; rc=$?
  assert_status 5 "$rc" "cyoda missing: exit 5"
  assert_eq "$(jq -c . "$CYODA_PLUGIN_CONFIG")" "$before" "cyoda missing: entry untouched"
  rm -f "$CYODA_PLUGIN_CONFIG"
}

test_local_health_needs_launched_listener() {
  # a launched process whose child answers /api/health is not a healthy instance
  local d rc dd; d="$(mkproj imposter)"; rm -f "$CYODA_PLUGIN_CONFIG"
  mkdir -p "$T/imposter"
  cat >"$T/imposter/cyoda" <<'SH'
#!/bin/sh
mkdir -p "$HOME/srv/api"; echo '{"status":"UP"}' >"$HOME/srv/api/health"
python3 -m http.server --bind 127.0.0.1 --directory "$HOME/srv" "$CYODA_HTTP_PORT" >/dev/null 2>&1 &
echo $! >"$HOME/child.pid"
exec sleep 300
SH
  chmod +x "$T/imposter/cyoda"
  PATH="$T/imposter:$PATH" CYODA_LOCAL_HEALTH_TIMEOUT=3 bash "$LOCAL" start "$d" --run binary >/dev/null 2>&1; rc=$?
  assert_status 4 "$rc" "UP from a process other than the launched one: exit 4"
  dd="$T/data/$(bash "$S/cyoda-ports.sh" name "$d")"
  kill "$(cat "$dd/home/child.pid" 2>/dev/null)" 2>/dev/null
  rm -f "$CYODA_PLUGIN_CONFIG"
}

test_local_sqlite_in_data_dir() {
  local d out dd; d="$(mkproj sqlite)"; STARTED+=("$d"); rm -f "$CYODA_PLUGIN_CONFIG"
  mkdir -p "$T/xdg"
  out="$(XDG_DATA_HOME="$T/xdg" bash "$LOCAL" start "$d" --run binary --storage sqlite)"
  assert_contains "$(health "$(field "$out" ENDPOINT)")" UP "sqlite healthy"
  dd="$(entry "$d" dataDir)"
  assert_eq "$(find "$T/xdg" -type f | wc -l | tr -d ' ')" 0 "nothing under the developer's XDG_DATA_HOME"
  if [ -n "$(find "$dd" -name '*.db' -type f)" ]; then _ok; else _bad "sqlite db file in the data dir"; fi
  bash "$LOCAL" stop "$d"
}

test_local_stop_dir_gone() {
  local d out rc; d="$(mkproj vanish)"; STARTED+=("$d")
  out="$(bash "$LOCAL" start "$d" --run binary)"
  assert_contains "$(health "$(field "$out" ENDPOINT)")" UP "healthy before"
  rm -rf "$d"
  bash "$LOCAL" stop "$d" >/dev/null 2>&1; rc=$?
  assert_status 0 "$rc" "stop by key with the directory gone"
  assert_eq "$(health "$(field "$out" ENDPOINT)")" "" "stopped though the directory is gone"
}

compose_file() { # dir host-http [name]
  { [ -z "${3:-}" ] || echo "name: $3"
    cat <<YAML
services:
  cyoda:
    image: ghcr.io/cyoda/cyoda:0.8.4
    ports:
      - "127.0.0.1:$2:8080"
    environment:
      CYODA_STORAGE_BACKEND: memory
      CYODA_IAM_MODE: mock
YAML
  } >"$1/compose.yaml"
}

test_local_repo_own_project_name() {
  docker_ok || { _ok; echo "  docker unavailable: skipped test_local_repo_own_project_name"; return 0; }
  local d o out inst; d="$(mkproj named)"; o="$(mkproj named-other)"; STARTED+=("$d"); rm -f "$CYODA_PLUGIN_CONFIG"
  compose_file "$d" 31000 fixedname
  out="$(bash "$LOCAL" start-repo "$d" "$d/compose.yaml")"
  inst="$(entry "$d" instance)"
  assert_eq "$(field "$out" HTTP)" 31000 "free published port kept"
  assert_eq "$(entry "$d" composeProject)" "$inst" "launched under the instance name, not the file's name:"
  assert_eq "$(entry "$d" managed)" true "managed"
  assert_contains "$(docker ps --filter "label=com.docker.compose.project=$inst" --format '{{.Names}}')" "$inst" "compose project is the instance"
  if [ ! -f "$T/data/$inst/compose.override.yaml" ]; then _ok; else _bad "no override without a clash"; fi
  # another clone with the same file: its own stack, on another block (31000 is recorded and busy)
  compose_file "$o" 31000 fixedname; STARTED+=("$o")
  out="$(bash "$LOCAL" start-repo "$o" "$o/compose.yaml")"
  assert_eq "$(field "$out" STATE)" started "the clone starts its own stack"
  if [ "$(field "$out" HTTP)" != 31000 ]; then _ok; else _bad "the clone runs on another block" "$out"; fi
  bash "$LOCAL" stop "$o"
  assert_contains "$(health http://localhost:31000)" UP "stopping the clone leaves the first stack"
  bash "$LOCAL" stop "$d"
  assert_eq "$(docker ps -q --filter "label=com.docker.compose.project=$inst")" "" "first stack down"
}

test_local_repo_clash_with_recorded() {
  docker_ok || { _ok; echo "  docker unavailable: skipped test_local_repo_clash_with_recorded"; return 0; }
  local d o out inst; d="$(mkproj recclash)"; o="$(mkproj recclash-owner)"; STARTED+=("$d")
  compose_file "$d" 31000
  # another project records 31000 (stopped, nothing listens)
  printf '%s\n' "{\"projects\":{\"$o\":{\"run\":\"existing\",\"endpoint\":\"http://localhost:31000\"}}}" >"$CYODA_PLUGIN_CONFIG"
  out="$(bash "$LOCAL" start-repo "$d" "$d/compose.yaml")"
  inst="$(entry "$d" instance)"
  if [ "$(field "$out" HTTP)" != 31000 ] && [ -n "$(field "$out" HTTP)" ]; then _ok; else _bad "a port another project records is a clash" "$out"; fi
  if [ -f "$T/data/$inst/compose.override.yaml" ]; then _ok; else _bad "override written for a recorded port"; fi
  bash "$LOCAL" stop "$d"
  rm -f "$CYODA_PLUGIN_CONFIG"
}

test_local_repo_stop_checks_workdir() {
  docker_ok || { _ok; echo "  docker unavailable: skipped test_local_repo_stop_checks_workdir"; return 0; }
  local d b inst out; d="$(mkproj wd-mine)"; b="$(mkproj wd-theirs)"
  compose_file "$d" 31000; compose_file "$b" 31000
  inst="$(bash "$S/cyoda-ports.sh" name "$d")"
  # a stack under this project's instance name, started from another directory
  docker compose -p "$inst" -f "$b/compose.yaml" up -d >/dev/null 2>&1
  for _ in $(seq 1 60); do [ -n "$(health http://localhost:31000)" ] && break; sleep 0.5; done
  printf '%s\n' "{\"projects\":{\"$d\":{\"run\":\"repo\",\"instance\":\"$inst\",\"dataDir\":\"$T/data/$inst\",\"compose\":\"$d/compose.yaml\",\"composeProject\":\"$inst\",\"managed\":true,\"ports\":{\"http\":31000,\"grpc\":32010,\"admin\":32011},\"endpoint\":\"http://localhost:31000\"}}}" >"$CYODA_PLUGIN_CONFIG"
  out="$(bash "$LOCAL" stop "$d" 2>&1)"
  assert_contains "$(health http://localhost:31000)" UP "a stack started from another directory is left running"
  docker compose -p "$inst" -f "$b/compose.yaml" down >/dev/null 2>&1
  rm -f "$CYODA_PLUGIN_CONFIG"
}

test_local_repo_stop_compose_gone_calls() {
  local d w fd log; d="$(mkproj gone-calls)"; w="$(mkproj gone-calls-cwd)"; fd="$T/fakedocker"; log="$T/docker.log"
  mkdir -p "$fd"; : >"$log"
  cat >"$fd/docker" <<SH
#!/usr/bin/env bash
echo "\$*" >>"$log"
case "\$1 \$2" in "ps -aq"|"network ls") echo fakeid ;; esac
exit 0
SH
  chmod +x "$fd/docker"
  printf '%s\n' "{\"projects\":{\"$d\":{\"run\":\"repo\",\"instance\":\"gonecalls\",\"dataDir\":\"$T/data/gonecalls\",\"compose\":\"$d/compose.yaml\",\"composeProject\":\"gonecalls\",\"managed\":true,\"ports\":{\"http\":31000,\"grpc\":32010,\"admin\":32011},\"endpoint\":\"http://localhost:31000\"}}}" >"$CYODA_PLUGIN_CONFIG"
  echo 'services: {decoy: {image: busybox}}' >"$w/compose.yaml"
  (cd "$w" && PATH="$fd:$PATH" bash "$LOCAL" stop "$d" >/dev/null 2>&1)
  assert_eq "$(grep '^compose ' "$log" | grep -cv -- ' -f ')" 0 "no compose call without -f when the file is gone"
  assert_contains "$(cat "$log")" "rm -f fakeid" "containers removed by label"
  assert_contains "$(cat "$log")" "network rm fakeid" "network removed by label"
  rm -f "$CYODA_PLUGIN_CONFIG"
}

test_local_repo_stop_compose_gone() {
  docker_ok || { _ok; echo "  docker unavailable: skipped test_local_repo_stop_compose_gone"; return 0; }
  local d w inst rc; d="$(mkproj gone-file)"; w="$(mkproj gone-cwd)"; STARTED+=("$d"); rm -f "$CYODA_PLUGIN_CONFIG"
  compose_file "$d" 31000
  bash "$LOCAL" start-repo "$d" "$d/compose.yaml" >/dev/null
  inst="$(entry "$d" instance)"
  rm -f "$d/compose.yaml"
  # a Compose file in the caller's working directory must not be picked up (this one doesn't load)
  echo 'services: [not, a, map]' >"$w/compose.yaml"
  (cd "$w" && bash "$LOCAL" stop "$d" >/dev/null 2>&1); rc=$?
  assert_status 0 "$rc" "stop with the compose file gone"
  assert_eq "$(docker ps -aq --filter "label=com.docker.compose.project=$inst")" "" "containers removed by label"
  assert_eq "$(docker network ls -q --filter "label=com.docker.compose.project=$inst")" "" "network removed by label"
  rm -f "$CYODA_PLUGIN_CONFIG"
}

test_local_usage
test_local_stop_nothing_running
test_local_unhealthy_cleans_up
test_local_stop_unrelated_pid
test_local_start_binary
test_local_start_again_is_ours
test_local_restart_same_ports
test_local_two_projects_distinct_blocks
test_local_busy_default_block
test_local_path_with_spaces
test_local_stop_leaves_others
test_local_docker
test_local_repo_override
test_local_docker_unhealthy_cleans_up
test_local_repo_unmanaged_left_running
test_local_missing_cyoda_keeps_entry
test_local_health_needs_launched_listener
test_local_sqlite_in_data_dir
test_local_stop_dir_gone
test_local_repo_own_project_name
test_local_repo_clash_with_recorded
test_local_repo_stop_checks_workdir
test_local_repo_stop_compose_gone_calls
test_local_repo_stop_compose_gone
report
