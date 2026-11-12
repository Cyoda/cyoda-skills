---
name: test
description: Use when the entity models and workflows of a cyoda-go app need a smoke test on the instance (create an entity, fire its manual transitions, check the states), or a re-runnable smoke-test script for one entity is wanted, e.g. for CI.
allowed-tools: Bash(*cyoda-call.sh *) Bash(*cyoda-help.sh *) Bash(*cyoda-status.sh*) Bash(*cyoda-profile.sh*) Bash(jq *) Bash(cat *) Bash(ls *) Bash(cp *) Bash(mkdir *) Bash(bash *) Bash(*cyoda-local.sh *) Bash(*cyoda-config-write.sh *) Bash(*cyoda-docker-instances.sh*) Bash(*get-token.sh*) Bash(cyoda *) Bash(brew *) Bash(curl *) Bash(command -v *) Bash(git rev-parse *) Bash(pwd *) Bash(cd * && pwd -P) Bash(sh) Bash(chmod *) Bash(cmp *) Bash(find *)
---

# Cyoda smoke test

Create one entity per model, walk its manual transitions on the happy path, and report each state against the workflow. Or hand the developer a script that does the same for one entity.

**Facts come from `cyoda help`, not from this file.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` (stderr shows `SOURCE=instance|binary|web`). Exit 2 means unknown topic, exit 6 unknown section (stderr lists the sections that exist). Step 2.1 reads the sections this run depends on. State paths, fields and behaviour from what you read, and name the topic and section.

**Every API call** goes through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh <METHOD> <PATH> [curl args...]`. PATH is relative to `<endpoint>/api` (e.g. `/model/`). The body goes to stdout and `HTTP_STATUS=<code>` to stderr.

