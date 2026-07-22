#!/usr/bin/env bash
# Uninstall skills that were installed from this repo (remove the symlinks in
# ~/.claude/skills/, and, for prompt-coach, unwire its hooks from settings.json).
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
for name in "${NAMES[@]}"; do
  dst="$SKILLS_DIR/$name"
  if [ ! -L "$dst" ]; then
    [ -e "$dst" ] && echo "skip: $dst is not a symlink — leaving it alone" >&2
    continue
  fi
  target="$(readlink "$dst")"
  case "$target" in
    "$REPO/"*) rm -f "$dst"; echo "uninstalled: $name"
               [ "$name" = "prompt-coach" ] && removed_prompt_coach=1 ;;
    *) echo "skip: $dst points to $target (not this repo) — leaving it alone" >&2 ;;
  esac
done

# Unwire prompt-coach hooks from settings.json (only entries that reference THIS repo).
if [ "$removed_prompt_coach" = 1 ] && [ -f "$SETTINGS" ]; then
  REPO="$REPO" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os
settings = os.environ["SETTINGS"]; marker = os.environ["REPO"] + "/prompt-coach/scripts/"
with open(settings) as f:
    try: data = json.load(f) or {}
    except Exception: data = {}
hooks = data.get("hooks", {})
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
with open(settings, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
print(f"unwired {removed} prompt-coach hook(s) from " + settings if removed
      else "no prompt-coach hooks found in " + settings)
PY
fi

echo
echo "done."
