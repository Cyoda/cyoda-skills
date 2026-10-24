# Smoke tests

- `run.sh [--only NN] [--allow-version]` runs lint, `tests/scripts/test-*.sh`, `test-segregation.sh`, then each `scenarios/*.sh` against a fresh in-memory cyoda-go (v0.8.4) on ports 18080/19090/19091. `--only NN` runs just the scenario whose filename starts with `NN`.
- `lint.sh [--root DIR]` flags stale strings in `cyoda/` (needs `shellcheck`: `brew install shellcheck`).
- `test-segregation.sh` checks the plugin's Cloud segregation and side-effect flags (no migrate skill, `disable-model-invocation` on side-effect skills, single-plugin marketplace, plugin version, no Cloud lint hits). Run by `run.sh` unless `--only` is given.
- `test-harness.sh` tests the harness itself.
- `test-helm-template.sh` renders `cyoda/skills/deploy/templates/values.yaml` against the published chart `cyoda/cyoda` 0.8.4 with `helm template` (needs `helm` and network; no cluster; helm's config and cache go to a temp dir). Not part of `run.sh`.

- `scenarios/07-compute.sh` builds the Go compute member in `compute/` (test harness only, not skill content) and needs Go ≥ 1.26.7, or an older Go with `GOTOOLCHAIN=auto` plus network for the first toolchain and module download. Without either it prints `SKIP` and passes. Go runs with your real `HOME`, so it uses your usual module cache.

A scenario file defines `scenario_main`; it may use `assert_*` and `$BASE`. The server runs with `HOME` redirected to a temp dir, so `~/.config/cyoda/cyoda.env` is ignored. `start_server KEY=VALUE...` overrides default env (e.g. for a JWT-mode server).
