---
name: deploy
description: Use when the developer types /cyoda:deploy to move a working local cyoda-go app to a self-hosted cyoda-go instance (Docker Compose, Helm on Kubernetes, Terraform), or needs a seed script, verify script, compose file or secrets checklist for one.
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-help.sh *) Bash(*cyoda-call.sh GET *) Bash(jq *) Bash(find *) Bash(ls *) Bash(mkdir *) Bash(cp *) Bash(cmp *) Bash(cat *) Bash(mv *) Bash(grep *)
disable-model-invocation: true
---

# Cyoda deploy (self-hosted cyoda-go)

Writes the files that deploy and seed a cyoda-go instance into the developer's project, then lists the commands to run, in order. The developer, or a devops person, runs them and scripts from them.

**This skill writes files only.** It never runs `docker`, `docker compose`, `helm`, `kubectl` or `openssl`, never creates secrets, and never runs `seed.sh` or `verify.sh`. To check copied scripts, use `bash -n <file>` (syntax only); never execute `seed.sh` or `verify.sh`, not even for usage. It writes no secret value into any file. If the developer asks you to run the commands after the hand-over, that's an ordinary request outside this skill.

**Scope: cyoda-go only.** The developer's own services and compute-node images aren't deployed here. The instance is made reachable for compute nodes (gRPC port, `CYODA_COMPUTE_GRPC_ENDPOINT`).

**Facts come from `cyoda help`.** Read sections with `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` and say which one you used. Templates are under `${CLAUDE_PLUGIN_ROOT}/skills/deploy/templates/`.

A Cloud or migration question: reply only "That's not covered by this plugin." Don't name or describe the product or offer alternatives for it.

## Step 0 — Connection

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. Show every `WARN=` line.
- `STATUS=not_configured` or `unreachable`: "Deploy starts from a working app on a running cyoda-go. Next, type `/cyoda:setup` to connect to it." Stop.
- Note `VERSION`: the image tag must match it.

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh GET /model/` (help: `models --section ENDPOINTS`) and show each model's name, version and `currentState`. This skill makes no other API call.

## Step 1 — Project files

The seed loads the files `/cyoda:build` keeps, never live exports: model import accepts only sample data, so a model export can't be re-imported.

1. Read `cyoda-manifest.json` at the project root. Check that every `sample`, `workflow` and `config` path it lists exists (paths are relative to the manifest's dir).
2. **No manifest:** use `build`'s scan for `{entity}-v{version}-{sample,workflow,config}.json`:
   ```bash
   find . -name '*-v*-sample.json' -not -path '*/node_modules/*' -not -path './.git/*'
   ```
   For each hit, find the matching `-workflow.json` and `-config.json` the same way. Show the list and ask: "Write `cyoda-manifest.json` from these?" On a yes, write `{"manifestVersion":1,"entities":[{name, modelVersion, sample, workflow, config}, ...]}` (schema: `${CLAUDE_PLUGIN_ROOT}/skills/build/templates/cyoda-manifest.json`; `modelVersion` is an integer).
3. **Nothing found:** "Deploy seeds the new instance from the versioned model and workflow files that `/cyoda:build` writes, and this project has none. Next, type `/cyoda:build`: it creates them, or exports the models already on your instance." Stop.
4. A manifest entity that isn't LOCKED on the local instance hasn't been registered and tested yet: name it and ask whether to continue.

## Step 2 — Target

Ask which target, one line each:

| Target | Read | What happens |
|---|---|---|
| Docker Compose, **single-user** | `run --section "RUN MODES"` (Docker Compose), `run --section "PORT LAYOUT"` | `compose.single-user.yaml`: SQLite, **mock auth**, ports on `127.0.0.1`. Anyone who can reach the ports is admin: one developer, one machine |
| Docker Compose, **shared** | the above, plus `config auth --section OPTIONS` and `quickstart --section "PRODUCTION CHECKLIST"` | `compose.shared.yaml`: Postgres, JWT mode, signing key mounted `:ro` via `CYODA_JWT_SIGNING_KEY_FILE`, bootstrap M2M client |
| Helm on Kubernetes | `helm --section VALUES`, `helm --section "SECRETS PROVISIONING"`, `helm --section "INSTALL / UPGRADE / UNINSTALL"`, `config database --section OPTIONS` | `values.yaml` for chart `cyoda/cyoda` from `https://cyoda.github.io/cyoda-go`: the developer's Postgres, JWT mode, bootstrap M2M client, Gateway API or Ingress. Every credential is a Secret the developer creates first |
| Terraform | — | Point to `https://github.com/Cyoda/cyoda-go-terraform`: early and AWS-first; this skill doesn't guide it |

