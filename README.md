# du-skill-collection

A personal collection of [Claude Code](https://claude.com/claude-code) skills —
reusable, distilled lessons from real agent sessions. Each skill lives in its own
directory with a `SKILL.md` that Claude loads when its trigger conditions match.

## Skills

| Skill | What it does |
|-------|--------------|
| [pptx-flowchart-design](pptx-flowchart-design/SKILL.md) | Building flowcharts in `.pptx` via python-pptx — layout grid, arrow patterns, OOXML gotchas that cause PowerPoint "repair" prompts, and safe editing. |
| [pptx-slide-design](pptx-slide-design/SKILL.md) | Designing `.pptx` slides via python-pptx — layout, typography, and composition patterns that read as intentional rather than auto-generated. |
| [prompt-coach](prompt-coach/SKILL.md) | An advisory, session-scoped prompt-quality coaching layer. Surfaces one inline `🧭 coach:` tip per turn, keeps an off-context worklog, and produces on-demand session summaries. Hooks-based; ships **OFF**. |

## Quick start

Clone, then install all skills (symlinks them into `~/.claude/skills/`):

```bash
git clone https://github.com/ndu-bioinfo/du-skill-collection.git
cd du-skill-collection
./install.sh
```

Restart Claude Code (or open a new session) and the skills are available. This
also wires prompt-coach's hooks into your `settings.json` automatically — nothing
else to set up. (Pass `--no-hooks` to skip that.)

## Install / uninstall

`install.sh` and `uninstall.sh` handle batch or individual skills. They use
**symlinks**, so a later `git pull` updates every installed skill in place.

```bash
./install.sh                      # install ALL skills
./install.sh prompt-coach         # install one
./install.sh pptx-slide-design pptx-flowchart-design   # install several
./install.sh --list               # list available skills
./install.sh --no-hooks           # install without wiring prompt-coach's hooks

./uninstall.sh                    # remove ALL skills installed from this repo
./uninstall.sh prompt-coach       # remove one
```

Both are **idempotent** and safe: they only ever touch symlinks pointing back into
this repo — a real directory or a symlink to somewhere else is left untouched.

Custom locations (e.g. for testing) via env vars:

```bash
CLAUDE_SKILLS_DIR=~/some/dir CLAUDE_SETTINGS=~/some/settings.json ./install.sh
```

## prompt-coach hooks

Most skills are pure `SKILL.md` docs and work as soon as they're symlinked.
**prompt-coach is different** — it runs on Claude Code hooks, which must be wired into
your `settings.json` to fire. `install.sh` does this automatically whenever prompt-coach
is installed (wiring the `UserPromptSubmit` + `Stop` hooks); pass `--no-hooks` to skip it.

Then enable it per session (it ships OFF and is session-scoped):

```
/prompt-coach ON        # turn coaching on for this session
/prompt-coach status
/prompt-coach summary   # write a session lookback to ./.prompt-coach/
/prompt-coach OFF
```

`uninstall.sh prompt-coach` removes only the hook entries that point back into this
repo, leaving the rest of your `settings.json` intact. To wire the hooks by hand
instead, see [`prompt-coach/hooks.json`](prompt-coach/hooks.json).

## Layout

```
<skill-name>/
  SKILL.md            # required — YAML frontmatter + guidance
  references/         # optional — longer docs the skill pulls in on demand
  scripts/            # optional — helper scripts (e.g. prompt-coach's hooks)
  assets/             # optional — templates, snippets, sample files
install.sh            # symlink skills into ~/.claude/skills/
uninstall.sh          # remove them
```

Skill names are kebab-case and match the frontmatter `name:`.

### SKILL.md frontmatter

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
non-obvious gotchas that make it worth remembering.

## Adding a new skill

1. Create `<skill-name>/SKILL.md` with the frontmatter above.
2. Write the body from real session experience — what tripped you up, what patterns
   worked. Skip generic advice.
3. Add a row to the Skills table above.
4. Commit. `install.sh` will pick it up automatically (it discovers any dir with a
   `SKILL.md`).

Skills are distilled from things that already went wrong or right — don't write
speculative ones.
