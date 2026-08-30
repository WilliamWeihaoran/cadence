#!/bin/zsh
# Guarded xcodebuild. Use this instead of calling xcodebuild directly.
#
#   ./scripts/xcb.sh <id> build [extra xcodebuild args...]
#   ./scripts/xcb.sh <id> test  [extra xcodebuild args...]     # takes the test-host lock
#   ./scripts/xcb.sh <id> raw   <every arg, including the action>
#   ./scripts/xcb.sh audit                                     # report shared-DerivedData leaks
#   ./scripts/xcb.sh check-test-log <log>                      # the zero-test guard, on its own
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
# 3. A GREEN RUN OVER ZERO TESTS (T-552). `-only-testing:` takes a SUITE name, not a file name,
#    and a name matching nothing is not an error: xcodebuild prints `Executed 0 tests`,
#    `** TEST SUCCEEDED **` and exits 0, with no warning and no diagnostic. Measured 2026-08-31,
#    33 of this repository's 255 test files declare more than one suite and 14 declare none named
#    after the file, so scoping a run by *filename* against any of those exercises nothing and
#    reports success -- which is character for character what "the mutation survived" looks like.
#    The prose rule for it lives in docs/SUBAGENT_RUNBOOK.md and is exactly the kind of step an
#    agent under time pressure skips, so the runner enforces it instead: a `test` action that
#    xcodebuild called successful while running no test at all exits 4 from here.
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

# --- the zero-test guard (T-552) ---------------------------------------------
# Evidence that a test RAN, in the two shapes this repository's logs use: swift-testing's
# `✔ Test name()` / `✘ Test name()`, and XCTest's `Test Case '-[Suite testName]' passed`.
#
# The `Executed N tests` summary is deliberately NOT the signal. It is the line a run that died
# before reaching any test never prints at all, so keying on it would read total silence as a full
# run; and its own text is what a filtered-to-nothing run reports zero on. Counting per-test result
# lines answers the only question that matters -- did anything actually execute -- from evidence
# that has to be produced rather than from a summary that has to be absent.
#
# No `^` in the pattern, deliberately: grep anchors it per line and ICU anchors it to the whole
# string, and CadenceBuildInvocationHygieneTests lifts this exact pattern out of this file and runs
# it against literal log fixtures to prove it still discriminates. An anchor the two engines read
# differently would make that check evidence about something other than this script.
TEST_RESULT_PATTERN='(✔|✘) Test [A-Za-z0-9_]+\(\)|Test Case .*(passed|failed)'

tests_seen() { grep -acE "$TEST_RESULT_PATTERN" "$1" 2>/dev/null | tr -d ' '; }

# Everything the caller needs to fix an empty run, printed where the empty run happened.
empty_run_diagnostic() {
  local log="$1"
  say ""
  say "!! REFUSING: this test run executed 0 tests, and xcodebuild called that a success."
  say "   ** TEST SUCCEEDED ** over an empty filter is indistinguishable from a passing suite,"
  say "   and from a surviving mutation. It is being reported as a failure here instead (T-552)."
  # The filter is read back off xcodebuild's own "Command line invocation" line, which quotes its
  # arguments -- so the character class stops at a quote as well as at a space, or the identifier
  # is reported with a stray `"` glued to it and reads like part of the suite name.
  local requested=(${(f)"$(grep -oE -- '-only-testing:[^ "'"'"']*' "$log" 2>/dev/null | sort -u)"})
  if (( ${#requested} )); then
    say "   the run was filtered to:"
    for f in $requested; do say "     $f"; done
    say "   \`-only-testing:\` takes a SUITE name, not a file name. Ask the source which suite"
    say "   declares your test:  ./scripts/test-suite-index.sh <testName>"
  else
    say "   the run named no -only-testing: filter, so this is not a mis-scoped suite --"
    say "   the test target built but nothing ran. Read $log from the top."
  fi
}

if [[ "${1:-}" == "check-test-log" ]]; then
  CHECK_LOG="${2:-}"
  if [[ ! -f "$CHECK_LOG" ]]; then
    say "usage: ./scripts/xcb.sh check-test-log <logfile>"; exit 2
  fi
  CHECK_RAN=$(tests_seen "$CHECK_LOG")
  if (( CHECK_RAN == 0 )); then
    empty_run_diagnostic "$CHECK_LOG"
    exit 4
  fi
  say "$CHECK_RAN test result(s) in $CHECK_LOG"
  exit 0
fi

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

# `raw` is how a caller reaches `test-without-building`, so the guard keys on the actions that
# execute tests rather than on `$ACTION` alone -- otherwise the one route that skips the build,
# and so the one most likely to be re-run in a mutation loop, is the one route with no guard.
IS_TEST_RUN=0
for a in "${run_args[@]}"; do
  [[ "$a" == "test" || "$a" == "test-without-building" ]] && IS_TEST_RUN=1
done

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
if (( IS_TEST_RUN )); then
  RAN=$(tests_seen "$LOG")
  say "  tests executed:  $RAN"
  if (( RAN == 0 )); then
    empty_run_diagnostic "$LOG"
    (( STATUS == 0 )) && STATUS=4
  fi
fi
if [[ "$(shared_cadence_entries)" != "$before_entries" ]]; then
  say ""
  say "!! LEAK: a shared DerivedData entry appeared during this run, despite the private path."
  say "   Something in the build reached the default location. ./scripts/xcb.sh audit lists them."
fi
say "  (delete $DD when you are done; a full one is ~1.7 GB)"
exit $STATUS