A team, CI or any host other than the developer's own machine needs **shared** or **Helm**. Don't offer single-user for those.

**Helm only**, ask and record (the agent can't see the cluster, so these are the developer's answers):
- **Namespace** (default `cyoda`).
- **Postgres:** the chart runs none. Confirm a database the cluster can reach exists (managed service or operator). Its DSN goes only into Secret `cyoda-pg` (checklist row 4), never into chat or a file.
- **Routing**, one of:
  - **Gateway API** (chart default): the Gateway's name and namespace (`kubectl get gateways -A` lists them), plus the API host and the gRPC host. Its listeners must admit routes from `<NAMESPACE>`.
  - **Ingress:** the IngressClass name (`kubectl get ingressclass`), the API host, the gRPC host and the TLS Secret in `<NAMESPACE>` that covers both (gRPC through an Ingress needs TLS).
  - **Neither** (e.g. kind, minikube): no route. The API is reached through `kubectl port-forward -n <NAMESPACE> svc/cyoda 18080:8080` (not local 8080: the developer's local cyoda-go holds it), and compute nodes must run in the cluster.
- Gateway or Ingress: `<API_URL>` is `https://<API_HOST>` and `<GRPC_ENDPOINT>` is `<GRPC_HOST>:443` (TLS at the edge). Neither: `http://localhost:18080` and `cyoda.<NAMESPACE>.svc:9090`.

## Step 3 — Environment and schema settings

Ask: "Is this instance **production**?" The answer is the env name for `seed.sh --env` and the profile (`production` or `development`).

For **production**, ask per entity: "Does any processor write fields to `<entity>` that aren't in its sample? A strict schema rejects them." Read `models --section LIFECYCLE` and `models --section ENDPOINTS` (changeLevel) first.
- **No:** record `null` (strict).
- **Yes:** ask which changeLevel, from the values listed there, least permissive first. Record it.

Record the answer as `env.production.changeLevel` in that entity's `-config.json`, keeping every other key, and show the result:
```bash
jq --argjson cl '<null or "VALUE">' '.env = ((.env // {}) + {production: ((.env.production // {}) + {changeLevel: $cl})})' <config> > <config>.tmp && mv <config>.tmp <config>
```
`seed.sh` applies the env override when it's present and the base `changeLevel` otherwise. A permissive dev schema never reaches production without this question.

## Step 4 — Output dir

Scan first: if `deploy/` exists use `deploy/cyoda/`; else if `ops/` exists use `ops/cyoda/`; else `deploy/cyoda/`. Say which and why, and let the developer change it. If a file to write already exists there and differs (`cmp`), show the difference and ask before replacing it.

## Step 5 — Write the artifacts

Copy from `${CLAUDE_PLUGIN_ROOT}/skills/deploy/templates/` into `<DIR>`:

| File | From | Purpose |
|---|---|---|
| `compose.yaml` (Compose) | `compose.single-user.yaml` or `compose.shared.yaml` | the instance. If `VERSION` from Step 0 isn't `0.8.4`, change the default in `${CYODA_VERSION:-0.8.4}` to it |
| `values.yaml` (Helm) | `values.yaml` | the chart values. The image follows the chart's appVersion, which Step 6 matches to `VERSION` |
| `seed.sh` | `seed.sh` | loads models and workflows in the canonical order; safe to re-run (it prints usage when the developer runs it without arguments) |
| `verify.sh` | `verify.sh` | checks health, readiness and that every manifest model is LOCKED |
| `secrets-checklist.md` | `secrets-checklist.md` | every secret to create and where it's read from |
| `.gitignore` (Compose shared only) | write `secrets/` and `.env`, one per line | keeps secrets out of git |

Fill `values.yaml` (Helm), keeping its comments:
- `<APP>`: the project name (the bootstrap client id becomes `<APP>-deployer`).
- Gateway: fill `<GATEWAY_NAME>`, `<GATEWAY_NAMESPACE>`, `<API_HOST>` and `<GRPC_HOST>`, and delete the `ingress:` block with its comment lines.
- Ingress: replace the `gateway:` block with `gateway:` / `  enabled: false`, set `ingress.enabled: true`, and fill `<INGRESS_CLASS>`, `<API_HOST>`, `<GRPC_HOST>` and `<TLS_SECRET>`.
- Neither: replace the `gateway:` block with `gateway:` / `  enabled: false`, and delete the `ingress:` block with its comment lines.
- Leave `replicas`, `autoscaling` and `migrate` at the chart defaults written there unless the developer asks: the migration Job stays on, and the comments say how to scale.
- Check: `grep -n '<[A-Z_]*>' <DIR>/values.yaml` prints nothing.

Fill the checklist placeholders:
- `<MODE>`: single-user, shared or helm. Keep that mode's section and delete the others with their comment lines.
- `<NAMESPACE>` (Helm): the namespace.
- `<DEPLOY_DIR>`: the output dir.
- `<APP>`: the project name.
- `<API_URL>`: `http://localhost:8080` for single-user. For shared, ask for the host the team will use. For Helm, from Step 2.
- `<GRPC_ENDPOINT>`: the same host with port `9090`, as `host:9090`. For Helm, from Step 2.
- `<TOKEN_COMMAND>`: the project's token script if one exists (e.g. `get-token.sh`), else `<path to your token script>`.

When the project already has a token script, put its absolute path in the checklist and the profile's `tokenCommand`, and delete the `/cyoda:auth` line (the "Type `/cyoda:auth` in Claude Code…" sentence) from the generated `secrets-checklist.md`. Keep that line only when there is no token script.

Don't create `secrets/` or any file in it, and don't put a value for a secret anywhere.

## Step 6 — Hand over

List what was written, one line per file, then the commands in this order, with the real paths, namespace, hosts and `VERSION` filled in (from the project root).

**Compose** (for single-user, skip 1 and leave out every `CYODA_TOKEN_COMMAND` and `CYODA_CLIENT_*`):

```bash
# 1. Secrets (shared): create every item in <DIR>/secrets-checklist.md, and export CYODA_BOOTSTRAP_CLIENT_ID
# 2. Start
docker compose -f <DIR>/compose.yaml up -d
# 3. Health: expect {"status":"UP"}
curl -fsS <API_URL>/api/health
# 4. Seed
CYODA_ENDPOINT=<API_URL> CYODA_TOKEN_COMMAND=<TOKEN_COMMAND> CYODA_CLIENT_ID=<id> CYODA_CLIENT_SECRET_CMD='<command that prints the secret>' \
  bash <DIR>/seed.sh --manifest cyoda-manifest.json --env <env>
# 5. Verify (CYODA_ADMIN_URL works only on the host itself: the admin port is loopback)
CYODA_ENDPOINT=<API_URL> CYODA_ADMIN_URL=http://localhost:9091 CYODA_TOKEN_COMMAND=<TOKEN_COMMAND> CYODA_CLIENT_ID=<id> CYODA_CLIENT_SECRET_CMD='<command>' \
  bash <DIR>/verify.sh --manifest cyoda-manifest.json
```

**Helm** (`<SECRET_CMD>` is `kubectl get secret cyoda-bootstrap -n <NAMESPACE> -o jsonpath={.data.secret} | base64 -d`):

```bash
# 1. Namespace and secrets: kubectl create namespace <NAMESPACE>, then every item in <DIR>/secrets-checklist.md
# 2. Chart: the release whose appVersion is <VERSION>. Expect a chart version; if it prints nothing, stop: no chart for <VERSION> is published
helm repo add cyoda https://cyoda.github.io/cyoda-go
helm repo update cyoda
CHART_VERSION="$(helm search repo cyoda/cyoda --versions -o json | jq -r --arg app <VERSION> '[.[] | select(.app_version == $app)][0].version // empty')"; echo "$CHART_VERSION"
# 3. Install: the migration Job runs first (pre-install hook), then the StatefulSet
helm install cyoda cyoda/cyoda --version "$CHART_VERSION" -f <DIR>/values.yaml -n <NAMESPACE>
kubectl rollout status statefulset/cyoda -n <NAMESPACE>
# 4. Health through the route: expect {"status":"UP"}
#    Neither: forward the API to local 18080 first, and wait until it answers:
#    kubectl port-forward -n <NAMESPACE> svc/cyoda 18080:8080 & PF_API=$!
#    for i in $(seq 1 30); do curl -fsS -o /dev/null http://localhost:18080/api/health && break; sleep 1; done
curl -fsS <API_URL>/api/health
# 5. Seed
CYODA_ENDPOINT=<API_URL> CYODA_TOKEN_COMMAND=<TOKEN_COMMAND> CYODA_CLIENT_ID=<APP>-deployer CYODA_CLIENT_SECRET_CMD='<SECRET_CMD>' \
  bash <DIR>/seed.sh --manifest cyoda-manifest.json --env <env>
# 6. Verify: the admin port 9091 is reachable only through a port-forward (the NetworkPolicy admits the monitoring namespace only).
#    Local 19091, not 9091: the local cyoda-go's admin port would answer instead of the cluster's
kubectl port-forward -n <NAMESPACE> svc/cyoda 19091:9091 & PF_ADMIN=$!
for i in $(seq 1 30); do curl -fsS -o /dev/null http://localhost:19091/livez && break; sleep 1; done
CYODA_ENDPOINT=<API_URL> CYODA_ADMIN_URL=http://localhost:19091 CYODA_TOKEN_COMMAND=<TOKEN_COMMAND> CYODA_CLIENT_ID=<APP>-deployer CYODA_CLIENT_SECRET_CMD='<SECRET_CMD>' \
  bash <DIR>/verify.sh --manifest cyoda-manifest.json
# 7. Stop the port-forwards
kill "$PF_ADMIN" ${PF_API:+"$PF_API"}
```

Upgrades: `helm upgrade cyoda cyoda/cyoda --version <new chart> -f <DIR>/values.yaml -n <NAMESPACE>` reruns the migration Job first (help: `helm --section "INSTALL / UPGRADE / UNINSTALL"`).

Then, briefly:
- seed and verify are plain bash + curl + jq, so a pipeline can call them as they are. Seeding again after a workflow change re-imports the workflows. A sample or unique-key change on a LOCKED model needs a new model version from `/cyoda:build`: the seed skips locked models.
- Compute nodes: `CYODA_COMPUTE_GRPC_ENDPOINT` and the token source are in the checklist (help: `config grpc --section OPTIONS`). Processors are only exercised once a compute node runs against the new instance.

## Step 7 — Profile (optional)

Ask: "Add a profile for the new instance, so `status`, `build` and `debug` can target it later?" On a yes, ask for a name (`default` is reserved for local) and write `endpoint` (`<API_URL>`, no `/api`), `env` and, for shared or Helm with a token script, `tokenCommand`. Never write a token or secret. Don't make it active: it doesn't answer until the instance is up (Compose step 2, Helm step 3).

```bash
CONFIG="${CYODA_PLUGIN_CONFIG:-$HOME/.config/cyoda/cyoda-plugin-config.json}"
mkdir -p "$(dirname "$CONFIG")"
[ -f "$CONFIG" ] || echo '{"active":"default","profiles":{}}' > "$CONFIG"
jq --arg p "<NAME>" --arg ep "<API_URL>" --arg env "<env>" --arg tc "<TOKEN_COMMAND or empty>" \
  '.profiles[$p] = ((.profiles[$p] // {}) + {endpoint: $ep, env: $env} + (if $tc == "" then {} else {tokenCommand: $tc} end))' \
  "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
```

Close with one hand-off and its reason:
- Shared or Helm without a token script: "Once it's up, next, type `/cyoda:auth` to create the token script for this instance's bootstrap client."
- Profile written: "Once `/api/health` answers, next, type `/cyoda:setup` to switch to profile `<NAME>`."
- No profile: "`verify.sh` is the smoke check for the new instance. To point the other skills at it later, next, type `/cyoda:setup` and connect to `<API_URL>`."

## Known upstream issues

- The upstream `deploy/docker/compose.yaml` has a commented "production" block that sets `CYODA_REQUIRE_JWT=true` without `CYODA_IAM_MODE=jwt` and passes the PEM inline. Follow `run` and `config auth` instead, as `compose.shared.yaml` does.
- Workflow import is strict and an export isn't re-importable as is (cyoda-go#684 item I): `seed.sh` posts only `{importMode, workflows}`.
- `cyoda help helm` and `run` say the chart is unpublished and at 0.1.0, and install from `./deploy/helm/cyoda`. It's published at `https://cyoda.github.io/cyoda-go` (#684 item A): install `cyoda/cyoda` from there, at the chart whose appVersion is `VERSION`.
- Help's Helm minimal install sets no bootstrap client, which leaves no credential to seed with (#684 item D): `values.yaml` always sets `bootstrap.clientId`.
- An empty `gateway.parentRefs` doesn't fail the chart, it leaves the routes attached to nothing (#684 item G): `values.yaml` always sets the gateway parentRefs, or ingress, explicitly.
- `cyoda help helm` VALUES omits `migrate.postgres.existingSecret` / `existingSecretKey`, the migration Job's own DSN (#684 item H). `values.yaml` names them, empty (the Job uses the runtime DSN).

## Common mistakes

| Mistake | Instead |
|---|---|
| Running `docker compose up`, `openssl` or `seed.sh` "to save a step" | Write the files; list the commands. The developer runs them |
| Single-user compose for a team or a shared host | Shared: JWT mode and a bootstrap client |
| A secret value in compose, `.env`, `values.yaml`, the checklist or the profile | Compose: files under `secrets/` mounted `:ro`. Helm: Kubernetes Secrets. The developer creates them |
| `CYODA_REQUIRE_JWT=true` alone, or `CYODA_JWT_SIGNING_KEY` inline | `CYODA_IAM_MODE=jwt` + `CYODA_JWT_SIGNING_KEY_FILE` |
| Seeding from live exports | The manifest's versioned files |
| Production without the processor-fields question | Step 3, recorded as `env.production.changeLevel` |
| `/readyz` on the API port | `/api/health` on 8080; `/readyz` on the admin port 9091 (`run --section "HEALTH PROBES"`) |
| Making the new profile active before the instance runs | Write it inactive; switch with `/cyoda:setup` |
| `helm install ./deploy/helm/cyoda`, or a chart version guessed from help | `cyoda/cyoda` from the published repo, at the chart whose appVersion is `VERSION` |
| Leaving HMAC, metrics or bootstrap Secrets to the chart | Pre-create all of them: chart-generated ones fail `helm template`, `--dry-run` and GitOps renders |
| `helm install --create-namespace` | `kubectl create namespace` first: the chart can't render into a missing namespace |
| `/readyz` through the Gateway or Ingress | Admin port 9091 through `kubectl port-forward` |
| Port-forwarding to local 8080 or 9091 | Local 18080 and 19091: the developer's local cyoda-go holds 8080 and 9091, and seed or verify would silently hit it |
