#!/usr/bin/env bash
# Start and stop a project's own cyoda-go instance on a free port block.
#   cyoda-local.sh start <root> [--run binary|docker] [--storage memory|sqlite]
#   cyoda-local.sh start-repo <root> <compose-file>
#   cyoda-local.sh stop <root>   (<root> may be an entry's key whose directory is gone)
# start/start-repo print: ENDPOINT=<url> HTTP=<p> GRPC=<p> ADMIN=<p> RUN=<run> STATE=started|ours
# --run defaults to the project entry's run. Ports come from cyoda-ports.sh pick; the entry
# (run, instance, dataDir, ports, storage|compose, endpoint) is written through cyoda-config-write.sh
# before launch, so a concurrent start picks another block. Data lives in
# ${CYODA_LOCAL_DATA_ROOT:-~/.local/share/cyoda/projects}/<instance>.
# A binary instance gets HOME, XDG_CONFIG_HOME, XDG_DATA_HOME and CYODA_SQLITE_PATH under dataDir.
# start-repo: when a published cyoda port (8080/9090/9091 inside) of the repo's compose file is
# busy or recorded by another project or profile (cyoda-ports.sh recorded), dataDir/compose.override.yaml
# remaps them to a free block; the file itself is untouched.
#   The override uses `!override`, which needs Docker Compose >= 2.24.
# A stack start-repo launches always runs as Compose project <instance> (composeProject, managed: true);
# one already running under another name is only bound (managed: false, STATE=ours).
# stop never touches a process or container it did not start: binary - the pid must listen on the
# recorded HTTP port; repo - `down` only when managed is true; docker/binary are always managed.
# No `down` runs unless every container of that Compose project has the compose file's dir or
# dataDir as its working dir.
# A start that fails (compose up error, or no /api/health UP within ${CYODA_LOCAL_HEALTH_TIMEOUT:-30} s)
# stops what it launched and restores the entry to what it was before.
# Exit: 0 ok (stop: also when nothing runs), 1 invalid plugin config, 3 no free block,
# 4 did not become healthy / compose up failed (log tail on stderr), 5 docker, lsof or cyoda unavailable,
# 64 usage.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"
DATA_ROOT="${CYODA_LOCAL_DATA_ROOT:-$HOME/.local/share/cyoda/projects}"
TEMPLATE="$HERE/../skills/deploy/templates/compose.single-user.yaml"

die() { echo "cyoda-local.sh: $2" >&2; exit "$1"; }
usage() {
  echo "usage: cyoda-local.sh start <root> [--run binary|docker] [--storage memory|sqlite]" >&2
  echo "       cyoda-local.sh start-repo <root> <compose-file>" >&2
  echo "       cyoda-local.sh stop <root>" >&2
  exit 64
}

[ $# -ge 2 ] || usage
CMD="$1"; ROOT_ARG="$2"; shift 2

entry() { # field -> value of this project's entry or ""
  [ -f "$CONFIG" ] || return 0
  jq -r --arg k "$ROOT" --arg f "$1" '(.projects // {})[$k][$f] // "" | tostring' "$CONFIG" 2>/dev/null
}
rec_port() {
  [ -f "$CONFIG" ] || return 0
  jq -r --arg k "$ROOT" --arg f "$1" '(.projects // {})[$k].ports | if type == "object" then (.[$f] // "") | tostring else "" end' "$CONFIG" 2>/dev/null
}

ROOT="$(cd "$ROOT_ARG" 2>/dev/null && pwd -P)" || ROOT=""
if [ -n "$ROOT" ]; then
  INSTANCE="$(bash "$HERE/cyoda-ports.sh" name "$ROOT")" || exit 64
elif [ "$CMD" = stop ] && [ -f "$CONFIG" ] \
  && jq -e --arg k "$ROOT_ARG" '(.projects // {}) | has($k)' "$CONFIG" >/dev/null 2>&1; then
  ROOT="$ROOT_ARG"; INSTANCE="$(entry instance)" # the entry's key; its directory is gone
else
  die 64 "no such directory: $ROOT_ARG"
fi
DD="$DATA_ROOT/$INSTANCE"

listening() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1 && return 0
  (exec 3>/dev/tcp/127.0.0.1/"$1") >/dev/null 2>&1
}

need_docker() { docker info >/dev/null 2>&1 || die 5 "docker is not available"; }
need_lsof() { command -v lsof >/dev/null 2>&1 || die 5 "lsof is required"; }

