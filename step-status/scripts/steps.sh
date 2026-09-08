#!/usr/bin/env bash
# step-status CLI — record where a multi-step workflow is, so the status line can
# render a chain like:  init ✓ → loop|check agent status ● → summary ○
#
#   steps.sh set <name>...            define the chain; first step becomes active
#   steps.sh start <name> [detail]    mark a step in progress (detail shows as name|detail)
#   steps.sh done <name>              mark done; activates the next planned step if none is active
#   steps.sh fail <name>              mark failed
#   steps.sh msg sent|recv <session> [text]   note a cross-session message on the active step
#                                     (detail becomes "⇢ session: text" / "⇠ session: text")
#   steps.sh render                   print the current chain (nothing if no chain)
#   steps.sh clear                    remove the current chain (and its note)
#   steps.sh use <chain>              switch to (or create) a named chain; the status line follows
#   steps.sh list                     all chains in this dir: * marks current, with notes
#   steps.sh note [text]              set (or print) a one-line context note for the current chain
#   steps.sh --selfcheck              run the built-in check
#
# State: $STEP_STATUS_DIR (default ./.step-status). `current` names the active chain (default:
# "default"); <chain>.state holds one step per line, <chain>.note an optional context line:
#   <status>\t<name>\t<detail>     status ∈ planned|active|done|failed
set -uo pipefail
# ponytail: cwd-keyed — two sessions in one dir clobber each other; key by session if that bites.

DIR="${STEP_STATUS_DIR:-$PWD/.step-status}"
CHAIN="$( [[ -f "$DIR/current" && ! -L "$DIR/current" ]] && head -c 200 "$DIR/current" | tr -d '\n' )"
CHAIN="${CHAIN:-default}"
STATE="$DIR/$CHAIN.state"
NOTE="$DIR/$CHAIN.note"

sym() { case "$1" in done) printf '✓';; active) printf '●';; failed) printf '✗';; *) printf '○';; esac; }

# State lives inside the project cwd, which a cloned repo controls: never follow symlinks
# and never echo control characters into the terminal.
safe_state() {
  if [[ -L "$DIR" || -L "$STATE" || -L "$NOTE" ]]; then echo "steps.sh: refusing symlinked $DIR" >&2; return 1; fi
}
valid_name() {
  [[ -n "$1" && "$1" != *$'\t'* && "$1" != *$'\n'* ]] || { echo "steps.sh: invalid step name/detail (empty, tab or newline)" >&2; return 2; }
}
# Chain names become file names: keep them to a safe charset.
valid_chain() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "steps.sh: invalid chain name '$1' (letters, digits, . _ -)" >&2; return 2; }
}

# render_file <state-file> — one line, or nothing if the file is missing/empty.
render_file() {
  [[ -f "$1" && ! -L "$1" ]] || return 0
  local out="" st name detail
  while IFS=$'\t' read -r st name detail; do
    [[ -z "$name" ]] && continue
    [[ -n "$out" ]] && out+=" → "
    out+="$name"; [[ -n "$detail" ]] && out+="|$detail"
    out+=" $(sym "$st")"
  done < "$1"
  [[ -n "$out" ]] && printf '%s\n' "$out" | tr -d '\000-\010\013-\037\177'
}
# Current chain; prefixed with [name] when it is not the default one.
render() {
  safe_state || return 0
  local line; line="$(render_file "$STATE")"
  [[ -z "$line" ]] && return 0
  [[ "$CHAIN" == default ]] && printf '%s\n' "$line" || printf '[%s] %s\n' "$CHAIN" "$line"
}

use_chain() {
  valid_chain "$1" || return 2
  ensure_dir || return 1
  printf '%s\n' "$1" > "$DIR/current"
  local line; line="$(render_file "$DIR/$1.state")"
  echo "chain: $1${line:+ — $line}${line:- (empty — run 'set')}"
}

