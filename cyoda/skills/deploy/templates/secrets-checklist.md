# cyoda-go secrets checklist — <MODE>

Deployment files: `<DEPLOY_DIR>/`. Create everything below **before** the first
`docker compose up` or `helm install`. This file names each secret and where cyoda-go
reads it. It holds no secret values: keep it that way.

Facts: `cyoda help config auth` (OPTIONS), `cyoda help quickstart` (PRODUCTION CHECKLIST,
incl. "Generating secrets"), `cyoda help run` (RUN MODES: Docker Compose), `cyoda help helm`
(SECRETS PROVISIONING, GENERATING SECRETS).

<!-- single-user: keep this section, delete the shared and helm sections -->
## Single-user (compose.single-user.yaml)

- [ ] Nothing to create: mock auth, SQLite in the `cyoda-data` volume.
- [ ] Ports stay bound to `127.0.0.1`. Anyone who can reach them is admin.

<!-- shared: keep this section, delete the single-user and helm sections -->
## Shared (compose.shared.yaml)

`<DEPLOY_DIR>/secrets/` and `<DEPLOY_DIR>/.env` are git-ignored.
The container runs as UID/GID 65532. On a Linux host, each file under `secrets/` must be
readable by that user (for example `chown 65532:65532` and `chmod 0400`).

| # | Secret | Create it as | Read by | How |
|---|---|---|---|---|
| 1 | JWT signing key (RSA, PEM, ≥ 2048 bits) | `secrets/signing.pem` | `CYODA_JWT_SIGNING_KEY_FILE` (mounted `:ro`) | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out secrets/signing.pem` |
| 2 | Bootstrap M2M client id | `CYODA_BOOTSTRAP_CLIENT_ID` in your shell or `<DEPLOY_DIR>/.env` | `CYODA_BOOTSTRAP_CLIENT_ID` | any name, e.g. `<APP>-deployer` (not secret, but keep it with the secret) |
| 3 | Bootstrap M2M client secret | `secrets/bootstrap-client-secret` (one line) | `CYODA_BOOTSTRAP_CLIENT_SECRET_FILE` (mounted `:ro`) | a random value, e.g. `openssl rand -hex 32` |
| 4 | Postgres password | `secrets/postgres-password` | `POSTGRES_PASSWORD_FILE` (postgres service) | a random value, e.g. `openssl rand -hex 32` (hex keeps the URL below valid) |
| 5 | Postgres URL | `secrets/postgres-url` | `CYODA_POSTGRES_URL_FILE` | `postgres://cyoda:<password from 4>@postgres:5432/cyoda?sslmode=disable` |

- [ ] 1–5 created; `git status` shows none of them.
- [ ] Store the client id and secret (2, 3) where the people and pipelines that seed and
      call this instance can read them: a password manager, keychain or CI secret store.
- [ ] Rotation: the signing key and bootstrap secret are read at startup; restart the
      `cyoda` service after replacing them. See `cyoda help auth clients` for other clients.
- [ ] Cluster mode (more than one node) is out of scope for this file. It needs an HMAC
      secret too: `cyoda help config auth`, "HMAC secret".

<!-- helm: keep this section, delete the single-user and shared sections -->
## Helm (values.yaml, namespace `<NAMESPACE>`)

Every credential is a Kubernetes Secret in `<NAMESPACE>`, created before `helm install`
and named in `values.yaml`. The commands pipe each value straight into the cluster: no
secret file is written, in this dir or anywhere else.

```bash
kubectl create namespace <NAMESPACE>
```

Create the namespace first: the chart fails to render into a namespace that doesn't
exist yet (`cyoda help helm`, SECRETS PROVISIONING).

