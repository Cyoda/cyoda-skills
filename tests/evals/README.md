# Eval tooling

Helpers for running `cyoda/skills/<skill>/evaluations/evals.json` (process: "Running evals" in `CLAUDE.md`). Results go to `cyoda-evals-workspace/<iteration>/`; server state goes to `tests/evals/.state/` (gitignored).

## Real server or simulated instance

- **Real server** for anything the skill does to an instance (status, register, create, transitions, auth). One throwaway in-memory cyoda-go per eval, then `setup.py` writes the fixtures and a plugin config pointed at it. Prompts: `exec-prompt.md`, `grade-prompt.md`.
- **Simulated instance** when the fixture needs state a fresh server can't give cheaply: specific entity ids or histories, a running compute node, a remote or production endpoint. The executor answers instance calls from the eval's `_simulated/instance.md` (marked SIMULATED/ASSUMED). Prompts: `exec-prompt-sim.md`, `grade-prompt-sim.md`; run `setup.py … none`.
- **Help runs for real** in both: executors call `cyoda help` / `cyoda-help.sh` against the installed binary. For a "cyoda not installed" eval, render the prompt with `--no-cyoda`: it tells the executor to use the PATH from `nocyoda-path.sh`, which hides only the `cyoda` binary.

## Commands

```bash
bash tests/evals/start.sh <id> [mock|jwt]      # server on 20000+id*100+{80 HTTP, 90 gRPC, 91 admin}
python3 tests/evals/setup.py <iteration> <skill> <eval_id> <id|none> [--seed-project] [--endpoint URL]
bash tests/evals/prompt.sh exec-prompt.md <iteration> <skill> <eval_id> [--no-cyoda]   # executor prompt
bash tests/evals/prompt.sh grade-prompt.md <iteration> <skill> <eval_id>               # grader prompt
bash tests/evals/timing.sh <iteration> <skill> <eval_id> <total_tokens> <duration_ms>  # with_skill/timing.json
bash tests/evals/stop.sh [id...]                # kills by port; reports how many still listen
```

- Pick a distinct server id per eval (e.g. skill number × 10 + eval id) so parallel executors don't share an instance. Ids up to 454 keep ports below 65536.
- `--seed-project` registers the fixture's `src/data/<e>-v1-sample.json`, locks the model and imports `src/workflows/<e>-v1-workflow.json`: use it when the eval starts with models already on the instance.
- **JWT mode** (`start.sh <id> jwt`) is for auth evals: a fresh RSA signing key and a bootstrap client `evalclient` / `evalsecret`; tokens come from `POST /api/oauth/token` (`cyoda help auth tokens`). Mock mode needs no token.
- **Timing:** when an executor's task notification arrives, run `timing.sh` with its `total_tokens` and `duration_ms` before grading; each call is also appended to `.state/tokens.log`.
- `stop.sh` kills whatever listens on each server's ports, because `.state/s<id>/pid` holds a wrapper's pid, not cyoda's.
