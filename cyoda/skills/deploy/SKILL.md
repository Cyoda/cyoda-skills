---
name: deploy
description: Use when a working local cyoda-go app is to be deployed to a self-hosted cyoda-go instance (Docker Compose, Helm on Kubernetes, Terraform; dev, staging or prod stages), or a seed script, verify script, compose file, Helm values or secrets checklist for one is needed.
allowed-tools: Bash(*cyoda-status.sh*) Bash(*cyoda-help.sh *) Bash(*cyoda-call.sh GET *) Bash(jq *) Bash(find *) Bash(ls *) Bash(mkdir *) Bash(cp *) Bash(chmod *) Bash(cmp *) Bash(cat *) Bash(mv *) Bash(grep *)
---

# Cyoda deploy (self-hosted cyoda-go)

Writes the files that deploy and seed a cyoda-go instance into the developer's project, then lists the commands their pipeline runs, in order.

**This skill writes files only.** It doesn't run `docker`, `docker compose`, `helm`, `kubectl`, `openssl`, `seed.sh` or `verify.sh` (check copied scripts with `bash -n`), and no file it writes holds a secret value.

**Scope: cyoda-go only.** The developer's own services and compute-node images aren't deployed here. The instance is made reachable for compute nodes (gRPC port, `CYODA_COMPUTE_GRPC_ENDPOINT`).

**Facts come from `cyoda help`.** Read sections with `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"`. In your reply, name the sections your facts come from. Templates are under `${CLAUDE_PLUGIN_ROOT}/skills/deploy/templates/`.

## Step 0 — Connection

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. Show every `WARN=` line.
- `STATUS=not_configured` or `unreachable`: "Deploy starts from a working app on a running cyoda-go; starting or linking it is covered by `cyoda:setup`." Stop.
- Note `VERSION`: the image tag must match it.

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh GET /model/` (help: `models --section ENDPOINTS`) and show each model's name, version and `currentState`. This skill makes no other API call.

## Step 1 — Project files

The seed loads the files `cyoda:build` keeps, never live exports: model import accepts only sample data, so a model export can't be re-imported.

1. Read `cyoda-manifest.json` at the project root. Check that every `sample`, `workflow` and `config` path it lists exists (paths are relative to the manifest's dir).
2. **No manifest:** find `{entity}-v{version}-{sample,workflow,config}.json` files (`build`'s naming) and write `cyoda-manifest.json` from them, saying so in one line: `{"manifestVersion":1,"entities":[{name, modelVersion, sample, workflow, config}, ...]}` (schema: `${CLAUDE_PLUGIN_ROOT}/skills/build/templates/cyoda-manifest.json`; `modelVersion` is an integer).
3. **Nothing found:** "Deploy seeds the new instance from the versioned model and workflow files that `cyoda:build` writes (it creates them, or exports the models already on the instance), and this project has none." Stop.
4. A manifest entity that isn't LOCKED on the local instance: continue, and say in one line that `seed.sh` registers it from the project files.

## Step 2 — Target

Ask which target:

| Target | Read | What happens |
|---|---|---|
| Docker Compose, **single-user** | `run --section "RUN MODES"` (Docker Compose), `run --section "PORT LAYOUT"` | `compose.single-user.yaml`: SQLite, **mock auth**, ports on `127.0.0.1`. Anyone who can reach the ports is admin: one developer, one machine |
| Docker Compose, **shared** | the above, plus `config auth --section OPTIONS` and `quickstart --section "PRODUCTION CHECKLIST"` | `compose.shared.yaml`: Postgres, JWT mode, signing key mounted `:ro` via `CYODA_JWT_SIGNING_KEY_FILE`, bootstrap M2M client |
| Helm on Kubernetes | `helm --section VALUES`, `helm --section "SECRETS PROVISIONING"`, `helm --section "INSTALL / UPGRADE / UNINSTALL"`, `config database --section OPTIONS` | `values.yaml` for chart `cyoda/cyoda` from `https://cyoda.github.io/cyoda-go`: the developer's Postgres, JWT mode, bootstrap M2M client, Gateway API or Ingress. Every credential is a Secret the developer creates first |
| Terraform | — | Point to `https://github.com/Cyoda/cyoda-go-terraform`: early and AWS-first; this skill doesn't guide it |

A team, CI or any host other than the developer's own machine needs **shared** or **Helm**, not single-user.