| # | Secret | Kubernetes Secret (key) | Read by | How |
|---|---|---|---|---|
| 1 | JWT signing key (RSA, PEM, ≥ 2048 bits) | `cyoda-jwt` (`signing-key.pem`) | `jwt.existingSecret` → `CYODA_JWT_SIGNING_KEY_FILE` | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \| kubectl create secret generic cyoda-jwt -n <NAMESPACE> --from-file=signing-key.pem=/dev/stdin` |
| 2 | Bootstrap M2M client id | none: `bootstrap.clientId: <APP>-deployer` in `values.yaml` | `CYODA_BOOTSTRAP_CLIENT_ID` (ConfigMap) | already set; not secret |
| 3 | Bootstrap M2M client secret | `cyoda-bootstrap` (`secret`) | `bootstrap.clientSecret.existingSecret` → `CYODA_BOOTSTRAP_CLIENT_SECRET_FILE` | `kubectl create secret generic cyoda-bootstrap -n <NAMESPACE> --from-literal=secret="$(openssl rand -hex 32)"` |
| 4 | Postgres DSN (your database; the chart runs none) | `cyoda-pg` (`dsn`) | `postgres.existingSecret` → `CYODA_POSTGRES_URL_FILE` (pods and migration Job) | `read -rs PG_DSN && printf '%s' "$PG_DSN" \| kubectl create secret generic cyoda-pg -n <NAMESPACE> --from-file=dsn=/dev/stdin && unset PG_DSN`, typing `postgres://user:pass@host:5432/db?sslmode=require` |
| 5 | HMAC secret (cluster mode is always on) | `cyoda-hmac` (`secret`) | `cluster.hmacSecret.existingSecret` → `CYODA_HMAC_SECRET_FILE` | `kubectl create secret generic cyoda-hmac -n <NAMESPACE> --from-literal=secret="$(openssl rand -hex 32)"` |
| 6 | Metrics bearer token (admin port 9091) | `cyoda-metrics-bearer` (`bearer`) | `monitoring.metricsBearer.existingSecret` → `CYODA_METRICS_BEARER_FILE` | `kubectl create secret generic cyoda-metrics-bearer -n <NAMESPACE> --from-literal=bearer="$(openssl rand -hex 24)"` |

- [ ] 1–6 created: `kubectl get secret -n <NAMESPACE>` lists `cyoda-jwt`, `cyoda-bootstrap`,
      `cyoda-pg`, `cyoda-hmac` and `cyoda-metrics-bearer`.
- [ ] The people and pipelines that seed and call this instance can read the bootstrap
      secret (3): with `kubectl get secret cyoda-bootstrap -n <NAMESPACE> -o jsonpath={.data.secret} | base64 -d`,
      or from a password manager or CI secret store you copy it into.
- [ ] Optional, two database roles: a second DSN Secret for the migration Job (the owner/DDL
      role), set as `migrate.postgres.existingSecret` in `values.yaml`. That chart value is
      missing from `cyoda help helm` VALUES (cyoda-go#684 item H).
- [ ] Rotation: secrets are read at startup; after replacing one, run
      `kubectl rollout restart statefulset/cyoda -n <NAMESPACE>`. See `cyoda help auth clients`
      for other clients.

## Tokens for seed.sh, verify.sh and your app

`seed.sh` and `verify.sh` run `CYODA_TOKEN_COMMAND` (with `CYODA_ENDPOINT` set) to get a
JWT, and send no auth header when it's unset.

- Single-user: leave `CYODA_TOKEN_COMMAND` unset.
- Shared and Helm: `CYODA_TOKEN_COMMAND=<TOKEN_COMMAND>`, with `CYODA_CLIENT_ID` and
  `CYODA_CLIENT_SECRET` (or `CYODA_CLIENT_SECRET_CMD`) set to the bootstrap client from
  2 and 3. Type `/cyoda:auth` in Claude Code to create the token script if you don't have one.

## Compute nodes

Compute nodes connect to the gRPC port (9090; on Helm, the gRPC route or Ingress host), not
the REST port. Give each node:

| Variable | Value | Notes |
|---|---|---|
| `CYODA_COMPUTE_GRPC_ENDPOINT` | `<GRPC_ENDPOINT>` | host:port the node can reach |
| `CYODA_COMPUTE_TOKEN` | single-user: none needed (mock auth); shared and Helm: a JWT from the token command above | tokens expire (`CYODA_JWT_EXPIRY_SECONDS`, default 1 h): fetch a fresh one on reconnect |
| `CYODA_COMPUTE_HTTP_BASE` | `<API_URL>` | optional, for REST callbacks |

Facts: `cyoda help config grpc`, `cyoda help grpc`.
