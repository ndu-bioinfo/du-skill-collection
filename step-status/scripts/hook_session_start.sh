#!/usr/bin/env bash
# SessionStart (matcher: startup|clear) — drop any step chain left behind in this cwd so a
# new session never shows a stale one. Not on resume/compact: those continue a workflow.
# Best-effort: always exits 0; does nothing if the cwd can't be read from the hook JSON.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
CWD="$(STEP_INPUT="$INPUT" python3 -c 'import json,os
try: print(json.loads(os.environ["STEP_INPUT"] or "{}").get("cwd") or "")
except Exception: print("")' 2>/dev/null || true)"
[[ -n "$CWD" && -d "$CWD/.step-status" && ! -L "$CWD/.step-status" ]] &&
  find "$CWD/.step-status" -maxdepth 1 -type f \( -name '*.state' -o -name '*.note' -o -name current \) -delete 2>/dev/null
exit 0
