#!/usr/bin/env bash
# Shared helpers for prompt-coach — an advisory prompt-quality coaching layer.
#
# prompt-coach is ADVISORY: it warns and teaches, it never blocks. Everything is
# gated by a per-session enable flag ($COACH_STATE_DIR/<session_id>.enabled), so it
# is OFF by default.
#
# Sourced library — does NOT `set -e` (hooks must never hard-fail).

: "${COACH_STATE_HOME:=$HOME/.prompt-coach}"
: "${COACH_STATE_DIR:=$COACH_STATE_HOME/sessions}"   # per-session enable flags live here

# prompt-coach is SESSION-SCOPED: it is enabled per Claude Code session, never
# globally. The session id is the same value everywhere — hooks receive it as
# `session_id` in their payload; the toggle skill reads $CLAUDE_CODE_SESSION_ID.
coach_flag_for() { local sid="${1:-}"; [[ -z "$sid" ]] && return 1; echo "$COACH_STATE_DIR/${sid}.enabled"; }
coach_enabled()  { local f; f="$(coach_flag_for "${1:-}")" || return 1; [[ -f "$f" ]]; }

# Structured secrets / common-PII scrub for the on-disk worklog, so a credential or
# obvious identifier in a prompt is never persisted in the clear. This is a disk-hygiene
# backstop, not a transmission gate — the prompt still reaches the model. Newline-
# delimited; the python heredoc below reads it from the env.
COACH_SCRUB='\b\d{3}-\d{2}-\d{4}\b
\b(?:\(\d{3}\)\s*|\d{3}[-.\s])\d{3}[-.\s]\d{4}\b
\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b
\b(?:api[_-]?key|secret|password|passwd|token)\b\s*[:=]\s*\S{6,}
\bsk-[A-Za-z0-9]{16,}\b
\bAKIA[0-9A-Z]{16}\b
-----BEGIN [A-Z ]*PRIVATE KEY-----'

