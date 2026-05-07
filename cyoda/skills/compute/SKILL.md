---
name: compute
description: Guide implementation of Cyoda compute nodes — external gRPC processors and criteria services. Language-agnostic. Covers connection lifecycle, tag routing, processor and criteria patterns, and production requirements. Auto-invoked when compute node implementation is discussed.
when_to_use: When the user needs to implement a compute node processor or criteria service, asks about gRPC integration, or needs to connect external code to Cyoda workflows.
allowed-tools: Bash(jq *)
---

## Cyoda Compute Node Implementation

Compute nodes are **optional** — many Cyoda workflows work entirely with built-in processors and criteria. Only add a compute node when you need custom logic that Cyoda cannot express natively.

### Do you need a compute node?

A compute node is needed when a workflow transition requires:
- Calling an external API or service
- Running custom validation or calculation logic
- Modifying entity data in a way built-in processors don't support

If your workflow only needs state changes, simple field criteria, or scheduled transitions — you likely don't need a compute node.

### Implementation Guide

Refer to the detailed patterns reference: [resources/grpc-patterns.md](resources/grpc-patterns.md)

**Connection steps:**
1. Connect to `CloudEventsService.startStreaming` via gRPC
2. Send `CalculationMemberJoinEvent` with your tags — see [grpc-patterns.md](resources/grpc-patterns.md)
3. Receive `CalculationMemberGreetEvent` with your `memberId`
4. Handle incoming requests (processors or criteria)
5. Maintain keep-alive, implement reconnection

**For processor implementation:** see [examples/processor.md](examples/processor.md)
**For criteria implementation:** see [examples/criteria.md](examples/criteria.md)

### Authentication

Use the JWT token from the active profile in `~/.config/cyoda/cyoda-plugin-config.json`:
```!
PROFILE=$(jq -r '.active // "default"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "default"); jq -r --arg p "$PROFILE" '.profiles[$p].token // "none — local mock auth"' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "no token — local mock auth"
```
Include as bearer token in gRPC metadata: `Authorization: Bearer {token}`

For local cyoda-go with mock auth, authentication may not be required — check with `/cyoda:docs`.

### Schema Details — Fetch Before Implementing

**Before writing any implementation code**, fetch the authoritative schemas:
1. `cyoda help grpc proto` — CloudEvent proto definition; generate language-specific stubs from this
2. `cyoda help cloudevents json` — JSON schemas for every event type with exact field names

Do NOT rely on field names from `grpc-patterns.md` or `examples/` — those show structure and sequence only. The schemas are the authoritative source for field names, required fields, and types. Using stale example field names instead of checking the schemas is a common source of bugs.

### Production Requirements

- Idempotency: deduplicate using `requestId`
- Thread safety: synchronize all stream writes
- Timeout: respond within 60 seconds
- Reconnection: exponential backoff (see grpc-patterns.md)
- Monitoring: track request latency, keep-alive intervals, reconnection count
