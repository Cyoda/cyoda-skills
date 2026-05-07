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
- Skills with side effects (`setup`, `build`, `test`, `migrate`, `app`) must have `disable-model-invocation: true`

## Running evals

Evals live in `cyoda/skills/<skill>/evaluations/evals.json`. Results go in `cyoda-evals-workspace/iteration-N/`.

**Skill-creator plugin path:** `~/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator/`

### Process

**1. Spawn executor subagents** (one per eval, all in parallel, background):
- Read `SKILL.md` from the skill path
- Simulate the skill executing the eval prompt using fixture files from `files` block
- Write transcript to `cyoda-evals-workspace/iteration-N/<skill>/eval-<id>/with_skill/outputs/transcript.md`
- Capture `total_tokens` and `duration_ms` from task notification → save as `timing.json` in the same `with_skill/` dir

**2. Spawn grader subagents** (one per eval, all in parallel, background):
- Read grader instructions from `<skill-creator-path>/agents/grader.md`
- Grade each assertion in the eval's `assertions` array against the transcript
- Save `grading.json` to `with_skill/` (same dir as `timing.json`)

**3. Aggregate:**
```bash
# Fix null fields that crash the aggregator
for f in cyoda-evals-workspace/iteration-N/<skill>/eval-*/with_skill/grading.json; do
  jq '.execution_metrics.total_tool_calls //= 0 | .execution_metrics.output_chars //= 0' "$f" > /tmp/g.json && mv /tmp/g.json "$f"
  mkdir -p "$(dirname $f)/run-1"
  cp "$f" "$(dirname $f)/run-1/grading.json"
  cp "$(dirname $f)/timing.json" "$(dirname $f)/run-1/timing.json" 2>/dev/null || true
done

cd ~/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator
python3 -m scripts.aggregate_benchmark /path/to/cyoda-evals-workspace/iteration-N/<skill> --skill-name cyoda-<skill>
```

**4. Generate viewer:**
```bash
SC=~/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator
python3 "$SC/eval-viewer/generate_review.py" \
  cyoda-evals-workspace/iteration-N/<skill> \
  --skill-name "cyoda:<skill>" \
  --benchmark cyoda-evals-workspace/iteration-N/<skill>/benchmark.json \
  --static /tmp/cyoda-<skill>-review.html
open /tmp/cyoda-<skill>-review.html
```

### Notes
- Run all executor agents in the same turn (parallel background)
- Run all grader agents in the same turn after executors complete
- The aggregator expects `run-1/grading.json` inside each `with_skill/` dir — the fix loop above creates it
- One eval run = one `iteration-N` directory; increment N for each new run session

## References

- Cyoda docs: https://docs.cyoda.net/
- OpenAPI: https://docs.cyoda.net/openapi/openapi.json
- Plugins guide: https://code.claude.com/docs/en/plugins
- Skills guide: https://code.claude.com/docs/en/skills.md
