#!/usr/bin/env bash
# Resolve the current session's transcript path, the CWD worklog path, and the
# default summary output paths, for the /prompt-coach summary flow. Prints:
#   TRANSCRIPT=<path>   (raw session messages — always present)
#   WORKLOG=<path>      (per-turn context/feedback records — present if coach was ON)
#   OUTFILE / OUTFILE_HTML=<path>   (the trainee summary — always)
#   OUTFILE_COACH=<path>            (coach self-improvement notes — ONLY with --debug)
# The coach-improvement file is OFF by default; pass `--debug` to enable it. When it's
# off the OUTFILE_COACH line is simply not printed, so the flow produces only the
# trainee deliverable.
# Summaries are written to the CWD-local, self-ignoring `./.prompt-coach/` dir (same
# place as the worklog) — never a global/home location — so they stay next to the work
# and out of git. In a non-git dir it's just a local folder (the .gitignore is harmless).
# Exits 1 with a stderr message if it cannot locate the transcript. The worklog may
# not exist (coach was off / first run); the summary flow handles that case.
set -uo pipefail
DEBUG=0
for a in "$@"; do [[ "$a" == "--debug" ]] && DEBUG=1; done
SID="${CLAUDE_CODE_SESSION_ID:-}"
[[ -z "$SID" ]] && { echo "no CLAUDE_CODE_SESSION_ID — cannot locate transcript" >&2; exit 1; }
# Claude Code names the project dir by replacing EVERY non-alphanumeric char with
# '-' (e.g. /Users/name/... -> -Users-name-...), not just slashes.
ENC="$(printf '%s' "$PWD" | sed 's#[^a-zA-Z0-9]#-#g')"
TRANSCRIPT="$HOME/.claude/projects/$ENC/$SID.jsonl"
if [[ ! -f "$TRANSCRIPT" ]]; then
  # Fallback: search all project dirs for this session id.
  TRANSCRIPT="$(find "$HOME/.claude/projects" -name "$SID.jsonl" -type f 2>/dev/null | sort | head -1)"
fi
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && { echo "transcript not found for session $SID" >&2; exit 1; }
DATE="$(date +%Y-%m-%d)"
# CWD-local, self-ignoring worklog dir (Stop hook writes the worklog here; summaries
# land here too). Create it + its `*` .gitignore so output is git-ignored by construction
# in a repo, and just a local folder otherwise.
WLDIR="$PWD/.prompt-coach"
mkdir -p "$WLDIR" 2>/dev/null || true
[[ -f "$WLDIR/.gitignore" ]] || printf '*\n' >"$WLDIR/.gitignore" 2>/dev/null || true
WORKLOG="$WLDIR/coach-$SID.jsonl"
# Emit shell-QUOTED KEY=VALUE lines (printf %q — bash's shlex.quote) so the caller can
# `eval`/`source` this output safely even when a path contains spaces (e.g. a macOS home
# like /Users/John Doe/...). For space-free paths %q is a no-op, so output is unchanged.
printf 'TRANSCRIPT=%q\n'   "$TRANSCRIPT"
printf 'WORKLOG=%q\n'      "$WORKLOG"
printf 'OUTFILE=%q\n'      "$WLDIR/coach-summary-$DATE-$SID.md"
printf 'OUTFILE_HTML=%q\n' "$WLDIR/coach-summary-$DATE-$SID.html"
# Coach self-improvement notes are debug-only (default off). Emit the path only under
# --debug; otherwise the flow sees no OUTFILE_COACH and skips that deliverable.
[[ "$DEBUG" == 1 ]] && printf 'OUTFILE_COACH=%q\n' "$WLDIR/coach-suggestions-$DATE-$SID.md"
