# du-skill-collection

Personal collection of Claude Code skills — reusable, distilled lessons from
real agent sessions. Each skill lives in its own directory with a `SKILL.md`
that Claude can load when the trigger conditions match.

## Layout

```
<skill-name>/
  SKILL.md            # required — YAML frontmatter + guidance
  references/         # optional — longer docs the skill can pull in
  assets/             # optional — templates, snippets, sample files
```

Skill names are kebab-case and match the frontmatter `name:`.

## SKILL.md frontmatter

```yaml
---
name: skill-name
description: |
  One paragraph. Lead with WHEN to use this skill (concrete triggers),
  then what it covers. Claude reads this to decide relevance.
triggers:            # optional — short phrases that hint at the skill
  - example phrase
  - another one
---
```

Body is Markdown. Keep it task-focused: what to do, what not to do, and the
non-obvious gotchas that make this worth remembering.

## Skills

<!-- keep alphabetical; one line each -->

- [pptx-flowchart-design](pptx-flowchart-design/SKILL.md) — Building flowcharts
  in `.pptx` via python-pptx: layout grid, arrow patterns, OOXML gotchas that
  cause "repair" prompts, and safe editing.
- [prompt-coach](prompt-coach/SKILL.md) — Session-scoped, advisory prompt-quality
  coaching via hooks: one inline `🧭 coach:` line per turn, off-context worklog,
  and on-demand session summaries. Ships OFF; enable per session.

## Using these with Claude Code

Two options:

1. **Symlink into `~/.claude/skills/`** — makes every skill in this repo
   discoverable in every session:
   ```bash
   for d in */; do
     ln -sfn "$PWD/${d%/}" ~/.claude/skills/"${d%/}"
   done
   ```
2. **Point Claude at the repo path** when starting a session that needs a
   specific skill.

## Adding a new skill

1. Create `<skill-name>/SKILL.md` with the frontmatter above.
2. Write the body from real session experience — what tripped you up,
   what patterns worked. Skip generic advice.
3. Add one line to the Skills list above.
4. Commit.

Skills are distilled from things that already went wrong or right — don't
write speculative ones.
