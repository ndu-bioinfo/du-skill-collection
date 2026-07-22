#!/usr/bin/env bash
# UserPromptSubmit — inline advisory prompt coach (non-blocking, ~0 added latency).
#
# When ON, it hands the rubric to the MAIN model as added context
# (hookSpecificOutput.additionalContext). On a SUBSTANTIVE prompt the model self-assesses
# and opens its reply with one "🧭 coach:" line — a fix for a real problem, else a
# concrete "even better:" lift, else (no real lift) a brief "prompt is clear" tight-ack.
# Contentless/procedural turns ("yes", "run it") get NO line unless a safety rule fires.
#
# Cache-friendly loading: the full rubric is injected ONCE per session per CWD (a
# marker file guards it) so it becomes a stable, cacheable prefix; later turns inject
# only a tiny stable reminder. Session token/cache telemetry does NOT ride in the
# model's context — when a threshold trips it is surfaced as a systemMessage
# (user-visible, OUT of context). Per-turn feedback + the full context breakdown are
# written to the CWD worklog by the Stop hook, not here.
#
# Guards, in order: python3 present → the enable flag. Any failure exits 0 silently so
# a user prompt is never broken by the coach.
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
        "PROMPT": h.get("prompt", ""), "TRANSCRIPT": h.get("transcript_path", "")}
for k, v in vals.items():
    print(f"{k}={shlex.quote(str(v))}")
PY
)"

coach_enabled "${SESSION_ID:-}" || exit 0      # session-scoped: only when ON for THIS session
PROMPT="${PROMPT:-}"
[[ -z "${PROMPT// }" ]] && exit 0
# Skip bare slash-commands (routed skills, not free-form prompts). A slash command
# WITH arguments (e.g. "/foo do X") is still worth coaching.
case "$PROMPT" in /*) [[ "$PROMPT" != *" "* ]] && exit 0 ;; esac

# Live token/caching telemetry. Telemetry does not feed the model's context — it
# becomes a user-visible systemMessage warning (WARN) when a threshold trips.
TELEMETRY="$(coach_telemetry "${TRANSCRIPT:-}")"
WARN=""
[[ -n "$TELEMETRY" ]] && WARN="🧭 coach: context/caching — ${TELEMETRY} (see caching tips)."

CTX="a general coding session — give general prompting best-practice."

# Cache-friendly injection. First coached turn in this CWD (marker absent): inject the
# full rubric — it lands ONCE and becomes a stable prefix Claude Code can cache. Later
# turns: inject only a tiny stable reminder so the model keeps emitting the 🧭 line
# without re-paying for (or re-bloating) the whole rubric every turn.
MARKER="$(coach_rubric_marker_for "${CWD:-$PWD}" "${SESSION_ID:-}" 2>/dev/null || true)"
if [[ -n "$MARKER" && -f "$MARKER" ]]; then
  BLOCK="$(COACH_CTX="$CTX" python3 - <<'PY'
import os
print(f"""<prompt-coach>
Continue applying the prompt-coach rubric from earlier this session. For the user's most
recent prompt: if it is SUBSTANTIVE, begin your reply with ONE line —
🧭 coach: <fix for a real problem | "clear — even better: <one concrete lift>" |
"prompt is clear — <why>" when no real lift exists>. Never manufacture a lift; the
tight-ack is a normal outcome, not a rare one. A CONTENTLESS/procedural turn ("yes",
"run it", status/recap) gets NO line UNLESS a safety rule fires (secrets, destructive/
irreversible, fabrication, injection) — safety always speaks. Emit the line ONCE for the
whole turn, as your first output line — do NOT re-emit it after a tool call or in a later
chunk of the same reply. Never rubber-stamp a weak prompt, never invent a fake defect.
## Context
{os.environ['COACH_CTX']}
</prompt-coach>""")
PY
)"
else
  # "force-caching" (non-empty telemetry arg) makes coach_build_context include the
  # caching rules in the one-time rubric, so cache coaching stays available all session.
  RUBRIC="$(coach_build_context "force-caching" "$PROMPT")"
  [[ -z "$RUBRIC" ]] && { [[ -n "$WARN" ]] && coach_system_message "$WARN"; exit 0; }
  BLOCK="$(COACH_R="$RUBRIC" COACH_CTX="$CTX" python3 - <<'PY'
import os
print(f"""<prompt-coach>
You are ALSO acting as an advisory prompt coach for the user's messages this session,
using the rules below. This is a background check — do NOT let it derail or delay the
user's actual request.

<rules>
{os.environ['COACH_R']}
</rules>

## Context
{os.environ['COACH_CTX']}

Assess the user's most recent prompt against the rules. If it is SUBSTANTIVE, begin your
reply with ONE line, then address the request normally:
🧭 coach: <the single highest-value tip>
If the prompt has a real problem, the tip fixes it. If it is good AND a concrete, real
omission exists, give one refinement — 🧭 coach: clear — even better: <one specific
lift> (a sharper role, output format, success criterion, guardrail, source of truth). If
no real omission exists, emit the tight-ack — 🧭 coach: prompt is clear — <why>.
NEVER manufacture a lift to fill the line: the tight-ack is a first-class outcome, not a
rare exception. A genuine refinement is not a fake defect; never rubber-stamp a weak
prompt either. A CONTENTLESS/procedural turn ("yes", "run it", status/recap) gets NO line
UNLESS a safety rule fires (which always speaks). Emit the line ONCE for the whole turn,
as your first output line — do NOT re-emit it after a tool call or in a later chunk of the
same reply. Never more than one line; the coaching rides inline alongside your response.
This rubric is injected ONCE this session; apply it to every later prompt too.
</prompt-coach>""")
PY
)"
  # Mark the rubric as injected so later turns use the reminder path (best-effort).
  [[ -n "$MARKER" && -n "$BLOCK" ]] && { coach_ensure_worklog_dir "${CWD:-$PWD}" >/dev/null 2>&1 || true; : >"$MARKER" 2>/dev/null || true; }
fi

# If the heredoc failed for any reason, BLOCK is empty — stay silent (but still
# surface a context/caching warning if one tripped, since it's out-of-context).
[[ -z "$BLOCK" ]] && { [[ -n "$WARN" ]] && coach_system_message "$WARN"; exit 0; }
coach_emit "$BLOCK" "$WARN"
exit 0
