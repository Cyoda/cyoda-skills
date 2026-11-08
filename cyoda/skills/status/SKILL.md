---
name: status
description: Use when the developer asks whether Cyoda is connected, which cyoda-go instance, project binding, profile or version is active, or why the connection fails; at the start of Cyoda work; and before an operation that needs a running cyoda-go instance.
allowed-tools: Bash(*cyoda-status.sh*)
---

# Cyoda connection status

## Steps

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. It probes the public `/api/help`, so no token is needed. If it exits non-zero (an invalid config file or `projects` entry, or `CYODA_PROFILE` naming a profile that doesn't exist), show its stderr as it is and stop.
2. Its first line is `STATUS=<s> PROFILE=<P> ENDPOINT=<E> VERSION=<V> BINARY_VERSION=<B> SOURCE=<src>`, plus ` PROJECT=<dir>` when `SOURCE=project`. `PROFILE` is in double quotes when it holds a space or a quote (`PROFILE="my shop"`; report it without the quotes, `\"` as `"`). `PROJECT` is always last and runs to the end of the line. Report exactly one line:

| `STATUS` | Report |
|---|---|
| `connected` | `Connected to cyoda-go v<V> — <E> <TAG>` |
| `unreachable` | `cyoda-go unreachable — <E> <TAG>` |
| `not_configured` | `Not connected — type /cyoda:setup` |

   - `<TAG>` comes from `SOURCE`: `project` → `[project: <P>]`; `profile` or `default` → `[profile: <P>]`.
   - `VERSION=unknown`: write `version unknown` in place of `v<V>`.
   - `<V>` is the instance's version; `BINARY_VERSION` is the local `cyoda` binary.
3. After the status line, print each `WARN=<text>` line as `Warning: <text>`.
4. If `STATUS` is `unreachable` or `not_configured`, or a `WARN=` line is present, and no printed line names `/cyoda:setup`, end with "next, type `/cyoda:setup`".

## Examples

```
Connected to cyoda-go v0.8.4 — http://localhost:8080 [profile: default]
Warning: no saved profile; using the default local instance http://localhost:8080 — type /cyoda:setup to save it
```

```
Connected to cyoda-go v0.8.4 — http://localhost:8082 [project: shop]
```
