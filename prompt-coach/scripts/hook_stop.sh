#!/usr/bin/env bash
# Stop — after each assistant turn, append ONE worklog record to the CWD worklog:
# the context breakdown (semantic categories), cache stats + chain-break flag, the
# coach's 🧭 line, and the scrubbed prompt that triggered it. This is what takes
# feedback + telemetry OFF the model's context — nothing here is injected back into
# the conversation; it only writes to disk (`./.prompt-coach/coach-<session>.jsonl`).
#
# Non-blocking, best-effort: any failure exits 0 so the turn is never affected.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_common.sh" 2>/dev/null || exit 0

command -v python3 >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"; [[ -z "$INPUT" ]] && exit 0
eval "$(COACH_HOOK_JSON="$INPUT" python3 - <<'PY'
import json, os, shlex, sys
try: h = json.loads(os.environ.get("COACH_HOOK_JSON", "{}"))
except Exception: sys.exit(0)
vals = {"SESSION_ID": h.get("session_id", ""), "CWD": h.get("cwd", "") or os.getcwd(),
        "TRANSCRIPT": h.get("transcript_path", "")}
for k, v in vals.items():
    print(f"{k}={shlex.quote(str(v))}")
PY
)"

coach_enabled "${SESSION_ID:-}" || exit 0      # session-scoped: only when ON for THIS session
TRANSCRIPT="${TRANSCRIPT:-}"; [[ -f "$TRANSCRIPT" ]] || exit 0

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REC="$(coach_worklog_record "$TRANSCRIPT" "${SESSION_ID}" "$TS")"
[[ -z "$REC" ]] && exit 0

# Dedup: the Stop hook can fire more than once for the same assistant turn. Skip if
# this record's turn uuid already matches the last line already in the worklog.
WL="$(coach_worklog_for "${CWD:-$PWD}" "${SESSION_ID}" 2>/dev/null || true)"
if [[ -n "$WL" && -f "$WL" ]]; then
  NEW_UUID="$(COACH_R="$REC" python3 -c 'import json,os;print(json.loads(os.environ["COACH_R"]).get("uuid") or "")' 2>/dev/null || true)"
  LAST_UUID="$(tail -1 "$WL" 2>/dev/null | python3 -c 'import json,sys
try: print(json.loads(sys.stdin.read()).get("uuid") or "")
except Exception: print("")' 2>/dev/null || true)"
  [[ -n "$NEW_UUID" && "$NEW_UUID" == "$LAST_UUID" ]] && exit 0
fi

coach_worklog_append "${CWD:-$PWD}" "${SESSION_ID}" "$REC"
exit 0
