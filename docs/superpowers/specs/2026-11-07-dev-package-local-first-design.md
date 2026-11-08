# Cyoda Dev Package: Design/Build/Test Focus, Local cyoda-go, Spikes

**Date:** 2026-11-07
**Status:** Draft, awaiting approval
**Supersedes:** in `2026-10-17-cyoda-go-split-and-help-first-design.md`, the `env` field, the production guard and `deploy` Step 7. The rest of that document stands.

## Intent

The skills help design, build and test cyoda-go applications. The agent gets platform facts from `cyoda help`. Remove what doesn't serve that cycle (Cloud remnants, production handling), make a local cyoda-go the expected setup, and let the agent spike complex behaviour.

## Rules for the skill text

- `SKILL.md` stays compact and to the point: instructions only. No rationale, no design discussion, no remarks about how a developer should work or about environments outside development.
- No access checks or restrictions in skills or scripts.
- **Cyoda-specific content only.** Test for every line: would a frontier model (Opus/Sonnet 5.5 and peers) do this right without it, given `cyoda help`? If yes, cut it.

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
- `setup`, link mode: a project's own cyoda-go container that isn't running may be started (its Compose project), then linked.

### Web help mirror

One short list in `docs` of where the mirror differs, used when `SOURCE=web`: whole pages only (`--section` ignored), no actions (`cloudevents json`, `grpc proto`, `openapi …`, `workflows schema-version versions`), version from the mirror's `index.json`. Lowercase sub-topic paths are handled by `cyoda-help.sh` (`7ea25b7`). Nothing depends on a cyoda-docs fix.

### Spikes

Half a sentence in `design`, `build`, `compute` and `debug`, along the lines of: "For complex behaviour help doesn't settle, ask whether to spike it on a throwaway local instance (in-memory with mock auth, or the stack in Docker), and tear it down after." Add the needed commands to those skills' `allowed-tools`. No separate guide.

### `deploy`

Artifacts unchanged. The "Is this instance production?" question becomes "Which stage is this for?", with the strict-schema question asked for the stage the developer says is strict; `seed.sh --env <stage>` as today.

### `auth`

Unchanged apart from the removals above.

### Trim every skill to Cyoda-specific content

Applies to all 11 `SKILL.md` files and their resources, together with the changes above.

**Keep:**
- cyoda-go behaviour and gotchas a model can't infer: the canonical registration order, the version decision (`MODEL_HAS_ENTITIES` once entities exist), export reshaping (#684-I), tag overlap routing (#684-B), schedules on automated transitions, an automated exit from an error state needs a criterion, notifications "coming soon", the `/api/health` vs admin `/readyz` split, the install formula.
- Which `cyoda help` topic and section answers what.
- The plugin's own contract: script names, exit codes, the config shape, file layout and naming, the manifest, skill hand-offs.
- Cyoda modelling guidance: the best practices, the anti-patterns, the developer-says → model-it-as table.
- `#684` workarounds with their item letter.

**Cut:**
- Interaction choreography: one question at a time, skip answered questions, show-and-confirm rounds, "revise until yes", "tell the developer which file you saved".
- General engineering: shell quoting rules, `pipefail` explanations, the language-detection script, the `jq` manifest upsert (the schema stays), retry and reconnect patterns, the gRPC single-writer queue, how to write a token client or a CI script, secret hygiene a model already practises.
- Process policing: "never guess a path", "don't diagnose Homebrew", "don't sudo", the write-denied message, "a request to register is not the confirmation".
- Rationale sentences and common-mistakes rows that restate any of the above.

**Expected effect:** `SKILL.md` text roughly halves (18,400 words today). `compute/resources/grpc-patterns.md` shrinks to the cyoda-specific lifecycle (join, greet, keep-alive ack, the three request types, `cyodatxtoken`). `design/resources/design-guidelines.md` keeps only what the best practices and anti-patterns don't already cover. Within the local-first changes above, the same rule applies: `setup` keeps its Docker discovery but doesn't get a "read the README" instruction; the spike sentence names only the cyoda-specific part (in-memory storage and mock auth from `cyoda help run`, or the stack in Docker) and that the agent asks first.

The evals are the safety net: a trim that makes a case fail puts back only what that case needs.

## Evals

- Remove Cloud assertions and every assertion on `[PRODUCTION]`, `ENV=`, `--confirm-production` or production questions.
- Rewrite the cases built on them: `build` 6, `test` 3 and 5, `status` cases showing `[PRODUCTION]`, `setup` 3 (keeps connecting, without the environment question), `debug` (repair without confirmation), `deploy` 3 (stage instead of production).
- Add: `design` with no binary (designs, recommends installing once); a spike offer in `design` or `build` (asks; carries on from help on a no); `setup` starting and linking a project's own Compose stack found in the repo.

## Tests and docs

- Script tests: `--confirm-production` gone, `env` ignored, no `ENV=`.
- Lint: add `--confirm-production`, `[PRODUCTION]`, `not covered by this plugin`.
- `README.md`, `cyoda/README.md`: config without `env`, no production guard.
- Release `0.5.0`.

## Process

Every skill edit follows `superpowers:writing-skills`, with the evals as the tests: write or change the eval case first, run it against the current skill and see it fail, edit the skill, re-run it and see it pass. Match the guidance form to the failure (a recipe or exact text for wrong-shaped output, a conditional on an observable predicate, no prohibition lists). Also covers rewording three edits made without it on 2026-11-07: `debug` Path E ("never assume…" becomes a positive instruction), and the rationale in `deploy`'s quoted question (that question is reworded here anyway); `app`'s Cloud line is removed.

## Left to the builder

Exact wording within the rules above; which eval cases are rewritten versus replaced.