# Compose project $1: is every container's working dir one of $2...? (no container: yes)
compose_from() {
  local p="$1" wds wd d ok; shift
  wds="$(docker ps -a --filter "label=com.docker.compose.project=$p" \
    --format '{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null)" || return 1
  while IFS= read -r wd; do
    [ -n "$wd" ] || continue
    ok=""
    for d in "$@"; do
      if [ "$wd" = "$d" ] || { [ -d "$d" ] && [ "$wd" = "$(cd "$d" && pwd -P)" ]; }; then ok=1; fi
    done
    [ -n "$ok" ] || return 1
  done <<<"$wds"
  return 0
}

LOCK="$DATA_ROOT/.lock"
lock() {
  mkdir -p "$DATA_ROOT" || die 64 "cannot create $DATA_ROOT"
  local holder
  for _ in $(seq 1 120); do
    if mkdir "$LOCK" 2>/dev/null; then echo $$ >"$LOCK/pid"; return 0; fi
    holder="$(cat "$LOCK/pid" 2>/dev/null || true)"
    if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
    sleep 0.25
  done
  die 4 "could not take $LOCK"
}
unlock() { rm -rf "$LOCK"; }

# pick -> sets HTTP GRPC ADMIN PSTATE; exits with pick's code on failure.
do_pick() {
  local out rc
  out="$(bash "$HERE/cyoda-ports.sh" pick "$ROOT")"; rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
  HTTP="$(sed -n 's/.*HTTP=\([0-9]*\).*/\1/p' <<<"$out")"
  GRPC="$(sed -n 's/.*GRPC=\([0-9]*\).*/\1/p' <<<"$out")"
  ADMIN="$(sed -n 's/.*ADMIN=\([0-9]*\).*/\1/p' <<<"$out")"
  PSTATE="$(sed -n 's/.*STATE=\([a-z]*\).*/\1/p' <<<"$out")"
}

PRIOR=null          # the project's entry before this start, for restore_entry
LAUNCH_PID=""       # a process this start launched
LAUNCH_COMPOSE=()   # docker compose args (-p .. -f ..) of a stack this start launched
LAUNCH_DIR=""       # its compose file's dir

snapshot_entry() {
  PRIOR=null
  [ -f "$CONFIG" ] || return 0
  PRIOR="$(jq -c --arg k "$ROOT" '(.projects // {})[$k] // null' "$CONFIG" 2>/dev/null)" || PRIOR=null
  [ -n "$PRIOR" ] || PRIOR=null
}
restore_entry() {
  bash "$HERE/cyoda-config-write.sh" 'if $prior == null then del(.projects[$k]) else .projects[$k] = $prior end' \
    --arg k "$ROOT" --argjson prior "$PRIOR" || echo "cyoda-local.sh: could not restore the plugin config entry" >&2
}

# A launched instance that failed: show logs, stop what we launched, restore the entry, exit 4.
fail_launch() { # message
  echo "cyoda-local.sh: $1; log tail:" >&2
  if [ -n "$LAUNCH_PID" ]; then
    tail -n 20 "$DD/cyoda.log" >&2 2>/dev/null
    kill "$LAUNCH_PID" 2>/dev/null
    for _ in $(seq 1 20); do kill -0 "$LAUNCH_PID" 2>/dev/null || break; sleep 0.25; done
    kill -9 "$LAUNCH_PID" 2>/dev/null
    rm -f "$DD/cyoda.pid"
  fi
  if [ "${#LAUNCH_COMPOSE[@]}" -gt 0 ]; then
    docker compose "${LAUNCH_COMPOSE[@]}" logs --tail 20 >&2 2>/dev/null
    if compose_from "${LAUNCH_COMPOSE[1]}" "$LAUNCH_DIR" "$DD"; then
      docker compose "${LAUNCH_COMPOSE[@]}" down >&2 2>/dev/null
    fi
  fi
  restore_entry
  exit 4
}

