#!/usr/bin/env bash
# UserPromptSubmit — inject the current chain (or a one-line nudge to start one) as context,
# so Claude actually uses step-status instead of waiting to be asked. Never fails.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat 2>/dev/null || true)"
CWD="$(STEP_INPUT="$INPUT" python3 -c 'import json,os
try: print(json.loads(os.environ["STEP_INPUT"] or "{}").get("cwd") or "")
except Exception: print("")' 2>/dev/null || true)"
[[ -n "$CWD" ]] || exit 0
LINE="$(STEP_STATUS_DIR="$CWD/.step-status" bash "$HERE/steps.sh" render 2>/dev/null)"
STEPS="bash \"$HERE/steps.sh\""
if [[ -n "$LINE" ]]; then
  echo "[step-status] chain: $LINE — on every phase transition run $STEPS done|start <step> and quote the echoed line on its own line; \`clear\` when finished."
else
  echo "[step-status] if this turn starts work with 2+ phases, run $STEPS set <phase>... first, then quote the echoed chain on its own line at every transition."
fi
exit 0
