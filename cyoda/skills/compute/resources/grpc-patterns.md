# Compute node gRPC patterns

Structure and sequence only. Field names, required fields and types come from `cyoda help cloudevents json` and `cyoda help grpc proto`; the protocol rules from `cyoda help grpc` (CONNECTION, COMPUTE MEMBER PROTOCOL, KEEPALIVE, TAG ROUTING, ERRORS). Check those before you implement anything here.

## Event envelope

Every message on the stream is a CloudEvent (proto `io.cloudevents.v1.CloudEvent`) whose JSON payload is in `text_data`. The `type` attribute names the event (e.g. `CalculationMemberJoinEvent`). Both the CloudEvent attributes and the payload have required fields: take them from `grpc proto` and `cloudevents json`. Dispatched requests also carry extension attributes: `cyodatxtoken` (the transaction token for callbacks) and `authtype` / `authid` / `authclaims` (who caused the call; `grpc` COMPUTE MEMBER PROTOCOL, auth context).

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
on stream end or error: reconnect (below)
```

The greet always arrives before any request. Keep reading at all times: a member that stops reading, or sends nothing for `CYODA_KEEPALIVE_TIMEOUT` seconds, is evicted (`grpc` KEEPALIVE; defaults in `cyoda help config grpc`).

## Single writer: a send queue

A gRPC stream allows one sender at a time. Handlers that run in parallel put their responses on a queue; one loop drains it into the stream.

```
send_queue = new blocking queue
enqueue(send_queue, JoinEvent)

function outbound():            // the stream's request iterator
    loop:
        event = dequeue(send_queue)     // blocks
        if event == STOP: return
        yield event

stream = startStreaming(outbound(), metadata = auth)

for each event in stream:               // inbound, never blocked by work
    if event is a request:
        run_in_worker(handle, event)    // worker enqueues its response
    else:
        enqueue(send_queue, ackFor(event))

enqueue(send_queue, STOP)
```

Go: a channel and one goroutine calling `Send`. Python: `queue.Queue` and a generator. Java: `LinkedBlockingQueue` and one thread calling `onNext`. Handlers that take long still let the inbound loop ack keep-alives.

## Reconnection

On disconnect, eviction (`DeadlineExceeded`) or a server restart:
1. Wait with exponential backoff and jitter, e.g. 1 s, 2 s, 4 s, up to a cap.
2. Get a fresh token: the old one may have expired.
3. Open a new stream and join again. The server assigns a new member id.
4. Requests that were in flight on the old stream have already failed on the server side (`COMPUTE_MEMBER_DISCONNECTED`); don't send their answers on the new stream.

## Tags

Declare the tags in the join event. Routing is by overlap with the workflow's `calculationNodesTags`, random among matches, any member when the workflow's tags are empty (`grpc` TAG ROUTING; `workflows` PROCESSORS is wrong on this, #684-B). Use one distinct tag per kind of work, and exactly the same spelling as the workflow.

## Idempotency

Keep a bounded cache of `requestId` → response. A duplicate gets the cached response. Processors in `COMMIT_BEFORE_DISPATCH` mode can be re-dispatched with a new request after a conflict or crash, so their external side effects also need a natural key (an external id written once).

## Errors

- Stream errors: `Unauthenticated` (bad or missing token), `PermissionDenied` (no `ROLE_M2M`, or tenant mismatch on join), `InvalidArgument` (first message isn't a join), `DeadlineExceeded` (evicted).
- Inside a response, report failure with `success: false` and an `error` object; the workflow fails the transition (`WORKFLOW_FAILED`) unless the processor is `ASYNC_NEW_TX`.
