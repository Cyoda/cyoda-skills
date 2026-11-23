# Compute node gRPC patterns

Structure and sequence only. Field names, required fields and types come from `cyoda help cloudevents json` and `cyoda help grpc proto`; the protocol rules from `cyoda help grpc` (CONNECTION, COMPUTE MEMBER PROTOCOL, KEEPALIVE, TAG ROUTING, ERRORS) and `cyoda help auth integration` (STEP 6 — CONNECT A COMPUTE NODE).

## Event envelope

Every message on the stream is a CloudEvent (proto `io.cloudevents.v1.CloudEvent`) whose JSON payload is in `text_data`. The `type` attribute names the event (e.g. `CalculationMemberJoinEvent`). Both the CloudEvent attributes and the payload have required fields: take them from `grpc proto` and `cloudevents json`. Dispatched requests also carry attributes: `cyodatxtoken` (the transaction token for callbacks, echoed as `X-Tx-Token` / `tx-token`), `authtype` / `authid` (who the work is for), `authexectype` / `authexecid` (who executes it), `authclaims` (the executor's roles), and `time` (the platform clock); `grpc` COMPUTE MEMBER PROTOCOL, auth context.

## Lifecycle

```
token = client_credentials token of the node's own M2M client   // renewed before expiry; the stream stays open
connect(startStreaming, metadata: authorization = "Bearer " + token)
send   CalculationMemberJoinEvent{id, tags, joinedLegalEntityId}
recv   CalculationMemberGreetEvent{memberId, ...}   -> store memberId, send EventAckResponse
loop:
  recv KeepAliveEvent                 -> send EventAckResponse (sourceEventId = its id)
  recv EntityProcessorCalculationRequest -> send EntityProcessorCalculationResponse
  recv EntityCriteriaCalculationRequest  -> send EntityCriteriaCalculationResponse
  recv EntityFunctionCalculationRequest  -> send EntityFunctionCalculationResponse
on stream end: by status (Errors below), open a new stream and join again (new memberId)
```

The greet always arrives before any request. Keep reading at all times: a member that stops reading, or sends nothing for `CYODA_KEEPALIVE_TIMEOUT` seconds, is evicted (`grpc` KEEPALIVE; defaults in `cyoda help config grpc`). A request in flight on a lost stream is no longer this member's; don't answer it on the new stream. If cyoda tries it again, it arrives as a new request with the same `requestId`.

## Idempotency

Every try of one callout carries the same `requestId`. A `COMMIT_BEFORE_DISPATCH` replay (the client ran the operation again) is a new callout with a new `requestId` (`workflows` PROCESSORS), so key its side effects on a natural id (a write-once external id), not only `requestId`.

## Errors

- Stream errors (`grpc` ERRORS): `Unauthenticated` (bad token, or the client was deleted or its secret reset: fetch a fresh token and reconnect; stop if it is refused again), `PermissionDenied` (not the node's own client-credentials token, no `ROLE_M2M`, or `joinedLegalEntityId` names another tenant: fix the configuration), `InvalidArgument` (first message isn't a join), `DeadlineExceeded` (evicted: reconnect at once), `Unavailable` (node shutting down or client store unreadable: reconnect with backoff).
- Inside a response, report failure with an explicit `success: false` and an `error` object; an `error` without it is a success. The workflow fails the operation (`WORKFLOW_FAILED`) unless the processor is `ASYNC_NEW_TX`, and no other member is tried.
