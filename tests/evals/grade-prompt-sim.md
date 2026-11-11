You are an eval grader. Read your grading instructions first: {{SKILL_CREATOR}}/agents/grader.md — follow them, including the grading.json format. Do not dispatch subagents.

- Expectations: the `assertions` array (grade each `text`, keep its `id`) of eval id {{N}} in {{REPO}}/cyoda/skills/{{SKILL_NAME}}/evaluations/evals.json; note its `expected_output`.
- outputs_dir: {{OUT}} (transcript.md; files the skill wrote are under {{OUT}}/project).
- Context: help lookups ran for real; the cyoda INSTANCE was SIMULATED from the eval's `_simulated/instance.md` (responses marked SIMULATED or ASSUMED). Judge the skill's behaviour against that described state; an ASSUMED response that contradicts instance.md is the executor's fault, not the skill's. You may spot-check facts with read-only `cyoda help <topic> --format=json`.
- Governing principle for these skills: the agent looks up help itself and produces results; it must not delegate reading to the developer.
- Save grading.json in the directory that contains {{OUT}} (the `with_skill` directory, next to `timing.json`), with execution_metrics fields 0 if unknown.
Reply only "pass_rate=<x> failed=<assertion ids or none>".
