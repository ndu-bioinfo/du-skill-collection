#!/usr/bin/env bash
# Wire (or unwire) the step-status status line in Claude Code settings.json.
# Plugins cannot set statusLine, so this is the one manual step; install.sh calls it too.
#
#   wire_statusline.sh            # wrap an existing statusLine command, or install standalone
#   wire_statusline.sh --unwire   # restore the previous statusLine exactly / remove the standalone entry
#   wire_statusline.sh --selfcheck
#
# Auto-detect: an existing command (e.g. `npx -y ccstatusline@latest`) is wrapped so its
# output stays and the step chain is appended; no command → the chain is the status line.
# The original statusLine object is saved to $STEP_STATUS_HOME/prev-statusline.json and
# restored wholesale on --unwire. Also registers the SessionStart hook unless
# STEP_STATUS_NO_HOOK=1 (plugin installs already ship it).
# Plugin installs live in a versioned cache dir that changes on update, so in that case the
# scripts are copied to $STEP_STATUS_HOME/bin and settings point there (re-run after updates).
# Settings path: $CLAUDE_SETTINGS (default ~/.claude/settings.json). Never rewrites a file it
# could not parse.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
HOME_DIR="${STEP_STATUS_HOME:-$HOME/.claude/step-status}"
case "${1-}" in
  "") MODE=wire ;; --unwire) MODE=unwire ;; --selfcheck) MODE=selfcheck ;;
  *) echo "usage: wire_statusline.sh [--unwire|--selfcheck]" >&2; exit 2 ;;
esac

