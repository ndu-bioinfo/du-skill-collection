#!/usr/bin/env bash
# step-status CLI — record where a multi-step workflow is, so the status line can
# render a chain like:  init ✓ → loop|check agent status ● → summary ○
#
#   steps.sh set <name>...            define the chain; first step becomes active
#   steps.sh start <name> [detail]    mark a step in progress (detail shows as name|detail)
#   steps.sh done <name>              mark done; activates the next planned step if none is active
#   steps.sh fail <name>              mark failed
#   steps.sh render                   print the chain (nothing if no chain)
#   steps.sh clear                    remove the chain
#   steps.sh --selfcheck              run the built-in check
#
# State: $STEP_STATUS_DIR/state (default ./.step-status/state), one step per line:
#   <status>\t<name>\t<detail>     status ∈ planned|active|done|failed
set -uo pipefail
# ponytail: cwd-keyed — two sessions in one dir clobber each other; key by session if that bites.

DIR="${STEP_STATUS_DIR:-$PWD/.step-status}"
STATE="$DIR/state"

sym() { case "$1" in done) printf '✓';; active) printf '●';; failed) printf '✗';; *) printf '○';; esac; }

# State lives inside the project cwd, which a cloned repo controls: never follow symlinks
# and never echo control characters into the terminal.
safe_state() {
  if [[ -L "$DIR" || -L "$STATE" ]]; then echo "steps.sh: refusing symlinked $DIR" >&2; return 1; fi
}
valid_name() {
  [[ -n "$1" && "$1" != *$'\t'* && "$1" != *$'\n'* ]] || { echo "steps.sh: invalid step name/detail (empty, tab or newline)" >&2; return 2; }
}

render() {
  [[ -f "$STATE" ]] || return 0
  safe_state || return 0
  local out="" st name detail
  while IFS=$'\t' read -r st name detail; do
    [[ -z "$name" ]] && continue
    [[ -n "$out" ]] && out+=" → "
    out+="$name"; [[ -n "$detail" ]] && out+="|$detail"
    out+=" $(sym "$st")"
  done < "$STATE"
  [[ -n "$out" ]] && printf '%s\n' "$out" | tr -d '\000-\010\013-\037\177'
}

ensure_dir() {
  mkdir -p "$DIR" || return 1
  safe_state || return 1
  [[ -f "$DIR/.gitignore" ]] || printf '*\n' > "$DIR/.gitignore"
}

# Atomic write: stdin → $STATE via a temp file in the same dir.
write_state() { local tmp; tmp="$(mktemp "$DIR/.state.XXXXXX")" || return 1; cat > "$tmp" && mv -f "$tmp" "$STATE"; }

# update <name> <status> [detail] — rewrite matching row. After `done`, activate the first
# planned row only if no row is active (out-of-order use never yields two ● at once).
update() {
  local target="$1" newst="$2" newdetail="${3-}" hit=0 any_active=0 i
  local -a sts=() names=() details=()
  [[ -f "$STATE" ]] || { echo "steps.sh: no chain — run 'set' first" >&2; return 1; }
  safe_state || return 1
  while IFS=$'\t' read -r st name detail; do
    [[ -z "$name" ]] && continue
    if [[ "$name" == "$target" ]]; then st="$newst"; detail="$newdetail"; hit=1; fi
    sts+=("$st"); names+=("$name"); details+=("$detail")
  done < "$STATE"
  [[ $hit == 1 ]] || { echo "steps.sh: unknown step '$target'" >&2; return 1; }
  for st in "${sts[@]}"; do [[ "$st" == active ]] && any_active=1; done
  if [[ "$newst" == done && $any_active == 0 ]]; then
    for i in "${!sts[@]}"; do [[ "${sts[$i]}" == planned ]] && { sts[$i]=active; break; }; done
  fi
  for i in "${!sts[@]}"; do printf '%s\t%s\t%s\n' "${sts[$i]}" "${names[$i]}" "${details[$i]}"; done | write_state
}

set_chain() {
  [[ $# -ge 1 ]] || { echo "usage: steps.sh set <name>..." >&2; return 2; }
  local n seen=$'\n'
  for n in "$@"; do
    valid_name "$n" || return 2
    [[ "$seen" == *$'\n'"$n"$'\n'* ]] && { echo "steps.sh: duplicate step name '$n'" >&2; return 2; }
    seen+="$n"$'\n'
  done
  ensure_dir || return 1
  { printf 'active\t%s\t\n' "$1"; shift; for n in "$@"; do printf 'planned\t%s\t\n' "$n"; done; } | write_state
}

need_name() { [[ -n "${1-}" ]] || { echo "usage: steps.sh $2 <name>" >&2; return 2; }; }

selfcheck() {
  local d s; d="$(mktemp -d)"; s="${BASH_SOURCE[0]}"; export STEP_STATUS_DIR="$d"
  r() { bash "$s" render; }
  fail() { echo "FAIL $1: $(r)"; exit 1; }
  bash "$s" set init loop summary
  [[ "$(r)" == "init ● → loop ○ → summary ○" ]] || fail set
  bash "$s" done init; bash "$s" start loop "check agent status"
  [[ "$(r)" == "init ✓ → loop|check agent status ● → summary ○" ]] || fail start
  bash "$s" done loop
  [[ "$(r)" == "init ✓ → loop ✓ → summary ●" ]] || fail auto-next
  bash "$s" fail summary
  [[ "$(r)" == "init ✓ → loop ✓ → summary ✗" ]] || fail fail
  bash "$s" set a b c; bash "$s" start b; bash "$s" done a
  [[ "$(r)" == "a ✓ → b ● → c ○" ]] || fail out-of-order
  bash "$s" set a a b 2>/dev/null && fail duplicate-accepted
  bash "$s" set $'a\tb' 2>/dev/null && fail tab-name-accepted
  bash "$s" set "" b 2>/dev/null && fail empty-name-accepted
  out="$(bash "$s" start 2>&1)"; [[ $? -ne 0 && "$out" != *unbound* ]] || fail start-no-arg
  bash "$s" done zzz 2>/dev/null && fail unknown-step-accepted
  bash "$s" --bogus 2>/dev/null && fail unknown-cmd-accepted
  bash "$s" clear; [[ -z "$(r)" ]] || fail clear
  printf 'active\tx\e[31mred\t\n' > "$d/state"; [[ "$(r)" == "x[31mred ●" ]] || fail control-chars
  ln -sfn /dev/null "$d/state"; bash "$s" set p 2>/dev/null && fail symlink-followed
  [[ "$(cat "$d/.gitignore")" == "*" ]] || fail gitignore
  rm -rf "$d"; echo "selfcheck OK"
}

main() {
  local cmd="${1:-render}"; shift || true
  case "$cmd" in
    set)   set_chain "$@" ;;
    start) need_name "${1-}" start && valid_name "${2-x}" && update "$1" active "${2-}" ;;
    done)  need_name "${1-}" done && update "$1" done ;;
    fail)  need_name "${1-}" fail && update "$1" failed ;;
    render) render ;;
    clear) [[ -L "$STATE" ]] || rm -f "$STATE" ;;
    --selfcheck) selfcheck ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) echo "steps.sh: unknown command '$cmd'" >&2; return 2 ;;
  esac
}
main "$@"
