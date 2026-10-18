#!/usr/bin/env bash
# Throwaway in-memory cyoda-go server lifecycle for smoke tests.
# start_server [KEY=VALUE ...]  extra env pairs override the defaults.
# stop_server                   idempotent; restores HOME/XDG_CONFIG_HOME.

SMOKE_HTTP_PORT=18080
SMOKE_GRPC_PORT=19090
SMOKE_ADMIN_PORT=19091
BASE="http://localhost:${SMOKE_HTTP_PORT}/api"
SMOKE_PID=""
SMOKE_TMP=""

_port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }

start_server() {
  local p
  for p in "$SMOKE_HTTP_PORT" "$SMOKE_GRPC_PORT" "$SMOKE_ADMIN_PORT"; do
    if _port_busy "$p"; then
      echo "start_server: port $p is already in use; refusing to start (not killing unknown processes)" >&2
      return 1
    fi
  done

  _SMOKE_REAL_HOME="$HOME"
  _SMOKE_REAL_XDG="${XDG_CONFIG_HOME-}"
  _SMOKE_HAD_XDG="${XDG_CONFIG_HOME+set}"
  SMOKE_TMP="$(mktemp -d)"
  mkdir -p "$SMOKE_TMP/home/.config"
  HOME="$SMOKE_TMP/home"; export HOME
  XDG_CONFIG_HOME="$SMOKE_TMP/home/.config"; export XDG_CONFIG_HOME

  env CYODA_STORAGE_BACKEND=memory CYODA_IAM_MODE=mock \
      CYODA_HTTP_PORT="$SMOKE_HTTP_PORT" CYODA_GRPC_PORT="$SMOKE_GRPC_PORT" \
      CYODA_ADMIN_PORT="$SMOKE_ADMIN_PORT" "$@" \
      cyoda >"$SMOKE_TMP/server.log" 2>&1 &
  SMOKE_PID=$!

  local _
  for _ in $(seq 1 30); do
    if ! kill -0 "$SMOKE_PID" 2>/dev/null; then break; fi
    if [ "$(curl -s --max-time 1 "$BASE/health" 2>/dev/null)" = '{"status":"UP"}' ]; then
      return 0
    fi
    sleep 0.5
  done
  echo "start_server: server not healthy within 15s; last 20 log lines:" >&2
  tail -n 20 "$SMOKE_TMP/server.log" >&2
  return 1
}

stop_server() {
  if [ -n "$SMOKE_PID" ]; then
    kill "$SMOKE_PID" 2>/dev/null
    local _
    for _ in $(seq 1 20); do
      kill -0 "$SMOKE_PID" 2>/dev/null || break
      sleep 0.25
    done
    kill -9 "$SMOKE_PID" 2>/dev/null
    wait "$SMOKE_PID" 2>/dev/null
    SMOKE_PID=""
  fi
  if [ -n "$SMOKE_TMP" ]; then
    rm -rf "$SMOKE_TMP"
    SMOKE_TMP=""
    HOME="$_SMOKE_REAL_HOME"; export HOME
    if [ -n "$_SMOKE_HAD_XDG" ]; then XDG_CONFIG_HOME="$_SMOKE_REAL_XDG"; export XDG_CONFIG_HOME; else unset XDG_CONFIG_HOME; fi
  fi
  return 0
}
