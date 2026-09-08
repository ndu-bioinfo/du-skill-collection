---
name: step-status
description: |
  Show a live step chain in the Claude Code status line while running any multi-step
  workflow (a skill or task with two or more named phases such as init → loop → summary).
  Use whenever you start such a workflow, when the user asks for a status/progress
  indicator, or types "/step-status". Claude updates the chain by calling
  scripts/steps.sh at each phase transition; the status line renders it as
  `init ✓ → loop|check agent status ● → summary ○`.
triggers:
  - step-status
  - status line progress
  - show pipeline status
  - step chain
  - workflow progress indicator
---

# step-status

A step chain in the status line, driven by explicit CLI calls. Nothing is inferred:
you tell it the phases, then mark them as you go.

Symbols: `✓` done · `●` in progress · `○` planned · `✗` failed. An active step may carry
a detail after `|` (e.g. `loop|check agent status`).

## How to use (Claude)

`STEPS` below means `bash <this skill's dir>/scripts/steps.sh`. The Skill tool prints the
base directory of this skill when loaded; installed as a plugin it is
`${CLAUDE_PLUGIN_ROOT}`, as a symlinked skill it is `~/.claude/skills/step-status`. Run it
via the Bash tool from the project root — state lives in `./.step-status/state`
(self-ignoring, keyed by cwd).

1. **At the start** of a multi-step workflow, define the chain once. The first step
   becomes active:
   ```bash
   STEPS set init loop summary
   ```
2. **On each transition**:
   ```bash
   STEPS done init                          # ✓ init, auto-activates loop
   STEPS start loop "check agent status"    # optional detail → loop|check agent status ●
   STEPS done loop                          # ✓ loop, auto-activates summary
   STEPS fail summary                       # ✗ if a step blows up
   ```
3. **At the end**: `STEPS clear` — the chain disappears from the status line.

Rules:
- One `set` per workflow. Re-running `set` restarts the chain.
- `done X` activates the next *planned* step, so you rarely need `start` unless you
  want to attach a detail or skip ahead.
- Names with spaces are fine (quote them). Keep them short — it's a status bar.
- If the user asks "where are we?", run `STEPS render` and quote the line.

## What the user sees

```
init ✓ → loop|check agent status ● → summary ○
```

Rendered by `scripts/statusline.sh`, which `scripts/wire_statusline.sh` (called by
`./install.sh step-status`, or by you on `/step-status setup`) wires into `statusLine` in
`settings.json`: if a status line already exists (e.g. `ccstatusline`) it is **wrapped**
and the chain is appended as an extra line; otherwise the chain is the whole status line.
A `SessionStart` hook clears any chain left in the cwd from a previous session.

## One-time setup (`/step-status setup`)

Plugins cannot set `statusLine`, so when the user runs `/step-status setup` (or the chain
never appears in their status bar) run:

```bash
bash <this skill's dir>/scripts/wire_statusline.sh          # STEP_STATUS_NO_HOOK=1 when installed as a plugin (hook already shipped)
bash <this skill's dir>/scripts/wire_statusline.sh --unwire # undo
```

It auto-detects an existing status line command and wraps it, or installs standalone. It
refuses to touch a settings.json it cannot parse, and saves the original `statusLine` so
`--unwire` restores it exactly. Plugin installs live in a versioned cache dir, so the scripts
are copied to `~/.claude/step-status/bin` and settings point there: re-run setup after a
plugin update. Tell the user to restart Claude Code afterwards. `install.sh` (symlink install) runs this
for you. Hook manifest for reference: `hooks/hooks.json`.

## Checks

```bash
bash step-status/scripts/steps.sh --selfcheck
bash step-status/scripts/wire_statusline.sh --selfcheck   # settings.json wrap/unwire round trip
for s in step-status/scripts/*.sh; do bash -n "$s"; done
```

## Gotchas

- State is keyed by cwd, not session. Two Claude sessions in the same directory share
  (and clobber) one chain.
- The SessionStart hook clears the chain on `startup|clear` only; `/compact` and resume keep it.
- Step names must not be empty or contain tabs/newlines, and must be unique in a chain.
- The status line refreshes on Claude Code's own cadence (after assistant messages), so a
  `done` shows up a moment later, not instantly.
- `statusline.sh` never fails and prints nothing when no chain is set, so wrapping is
  invisible until a workflow calls `set`.
