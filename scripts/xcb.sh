#!/bin/zsh
# Guarded xcodebuild. Use this instead of calling xcodebuild directly.
#
#   ./scripts/xcb.sh <id> build [extra xcodebuild args...]
#   ./scripts/xcb.sh <id> test  [extra xcodebuild args...]     # takes the test-host lock
#   ./scripts/xcb.sh <id> raw   <every arg, including the action>
#   ./scripts/xcb.sh audit                                     # report shared-DerivedData leaks
#
# `-project Cadence.xcodeproj` is supplied for you; pass `-scheme` and `-destination` yourself.
#
# It exists because two hazards in this repository produce no diagnostic of their own, so both
# get misread as broken code (docs/TODO.md T-86 and T-117).
#
# 1. DERIVED DATA (T-86). A private `-derivedDataPath` has been the standing rule since
#    2026-08-18, and the rule is right: the shared path is one mutable directory, and a clean
#    build there deletes `Build/Products/` under anything already running from it -- which
#    surfaces as `EXC_BREAKPOINT` in `libsecinit` before `main()`, i.e. as an app crash. What the
#    rule cannot do is cover a command nobody rereads. Measured 2026-08-30: even a read-only
#    `xcodebuild -showBuildSettings` with no flag creates the shared entry for the project's path
#    and resolves packages into it. This script never lets an invocation reach the default path,
#    refuses a `-derivedDataPath` aimed at the shared root, and reports afterwards if a shared
#    entry appeared anyway -- the report is the point, since a leak is otherwise invisible.
#
# 2. PROJECT-FILE LOCK (T-117). `NSFileCoordinator` serialises reads of `Cadence.xcodeproj`, and
#    a run can block in `_blockOnAccessClaim` behind another claimant -- a concurrent xcodebuild,
#    or the user's Xcode with the project open. Confirmed twice by `sample`. It emits nothing at
#    all: the log stops at the "Command line invocation" line and the process sits at 0% CPU,
#    which reads exactly like a broken checkout. It cannot be detected in advance -- a coordinated
#    access claim is not an open file descriptor, so `lsof` on `project.pbxproj` shows nothing
#    even while a build holds it (measured 2026-08-30). The only observable is the stalled
#    process's own stack, so the watchdog below takes it: if the log stops advancing while the
#    process is idle, it samples and prints the verdict instead of leaving you with silence.
#
# It never kills anything. The user's Cadence, the user's Xcode and other agents' builds are all
# off limits; a stall is reported, and the decision to wait or abandon stays with the caller.

set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODEBUILD="${XCODEBUILD:-/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild}"
SHARED_DD="$HOME/Library/Developer/Xcode/DerivedData"
# How long the log may stand still, with the process idle, before we call it a stall and sample.
STALL_SECONDS=${CADENCE_STALL_SECONDS:-180}
STALL_POLL=${CADENCE_STALL_POLL:-30}
say() { print -r -- "$@" }
# $TMPDIR ends in a slash here and may be unset elsewhere; normalise once rather than writing
# /private/tmpcadence-dd-x on a machine without it.
TMP_BASE="${TMPDIR:-/private/tmp/}"; [[ "$TMP_BASE" != */ ]] && TMP_BASE="$TMP_BASE/"

shared_cadence_entries() {
  print -rn -- "$(ls -d "$SHARED_DD"/Cadence-* 2>/dev/null | sort)"
}

if [[ "${1:-}" == "audit" ]]; then
  say "== shared DerivedData entries for this project =="
  say "   (\"has Build/\" is the dangerous shape: a clean build there wipes it under a running app)"
  local_found=0
  for d in "$SHARED_DD"/Cadence-*(N/); do
    local_found=1
    shape=$([[ -d "$d/Build/Products" ]] && print "has Build/Products" || print "logs+packages only")
    say "  ${d:t}  $(date -r "$d" '+%Y-%m-%d %H:%M')  $(du -sh "$d" 2>/dev/null | cut -f1)  $shape"
  done
  (( local_found )) || say "  none"
  say ""
  say "  An entry per project PATH, so scratch trees get their own and the repository root shares"
  say "  the one Xcode uses. Nothing is deleted from here: one of these is the user's."
  exit 0
fi

ID="${1:-}"; ACTION="${2:-}"
if [[ -z "$ID" || -z "$ACTION" ]]; then
  say "usage: ./scripts/xcb.sh <id> build|test|raw [args...]   |   ./scripts/xcb.sh audit"; exit 2
fi
shift 2

