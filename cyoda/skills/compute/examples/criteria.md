# Function criterion

Pseudocode for a criteria handler. Field names are placeholders: take the real ones from `cyoda help cloudevents json` (`processing/EntityCriteriaCalculationRequest.json` and `EntityCriteriaCalculationResponse.json`). Semantics: `cyoda help grpc` COMPUTE MEMBER PROTOCOL (criteria dispatch); criterion shape: `cyoda help search` CONDITION DSL (FunctionCondition).

## Workflow side

A `function` criterion must be the whole criterion on a transition (or a workflow's selection criterion), not nested in a `group`. Its `function.name` arrives as the request's criteria id/name, and `function.config.calculationNodesTags` routes it by tag overlap. Use one only when the check needs data that isn't on the entity, or when the user should see why it failed. A field check on the entity is an inline `simple` criterion and needs no compute node.

## Handler

```
function handleCriteriaRequest(request):
  if cache.has(request.<requestId>):
    return cache.get(request.<requestId>)

  entity = request.<payload>.<data>
  // request.<target> says what is being decided, e.g. "TRANSITION"

  limit = creditService.limitFor(entity.customerId)
  ok = entity.amount <= limit

  response = {
    <requestId>: request.<requestId>,
    <entityId>:  request.<entityId>,
    success: true,
    matches: ok
  }
  if not ok:
    response.reason = "amount " + entity.amount + " exceeds credit limit " + limit   // ≤ 2 KiB

  cache.put(request.<requestId>, response)
  return response
```

## Where the reason shows up

- **Manual transition**: the caller gets `400 WORKFLOW_FAILED` with `detail` `transition "<name>" criterion not matched: <reason>`. The transaction rolls back, so this is the only place it appears.
- **Automated transition, workflow selection**: the `TRANSITION_NOT_MATCH_CRITERION` or `WORKFLOW_SKIP` event in `GET /api/audit/entity/{id}` carries it as `data.reason`.
- No `reason`: the audit says `criterion did not match`, and the 400 detail is the bare `criterion not matched`.

`success: false` (as opposed to `matches: false`) means the criterion couldn't be evaluated. That fails the call rather than holding the entity.
