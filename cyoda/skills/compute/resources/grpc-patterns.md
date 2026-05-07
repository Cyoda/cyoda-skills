# Cyoda Compute Node gRPC Patterns

## Before You Implement — Fetch the Authoritative Schemas

**Always run this first:**
```
cyoda help cloudevents json
```

This returns the JSON schemas for every event type (JoinEvent, GreetEvent, KeepAliveEvent, ProcessorRequest/Response, CriteriaRequest/Response, EventAckResponse, etc.) with exact field names, types, and required fields. The examples below describe the *structure and sequence* only — get field names from the schemas, not from this file.

## Endpoint

### Local cyoda-go
`localhost:9090` (plaintext). No TLS.

### Cyoda Cloud
The gRPC endpoint uses a **different hostname** from the REST API. If the REST endpoint is:
```
https://client-<id>-<env>.eu.cyoda.net
```
The gRPC endpoint is:
```
grpc-client-<id>-<env>.eu.cyoda.net:443  (TLS)
```
Just prepend `grpc-` to the REST hostname and use port 443 with TLS. Do not try the REST hostname directly for gRPC — it will return HTTP 405.

## Connection Lifecycle

All compute nodes connect via a persistent bidirectional gRPC stream to `CloudEventsService.startStreaming`.

### 1. Join Handshake

Send a join event with your tags. Receive a greet event back with your assigned member ID — store it.
The greet event requires an acknowledgement response. Check `cyoda help cloudevents json` for the exact event type names and required fields.

### 2. Keep-Alive

The server sends periodic keep-alive probes. Respond within the configured timeout (default 60s).
Failure to respond causes disconnection. Check `cyoda help cloudevents json` for the keep-alive event type name and the required response type and fields.

### 3. Reconnection

Implement exponential backoff on disconnection:
- Attempt 1: wait 1s
- Attempt 2: wait 2s
- Attempt 3: wait 4s
- Cap at 60s

On reconnect, send the join event again (new member ID will be assigned).

## Event Envelope

Every event sent to the gRPC stream is a CloudEvent proto wrapping a JSON payload in `text_data`. The CloudEvent proto fields (id, source, type, etc.) and the text_data payload both have their own required fields — check `cyoda help grpc proto` and `cyoda help cloudevents json` for both sets.

## Tag-Based Routing

The platform routes requests only to members whose registered tags form a **superset** of the tags configured on the workflow processor/criterion.

Example: if workflow processor has tags `["payment", "eu"]`, your compute node must register with at least `["payment", "eu"]` (plus any additional tags you want).

Tags are case-insensitive.

## Authentication

Include a JWT bearer token in gRPC metadata headers:
```
Authorization: Bearer eyJ...
```

## Thread Safety and Bidirectional Streaming

The gRPC bidirectional stream is not thread-safe for sending. The correct pattern is a **queue-based request iterator** — a single goroutine/thread reads from a channel/queue and streams events; all other goroutines/threads enqueue events to send.

Pseudocode (language-agnostic):
```
send_queue = new blocking queue
enqueue(send_queue, JoinEvent)

function requestIterator():
    loop:
        event = dequeue(send_queue)  // blocks until item available
        if event == STOP_SIGNAL: return
        yield event

stream = startStreaming(requestIterator(), metadata=authMeta)

for each event in stream:
    response = handleEvent(event)
    enqueue(send_queue, response)

enqueue(send_queue, STOP_SIGNAL)  // shut down iterator
```

This pattern works in any language with a blocking queue and iterator/generator abstraction. In Go, use a channel; in Python, use `queue.Queue`; in Java, use `LinkedBlockingQueue`.

## Idempotency

Use the request ID field in every request to deduplicate retries. If you receive a request with an ID you've already processed, return the cached response. Check `cyoda help cloudevents json` for the exact field name.
