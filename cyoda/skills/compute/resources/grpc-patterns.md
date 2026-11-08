# Compute node gRPC patterns

Structure and sequence only. Field names, required fields and types come from `cyoda help cloudevents json` and `cyoda help grpc proto`; the protocol rules from `cyoda help grpc` (CONNECTION, COMPUTE MEMBER PROTOCOL, KEEPALIVE, TAG ROUTING, ERRORS).

## Event envelope

Every message on the stream is a CloudEvent (proto `io.cloudevents.v1.CloudEvent`) whose JSON payload is in `text_data`. The `type` attribute names the event (e.g. `CalculationMemberJoinEvent`). Both the CloudEvent attributes and the payload have required fields: take them from `grpc proto` and `cloudevents json`. Dispatched requests also carry extension attributes: `cyodatxtoken` (the transaction token for callbacks, echoed as `X-Tx-Token` / `tx-token`) and `authtype` / `authid` / `authclaims` (who caused the call; `grpc` COMPUTE MEMBER PROTOCOL, auth context).

## Lifecycle

```
connect(startStreaming, metadata: authorization = "Bearer " + token)
send   CalculationMemberJoinEvent{id, tags, joinedLegalEntityId}
recv   CalculationMemberGreetEvent{memberId, ...}   -> store memberId, send EventAckResponse
loop:
  recv KeepAliveEvent                 -> send EventAckResponse (sourceEventId = its id)
  recv EntityProcessorCalculationRequest -> send EntityProcessorCalculationResponse
  recv EntityCriteriaCalculationRequest  -> send EntityCriteriaCalculationResponse
  recv EntityFunctionCalculationRequest  -> send EntityFunctionCalculationResponse
on stream end or error: open a new stream and join again (new memberId)
```

The greet always arrives before any request. Keep reading at all times: a member that stops reading, or sends nothing for `CYODA_KEEPALIVE_TIMEOUT` seconds, is evicted (`grpc` KEEPALIVE; defaults in `cyoda help config grpc`). Requests in flight on a lost stream have already failed on the server (`COMPUTE_MEMBER_DISCONNECTED`); don't answer them on the new stream.

## Idempotency

A duplicate `requestId` gets the same response. Processors in `COMMIT_BEFORE_DISPATCH` mode can be re-dispatched with a new request after a conflict or crash, so their external side effects also need a natural key (an external id written once).

## Errors

- Stream errors: `Unauthenticated` (bad or missing token), `PermissionDenied` (no `ROLE_M2M`, or tenant mismatch on join), `InvalidArgument` (first message isn't a join), `DeadlineExceeded` (evicted).
- Inside a response, report failure with `success: false` and an `error` object; the workflow fails the transition (`WORKFLOW_FAILED`) unless the processor is `ASYNC_NEW_TX`.
