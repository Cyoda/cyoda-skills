# Compute Node Processor Implementation

## Fetch Schemas First

Before implementing, run:
```
cyoda help cloudevents json
```
Look up `EntityProcessorCalculationRequest` and `EntityProcessorCalculationResponse` for the exact field names and required fields. Do not rely on the pseudocode below for field names — the schemas are authoritative.

## Pattern

You receive a processor request for each entity transitioning through a tagged state. You process it and return a response.

```
function handleProcessorRequest(request):
  if alreadyProcessed(request.<requestId field>):
    return cachedResponse(request.<requestId field>)

  entity = parseJSON(request.<entity data field>)

  // your business logic here
  entity.processedAt = now()

  response = buildResponse(
    requestId: request.<requestId field>,
    entityId: request.<entityId field>,
    entityData: toJSON(entity),
    success: true
  )

  cacheResponse(request.<requestId field>, response)
  return response
```

## Timeout

Complete the response within 60 seconds (default). For long operations, use async processing and return a "processing started" response, then trigger a transition when complete.
