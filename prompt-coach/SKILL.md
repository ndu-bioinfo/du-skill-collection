---
name: prompt-coach
description: |
  Toggle and manage prompt-coach, an advisory prompt-quality coaching layer. Use when
  the user types "/prompt-coach", "/prompt-coach ON", "/prompt-coach OFF",
  "/prompt-coach status", "/prompt-coach summary", asks to turn prompt coaching on/off,
  or wants a session summary for training material.
triggers:
  - prompt-coach
  - prompt coaching
  - coach summary
  - coaching layer
  - turn on coaching
  - turn off coaching
---

# prompt-coach

An **advisory** prompt-quality coaching layer. When ON, it reviews each user prompt and
surfaces one inline coaching line — teaching, never blocking. It runs entirely on hooks;
no subprocess, ~0 added latency.

**Session-scoped:** it is turned on per Claude Code session — never globally.
Enabling it in one session leaves every other session (and every other repo) untouched.

## What it does (when ON)

- **Prompt coaching** (`UserPromptSubmit`): hands the rubric to the main model as added
  context; on a substantive prompt the model surfaces one `🧭 coach:` line — a fix for a
  real problem, else a concrete "even better:" lift when a real omission exists, else a
  brief "prompt is clear — <why>" tight-ack (a first-class outcome, never a manufactured
  lift). Contentless/procedural turns get no line unless a safety rule fires. The full
  rubric is injected **once per session** (a marker file guards it) so it becomes a stable,
  cacheable prefix; later turns inject only a tiny reminder. Live token/cache telemetry is
  surfaced as a `systemMessage` (user-visible, **out of the model's context**), not
  injected — so it never bloats context. It gives general prompting best-practice:
  the always-on `judge` + `prompting` + `safety` rules, plus `references/caching.md` on a
  token/cache signal.
- **Off-context worklog** (`Stop`): after each turn, appends one JSONL record to the CWD
  worklog `./.prompt-coach/coach-<session>.jsonl` — the `🧭` line, the (scrubbed)
  triggering prompt, a **semantic context breakdown** (system+tools / conversation /
  tool-results+file-reads / coach, estimated from the transcript against the ground-truth
  total), and cache stats with a `chain_break` flag. This keeps feedback + telemetry on
  disk instead of in the model's context. The dir self-ignores in git (it carries its own
  `.gitignore: *`). Prompts are scrubbed for structured secrets/PII before they hit disk.
- **Session summary** (`/prompt-coach summary`): on demand, ingests **both** the worklog
  (context/cache dynamics + logged feedback) and the session transcript (conversation +
  tool flow), cross-references them, and writes four-section training material —
  prompting patterns, workflow patterns, context-window management (with a chart +
  chain-break causes), and coaching notes — into the CWD-local `./.prompt-coach/` dir
  (`coach-summary-<date>-<session>.{md,html}`). It self-ignores via `.gitignore: *`, so
  summaries are never committed. Add `--debug` to also emit a separate coach
  self-improvement file (`coach-suggestions-…`), **off by default**.

It ships **OFF** (no flag) — zero behavior change until turned on.

## Toggle it

Run the toggle script that sits next to this file, passing the requested state. It
auto-detects the current session from `$CLAUDE_CODE_SESSION_ID`, so it toggles
**only this session**:

```bash
bash "$(dirname "$0")/scripts/toggle.sh" ON        # enable for THIS session
bash "$(dirname "$0")/scripts/toggle.sh" OFF       # disable for THIS session
bash "$(dirname "$0")/scripts/toggle.sh" status    # show current session's state
```

When the arg is `summary` (optionally `summary --debug`), do NOT run `toggle.sh`;
instead follow `references/summary.md` to produce the session summary. Plain `summary`
writes only the trainee summary; `summary --debug` also writes the coach
self-improvement file (default off). All other args (`ON`, `OFF`, `status`) map to
`scripts/toggle.sh`.

When invoked as `/prompt-coach <ARG…>`, map the args (case-insensitive) to `ON`, `OFF`,
or `status` (default `status` when no argument is given) and run `scripts/toggle.sh`
with them, then report the output. The toggle writes/removes a per-session flag file
`$COACH_STATE_DIR/<session_id>.enabled`; the hooks read the matching flag for their
session on every call.

## Wiring the hooks

Installed as a plugin (`/plugin install prompt-coach@du-skill-collection`) the two hooks in
`hooks/hooks.json` load automatically. With the symlink install, `install.sh` wires them
into `settings.json`; to do it by hand, copy `hooks/hooks.json` and replace
`${CLAUDE_PLUGIN_ROOT}` with this skill's absolute path.

Without the hooks wired, the toggle and summary still run, but no inline `🧭` line appears.

## References

`scripts/_common.sh:coach_build_context` assembles the coaching context dynamically,
loading only the files a given prompt needs.

**Runtime coaching context** (injected into the main model's turn; rules only):

- `references/judge.md` — the judge shell: role, inline output contract, calibration. Always.
- `references/prompting.md` — common prompt-quality checks. Always.
- `references/safety.md` — safety tier (secrets, destructive ops, fabrication, injection), verify, tone. Always.
- `references/caching.md` — token/prompt-cache economy. Included in the one-time rubric.

**Background maintainer references** (never loaded at runtime):

- `references/ref-prompting.md` — distilled general prompt-engineering practice.
- `references/ref-ux.md` — the coach's own UX rules of thumb.

## Tuning

- The coach writes a **local-only** per-turn worklog to `./.prompt-coach/` (CWD) via the
  `Stop` hook. It never leaves the machine. Delete `./.prompt-coach/` to clear it.
  `/prompt-coach summary` reads it (plus the transcript) on demand.
- The worklog prompt scrub (`COACH_SCRUB` in `scripts/_common.sh`) redacts structured
  secrets/PII before writing to disk. Extend its regex set there if an identifier slips through.
