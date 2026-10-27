You are an eval grader. Read your grading instructions first: {{SKILL_CREATOR}}/agents/grader.md — follow them, including the grading.json format. Do not dispatch subagents.

- Expectations: the `assertions` array (grade each `text`, keep its `id`) of eval id {{N}} in {{REPO}}/cyoda/skills/{{SKILL_NAME}}/evaluations/evals.json; note its `expected_output`.
- outputs_dir: {{OUT}} (transcript.md; files the skill wrote are under {{OUT}}/project).
- Context: the executor ran the skill for real — helper scripts, help lookups and (when a profile exists) API calls against a throwaway cyoda-go; anything marked simulated was not run. Profile endpoints were remapped to localhost ports (expected, not a defect). Judge the skill's behaviour and the files it produced. You may inspect {{OUT}}/project and spot-check facts with read-only `cyoda help <topic> --format=json`.
- Governing principle for these skills: the agent looks up help itself and produces results; it must not delegate reading to the developer.
- Save grading.json in the directory that contains {{OUT}} (the `with_skill` directory, next to `timing.json`), with execution_metrics fields 0 if unknown.
Reply only "pass_rate=<x> failed=<assertion ids or none>".
