# Workflow design best practices beyond `cyoda help design`

Practices for designing Cyoda entity models and workflows that `cyoda help design` doesn't carry.
Review a design against both lists. Each practice has a bold name, and a design review cites that
name. Where a practice depends on platform mechanics, it names the `cyoda help` section. Read that
section for the exact syntax. Do not copy syntax from this file.

## Contents

- [Terms](#terms)
- [Entities and keys](#entities-and-keys)
- [Shaping the state machine](#shaping-the-state-machine)
- [Transitions](#transitions)
- [Several workflows on one model](#several-workflows-on-one-model)
- [Criteria](#criteria)
- [Processors and cascades](#processors-and-cascades)
- [Scheduled transitions](#scheduled-transitions)
- [Validation](#validation)
- [Review checklist](#review-checklist)

## Terms

| Term | Meaning |
|---|---|
| anchor | The entity whose transition is running the processor |
| callout | A processor, a function criterion or a schedule function |
| API boundary | Your application's layer between its users and Cyoda |

## Entities and keys

- **Enforce uniqueness with a unique key, never a criterion.** A criterion that searches for an
  existing entity cannot see one that another transaction is creating at the same time. It also
  covers only the transitions that declare it. The store checks a unique key on every write, by
  every writer. Declare the key before the model locks. Unique keys need a storage backend that
  supports them (`422 COMPOSITE_KEY_UNSUPPORTED` when you declare one). Facts: `cyoda help models`
  ENDPOINTS (unique-keys).
- **"Exactly one live X per Y" is a unique key with a retirement number.** A plain key cannot
  express "live". Give X an integer field `retiredSeq`, sent as `0` on create (a key filled in part
  refuses the write) and changed only by processors, and register the key `(Y, retiredSeq)`:

  ```
  X is created:              retiredSeq = 0                              a second live X for Y claims (Y, 0): refused
  X enters a terminal state: retiredSeq = 1 + max(retiredSeq of Y's Xs)  (Y, 0) is free for a successor
  ```

  The choice of terminal states then decides when a successor may exist, so state it explicitly.
  Keys are checked when the transaction commits, so retiring X and creating its successor may be one
  transaction, in either order; in separate requests, retire X first. Facts: `cyoda help models`
  ENDPOINTS (unique-keys, **Enforcement**).

## Shaping the state machine

- **Add a technical state only where the platform needs one.** A state such as `processing` or
  `retry` is usually work for a processor on a transition. Two shapes need a state with no business
  meaning. One is the waiting state and the routing state of a poll (`cyoda help workflows`
  SCHEDULED TRANSITIONS, "One-shot vs. polling"). The other is the state before a
  `COMMIT_BEFORE_DISPATCH` processor, which other transactions can read (`cyoda help workflows`
  PROCESSORS). Give each technical state a `description` that says why it exists.

## Transitions

- **Declare a general action once per state it is legal from.** The caller names only the
  transition, and the engine resolves the name in the entity's current state. So `CANCEL`, declared
  on each state that allows it, takes the entity to `cancelled` from any of them. Each declaration
  has its own criterion and processors.
- **Declare who may fire a transition in its annotations.** Put a `roles` list on each transition,
  and have your API boundary check it before it fires the transition. The engine stores annotations
  and reads none of them (`cyoda help workflows` WORKFLOW SCHEMA, `annotations`). Let an empty list
  mean that no person fires the transition: only processors, scheduled transitions and your
  application's own system work do. Your API boundary offers users every transition that has roles,
  and none that has none.
- **Let only your deployment change the workflows.** Whoever imports a workflow sets its `roles`,
  and cyoda-go admits only M2M clients, so import workflows only from reviewed files in a deployment
  step, and offer no route to the import endpoint (`cyoda help auth`).
- **Give a transition name one set of permitted roles.** A user sees an action by its name, and
  your API boundary checks its roles by that name. When the rule depends on **who** acts, use two
  transition names with two role sets (`APPROVE` and `APPROVE_OVER_LIMIT`). When it depends on
  **the data**, use one name with a criterion, which holds for every caller.

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
  catch-all keeps its state, which the catch-all does not declare. Facts: `cyoda help workflows`
  CRITERIA, "Workflow-level selection".

## Criteria

- **Put the cheap test before the callout.** Put in-memory conditions before function conditions
  in a group, or in the function condition's pre-check (`function.criterion`), so a callout is made
  only when it can change the answer. Facts: `cyoda help workflows` CRITERIA, "Function conditions".
- **Fail closed.** A function criterion that cannot decide (a failed read, missing data, an unknown
  `context`) answers with `success: false`, not `matches: false`. A `matches: false` lets the next
  automated transition fire. A failure fails the write with `WORKFLOW_FAILED`. Facts:
  `cyoda help grpc` COMPUTE MEMBER PROTOCOL, `cyoda help workflows` CRITERIA, "Function conditions".

## Processors and cascades

- **Pass the anchor's facts down the cascade.** The engine applies a processor's returned changes
  after the processor answers. So a processor on another entity, fired by this processor, does not
  see them when it reads the anchor. Put what that entity's processor needs into the body of the
  transition that fires on it. Facts: `cyoda help workflows` PROCESSORS ("What a callback read of
  the entity returns").
- **Declare `idempotent: true` only where a repeat is harmless everywhere.** Cyoda gives a
  processor that got no answer to another compute member, and repeats it in a scheduled run, only
  when it is declared `idempotent`; without it, the callout or the scheduled task fails instead.
  Facts: `cyoda help workflows` PROCESSORS (**Repeating a processor**).

## Scheduled transitions

- **Never put an automated transition with no criterion beside a scheduled transition.** The entity
  leaves the state at once, so the scheduled transition never fires. An automated transition with a
  criterion is allowed there: a write that does not match leaves the entity in the state and re-arms
  the scheduled transition. Facts: `cyoda help workflows` SCHEDULED TRANSITIONS (**Arming**).
- **End the entity that carries a recurring scheduled transition.** A recurring cycle adds
  revisions to its entity forever. For example, create one scan entity per business day. Have each
  one create the next day's entity and then end itself.
- **Give a scheduled transition a `timeoutMs`.** A failed scheduled run is retried with a growing
  delay, and without `timeoutMs` it is retried without end. Facts: `cyoda help workflows`
  SCHEDULED TRANSITIONS (**Retries**).

## Validation

- **Name elements with letters, digits, `_` and `-`.** The platform accepts names of up to 256
  characters. The `@cyoda/workflow-core` validator, which the Cyoda workflow editor uses, also
  rejects dots. Use prefixes for namespaces (`asset-cash-terms-complete`).

## Review checklist

Copy this list into the review, after the `cyoda help design` bullets. Mark each line `ok`,
`changed: <what>` or `n/a`. Change the design for each line that fails, then review the whole list
again. Stop when every line is `ok` or `n/a`.

```
Entities and keys
- Enforce uniqueness with a unique key, never a criterion
- "Exactly one live X per Y" is a unique key with a retirement number
Shaping the state machine
- Add a technical state only where the platform needs one
Transitions
- Declare a general action once per state it is legal from
- Declare who may fire a transition in its annotations
- Let only your deployment change the workflows
- Give a transition name one set of permitted roles
Several workflows on one model
- End the list with a catch-all workflow
Criteria
- Put the cheap test before the callout
- Fail closed
Processors and cascades
- Pass the anchor's facts down the cascade
- Declare `idempotent: true` only where a repeat is harmless everywhere
Scheduled transitions
- Never put an automated transition with no criterion beside a scheduled transition
- End the entity that carries a recurring scheduled transition
- Give a scheduled transition a `timeoutMs`
Validation
- Name elements with letters, digits, `_` and `-`
```
