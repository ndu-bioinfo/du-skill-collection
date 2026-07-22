#!/usr/bin/env bash
# Install skills from this repo by symlinking them into ~/.claude/skills/.
#
#   ./install.sh                          # install ALL skills
#   ./install.sh prompt-coach             # install specific skill(s)
#   ./install.sh pptx-slide-design pptx-flowchart-design
#   ./install.sh --with-hooks prompt-coach  # also wire prompt-coach's hooks into settings.json
#   ./install.sh --list                   # list available skills and exit
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

WITH_HOOKS=0
NAMES=()
for a in "$@"; do
  case "$a" in
    --with-hooks) WITH_HOOKS=1 ;;
    --list) available; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "install.sh: unknown option: $a" >&2; exit 2 ;;
    *) NAMES+=("$a") ;;
  esac
done

# No names → all skills.
if [ ${#NAMES[@]} -eq 0 ]; then
  while IFS= read -r s; do NAMES+=("$s"); done < <(available)
fi

mkdir -p "$SKILLS_DIR"
installed_prompt_coach=0

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
done

# prompt-coach only coaches once its hooks are wired into settings.json. Do that
# only on explicit --with-hooks (editing settings is opt-in).
if [ "$installed_prompt_coach" = 1 ]; then
  if [ "$WITH_HOOKS" = 1 ]; then
    REPO="$REPO" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os
settings = os.environ["SETTINGS"]; repo = os.environ["REPO"]
data = {}
if os.path.exists(settings):
    with open(settings) as f:
        try: data = json.load(f) or {}
        except Exception: data = {}
hooks = data.setdefault("hooks", {})
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
with open(settings, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
print("hooks wired into " + settings + ": " + (", ".join(added) if added else "already present"))
PY
    echo "prompt-coach hooks are wired — enable per session with: /prompt-coach ON"
  else
    echo
    echo "note: prompt-coach needs its hooks wired to coach. Re-run with --with-hooks,"
    echo "      or add them manually (see prompt-coach/hooks.json)."
  fi
fi

echo
echo "done. Restart Claude Code (or start a new session) to pick up installed skills."
