---
name: docs
description: Use when the developer asks how a cyoda-go API, endpoint, concept, configuration variable, error code, CLI command or gRPC/CloudEvents schema works, or another Cyoda skill needs a fact checked against `cyoda help`.
allowed-tools: Bash(*cyoda-help.sh *) Bash(cyoda help *) Bash(cyoda --version) Bash(command -v cyoda) Bash(jq *) WebFetch
---

# Cyoda documentation lookup

Answer from `cyoda help` and end with its source.

## Lookup order

Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh <topic...> [--section "<NAME>"]`. It stops at the first source that answers:

1. **The bound instance** (the working directory's `projects` entry in the plugin config, else the active profile): `GET <endpoint>/api/help/<topic>`.
2. **The local binary**: `cyoda help <topic> --format=json`.
3. **The web help mirror**: `https://docs.cyoda.net/help/<topic>.md`.

stderr line 1 is `SOURCE=instance|binary|web VERSION=<v>`. Exit 2: unknown topic (or every source failed). Exit 6: unknown section; stderr lists the sections that exist.

4. **Only if help has no answer**: the docs site. Fetch `https://docs.cyoda.net/llms.txt`, then the page it points to, and say the answer is from the docs site. The getting-started page (`install-and-first-entity`) is wrong on v0.8.4 until Cyoda/cyoda-docs#134 closes (workflow version `"1"`, entities before the model is locked, a transition fired by an empty PUT): take recipes from help.

## SOURCE=web

The first time, run `command -v cyoda`. It finds nothing: say "`cyoda` isn't installed, so this is from the web help mirror (v`<VERSION>`)." It finds `cyoda`: say only that the answer is from the web help mirror (v`<VERSION>`). Then answer from the mirror, which differs from the binary:

- It returns the whole page and ignores `--section`: find the section by its heading.
- It serves no actions (exit 2): `cloudevents json`, `grpc proto`, `openapi …`, `workflows schema-version versions`.
- `VERSION` is the docs' pinned version, from the mirror's `https://docs.cyoda.net/help/index.json`.

## Read sections, not topics

Read one section (`crud` and `workflows` are about 12k tokens each):

- Topic list: `cyoda help` (binary), or `https://docs.cyoda.net/help/index.json`.
- A topic's sections: request any section name; exit 6 prints the list. Or `cyoda help <topic> --format=json | jq -r '.sections[].name'`.
- Subtopics are extra words: `cyoda-help.sh config grpc`, `cyoda-help.sh auth tokens --section "REQUEST FLOW"`.
- Every `CYODA_*` variable with its default: `cyoda help config all`.

## Error codes

Run `cyoda-help.sh errors <CODE>` (e.g. `errors WORKFLOW_FAILED`): every code has its own page. `errors --section "ERROR CODE INDEX"` is incomplete (cyoda-go#684 item N), so a code missing from the index isn't missing from help; the full list is the topic's subtopics: `cyoda help errors --format=json | jq -r '.children[]'` (or SUBTOPICS at the end of `cyoda help errors`). The code is in a response's `.properties.errorCode`; key on it, not on the HTTP status.

## Schemas

Get field names and types from these:

| Need | Run | Notes |
|---|---|---|
| CloudEvent JSON schemas (compute-node messages) | `cyoda-help.sh cloudevents json` | One JSON map; pick one: `\| jq '.schemas["processing/EntityCriteriaCalculationResponse.json"]'` |
| gRPC service `.proto` | `cyoda-help.sh grpc proto` | Proto text, printed as is. `cyoda-help.sh grpc json` gives the descriptor set as JSON. When the answer is about a compute-node message, say the node's gRPC stubs are generated from this proto in the developer's language |
| REST API (OpenAPI 3.1) | `cyoda-help.sh openapi json` (or `openapi yaml`) | About 0.5 MB; pick one path: `\| jq '.paths["/entity/{entityId}"]'`. Tags: `cyoda-help.sh openapi tags` |

These are actions, not topics: the output is printed verbatim (JSON or text) and `--section` is rejected (exit 6). `cyoda-help.sh workflows schema-version versions` is another, printing `{"current", "supported"}`.

## Known help errata (v0.8.4)

Filed as Cyoda/cyoda-go#684. When an answer touches one of these, give the correct fact and cite the item:

| Item | Help says | Fact |
|---|---|---|
| B | `workflows` PROCESSORS: the node must declare *all* `calculationNodesTags` | Overlap: any one shared tag. Use `grpc --section "TAG ROUTING"` |
| C | `crud` PATCH: `{}` is "consistent with PUT-with-empty-body" | A PUT with an empty body is 400. Fire a transition without changing data with PATCH `{}`, `If-Match: *`, `application/merge-patch+json` |
| I | `workflows` IMPORT REQUEST / EXPORT RESPONSE say nothing on strictness | Import rejects unknown fields; an export (`{entityName, modelVersion, workflows}`) must be reshaped to `{importMode, workflows}` before re-import |
| J | `responseTimeoutMs` `0` means "node default" | `0` means the server default of 30 s |
| A | `helm` CHART REPOSITORY: chart unpublished, 0.1.0 | Published at `https://cyoda.github.io/cyoda-go` |
| E, F, H | `config` Profile loader, `audit` ENDPOINTS `eventType` list, `helm` VALUES | Incomplete or wrong. Don't answer from these sections alone: say so and check a second source (`run` for env files; `workflows` SCHEDULED TRANSITIONS for the `SCHEDULED_TRANSITION_*` audit events) |

## Answering

End with the source: "From `cyoda help <topic>` § `<SECTION>` (`<SOURCE>`, v`<VERSION>`)." If the `cyoda-status.sh` warning says the binary and instance versions differ, the instance's help wins.

## Out of scope

| Question | Answer |
|---|---|
| SQL, Trino, analytics, reporting queries | "SQL analytics is not available in cyoda-go `<VERSION>`." Help's `analytics` topic describes an interface cyoda-go doesn't serve: don't answer from it. Write the concrete request for the developer's report (method, path and JSON body): grouped statistics from `crud --section ENDPOINTS`, or search from `search --section ENDPOINTS` with the condition from `search --section "CONDITION DSL"` |
| Notifications, alerts, webhooks on state entry | "Notifications are coming soon — check `cyoda help` for availability." |
| Any other feature that help doesn't document | "Not available in cyoda-go `<VERSION>` — check `cyoda help`." |
