#!/usr/bin/env bash
# Install skills from this repo by symlinking them into ~/.claude/skills/.
#
#   ./install.sh                          # install ALL skills
#   ./install.sh prompt-coach             # install specific skill(s)
#   ./install.sh pptx-slide-design pptx-flowchart-design
#   ./install.sh --no-hooks               # skip wiring prompt-coach/step-status hooks + status line
#   ./install.sh --list                   # list available skills and exit
#
# prompt-coach's hooks are wired into settings.json automatically when it's
# installed, so a fresh `./install.sh` is all anyone needs. Pass --no-hooks to skip.
# step-status's status line (wrap or standalone) + SessionStart hook are wired only when
# you name it explicitly (`./install.sh step-status`), since that replaces statusLine.
#
# Symlinks (not copies) so `git pull` updates every installed skill in place.
# Idempotent: re-running is safe. Override locations with $CLAUDE_SKILLS_DIR /
# $CLAUDE_SETTINGS. Uninstall with ./uninstall.sh.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

usage() { sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# A skill = a top-level dir containing SKILL.md.
available() { for d in "$REPO"/*/; do [ -f "${d}SKILL.md" ] && basename "$d"; done; }

WITH_HOOKS=1
NAMES=()
for a in "$@"; do
  case "$a" in
    --with-hooks) WITH_HOOKS=1 ;;   # kept for back-compat; hooks are on by default
    --no-hooks) WITH_HOOKS=0 ;;
    --list) available; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "install.sh: unknown option: $a" >&2; exit 2 ;;
    *) NAMES+=("$a") ;;
  esac
done

# No names → all skills.
EXPLICIT=${#NAMES[@]}
if [ ${#NAMES[@]} -eq 0 ]; then
  while IFS= read -r s; do NAMES+=("$s"); done < <(available)
fi

mkdir -p "$SKILLS_DIR"
installed_prompt_coach=0
installed_step_status=0

for name in "${NAMES[@]}"; do
  src="$REPO/$name"
  if [ ! -f "$src/SKILL.md" ]; then
    echo "skip: '$name' is not a skill in this repo (no SKILL.md)" >&2
    continue
  fi
  dst="$SKILLS_DIR/$name"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "skip: $dst exists and is not a symlink — leaving it alone" >&2
    continue
  fi
  ln -sfn "$src" "$dst"
  echo "installed: $name -> $dst"
  [ "$name" = "prompt-coach" ] && installed_prompt_coach=1
  [ "$name" = "step-status" ] && installed_step_status=1
done

# step-status renders in the status line. Plugins can't set statusLine, so wire it here
# (wrap an existing command or install standalone) plus the SessionStart hook — but only
# when step-status was asked for by name: replacing statusLine is not a side effect anyone
# installing the pptx skills should get.
if [ "$installed_step_status" = 1 ]; then
  if [ "$WITH_HOOKS" = 1 ] && [ "$EXPLICIT" -gt 0 ]; then
    CLAUDE_SETTINGS="$SETTINGS" bash "$REPO/step-status/scripts/wire_statusline.sh"
  else
    echo "note: step-status status line not wired. Run: ./install.sh step-status"
    echo "      (or bash step-status/scripts/wire_statusline.sh) to wrap your status line."
  fi
fi

# prompt-coach only coaches once its hooks are wired into settings.json. Do that
# only on explicit --with-hooks (editing settings is opt-in).
if [ "$installed_prompt_coach" = 1 ]; then
  if [ "$WITH_HOOKS" = 1 ]; then
    REPO="$REPO" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys
settings = os.environ["SETTINGS"]; repo = os.environ["REPO"]
data = {}
if os.path.exists(settings):
    with open(settings) as f: raw = f.read()
    if raw.strip():
        try: data = json.loads(raw)
        except Exception as e: sys.exit(f"refusing to rewrite {settings}: not valid JSON ({e})")
if not isinstance(data, dict): sys.exit(f"{settings} is not a JSON object")
hooks = data.get("hooks") if isinstance(data.get("hooks"), dict) else {}
data["hooks"] = hooks
entries = {
  "UserPromptSubmit": {"hooks": [{"type": "command",
     "command": f'bash "{repo}/prompt-coach/scripts/hook_prompt.sh"', "timeout": 10}]},
  "Stop": {"matcher": "", "hooks": [{"type": "command",
     "command": f'bash "{repo}/prompt-coach/scripts/hook_stop.sh"', "timeout": 10}]},
}
def present(ev, cmd):
    return any(h.get("command") == cmd
               for grp in hooks.get(ev, []) for h in grp.get("hooks", []))
added = []
for ev, grp in entries.items():
    cmd = grp["hooks"][0]["command"]
    hooks.setdefault(ev, [])
    if not present(ev, cmd):
        hooks[ev].append(grp); added.append(ev)
os.makedirs(os.path.dirname(settings) or ".", exist_ok=True)
tmp = settings + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
os.replace(tmp, settings)
print("hooks wired into " + settings + ": " + (", ".join(added) if added else "already present"))
PY
    echo "prompt-coach hooks are wired — enable per session with: /prompt-coach ON"
  else
    echo
    echo "note: prompt-coach needs its hooks wired to coach. You passed --no-hooks;"
    echo "      re-run without it, or add them manually (see prompt-coach/hooks/hooks.json)."
  fi
fi

echo
echo "done. Restart Claude Code (or start a new session) to pick up installed skills."
