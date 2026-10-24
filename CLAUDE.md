# agent-skills

This repo contains the **Cyoda Claude Code plugin** — a set of skills that help developers build, test, and run applications on Cyoda.

Design specs (source of truth changed date): `docs/superpowers/specs/*`

## Skill authoring

When creating or editing skills, invoke the `superpowers:writing-skills` skill first.

Each skill lives in its own directory under `skills/` with:
- `SKILL.md` — required frontmatter: `name`, `description`, and `disable-model-invocation: true` for skills with side effects
- `evaluations/` — 3+ JSON eval files covering happy path, edge case, and failure scenario
- Optional: `examples/`, `templates/`, `resources/`

Rules that are easy to get wrong:
- `SKILL.md` files stay under 500 lines — reference supporting files rather than embedding content inline
- Never embed Cyoda docs in skill bodies — `cyoda:docs` fetches them dynamically at runtime
- Skills with side effects (`setup`, `build`, `test`, `app`, `deploy`, `auth`) must have `disable-model-invocation: true`
- Shared helpers live in `cyoda/scripts/`. Skills invoke them with a plain instruction "Run `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`" (substituted in skill markdown). Do not rely on ```! blocks expanding `${CLAUDE_PLUGIN_ROOT}` (not verified: the probe could not run in the sandbox).

## Running evals

Evals live in `cyoda/skills/<skill>/evaluations/evals.json`. Results go in `cyoda-evals-workspace/iteration-N/<skill>/eval-<id>/with_skill/` (one `iteration-N` per run session). Tooling and prompt templates: `tests/evals/` (see its README).

**Skill-creator path** (`SC` below): `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator/`

### Process

1. **Instance per eval.** Anything the skill does to an instance runs against a real throwaway cyoda-go: `bash tests/evals/start.sh <id> [jwt]`, then `python3 tests/evals/setup.py iteration-N <skill> <eval> <id> [--seed-project]`. Simulate the instance (`setup.py … none`, `*-sim.md` prompts) only when the fixture needs specific entity ids/histories or a compute node. Help lookups always run for real.
2. **Executors** (one per eval, all in parallel, background): prompt from `bash tests/evals/prompt.sh exec-prompt[-sim].md iteration-N <skill> <eval>`. Each writes `with_skill/outputs/transcript.md`. When its task notification arrives: `bash tests/evals/timing.sh iteration-N <skill> <eval> <total_tokens> <duration_ms>`.
3. **Graders** (one per eval, all in parallel, after the executors): prompt from `prompt.sh grade-prompt[-sim].md …`. Each saves `grading.json` in the `with_skill/` directory, next to `timing.json`.
4. `bash tests/evals/stop.sh` (expect "still listening: 0").
5. **Aggregate and view:**
```bash
SC=~/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator
W="$PWD/cyoda-evals-workspace/iteration-N/<skill>"
for f in "$W"/eval-*/with_skill/grading.json; do   # the aggregator reads run-1/ and crashes on null metrics
  d="$(dirname "$f")"; mkdir -p "$d/run-1"
  jq '.execution_metrics.total_tool_calls //= 0 | .execution_metrics.output_chars //= 0' "$f" > "$d/g.tmp" && mv "$d/g.tmp" "$f"
  cp "$f" "$d/run-1/grading.json"
  cp "$d/timing.json" "$d/run-1/timing.json" 2>/dev/null || true
done
(cd "$SC" && python3 -m scripts.aggregate_benchmark "$W" --skill-name cyoda-<skill>)
python3 "$SC/eval-viewer/generate_review.py" "$W" --skill-name "cyoda:<skill>" \
  --benchmark "$W/benchmark.json" --static /tmp/cyoda-<skill>-review.html && open /tmp/cyoda-<skill>-review.html
```

## References

- Cyoda docs: https://docs.cyoda.net/
- OpenAPI: https://docs.cyoda.net/openapi/openapi.json
- Plugins guide: https://code.claude.com/docs/en/plugins
- Skills guide: https://code.claude.com/docs/en/skills.md

## Smoke tests

- `tests/smoke/run.sh [--only NN] [--allow-version]` — lint, script tests, then scenarios against a throwaway in-memory cyoda-go (needs v0.8.4)
- `tests/smoke/lint.sh` — stale-string lint over `cyoda/` (exit 1 on any hit; needs `shellcheck`)
- `tests/smoke/test-harness.sh` — tests for the harness itself
