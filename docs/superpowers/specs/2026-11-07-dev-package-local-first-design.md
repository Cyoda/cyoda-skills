# Cyoda Dev Package: Design/Build/Test Focus, Local cyoda-go, Spikes

**Date:** 2026-11-07
**Status:** Draft, awaiting approval
**Supersedes:** in `2026-10-17-cyoda-go-split-and-help-first-design.md`, the `env` field, the production guard and `deploy` Step 7. The rest of that document stands.

## Intent

The skills help design, build and test cyoda-go applications. The agent gets platform facts from `cyoda help`. Remove what doesn't serve that cycle (Cloud remnants, production handling), make a local cyoda-go the expected setup, and let the agent spike complex behaviour.

## Rules for the skill text

- `SKILL.md` stays compact and to the point: instructions only. No rationale, no design discussion, no remarks about how a developer should work or about environments outside development.
- No access checks or restrictions in skills or scripts.

## Changes

### Remove

| Where | What |
|---|---|
| `app`, `auth`, `compute`, `debug`, `deploy`, `design`, `docs`, `setup`, `status`, `test` | The "Cloud … reply only 'That's not covered by this plugin.'" lines |
| Config, `cyoda-profile.sh`, `cyoda-status.sh` | The `env` field and `ENV=` in the status line. Old values are ignored |
| `cyoda-call.sh` | `--confirm-production` and exit `3` |
| `setup` | The development/production question in connect mode |
| `status` | The `[PRODUCTION]` tag |
| `build`, `test`, `debug` | Production guards and their questions |
| `debug` | The confirmation round before changing an entity (it shows the call it made) |
| `app` | The `[PRODUCTION]` profile line |
| `deploy` | Step 7 (adding a profile for the deployed instance) and the hand-off to `/cyoda:auth` for its credentials |

`setup` keeps connecting to an endpoint the developer gives, as a profile with `endpoint` and optional `tokenCommand`.

### Local cyoda-go

- `app`: the journey names a local cyoda-go as the step after design, before build.
- `build`, `test`: unchanged. They already need a running instance and hand off to `/cyoda:setup` without one.
- `design`: when the binary is missing, recommend installing it once ("next, type `/cyoda:setup`") and carry on. Drop "so it works without an instance and without the binary".
- `docs`: when the answer comes from the web mirror, say so once and recommend installing cyoda-go.
- `setup`, local and link mode: if the repo shows how the project runs its own stack (Compose file, `make` target, README), use that: start it if it isn't running, then link it.

### Web help mirror

One short list in `docs` of where the mirror differs, used when `SOURCE=web`: whole pages only (`--section` ignored), no actions (`cloudevents json`, `grpc proto`, `openapi …`, `workflows schema-version versions`), version from the mirror's `index.json`. Lowercase sub-topic paths are handled by `cyoda-help.sh` (`7ea25b7`). Nothing depends on a cyoda-docs fix.

### Spikes

Half a sentence in `design`, `build`, `compute` and `debug`, along the lines of: "For complex behaviour help doesn't settle, ask whether to spike it on a throwaway local instance (in-memory with mock auth, or the stack in Docker), and tear it down after." Add the needed commands to those skills' `allowed-tools`. No separate guide.

### `deploy`

Artifacts unchanged. The "Is this instance production?" question becomes "Which stage is this for?", with the strict-schema question asked for the stage the developer says is strict; `seed.sh --env <stage>` as today.

### `auth`

Unchanged apart from the removals above.

## Evals

- Remove Cloud assertions and every assertion on `[PRODUCTION]`, `ENV=`, `--confirm-production` or production questions.
- Rewrite the cases built on them: `build` 6, `test` 3 and 5, `status` cases showing `[PRODUCTION]`, `setup` 3 (keeps connecting, without the environment question), `debug` (repair without confirmation), `deploy` 3 (stage instead of production).
- Add: `design` with no binary (designs, recommends installing once); a spike offer in `design` or `build` (asks; carries on from help on a no); `setup` starting and linking a project's own Compose stack found in the repo.

## Tests and docs

- Script tests: `--confirm-production` gone, `env` ignored, no `ENV=`.
- Lint: add `--confirm-production`, `[PRODUCTION]`, `not covered by this plugin`.
- `README.md`, `cyoda/README.md`: config without `env`, no production guard.
- Release `0.5.0`.

## Left to the builder

Exact wording within the rules above; which eval cases are rewritten versus replaced.
