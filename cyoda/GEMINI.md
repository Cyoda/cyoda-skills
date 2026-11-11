# Cyoda Gemini CLI Extension

Use the bundled Cyoda skills when building applications on Cyoda.

Cyoda applications are built around entities, workflows, criteria, processors, tests and local development conventions.

When the user asks to build, design, test, debug, deploy or document a Cyoda application, inspect the relevant skill in this extension's `skills/` directory before generating code.

`${CLAUDE_PLUGIN_ROOT}` in the skills means this extension's root directory (the directory containing this GEMINI.md). Gemini doesn't substitute it: replace it with that path when you run a referenced `scripts/*.sh` command.

Skills:

- `skills/app/SKILL.md` for the full journey, start to finish
- `skills/setup/SKILL.md` for installing and connecting to cyoda-go
- `skills/auth/SKILL.md` for tokens on an instance that isn't running mock auth
- `skills/design/SKILL.md` for entity and workflow design
- `skills/build/SKILL.md` for registering entity models and workflows
- `skills/compute/SKILL.md` for processors and compute nodes
- `skills/test/SKILL.md` for testing
- `skills/debug/SKILL.md` for debugging and entity history
- `skills/deploy/SKILL.md` for deploying to a self-hosted cyoda-go (Docker Compose, Helm)
- `skills/docs/SKILL.md` for documentation lookups
- `skills/status/SKILL.md` for checking the connection