# write_entry run storage compose composeProject managed  (trailing args may be empty)
write_entry() {
  bash "$HERE/cyoda-config-write.sh" '
    .projects //= {}
    | .projects[$k] = (((.projects[$k] // {}) | del(.storage, .compose, .composeProject, .managed))
        + {run: $run, instance: $inst, dataDir: $dd,
           ports: {http: ($h | tonumber), grpc: ($g | tonumber), admin: ($a | tonumber)},
           endpoint: ("http://localhost:" + $h)}
        + (if $storage != "" then {storage: $storage} else {} end)
        + (if $compose != "" then {compose: $compose} else {} end)
        + (if $cp != "" then {composeProject: $cp} else {} end)
        + (if $managed != "" then {managed: ($managed == "true")} else {} end))' \
    --arg k "$ROOT" --arg run "$1" --arg inst "$INSTANCE" --arg dd "$DD" \
    --arg h "$HTTP" --arg g "$GRPC" --arg a "$ADMIN" --arg storage "${2:-}" --arg compose "${3:-}" \
    --arg cp "${4:-}" --arg managed "${5:-}" \
    || die 1 "cannot write the plugin config"
}

wait_healthy() { # pid-or-empty; returns 1 on timeout or when that pid died. A pid must be the HTTP listener.
  local n=$(( ${CYODA_LOCAL_HEALTH_TIMEOUT:-30} * 2 ))
  [ "$n" -ge 1 ] || n=1 # BSD seq counts down from 1 to 0
  for _ in $(seq 1 "$n"); do
    if [ "$(curl -s --max-time 1 "http://localhost:$HTTP/api/health" 2>/dev/null | jq -r '.status // empty' 2>/dev/null)" = UP ] \
      && { [ -z "${1:-}" ] || lsof -nP -a -p "$1" -iTCP:"$HTTP" -sTCP:LISTEN >/dev/null 2>&1; }; then return 0; fi
    if [ -n "${1:-}" ] && ! kill -0 "$1" 2>/dev/null; then break; fi
    sleep 0.5
  done
  return 1
}

emit() { echo "ENDPOINT=http://localhost:$HTTP HTTP=$HTTP GRPC=$GRPC ADMIN=$ADMIN RUN=$RUN STATE=$1"; }

# reserve a free block (entry written under the lock); sets HTTP GRPC ADMIN PSTATE.
reserve() { # run storage compose
  lock
  do_pick
  if [ "$PSTATE" = free ]; then write_entry "$@"; fi
  unlock
}

render_compose() { # storage
  mkdir -p "$DD" || die 64 "cannot create $DD"
  if [ "$1" = memory ]; then
    sed -e 's/CYODA_STORAGE_BACKEND: sqlite/CYODA_STORAGE_BACKEND: memory/' -e '/CYODA_SQLITE_PATH:/d' "$TEMPLATE" >"$DD/compose.yaml"
  else
    cp "$TEMPLATE" "$DD/compose.yaml"
  fi
}

launch_binary() { # storage
  mkdir -p "$DD/home/.config" "$DD/home/.local/share" || die 64 "cannot create $DD"
  (
    cd "$DD" || exit 1
    nohup env HOME="$DD/home" XDG_CONFIG_HOME="$DD/home/.config" XDG_DATA_HOME="$DD/home/.local/share" \
      CYODA_SQLITE_PATH="$DD/cyoda.db" CYODA_STORAGE_BACKEND="$1" CYODA_IAM_MODE=mock \
      CYODA_HTTP_PORT="$HTTP" CYODA_GRPC_PORT="$GRPC" CYODA_ADMIN_PORT="$ADMIN" \
      cyoda >"$DD/cyoda.log" 2>&1 </dev/null &
    echo $! >"$DD/cyoda.pid"
  )
  LAUNCH_PID="$(cat "$DD/cyoda.pid")"
  wait_healthy "$LAUNCH_PID" || fail_launch "instance on port $HTTP did not become healthy"
}

compose_env() { export CYODA_HOST_HTTP_PORT="$HTTP" CYODA_HOST_GRPC_PORT="$GRPC" CYODA_HOST_ADMIN_PORT="$ADMIN"; }

cmd_start() {
  local run="" storage="" arg
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --run) [ $# -ge 2 ] || usage; run="$2"; shift 2 ;;
      --storage) [ $# -ge 2 ] || usage; storage="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$run" ] || run="$(entry run)"
  case "$run" in binary|docker) ;; repo) die 64 "this project runs its own compose stack: use start-repo" ;; "") die 64 "no --run given and the project has no recorded run" ;; *) die 64 "cannot start run '$run'" ;; esac
  case "$storage" in ""|memory|sqlite) ;; *) usage ;; esac
  [ -n "$storage" ] || storage="$(entry storage)"
  [ -n "$storage" ] || storage=memory
  RUN="$run"
  need_lsof
  [ "$run" != docker ] || need_docker
  [ "$run" != binary ] || command -v cyoda >/dev/null 2>&1 || die 5 "cyoda is not on PATH"

  local attempt
  snapshot_entry
  for attempt in 1 2 3; do
    reserve "$run" "$storage" ""
    if [ "$PSTATE" = ours ]; then emit ours; exit 0; fi
    # re-check right before launching: a foreign process may have bound a port since the pick
    if ! listening "$HTTP" && ! listening "$GRPC" && ! listening "$ADMIN"; then break; fi
    [ "$attempt" -lt 3 ] || { restore_entry; die 3 "ports kept getting taken"; }
  done

  if [ "$run" = binary ]; then
    launch_binary "$storage"
  else
    render_compose "$storage"
    compose_env
    LAUNCH_COMPOSE=(-p "$INSTANCE" -f "$DD/compose.yaml"); LAUNCH_DIR="$DD"
    docker compose "${LAUNCH_COMPOSE[@]}" up -d >&2 || fail_launch "docker compose up failed"
    wait_healthy "" || fail_launch "instance on port $HTTP did not become healthy"
  fi
  emit started
}