list_chains() {
  [[ -d "$DIR" ]] || return 0
  local f n mark note
  for f in "$DIR"/*.state; do
    [[ -f "$f" ]] || continue
    n="$(basename "$f" .state)"; mark=" "; [[ "$n" == "$CHAIN" ]] && mark="*"
    note=""; [[ -f "$DIR/$n.note" && ! -L "$DIR/$n.note" ]] && note="$(head -n1 "$DIR/$n.note" | tr -d '\000-\037\177')"
    printf '%s %s: %s%s\n' "$mark" "$n" "$(render_file "$f")" "${note:+  # $note}"
  done
}

note_chain() {
  ensure_dir || return 1
  if [[ $# -eq 0 ]]; then [[ -f "$NOTE" ]] && head -n1 "$NOTE"; return 0; fi
  valid_name "$*" || return 2
  printf '%s\n' "$*" > "$NOTE"
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

# msg sent|recv <session> [text] — record inter-session comms as the active step's detail.
msg_step() {
  local dir="${1-}" who="${2-}" text="${3-}" arrow st name detail active=""
  case "$dir" in sent) arrow='⇢';; recv) arrow='⇠';; *) echo "usage: steps.sh msg sent|recv <session> [text]" >&2; return 2;; esac
  [[ -n "$who" ]] || { echo "usage: steps.sh msg sent|recv <session> [text]" >&2; return 2; }
  valid_name "$who$text" || return 2
  [[ -f "$STATE" ]] || { echo "steps.sh: no chain — run 'set' first" >&2; return 1; }
  safe_state || return 1
  while IFS=$'\t' read -r st name detail; do [[ "$st" == active ]] && { active="$name"; break; }; done < "$STATE"
  [[ -n "$active" ]] || { echo "steps.sh: no active step to attach the message to" >&2; return 1; }
  update "$active" active "$arrow $who${text:+: $text}"
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
  printf 'active\tx\e[31mred\t\n' > "$d/default.state"; [[ "$(r)" == "x[31mred ●" ]] || fail control-chars
  ln -sfn /dev/null "$d/default.state"; bash "$s" set p 2>/dev/null && fail symlink-followed
  rm -f "$d/default.state"
  # named chains: switch, keep both, notes, list, clear only the current one
  bash "$s" set a b; bash "$s" use pr >/dev/null; bash "$s" set x y z; bash "$s" done x
  bash "$s" note "reviewing PR 42"
  [[ "$(r)" == "[pr] x ✓ → y ● → z ○" ]] || fail named-render
  [[ "$(bash "$s" note)" == "reviewing PR 42" ]] || fail note-read
  bash "$s" use default >/dev/null; [[ "$(r)" == "a ● → b ○" ]] || fail switch-back
  [[ "$(bash "$s" list)" == $'* default: a ● → b ○\n  pr: x ✓ → y ● → z ○  # reviewing PR 42' ]] || fail "list: $(bash "$s" list)"
  bash "$s" use pr >/dev/null; bash "$s" clear; [[ -z "$(r)" && ! -e "$d/pr.note" ]] || fail named-clear
  [[ -f "$d/default.state" ]] || fail clear-scoped
  bash "$s" use ../evil 2>/dev/null && fail bad-chain-name
  # inter-session comms land on the active step
  bash "$s" use default >/dev/null; bash "$s" set ask wait >/dev/null; bash "$s" msg sent RCM-info "need diagnostics" >/dev/null
  [[ "$(r)" == "ask|⇢ RCM-info: need diagnostics ● → wait ○" ]] || fail "msg-sent: $(r)"
  bash "$s" done ask >/dev/null; bash "$s" msg recv RCM-info >/dev/null
  [[ "$(r)" == "ask ✓ → wait|⇠ RCM-info ●" ]] || fail "msg-recv: $(r)"
  bash "$s" msg bogus x 2>/dev/null && fail msg-bad-direction
  bash "$s" clear
  [[ "$(cat "$d/.gitignore")" == "*" ]] || fail gitignore
  rm -rf "$d"; echo "selfcheck OK"
}

main() {
  local cmd="${1:-render}"; shift || true
  case "$cmd" in
    set)   set_chain "$@" && render ;;
    start) need_name "${1-}" start && valid_name "${2-x}" && update "$1" active "${2-}" && render ;;
    done)  need_name "${1-}" done && update "$1" done && render ;;
    fail)  need_name "${1-}" fail && update "$1" failed && render ;;
    msg)   msg_step "$@" && render ;;
    render) render ;;
    clear) [[ -L "$STATE" || -L "$NOTE" ]] || rm -f "$STATE" "$NOTE" ;;
    use)   need_name "${1-}" use && use_chain "$1" ;;
    list)  list_chains ;;
    note)  note_chain "$@" ;;
    --selfcheck) selfcheck ;;
    -h|--help) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *) echo "steps.sh: unknown command '$cmd'" >&2; return 2 ;;
  esac
}
main "$@"
