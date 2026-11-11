> Temporary — superseded by cyoda help once Cyoda/cyoda-go#684 item L ships.

# Workflow design best practices

Practices for designing Cyoda entity models and workflows. Each practice has a bold name, and a
design review cites that name. Platform facts are checked against cyoda-go 0.8.4. Where a practice
depends on platform mechanics, it names the `cyoda help` section. Read that section for the exact
syntax. Do not copy syntax from this file.

## Contents

- [Terms](#terms)
- [Entities and keys](#entities-and-keys)
- [Shaping the state machine](#shaping-the-state-machine)
- [Transitions](#transitions)
- [Several workflows on one model](#several-workflows-on-one-model)
- [Criteria](#criteria)
- [Processors and cascades](#processors-and-cascades)
- [Scheduled transitions](#scheduled-transitions)
- [Annotations](#annotations)
- [Validation](#validation)
- [Review checklist](#review-checklist)

## Terms

This file uses these terms and no synonyms for them.

| Term | Meaning |
|---|---|
| entity | One instance of a model. Its revisions are its history |
| manual transition | A transition that a caller fires by name |
| automated transition | A transition that the engine fires by itself when its criterion matches |
| scheduled transition | A transition that fires by itself at a computed time. Arming it sets that time |
| loopback | A write with no transition name. It re-runs the automated transitions from the current state |
| cascade | The transitions, on this entity and on others, that one write sets off |
| criterion | The condition on a transition or on a workflow. A **function criterion** is evaluated by a compute node. The other types are evaluated in memory |
| compute node | Your process that joins Cyoda over gRPC and serves callouts. Help calls it a compute member or calculation node |
| processor | Code on a compute node that runs when its transition fires |
| callout | A processor, a function criterion or a schedule function |
| call site | One declaration of a callout in a workflow |
| handler | The code on the compute node that answers a callout by its name |
| anchor | The entity whose transition is running the processor |
| workflow selection | The choice of one workflow, among the model's workflows, for an entity |
| API boundary | Your application's layer between its users and Cyoda |
| source state | The state a transition leaves |
| transaction token | The token Cyoda sends with a dispatch. A processor's writes that carry it join the transition's transaction |

## Entities and keys

- **Use tree-shaped JSON.** Nested objects and arrays are first-class in search and in criteria
  (`[*]`, `[n]`). Keep a value that you will group or aggregate on at a scalar path, because grouped
  stats cannot use array subscripts.
- **Compute aggregations; don't maintain them.** A running total or a counter entity conflicts under
  snapshot isolation (retryable 409s), and it repeats what a query gives. Use point-in-time reads,
  searches and the stats API. Add a dedicated aggregate entity only when volumes make indexed queries
  too slow. Facts: `cyoda help crud` (stats), `cyoda help search`.
- **Link entities by entity id.** Store the referenced entity's id in a field for 1:1, 1:N or N:M
  relations. The platform does not check the reference, and it does not stop the deletion of a
  referenced entity.
- **Enforce uniqueness with a unique key, never a criterion.** A criterion that searches for an
  existing entity cannot see one that another transaction is creating at the same time. It also
  covers only the transitions that declare it. The store checks a unique key on every write, by
  every writer. Declare the key before the model locks. Unique keys need a storage backend that
  supports them (`422 COMPOSITE_KEY_UNSUPPORTED` when you declare one). Facts: `cyoda help models`
  (unique keys).
- **"Exactly one live X per Y" is a unique key with a retirement number.** A plain key cannot
  express "live". Give X an integer field `retiredSeq` that only processors write, and register the
  key `(Y, retiredSeq)`:

  ```
  X is created:              retiredSeq = 0                              a second live X for Y claims (Y, 0): refused
  X enters a terminal state: retiredSeq = 1 + max(retiredSeq of Y's Xs)  (Y, 0) is free for a successor
  ```

  The choice of terminal states then decides when a successor may exist, so state it explicitly. A
  transaction that retires one X and creates its successor writes the retirement first. The engine
  saves an anchor's changes only after its processor answers (see *Let the engine save the anchor*),
  so X must not be the anchor of the processor that creates the successor. Have that processor fire
  X's retiring transition first, and then create the successor. Facts:
  `cyoda help models` (transactional ordering: free before claim), `cyoda help crud` (a key field
  that is missing fails the write).

## Shaping the state machine

- **Balance the number of states.** Too few states hide the processing. Too many make the workflow
  hard to follow. The engine limits a cascade to `CYODA_MAX_STATE_VISITS` (default 10) visits per
  state and to a depth of 100.
- **Add a technical state only where the platform needs one.** A state such as `processing` or
  `retry` is usually work for a processor on a transition. Two shapes need a state with no business
  meaning. One is the waiting state and the routing state of a poll
  ([Scheduled transitions](#scheduled-transitions)). The other is the state before a
  `COMMIT_BEFORE_DISPATCH` processor, which other transactions can read. Give each technical state a
  `description` that says why it exists.
- **Model error states explicitly.** Give each step that can fail a transition to an explicit error
  state. A manual transition out keeps the entity there until someone fires it. An automated
  transition out needs a criterion, or the entity leaves at once. A scheduled transition out, for
  escalation, is also allowed. Find the entities that need action by a search on the state
  (`cyoda help crud` state counts, `cyoda help search`).
- **Add backward transitions for retries and corrections.** A transition back to an earlier state
  lets a person correct data or retry a step without a new entity.
- **Build explicit validation cycles.** When a change makes an entity invalid, route it back to a
  state before the validation step. An automated backward transition needs a criterion. Use
  `allowCycles: true` only for a cycle that passes through a scheduled transition.
- **Define precise terminal states.** The engine has no terminal flag: an entity stays in a state
  that has no automated transition. Use several terminal states to say how a lifecycle ended. Keep planned ends
  (`completed`, `matured`) apart from other ends (`cancelled`, `rejected`, `replaced`).
- **End a lifecycle in a terminal state; never delete.** Delete bypasses the workflow: no
  transition, criterion or processor runs. A terminal state keeps the entity and its history.

## Transitions

- **Drive processing with automated transitions.** After every write, the engine fires the first
  matching automated transition in declaration order, again and again, inside the write's
  transaction. An automated transition with no criterion comes last in its state, or it shadows every
  transition after it. Facts: `cyoda help workflows` CRITERIA.
- **Use manual transitions for external triggers.** People, batch jobs and other systems fire manual
  transitions. So do processors that act on other entities, which is how a cascade crosses entities.
  The engine does not enforce `manual: true`: a caller can fire any transition by name that is not
  disabled or scheduled. Your API boundary enforces "manual only".
- **Re-trigger evaluation with a loopback, not by firing an automated transition.** A loopback
  re-runs the automated transitions from the current state, so their criteria get another chance. An
  empty merge patch `{}` is a loopback that changes no data. A loopback also re-arms the state's
  scheduled transitions, and so postpones them
  ([Scheduled transitions](#scheduled-transitions)). Facts: `cyoda help crud` (PATCH).
- **Declare a general action once per state it is legal from.** The caller names only the
  transition, and the engine resolves the name in the entity's current state. So `CANCEL`, declared
  on each state that allows it, takes the entity to `cancelled` from any of them. Each declaration
  has its own criterion and processors.
- **Declare who may fire a transition in its annotations.** Put a `roles` list on each transition,
  and have your API boundary check it before it fires the transition. The permissions then live
  beside the transitions they control. A reviewer reads who may do what from the workflow, and one
  edit to the workflow changes an action and its permission together. Your API boundary can build
  both its routes and its permission check from the workflow, with no second list to keep in step.
  Let an empty list mean that no person fires the transition: only processors, scheduled
  transitions and your application's own system work do. Test both directions: your API boundary
  offers users every transition that has roles, and offers them no transition that has none.
- **Let only your deployment change the workflows.** Whoever imports a workflow sets its `roles`,
  and cyoda-go admits only M2M clients, so import workflows only from reviewed files in a deployment
  step, and offer no route to the import endpoint (`cyoda help auth`).
- **Give a transition name one set of permitted roles.** A user sees an action by its name, and
  your API boundary checks its roles by that name. One role set per name makes the permission
  readable from the name alone. When the rule depends on **who** acts, use two transition names with
  two role sets (`APPROVE` and `APPROVE_OVER_LIMIT`). When it depends on **the data**, use one name
  with a function criterion, which holds for every caller.

## Several workflows on one model

- **End the list with a catch-all workflow.** Workflow selection takes the first active workflow
  whose criterion matches. When none matches, the engine uses a built-in default workflow and gives
  only a warning. Declare an unconditional workflow last. Its initial state is an error state that
  quarantines the unrecognised variant:

  ```
  workflows: [ asset-cash (kind = cash), asset-security (kind = security), ...,
               asset-unsupported-kind (criterion: null) -> initial state "unsupported" ]
  ```

  The catch-all quarantines only a new entity. An existing entity that selection moves to the
  catch-all keeps its state, and the catch-all does not declare that state, so its next manual
  transition fails with `WORKFLOW_FAILED`. Facts: `cyoda help workflows` CRITERIA,
  "Workflow-level selection".
- **Select on a field that you refuse to change.** Workflow selection runs again on every write and
  every transition, against the payload of that request. An edit to the selecting field can move the
  entity to another workflow. That can strand it in an undeclared state, or cancel its scheduled
  transition. A caller who can write the field can also choose which workflow's criteria apply to
  its own request. The engine does not make the field immutable, so refuse writes to it at your API
  boundary. Facts: `cyoda help workflows` CRITERIA, "Workflow-level selection".
- **Hold deliberate duplicates identical with a check.** A transition's target state is fixed. When
  the same processing must lead back to different states, the workflow needs twin states with the
  same transitions. Assert in a test that the twins carry the same processors and criteria.

## Criteria

- **Give a rejection reason when a criterion fails.** Only a function criterion can return a
  `reason` (with `matches: false`, at most 2 KiB). A manual transition returns it in its
  `400 WORKFLOW_FAILED` response. An automated transition records it in the audit event
  `TRANSITION_NOT_MATCH_CRITERION`. Name the condition that failed. An in-memory criterion records
  a generic message, so describe its purpose in `criterionAnnotations.description`. Facts:
  `cyoda help grpc` (criteria response).
- **Compute live facts in a function criterion, not a stored flag.** A flag that one transition
  writes and another reads is out of date as soon as a rule changes or a date passes. When a
  criterion depends on derived facts (eligibility, expiry, coverage), compute them when the
  transition fires.
- **Make a function criterion the whole criterion.** A function criterion nested in a `group` fails
  every evaluation, although it imports cleanly. When a criterion needs two computed clauses, write
  one function criterion that checks both. Facts: `cyoda help workflows` CRITERIA.
- **Check for a non-blank value with a function criterion.** `NOT_NULL` means "present and not
  null", and the empty string `""` meets it. Facts: `cyoda help predicates`.
- **Fail closed.** A function criterion that cannot decide (a failed read, missing data, an unknown
  `context`) answers with `success: false`, not `matches: false`. A `matches: false` lets the next
  automated transition fire. A failure fails the write with `WORKFLOW_FAILED`. Never let a criterion
  that could not be evaluated read as permission. Facts: `cyoda help grpc` (`success: false`),
  `cyoda help errors WORKFLOW_FAILED`.

## Processors and cascades

- **Let the engine save the anchor.** A processor returns its changes. It never writes the entity
  it was called for, even when it holds the transaction token. Help allows either path, and this
  practice takes the stricter one: the engine applies the returned changes, so one path writes the
  anchor. Facts: `cyoda help workflows` PROCESSORS ("a processor must not save the entity it is
  processing for").
- **Pass the anchor's facts down the cascade.** The engine applies a processor's returned changes
  after the processor answers. So while a processor runs, its changes to the anchor are not in the
  store. A processor on another entity, fired by this processor, does not see them when it reads the
  anchor. Put what that entity's processor needs into the body of the transition that fires on it.
- **Fail loud.** A processor that meets a case it does not handle, or a call site with no handler,
  answers with a failure. A success that did nothing commits a transition with wrong data, and the
  defect shows later as a wrong number. A failed `SYNC` processor leaves the entity in its source
  state. An `ASYNC_NEW_TX` processor's failure is only logged, and the transition completes, so never
  use that mode for a processor whose failure matters. Facts: `cyoda help workflows` PROCESSORS.
- **State the call site's role in `context`.** One handler can serve several call sites. The
  workflow passes `context` to the handler verbatim. The handler reads its role from `context`,
  never from the transition name, which a rename changes silently. An empty `context` arrives as no
  `parameters` at all. So a handler that expects a context refuses when it is absent or unknown.
  Facts: `cyoda help workflows` PROCESSORS (`context`).
- **Keep a cascade in one transaction with `SYNC`.** A `SYNC` processor whose writes carry the
  transaction token commits with its parent or rolls back with it. Use `COMMIT_BEFORE_DISPATCH` for
  slow external work. The state before that processor is then committed, and other transactions can
  read it. The processor must be idempotent, because a replay dispatches it again. Facts:
  `cyoda help workflows` PROCESSORS (execution modes).
- **Make every processor safe to run again.** A caller that replays a failed request runs its
  processors again, in a new transaction. cyoda-go dispatches a processor once, whatever the
  policy. Facts: `cyoda help workflows` PROCESSORS (`retryPolicy`). A processor's writes through
  Cyoda roll back with its transaction. Its effects outside Cyoda do not, so make them idempotent.

## Scheduled transitions

- **Poll for a condition that can become true without a write.** The engine evaluates automated
  transitions only when the entity is written. A condition that turns true because time passes, or
  because another entity changes, is never seen. Poll for it with a waiting state and a routing
  state:

  ```
  waiting  --scheduled, no criterion-->                checking
  checking --automated, criterion "condition holds"--> done
  checking --automated, no criterion, declared last--> waiting
  ```

  Import the cycle with `allowCycles: true`. Facts: `cyoda help workflows` SCHEDULED TRANSITIONS,
  "One-shot vs. polling".
- **Never put an automated transition with no criterion beside a scheduled transition.** The entity
  leaves the state at once, so the scheduled transition never fires. An automated transition with a
  criterion is allowed there: a write that does not match leaves the entity in the state and re-arms
  the scheduled transition. Facts: `cyoda help workflows` SCHEDULED TRANSITIONS (arming).
- **Expect frequent writes to postpone a scheduled transition.** Each write that leaves the entity
  in the source state arms the scheduled transition again. An entity that is written more often than
  its interval never fires. Put the scheduled transition on an entity that is not written while it
  waits.
- **End the entity that carries a recurring scheduled transition.** A recurring cycle adds
  revisions to its entity forever. For example, create one scan entity per business day. Have each
  one create the next day's entity and then end itself.
- **Make a scheduled transition's processors safe to run twice.** The scheduler can dispatch a due
  scheduled transition again after `CYODA_SCHEDULER_REDISPATCH_BACKOFF` (default 30 s). Facts:
  `cyoda help config scheduler`. On cyoda-go 0.8.4 a failed fire was dispatched again in this way
  (measured).

## Annotations

- **Choose one annotation vocabulary and enforce it at your API boundary.** The engine stores
  `annotations` and `criterionAnnotations`, and it reads none of them. Help names two well-known
  keys, `displayName` and `description`. Any other key, such as a `roles` list on a transition
  (see *Declare who may fire a transition in its annotations*), means nothing until your API
  boundary acts on it. Fail the build when an annotation is missing or has an
  unknown key. Facts: `cyoda help workflows` WORKFLOW SCHEMA (`annotations`).
- **Let the workflow describe the actions.** Put each action's label (`displayName`), help text
  (`description`), roles and any confirmation flag on its transition. Have your API boundary build
  the actions it offers from these annotations, and keep no separate list of actions.

## Validation

- **Name elements with letters, digits, `_` and `-`.** The platform accepts names of up to 256
  characters. The `@cyoda/workflow-core` validator, which the Cyoda workflow editor uses, also
  rejects dots. Use prefixes for namespaces (`asset-cash-terms-complete`).
- **Set `version` to the import contract.** A workflow's `version` is the version of the workflow
  import contract, not of the model. Facts: `cyoda help workflows schema-version`.
- **Validate before you import, then fire every transition.** Run each workflow through
  `@cyoda/workflow-core`, then import it into a throwaway instance. Some defects pass both and fail
  only when a transition fires: a function criterion nested in a `group`, a criterion on a field
  that the model does not declare, and a processor with `type: "internalized"`. Facts:
  `cyoda help workflows` CRITERIA, PROCESSORS.
- **Tie call sites to handlers in both directions.** The engine dispatches a callout by name, so a
  call site with no handler fails only when it runs. Test that every call site in a workflow has a
  handler, and that every handler has a call site.

## Review checklist

Copy this list into the review. Mark each line `ok`, `changed: <what>` or `n/a`. Change the design
for each line that fails, then review the whole list again. Stop when every line is `ok` or `n/a`.

```
Entities and keys
- Use tree-shaped JSON
- Compute aggregations; don't maintain them
- Link entities by entity id
- Enforce uniqueness with a unique key, never a criterion
- "Exactly one live X per Y" is a unique key with a retirement number
Shaping the state machine
- Balance the number of states
- Add a technical state only where the platform needs one
- Model error states explicitly
- Add backward transitions for retries and corrections
- Build explicit validation cycles
- Define precise terminal states
- End a lifecycle in a terminal state; never delete
Transitions
- Drive processing with automated transitions
- Use manual transitions for external triggers
- Re-trigger evaluation with a loopback, not by firing an automated transition
- Declare a general action once per state it is legal from
- Declare who may fire a transition in its annotations
- Let only your deployment change the workflows
- Give a transition name one set of permitted roles
Several workflows on one model
- End the list with a catch-all workflow
- Select on a field that you refuse to change
- Hold deliberate duplicates identical with a check
Criteria
- Give a rejection reason when a criterion fails
- Compute live facts in a function criterion, not a stored flag
- Make a function criterion the whole criterion
- Check for a non-blank value with a function criterion
- Fail closed
Processors and cascades
- Let the engine save the anchor
- Pass the anchor's facts down the cascade
- Fail loud
- State the call site's role in `context`
- Keep a cascade in one transaction with `SYNC`
- Make every processor safe to run again
Scheduled transitions
- Poll for a condition that can become true without a write
- Never put an automated transition with no criterion beside a scheduled transition
- Expect frequent writes to postpone a scheduled transition
- End the entity that carries a recurring scheduled transition
- Make a scheduled transition's processors safe to run twice
Annotations
- Choose one annotation vocabulary and enforce it at your API boundary
- Let the workflow describe the actions
Validation
- Name elements with letters, digits, `_` and `-`
- Set `version` to the import contract
- Validate before you import, then fire every transition
- Tie call sites to handlers in both directions
```