# …/prompt-coach/references, resolved from this script's location.
coach_ref_dir() { echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/references"; }

# Does the prompt itself concern context/token/cache economy? A cheap prompt
# "finding" that pulls in the caching rules even with no telemetry trip.
coach_prompt_mentions_caching() {  # <prompt>
  printf '%s' "${1:-}" | grep -qiE 'cach|token|context (window|fill|limit|usage)|/compact|compact (the|this)|context is (full|large)'
}

# Assemble the coaching context DYNAMICALLY from the small single-axis rule files,
# loading only what THIS prompt needs (keeps the injected context lean):
#   judge + prompting + safety  — always (the everyday coach)
#   caching                     — only on a token/cache signal (telemetry or prompt)
# Echoes the concatenated rule text. Signals are a plain keyword scan — it only ADDS
# depth, never removes the always-on core, so a miss just costs depth.
coach_build_context() {  # <telemetry> <prompt>
  local telemetry="${1:-}" prompt="${2:-}" ref
  ref="$(coach_ref_dir)"
  local parts=(judge.md prompting.md safety.md)
  { [[ -n "$telemetry" ]] || coach_prompt_mentions_caching "$prompt"; } && parts+=(caching.md)
  local out="" p body
  for p in "${parts[@]}"; do
    body="$(cat "$ref/$p" 2>/dev/null || true)"
    [[ -n "$body" ]] && out="${out:+$out$'\n\n'}$body"
  done
  printf '%s' "$out"
}

# Non-blocking, user-visible note (valid for UserPromptSubmit & PreToolUse: a
# systemMessage with no permissionDecision shows the note and lets the action run).
coach_system_message() {
  COACH_MSG="$1" python3 -c 'import json,os;print(json.dumps({"systemMessage":os.environ["COACH_MSG"]}))'
}

# Emit a UserPromptSubmit response: additionalContext (fed to the model — this is how
# the inline coach hands the rubric to the main model to self-assess) plus an optional
# systemMessage (user-visible, OUT of the model's context). Used so a context/caching
# warning reaches the user without riding in the model's context.
coach_emit() {  # <additional_context> [system_message]
  COACH_AC="$1" COACH_MSG="${2:-}" python3 -c '
import json, os
ac = os.environ.get("COACH_AC", ""); msg = os.environ.get("COACH_MSG", "")
out = {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": ac}}
if msg:
    out["systemMessage"] = msg
print(json.dumps(out))'
}

# ── CWD-local worklog ────────────────────────────────────────────────────────
# The coach records one JSONL line per turn (context breakdown + cache stats + the
# 🧭 line + the scrubbed prompt) so feedback + telemetry live on DISK, not in the
# model's growing context. Lives under the project/CWD so it travels with the repo.
# The dir carries its own `.gitignore: *` so it self-ignores in any repo without
# touching the repo's root .gitignore. Written by the Stop hook, read by summary.
: "${COACH_WORKLOG_DIRNAME:=.prompt-coach}"
coach_worklog_dir()        { echo "${1:-$PWD}/$COACH_WORKLOG_DIRNAME"; }  # <cwd>
coach_worklog_for()        { local d; d="$(coach_worklog_dir "${1:-$PWD}")"; [[ -z "${2:-}" ]] && return 1; echo "$d/coach-${2}.jsonl"; }       # <cwd> <sid>
coach_rubric_marker_for()  { local d; d="$(coach_worklog_dir "${1:-$PWD}")"; [[ -z "${2:-}" ]] && return 1; echo "$d/${2}.rubric-injected"; }   # <cwd> <sid>
coach_ensure_worklog_dir() {  # <cwd> -> prints dir; creates it + self-ignoring .gitignore
  local d; d="$(coach_worklog_dir "${1:-$PWD}")"
  mkdir -p "$d" 2>/dev/null || return 1
  [[ -f "$d/.gitignore" ]] || printf '*\n' >"$d/.gitignore" 2>/dev/null || true
  echo "$d"
}
coach_worklog_append() {  # <cwd> <sid> <json_line>
  local cwd="${1:-$PWD}" sid="${2:-}" line="${3:-}"
  [[ -z "$sid" || -z "$line" ]] && return 1
  coach_ensure_worklog_dir "$cwd" >/dev/null || return 1
  local wl; wl="$(coach_worklog_for "$cwd" "$sid")" || return 1
  printf '%s\n' "$line" >>"$wl" 2>/dev/null || return 1
}

# Build ONE worklog record from the transcript (parsed once). Emits a JSONL line:
#   {ts,turn,session,model,prompt(scrubbed),feedback,ctx{total,window,pct,categories{…}},
#    cache{read,creation,hit_pct,chain_break},uuid}
# model is the ground-truth model from the transcript; window is derived from it.
# Categories are a SEMANTIC ESTIMATE (~chars÷4): conversation / tool_results_files /
# coach are summed from transcript content; system_tools is the residual against the
# ground-truth total from the last usage record (system prompt + tool/MCP schemas +
# memory aren't in the transcript, so residual is the only honest way to size them).
# Empty output on a tiny/early session (<5k ctx) or parse failure. Best-effort.
coach_worklog_record() {  # <transcript_path> <session> <ts>
  local tp="${1:-}" sid="${2:-}" ts="${3:-}"
  [[ -f "$tp" ]] || return 0
  COACH_TP="$tp" COACH_SID="$sid" COACH_TS="$ts" COACH_SCRUB="$COACH_SCRUB" \
  python3 - <<'PY' 2>/dev/null || true
import json, os, re, sys
try: sys.stdout.reconfigure(encoding="utf-8")   # record carries 🧭; don't crash the write on a C-locale
except Exception: pass
tp = os.environ["COACH_TP"]; sid = os.environ.get("COACH_SID", ""); ts = os.environ.get("COACH_TS", "")
SCRUB = [p for p in os.environ.get("COACH_SCRUB", "").splitlines() if p]
def scrub(s):
    for p in SCRUB:
        s = re.sub(p, "[REDACTED]", s, flags=re.I)
    return s
def est(s):
    return max(0, len(s) // 4)
conv = tool = coach = 0
last = None; last_model = ""; creation_recent = []; nturns = 0; last_uuid = ""
last_prompt = ""; last_feedback = None
try:
    with open(tp, encoding="utf-8") as f:
        for line in f:
            try: o = json.loads(line)
            except Exception: continue
            t = o.get("type"); msg = o.get("message") or {}
            content = msg.get("content")
            parts = [{"type": "text", "text": content}] if isinstance(content, str) else (content if isinstance(content, list) else [])
            if t == "assistant":
                u = msg.get("usage")
                if u:
                    last = u; last_model = msg.get("model") or last_model
                    creation_recent.append(int(u.get("cache_creation_input_tokens") or 0))
                    nturns += 1; last_uuid = o.get("uuid") or last_uuid
            if t == "user":
                has_tr = any(isinstance(p, dict) and p.get("type") == "tool_result" for p in parts)
                txts = [p.get("text", "") if isinstance(p, dict) else str(p) for p in parts
                        if isinstance(p, str) or (isinstance(p, dict) and p.get("type") == "text")]
                joined = "".join(txts).strip()
                if joined and not has_tr:            # a real human prompt, not a tool_result carrier
                    last_prompt = joined
                    last_feedback = None             # reset per turn: a contentless turn must NOT
                                                     # inherit the prior turn's 🧭 line
            for part in parts:
                if not isinstance(part, dict): continue
                pt = part.get("type")
                if pt == "tool_result":
                    c = part.get("content")
                    txt = "".join(x.get("text", "") for x in c if isinstance(x, dict)) if isinstance(c, list) else str(c or "")
                    tool += est(txt)
                elif pt == "text":
                    txt = part.get("text", "") or ""
                    if "🧭" in txt:
                        coach += est(txt)
                        if t == "assistant":
                            for ln in txt.splitlines():
                                if "🧭" in ln: last_feedback = ln.strip()
                    elif "<prompt-coach>" in txt:
                        coach += est(txt)
                    else:
                        conv += est(txt)
                elif pt == "thinking":
                    conv += est(part.get("thinking", "") or "")
                elif pt == "tool_use":
                    conv += est(json.dumps(part.get("input") or {}))
except Exception:
    raise SystemExit(0)
if not last:
    raise SystemExit(0)
inp = int(last.get("input_tokens") or 0)
read = int(last.get("cache_read_input_tokens") or 0)
crea = int(last.get("cache_creation_input_tokens") or 0)
total = inp + read + crea
if total < 5000:
    raise SystemExit(0)
env = os.environ.get("COACH_CTX_WINDOW")
WINDOW = int(env) if (env and env.isdigit()) else (200_000 if "haiku" in (last_model or "").lower() else 1_000_000)
system_tools = max(0, total - conv - tool - coach)
cached = read + crea
hit = round(100.0 * read / cached, 1) if cached else 100.0
# chain broke THIS turn = a non-first, substantial turn where less than half the
# context was served from cache (the prefix busted and had to be reprocessed).
chain_break = bool(nturns > 1 and total > 20_000 and read < 0.5 * total)
stored_prompt = scrub(last_prompt)[:500]
rec = {
    "ts": ts, "turn": nturns, "session": sid,
    "model": last_model or None,   # ground-truth model; window below is derived from it
    "prompt": stored_prompt, "feedback": last_feedback,
    "ctx": {"total": total, "window": WINDOW, "pct": round(100.0 * total / WINDOW, 1),
            "categories": {"system_tools": system_tools, "conversation": conv,
                           "tool_results_files": tool, "coach": coach}},
    "cache": {"read": read, "creation": crea, "hit_pct": hit, "chain_break": chain_break},
    "uuid": last_uuid,
}
print(json.dumps(rec, ensure_ascii=False))
PY
}

# Session token/caching telemetry from the transcript. The UserPromptSubmit hook
# receives `transcript_path`; each assistant turn carries a real `usage` record
# (input / cache_read / cache_creation / output). We compute context fill and the
# cache-hit ratio from ground truth. Emits ONE compact line ONLY when a threshold
# trips (else empty → the hook appends nothing and the coach never nags). Best-effort.
# ponytail: reads the whole transcript each turn (O(n), fine at these sizes); a
# byte-offset tail is the upgrade path if transcripts get huge.
: "${COACH_CTX_WARN_PCT:=75}"    # context-fill % that trips a tip
: "${COACH_CACHE_WARN_PCT:=60}"  # cache-hit % below which we flag poor caching
coach_telemetry() {  # <transcript_path>
  local tp="${1:-}"; [[ -f "$tp" ]] || return 0
  COACH_TP="$tp" COACH_CTX_WARN="$COACH_CTX_WARN_PCT" COACH_CACHE_WARN="$COACH_CACHE_WARN_PCT" \
  python3 - <<'PY' 2>/dev/null || true
import json, os
tp = os.environ["COACH_TP"]
ctx_warn = float(os.environ.get("COACH_CTX_WARN") or 75)
cache_warn = float(os.environ.get("COACH_CACHE_WARN") or 60)
last = None; last_model = ""; creation_recent = []
try:
    with open(tp, encoding="utf-8") as f:
        for line in f:
            try: o = json.loads(line)
            except Exception: continue
            if o.get("type") != "assistant": continue
            msg = o.get("message") or {}
            u = msg.get("usage")
            if not u: continue
            last = u
            last_model = msg.get("model") or last_model   # ground-truth model for THIS session
            creation_recent.append(int(u.get("cache_creation_input_tokens") or 0))
except Exception:
    raise SystemExit(0)
if not last:
    raise SystemExit(0)
# Context window depends on the model loaded at runtime — never a single hardcode.
# Priority: explicit COACH_CTX_WINDOW override → per-model lookup (model read from the
# transcript) → 1M default. Current Claude models are 1M-native EXCEPT Haiku (200k).
def _window_for(model):
    env = os.environ.get("COACH_CTX_WINDOW")
    if env and env.isdigit():
        return int(env)
    m = (model or "").lower()
    if "haiku" in m:
        return 200_000
    return 1_000_000
WINDOW = _window_for(last_model)
inp = int(last.get("input_tokens") or 0)
read = int(last.get("cache_read_input_tokens") or 0)
crea = int(last.get("cache_creation_input_tokens") or 0)
ctx = inp + read + crea
if ctx < 5000:            # early/tiny session — nothing worth coaching yet
    raise SystemExit(0)
fill = 100.0 * ctx / WINDOW
cached = read + crea
hit = (100.0 * read / cached) if cached else 100.0
# churn: cache_creation stayed high across the last few turns → prefix keeps busting
recent = creation_recent[-3:]
churn = len(recent) == 3 and all(c > 10_000 for c in recent)
# Lead with the cache-instability signals — a busting prefix silently re-charges the
# whole prefix every turn and NO built-in command surfaces it. Fill/compact comes last:
# Claude Code already auto-prompts it, so we only defer to that, never headline it.
cache_unstable = churn or (cached >= 20_000 and hit < cache_warn)
flags = []
if churn: flags.append("cache_creation high 3 turns running (prefix keeps busting)")
if cached >= 20_000 and hit < cache_warn: flags.append(f"cache-hit only {hit:.0f}%")
if fill >= ctx_warn: flags.append(f"context ~{fill:.0f}% full ({ctx//1000}k/{WINDOW//1000}k)")
if flags:
    if cache_unstable:
        tip = ("Something early in the context keeps changing — usually an MCP/tool added or "
               "reordered mid-session, a model switch, or a CLAUDE.md edit; finish that setup "
               "up front so the prefix stays cached")
    else:  # fill-only — the system owns /compact, so don't hint it; give the cheaper lever
        tip = ("The window-full case is handled by Claude Code — the cheaper lever now is to "
               "prune unused tools/MCP or use targeted reads to reclaim space")
    print("; ".join(flags) + ". " + tip)
PY
}
