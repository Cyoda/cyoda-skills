# cyoda-go secrets checklist — <MODE>

Deployment files: `<DEPLOY_DIR>/`. Create everything below **before** the instance
first starts. This file names each secret and where cyoda-go
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

`<DEPLOY_DIR>/secrets/` and `<DEPLOY_DIR>/.env` are git-ignored. Run the commands below
from the project root, in one shell, after `umask 077 && mkdir -p <DEPLOY_DIR>/secrets`, so
every file lands in the git-ignored dir and only you can read it.
The container runs as UID/GID 65532. On a Linux host, each file under `secrets/` must be
readable by that user (for example `chown 65532:65532` and `chmod 0400`).

| # | Secret | Create it as | Read by | How |
|---|---|---|---|---|
| 1 | JWT signing key (RSA, PEM, ≥ 2048 bits) | `<DEPLOY_DIR>/secrets/signing.pem` | `CYODA_JWT_SIGNING_KEY_FILE` (mounted `:ro`) | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out <DEPLOY_DIR>/secrets/signing.pem` |
| 2 | Postgres password | `<DEPLOY_DIR>/secrets/postgres-password` | `POSTGRES_PASSWORD_FILE` (postgres service) | a random value: `openssl rand -hex 32 > <DEPLOY_DIR>/secrets/postgres-password` (hex keeps the URL below valid) |
| 3 | Postgres URL | `<DEPLOY_DIR>/secrets/postgres-url` | `CYODA_POSTGRES_URL_FILE` | `postgres://cyoda:<password from 2>@postgres:5432/cyoda?sslmode=disable`: `printf 'postgres://cyoda:%s@postgres:5432/cyoda?sslmode=disable\n' "$(cat <DEPLOY_DIR>/secrets/postgres-password)" > <DEPLOY_DIR>/secrets/postgres-url` |

- [ ] 1–3 created; `git status` shows none of them.
- [ ] The signing key (1) is the root credential: whoever holds it can sign any token
      (`cyoda help cli token`). Keep a copy only where the operator's secrets live.
- [ ] Cluster mode (more than one node) is out of scope for this file. It needs an HMAC
      secret too: `cyoda help config auth`, "HMAC secret".

<!-- helm: keep this section, delete the single-user and shared sections -->
## Helm (values.yaml, namespace `<NAMESPACE>`)

Every credential is a Kubernetes Secret in `<NAMESPACE>`, created before `helm install`
and named in `values.yaml`. Every command below pipes its value into `kubectl` on stdin:
no value appears on a command line (`ps`), and no secret file is written, in this dir or
anywhere else. `tr -d '\n'` matters: `--from-file` keeps a trailing newline, which breaks
the hex decode of the HMAC secret.

```bash
kubectl create namespace <NAMESPACE>
```

Create the namespace first: the chart fails to render into a namespace that doesn't
exist yet (`cyoda help helm`, SECRETS PROVISIONING).

| # | Secret | Kubernetes Secret (key) | Read by | How |
|---|---|---|---|---|
| 1 | JWT signing key (RSA, PEM, ≥ 2048 bits) | `cyoda-jwt` (`signing-key.pem`) | `jwt.existingSecret` → `CYODA_JWT_SIGNING_KEY_FILE` | `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \| kubectl create secret generic cyoda-jwt -n <NAMESPACE> --from-file=signing-key.pem=/dev/stdin` |
| 2 | Postgres DSN (your database; the chart runs none) | `cyoda-pg` (`dsn`) | `postgres.existingSecret` → `CYODA_POSTGRES_URL_FILE` (pods and migration Job) | `printf 'DSN: '; read -rs PG_DSN; echo; printf '%s' "$PG_DSN" \| kubectl create secret generic cyoda-pg -n <NAMESPACE> --from-file=dsn=/dev/stdin; unset PG_DSN`, typing `postgres://user:pass@host:5432/db?sslmode=require` |
| 3 | HMAC secret (cluster mode is always on) | `cyoda-hmac` (`secret`) | `cluster.hmacSecret.existingSecret` → `CYODA_HMAC_SECRET_FILE` | `openssl rand -hex 32 \| tr -d '\n' \| kubectl create secret generic cyoda-hmac -n <NAMESPACE> --from-file=secret=/dev/stdin` |
| 4 | Metrics bearer token (admin port 9091) | `cyoda-metrics-bearer` (`bearer`) | `monitoring.metricsBearer.existingSecret` → `CYODA_METRICS_BEARER_FILE` | `openssl rand -hex 24 \| tr -d '\n' \| kubectl create secret generic cyoda-metrics-bearer -n <NAMESPACE> --from-file=bearer=/dev/stdin` |

- [ ] 1–4 created: `kubectl get secret -n <NAMESPACE>` lists `cyoda-jwt`, `cyoda-pg`,
      `cyoda-hmac` and `cyoda-metrics-bearer`.
- [ ] Optional, two database roles: a second DSN Secret for the migration Job (the owner/DDL
      role), set as `migrate.postgres.existingSecret` in `values.yaml`.
- [ ] Rotation: secrets are read at startup; after replacing one, run
      `kubectl rollout restart statefulset/cyoda -n <NAMESPACE>`.

## Tokens for seed.sh and verify.sh

`seed.sh` and `verify.sh` run `CYODA_TOKEN_COMMAND` (with `CYODA_ENDPOINT` set) to get a
JWT, and send no auth header when it's unset.

- Single-user: leave `CYODA_TOKEN_COMMAND` unset.
- Shared and Helm: `CYODA_TOKEN_COMMAND='<TOKEN_COMMAND>'`. It runs `cyoda token` where
  the signing key is, for tenant `<TENANT>` with `ROLE_M2M` (`cyoda help cli token`): no
  client and no stored secret.

## Clients for your app and compute nodes

Shared and Helm: your app and each compute-node service get an M2M client of their own in
tenant `<TENANT>` (`cyoda help auth integration`, STEP 2). Create each once, with an admin
token, and move `client_id` and `client_secret` into that part's secret store (the secret
is shown once), then delete the file:

```bash
( umask 077; curl -sS --fail-with-body -o <APP>-compute.json -X POST "<API_URL>/api/clients?clientId=<APP>-compute" \
    -H @<(printf 'Authorization: Bearer %s\n' "$(<ADMIN_TOKEN_COMMAND>)") )
```

`409 M2M_CLIENT_EXISTS`: the client exists; `PUT /api/clients/<id>/secret` issues a new
secret (`cyoda help auth clients`). Tokens: `POST <API_URL>/api/tenants/<TENANT>/oauth/token`
(`cyoda help auth tokens`).

## Compute nodes

Compute nodes connect to the gRPC endpoint, not the REST port. Give each node (names as in
`cyoda help config grpc`):

| Variable | Value | Notes |
|---|---|---|
| `CYODA_COMPUTE_GRPC_ENDPOINT` | `<GRPC_ENDPOINT>` | host:port the node can reach |
| `CYODA_COMPUTE_TENANT_ID`, `CYODA_COMPUTE_CLIENT_ID`, `CYODA_COMPUTE_CLIENT_SECRET` | single-user: none needed (mock auth); shared and Helm: `<TENANT>` and the node's own client (above) | the stream opens only with that client's `client_credentials` token, never a `cyoda token` |
| `CYODA_COMPUTE_HTTP_BASE` | `<API_URL>` | token endpoint and REST callbacks |

Facts: `cyoda help auth integration` (STEP 6), `cyoda help grpc`.