**Helm only**, ask:
- **Namespace** (default `cyoda`).
- **Postgres:** the chart runs none. Confirm a database the cluster can reach exists (managed service or operator). Its DSN goes only into Secret `cyoda-pg` (checklist row 4).
- **Routing**, one of:
  - **Gateway API** (chart default): the Gateway's name and namespace, plus the API host and the gRPC host. Its listeners must admit routes from `<NAMESPACE>`.
  - **Ingress:** the IngressClass name, the API host, the gRPC host and the TLS Secret in `<NAMESPACE>` that covers both (gRPC through an Ingress needs TLS).
  - **Neither** (e.g. kind, minikube): no route. The API is reached through `kubectl port-forward -n <NAMESPACE> svc/cyoda 18080:8080` (not local 8080: the developer's local cyoda-go holds it), and compute nodes must run in the cluster.
- Gateway or Ingress: `<API_URL>` is `https://<API_HOST>` and `<GRPC_ENDPOINT>` is `<GRPC_HOST>:443` (TLS at the edge). Neither: `http://localhost:18080` and `cyoda.<NAMESPACE>.svc:9090`.

## Step 3 — Stages and schema settings

Ask: "Which stage is this for, and is its schema strict?" The developer may name several stages. Each stage name is its `seed.sh --env <stage>`. Compose shared: ask for each stage's host the developer hasn't given.

For each strict stage, read `models --section LIFECYCLE` and `models --section ENDPOINTS` (changeLevel), then ask per entity, word for word:
> Does any processor write fields to `<entity>` that aren't in its sample? A strict schema rejects them.

- **No:** record `null` (strict).
- **Yes:** ask which changeLevel, from the values listed there, least permissive first. Record it.

Record the answer as `env.<stage>.changeLevel` in that entity's `-config.json`, keeping every other key:
```bash
jq --arg st '<stage>' --argjson cl '<null or "VALUE">' '.env = ((.env // {}) + {($st): ((.env[$st] // {}) + {changeLevel: $cl})})' <config> > <config>.tmp && mv <config>.tmp <config>
```
`seed.sh` applies `env.<stage>` when it's present and the base `changeLevel` otherwise. For a stage that isn't strict, remove any `env.<stage>.changeLevel`: `jq --arg st '<stage>' 'del(.env[$st].changeLevel)'`, written back the same way.

## Step 4 — Output dir

If `deploy/` exists use `deploy/cyoda/`; else if `ops/` exists use `ops/cyoda/`; else `deploy/cyoda/`. If a file to write already exists there and differs (`cmp`), keep it, write the generated one beside it as `<name>.new`, say so in one line, and never overwrite it.

## Step 5 — Write the artifacts

Copy from `${CLAUDE_PLUGIN_ROOT}/skills/deploy/templates/` into `<DIR>`:

| File | From | Purpose |
|---|---|---|
| `compose.yaml` (Compose) | `compose.single-user.yaml` or `compose.shared.yaml` | the instance. If `VERSION` from Step 0 isn't `0.8.4`, change the default in `${CYODA_VERSION:-0.8.4}` to it |
| `values.yaml` (Helm) | `values.yaml` | the chart values. The image follows the chart's appVersion, which Step 6 matches to `VERSION` |
| `seed.sh` | `seed.sh` | loads models and workflows in the canonical order; safe to re-run |
| `verify.sh` | `verify.sh` | checks health, readiness and that every manifest model is LOCKED |
| `secrets-checklist.md` | `secrets-checklist.md` | every secret to create and where it's read from |
| `.gitignore` (Compose shared only) | write `secrets/` and `.env`, one per line | keeps secrets out of git |

Fill `values.yaml` (Helm), keeping its comments:
- `<APP>`: the project name (the bootstrap client id becomes `<APP>-deployer`).
- Gateway: fill `<GATEWAY_NAME>`, `<GATEWAY_NAMESPACE>`, `<API_HOST>` and `<GRPC_HOST>`, and delete the `ingress:` block with its comment lines.
- Ingress: replace the `gateway:` block with `gateway:` / `  enabled: false`, set `ingress.enabled: true`, and fill `<INGRESS_CLASS>`, `<API_HOST>`, `<GRPC_HOST>` and `<TLS_SECRET>`.
- Neither: replace the `gateway:` block with `gateway:` / `  enabled: false`, and delete the `ingress:` block with its comment lines.
- Leave `replicas`, `autoscaling` and `migrate` at the chart defaults written there unless the developer asks.
- Check: `grep -n '<[A-Z_]*>' <DIR>/values.yaml` prints nothing.

Fill the checklist placeholders:
- `<MODE>`: single-user, shared or helm. Keep that mode's section and delete the others with their comment lines. In "Tokens for seed.sh, verify.sh and your app" and "Compute nodes", keep only the lines and table values for that mode.
- `<NAMESPACE>` (Helm): the namespace.
- `<DEPLOY_DIR>`: the output dir.
- `<APP>`: the project name.
- `<API_URL>`: `http://localhost:18080` for single-user. For shared, `http://<host>:18080` with the stage's host. For Helm, from Step 2.
- `<GRPC_ENDPOINT>`: Compose, the same host with port `19090`, as `host:19090`. For Helm, from Step 2.
- Several stages: in the Compute nodes table, write the `<GRPC_ENDPOINT>` and `<API_URL>` values once per stage, each prefixed with its stage (e.g. `uat: uat.shop.example.com:19090`).
- `<TOKEN_COMMAND>`: the absolute path of the project's token script (e.g. `get-token.sh`). Shared or Helm and none exists: copy `${CLAUDE_PLUGIN_ROOT}/skills/auth/templates/get-token.sh` to `scripts/get-token.sh` if the project has a `scripts/` dir, else to the project root, `chmod +x` it, and use that path.

Both compose files publish host ports 18080 (API), 19090 (gRPC) and 19091 (admin), not 8080/9090/9091: the developer's local cyoda-go holds those, so `up` would fail or health, seed and verify would hit the local instance (`CYODA_HOST_*_PORT` overrides them).

## Step 6 — Hand over

List what was written, one line per file (a `get-token.sh` copied in Step 5: its path, marked as new), then what the pipeline runs, per stage: the commands below in this order, with the real paths, namespace, hosts and `VERSION` filled in (from the project root). For several stages, write the commands out in full for each stage, each with that stage's `<API_URL>` and `--env <stage>`.

**Compose** (for single-user, skip 1 and leave out every `CYODA_TOKEN_COMMAND` and `CYODA_CLIENT_*`):

```bash
# 1. Secrets (shared): create every item in <DIR>/secrets-checklist.md, and export CYODA_BOOTSTRAP_CLIENT_ID
# 2. Start
docker compose -f <DIR>/compose.yaml up -d
# 3. Health: expect {"status":"UP"}
curl -fsS <API_URL>/api/health
# 4. Seed
CYODA_ENDPOINT=<API_URL> CYODA_TOKEN_COMMAND=<TOKEN_COMMAND> CYODA_CLIENT_ID=<id> CYODA_CLIENT_SECRET_CMD='<command that prints the secret>' \
  bash <DIR>/seed.sh --manifest cyoda-manifest.json --env <stage>
# 5. Verify (CYODA_ADMIN_URL works only on the host itself: the admin port is loopback)
CYODA_ENDPOINT=<API_URL> CYODA_ADMIN_URL=http://localhost:19091 CYODA_TOKEN_COMMAND=<TOKEN_COMMAND> CYODA_CLIENT_ID=<id> CYODA_CLIENT_SECRET_CMD='<command>' \
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
  bash <DIR>/seed.sh --manifest cyoda-manifest.json --env <stage>
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
- Seeding again after a workflow change re-imports the workflows. A sample or unique-key change on a LOCKED model needs a new model version (`cyoda:build`): the seed skips locked models.
- Compute nodes: `CYODA_COMPUTE_GRPC_ENDPOINT` and the token source are in the checklist (help: `config grpc --section OPTIONS`). Processors are only exercised once a compute node runs against the new instance.

## Known upstream issues

- The upstream `deploy/docker/compose.yaml` has a commented "production" block that sets `CYODA_REQUIRE_JWT=true` without `CYODA_IAM_MODE=jwt` and passes the PEM inline (cyoda-go#684 item M). Follow `run` and `config auth` instead, as `compose.shared.yaml` does.
- Workflow import is strict and an export isn't re-importable as is (cyoda-go#684 item I): `seed.sh` posts only `{importMode, workflows}`.
- `cyoda help helm` and `run` say the chart is unpublished and at 0.1.0, and install from `./deploy/helm/cyoda`. It's published at `https://cyoda.github.io/cyoda-go` (#684 item A): install `cyoda/cyoda` from there, at the chart whose appVersion is `VERSION`.
- Help's Helm minimal install sets no bootstrap client, which leaves no credential to seed with (#684 item D): `values.yaml` always sets `bootstrap.clientId`.
- An empty `gateway.parentRefs` doesn't fail the chart, it leaves the routes attached to nothing (#684 item G): `values.yaml` always sets the gateway parentRefs, or ingress, explicitly.
- `cyoda help helm` VALUES omits `migrate.postgres.existingSecret` / `existingSecretKey`, the migration Job's own DSN (#684 item H). `values.yaml` names them, empty (the Job uses the runtime DSN).

## Common mistakes

| Mistake | Instead |
|---|---|
| A strict stage without the processor-fields question | Step 3, recorded as `env.<stage>.changeLevel` |
| `/readyz` on the API port | `/api/health` on the API port; `/readyz` on the admin port (container 9091; `run --section "HEALTH PROBES"`) |
| Leaving HMAC, metrics or bootstrap Secrets to the chart | Pre-create all of them: chart-generated ones fail `helm template`, `--dry-run` and GitOps renders |
