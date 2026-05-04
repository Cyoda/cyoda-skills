---
name: debug
description: Diagnose Cyoda failures and observe entity history. Two modes — debugging (fix problems) and observation (audit trail, point-in-time lookup). Auto-invoked when transition failures, processor errors, or entity history questions arise.
when_to_use: When a transition fails, a processor throws an error, an entity is in an unexpected state, connectivity is broken, or when investigating entity history and audit trails.
allowed-tools: Bash(curl *) Bash(cat *) Bash(grep *) Bash(jq *)
---

## Cyoda Debug and Observation

Reading connection config:
```!
jq . .cyoda/config 2>/dev/null || echo '{"endpoint":"none"}'
```

Are you **debugging a problem** or **observing entity history**?

---

### Debugging Mode

Identify the failure category and follow the relevant path:

#### Failed Transition

1. Fetch the entity and check current state:
```bash
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}"
```
2. Check if the transition is valid from the current state (compare against workflow definition)
3. Check criteria: if the transition has criteria, evaluate them manually
4. Look at entity changes for previous errors:
```bash
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}/changes"
```
5. If a processor is attached, check processor execution logs

#### Processor Error

1. Check gRPC connectivity: is your compute node registered?
2. Check tag routing: do the node's registered tags form a superset of the transition's required tags?
3. Check timeout: did the processor respond within 60s?
4. Check response format: does it include `requestId` and `entityId`?
5. Check idempotency: is the processor handling duplicate `requestId` correctly?

#### Schema Rejection

1. Check schema mode: discover (widening) vs lock (strict)
2. In discover mode: type conflicts cause polymorphic fields — check what happened
3. In lock mode: compare incoming entity fields against the locked schema
4. Use `/cyoda:docs` for schema management API details

#### Connectivity Issues

1. Check `.cyoda/config` has correct `endpoint` value
2. For cloud: check `token` is not expired — re-run `/cyoda:auth` if needed
3. Test endpoint directly:
```!
ENDPOINT=$(jq -r '.endpoint' .cyoda/config)
curl -sf --max-time 5 "${ENDPOINT}/readyz" || echo "UNREACHABLE"
```

---

### Observation Mode

Investigate an entity's history for audit, compliance, or investigation purposes.

**Browse entity lifecycle:**
```bash
ENDPOINT=$(jq -r '.endpoint' .cyoda/config)
TOKEN=$(jq -r '.token // ""' .cyoda/config)
AUTH=$([ -n "$TOKEN" ] && echo "-H 'Authorization: Bearer $TOKEN'" || echo "")

# Entity change history
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}/changes"
```

**Point-in-time state lookup:**
```bash
# What state was this entity in at a specific time?
curl -sf $AUTH "${ENDPOINT}/api/entity/${ENTITY_ID}?pointInTime=2026-01-15T10:00:00Z"
```

**Questions to answer with observation:**
- Which transitions fired and when?
- Which processors ran for each transition?
- What was the entity's state at time T?
- Has this entity been in an error state before?

For deeper audit data (who changed what, when), use `/cyoda:docs` to look up the audit endpoints.
