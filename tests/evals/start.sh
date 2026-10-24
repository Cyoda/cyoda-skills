#!/usr/bin/env bash
# start.sh <id> [mock|jwt] — throwaway in-memory cyoda-go for eval server <id>.
# Ports: 20000+id*100+{80 HTTP, 90 gRPC, 91 admin}. State: tests/evals/.state/s<id>/.
# jwt mode: RSA signing key in the state dir, bootstrap client evalclient/evalsecret.
set -euo pipefail
id="${1:?usage: start.sh <id> [mock|jwt]}"; mode="${2:-mock}"
case "$id" in *[!0-9]* | "") echo "id must be a number" >&2; exit 2 ;; esac
base=$((20000 + id * 100))
STATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state"
D="$STATE/s$id"; rm -rf "$D"; mkdir -p "$D/home"
args=(HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" CYODA_STORAGE_BACKEND=memory
  CYODA_HTTP_PORT=$((base + 80)) CYODA_GRPC_PORT=$((base + 90)) CYODA_ADMIN_PORT=$((base + 91)))
case "$mode" in
  jwt)
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$D/k.pem" 2>/dev/null
    args+=(CYODA_IAM_MODE=jwt CYODA_JWT_SIGNING_KEY_FILE="$D/k.pem"
      CYODA_BOOTSTRAP_CLIENT_ID=evalclient CYODA_BOOTSTRAP_CLIENT_SECRET=evalsecret) ;;
  mock) args+=(CYODA_IAM_MODE=mock) ;;
  *) echo "mode must be mock or jwt" >&2; exit 2 ;;
esac
# The pid file holds the subshell's pid, not cyoda's: stop.sh kills by port instead.
(cd "$D" && env "${args[@]}" nohup "${CYODA_BIN:-cyoda}" > "$D/server.log" 2>&1 & echo $! > "$D/pid")
for _ in $(seq 1 50); do
  if curl -sf "http://localhost:$((base + 80))/api/health" >/dev/null; then
    echo "eval server $id up on $((base + 80)) ($mode)"; exit 0
  fi
  perl -e 'select(undef,undef,undef,0.2)'
done
echo "eval server $id failed to start" >&2; tail -5 "$D/server.log" >&2; exit 1
