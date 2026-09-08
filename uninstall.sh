#!/usr/bin/env bash
# Uninstall skills that were installed from this repo (remove the symlinks in
# ~/.claude/skills/; for prompt-coach unwire its hooks, for step-status restore the
# previous statusLine and drop its SessionStart hook in settings.json).
#
#   ./uninstall.sh                 # uninstall ALL skills from this repo
#   ./uninstall.sh prompt-coach    # uninstall specific skill(s)
#
# Only removes symlinks that point back into THIS repo — never touches a real
# directory or a symlink to somewhere else. Override locations with
# $CLAUDE_SKILLS_DIR / $CLAUDE_SETTINGS.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
available() { for d in "$REPO"/*/; do [ -f "${d}SKILL.md" ] && basename "$d"; done; }

NAMES=()
for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0 ;;
    -*) echo "uninstall.sh: unknown option: $a" >&2; exit 2 ;;
    *) NAMES+=("$a") ;;
  esac
done

if [ ${#NAMES[@]} -eq 0 ]; then
  while IFS= read -r s; do NAMES+=("$s"); done < <(available)
fi

removed_prompt_coach=0
removed_step_status=0
for name in "${NAMES[@]}"; do
  dst="$SKILLS_DIR/$name"
  if [ ! -L "$dst" ]; then
    [ -e "$dst" ] && echo "skip: $dst is not a symlink — leaving it alone" >&2
    continue
  fi
  target="$(readlink "$dst")"
  case "$target" in
    "$REPO/"*) rm -f "$dst"; echo "uninstalled: $name"
               [ "$name" = "prompt-coach" ] && removed_prompt_coach=1
               [ "$name" = "step-status" ] && removed_step_status=1 ;;
    *) echo "skip: $dst points to $target (not this repo) — leaving it alone" >&2 ;;
  esac
done

# Unwire prompt-coach hooks from settings.json (only entries that reference THIS repo).
if [ "$removed_prompt_coach" = 1 ] && [ -f "$SETTINGS" ]; then
  REPO="$REPO" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys
settings = os.environ["SETTINGS"]; marker = os.environ["REPO"] + "/prompt-coach/scripts/"
data = {}
if os.path.exists(settings):
    with open(settings) as f: raw = f.read()
    if raw.strip():
        try: data = json.loads(raw)
        except Exception as e: sys.exit(f"refusing to rewrite {settings}: not valid JSON ({e})")
if not isinstance(data, dict): sys.exit(f"{settings} is not a JSON object")
hooks = data.get("hooks") if isinstance(data.get("hooks"), dict) else {}
removed = 0
for ev in list(hooks):
    groups = []
    for grp in hooks[ev]:
        kept = [h for h in grp.get("hooks", []) if marker not in (h.get("command") or "")]
        removed += len(grp.get("hooks", [])) - len(kept)
        if kept:
            grp["hooks"] = kept; groups.append(grp)
    if groups: hooks[ev] = groups
    else: del hooks[ev]
if not hooks:
    data.pop("hooks", None)
tmp = settings + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
os.replace(tmp, settings)
print(f"unwired {removed} prompt-coach hook(s) from " + settings if removed
      else "no prompt-coach hooks found in " + settings)
PY
fi

# Unwire step-status: restore the wrapped status line (or drop the standalone one) and its hook.
if [ "$removed_step_status" = 1 ] && [ -f "$SETTINGS" ]; then
  CLAUDE_SETTINGS="$SETTINGS" bash "$REPO/step-status/scripts/wire_statusline.sh" --unwire
fi

echo
echo "done."
