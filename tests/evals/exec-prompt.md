You are an eval executor for a Claude Code skill. Run the skill against one eval prompt and write a transcript. Do not dispatch subagents.

Skill: {{REPO}}/cyoda/skills/{{SKILL_NAME}}/SKILL.md (read it and any files it references). `${CLAUDE_PLUGIN_ROOT}` = {{REPO}}/cyoda.
Eval: eval id {{N}} in {{REPO}}/cyoda/skills/{{SKILL_NAME}}/evaluations/evals.json ({{ITERATION}}) — use its `prompt` as the user's message. Do NOT read its `expected_output` or `assertions`; behave as the skill directs.

Environment (already set up for you; this is REAL, not simulated):
- Project directory: {{OUT}}/project — it contains the eval's fixture files. Work with this as the current directory (`cd` into it for every command). You may create/modify files inside it as the skill directs.
- If {{OUT}}/plugin-config.json exists, a real throwaway cyoda-go instance is running for this eval and the active profile points at it. ALWAYS run helper scripts with `CYODA_PLUGIN_CONFIG={{OUT}}/plugin-config.json` set (if the file doesn't exist, no profile is configured). Never read or touch ~/.config/cyoda.
- The eval's `_simulated/*` entries describe the starting state and the developer's answers (endpoints in them may differ from the real one — use the profile). When the skill asks the developer something, answer as they say, or with a short plausible reply consistent with the prompt.
- Run for real: the plugin's helper scripts (`${CLAUDE_PLUGIN_ROOT}/scripts/*.sh`), read-only `cyoda help …`, jq/envsubst/file operations in the project dir, and API calls through cyoda-call.sh. Paste real outputs.
- Never run: brew, cyoda init/serve, docker, helm install/upgrade, kubectl, openssl key generation, or anything outside the project dir and the instance. If the skill calls for one of these, write the command as SIMULATED.

Write the transcript to {{OUT}}/transcript.md: the user prompt, then each step in order (what you read, commands with their real output — mark any simulated ones — and messages to the developer), ending with your final message. Also list the files you created or changed in the project dir. Then reply only "done".
