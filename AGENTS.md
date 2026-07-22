# Agent and contributor guide

Rules and conventions for working in `du-skill-collection` — a collection of Claude Code
skills. Read this before making changes. See [README.md](README.md) for user-facing docs.

## Git workflow

- **Never push directly to `main`.** Do all work on a branch, open a PR, then merge.
  `main` is the public, released branch.
- Branch names: short, kebab-case, describing the change (e.g. `add-agents-md`,
  `fix-install-symlink`).
- End every commit message with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Releases are cut with `gh release create` on `main`, semver-tagged (`vMAJOR.MINOR.PATCH`).
  Bump: new skill or install/UX change → minor; fixes → patch.
- This repo is **public**. Never commit secrets, credentials, or PII. Scan before
  publishing (`grep -rniE '/Users/|@|AKIA|sk-|BEGIN .*KEY'`).

## Repo conventions

- Each skill is a top-level **kebab-case** directory containing a `SKILL.md`. The
  directory name must match the frontmatter `name:`.
- `SKILL.md` frontmatter is `name` + `description` (lead with WHEN to use it) +
  optional `triggers`. Body is task-focused Markdown — what to do, what not to do,
  the non-obvious gotchas. See existing skills for the shape.
- Optional per-skill subdirs: `references/` (docs pulled in on demand), `scripts/`
  (helpers), `assets/` (templates/samples).
- Skills are **distilled from real sessions** — things that already went wrong or
  right. Don't write speculative skills or generic advice.
- `install.sh` auto-discovers skills (any dir with a `SKILL.md`). Adding a skill needs
  no installer change — just add a row to the README skill table.

## Common tasks

- **Install / uninstall** (symlink-based, from repo root):
  `./install.sh` (all) · `./install.sh <skill>…` (specific) · `./install.sh --list` ·
  `./install.sh --with-hooks prompt-coach` · `./uninstall.sh [<skill>…]`.
- **Test install/uninstall without touching your real config** — point them at a
  throwaway dir:
  `CLAUDE_SKILLS_DIR=$(mktemp -d) CLAUDE_SETTINGS=$(mktemp -d)/settings.json ./install.sh …`
- **prompt-coach checks:**
  `python3 prompt-coach/scripts/render_worklog.py --selfcheck` and
  `for s in prompt-coach/scripts/*.sh; do bash -n "$s"; done`.

## Troubleshooting / gotchas

- **prompt-coach hook scripts must run under `bash`, not `zsh`.** They rely on
  `BASH_SOURCE` for path resolution; the interactive shell here is zsh, so `source`-ing
  them directly resolves paths wrong. Claude Code invokes hooks via `bash "…"`, and the
  install/test commands use `bash -c`, so real use is fine — just don't `source` them in zsh.
- **Hook scripts never hard-fail.** They `exit 0` on any error and are gated by a
  per-session enable flag, so a broken coach can never block a user's prompt. Keep it
  that way when editing `prompt-coach/scripts/`.
- **prompt-coach only coaches once its hooks are wired** into `~/.claude/settings.json`
  (`./install.sh --with-hooks prompt-coach`). Symlinking alone gives you the toggle +
  summary skill but no inline `🧭 coach:` line.
- **Installers only touch symlinks pointing back into this repo.** A real directory or a
  foreign symlink at the target is left alone (by design) — don't "fix" that guard.
- The `./.prompt-coach/` worklog dir self-ignores (`.gitignore: *`) — never commit it.