# --- the DerivedData guard ---------------------------------------------------
# A caller may supply its own path; it may not supply the shared one, and it may not omit one.
DD=""
args=("$@")
for (( i = 1; i <= ${#args}; i++ )); do
  if [[ "${args[i]}" == "-derivedDataPath" ]]; then DD="${args[i+1]:-}"; fi
done
if [[ -n "$DD" ]]; then
  case "${DD:A}" in
    "${SHARED_DD:A}"/*|"${SHARED_DD:A}")
      say "REFUSING: -derivedDataPath '$DD' is inside the shared DerivedData."
      say "  That is the T-86 hazard exactly: a build there deletes Build/Products/ under the"
      say "  user's running app and under Xcode. Pass a path under \${TMPDIR} or /private/tmp."
      exit 3 ;;
  esac
else
  DD="${TMP_BASE}cadence-dd-$ID"
  args+=(-derivedDataPath "$DD")
fi
LOG="${TMP_BASE}cadence-xcb-$ID.log"

# --- preflight ---------------------------------------------------------------
say "== xcb preflight ($ID) =="
say "  derivedDataPath: $DD"
say "  log:             $LOG"
# Anchored, and matching the binary path: an unanchored `pgrep -f xcodebuild` counts this script
# and every wait loop whose own command text spells the word.
others=$(pgrep -f '^/Applications/.*/xcodebuild' 2>/dev/null | grep -vx "$$" | wc -l | tr -d ' ')
say "  other xcodebuild processes: $others"
if (( $(pgrep -x Xcode 2>/dev/null | wc -l) > 0 )); then
  say "  WARNING: Xcode is running. T-117's mitigation is to quit it while a batch of agents"
  say "           builds; an open project is a standing claimant on Cadence.xcodeproj."
fi
before_entries="$(shared_cadence_entries)"

# --- the test-host lock ------------------------------------------------------
# Only `test` needs it: it is the app-group container that two hosts corrupt (T-236), not the
# build output. Acquire and release under the SAME id -- a mismatch makes `release` refuse and
# strands the lock for the rest of its lease.
if [[ "$ACTION" == "test" ]]; then
  "$ROOT_DIR/scripts/test-host-lock.sh" acquire "${CADENCE_LOCK_TIMEOUT:-5400}" "xcb-$ID" || exit 1
  trap "\"$ROOT_DIR/scripts/test-host-lock.sh\" release 'xcb-$ID'" EXIT INT TERM
fi

# --- the T-117 stall watchdog ------------------------------------------------
# Reports, never kills. `sample` on our own child is what turns silence into a verdict.
watchdog() {
  local target="$1" still=0 last=-1
  while sleep "$STALL_POLL"; do
    kill -0 "$target" 2>/dev/null || return 0
    local size=$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')
    local cpu=$(ps -o %cpu= -p "$target" 2>/dev/null | tr -d ' ')
    if [[ "$size" == "$last" && "${cpu%%.*}" == "0" ]]; then
      (( still += STALL_POLL ))
    else
      still=0
    fi
    last="$size"
    (( still < STALL_SECONDS )) && continue
    say ""
    say "!! xcb: no output and 0% CPU for ${still}s (pid $target). Sampling before you debug Swift."
    local stack=$(sample "$target" 3 -mayDie 2>/dev/null)
    if print -r -- "$stack" | grep -q '_blockOnAccessClaim\|NSFileCoordinator'; then
      say "!! T-117 CONFIRMED: blocked in NSFileCoordinator on the project file, not compiling."
      say "   Another claimant holds Cadence.xcodeproj -- a concurrent xcodebuild, or Xcode."
      say "   This is not a broken checkout and not your change. Wait it out, or quit Xcode."
    elif [[ -z "$stack" ]]; then
      say "?? could not sample pid $target; treat total silence as T-117 until shown otherwise."
    else
      say "?? stalled, but not in _blockOnAccessClaim. Top frames:"
      print -r -- "$stack" | grep -m 5 '^ *[0-9]* ' || true
    fi
    still=0
  done
}

# --- run ---------------------------------------------------------------------
case "$ACTION" in
  build|test) run_args=("${args[@]}" "$ACTION") ;;
  raw)        run_args=("${args[@]}") ;;
  *) say "unknown action '$ACTION'"; exit 2 ;;
esac

"$XCODEBUILD" -project "$ROOT_DIR/Cadence.xcodeproj" "${run_args[@]}" > "$LOG" 2>&1 &
XCB_PID=$!
watchdog "$XCB_PID" &
WATCHDOG_PID=$!
wait "$XCB_PID"; STATUS=$?
kill "$WATCHDOG_PID" 2>/dev/null

# --- postflight --------------------------------------------------------------
say ""
say "== xcb result ($ID) =="
say "  XCODEBUILD_EXIT=$STATUS"
# The compile-error count, spelled the way AGENTS.md requires: a loose `grep -c 'error:'` counts a
# test failure whose message contains the word and reads a real kill as a build break.
say "  compile errors:  $(grep -cE '\.swift:[0-9]+:[0-9]+: error:' "$LOG" | tr -d ' ')"
say "  warnings:        $(grep -c 'warning:' "$LOG" | tr -d ' ')"
if [[ "$(shared_cadence_entries)" != "$before_entries" ]]; then
  say ""
  say "!! LEAK: a shared DerivedData entry appeared during this run, despite the private path."
  say "   Something in the build reached the default location. ./scripts/xcb.sh audit lists them."
fi
say "  (delete $DD when you are done; a full one is ~1.7 GB)"
exit $STATUS
