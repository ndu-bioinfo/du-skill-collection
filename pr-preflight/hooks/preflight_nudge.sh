#!/bin/bash
# PostToolUse(Bash) hook. After `gh pr create` or a `git push`, it asks `preflight.py nudge` what,
# if anything, to tell Claude. The script owns the config, opt-out and marker rules, so this file
# only matches commands. The hook never blocks and never writes files, and anything unexpected ends
# in a silent exit 0.

input=$(cat)
# This runs after every Bash call, so leave with builtins alone unless the payload could hold
# either command at all.
case "$input" in *gh*pr*create*|*gh*api*pulls*|*git*push*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 0

script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/preflight.py"
{ IFS= read -r cwd; cmd=$(cat); } < <(printf '%s' "$input" | jq -r '(.cwd // ""), (.tool_input.command // "")' 2>/dev/null)
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null

# Match only a real command, at the start of the line or after a shell separator, so `echo 'git push'` doesn't count.
sep='(^|[;&|(][[:space:]]*)'
# A PR is created by `gh pr create`, or over REST by `gh api .../pulls` with a POST (the fallback
# when GraphQL is rate-limited, which `gh pr create` depends on).
create_re="${sep}gh[[:space:]]+pr[[:space:]]+create([[:space:]]|\$)"
# The endpoint and the POST must belong to the same `gh api` call. The script tokenises the
# command with shlex, so separators inside quotes (`-f body="a; b"`) don't split a call.
rest_post() { case "$cmd" in *gh*api*pulls*) printf '%s' "$cmd" | python3 "$script" is-rest-create ;; *) return 1 ;; esac; }
if printf '%s\n' "$cmd" | grep -Eq "$create_re" || rest_post; then
  # Both print the new PR URL on success (gh api inside its JSON); no URL means it failed.
  # The strict charset keeps a crafted URL from carrying shell syntax into the suggested command.
  url=$(printf '%s' "$input" | jq -r '.tool_response.stdout // empty' 2>/dev/null |
    grep -Eo 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | tail -n 1)
  [ -n "$url" ] && python3 "$script" nudge created "$url" 2>/dev/null
elif printf '%s\n' "$cmd" | grep -Eq "${sep}git[[:space:]]+push([[:space:]]|\$)"; then
  # The script reads git's own report of what was pushed from the payload.
  printf '%s' "$input" | python3 "$script" nudge pushed 2>/dev/null
fi
exit 0