selfcheck() {
  local d s; d="$(mktemp -d)"; s="${BASH_SOURCE[0]}"
  export STEP_STATUS_HOME="$d/home" STEP_STATUS_NO_HOOK=0
  fail() { echo "FAIL $1"; cat "$d"/*.json 2>/dev/null; exit 1; }
  # 1. malformed settings are never rewritten
  printf '{ "model": "opus", broken' > "$d/bad.json"; cp "$d/bad.json" "$d/bad.before"
  CLAUDE_SETTINGS="$d/bad.json" bash "$s" >/dev/null 2>&1 && fail "malformed accepted"
  cmp -s "$d/bad.json" "$d/bad.before" || fail "malformed rewritten"
  # 2. wrap → idempotent → unwire is an exact round trip (padding preserved)
  printf '{"permissions":{"allow":["Bash"]},"statusLine":{"type":"command","command":"echo X","padding":1}}' > "$d/s.json"; cp "$d/s.json" "$d/s.before"
  export CLAUDE_SETTINGS="$d/s.json"
  bash "$s" | grep -q wrapped || fail wrap
  bash "$s" | grep -q "already wired" || fail idempotent
  python3 -c "import json;d=json.load(open('$d/s.json'));assert d['statusLine']['command'].endswith(\"-- 'echo X'\");assert d['permissions']=={'allow':['Bash']};assert len(d['hooks']['SessionStart'])==1" || fail wrapped-shape
  bash "$s" --unwire | grep -q restored || fail unwire
  python3 -c "import json,sys;a=json.load(open('$d/s.json'));b=json.load(open('$d/s.before'));sys.exit(a!=b)" || fail round-trip
  # 3. standalone → unwire removes the key; hooks:null tolerated
  printf '{"hooks":null}' > "$d/t.json"; export CLAUDE_SETTINGS="$d/t.json"
  bash "$s" | grep -q standalone || fail standalone
  bash "$s" --unwire | grep -q removed || fail standalone-unwire
  [[ "$(python3 -c "import json;print(json.load(open('$d/t.json')))")" == "{}" ]] || fail standalone-clean
  # 4. wrapped mode output: inner output on its own line, chain appended
  export STEP_STATUS_DIR="$d/proj/.step-status"; mkdir -p "$d/proj"
  bash "$HERE/steps.sh" set a b >/dev/null
  out="$(printf '{"workspace":{"current_dir":"%s"}}' "$d/proj" | bash "$HERE/statusline.sh" -- 'printf abc')"
  [[ "$out" == $'abc\na ● → b ○' ]] || fail "wrapped output: $out"
  [[ -z "$(echo '{}' | bash "$HERE/statusline.sh")" ]] || fail "no-cwd should print nothing"
  rm -rf "$d"; echo "selfcheck OK"
}
[[ "$MODE" == selfcheck ]] && { selfcheck; exit 0; }

# Plugin cache dirs are versioned; copy scripts somewhere stable and wire that.
if [[ "$HERE" == */plugins/cache/* ]]; then
  mkdir -p "$HOME_DIR/bin" && cp "$HERE"/steps.sh "$HERE"/statusline.sh "$HERE"/hook_session_start.sh "$HOME_DIR/bin/"
  HERE="$HOME_DIR/bin"
fi
mkdir -p "$HOME_DIR"

HERE="$HERE" SETTINGS="$SETTINGS" MODE="$MODE" PREV="$HOME_DIR/prev-statusline.json" NO_HOOK="${STEP_STATUS_NO_HOOK:-0}" python3 - <<'PY'
import json, os, shlex, sys
settings, here, mode, prev = (os.environ[k] for k in ("SETTINGS", "HERE", "MODE", "PREV"))
data = {}
if os.path.exists(settings):
    with open(settings) as f: raw = f.read()
    if raw.strip():
        try: data = json.loads(raw)
        except Exception as e: sys.exit(f"step-status: refusing to rewrite {settings}: not valid JSON ({e})")
if not isinstance(data, dict): sys.exit(f"step-status: {settings} is not a JSON object")
hooks = data.get("hooks")
if not isinstance(hooks, dict): hooks = {}
data["hooks"] = hooks
def ours(cmd, script): return f'"{here}/{script}"' in cmd          # exactly this install (AGENTS.md: only touch our own entries)
def foreign(cmd): return "step-status" in cmd and "statusline.sh" in cmd and not ours(cmd, "statusline.sh")
sl = data.get("statusLine") if isinstance(data.get("statusLine"), dict) else None
old = (sl or {}).get("command") or ""
sl_script = f'bash "{here}/statusline.sh"'
hook_cmd = f'bash "{here}/hook_session_start.sh"'
notes = []
if mode == "wire":
    if ours(old, "statusline.sh"):
        notes.append("already wired")
    elif foreign(old):
        sys.exit(f"step-status: statusLine is already wired by another step-status install ({old}); run --unwire there first")
    else:
        with open(prev, "w") as f: json.dump(sl, f)      # None when there was no statusLine
        if old:
            data["statusLine"] = {"type": "command", "command": f"{sl_script} -- {shlex.quote(old)}", "padding": 0}
            notes.append(f"wrapped existing status line ({old})")
        else:
            data["statusLine"] = {"type": "command", "command": sl_script, "padding": 0}
            notes.append("standalone (no existing status line found)")
    if os.environ["NO_HOOK"] != "1":
        groups = hooks.get("SessionStart") if isinstance(hooks.get("SessionStart"), list) else []
        hooks["SessionStart"] = groups
        if not any(ours(h.get("command") or "", "hook_session_start.sh") for g in groups if isinstance(g, dict) for h in g.get("hooks", [])):
            groups.append({"matcher": "startup|clear", "hooks": [{"type": "command", "command": hook_cmd, "timeout": 10}]})
            notes.append("SessionStart hook added")
else:
    removed = 0
    for ev in list(hooks):
        kept_groups = []
        for g in hooks[ev] if isinstance(hooks[ev], list) else []:
            kept = [h for h in g.get("hooks", []) if not ours(h.get("command") or "", "hook_session_start.sh")]
            removed += len(g.get("hooks", [])) - len(kept)
            if kept: g["hooks"] = kept; kept_groups.append(g)
        if kept_groups: hooks[ev] = kept_groups
        else: del hooks[ev]
    if removed: notes.append(f"removed {removed} SessionStart hook(s)")
    if ours(old, "statusline.sh"):
        saved = None
        if os.path.exists(prev):
            with open(prev) as f: saved = json.load(f)
            os.remove(prev)
        if saved:
            data["statusLine"] = saved; notes.append("restored status line: " + str(saved.get("command")))
        else:
            parts = shlex.split(old)
            if "--" in parts and parts.index("--") + 1 < len(parts):
                data["statusLine"]["command"] = parts[parts.index("--") + 1]; notes.append("restored status line: " + data["statusLine"]["command"])
            else:
                data.pop("statusLine", None); notes.append("removed standalone status line")
    else:
        notes.append("no step-status status line found")
if not hooks: data.pop("hooks", None)
os.makedirs(os.path.dirname(settings) or ".", exist_ok=True)
tmp = settings + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
os.replace(tmp, settings)
print("step-status: " + "; ".join(notes))
PY
