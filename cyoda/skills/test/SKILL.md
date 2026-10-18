---
name: test
description: Use when the developer types /cyoda:test to smoke-test the entity models and workflows registered on their cyoda-go instance (create an entity, fire its manual transitions, check the states), or to get a re-runnable smoke-test script for one entity.
allowed-tools: Bash(*cyoda-call.sh *) Bash(*cyoda-help.sh *) Bash(*cyoda-status.sh*) Bash(*cyoda-profile.sh*) Bash(jq *) Bash(cat *) Bash(ls *) Bash(cp *) Bash(mkdir *) Bash(bash *)
disable-model-invocation: true
---

# Cyoda smoke test

Create one entity per model, walk its manual transitions on the happy path, and report each state against the workflow. Or hand the developer a script that does the same for one entity.

**Facts come from `cyoda help`, not from this file.** Read the section, not the whole topic: run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> --section "<NAME>"` (stderr shows `SOURCE=instance|binary|web`). Exit 2 means unknown topic, exit 6 unknown section (stderr lists the sections that exist). The entity calls are in `crud --section ENDPOINTS`; read it before Step 3.

**Every API call** goes through `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-call.sh [--confirm-production] <METHOD> <PATH> [curl args...]`. PATH is relative to `<endpoint>/api` (e.g. `/model/`). The body goes to stdout and `HTTP_STATUS=<code>` to stderr. Never build a URL or auth header yourself.

| Exit | Meaning | What you do |
|---|---|---|
| 0 | 2xx | continue |
| 22 | HTTP ≥ 400 | 401/403: the script already retried once with a fresh token. Show the error, stop, and say "next, type `/cyoda:auth`". Anything else: record ✗ for the step (Step 3) |
| 3 | production refusal | see Step 3, Production |
| 4 | the profile's tokenCommand failed | show stderr, stop, and say "next, type `/cyoda:auth`" |
| 5 | no endpoint configured | stop and say "next, type `/cyoda:setup`" |

Request bodies are files (`--data-binary @<file>`) or a short inline literal (`-d '{}'`), never stdin: a token retry would resend an empty body.

## Step 0 — Connection

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`.
- `STATUS=not_configured`: "No cyoda-go instance is configured. Next, type `/cyoda:setup`." Stop.
- `STATUS=unreachable`: show the `WARN=` line and stop.
- Show any other `WARN=` lines as they are.
- `ENV=production`: say "Profile `<PROFILE>` (`<ENDPOINT>`) is **production**." Discovery (Step 2) is GETs only and runs as usual; the question comes before the first write (Step 3).

## Step 1 — Mode

Ask: "Run the smoke test now (**automated**), or get a script you can re-run (**guided**)?" Skip the question if the request already says which.

## Step 2 — Discover