| Exit | Meaning | What you do |
|---|---|---|
| 0 | 2xx | continue |
| 1 | invalid config file, or `CYODA_PROFILE` names a profile that doesn't exist | show stderr and stop; the plugin config is covered by `cyoda:setup` |
| 22 | HTTP ≥ 400, or `HTTP_STATUS=000` | `000` means curl never got a response (bad `@file` path, connection refused): a call problem, not a test result. Fix the call and re-run it. 401/403: the script already retried once with a fresh token. Show the error and [get a token](#no-instance-or-no-token). Anything else: record ✗ for the step (Step 3) |
| 4 | the profile's tokenCommand failed | show stderr and [get a token](#no-instance-or-no-token) |
| 5 | no endpoint configured | [get an instance](#no-instance-or-no-token) |
| 64 | usage error (a leading `-` or a missing method/path) | fix the call form |

Request bodies are files (`--data-binary @<file>`) or a short inline literal (`-d '{}'`), never stdin: a token retry would resend an empty body.

## Step 0 — Connection

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. `STATUS=connected` with `SOURCE=project`, with `SOURCE=profile` for a `PROFILE` other than `default` (the old machine-wide local default), or with `CYODA_PROFILE` set: show any `WARN=` lines as they are and go on. Otherwise, `SOURCE=default` included, [get an instance](#no-instance-or-no-token).

### No instance or no token

- **Get an instance** (Step 0 doesn't go on, or exit 5): carry out `cyoda:setup`'s procedure yourself: read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow its *Getting an instance* for this project. Then go on with the test.
- **Get a token** (401/403, or exit 4): carry out `cyoda:auth`'s procedure yourself: read `${CLAUDE_PLUGIN_ROOT}/skills/auth/SKILL.md` and follow it for the bound instance. Explain the error from help: read `cyoda-help.sh auth tokens --section ERRORS` (and `auth clients --section "REQUEST FLOW"` for a rejected client) and name the section next to the fact. Once a call succeeds, re-run the failed call and go on. While the token can't be had (credentials only the developer holds), run no test calls.

## Step 1 — Mode

**Guided** (a script to re-run, e.g. in CI) when the request asks for one; otherwise **automated**: run the test now.

## Step 2 — Discover

1. **Read help.** Run `cyoda-help.sh crud --section ENDPOINTS` (the entity calls) and `cyoda-help.sh models --section ENDPOINTS` (the model calls) before any call below.
2. `cyoda-call.sh GET /model/`. Print "Discovered N models: `<name>` v`<version>` (`<currentState>`), ...".
3. A model in the project's `cyoda-manifest.json` that is missing from the instance (e.g. a fresh instance): register it from its listed files following `cyoda:build`'s Step 7 (canonical order; read `${CLAUDE_PLUGIN_ROOT}/skills/build/SKILL.md`), then list again. The project's files stay unchanged.
4. Only LOCKED models can hold entities. If any model is UNLOCKED, run `cyoda-help.sh models --section LIFECYCLE` and give its reason when you list the model as skipped: "not locked yet (<reason>, `models` § LIFECYCLE)".
5. More than 3 testable models: test the ones the request names, else all.
6. For each selected model, `cyoda-call.sh GET /model/{e}/{v}/workflow/export`. Note `initialState` and, per state, the transitions with `manual: true`, skipping any with `disabled: true` or a `schedule` (those can't be fired by name). No workflow: skip the model and say so in the summary.
7. The payload is the project's sample: read `cyoda-manifest.json` at the project root and use the `sample` file listed for `{e}` v`{v}`. No manifest entry: write a minimal payload from `GET /model/export/SIMPLE_VIEW/{e}/{v}` and check it with `POST /model/validate/{e}/{v}` (it answers 200 either way: read `.success` and `.message`).

Guided mode continues at [Guided mode](#guided-mode).

## Step 3 — Run (automated)

For each model print `Testing <e> v<v>...`, then:

1. **Create**: `POST /entity/JSON/{e}/{v}` with `-H 'Content-Type: application/json' --data-binary @<sample>`. The id is `.[0].entityIds[0]`. Print `  Creating entity... ✓ [id: <id>]` or `✗ <errorCode>`.
2. **State after create**: `GET /entity/{id}`, `.meta.state`. Automated transitions run inside the create, so the state may be past `initialState` (`workflows --section "ENGINE EXECUTION"`). Work out the expected state by following the automated transitions from `initialState`; if a criterion makes that uncertain, say why. Print `  State after create: <s> ✓` or `✗ (expected <x>)`.
3. **Manual transitions**: `GET /entity/{id}/transitions` lists what can fire now. Take the first manual transition the workflow declares for the current state that is also in that list. Fire it with **PATCH `{}`**, which keeps the data unchanged (a PUT with no body is a 400, #684-C; a PUT with a body replaces the data):
   `cyoda-call.sh PATCH /entity/JSON/{id}/{t} -H 'Content-Type: application/merge-patch+json' -H 'If-Match: *' -d '{}'`
   Then `GET /entity/{id}` and compare with the transition's `next` (plus any automated cascade after it). Print `  <t>: <state> ✓` or `✗ (expected <x>)`. Repeat until the state has no manual transition left or a state repeats.
4. **On a failure**: read `.properties.errorCode` from the body and run `cyoda-help.sh errors <errorCode>` (every code has a page, including the ones the ERROR CODE INDEX leaves out). Put the one-line cause next to the ✗, then continue with the next model.

## Step 4 — Summary and clean-up

```
Model        | Transitions fired | Result
-------------|-------------------|-------
<e> v<v>     | N                 | PASS / FAIL (step, errorCode)
```

Then:
- **Clean-up**: `DELETE /entity/{id}` for each id created in this run, nothing else; the models stay. Say so in one line. Delete is soft: the history stays, and no workflow runs. Never send the model-wide `DELETE /entity/{e}/{v}`: with no condition it deletes every entity of the model.
- A failure: give the call, status and body; diagnosing it is covered by `cyoda:debug`, and a workflow fix by `cyoda:build`.

## Guided mode

The template [templates/smoke-test.sh](templates/smoke-test.sh) reads everything from the environment, so it's copied unchanged:

1. Pick one model and one manual transition from Step 2. Copy `${CLAUDE_PLUGIN_ROOT}/skills/test/templates/smoke-test.sh` to `scripts/smoke-test.sh` if a `scripts/` directory exists, else to `smoke-test.sh` at the project root.
2. Give the run command with the discovered values. Take the endpoint from `cyoda-status.sh` and the profile's `tokenCommand` from `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-profile.sh` (omit `CYODA_TOKEN_COMMAND` when there is none, as in mock mode). With `"source":"project"` the `tokenCommand` may be relative to `projectDir`: run the command from there. The script runs the token command with `CYODA_ENDPOINT` set, as the plugin does.
   ```bash
   ENTITY_NAME=<e> MODEL_VERSION=<v> TRANSITION_NAME=<t> EXPECTED_STATE=<next> \
   CYODA_ENDPOINT='<endpoint>' CYODA_TOKEN_COMMAND='<tokenCommand>' bash scripts/smoke-test.sh
   ```
3. Say what it does: checks the model is LOCKED, creates an entity from the manifest's sample (or `SAMPLE_FILE`), checks the transition is available, fires it with PATCH `{}`, and ends with `=== PASS ===` (exit 0) or `=== FAIL ===` (exit 1). It stores no token: it runs the token command each time.

## Common mistakes

| Mistake | Instead |
|---|---|
| Firing a transition with an empty PUT | PATCH `{}` with `If-Match: *` and merge-patch (#684-C) |
