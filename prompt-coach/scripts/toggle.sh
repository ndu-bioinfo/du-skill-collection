#!/usr/bin/env bash
# /prompt-coach ON|OFF|status — flips the PER-SESSION enable flag the hooks gate on.
# Session-scoped by design: turning it on affects only the current Claude Code
# session, never other sessions or other repos.
#
#   ON       enable for this session
#   OFF      disable for this session
#   status   show this session's state
#
# The session id comes from $CLAUDE_CODE_SESSION_ID (set in every CC session);
# tests override it with $COACH_SID. The hooks read the SAME id from their payload,
# so the flag written here is the flag they check.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/_common.sh" 2>/dev/null || { echo "prompt-coach: cannot load helpers" >&2; exit 1; }

cmd="$(printf '%s' "${1:-status}" | tr '[:upper:]' '[:lower:]')"
SID="${COACH_SID:-${CLAUDE_CODE_SESSION_ID:-}}"
if [[ -z "$SID" ]]; then
  echo "prompt-coach: no session id (CLAUDE_CODE_SESSION_ID unset) — run inside a Claude Code session" >&2
  exit 1
fi
FLAG="$(coach_flag_for "$SID")"
mkdir -p "$COACH_STATE_DIR" 2>/dev/null || true

_now() { date -u +%FT%TZ 2>/dev/null || echo 1; }

case "$cmd" in
  on|enable|enabled)
    printf 'enabled=%s\n' "$(_now)" > "$FLAG"
    echo "prompt-coach: ON for this session ($SID)"
    echo "  · session summary on demand: /prompt-coach summary  (writes training material)"
    echo "  · each prompt is coached inline by the main model (no subprocess, ~0 added latency);"
    echo "    a tip appears as a '🧭 coach:' line only when useful — silent when the prompt is fine"
    echo "  · other sessions are unaffected"
    ;;
  off|disable|disabled)
    rm -f "$FLAG" 2>/dev/null || true
    echo "prompt-coach: OFF for this session ($SID)"
    ;;
  status|"")
    if coach_enabled "$SID"; then
      echo "prompt-coach: ON for this session ($SID)  (since $(grep -o '^enabled=.*' "$FLAG" 2>/dev/null | cut -d= -f2-))"
    else
      echo "prompt-coach: OFF for this session ($SID)"
    fi
    ;;
  *)
    echo "usage: prompt-coach ON | OFF | status" >&2
    exit 2
    ;;
esac
