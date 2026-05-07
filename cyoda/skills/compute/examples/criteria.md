# Compute Node Criteria Implementation

## Fetch Schemas First

Before implementing, run:
```
cyoda help cloudevents json
```
Look up `EntityCriteriaCalculationRequest` and `EntityCriteriaCalculationResponse` for the exact field names and required fields. Do not rely on the pseudocode below for field names — the schemas are authoritative.

## Pattern

You receive a criteria request when the platform needs to evaluate whether a transition should fire. You return a boolean result.

```
function handleCriteriaRequest(request):
  if alreadyEvaluated(request.<requestId field>):
    return cachedResponse(request.<requestId field>)

  entity = parseJSON(request.<entity data field>)

  // your boolean logic here
  result = entity.amount > 1000 AND entity.currency == "EUR"

  return buildResponse(
    requestId: request.<requestId field>,
    entityId: request.<entityId field>,
    result: result   // true = criteria met, transition may fire
  )
```