1. `cyoda-call.sh GET /model/` (help: `models --section ENDPOINTS`). Print "Discovered N models: `<name>` v`<version>` (`<currentState>`), ...".
2. Only LOCKED models can hold entities (`models --section LIFECYCLE`). List any UNLOCKED one as skipped: "not locked yet; next, type `/cyoda:build` to finish registering it".
3. More than 3 testable models: ask which to test (names or `all`).
4. For each selected model, `cyoda-call.sh GET /model/{e}/{v}/workflow/export`. Note `initialState` and, per state, the transitions with `manual: true`, skipping any with `disabled: true` or a `schedule` (those can't be fired by name). No workflow: skip the model and say so in the summary.
5. The payload is the project's sample: read `cyoda-manifest.json` at the project root and use the `sample` file listed for `{e}` v`{v}`. No manifest entry: write a minimal payload from `GET /model/export/SIMPLE_VIEW/{e}/{v}`, check it with `POST /model/validate/{e}/{v}` (it answers 200 either way: read `.success` and `.message`), and show it before using it.

Guided mode continues at [Guided mode](#guided-mode).

## Step 3 — Run (automated)

**Production:** before the first create, ask "This test creates real entities and fires real transitions on `<ENDPOINT>`. Proceed? (yes/no)". Only after an explicit yes, add `--confirm-production` to this run's POST/PATCH/DELETE calls. Without a yes, stop after the Step 2 report: no writes.

For each model print `Testing <e> v<v>...`, then:

1. **Create**: `POST /entity/JSON/{e}/{v}` with `-H 'Content-Type: application/json' --data-binary @<sample>`. The id is `.[0].entityIds[0]`. Print `  Creating entity... ✓ [id: <id>]` or `✗ <errorCode>`.
2. **State after create**: `GET /entity/{id}`, `.meta.state`. Automated transitions run inside the create, so the state may be past `initialState` (`workflows --section "ENGINE EXECUTION"`). Work out the expected state by following the automated transitions from `initialState`; if a criterion makes that uncertain, say why. Print `  State after create: <s> ✓` or `✗ (expected <x>)`.
3. **Manual transitions**: `GET /entity/{id}/transitions` lists what can fire now. Take the first manual transition the workflow declares for the current state that is also in that list. Fire it with **PATCH `{}`**, which keeps the data unchanged:
   `cyoda-call.sh PATCH /entity/JSON/{id}/{t} -H 'Content-Type: application/merge-patch+json' -H 'If-Match: *' -d '{}'`
   Then `GET /entity/{id}` and compare with the transition's `next` (plus any automated cascade after it). Print `  <t>: <state> ✓` or `✗ (expected <x>)`. Repeat until the state has no manual transition left or a state repeats.
4. **On a failure**: read `.properties.errorCode` from the body and run `cyoda-help.sh errors <errorCode>` (every code has a page, including the ones the ERROR CODE INDEX leaves out). Put the one-line cause next to the ✗, then continue with the next model: don't stop the run.

Don't fire a transition with a PUT and no body: that's a 400 (#684-C), and a PUT with a body replaces the data.

## Step 4 — Summary and clean-up

```
Model        | Transitions fired | Result
-------------|-------------------|-------
<e> v<v>     | N                 | PASS / FAIL (step, errorCode)
```

Then offer, one at a time:
- **Clean-up**: "Delete the N test entities? (yes/no)". On yes, `DELETE /entity/{id}` for each id created in this run, nothing else. Delete is soft: the history stays, and no workflow runs (`crud --section ENDPOINTS`). Never send the model-wide `DELETE /entity/{e}/{v}`: with no condition it deletes every entity of the model.
- **History**: "Show the audit trail of `<id>`?" On yes, use the `cyoda:debug` skill in observation mode for that entity.
- A failure: offer the `cyoda:debug` skill with the call, status and body. If the fix is a workflow change, "next, type `/cyoda:build`".

## Guided mode

The template [templates/smoke-test.sh](templates/smoke-test.sh) reads everything from the environment, so it's copied unchanged:

1. Pick one model and one manual transition from Step 2. Copy the template to `scripts/smoke-test.sh` if a `scripts/` directory exists, else to `smoke-test.sh` at the project root. If a different file is already there, ask before overwriting.
2. Give the run command with the discovered values. Take the endpoint from `cyoda-status.sh` and the profile's `tokenCommand` from `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-profile.sh` (omit `CYODA_TOKEN_COMMAND` when there is none, as in mock mode):
   ```bash
   ENTITY_NAME=<e> MODEL_VERSION=<v> TRANSITION_NAME=<t> EXPECTED_STATE=<next> \
   CYODA_ENDPOINT=<endpoint> CYODA_TOKEN_COMMAND=<tokenCommand> bash scripts/smoke-test.sh
   ```
3. Say what it does: checks the model is LOCKED, creates an entity from the manifest's sample (or `SAMPLE_FILE`), checks the transition is available, fires it with PATCH `{}`, and ends with `=== PASS ===` (exit 0) or `=== FAIL ===` (exit 1). It never reads or stores a token itself.

## Common mistakes

| Mistake | Instead |
|---|---|
| Guessing endpoint paths | `crud --section ENDPOINTS`, `models --section ENDPOINTS` |
| Expecting the entity in `initialState` after create | Follow the automated cascade first |
| Firing a transition with an empty PUT | PATCH `{}` with `If-Match: *` and merge-patch |
| Inventing a payload when the project has a sample | The manifest's `sample` file |
| Handling 401 by re-running the token command | The script already did. Say "next, type `/cyoda:auth`" |
| Saying you'll run `/cyoda:build` or `/cyoda:setup` yourself | "Next, type `/cyoda:<x>`" with a one-line reason |
| A Cloud or migration question | "That's not covered by this plugin" |
