---
name: setup
description: Provision a Cyoda instance. Install and start a local cyoda-go. Run this first before any other cyoda skills.
allowed-tools: Bash(brew *) Bash(cyoda *) Bash(curl *) Bash(mkdir *) Bash(tee *) Bash(grep *) Bash(cat *) Bash(jq *)
disable-model-invocation: true
---

## Cyoda Instance Setup

Set up a local cyoda-go instance.

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

List existing profiles (if any):
```bash
jq -r '.profiles | keys[]' "$HOME/.config/cyoda/cyoda-plugin-config.json" 2>/dev/null || echo "(none yet)"
```

Ask: *"Which profile name should this connection be saved under? (e.g. `default`, `local`)"*

```bash
CONFIG_FILE="$HOME/.config/cyoda/cyoda-plugin-config.json"
mkdir -p "$HOME/.config/cyoda"
NEW_DATA='{"endpoint": "http://localhost:8080", "env": "development"}'
# Claude substitutes the profile name the user provided for PROFILE_NAME
EXISTING=$(cat "$CONFIG_FILE" 2>/dev/null || echo "{\"active\":\"${PROFILE_NAME}\",\"profiles\":{}}")
echo "$EXISTING" | jq --arg p "$PROFILE_NAME" --argjson data "$NEW_DATA" \
  '.profiles[$p] = $data | .active = $p' > "$CONFIG_FILE"
```

If the write fails with a permission error (`mkdir` fails or the redirect is denied): do NOT attempt `sudo`, `chmod`, `chown`, or any other fix. Show:

> *"Couldn't write to `~/.config/cyoda/` — you may be running in a sandbox or restricted environment. Please grant write access to that directory and try again. Would you like help with that?"*

Confirm: **"Local cyoda-go is running. REST on port 8080, gRPC on port 9090. `/cyoda:auth` is not needed for local — mock auth is active."**

---

### Existing instance

Connect to an existing instance — see Task 9.