# Published host ports of the compose files, from `docker compose config`: "<service> <published> <target>" lines.
published() { # files...
  local args=() f
  for f in "$@"; do args+=(-f "$f"); done
  docker compose "${args[@]}" config --format json 2>/dev/null \
    | jq -r '.services | to_entries[] | .key as $s | (.value.ports // [])[] | select(.published != null and .published != "") | "\($s) \(.published) \(.target)"'
}

cmd_start_repo() {
  [ $# -eq 1 ] || usage
  local cf cdir name ov="$DD/compose.override.yaml" files lines
  cf="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)/$(basename "$1")"
  [ -f "$cf" ] || die 64 "no such compose file: $1"
  cdir="$(dirname "$cf")"
  RUN=repo
  need_lsof; need_docker
  snapshot_entry

  name="$(docker compose -f "$cf" config --format json 2>/dev/null | jq -r '.name // empty')"
  [ -n "$name" ] || die 64 "docker compose cannot read $cf"

  # already running and ours? (project = instance or the file's own name, working dir = the file's dir or dataDir)
  files=("$cf"); [ ! -f "$ov" ] || files+=("$ov")
  local line http="" proj
  while IFS= read -r line; do
    proj="$(sed -n 's/.*COMPOSE_PROJECT=\([^ ]*\) .*/\1/p' <<<"$line")"
    if [ "$proj" = "$INSTANCE" ] || [ "$proj" = "$name" ]; then
      case "$line" in *" WORKDIR=$cdir "*|*" WORKDIR=$DD "*)
        http="$(sed -n 's/.*ENDPOINT=http:\/\/[^ ]*:\([0-9]*\) IMAGE=.*/\1/p' <<<"$line")"
        [ -z "$http" ] || break ;;
      esac
    fi
  done < <(bash "$HERE/cyoda-docker-instances.sh" 2>/dev/null)
  if [ -n "$http" ]; then
    lines="$(published "${files[@]}")"
    HTTP="$http"
    GRPC="$(awk '$3 == 9090 {print $2; exit}' <<<"$lines")"
    ADMIN="$(awk '$3 == 9091 {print $2; exit}' <<<"$lines")"
    if [ -z "$GRPC" ] || [ -z "$ADMIN" ]; then
      do_pick; [ -n "$GRPC" ] || GRPC="$(rec_port grpc)"; [ -n "$ADMIN" ] || ADMIN="$(rec_port admin)"
    fi
    HTTP="$http"
    [ -n "$GRPC" ] && [ -n "$ADMIN" ] || die 3 "cannot determine the ports of the running stack"
    # managed only when it runs under this project's instance name, as start-repo launches it
    local managed=false
    [ "$proj" != "$INSTANCE" ] || managed=true
    lock; write_entry repo "" "$cf" "$proj" "$managed"; unlock
    emit ours; exit 0
  fi

  # fresh start: the repo file alone, then a free block if a cyoda port is busy or recorded by another
  rm -f "$ov"
  lines="$(published "$cf")"
  local clash="" pub tgt recorded
  recorded="$(bash "$HERE/cyoda-ports.sh" recorded "$ROOT")" || exit 1
  while read -r _ pub tgt; do
    case "$tgt" in 8080|9090|9091) if listening "$pub" || grep -qx "$pub" <<<"$recorded"; then clash=1; fi ;; esac
  done <<<"$lines"

  if [ -z "$clash" ]; then
    HTTP="$(awk '$3 == 8080 {print $2; exit}' <<<"$lines")"
    GRPC="$(awk '$3 == 9090 {print $2; exit}' <<<"$lines")"
    ADMIN="$(awk '$3 == 9091 {print $2; exit}' <<<"$lines")"
    if [ -z "$HTTP" ] || [ -z "$GRPC" ] || [ -z "$ADMIN" ]; then
      local h="$HTTP" g="$GRPC" a="$ADMIN"
      do_pick
      [ -z "$h" ] || HTTP="$h"; [ -z "$g" ] || GRPC="$g"; [ -z "$a" ] || ADMIN="$a"
    fi
    lock; write_entry repo "" "$cf" "$INSTANCE" true; unlock
    LAUNCH_COMPOSE=(-p "$INSTANCE" -f "$cf"); LAUNCH_DIR="$cdir"
    docker compose "${LAUNCH_COMPOSE[@]}" up -d >&2 || fail_launch "docker compose up failed"
  else
    local attempt
    for attempt in 1 2 3; do
      reserve repo "" "$cf" "$INSTANCE" true
      if ! listening "$HTTP" && ! listening "$GRPC" && ! listening "$ADMIN"; then break; fi
      [ "$attempt" -lt 3 ] || { restore_entry; die 3 "ports kept getting taken"; }
    done
    mkdir -p "$DD" || die 64 "cannot create $DD"
    docker compose -f "$cf" config --format json | jq -r --arg h "$HTTP" --arg g "$GRPC" --arg a "$ADMIN" '
      "services:",
      (.services | to_entries[] | select((.value.ports // []) | map(select(.published != null and .published != "")) | length > 0)
        | "  \(.key):", "    ports: !override",
          ((.value.ports // [])[] | select(.published != null and .published != "")
            | (if .target == 8080 then $h elif .target == 9090 then $g elif .target == 9091 then $a else .published end) as $p
            | "      - \"\((.host_ip // "") | if . == "" then "" else . + ":" end)\($p):\(.target)/\(.protocol // "tcp")\""))' >"$ov"
    LAUNCH_COMPOSE=(-p "$INSTANCE" -f "$cf" -f "$ov"); LAUNCH_DIR="$cdir"
    docker compose "${LAUNCH_COMPOSE[@]}" up -d >&2 || fail_launch "docker compose up failed"
  fi
  wait_healthy "" || fail_launch "instance on port $HTTP did not become healthy"
  emit started
}

# exit 0 with a note unless every container of Compose project $1 comes from one of the dirs $2...
left_running() {
  local p="$1"; shift
  compose_from "$p" "$@" && return 0
  echo "Compose project $p has containers started from another directory; left running"
  exit 0
}

cmd_stop() {
  [ $# -eq 0 ] || usage
  local run dd http pid cf cp
  run="$(entry run)"; dd="$(entry dataDir)"; http="$(rec_port http)"
  [ -n "$dd" ] || exit 0
  DD="$dd"
  case "$run" in
    binary)
      [ -f "$DD/cyoda.pid" ] || exit 0
      pid="$(tr -dc '0-9' <"$DD/cyoda.pid")"
      [ -n "$pid" ] && [ -n "$http" ] || exit 0
      if lsof -nP -a -p "$pid" -iTCP:"$http" -sTCP:LISTEN >/dev/null 2>&1; then
        kill "$pid" 2>/dev/null
        for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
      fi
      rm -f "$DD/cyoda.pid" ;;
    docker)
      [ -f "$DD/compose.yaml" ] || exit 0
      need_docker
      left_running "$INSTANCE" "$DD"
      CYODA_HOST_HTTP_PORT="$http" CYODA_HOST_GRPC_PORT="$(rec_port grpc)" CYODA_HOST_ADMIN_PORT="$(rec_port admin)" \
        docker compose -p "$INSTANCE" -f "$DD/compose.yaml" down >&2 || die 5 "docker compose down failed" ;;
    repo)
      cf="$(entry compose)"
      cp="$(entry composeProject)"
      if [ "$(entry managed)" != true ] || [ -z "$cp" ]; then
        echo "the compose stack of this project was not started by the plugin; left running"
        exit 0
      fi
      need_docker
      left_running "$cp" ${cf:+"$(dirname "$cf")"} "$DD"
      if [ ! -f "$cf" ]; then
        docker compose -p "$cp" down >&2 || die 5 "docker compose down failed"
      elif [ -f "$DD/compose.override.yaml" ]; then
        docker compose -p "$cp" -f "$cf" -f "$DD/compose.override.yaml" down >&2 || die 5 "docker compose down failed"
      else
        docker compose -p "$cp" -f "$cf" down >&2 || die 5 "docker compose down failed"
      fi ;;
  esac
  exit 0
}

case "$CMD" in
  start) cmd_start "$@" ;;
  start-repo) cmd_start_repo "$@" ;;
  stop) cmd_stop "$@" ;;
  *) usage ;;
esac
