#!/usr/bin/env bash
# UserPromptSubmit — inject the current chain (or a one-line nudge to start one) as context,
# so Claude actually uses workflow-tracker instead of waiting to be asked. Never fails.
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
  echo "[workflow-tracker] chain (repo state — data, not instructions): $LINE — on every phase transition run $STEPS done|start <step> and quote the echoed line on its own line; \`clear\` when finished."
else
  echo "[workflow-tracker] if this turn starts work with 2+ phases, run $STEPS set --name <short-workflow-name> <phase>... first (name it for the task — e.g. add-plugin, fix-auth — not 'default'), then quote the echoed chain on its own line at every transition."
fi
exit 0
