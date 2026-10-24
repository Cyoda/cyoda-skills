You are an eval executor for a Claude Code skill. Run the skill against one eval prompt and write a transcript. Do not dispatch subagents.

Skill: {{REPO}}/cyoda/skills/{{SKILL_NAME}}/SKILL.md (read it and any files it references). `${CLAUDE_PLUGIN_ROOT}` = {{REPO}}/cyoda.
Eval: eval id {{N}} in {{REPO}}/cyoda/skills/{{SKILL_NAME}}/evaluations/evals.json ({{ITERATION}}) — use its `prompt` as the user's message. Do NOT read its `expected_output` or `assertions`; behave as the skill directs.

Environment:
- Project directory: {{OUT}}/project (the eval's non-simulated fixture files). Work with it as the current directory.
- The cyoda INSTANCE is SIMULATED for this eval: its state and the responses of every call to it (cyoda-status.sh, cyoda-profile.sh, cyoda-call.sh, curl to the instance) are described in the eval's `_simulated/instance.md` entry (and the profile file in {{OUT}}/plugin-config.json). Write each such command exactly as you'd run it, then the response consistent with instance.md, marked SIMULATED. Never invent instance state beyond what instance.md implies; if you need a response it doesn't cover, write a plausible one and mark it ASSUMED.
- Run FOR REAL, and paste the real output: read-only `cyoda help …` and `${CLAUDE_PLUGIN_ROOT}/scripts/cyoda-help.sh …` (always with `CYODA_PLUGIN_CONFIG=/nonexistent CYODA_DEFAULT_ENDPOINT=http://localhost:1` so help comes from the local binary), plus file reads in the project dir.
- Never run anything that changes state outside {{OUT}}.
- When the skill asks the developer something, answer with a short plausible reply consistent with the prompt and instance.md.

Write the transcript to {{OUT}}/transcript.md: the user prompt, then each step in order (what you read, commands with real or SIMULATED/ASSUMED output, messages to the developer), ending with your final message. Then reply only "done".
