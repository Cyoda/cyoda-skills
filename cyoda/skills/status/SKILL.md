---
name: status
description: Use when the developer asks whether Cyoda is connected, which cyoda-go instance, profile or version is active, or why the connection fails; at the start of Cyoda work; and before an operation that needs a running cyoda-go instance.
allowed-tools: Bash(*cyoda-status.sh*)
---

# Cyoda connection status

Read-only. One script call, one status line, then the warnings.

## Steps

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. Don't read the config or curl the instance yourself, and don't run the profile's `tokenCommand`: the script probes the public `/api/help` only.
2. Its first line is `STATUS=<s> PROFILE=<P> ENDPOINT=<E> ENV=<env> VERSION=<V> BINARY_VERSION=<B>`. Report exactly one line:

| `STATUS` | Report |
|---|---|
| `connected` | `Connected to cyoda-go v<V> — <E> [profile: <P>]` |
| `unreachable` | `cyoda-go unreachable — <E> [profile: <P>]` |
| `not_configured` | `Not connected — type /cyoda:setup` |

   - Append ` [PRODUCTION]` to a `connected` or `unreachable` line when `ENV=production`.
   - `VERSION=unknown`: write `version unknown` in place of `v<V>`.
   - `<V>` is the instance's version. `BINARY_VERSION` is the local `cyoda` binary; don't report it as the instance version.
3. Print **every** `WARN=` line after the status line, as it is, one per line, prefixed `Warning: `. Don't drop, merge or reword them. The texts the script emits:
   - `active profile <P> is unreachable; run /cyoda:setup to switch to default`
   - `no saved profile; using the default local instance <E> — type /cyoda:setup to save it` (no config file: `PROFILE=default` is implicit)
   - `no cyoda-go is answering at <E> — type /cyoda:setup to install or start one` (the implicit default is unreachable)
   - `local cyoda <B> differs from instance <V>; help is read from the instance`
   - `profile <P> contains a stored token, which this plugin no longer reads; you can remove it`

Nothing else: don't switch profiles, edit the config, install or upgrade anything. When a fix needs a side effect, say which command to type: "type `/cyoda:setup`" (connection, profile switch) or "type `/cyoda:auth`" (token). Never say you'll invoke them.

## Examples

```
Connected to cyoda-go v0.8.4 — http://localhost:8080 [profile: default]
```

```
Connected to cyoda-go v0.8.4 — http://localhost:8080 [profile: default]
Warning: no saved profile; using the default local instance http://localhost:8080 — type /cyoda:setup to save it
```

```
Connected to cyoda-go v0.8.4 — https://cyoda.example.com [profile: prod] [PRODUCTION]
Warning: local cyoda 0.9.0 differs from instance 0.8.4; help is read from the instance
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Labels such as "Local cyoda-go" | Every instance is `cyoda-go`; production is the `[PRODUCTION]` tag only |
| Reporting `BINARY_VERSION` as the version | Report `VERSION` (from the instance) |
| Showing only the first warning | Print every `WARN=` line |
| Running the tokenCommand or an authenticated call | Not needed: `/api/help` is public |
| A Cloud or migration question | Reply only "That's not covered by this plugin." Don't name or describe the product or offer alternatives for it |
