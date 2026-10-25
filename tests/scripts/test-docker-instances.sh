#!/usr/bin/env bash
# cyoda-docker-instances.sh against a docker shim: lists running cyoda-go
# containers (image ghcr.io/cyoda/cyoda, any tag) with the host port published
# for container port 8080 and the compose project. Docker is only read.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
S="$ROOT/cyoda/scripts"
# shellcheck source=../lib/assert.sh
source "$ROOT/tests/lib/assert.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/shim" "$T/nodocker"
cat >"$T/inspect.json" <<'J'
[
 {"Id":"aaa111","Name":"/shop-cyoda-1","Config":{"Image":"ghcr.io/cyoda/cyoda:0.8.4","Labels":{"com.docker.compose.project":"shop"}},
  "NetworkSettings":{"Ports":{"8080/tcp":[{"HostIp":"0.0.0.0","HostPort":"8082"},{"HostIp":"::","HostPort":"8082"}],"9090/tcp":[{"HostIp":"0.0.0.0","HostPort":"9092"}]}}},
 {"Id":"bbb222","Name":"/billing-cyoda-1","Config":{"Image":"ghcr.io/cyoda/cyoda","Labels":{"com.docker.compose.project":"billing"}},
  "NetworkSettings":{"Ports":{"8080/tcp":[{"HostIp":"127.0.0.1","HostPort":"8080"}]}}},
 {"Id":"ccc333","Name":"/pg","Config":{"Image":"postgres:16","Labels":{"com.docker.compose.project":"shop"}},
  "NetworkSettings":{"Ports":{"5432/tcp":[{"HostIp":"0.0.0.0","HostPort":"5432"}]}}},
 {"Id":"ddd444","Name":"/lonely","Config":{"Image":"ghcr.io/cyoda/cyoda:latest","Labels":{}},
  "NetworkSettings":{"Ports":{"8080/tcp":null}}},
 {"Id":"eee555","Name":"/lookalike","Config":{"Image":"ghcr.io/cyoda/cyoda-docs:1","Labels":{}},
  "NetworkSettings":{"Ports":{"8080/tcp":[{"HostIp":"0.0.0.0","HostPort":"8090"}]}}}
]
J
cat >"$T/shim/docker" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$T/docker-calls"
case "\$1" in
  ps) [ -n "\${SHIM_PS_FAIL:-}" ] && { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
      [ -n "\${SHIM_EMPTY:-}" ] && exit 0
      printf 'aaa111\nbbb222\nccc333\nddd444\neee555\n' ;;
  inspect) cat "$T/inspect.json" ;;
  *) echo "unexpected docker \$1" >&2; exit 9 ;;
esac
SH
chmod +x "$T/shim/docker"
for t in bash jq awk cat printf sed tr dirname; do
  p="$(command -v "$t")" && ln -sf "$p" "$T/nodocker/$t"
done

test_docker_lists_cyoda_containers() {
  local out rc
  rm -f "$T/docker-calls"
  out="$(PATH="$T/shim:$PATH" bash "$S/cyoda-docker-instances.sh")"; rc=$?
  assert_status 0 "$rc" "exit 0"
  assert_eq "$out" "CONTAINER=shop-cyoda-1 COMPOSE_PROJECT=shop ENDPOINT=http://localhost:8082 IMAGE=ghcr.io/cyoda/cyoda:0.8.4
CONTAINER=billing-cyoda-1 COMPOSE_PROJECT=billing ENDPOINT=http://localhost:8080 IMAGE=ghcr.io/cyoda/cyoda
CONTAINER=lonely COMPOSE_PROJECT=- ENDPOINT=none IMAGE=ghcr.io/cyoda/cyoda:latest" "cyoda-go containers only, with host REST port and compose project"
  assert_eq "$(cut -d' ' -f1 "$T/docker-calls" | sort -u | tr '\n' ' ')" "inspect ps " "only docker ps and docker inspect are run"
  assert_contains "$(head -n1 "$T/docker-calls")" "ps --format" "docker ps --format"
}

test_docker_no_containers() {
  local out rc
  out="$(SHIM_EMPTY=1 PATH="$T/shim:$PATH" bash "$S/cyoda-docker-instances.sh")"; rc=$?
  assert_status 0 "$rc" "no containers: exit 0"
  assert_eq "$out" "" "no containers: no output"
}

test_docker_daemon_down() {
  local err rc
  err="$(SHIM_PS_FAIL=1 PATH="$T/shim:$PATH" bash "$S/cyoda-docker-instances.sh" 2>&1 >/dev/null)"; rc=$?
  assert_status 4 "$rc" "daemon down: exit 4"
  assert_contains "$err" "docker ps failed" "daemon down message"
}

test_docker_not_installed() {
  local err rc
  err="$(PATH="$T/nodocker" "$T/nodocker/bash" "$S/cyoda-docker-instances.sh" 2>&1 >/dev/null)"; rc=$?
  assert_status 3 "$rc" "no docker: exit 3"
  assert_contains "$err" "docker is not on PATH" "no docker message"
}

test_docker_lists_cyoda_containers
test_docker_no_containers
test_docker_daemon_down
test_docker_not_installed
report
