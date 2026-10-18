# Smoke tests

- `run.sh [--only NN] [--allow-version]` runs lint, `tests/scripts/test-*.sh`, then each `scenarios/*.sh` against a fresh in-memory cyoda-go (v0.8.4) on ports 18080/19090/19091. `--only NN` runs just the scenario whose filename starts with `NN`.
- `lint.sh [--root DIR]` flags stale strings in `cyoda/` (needs `shellcheck`: `brew install shellcheck`).
- `test-harness.sh` tests the harness itself.

A scenario file defines `scenario_main`; it may use `assert_*` and `$BASE`. The server runs with `HOME` redirected to a temp dir, so `~/.config/cyoda/cyoda.env` is ignored. `start_server KEY=VALUE...` overrides default env (e.g. for a JWT-mode server).
