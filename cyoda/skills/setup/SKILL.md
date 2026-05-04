---
name: setup
description: Provision a Cyoda instance. Two modes — local (install and start cyoda-go) or cloud (configure connection to Cyoda Cloud). Run this first before any other cyoda skills.
allowed-tools: Bash(brew *) Bash(cyoda *) Bash(curl *) Bash(mkdir *) Bash(tee *) Bash(grep *) Bash(cat *) Bash(jq *)
---

## Cyoda Instance Setup

Are you setting up a **local** cyoda-go instance or connecting to **Cyoda Cloud**?

Wait for the user to choose, then follow the appropriate path.

---

### Local cyoda-go

**Step 1 — Check if already installed:**
```!
which cyoda 2>/dev/null && cyoda --version 2>/dev/null || echo "NOT_INSTALLED"
```

If already installed, skip to Step 4 (start and verify).

**Step 2 — Install via Homebrew:**

Attempt each command in sequence:

```bash
brew tap cyoda-platform/cyoda-go
```

```bash
brew install cyoda
```

If **either command fails** (non-zero exit, permission error, Homebrew not found — any error at all):
- Do NOT attempt to diagnose or fix Homebrew.
- Do NOT run `brew doctor`, `sudo`, or any remediation.
- Do NOT add any advice, context, or extra commands to the message below.
- Show the user this message VERBATIM — copy it exactly:

> "I couldn't complete the installation — this usually needs to run in your own terminal. Please run these commands and let me know when they're done:
> ```bash
> brew tap cyoda-platform/cyoda-go
> brew install cyoda
> ```"

Wait for the user to confirm before continuing to Step 3.

If Homebrew is not available at all, check https://docs.cyoda.net/ for alternative installers.

**Step 3 — Initialize (first time only):**

```bash
cyoda init
```

This creates SQLite storage at `~/.local/share/cyoda/cyoda.db` and writes a starter config.

**Step 4 — Start the server:**

```bash
cyoda
```

The server runs in the foreground. Open a new terminal for subsequent commands.

**Step 5 — Verify:**
```!
curl -sf --max-time 5 http://localhost:8080/readyz 2>/dev/null || curl -sf --max-time 5 http://localhost:9091/readyz 2>/dev/null || echo "UNREACHABLE"
```

If `UNREACHABLE`: ask the user to start cyoda in a separate terminal with `cyoda` and try again.

**Step 6 — Write config:**

```bash
mkdir -p .cyoda
echo '{"endpoint": "http://localhost:8080", "env": "development"}' | jq . > .cyoda/config
grep -qxF '.cyoda/config' .gitignore 2>/dev/null || echo '.cyoda/config' >> .gitignore
grep -qxF '.cyoda/' .gitignore 2>/dev/null || echo '.cyoda/' >> .gitignore
```

Confirm: **"Local cyoda-go is running. REST on port 8080, gRPC on port 9090. `/cyoda:auth` is not needed for local — mock auth is active."**

---

### Cyoda Cloud

**Step 1 — Check for existing account and environment:**

Ask: *"Do you have a Cyoda Cloud account and environment? If not, go to [Cyoda AI Studio](https://ai.cyoda.net/) and ask it to:*
- *'create a new environment' — to provision a fresh environment*
- *'list my environments' — to see what you already have*
- *'redeploy environment X' — to redeploy an existing one*

*AI Studio will give you an endpoint URL once the environment is ready."*

Wait for confirmation.

**Step 2 — Collect endpoint URL:**

Ask: *"What is your Cyoda Cloud endpoint URL? (e.g., https://client-1edf4e3da14e497baf58d3aeb621ac40-dev.eu.cyoda.net)"*

**Step 2b — Verify endpoint is reachable:**

```bash
HTTP_CODE=$(curl -s --max-time 5 --output /dev/null --write-out "%{http_code}" "${USER_ENDPOINT}/readyz" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "000" ]; then
  echo "ENDPOINT_UNREACHABLE"
fi
```

If `ENDPOINT_UNREACHABLE`: *"Cannot reach that endpoint. Check the URL and your network connection, then try again."* Stop.

**Step 3 — Write endpoint to config:**

```bash
mkdir -p .cyoda
# Claude substitutes the endpoint URL the user provided
echo "{\"endpoint\": \"<USER_PROVIDED_ENDPOINT>\"}" | jq . > .cyoda/config
grep -qxF '.cyoda/config' .gitignore 2>/dev/null || echo '.cyoda/config' >> .gitignore
grep -qxF '.cyoda/' .gitignore 2>/dev/null || echo '.cyoda/' >> .gitignore
```

**Step 4 — Prompt for auth:**

*"Endpoint saved. Now run `/cyoda:auth` to authenticate and obtain your JWT token."*

After login, verify connectivity:
```bash
curl -sf --max-time 5 \
  -H "Authorization: Bearer $(jq -r '.token // ""' .cyoda/config)" \
  "$(jq -r '.endpoint' .cyoda/config)/readyz" || echo "Check your endpoint and token"
```
