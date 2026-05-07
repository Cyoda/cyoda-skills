---
name: docs
description: Look up Cyoda documentation. Uses local `cyoda help` (version-specific, preferred for API details) with web docs as fallback. Synthesizes direct answers — never dumps raw output. Auto-invoked when Cyoda API questions arise.
when_to_use: When the user asks how to use a Cyoda API, what an endpoint does, how a concept works, or needs schema/protocol details.
allowed-tools: Bash(cyoda *) Bash(which *)
---

## Cyoda Documentation Lookup

Checking for local cyoda CLI:
```!
which cyoda 2>/dev/null && cyoda help 2>/dev/null | head -50 || echo "CYODA_CLI_NOT_INSTALLED"
```

**If output contains `CYODA_CLI_NOT_INSTALLED`:**

Ask the user once per session:

> *"Local `cyoda` CLI is not installed. It's recommended for development — run `/cyoda:setup` (local mode) to install it. Would you like to do that now, or should I use the online help at https://docs.cyoda.net/help/ to answer your question?"*

- If user wants to install: invoke `/cyoda:setup` (local mode), then re-invoke this skill.
- If user prefers online help (or already answered "no" earlier in this conversation): fetch `https://docs.cyoda.net/help/index.json` to discover available topics, then fetch `https://docs.cyoda.net/help/<slug>.md` for the relevant topic. URL mapping: `cyoda help A B C` → `https://docs.cyoda.net/help/a/b/c/`. This surface mirrors the CLI help and is designed for agent access.

**If cyoda CLI is installed:**

1. Use the `cyoda help` output above as the primary source to answer the user's question.
2. If the answer is not fully covered by local help, supplement with web docs: fetch `https://docs.cyoda.net/llms.txt` first to identify the relevant page, then fetch that page directly.
3. For gRPC/schema details, reference: https://github.com/Cyoda-platform/cyoda-docs/tree/main/src/schemas
4. For REST API details, reference: https://docs.cyoda.net/openapi/openapi.json

**Always:**
- Synthesize a direct, specific answer to the question asked
- Never paste raw `cyoda help` output without explanation
- Prefer local CLI output over web docs for API-level specifics
