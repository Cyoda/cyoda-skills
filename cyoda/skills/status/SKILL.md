---
name: status
description: Use when the developer asks whether Cyoda is connected, which cyoda-go instance, project binding, profile or version is active, or why the connection fails; at the start of Cyoda work; and before an operation that needs a running cyoda-go instance.
allowed-tools: Bash(*cyoda-status.sh*)
---

# Cyoda connection status

Read-only. One script call, one status line, then the warnings.

## Steps

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-status.sh`. Don't read the config or curl the instance yourself, and don't run the profile's `tokenCommand`: the script probes the public `/api/help` only. If it exits non-zero (an invalid config file, or `CYODA_PROFILE` naming a profile that doesn't exist), show its stderr as it is and stop.
2. Its first line is `STATUS=<s> PROFILE=<P> ENDPOINT=<E> ENV=<env> VERSION=<V> BINARY_VERSION=<B> SOURCE=<src>`, plus ` PROJECT=<dir>` when `SOURCE=project`. `PROFILE` is in double quotes when it holds a space or a quote (`PROFILE="my shop"`; report it without the quotes, `\"` as `"`). `PROJECT` is always last and runs to the end of the line. Report exactly one line:

| `STATUS` | Report |
|---|---|
| `connected` | `Connected to cyoda-go v<V> — <E> <TAG>` |
| `unreachable` | `cyoda-go unreachable — <E> <TAG>` |
| `not_configured` | `Not connected — type /cyoda:setup` |

   - `<TAG>` comes from `SOURCE`: `project` → `[project: <P>]` (this project's `.cyoda/instance.json`; `<P>` is the project dir's name); `profile` or `default` → `[profile: <P>]`.
   - Append ` [PRODUCTION]` to a `connected` or `unreachable` line when `ENV=production`.
   - `VERSION=unknown`: write `version unknown` in place of `v<V>`.
   - `<V>` is the instance's version. `BINARY_VERSION` is the local `cyoda` binary; don't report it as the instance version.
3. Print **every** `WARN=` line after the status line, as it is, one per line, prefixed `Warning: `. Don't drop, merge or reword them. The texts the script emits:
   - `active profile <P> is unreachable; run /cyoda:setup to switch to default`
   - `project <P> is bound to <E>, which is unreachable; start that instance, or type /cyoda:setup to link this project to another one`
   - `<path>/.cyoda/config contains a stored token, which this plugin no longer reads; you can remove it` (legacy project file: only its endpoint and env are used)
   - `<path>/.cyoda/instance.json contains a stored token, which this plugin no longer reads; you can remove it`
   - `ignoring <path>/.cyoda/instance.json: <reason>` (or `…/.cyoda/config`), where `<reason>` is one of `symlink`, `.cyoda directory not owned by you`, `.cyoda directory is group- or world-writable (run chmod 700 on it)`, `not owned by you`, `group- or world-writable (run chmod 600 on it)`, `.cyoda is a git repository or submodule`, `tracked by git (run git rm --cached on it and keep .cyoda/ in .gitignore)`, `git could not check whether it is tracked`. The project binding is ignored entirely, so the line shows the machine-wide profile or the default (`SOURCE` is not `project`).
   - `no saved profile; using the default local instance <E> — type /cyoda:setup to save it` (no config file: `PROFILE=default` is implicit)
   - `no cyoda-go is answering at <E> — type /cyoda:setup to install or start one` (the implicit default is unreachable)
   - `local cyoda <B> differs from instance <V>; help is read from the instance`
   - `profile <P> contains a stored token, which this plugin no longer reads; you can remove it`

Nothing else: don't switch profiles, edit the config or `.cyoda/instance.json`, install or upgrade anything. When a fix needs a side effect, say which command to type: "type `/cyoda:setup`" (connection, profile switch) or "type `/cyoda:auth`" (token). Never say you'll invoke them.

## Examples

```
Connected to cyoda-go v0.8.4 — http://localhost:8080 [profile: default]
```

```
Connected to cyoda-go v0.8.4 — http://localhost:8080 [profile: default]
Warning: no saved profile; using the default local instance http://localhost:8080 — type /cyoda:setup to save it
```

```
Connected to cyoda-go v0.8.4 — http://localhost:8082 [project: shop]
```

```
Connected to cyoda-go v0.8.4 — https://cyoda.example.com [profile: prod] [PRODUCTION]
Warning: local cyoda 0.9.0 differs from instance 0.8.4; help is read from the instance
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Labels such as "Local cyoda-go" | Every instance is `cyoda-go`; production is the `[PRODUCTION]` tag only |
| `[profile: <P>]` for `SOURCE=project` | `[project: <P>]`: the project's binding wins over the machine-wide active profile |
| Reporting `BINARY_VERSION` as the version | Report `VERSION` (from the instance) |
| Showing only the first warning | Print every `WARN=` line |
| Running the tokenCommand or an authenticated call | Not needed: `/api/help` is public |
| A Cloud or migration question | Reply only "That's not covered by this plugin." Don't name or describe the product or offer alternatives for it |
