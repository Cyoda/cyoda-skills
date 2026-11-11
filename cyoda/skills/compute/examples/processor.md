# Processor

Pseudocode for a processor handler. Field names are placeholders: take the real ones from `cyoda help cloudevents json` (`processing/EntityProcessorCalculationRequest.json` and `EntityProcessorCalculationResponse.json`). Semantics: `cyoda help grpc` COMPUTE MEMBER PROTOCOL and `cyoda help workflows` PROCESSORS.

## Workflow side

The processor sits on a transition. Its `config.calculationNodesTags` must share at least one tag with the node's join tags; `executionMode` and `config.responseTimeoutMs` are set per processor (SKILL.md Step 6).

## Handler

```
function handleProcessorRequest(request, cloudEvent):
  if cache.has(request.<requestId>):
    return cache.get(request.<requestId>)

  entity = request.<payload>.<data>            // absent when attachEntity = false

  quote = pricingService.quote(entity.items)
  entity.total = quote.total                    // the field must exist in the model's schema,
                                                // or the model's changeLevel must allow it

  // Optional: move a linked entity (event cascade) in the same transaction.
  if entity.<warehouseOrderId> != null:
    http.patch(HTTP_BASE + "/api/entity/JSON/" + entity.<warehouseOrderId> + "/reserve",
               headers: { "Content-Type": "application/merge-patch+json",
                          "If-Match": "*",
                          "Authorization": "Bearer " + token,
                          "X-Tx-Token": cloudEvent.extension("cyodatxtoken") },
               body: "{}")

  response = {
    <requestId>: request.<requestId>,
    <entityId>:  request.<entityId>,
    success: true,
    payload: { type: "JSON", data: entity }     // omit payload to leave the data unchanged
  }
  cache.put(request.<requestId>, response)
  return response
```

## Rules

- Returned `payload.data` **replaces** the entity's data and is validated like a client write. A field the schema doesn't allow fails the transition with `WORKFLOW_FAILED` and rolls it back.
- `success: false` or a timeout fails the transition (`SYNC`, `ASYNC_SAME_TX`, `COMMIT_BEFORE_DISPATCH`). In `ASYNC_NEW_TX` it's only logged, and returned data is discarded.
- Either return data for the entity being processed, or write it yourself through a callback. Not both: the returned data overwrites the write.
- The linked entity's transition (`reserve` above) is `manual: true` in its own workflow. Without `X-Tx-Token`, the call runs as its own transaction and stays committed even if this transition fails.
