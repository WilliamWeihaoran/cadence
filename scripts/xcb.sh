#!/bin/zsh
# Guarded xcodebuild. Use this instead of calling xcodebuild directly.
#
#   ./scripts/xcb.sh <id> build [extra xcodebuild args...]
#   ./scripts/xcb.sh <id> test  [extra xcodebuild args...]     # takes the test-host lock
#   ./scripts/xcb.sh <id> raw   <every arg, including the action>
#   ./scripts/xcb.sh audit                                     # report shared-DerivedData leaks
#   ./scripts/xcb.sh check-test-log <log> [xcodebuild-exit]    # the zero-test guard, on its own
#   ./scripts/xcb.sh check-suites-started <log> [args...]      # the per-suite guard, on its own
#   ./scripts/xcb.sh check-warnings <log>                      # the diagnostic counters, on their own
#   ./scripts/xcb.sh check-host-launch <log> [xcodebuild-exit] # the refused-relaunch report (T-1992)
#   ./scripts/xcb.sh check-entitlements <log> [exit] [dd-path] # the poisoned-DerivedData report (T-2046)
#   ./scripts/xcb.sh check-sleep <start> <end> [exit]          # did the Mac sleep in that window (T-2048)
#   ./scripts/xcb.sh check-automation                        # is an "Enable UI Automation" prompt standing? (T-2070)
#   ./scripts/xcb.sh check-only-testing <CadenceTests/Suite>   # resolve a filter, no build
#   ./scripts/xcb.sh last-green                                # is HEAD still the last full green? (T-2042)
#   ./scripts/xcb.sh run-state [<id>...]                       # QUEUED / RUNNING / WEDGED (T-2071)
#   ./scripts/xcb.sh release-dd <id|path>                      # delete a DerivedData no live build uses
#   ./scripts/xcb.sh check-destination <-destination value>   # resolve a simulator, no build
#   ./scripts/xcb.sh selftest                                  # prove the refusals still fire
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
# 4. A TEST RUN AGAINST A CHECKOUT THAT IS NOT HEAD (T-975). `agent-commit.sh` commits through a
#    private index so a landed commit never writes the shared checkout; the checkout therefore
#    drifts behind HEAD, and `git status` reports a stale copy in the same three characters it
#    reports real in-flight work with. A `test` action runs `scripts/worktree-drift.sh check`
#    first and exits 7 without taking the test-host lock if any tracked file is behind HEAD --
#    and asks again once it HOLDS the lock, warning when the tree moved during the wait or during
#    the run itself (T-3060).
#
# 5. A DECLINED HUNK NOBODY IS COMING BACK FOR (T-781). `agent-commit.sh` records the lines a
#    reconstruction declined, and the record is checked only when somebody next commits THAT path.
#    If nobody does, the first thing that happens is DECLINED-HUNK-STALE refusing every commit in
#    the checkout, half an hour later, to whoever happens to commit next. Measured 2026-09-05: an
#    agent died mid-commit leaving a stranded record, and it was found by a coordinator running
#    `check` by hand. So every run of this script ends by listing outstanding records with their
#    age and how long until they wall off the checkout. It REPORTS: `$STATUS` is never touched
#    here, because a fresh record is ordinary in-flight work and gating on it would refuse the
#    normal case dozens of times per `mutate.sh` needle (T-986). The gate stays in the heartbeat.
#
# 6. A SCOPED RUN THAT SILENTLY SKIPS HALF ITS FILE (T-1076). Hazard 3 catches a filter that
#    selects NOTHING. It is blind to a filter that selects SOME of what the caller meant, which is
#    the larger population: 26 files declare a suite named after the file AND siblings beside it,
#    and scoping one by filename runs a real suite, exits 0, and skips 311 of the 688 tests in
#    those files -- 45%, measured 2026-09-06. A short green run looks exactly like a fast one. So
#    `-only-testing:` names are now resolved against the source BEFORE the build and before the
#    lock: an unknown name is refused (exit 8), and a known name leaving siblings behind is
#    PRINTED with their test counts and the run continues, because a multi-suite file is usually
#    organised that way on purpose and a guard that fails the normal case gets switched off.
#
# 7. A WARNING BASELINE NOTHING LOCAL ENFORCED (T-1149). "The warning baseline is zero and any new
#    warning is a regression" is in AGENTS.md, CLAUDE.md, the release checklist and every brief;
#    `.github/scripts/check-log.sh` really does enforce it in CI, and nothing enforced it here. A
#    build introducing ten Swift warnings exited 0, and the count sat in one banner line among
#    nine. Since 2026-09-12 a run that RECOMPILED SWIFT and produced anchored warnings exits 9,
#    and prints them. A run that compiled nothing never gates -- that count is vacuous and saying
#    so is what T-1147 built -- and `CADENCE_ALLOW_WARNINGS=1` downgrades it to the old report for
#    the one caller that legitimately builds a non-baseline tree (`mutate.sh`). Measured at
#    17b5b61: 0 anchored warnings over 669 + 345 compile tasks, so this fires on nobody's normal
#    day, which is the T-986 test a gate has to pass before it is allowed to gate.
#
# 8. AN iOS SURFACE NOTHING LOCAL COMPILED (T-1956). A macOS build compiles none of `#if os(iOS)`,
#    so a green macOS run said nothing about 146 fenced files until CI's `ios-build` job did, after
#    a push. A green `build`/`test` of `-scheme Cadence` that compiled Swift is now followed by a
#    `generic/platform=iOS Simulator` build into the same DerivedData, gated like the primary one:
#    a warning exits 9, a compile failure exits 11. It never runs when the destination is already
#    iOS, and `CADENCE_SKIP_IOS_LEG=1` skips it with a `!!` banner (CI's `macos-tests` sets it).
#
# It never kills anything. The user's Cadence, the user's Xcode and other agents' builds are all
# off limits; a stall is reported, and the decision to wait or abandon stays with the caller.

set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Captured at top level: inside a function zsh rebinds $0 to the function's own name, so
# `${0:A}` there resolves to `selftest_only_testing` rather than to this file.
SCRIPT_PATH="${0:A}"
XCODEBUILD="${XCODEBUILD:-/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild}"
SHARED_DD="$HOME/Library/Developer/Xcode/DerivedData"
# How long the log may stand still, with the process idle, before we call it a stall and sample.
STALL_SECONDS=${CADENCE_STALL_SECONDS:-180}
STALL_POLL=${CADENCE_STALL_POLL:-30}
say() { print -r -- "$@" }
# $TMPDIR ends in a slash here and may be unset elsewhere; normalise once rather than writing
# /private/tmpcadence-dd-x on a machine without it.
TMP_BASE="${TMPDIR:-/private/tmp/}"; [[ "$TMP_BASE" != */ ]] && TMP_BASE="$TMP_BASE/"

# --- a runner that cannot be rewritten underneath itself (T-2085) -------------
# `zsh` reads a script INCREMENTALLY, by byte offset into one open fd. Rewriting this file in
# place while a run is executing it therefore does not "take effect next time": the running shell
# keeps reading the SAME inode from wherever it had got to, which is now in the middle of a
# different line. Reproduced deliberately on 2026-10-06 -- a 4-line script was truncated and
# rewritten with 40 lines one second into its own `sleep`, and it ran its own four lines and then
# executed THIRTY-SIX lines that were never part of its program.
#
# It happened twice for real on the same day, both from one commit (`1d8786cd`) that appended to
# this file while runs were live. `xcb-widgetdrop-tests` printed
# `./scripts/xcb.sh:3336: command not found: the`, **re-ran its whole test phase**, and emitted two
# `== xcb result ==` blocks with different exit codes (0, then 65) plus a lease self-reclaim; an
# agent reading only the last block would have recorded a red its own tree never caused. The
# commit's own author then hit it a second time: that run printed its complete result block and
# was found 40 minutes later running `test-host-lock.sh acquire` again as a child of itself,
# holding the lock AND queued behind it.
#
# "Edit it only when nothing is running" is a rule about remembering, and this repository's whole
# guard-script family exists because those do not hold. So the runner takes a private copy of
# itself and re-execs from that. The copy is unlinked immediately -- the fd stays valid, which the
# same probe confirmed -- so there is no path anyone could edit and no litter in TMPDIR either.
# `exec` keeps the pid, which is what the log name and the lock ticket are keyed on.
#
# `$0` becomes the snapshot, so the two things derived from it are carried across explicitly;
# everything downstream (`$here` in the selftest, `$ROOT_DIR/scripts/test-host-lock.sh`) must keep
# naming the REAL checkout. The guard variables are unset rather than exported onward, so a child
# invocation protects itself too.
#
# It fails OPEN. A runner that refuses to run because it could not copy itself would be a worse
# instrument than one that can be edited underneath it.
if [[ -n "${CADENCE_XCB_SELF:-}" ]]; then
  SCRIPT_PATH="${CADENCE_XCB_SCRIPT_PATH:-$SCRIPT_PATH}"
  ROOT_DIR="${CADENCE_XCB_ROOT_DIR:-$ROOT_DIR}"
  rm -f -- "$CADENCE_XCB_SELF"
  unset CADENCE_XCB_SELF CADENCE_XCB_SCRIPT_PATH CADENCE_XCB_ROOT_DIR
elif [[ -z "${CADENCE_XCB_NO_REEXEC:-}" ]]; then
  _xcb_snap="${TMP_BASE}cadence-xcb-self.$$.$RANDOM.zsh"
  if cp -- "$SCRIPT_PATH" "$_xcb_snap" 2>/dev/null; then
    CADENCE_XCB_SELF="$_xcb_snap" CADENCE_XCB_SCRIPT_PATH="$SCRIPT_PATH" \
      CADENCE_XCB_ROOT_DIR="$ROOT_DIR" exec zsh "$_xcb_snap" "$@"
  fi
  rm -f -- "$_xcb_snap"
fi

shared_cadence_entries() {
  print -rn -- "$(ls -d "$SHARED_DD"/Cadence-* 2>/dev/null | sort)"
}

# --- the zero-test guard (T-552) ---------------------------------------------
# Evidence that a test RAN, in the shapes this repository's logs use: swift-testing's
# `✔ Test name()` / `✘ Test name()`, its `✔ Test "display name"` / `✘ Test "display name"` form for
# a case declared `@Test("...")`, and XCTest's `Test Case '-[Suite testName]' passed`.
# `[Cc]ase` is deliberate: Xcode 26.6 writes `Test case '…' passed` (lowercase) in a PARALLEL run and
# `Test Case` (capital) serially. Measured 2026-08-31 — a scoped parallel run with 33 real results was
# refused as "executed 0 tests". A zero-test guard that false-negatives is the exact trap it exists to close.
#
# The quoted form is not cosmetic (T-667): a suite scoped alone by `-only-testing:CadenceTests/<X>`
# can run and pass every one of its tests while this pattern, before it matched quotes too, counted
# zero -- measured directly against `ListDetailPageTests` (9/9 passed, 0 counted) and
# `MarkdownTableMobileEditingTests` (27/27 passed, 0 counted) from real logs. That is not a filter
# that selected nothing; it is this guard's own blind spot, and it is silent for any `@Test("...")`
# case in the target (52 of them, in 5 files, at last count), not only those three suites.
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
TEST_RESULT_PATTERN='(✔|✘) Test ([A-Za-z0-9_]+\(\)|"[^"]*")|Test [Cc]ase .*(passed|failed)'

tests_seen() { grep -acE "$TEST_RESULT_PATTERN" "$1" 2>/dev/null | tr -d ' '; }

# --- what this run ASKED FOR, read from its arguments (T-1326) ---------------
# The arguments, never the log. A run's output is derived text that anything may write into: a
# failing test's doc comment, a diagnostic suggesting a rerun command, a test that prints an
# AGENTS.md excerpt. Measured 2026-09-21 on a real `-only-testing:CadenceTests` run -- one flag, no
# per-suite scoping -- which reported two suites as "requested" and never started: both names came
# out of `CadenceTestTargetHygieneTests`' own prose, which swift-testing echoes into the log when
# the test fails, and both carried the trailing backtick of the sentence that quoted them. A real
# flag never carries one. `raw` is covered by construction here, because `raw` is exactly "every
# arg the caller passed" and these read the args they are handed.
only_testing_values() {  # $@ = the run's own arguments; the raw filter values, one per line
  local -a vals; vals=()
  local -i i
  for (( i = 1; i <= $#; i++ )); do
    case "${argv[i]}" in
      -only-testing:*) vals+=("${argv[i]#-only-testing:}") ;;
      -only-testing)   vals+=("${argv[i+1]:-}") ;;
    esac
  done
  (( ${#vals} )) && print -rl -- ${(u)vals}
  return 0
}

# The CadenceTests SUITE names a run scopes to. `CadenceTests/Suite/testName` names one test of a
# suite that still starts, so it resolves to `Suite` -- the same reading `resolve_only_testing`
# makes of the same string, and the reason the old log-grep produced a second phantom shape: it
# kept the `/testName` tail and then looked for a suite by that whole name.
requested_suite_names() {  # $@ = the run's own arguments; one suite name per line
  local -a suites; suites=()
  local v rest
  for v in ${(f)"$(only_testing_values "$@")"}; do
    [[ "$v" == CadenceTests/* ]] || continue
    rest="${v#CadenceTests/}"
    [[ -n "$rest" ]] || continue
    suites+=("${rest%%/*}")
  done
  (( ${#suites} )) && print -rl -- ${(u)suites}
  return 0
}

# --- the runner that never started (T-2021) ----------------------------------
# A UI run can die before ANY test body executes: the UI-test runner times out asking macOS for
# automation mode, xcodebuild exits 65, and the log holds zero test result lines -- which the T-552
# advice below used to answer with "check your -only-testing: suite name". In every measured
# instance the filter was correct (T-1953, T-1957); the cause was this Mac, and the check that
# found it -- `DevToolsSecurity -status` -- took a full day to reach. So a run that exited non-zero
# (or whose exit is unknown, as for `check-test-log` handed a log alone) AND ran nothing AND
# carries xcodebuild's own sentence is an environmental refusal, and is reported as one.
# The sentence is matched exactly; it is xcodebuild's text, not ours, so nothing else writes it.
AUTOMATION_MODE_TIMEOUT='Timed out while enabling automation mode'

# T-2049's second sentence, and it is NOT UI-only: measured 2026-10-03, from 20:43 EDT every test
# run on this Mac died with it -- `escapefix`'s UI run and `calcrash`'s UNIT runs alike, in
# different DerivedData, on different tickets, while the same unit suite had run 5520 tests at
# 20:19. The test host (a UI run's `CadenceUITests-Runner`, a unit run's `Cadence`) launches, asks
# `testmanagerd` for transport, and is never answered. xcodebuild exits 65 having compiled and
# linked everything, so the counters read NON-vacuous and only the test result lines are zero --
# which is why this reads like a wrong suite name and is not one. It is the same shape as the
# automation-mode timeout and belongs in the same refusal.
RUNNER_HUNG_BEFORE_CONNECTION='The test runner hung before establishing connection'

runner_never_started() {  # $1 = log, $2 = xcodebuild's exit status ("" when unknown)
  [[ "${2:-}" != "0" ]] || return 1
  grep -qF -- "$AUTOMATION_MODE_TIMEOUT" "$1" 2>/dev/null && return 0
  grep -qF -- "$RUNNER_HUNG_BEFORE_CONNECTION" "$1" 2>/dev/null
}

automation_mode_refusal() {  # $1 = the log, so the refusal can name WHICH sentence fired
  if [[ -n "${1:-}" ]] && ! grep -qF -- "$AUTOMATION_MODE_TIMEOUT" "$1" 2>/dev/null; then
    runner_hung_refusal
    return 0
  fi
  say ""
  say "!! REFUSING: this test run executed 0 tests because the UI-test RUNNER never initialized."
  say "   This is an ENVIRONMENTAL refusal -- not evidence about the code, and not about the"
  say "   -only-testing: filter (T-2021). The log says: \"$AUTOMATION_MODE_TIMEOUT.\""
  say "   That is the ~70s timeout macOS returns when enabling automation turns into an"
  say "   authentication request. There are TWO causes and they need DIFFERENT fixes (T-2049)."
  say "   (1) Developer mode is disabled (T-1953, T-1957)."
  say "       Check:  DevToolsSecurity -status  -- it must say developer mode is currently enabled."
  say "       Enabling it is an admin change to this Mac and the owner's call."
  say "   (2) Developer mode READS ENABLED and it still times out: automationmode-writer is asking"
  say "       for the device owner's Touch ID / password and nobody answered. Measured 2026-10-03."
  say "       Check:  ./scripts/xcb.sh check-automation   (T-2070)"
  say "       DO NOT hand-type a bare \`log show --predicate 'eventMessage CONTAINS ...'\` here:"
  say "       /usr/bin/log is logged with its own argv, so such a predicate counts PREVIOUS PROBE"
  say "       RUNS as events -- 10 against 1 real on this Mac, measured 2026-10-07 -- and because"
  say "       a probe session runs both sides, it reads HEALTHY over a standing prompt."
  say "       The giveaway is: \"Writer daemon requires authentication to enable automation mode\","
  say "       and /var/db/com.apple.dt.automationmode/automation-enabled is absent afterwards."
  say "       Only the owner can clear this, by answering the prompt while the run is starting;"
  say "       the grant is PER-SESSION, so a previous grant is no reason to disbelieve it."
  say "   Either way it is the owner's to clear; re-run once it is."
}

runner_hung_refusal() {
  say ""
  say "!! REFUSING: this test run executed 0 tests because the TEST HOST never connected."
  say "   This is an ENVIRONMENTAL refusal -- not evidence about the code, and NOT about the"
  say "   -only-testing: filter (T-2049). The log says: \"$RUNNER_HUNG_BEFORE_CONNECTION.\""
  say "   It hits UNIT runs as well as UI runs, so do not read it as a UI-only problem, and the"
  say "   build counters stay non-vacuous, so VACUOUS-COUNT will not catch it."
  say "   It is a state of this MAC, not of your change. Before you debug anything of yours:"
  say "     1. Look for the same sentence in a SIBLING agent's log --"
  say "        grep -l '$RUNNER_HUNG_BEFORE_CONNECTION' /var/folders/*/*/T/cadence-xcb-*.log"
  say "        If another agent's run died the same way, it is the Mac. Say so and stop."
  say "     2. ./scripts/xcb.sh check-automation   -- is an \"Enable UI Automation\" prompt standing?"
  say "        A prompt nobody answered wedges UNIT runs too, and that is T-2070's measured case."
  say "     3. log show --last 20m --predicate 'process == \"testmanagerd\"'"
  say "        \"requested transport for IDE\" with no reply after it is this failure."
  say "   Measured 2026-10-03: it began at 20:43 EDT and took every agent's runs, unit and UI,"
  say "   after a full 5520-test unit run had passed at 20:19. Restarting testmanagerd or"
  say "   rebooting is an admin change to this Mac and the OWNER's call -- report it and stop."
}

# Everything the caller needs to fix an empty run, printed where the empty run happened.
# EMPTY_RUN_EXIT is xcodebuild's own exit status when the caller has it; unset means unknown.
empty_run_diagnostic() {
  local log="$1"; shift
  if runner_never_started "$log" "${EMPTY_RUN_EXIT:-}"; then
    automation_mode_refusal "$log"
    return 0
  fi
  say ""
  say "!! REFUSING: this test run executed 0 tests, and xcodebuild called that a success."
  say "   ** TEST SUCCEEDED ** over an empty filter is indistinguishable from a passing suite,"
  say "   and from a surviving mutation. It is being reported as a failure here instead (T-552)."
  # The run's own arguments when the caller has them (T-1326), and only then the log -- where the
  # filter is read back off xcodebuild's "Command line invocation" line, which quotes its
  # arguments, so the character class stops at a quote as well as at a space. `check-test-log`
  # holds a log and nothing else, which is the one caller that has to take the derived reading.
  local -a requested
  requested=()
  local shown
  if (( $# )); then
    for shown in ${(f)"$(only_testing_values "$@")"}; do
      [[ -n "$shown" ]] && requested+=("-only-testing:$shown")
    done
  else
    requested=(${(f)"$(grep -oE -- '-only-testing:[^ "'"'"']*' "$log" 2>/dev/null | sort -u)"})
  fi
  # Asked first, because it is the one cause that makes the suite-name advice below actively wrong.
  # The preflight guard catches a screen already locked; this catches one that locked mid-run, which
  # is not hypothetical -- a batch queued behind the test-host lock waits out whole minutes.
  if grep -q "The Mac's screen is locked" "$log" 2>/dev/null; then
    say "   every test skipped itself: the screen locked, so no launched app can reach the"
    say "   foreground (T-563). Nothing is wrong with the filter or the code. Unlock and re-run."
  elif (( ${#requested} )); then
    say "   the run was filtered to:"
    for f in $requested; do say "     $f"; done
    say "   \`-only-testing:\` takes a SUITE name, not a file name. Ask the source which suite"
    say "   declares your test:  ./scripts/test-suite-index.sh <testName>"
  else
    say "   the run named no -only-testing: filter, so this is not a mis-scoped suite --"
    say "   the test target built but nothing ran. Read $log from the top."
  fi
}

# --- the diagnostic counters (T-1147) ----------------------------------------
# Two readings, and the repository already knew both were needed: AGENTS.md requires the ANCHORED
# pattern for errors ("count compile errors with `grep -cE '\.swift:[0-9]+:[0-9]+: error:'`, not
# `grep -c 'error:'`"), and for a year the line beside it counted warnings with the loose one the
# same rule bans. That is not a stylistic mismatch, it INVERTS the banner against a zero baseline.
#
# MEASURED 2026-09-12, in this repository, at 17b5b61:
#
#   a `build` action  (669 SwiftCompile tasks)  loose 0, anchored 0
#   `build-for-testing` (345 more)              loose 1, anchored 0
#
# The one loose match is `appintentsmetadataprocessor[...] warning: Metadata extraction skipped.
# No AppIntents.framework dependency found.` -- a tool notice from the AppIntents metadata stage of
# the TEST BUNDLE, which has no AppIntents.framework dependency and never will. So every honest
# `test` run of this repository has been reporting `warnings: 1` against a stated baseline of
# zero, and an incremental run that recompiled nothing reports the reassuring `0`. The banner was
# calibrated exactly backwards: the more real the run, the worse the number looked.
#
# The loose count is kept and reported SEPARATELY rather than deleted. A tool notice is not a
# compiler diagnostic and must not be counted as one, but it is also not nothing -- the way to
# lose the next `ld: warning:` or `actool: warning:` for good is to grep only for `.swift:`.
#
# --- the cost of that anchor, and the second pattern that pays it (T-1516) ----
# The paragraph above is still right and is deliberately NOT widened. Its cost is a whole CATEGORY
# of real compiler warning that carries no `.swift:N:C:` prefix at all: a diagnostic raised inside
# a MACRO EXPANSION is attributed to the expansion buffer, not to a file, and its primary line
# reads `macro expansion #expect:1:39: warning: ...`. It therefore could not match
# `SWIFT_WARNING_PATTERN`, was swept into the loose count, and was printed under a `tool notices:`
# banner whose own words -- "not a compiler diagnostic" -- were false about it. `#expect` is in
# ~5,200 tests here, so the exposed surface was the whole suite, and the failure was silent in the
# direction that reports success: an agent introduced fourteen of them and read `warnings: 0`.
#
# MEASURED 2026-09-29, in this repository, on real `build-for-testing` logs of a probe file:
#
#   `#expect(a == b)` over a main-actor-isolated synthesised `Equatable` conformance
#     (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target + the
#     `InferIsolatedConformances` upcoming feature, both live here) raises `#IsolatedConformances`
#     inside the expansion. One log: 3 macro-expansion warnings, `SWIFT_WARNING_PATTERN` = 0.
#
# TWO SPELLINGS EXIST, not one, and the second is why this pattern does not name the macro:
#
#   macro expansion #expect:1:39: warning: main actor-isolated conformance of ...
#   macro expansion @ObservationTracked:2:24: warning: 'X' is deprecated: ...
#
# A freestanding macro spells itself `#name`; an ATTACHED one spells itself `@name`. A pattern
# written `[A-Za-z#]+` -- which is what T-1516 proposed from the one spelling it had seen -- misses
# every attached-macro diagnostic in the project, and `@Model`, `@Observable` and `@Test` are all
# attached macros this repository expands. `[^ :]+` covers any macro name without ever leaving the
# anchor, because the anchor is the literal `macro expansion ` prefix plus `:LINE:COL: warning:`,
# and neither `ld: warning:` nor `actool: warning:` nor the `appintentsmetadataprocessor` notice
# can reach it. It is also the only form of the character class that means the same thing to grep
# ERE and to ICU, which matters because `CadenceBuildInvocationHygieneTests` LIFTS this string out
# of this file and runs it with `NSRegularExpression` against the same real log lines.
#
# The continuation lines of the same diagnostic (`   |  |    `- warning: ...`) say `warning:` too
# and are deliberately NOT matched: they carry no `name:LINE:COL:`, so the count stays one per
# diagnostic. On the captured log that is 3 matched out of 6 loose `warning:` lines.
#
# --- and whether the number is about anything ---------------------------------
# The second half is the one AGENTS.md has been asking agents to do BY HAND: "a warning count from
# a run that did not recompile the file is vacuous ... check the log for its SwiftCompile line
# before quoting the number". Every brief in this repository repeats that sentence, which is the
# signature of a rule that should be an instrument. An incremental build reuses object files and
# reprints no diagnostic, so `warnings: 0` from a run that compiled nothing is a count over an
# empty set -- indistinguishable, in the banner, from a clean full build.
#
# So the banner states the denominator. `SwiftCompile` is the task line Xcode 26.6 writes for each
# compilation this repository's builds perform (669 of them in that full build, 0 in a no-op one);
# `CompileSwift`/`CompileSwiftSources`/`CompileC` are named alongside it because the older build
# system and any C/ObjC file spell it differently, and a counter that silently stops matching is
# the failure mode this whole file exists to prevent. If the vocabulary ever does change, this
# reports VACUOUS-COUNT on every run rather than quietly certifying zero -- loud and wrong beats
# silent and wrong, and `CadenceBuildInvocationHygieneTests` pins the pattern against real log
# lines so the drift is caught before anybody has to notice the noise.
# --- and the line the two anchors leave over: a CONTINUATION, not a notice (T-1620) ---------
# `notices` below is a SUBTRACTION, and until 2026-10-01 it subtracted only the primary lines. A
# Swift diagnostic is not one line. The snippet renderer prints the primary `file:LINE:COL:
# warning:` line and then repeats the whole message on a caret continuation inside the source
# snippet:
#
#   /repo/CadenceTests/Probe.swift:5:13: warning: 'zzDeprecated()' is deprecated: probe
#   5 |     let p = zzDeprecated() + zzDeprecated()
#     |             `- warning: 'zzDeprecated()' is deprecated: probe
#
# That second line says `warning:` and matches NEITHER anchored pattern -- it carries no
# `name:LINE:COL:` at all, which is exactly why T-1516 was careful not to count it as a warning.
# So it fell through to `loose - warnings` and was reported as a TOOL NOTICE, under a banner whose
# own words are "not a compiler diagnostic". Every real warning therefore manufactured at least one
# phantom notice, which inverts the number the same way T-1147 found the warning count inverted:
# the only line in the banner that is supposed to be diagnostic-free is wrong exactly on the runs
# that have diagnostics, i.e. the runs somebody is reading it to triage.
#
# MEASURED 2026-09-29 on the captured T-1516 probe logs: 6 loose `warning:` lines over 3 real
# macro-expansion diagnostics, reported as `warnings: 3` + `tool notices: 3`, true notices 0.
# MEASURED 2026-10-01 on a fresh `xcrun swiftc -typecheck` of a two-deprecation probe (Xcode 27):
# 4 loose lines over 2 diagnostics, 2 of them continuations, true notices 0.
#
# The marker is `` `- `` immediately before `warning:`, and that adjacency is the whole anchor: a
# real `ld: warning:`, `actool: warning:` or `appintentsmetadataprocessor ... warning:` has no
# caret in front of its `warning:` and is still counted, which is the control section 6 asserts.
# Six real diagnostics across three probe compiles on this toolchain, plus the two captured 2026-09-29
# logs, print this marker and no other; `|- warning:` was looked for in all of them and never seen,
# so it is deliberately NOT matched -- an unwitnessed alternative would be a pattern this repository
# cannot show a line for, and missing one would only restore today's inflation rather than break a count.
#
# Why SUBTRACT rather than widen a warning pattern: a continuation is not a second warning. T-1516
# already pins that the block must count ONCE, and widening to reach the caret line would double
# every diagnostic against a zero baseline. The subtraction below is written as a set difference
# (`grep | grep -v`) rather than as arithmetic for the reason that arithmetic has here: if a line
# ever matched two of the three patterns at once, `loose - a - b` goes NEGATIVE and the banner
# prints nonsense, while a set difference cannot.
SWIFT_ERROR_PATTERN='\.swift:[0-9]+:[0-9]+: error:'
SWIFT_WARNING_PATTERN='\.swift:[0-9]+:[0-9]+: warning:'
MACRO_WARNING_PATTERN='macro expansion [^ :]+:[0-9]+:[0-9]+: warning:'
CONTINUATION_WARNING_PATTERN='`- warning:'
SWIFT_COMPILE_TASK_PATTERN='^[[:space:]]*(SwiftCompile|CompileSwift|CompileSwiftSources|CompileC) '

# --- where the build stops and the tests start (T-1971) ----------------------
# EVERY PATTERN ABOVE USED TO BE GREPPED OVER THE WHOLE LOG, AND A `test` LOG IS TWO DOCUMENTS.
# The second one is test OUTPUT, and a failing test prints whatever its message holds -- which, for
# the tests that read these very guards, is shell source. `xcb.sh` carries, deliberately, in its own
# comments and selftest fixtures, the literal lines
# `/repo/CadenceTests/Probe.swift:5:13: warning: 'zzDeprecated()' is deprecated: probe` and
# `macro expansion #expect:1:39: warning: ...` -- they are there to document and to EXERCISE
# T-1516's two spellings. Measured 2026-10-01: one red `CadenceGuardScriptSelftestTests` expectation
# echoed those lines into the log and this report said **`warnings: 12`,
# `MACRO-EXPANSION-WARNING: 10`, `WARNING-BASELINE`, exit 9** over a tree with **zero** real
# warnings. The same tree with the expectation fixed reported 0. The gate was lying in the exact
# minute somebody was triaging a red run, and the lie pointed at a file they had not touched.
#
# A COMPILER CANNOT EMIT A DIAGNOSTIC AFTER THE BUILD IS OVER, so the counters read the build phase.
# The boundary is the first line announcing test execution, at column 0 in both vocabularies XCTest
# and swift-testing use (`Test Suite 'Selected tests' started at ...` / `◇ Test run started.`).
#
# AND THE FALLBACK IS TODAY'S BEHAVIOUR, WHICH IS THE WHOLE SAFETY ARGUMENT. A log with no such line
# -- a `build` action, a compile failure that never reached the tests, a format that changes under
# us -- is scanned WHOLE, exactly as before. So this change can only ever stop counting lines that
# come after testing began; it can never make a build diagnostic invisible by failing to find a
# marker. That direction matters more than the fix: T-1516 is what a warning gate reading zero over
# fourteen real warnings costs, and a boundary that guessed wrong would rebuild it.
#
# IT ALSO REFUSES TO BE SILENT ABOUT WHAT IT DROPPED. Anything past the boundary that still matches
# is COUNTED SEPARATELY and reported, with the line number to grep from -- so the 12 lines above
# would still be visible to a reader, just not gating. A guard that quietly discards input is the
# next ticket.
TEST_PHASE_START_PATTERN='^(Test Suite .* started at |◇ Test run started|Testing started)'

# Prints the number of lines to scan, or 0 meaning "the whole log".
build_phase_line_count() {  # $1 = log
  local n
  n=$(grep -nE "$TEST_PHASE_START_PATTERN" "$1" 2>/dev/null | head -1 | cut -d: -f1)
  [[ -n "$n" ]] || { print 0; return 0; }
  print $(( n - 1 ))
}

# Streams the portion of the log the counters are entitled to read.
build_phase_of() {  # $1 = log, $2 = line count from build_phase_line_count
  if (( $2 > 0 )); then head -n "$2" -- "$1"; else cat -- "$1"; fi
}

# --- and whether anything ACTS on it (T-1149) --------------------------------
# Everything above is a REPORT, and until 2026-09-12 that is all it was: `$STATUS` was never
# touched by a warning count, so a build that introduced ten Swift warnings exited 0 and read green
# to every caller watching an exit code -- with the number sitting in one banner line out of nine.
# The baseline of zero is asserted in AGENTS.md, in CLAUDE.md, in the release checklist and in
# every agent brief, and locally it was enforced by whether somebody happened to read that line.
#
# WHERE THE GATE WENT, AND WHERE IT DID NOT, decided by looking rather than by taste:
#
#   CI ALREADY GATES, and the ticket was wrong to say nothing did. `.github/scripts/check-log.sh`
#     counts `\.swift:N:C: warning:` and exits 1 above zero, and `ci.yml` runs it `if: always()`
#     on all three jobs. That gate is real, it is anchored, and it is not the gap.
#   THE LOCAL RUNNER IS THE GAP. CI fires on push and pull request; agents here commit to `main`
#     locally and are told not to push, so a warning introduced in a batch is invisible for as
#     long as the repository owner takes to push it, while every agent in between reads a green
#     banner. This script is where the log exists at the moment the decision is made.
#   NOT A GUARD TEST IN CadenceTests. Measured in T-959 and pinned by
#     `CadenceTestHostSandboxCapabilityTests`: that host may write nothing outside its own
#     container and the `/usr/bin/xcodebuild` xcrun shim refuses inside the App Sandbox, so it
#     cannot produce a build log to read. It can only test the COUNTER, which `selftest` and
#     `CadenceGuardScriptSelftestTests` already do.
#   NOT THE COMMIT PATH. `agent-commit.sh` has no build log, and gating commits on a build
#     artefact would refuse every documentation-only commit in the repository.
#
# WHY THIS ONE MAY GATE WHERE T-986 SAYS MOST MAY NOT. The rule there is that a guard which fires
# on the normal case gets switched off -- which is why the declined-hunk backstop above only
# prints. A warning gate does not fire on the normal case, and that is measured, not assumed:
# at 17b5b61, a full `build` (669 SwiftCompile tasks) and a full `build-for-testing` (345 more)
# each produced 0 anchored Swift warnings. The normal case is zero, so the gate is silent until
# somebody breaks the baseline. Two carve-outs keep it that way:
#
#   A VACUOUS RUN NEVER GATES. `warnings: 0` from a run that compiled nothing is a count over an
#     empty set; so is `warnings: 3` inherited from a log the run did not write. The gate only
#     fires on a run that actually compiled Swift, which is why VACUOUS-COUNT had to exist first.
#   CADENCE_ALLOW_WARNINGS=1 DOWNGRADES IT TO THE OLD REPORT. `mutate.sh` sets it, because a
#     mutated tree is by construction not the baseline -- half the mutations this repository
#     makes ("never used", "will never be executed") are warnings by design, and a gate that
#     turned those into RED-WITHOUT-A-FAILING-TEST would corrupt every mutation verdict it
#     touched. It still SAYS it is downgraded; a silent escape hatch is the thing being fixed.
WARNING_GATE_EXIT=9
DIAG_WARNINGS=0
DIAG_COMPILED=0
diagnostic_report() {  # $1 = log. Returns $WARNING_GATE_EXIT when the baseline is broken.
  local log="$1"
  local errors warnings sourced macroed compiled notices
  # T-1971: the build phase, or the whole log when nothing says the tests ever started.
  local -i scan after_phase
  scan=$(build_phase_line_count "$log")
  errors=$(build_phase_of "$log" $scan | grep -cE "$SWIFT_ERROR_PATTERN" 2>/dev/null | tr -d ' ')
  sourced=$(build_phase_of "$log" $scan | grep -cE "$SWIFT_WARNING_PATTERN" 2>/dev/null | tr -d ' ')
  macroed=$(build_phase_of "$log" $scan | grep -cE "$MACRO_WARNING_PATTERN" 2>/dev/null | tr -d ' ')
  # What the old whole-log reading would have added, kept so it can be REPORTED rather than dropped.
  after_phase=0
  if (( scan > 0 )); then
    after_phase=$(tail -n "+$(( scan + 1 ))" -- "$log" \
      | grep -cE "$SWIFT_WARNING_PATTERN|$MACRO_WARNING_PATTERN" 2>/dev/null | tr -d ' ')
  fi
  # T-1516: ONE gating total over TWO anchored patterns. A macro-expansion diagnostic is a compiler
  # warning that happens to have no file to be attributed to; it belongs in this number and not in
  # the tool-notice bucket, which is where the single-pattern reading put it.
  warnings=$(( sourced + macroed ))
  compiled=$(build_phase_of "$log" $scan | grep -cE "$SWIFT_COMPILE_TASK_PATTERN" 2>/dev/null | tr -d ' ')
  # T-1620: a tool notice is a line that says `warning:` and belongs to NO compiler diagnostic --
  # neither as a primary line nor as the caret continuation of the one above it. Set difference,
  # not `loose - warnings`, so a line can never be subtracted twice into a negative count.
  notices=$(build_phase_of "$log" $scan | grep 'warning:' 2>/dev/null \
    | grep -vcE "$SWIFT_WARNING_PATTERN|$MACRO_WARNING_PATTERN|$CONTINUATION_WARNING_PATTERN" \
    | tr -d ' ')
  DIAG_WARNINGS=$warnings
  DIAG_COMPILED=$compiled
  say "  compile errors:  $errors"
  say "  warnings:        $warnings"
  if (( macroed > 0 )); then
    say "  !! MACRO-EXPANSION-WARNING: $macroed of those have NO \`.swift:N:C:\` prefix -- they were"
    say "     raised inside a macro expansion and print as \`macro expansion #expect:1:39: warning:\`"
    say "     or \`macro expansion @Observable:2:24: warning:\` (T-1516). Grepping this log for"
    say "     \`\\.swift.*warning:\` will NOT find them; grep for \`macro expansion\`."
  fi
  if (( notices > 0 )); then
    say "  tool notices:    $notices  (lines saying \`warning:\` that are not a compiler diagnostic;"
    say "                   the baseline of zero is about the line above. grep the log to read them.)"
  fi
  if (( after_phase > 0 )); then
    say "  note (T-1971): $after_phase line(s) AFTER testing started match a compiler-warning pattern and"
    say "     are NOT in the count above. A compiler cannot emit a diagnostic once the build is over;"
    say "     what produces these is a FAILING TEST printing source that contains one -- this script's"
    say "     own comments and fixtures carry such lines on purpose (T-1516). Reported, never gated:"
    say "     read them with \`tail -n +$(( scan + 1 )) <log> | grep -nE 'warning:'\`. If a run is red,"
    say "     fix the test; these lines are its output, not your tree's diagnostics."
  fi
  if (( compiled == 0 )); then
    say "  !! VACUOUS-COUNT: this run compiled 0 Swift files, so \"warnings: $warnings\" is a count"
    say "     over nothing -- an incremental run reuses object files and reprints no diagnostic."
    say "     It is NOT evidence that your change is clean (AGENTS.md). Rebuild the file you edited."
    return 0
  fi
  say "  swift compile tasks: $compiled"
  (( warnings > 0 )) || return 0
  if [[ "${CADENCE_ALLOW_WARNINGS:-}" == "1" ]]; then
    say "  !! WARNING-BASELINE broken ($warnings), and NOT gated: CADENCE_ALLOW_WARNINGS=1 is set."
    say "     Reported, not enforced -- which is what mutate.sh wants and what nothing else should."
    return 0
  fi
  say ""
  say "!! WARNING-BASELINE: $warnings Swift warning(s) over $compiled compile task(s). The baseline"
  say "   is ZERO and any new warning is a regression (AGENTS.md). This run recompiled Swift, so"
  say "   the count is about something -- it is not the VACUOUS-COUNT case."
  build_phase_of "$log" $scan | grep -E "$SWIFT_WARNING_PATTERN|$MACRO_WARNING_PATTERN" 2>/dev/null | head -20 | sed 's/^/     /'
  say "   Fix them, or set CADENCE_ALLOW_WARNINGS=1 if you are deliberately building a tree that"
  say "   is not the baseline (mutate.sh does exactly that)."
  return $WARNING_GATE_EXIT
}


# --- the -only-testing: resolver (T-1076) ------------------------------------
# The zero-test guard above is the SECOND half of this problem, and it only ever sees the loud
# half. Measured 2026-09-06 over 302 files / 386 suites / 4,499 tests in `CadenceTests/`:
#
#   - 14 files declare no suite named after the file (279 tests). Scoping by filename there runs
#     NOTHING, and the zero-test guard covers it completely: exit 4, after the build.
#   - 26 files declare a suite named after the file AND others beside it. Scoping by filename
#     there runs a real suite, exits 0, and silently skips 311 of the 688 tests in those files
#     -- 45%. The zero-test guard covers this NOT AT ALL: the run is green, non-zero and short,
#     and a short green run is indistinguishable from a fast one.
#
# 39 files now declare more than one top-level suite, up from 32 when the question was first
# raised and 33 when T-552 measured it, so the quiet half grows while nothing watches it.
#
# So the names are resolved against the source BEFORE the build, which is also the only placement
# that pays: exit 4 arrives after a full compile, and a `test` action queues behind the test-host
# lock, which has been reaching forty minutes on a busy day. This runs pre-lock and pre-build.
#
# TWO OUTCOMES, DELIBERATELY ASYMMETRIC. An unknown name selects nothing and can only be a
# mistake, so it is REFUSED (exit 8). A known name with siblings is frequently correct -- a file
# holding four suites is a normal way to organise them, and scoping to one of them on purpose is
# an ordinary thing to do -- so it is PRINTED and the run continues. Making the second case fail
# would refuse the normal case daily and be switched off within a week; the message therefore
# names the skipped suites and their exact test counts, which is what makes it checkable at a
# glance rather than noise to be scrolled past.
#
# It reads `test-suite-index.sh --suite-files`, this repository's one parser of Swift test source
# (T-465's brace/raw-string handling included), rather than a second grep-shaped guess about
# where a suite begins. CADENCE_SUITE_FILES is a testing seam: `selftest` points it at a fixture
# so the checks below assert against a known 3-file target instead of a live one that changes
# under them.
# "1 test" / "4 tests". The counts are the part of these messages a reader checks, so they should
# not be the part that reads like a template that was never finished.
n_tests() { (( $1 == 1 )) && print -rn -- "1 test" || print -rn -- "$1 tests"; }

suite_files_source() {
  if [[ -n "${CADENCE_SUITE_FILES:-}" ]]; then
    cat -- "$CADENCE_SUITE_FILES" 2>/dev/null
  else
    "$ROOT_DIR/scripts/test-suite-index.sh" --suite-files 2>/dev/null
  fi
}

# `TypeName<TAB>label` for every suite in the target. CADENCE_SUITE_LABELS is the same testing seam
# CADENCE_SUITE_FILES is, and for the same reason plus one more: `--labels` shells out to
# `python3`, which the App-Sandboxed test host cannot run at all (T-719), so a selftest that needed
# the live index for this would degrade to asserting nothing exactly where it matters.
suite_labels_source() {
  if [[ -n "${CADENCE_SUITE_LABELS:-}" ]]; then
    cat -- "$CADENCE_SUITE_LABELS" 2>/dev/null
  else
    "$ROOT_DIR/scripts/test-suite-index.sh" --labels 2>/dev/null
  fi
}

# --- the per-requested-suite guard (T-667) -----------------------------------
# The zero-test guard answers "did this run execute anything at all", which cannot see one
# REQUESTED suite, among several, that contributed nothing -- the T-667 shape exactly: a 52-suite
# scoped run reported 593 tests and SUCCEEDED while 4 of the 52 executed zero, caught only by a
# human diffing `✔ Suite` lines against the requested flags. This automates that diff.
#
# Its two inputs are asymmetric on purpose (T-1326). WHAT WAS REQUESTED comes from the run's own
# ARGUMENTS, which are a fact about the invocation; WHETHER IT STARTED comes from the log, which is
# the only place that answer exists. The first reading used to come from the log too, and a suite
# name is then manufactured by any line that merely quotes the flag -- which sets `STATUS=6` on an
# otherwise green run and reports a failure nobody caused. See `requested_suite_names`.
#
# A suite's own Swift type name does not appear in swift-testing's event stream once it or its
# cases carry a display name (T-667) -- the log speaks only in display-name vocabulary then -- so
# this asks `test-suite-index.sh --labels`, which reads the source this script cannot, for the
# string the log will actually use rather than grepping for the type name itself.
SUITE_GATE_EXIT=6
suite_started_guard() {  # $1 = log, $2 = test result lines, $3... = the run's own arguments
  local log="$1" ran="$2"; shift 2
  # A wholly empty run is the zero-test guard's finding, and naming it twice buries both.
  (( ran > 0 )) || return 0
  local -a requested
  requested=(${(f)"$(requested_suite_names "$@")"})
  (( ${#requested} )) || return 0
  # One process for every suite in the target, not one per requested suite: `--labels` walks
  # `CadenceTests/` once and prints `TypeName<TAB>label` for each, so a 52-suite request costs one
  # subprocess here instead of 52.
  typeset -A suite_label_map
  local type_name suite_label
  while IFS=$'\t' read -r type_name suite_label; do
    [[ -z "$type_name" ]] && continue
    suite_label_map[$type_name]="$suite_label"
  done < <(suite_labels_source)
  local suite label marker
  local -i verdict=0
  for suite in $requested; do
    [[ -z "$suite" ]] && continue
    label="${suite_label_map[$suite]:-$suite}"
    if [[ "$label" == "$suite" ]]; then
      marker="Suite $suite started"
    else
      marker="Suite \"$label\" started"
    fi
    if ! grep -qF -- "$marker" "$log" 2>/dev/null; then
      say ""
      say "!! T-667: requested suite '$suite' never started (expected \"$marker\" somewhere in"
      say "   the log) even though this run's total test result lines is $ran. It contributed 0"
      say "   -- a typo'd suite name, or one folded into a larger passing run that hid it."
      verdict=$SUITE_GATE_EXIT
    fi
  done
  return $verdict
}

# What the partial-scope half of the resolver found, carried out of the PREFLIGHT so the
# POSTFLIGHT can say it again (T-3080). One `suite<TAB>count<TAB>file` entry per skipped sibling.
# Global because the two readers are ~3,700 lines apart in one script, and empty on every run that
# scopes nothing, scopes a whole file, or scopes a suite that is alone in its file.
typeset -ga PARTIAL_SCOPE_SKIPPED=()

# Exit 8 on an unknown suite, 0 otherwise. Prints the partial-scope notice as a side effect.
resolve_only_testing() {
  local -a filters; filters=("$@")
  (( ${#filters} )) || return 0

  typeset -A suite_file suite_count
  local s f c
  while IFS=$'\t' read -r s f c; do
    [[ -z "$s" ]] && continue
    suite_file[$s]="$f"; suite_count[$s]="$c"
  done < <(suite_files_source)

  # A guard that cannot answer says so and gets out of the way -- the same rule the drift check
  # follows. An empty index means python3 or the test tree is missing, NOT that every name in the
  # request is bogus, and refusing on that would refuse every run on a machine without python3.
  if (( ${#suite_file} == 0 )); then
    say "  -only-testing: not resolved (test-suite-index.sh returned no suites) -- proceeding"
    return 0
  fi

  # Which suites this run actually asks for, so a file scoped in FULL reports nothing below.
  local -a requested_suites whole_suites unknown
  requested_suites=(); whole_suites=(); unknown=()
  local spec target rest suite
  for spec in "${filters[@]}"; do
    target="${spec%%/*}"; rest=""
    [[ "$spec" == */* ]] && rest="${spec#*/}"
    # Only CadenceTests is indexed here. CadenceUITests and any other target are unanswerable,
    # not wrong, so they pass through untouched.
    [[ "$target" != "CadenceTests" ]] && continue
    [[ -z "$rest" ]] && continue          # the whole target: nothing to resolve
    suite="${rest%%/*}"
    requested_suites+=("$suite")
    [[ -z "${suite_file[$suite]:-}" ]] && unknown+=("$suite")
    # `Suite/testName` names ONE test on purpose, so "the rest of the file did not run" is not a
    # finding there, it is the request. Only a suite scoped WHOLE can be a partial scope; the name
    # is still validated above, because a typo in it is a mistake at any granularity.
    [[ "$rest" == */* ]] || whole_suites+=("$suite")
  done
  (( ${#requested_suites} )) || return 0

  if (( ${#unknown} )); then
    say ""
    say "!! REFUSING (UNKNOWN-SUITE): ${#unknown} -only-testing: name(s) match no suite in CadenceTests (T-1076)."
    say "   Nothing was built and no lock was taken. xcodebuild would have accepted this, run"
    say "   zero tests and exited 0 -- which is what a surviving mutation looks like."
    # `sf` and `n` are hoisted HERE, not declared in the loop below: a bare `local x` in a zsh
    # function whose parameter is already local PRINTS `x=<value>` instead of redeclaring it, so
    # the second unknown name would emit `sf=SomeSuiteTests` into the middle of its own refusal
    # (T-1074). `local -a in_file` / `local -a near` below are safe -- any flag suppresses the
    # listing -- which is exactly why the shape hides. Two unknown names is the ordinary case.
    local u stem_file sf n
    for u in "${unknown[@]}"; do
      say ""
      say "   '$u' is not a suite."
      # The single most common way to produce one: a FILE name. 14 files in this target declare
      # no suite named after themselves, so this is the population the zero-test guard catches
      # 20 minutes later -- named here, with the answer attached.
      stem_file=$(print -rl -- "$ROOT_DIR"/CadenceTests/**/"$u".swift(N) | head -1)
      if [[ -n "$stem_file" ]]; then
        say "     It is a FILE (${stem_file:t}), and \`-only-testing:\` takes a SUITE name."
        say "     That file declares:"
        local -a in_file; in_file=()
        for sf in ${(k)suite_file}; do
          [[ "${suite_file[$sf]}" == "${stem_file:t}" ]] && in_file+=("$sf")
        done
        for sf in ${(o)in_file}; do
          say "       -only-testing:CadenceTests/$sf   ($(n_tests ${suite_count[$sf]}))"
        done
      else
        local -a near
        near=(${(f)"$(print -rl -- ${(k)suite_file} | grep -i -- "$u" | head -5)"})
        if (( ${#near} )) && [[ -n "${near[1]}" ]]; then
          say "     Did you mean:"
          for n in "${near[@]}"; do say "       -only-testing:CadenceTests/$n   ($(n_tests ${suite_count[$n]}))"; done
        else
          say "     Ask the source which suite declares your test:"
          say "       ./scripts/test-suite-index.sh $u"
        fi
      fi
    done
    return 8
  fi

  # --- the quiet half: a real suite that leaves siblings behind ---------------
  # Reported per FILE, not per suite, so scoping to three of a file's four suites prints one
  # notice about the fourth rather than three overlapping ones.
  typeset -A is_requested
  local r
  for r in "${requested_suites[@]}"; do is_requested[$r]=1; done
  local -a reported; reported=()
  local file sib total
  for r in "${whole_suites[@]}"; do
    file="${suite_file[$r]}"
    [[ " ${reported[*]} " == *" $file "* ]] && continue
    local -a skipped; skipped=()
    total=0
    for sib in ${(k)suite_file}; do
      [[ "${suite_file[$sib]}" != "$file" ]] && continue
      [[ -n "${is_requested[$sib]:-}" ]] && continue
      skipped+=("$sib")
      (( total += suite_count[$sib] ))
      # The same finding, in a form the postflight can print without re-reading the index
      # (T-3080). Recorded here rather than recomputed there for the reason `suite_started_guard`
      # splits its two inputs: this one is a fact about the INVOCATION, settled before the build,
      # and a second reading taken forty minutes later could disagree with the run it describes
      # because a sibling agent edited the test tree in between.
      PARTIAL_SCOPE_SKIPPED+=("$sib"$'\t'"${suite_count[$sib]}"$'\t'"$file")
    done
    (( ${#skipped} )) || continue
    reported+=("$file")
    say ""
    say "!! PARTIAL-SCOPE (T-1076): $file declares suites this run will NOT execute."
    say "   $(n_tests $total) in that file $( (( total == 1 )) && print -n "is" || print -n "are") being skipped, in ${#skipped} suite(s):"
    for sib in ${(o)skipped}; do
      say "     -only-testing:CadenceTests/$sib   ($(n_tests ${suite_count[$sib]}))"
    done
    say "   This is NOT a failure and the run continues -- a file holding several suites is"
    say "   normal. It matters if you scoped by FILENAME meaning the file: then the run goes"
    say "   green over a fraction of it, and the zero-test guard cannot see that (it only fires"
    say "   at zero). Add the lines above if you meant the whole file."
    say "   Said again in this run's RESULT block, because that is where a green run is read (T-3080)."
  done
  return 0
}


# --- the PARTIAL-SCOPE restatement (T-3080) ----------------------------------
# THE NOTICE ABOVE IS NOT MISSING AND IT IS NOT WRONG. It is in the wrong half of the run.
#
# `resolve_only_testing` deliberately runs in the PREFLIGHT -- ahead of the drift check, ahead of a
# test-host queue that has been reaching forty minutes, ahead of a build -- because a name that
# selects nothing should not cost all three to discover. The cost of that placement is that the
# notice is printed once, minutes and thousands of lines before `== xcb result`, and the result
# block says nothing about it. The result block is the part of a run that is actually read: it is
# what an agent scrolls to, what a brief quotes, and what gets piped to `tail`.
#
# MEASURED, 2026-10-08 23:25. `xcb.sh listsdoor test -only-testing:CadenceTests/CadenceSidebarLayoutTests`
# ended `✔ Test run with 22 tests in 1 suite passed`, XCODEBUILD_EXIT=0 -- over a file whose OTHER
# suite, `SidebarStaticDestinationBridgeTests`, held the THIRTEEN tests that had just been written
# for the change being validated. The preflight had said so. Nothing after it did, and the agent
# recorded a green run that executed none of its new tests. That is the T-552 shape one notch
# quieter: not a run that executed nothing, but a run that executed everything except the point.
#
# WHY THAT IS THE DANGEROUS KIND. Every agent here is told to mutation-prove its work, and the
# whole protocol is "break it, watch the scoped run go red, restore". A scope that silently omits
# the suite the mutation lives in returns green for the mutated tree, which reads as a SURVIVING
# mutation -- or, worse, the mutation is in the product and the surviving tests pass anyway, so the
# kill is recorded against tests that never ran.
#
# IT REPORTS AND IT DOES NOT GATE, which is the same decision T-1076 made for the preflight half
# and T-1741 made for `INTERACTIVE-SKIPPED`, re-taken rather than inherited. 39 files in this
# target declare more than one top-level suite, and scoping to one of them on purpose is the
# ordinary, correct, daily invocation; a gate on it would fail the ordinary case, and a guard that
# fails the ordinary case is one agents learn to route around -- which costs the notice too. What
# was missing here was never severity. It was placement, and placement is free.
#
# Its own tag, `PARTIAL-SCOPE-UNRUN`, so it can be pinned separately: `PARTIAL-SCOPE` alone is
# satisfied by the preflight half, so a later edit that deleted this call would leave every
# existing pin green.
partial_scope_postflight() {   # $1 = test result lines, for the sentence that names them
  (( ${#PARTIAL_SCOPE_SKIPPED} )) || return 0
  local ran="${1:-}"
  local entry sib count file
  local -i total=0
  for entry in "${PARTIAL_SCOPE_SKIPPED[@]}"; do
    count="${${entry#*$'\t'}%%$'\t'*}"
    (( total += count ))
  done
  say ""
  say "!! PARTIAL-SCOPE-UNRUN (T-3080): this run left $(n_tests $total) unexecuted, in ${#PARTIAL_SCOPE_SKIPPED} suite(s)"
  say "   of a file it DID run -- so none of them are in the count above:"
  for entry in "${PARTIAL_SCOPE_SKIPPED[@]}"; do
    sib="${entry%%$'\t'*}"; count="${${entry#*$'\t'}%%$'\t'*}"; file="${entry##*$'\t'}"
    say "     -only-testing:CadenceTests/$sib   ($(n_tests $count))   [$file]"
  done
  say "   Said in the preflight too, and said again HERE because this block is what a green run"
  say "   is read from. It is NOT a failure: a file holding several suites is normal and scoping"
  say "   to one of them is an ordinary request."
  say "   It IS a failure of evidence if you scoped by FILENAME meaning the whole file -- \"test"
  say "   result lines: $ran\" then describes a fraction of it, and a mutation living in the suites"
  say "   above survived this run while looking killed. Add the lines above and re-run."
  return 0
}


# --- the interactive UI-test skip report (T-1741) ----------------------------
# EVERY GUARD IN THIS FILE SO FAR ANSWERS "DID THE RUN EXECUTE ANYTHING". This one answers the
# question one notch quieter: did the run execute everything it BUILT.
#
# `CadenceUITests` gates every pointer-taking test behind `CadenceUITestEnvironment
# .requireInteractiveUITests()`, which is right -- those tests take over the pointer and keyboard
# of whatever Mac they run on, and one of them right-clicks a sidebar. The channel is a marker file
# inside the runner's own container, because the environment variable provably cannot reach the
# sandboxed macOS UI-test process (T-1724). The consequence was not right: a default
# `-only-testing:CadenceUITests` run SKIPS four geometry guards -- the only two suites in this
# repository that can see where a popover actually lands -- prints `** TEST SUCCEEDED **`, and
# reads exactly like a run that checked them.
#
# THE DECISION (T-1741), and what it is NOT. It is not "run them in CI": `.github/workflows/ci.yml`
# does not run this target at all and says why -- macOS UI testing needs a one-time system
# authorisation granted with the user's password at a GUI prompt (T-531), and a hosted runner has
# nobody to grant it, so the stage would fail at launch on EVERY run rather than intermittently.
# It is not "run them in a nightly" either: there is no unattended Mac here, and a nightly on the
# owner's own machine would seize their pointer at 3am. And it is not "ungate them": a test that
# right-clicks while somebody is typing is a defect in the harness, not coverage.
#
# So the gate stays and THE SILENCE GOES. That is the whole of what was wrong: a skipped test that
# reports success is the same failure shape as T-1516's warning counter reading zero over fourteen
# real warnings, and as T-535's release gate that never compiled iOS. The count below is printed on
# every test run that skipped anything, it names the tests, and it names the one command that turns
# them on -- so "I did not run the geometry guards" becomes something the reader of a green run is
# told rather than something they have to know to ask.
#
# IT REPORTS AND IT DOES NOT GATE, for the reason PARTIAL-SCOPE does not: the ordinary, correct,
# daily invocation is the one that skips these, and a guard that fails the ordinary case is a guard
# that gets switched off. `$STATUS` is never touched here.
#
# AND IT COUNTS ITS OWN LINES. It does NOT add a number beside `.github/scripts/check-log.sh`'s
# executed-test counter, which [[T-1851]] measured as wrong twice over -- blind to the 133
# `@Test("a sentence")` cases, so it reports 5,242 where swift-testing says 5,374, and double
# counting a failing test, so 5 failures print as "tests failed: 10". A skip count placed next to
# a total that is already 133 short would read as a reconciliation and be neither. The two are
# also separate questions: `check-log.sh` is the CI gate, and CI does not run this target at all.
# T-1851 is left to be taken on its own rather than half-fixed from here.
INTERACTIVE_SKIP_MARKER="$HOME/Library/Containers/com.haoranwei.Cadence.CadenceUITests.xctrunner/Data/tmp/cadence-run-interactive-ui-tests"

# The skip's own message, which `CadenceUITestEnvironment.requireInteractiveUITests` writes and
# XCTest copies into the log verbatim. Keyed on the message rather than on the suite names so a
# suite added to the target is covered the day it is written, and so a skip for the OTHER reason
# this target skips -- a locked screen -- is counted separately rather than folded in.
INTERACTIVE_SKIP_PATTERN='Interactive UI tests are opt-in'
# XCTest's per-test skip line. `[Cc]ase` for the same reason TEST_RESULT_PATTERN has it: Xcode
# writes `Test case` lowercase in a parallel run and `Test Case` serially.
SKIPPED_CASE_PATTERN="Test [Cc]ase '[^']*' skipped"

interactive_skip_report() {
  local log="$1"
  [[ -r "$log" ]] || return 0
  local -i skipped interactive
  skipped=$(grep -cE "$SKIPPED_CASE_PATTERN" "$log" 2>/dev/null | tr -d ' ')
  interactive=$(grep -cF "$INTERACTIVE_SKIP_PATTERN" "$log" 2>/dev/null | tr -d ' ')
  (( skipped > 0 || interactive > 0 )) || return 0

  # The names, from the skip lines, so the report is checkable rather than a number.
  local -a names
  names=(${(f)"$(grep -oE "$SKIPPED_CASE_PATTERN" "$log" 2>/dev/null \
    | sed -E "s/^Test [Cc]ase '-?\[?([^]']*)\]?' skipped\$/\1/" | sort -u)"})

  say ""
  if (( interactive > 0 )); then
    say "!! INTERACTIVE-SKIPPED (T-1741): $skipped test(s) in this run SKIPPED themselves, and the"
    say "   interactive opt-in is why. They were built and they did not execute; the run's exit"
    say "   code says nothing about the surfaces they read."
  else
    say "!! INTERACTIVE-SKIPPED (T-1741): $skipped test(s) in this run SKIPPED themselves, for a"
    say "   reason other than the interactive opt-in. Read the skip message in $log."
  fi
  local n
  for n in "${names[@]}"; do [[ -n "$n" ]] && say "     $n"; done
  if (( interactive > 0 )); then
    say "   Turn them on for a run, then turn them off again -- they take over the pointer:"
    say "     touch '$INTERACTIVE_SKIP_MARKER'"
    say "     rm    '$INTERACTIVE_SKIP_MARKER'"
    say "   (CADENCE_RUN_INTERACTIVE_UI_TESTS=1 is honoured too and CANNOT be delivered to the"
    say "    macOS UI-test runner -- it is sandboxed into its own container; T-1724.)"
  fi
  return 0
}


# --- the MID-RUN locked-screen report (T-1890) -------------------------------
# The preflight guard below refuses a run whose screen is ALREADY locked. This names the case it
# structurally cannot see: a screen that locks *while* the run is in flight.
#
# Why that gap is not hypothetical, and what it costs. `requireAnUnlockedScreen()` runs in
# `setUpWithError`, so it reads the lock state at each test's START; the preflight reads it once,
# before the build. A lock arriving after setUp and during a test body is invisible to both. What
# the run then produces is not a skip and not an activation failure -- it is a launched app that
# reaches `.runningForeground` and publishes an EMPTY accessibility tree, so every element query
# times out and every failure is attributed to whatever line asked. T-1890 is four runs across
# three suites of exactly that, read for a day as a product regression, and the lock was only
# inferred three hours later from an unrelated refused run.
#
# The existing post-run reading is a grep for the skip message, and it fires only inside the
# zero-test guard -- i.e. only when EVERY test skipped, which requires the lock at setUp time.
# That is precisely the case this one does not cover.
#
# TWO SIGNALS, because a lock that is released before the run ends leaves no state behind:
#   1. `CGSSessionScreenIsLocked=Yes` now -- the screen is still locked at postflight.
#   2. `CGSSessionScreenLockedTime` >= the run's start -- the screen locked DURING the run, even
#      if it has since been unlocked. This is the one that catches a lock-and-unlock.
#
# WHAT IS MEASURED AND WHAT IS NOT. Signal 1 and the silence on an old lock time are measured
# (selftest, and live on 2026-10-01 against a Mac locked since 01:33:44 EDT). Signal 2's behaviour
# on an UNLOCKED Mac is NOT: whether `CGSSessionScreenLockedTime` survives an unlock carrying the
# last lock's time, or disappears with the lock, could not be measured without unlocking the host.
# The code is written so that either answer is safe -- an absent key makes no claim and falls back
# to signal 1, so the unmeasured semantics can only cost a detection, never invent one. A
# false NEGATIVE here leaves today's behaviour exactly as it is; a false positive would be the
# damaging direction and is unreachable.
#
# It REPORTS and never gates. The run's reds are already red; what was missing was anybody saying
# the reds are not about the code. Changing the exit code would hide a genuine failure behind an
# environmental one, which is the inversion this repository keeps catching.

# The session dictionary, with a testing seam. `CADENCE_SESSION_FIXTURE` points at a file holding
# an `ioreg -n Root -d1 -k IOConsoleUsers` capture, so the selftest can drive the mid-run case --
# which cannot be induced on a live host without locking the screen out from under the run.
session_dictionary() {
  if [[ -n "${CADENCE_SESSION_FIXTURE:-}" ]]; then
    cat "${CADENCE_SESSION_FIXTURE}" 2>/dev/null
    return 0
  fi
  ioreg -n Root -d1 -k IOConsoleUsers 2>/dev/null
}

# The epoch second at which the screen last locked, or empty when the key is absent.
# No pipe into `grep -q` anywhere in this family -- see `screen_is_locked` for why that shape
# answers "not locked" precisely when it DID find the key.
screen_lock_time() {
  local session; session="$(session_dictionary)"
  [[ "$session" == *'"CGSSessionScreenLockedTime"'* ]] || return 0
  print -r -- "$session" | sed -nE 's/.*"CGSSessionScreenLockedTime"[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' | head -1
}

# WHICH RUNS IT IS ABOUT (T-2041). Everything below explains UI-test reds, and a unit-only run has
# none of those to explain: `CadenceTests` hosts in the app but reads no accessibility tree, and the
# preflight deliberately lets such a run through a locked screen. Measured 2026-10-03 (heartbeat,
# `b3b28b3b`): a GREEN `-only-testing:CadenceTests` run -- exit 0, 0 failed cases -- ended on the
# full banner, "THESE REDS ARE NOT EVIDENCE ABOUT THE CODE" over no reds at all, and "the preflight
# refuses this outright" about a run the preflight correctly admitted. So the banner is kept for a
# selection that can reach `CadenceUITests` and a unit-only selection gets one informational line.
# Fails toward the banner: no `-only-testing:` at all is the whole scheme, which includes the UI
# target, unless that target is `-skip-testing:`'d wholesale.
selection_reaches_ui_tests() {  # $@ = the run's own arguments. 0 = can reach CadenceUITests.
  local -a vals; vals=(${(f)"$(only_testing_values "$@")"})
  local v
  local -i i
  if (( ${#vals} == 0 )); then
    for (( i = 1; i <= $#; i++ )); do
      case "${argv[i]}" in
        -skip-testing:CadenceUITests) return 1 ;;
        -skip-testing) [[ "${argv[i+1]:-}" == CadenceUITests ]] && return 1 ;;
      esac
    done
    return 0
  fi
  for v in $vals; do
    [[ "${v%%/*}" == CadenceUITests ]] && return 0
  done
  return 1
}

screen_lock_report() {  # $1 = run start (epoch s), $2... = the run's own arguments (T-2041)
  local -i run_start=${1:-0}
  shift
  local session; session="$(session_dictionary)"
  local -i locked_now=0
  [[ "$session" == *'"CGSSessionScreenIsLocked"=Yes'* ]] && locked_now=1
  local lock_time; lock_time="$(screen_lock_time)"
  local -i locked_during=0
  if [[ -n "$lock_time" ]] && (( run_start > 0 )) && (( lock_time >= run_start )); then
    locked_during=1
  fi
  (( locked_now || locked_during )) || return 0

  if ! selection_reaches_ui_tests "$@"; then
    say "  note: SCREEN-LOCKED (unit-only, informational; T-2041): the screen was locked around this run" \
        "(locked at $( [[ -n "$lock_time" ]] && { date -r "$lock_time" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || print -rn -- "$lock_time"; } || print -rn -- unknown)," \
        "still locked: $( (( locked_now )) && print -n yes || print -n no)); this selection runs no CadenceUITests and a unit test needs no foreground, so it says nothing about the result."
    return 0
  fi

  say ""
  say "!! SCREEN-LOCKED-MID-RUN (T-1890): the Mac's screen was locked around this run."
  # The STATE alone is not a diagnosis. "Locked underneath a live run" and "already locked before
  # the run started" are different failures with different fixes, and the timestamp is the only
  # thing that tells them apart -- so it is printed in BOTH branches, not just the mid-run one.
  # 2026-10-01 is the case that forced this: a Mac locked 7h37m before the run was ever launched,
  # which the state-only report would have described as a mid-run lock.
  if (( locked_during )); then
    say "   DIAGNOSIS: locked UNDERNEATH a live run -- the lock timestamp is inside the window."
    say "   The run started on an unlocked screen and lost it part-way through, so an early test"
    say "   may have read a real surface and a later one an empty tree. Trust neither."
  elif [[ -n "$lock_time" ]]; then
    say "   DIAGNOSIS: ALREADY LOCKED before this run started -- the lock PREDATES the window."
    say "   Nothing in this run ever had a foreground. On a live run the preflight refuses this"
    say "   outright, so reaching it here means the reading was taken by hand or out of band."
  else
    say "   DIAGNOSIS: locked now, and the session published no timestamp to date the lock by."
  fi
  if [[ -n "$lock_time" ]]; then
    say "   locked at:  $(date -r "$lock_time" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || print -r -- "$lock_time") (epoch $lock_time)"
  else
    say "   locked at:  unknown (no CGSSessionScreenLockedTime in the session dictionary)"
  fi
  say "   run began:  $(date -r "$run_start" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || print -r -- "$run_start") (epoch $run_start)"
  say "   still locked at postflight: $( (( locked_now )) && print -n yes || print -n no)"
  say "   A UI test cannot read a surface while loginwindow owns the foreground. The app reaches"
  say "   .runningForeground and then publishes NO accessibility tree, so every element query"
  say "   times out and the failure lands on whichever line asked. THESE REDS ARE NOT EVIDENCE"
  say "   ABOUT THE CODE. Unlock the screen, arm \`caffeinate -d -i\`, and re-run before reading"
  say "   anything into them. Note that caffeinate does NOT unlock an already-locked screen and"
  say "   does not prevent a manual lock -- measured 2026-10-01, a live -d -i assertion alongside"
  say "   CGSSessionScreenIsLocked=Yes."
  return 0
}

# --- the test host macOS refused to (re)launch (T-1992) ----------------------
# A full CadenceTests run can lose its host mid-suite and then be refused the relaunch:
# measured 2026-10-02 (heartbeat, `a037faa3`), 2,197 tests passed, the host vanished inside one
# test with no DiagnosticReports entry, and xcodebuild's relaunch came back `Could not launch
# "CadenceTests"` -- LaunchServices -10699, RunningBoard's `Launch prevented due to "prevent
# launch" assertion`. xcodebuild exited 65 with the test that happened to be running as the only
# "failure". That suite then passed alone and a full rerun on the same HEAD passed, so the red was
# not about the code -- but the only note the result block printed was SCREEN-LOCKED-MID-RUN,
# whose explanation (an empty accessibility tree) is about UI tests and does not describe this.
#
# The phrases are xcodebuild's own, matched exactly, so a test's prose is unlikely to write them.
# Cause unproven (a locked screen, or the owner's Xcode stopping a same-bundle-id process), so
# the report names the evidence and asks for a re-run; it does NOT mark the named test flaky, and
# like every report here it never gates -- the run's exit status is left exactly as it was.
HOST_LAUNCH_REFUSAL_PATTERN='LaunchServices has returned error -10699|OSStatus error -10699|Launch prevented due to "prevent launch" assertion'
# A test's START line: swift-testing's `◇ Test x() started.` (not `◇ Test run started.`) or
# XCTest's `Test Case '-[S t]' started.`
TEST_START_PATTERN='◇ Test .+ started\.|Test Case .+ started\.'

# --- but not inside a failing test's own output (T-3071) ---------------------
# "A test's prose is unlikely to write them" was wrong for exactly the tests that read this file.
# Measured 2026-10-08 (heartbeat, 54a6c843): one red `CadenceBuildInvocationHygieneTests`
# expectation printed `xcb.sh`'s source into the log -- the line defining the pattern above, and
# 8b's fixture -- and this report said THIS RED IS NOT EVIDENCE ABOUT THE CODE over a real
# assertion failure. Same disease as T-1971 (a test log is two documents, and a failing test
# prints whatever its message holds); a different boundary, because a refusal DOES happen after
# testing started, so "the build phase only" would blind it. What is excluded is the ISSUE DUMP:
# from swift-testing's column-0 `✘ Test … recorded an issue` / `✘ Test … failed` line through
# every line after it that is blank, indented, or `↳`-prefixed -- swift-testing prints a
# message's continuation lines indented, so the dump never reaches column 0. The first other
# column-0 line ends it, and xcodebuild's own launch failure (`IDELaunchReport …`, `Recovery
# Suggestion: …`, `Failure Reason: …`) is printed at column 0, so a genuine refusal right after a
# red test still closes the dump and is still read. The direction this can fail is a MISSED
# report, never a false one; and it only ever removes lines, so a log with no `✘` reads as before.
first_host_launch_refusal_line() {  # $1 = log. Prints the line number, or nothing.
  HLR_PATTERN=$HOST_LAUNCH_REFUSAL_PATTERN LC_ALL=C awk '
    /^✘ / { dump = 1; next }
    dump && ($0 == "" || /^[[:space:]]/ || /^↳/) { next }
    { dump = 0 }
    $0 ~ ENVIRON["HLR_PATTERN"] { print NR; exit }
  ' "$1" 2>/dev/null
}

host_launch_refusal_report() {  # $1 = log, $2 = xcodebuild's exit status ("" when unknown)
  local log=$1 xstatus=${2:-}
  [[ "$xstatus" == "0" ]] && return 0   # a green run has no red to explain
  local first; first=$(first_host_launch_refusal_line "$log")
  [[ -n "$first" ]] || return 0
  local last_test
  last_test=$(head -n $(( first - 1 )) "$log" | grep -aE -- "$TEST_START_PATTERN" \
    | grep -avF '◇ Test run started' | tail -1 \
    | sed -E 's/^.*◇ Test (.+) started\..*$/\1/; s/^.*Test Case (.+) started\..*$/\1/')
  say ""
  say "!! HOST-LAUNCH-REFUSED (T-1992): macOS refused to (re)launch the test host part-way through."
  say "   The log carries xcodebuild's own launch failure (LaunchServices -10699 / RunningBoard"
  say "   \"prevent launch\" assertion) at line $first. The host vanished and its relaunch was refused,"
  say "   so the run stopped there -- what reads as a failure is wherever it happened to be standing."
  if [[ -n "$last_test" ]]; then
    say "   last test started before the refusal: $last_test"
  else
    say "   last test started before the refusal: none found in the log"
  fi
  say "   THIS RED IS NOT EVIDENCE ABOUT THE CODE, and NOT about that test -- do not mark it flaky."
  say "   Re-run before treating the run as red. Suspects, unproven: a locked screen (see any"
  say "   SCREEN-LOCKED-MID-RUN note below; its UI-test explanation does not apply here) or an open"
  say "   Xcode stopping a process with the same bundle id."
  return 0
}

# --- a DerivedData poisoned by a touched entitlements file (T-2046) ----------
# Measured 2026-10-03 (agent `rowcrush`): one metadata-only write to `Cadence/Cadence.entitlements`
# -- content and mtime unchanged, ctime moved -- poisons a warm private DerivedData for good. Every
# later build in it dies at `builtin-productPackagingUtility` with xcodebuild's `Entitlements file
# "Cadence.entitlements" was modified during the build`, having compiled 0 Swift files, so all the
# result block said was VACUOUS-COUNT and T-552's "executed 0 tests" -- which reads exactly like a
# wrong suite name. Four runs went into that dead end. Deleting the generated `.xcent` did not
# clear it; `release-dd` plus a fresh build did. The error text offers a build-setting override:
# this report deliberately does not, because that ships a product whose signature may not match
# its entitlements. Never gates -- the run's exit status is left exactly as it was.
ENTITLEMENTS_MODIFIED_PATTERN='Entitlements file .* was modified during the build'
# THE BATCH-RULE HALF, which T-2046 left open: IS A DERIVEDDATA DISPOSABLE THE MOMENT THIS FIRES?
# YES, and it is settled here as a rule the script enforces rather than as advice a reader has to
# remember at the fourth identical red. The argument is the measurement in the paragraph above:
# the poisoning is PERMANENT for that tree (four consecutive runs, identical death at
# `builtin-productPackagingUtility`, 0 Swift files compiled), deleting the generated `.xcent` does
# NOT clear it, and `release-dd` plus a fresh build does -- so after this fires, every later build
# in that directory is a guaranteed twelve-minute dead end. There is also nothing in it worth
# keeping: it compiled nothing and ran nothing, so no evidence is lost by deleting it, and the
# only thing it can still produce is another agent reading T-552's "executed 0 tests" as a
# misspelt suite name. A DerivedData that has tripped this is RUBBISH, and the rule is that the
# next run refuses to build into it rather than paying to rediscover that.
#
# How the rule is carried: a sentinel file inside the DerivedData itself. Not a variable (the next
# run is a different process), not a note in a log (nobody re-reads the log of a run that produced
# nothing), and not an entry in TMPDIR beside the logs (it would outlive the directory it is about
# and refuse a FRESH DerivedData that happened to reuse the name). Inside the tree, it has exactly
# the lifetime of the thing it describes: `release-dd` deletes the directory and the sentinel with
# it, so clearing the refusal and clearing the poisoning are THE SAME ACT and cannot drift apart.
ENTITLEMENTS_POISON_SENTINEL='.cadence-entitlements-poisoned'
ENTITLEMENTS_POISONED_EXIT=14
entitlements_poisoned_dd_report() {  # $1 = log, $2 = xcodebuild's exit status ("" when unknown), $3 = the DerivedData path
  local log=$1 xstatus=${2:-} dd=${3:-<derived-data-path>}
  [[ "$xstatus" == "0" ]] && return 0   # a green run has no red to explain
  grep -aqE -- "$ENTITLEMENTS_MODIFIED_PATTERN" "$log" 2>/dev/null || return 0
  say ""
  say "!! ENTITLEMENTS-POISONED-DD (T-2046): this private DerivedData is poisoned by a metadata-only touch of Cadence.entitlements (\"was modified during the build\"), not by your code or your suite name -- run \`./scripts/xcb.sh release-dd $dd\` then a fresh build."
  if [[ -d "$dd" ]]; then
    print -r -- "poisoned $(date '+%Y-%m-%d %H:%M:%S') by ${log}" > "$dd/$ENTITLEMENTS_POISON_SENTINEL" 2>/dev/null
    say "   MARKED DISPOSABLE (T-2046): \`$ENTITLEMENTS_POISON_SENTINEL\` written into that tree, and the next"
    say "   run of this script refuses to build into it. It compiled nothing and ran nothing, so"
    say "   there is no evidence in it to lose -- delete it, do not nurse it."
  fi
  return 0
}
# The refusal the sentinel buys. Returns 0 (and prints) when the DerivedData has been marked.
entitlements_poisoned_dd_refusal() {  # $1 = the DerivedData path
  local dd=${1:-}
  [[ -n "$dd" && -f "$dd/$ENTITLEMENTS_POISON_SENTINEL" ]] || return 1
  say ""
  say "!! REFUSING -- ENTITLEMENTS-POISONED-DD (T-2046): this DerivedData was marked disposable by an"
  say "   earlier run of this script: $(cat -- "$dd/$ENTITLEMENTS_POISON_SENTINEL" 2>/dev/null)"
  say "   One metadata-only touch of Cadence.entitlements poisons a warm DerivedData PERMANENTLY:"
  say "   every later build in it dies at builtin-productPackagingUtility having compiled 0 Swift"
  say "   files, and what reaches you is T-552's \"executed 0 tests\" -- which reads character for"
  say "   character like a misspelt suite name. Four runs went into that dead end once already."
  say "   Deleting the generated Cadence.app.xcent does NOT clear it. This does:"
  say "       ./scripts/xcb.sh release-dd $dd"
  say "   then re-run. Nothing is lost: the tree compiled nothing and ran nothing."
  say "   Do NOT reach for CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION -- the error text offers it,"
  say "   and it ships a product whose signature may not match its entitlements."
  return 0
}

# --- an outstanding "Enable UI Automation" prompt (T-2070) -------------------
# A `CadenceUITests` run can raise an interactive authentication prompt ("Enable UI Automation")
# that no agent can answer, and while it stands NO macOS test run works -- the unit suite included.
# T-2067 is the measured incident: one unanswered prompt held testmanagerd inside a single
# synchronous `LAContext.evaluatePolicy` for 3h11m and killed seven runs behind it on a fixed 445s
# timer, while three agents chased daemons, DerivedData and Xcode because nothing said a prompt
# was open. This reads the host and refuses, the same shape as the locked-screen guard.
#
# THE PREDICATE IS THE WHOLE FIX, and the probe T-2070 shipped as "TESTED" was defective.
# MEASURED on this Mac 2026-10-07: the entry's predicate, which filters on
# `eventMessage CONTAINS "Writer daemon requires authentication"`, matches the `log` BINARY'S OWN
# INVOCATION RECORDS -- /usr/bin/log is itself logged with its argv, and its argv contains the
# phrase being counted. Over the same 24h window the unscoped read counts **10** requests and the
# scoped read counts **1** (the real one, testmanagerd at 16:47:08, granted at 17:13:45). Worse
# than noisy: the entry runs the SAME shape for the `done` counter, so every probe run lifts both
# sides together and `req - done` is dragged toward zero BY THE ACT OF PROBING -- the probe reads
# HEALTHY over a genuinely unanswered prompt, which is the one reading it exists to prevent.
# So the predicate names the two processes that actually emit these lines, says `process != "log"`
# out loud as well (belt and braces, and so a reader cannot quietly drop the scoping), and ONE
# read answers both counters over exactly one window instead of two reads over two.
# `automation_prompt_counts` also drops any line carrying `--predicate`: a line quoting a probe
# invocation is never a testmanagerd event, and that is the second line of defence that selftest
# can actually exercise through the fixture.
#
# The grant is PER-SESSION, not permanent (measured 2026-10-07, and root AGENTS.md was corrected):
# `/var/db/com.apple.dt.automationmode/automation-enabled` is absent while that directory's mtime
# matches the minute an ATTENDED UI run last ended, and a cold UI run raises the owner's Touch ID
# prompt every time. So "it was granted once" is never a reason to disbelieve this probe.
#
# Do NOT "fix" an outstanding prompt by `DevToolsSecurity -enable`, by killing testmanagerd or
# coreautha, or by writing to the authorization database -- T-1742 and T-2049 are what that cost.
# Only the owner, at the keyboard, can answer it.
AUTOMATION_PROMPT_EXIT=13
AUTOMATION_PROMPT_REQUEST='Writer daemon requires authentication'
AUTOMATION_PROMPT_GRANTED='Finished enabling Automation Mode'
AUTOMATION_PROMPT_PREDICATE='(process == "testmanagerd" OR process == "automationmode-writer") AND process != "log"'
# The testing seam, the shape `pmset_log` and `xctest_session_log` already use: the live condition
# needs this Mac's own authentication stack to stop answering, so `selftest` substitutes a file in
# the format `log show --style compact` prints.
automation_mode_log() {
  if [[ -n "${CADENCE_AUTOMATION_LOG_FIXTURE:-}" ]]; then
    cat -- "$CADENCE_AUTOMATION_LOG_FIXTURE" 2>/dev/null
    return 0
  fi
  /usr/bin/log show --last "${CADENCE_AUTOMATION_LOG_WINDOW:-6h}" \
    --predicate "$AUTOMATION_PROMPT_PREDICATE" --style compact 2>/dev/null
}
automation_prompt_counts() {   # prints "<requests> <granted>"
  local text
  text="$(automation_mode_log | grep -v -- '--predicate')"
  local -i req granted
  req=$(print -r -- "$text" | grep -cF -- "$AUTOMATION_PROMPT_REQUEST")
  granted=$(print -r -- "$text" | grep -cF -- "$AUTOMATION_PROMPT_GRANTED")
  print -r -- "$req $granted"
}
# >0 means a prompt is STANDING and no macOS test run can work. Zero or negative is healthy.
automation_prompt_outstanding() {
  local -a c
  c=( ${=$(automation_prompt_counts)} )
  print -r -- "$(( ${c[1]:-0} - ${c[2]:-0} ))"
}
# AN UNMATCHED REQUEST IS NOT BY ITSELF A STANDING PROMPT, and reading it as one would have made
# this guard worse than the disease it is for. MEASURED behaviour, corrected 2026-10-07: a cold UI
# run raises the owner's prompt EVERY time (the grant is per-session), and an UNATTENDED one burns
# ~70s and gives up -- leaving exactly the same unmatched "Writer daemon requires authentication"
# in the log, with no "Finished enabling Automation Mode" after it, over a host that then runs unit
# suites perfectly well. A count-only refusal would therefore have refused EVERY macOS test run on
# this Mac for the rest of the window after any unattended UI run -- siblings' unit runs included,
# which is the exact harm T-2067 did and this guard exists to prevent.
#
# So the refusal needs a second, INDEPENDENT reading of the same host: is a test session actually
# hanging where T-2067 hangs? That is T-2071's `runstate_transport_outstanding` -- sessions that
# connected minus sessions that got serialized transport -- which is also the pairing T-2070 (b)
# names. Two readings, two subsystems, one conclusion:
#
#   request unmatched AND a session hanging -> REFUSE. A prompt is standing and nothing can run.
#   request unmatched, no session hanging   -> WARN, do not gate. Most likely an unattended UI run
#                                              that timed out; the run is allowed to prove it.
#   no unmatched request                    -> silent.
#
# The second read is only paid when the first is positive, so an ordinary run still pays 2.3s.
automation_prompt_verdict() {   # prints STANDING | UNMATCHED | HEALTHY
  local -i outstanding hanging
  outstanding=$(automation_prompt_outstanding)
  (( outstanding > 0 )) || { print -r -- HEALTHY; return 0 }
  hanging=$(runstate_transport_outstanding)
  (( hanging > 0 )) && { print -r -- STANDING; return 0 }
  print -r -- UNMATCHED
}
# The note for the UNMATCHED reading. It never gates, for the reason INTERACTIVE-SKIPPED does not:
# it is a thing to know, not a thing to stop for, and a guard that stopped for it would be ignored.
automation_prompt_note() {
  local -a c; c=( ${=$(automation_prompt_counts)} )
  say ""
  say "   note: AUTOMATION-PROMPT-UNMATCHED (T-2070): this Mac logged an \"Enable UI Automation\""
  say "   request with no grant after it (requests=${c[1]}, granted=${c[2]}), but NO test session is"
  say "   hanging, so nothing is being refused. The usual cause is an UNATTENDED UI run that raised"
  say "   the owner's prompt and timed out after ~70s -- the grant is PER-SESSION, so a cold UI run"
  say "   raises it every time. If your run then dies at ~445s with 0 tests, it is this after all:"
  say "   ./scripts/xcb.sh check-automation, and only the owner can answer the prompt."
}
# Prints the refusal and returns 0 when a prompt is STANDING (both readings agree); returns 1
# otherwise, so the caller reads it exactly as it reads `dd_in_use_refusal`.
automation_prompt_refusal() {
  [[ "$(automation_prompt_verdict)" == STANDING ]] || return 1
  local -i outstanding; outstanding=$(automation_prompt_outstanding)
  local -a c; c=( ${=$(automation_prompt_counts)} )
  say ""
  say "!! REFUSING -- AUTOMATION-PROMPT-OUTSTANDING (T-2070): this Mac has an unanswered \"Enable UI"
  say "   Automation\" authentication prompt (requests=${c[1]}, granted=${c[2]}, outstanding=$outstanding)."
  say "   A test session is hanging as well (connected, never given serialized transport), which is"
  say "   the SECOND reading and the reason this refuses rather than merely noting it."
  say "   While it stands NO macOS test run works, the UNIT suite included: testmanagerd sits in one"
  say "   synchronous LAContext.evaluatePolicy and every run behind it dies on a fixed 445s timer."
  say "   T-2067 measured 3h11m of host and seven dead runs from exactly one of these."
  say "   ONLY THE OWNER CAN CLEAR IT, at the keyboard: answer the Touch ID / password prompt (it may"
  say "   be behind other windows, or already dismissed -- then re-run an ATTENDED UI run to raise it"
  say "   again). The grant is PER-SESSION, so this can recur on the next cold UI run."
  say "   Do NOT run \`sudo DevToolsSecurity -enable\`, kill testmanagerd/coreautha, or touch the"
  say "   authorization database -- T-1742 and T-2049 are what that cost."
  say "   CADENCE_ALLOW_AUTOMATION_PROMPT=1 exists to TEST this guard, not to get a run past it."
  return 0
}

# --- a run the Mac slept through (T-2048) ------------------------------------
# Measured 2026-10-03 (heartbeat, 3a5a43af): a full CadenceTests run on battery with the screen
# locked stopped advancing at 653 of 5518 tests, `pmset -g log` shows `Entering Sleep state due to
# 'Maintenance Sleep'` at 20:01, and the caller's 60-minute cap killed it. All the result block said
# was `XCODEBUILD_EXIT=143`. This counts the `Entering Sleep state` entries whose local timestamps
# fall inside [start, end] and names the COUNT -- never a duration, which the log does not state
# reliably. Never gates; a green run has nothing to explain and is not read.
# `CADENCE_PMSET_LOG_FIXTURE` is the testing seam: a file in `pmset -g log` format, so `selftest`
# drives the reading without the Mac ever sleeping. The live read costs ~24 s (166k lines on this
# Mac, measured 2026-10-04), which is why the result block asks `pmset -g stats` first.
pmset_log() {
  if [[ -n "${CADENCE_PMSET_LOG_FIXTURE:-}" ]]; then
    cat -- "$CADENCE_PMSET_LOG_FIXTURE" 2>/dev/null
    return 0
  fi
  pmset -g log 2>/dev/null
}
# Sleep + dark-wake + user-wake counters: a cheap "did any sleep/wake happen" reading. Any sleep that
# ended before postflight is followed by a wake of one kind or the other, so an unchanged sum means
# the 24-second log read can be skipped. Empty when unreadable, and empty never skips the read.
pmset_sleep_wake_sum() {
  pmset -g stats 2>/dev/null | awk -F: '/Count/ { s += $2; n++ } END { if (n) print s }'
}
system_sleep_report() {  # $1 = run start (epoch s), $2 = run end (epoch s), $3 = xcodebuild's exit ("" when unknown)
  local -i start=${1:-0} end=${2:-0}
  local xstatus=${3:-}
  [[ "$xstatus" == "0" ]] && return 0   # a green run has no red to explain
  (( start > 0 && end >= start )) || return 0
  local from to
  from=$(date -r "$start" '+%Y-%m-%d %H:%M:%S') || return 0
  to=$(date -r "$end" '+%Y-%m-%d %H:%M:%S') || return 0
  # `pmset -g log` stamps local wall time as `YYYY-MM-DD HH:MM:SS -0400`; the first 19 characters
  # compare lexically in the same local time the bounds were formatted in.
  local -i slept
  slept=$(pmset_log | awk -v from="$from" -v to="$to" '
    /Entering Sleep state/ { t = substr($0, 1, 19); if (t >= from && t <= to) n++ }
    END { print n + 0 }')
  (( slept > 0 )) || return 0
  say ""
  say "!! SYSTEM-SLEPT (T-2048): \`pmset -g log\` shows $slept 'Entering Sleep state' entr$( (( slept == 1 )) && print -n y || print -n ies) between this run's start ($from) and end ($to) -- a stall, a kill (exit 143) or a timeout here is not evidence about the code. Re-run awake, on AC, lid open."
  return 0
}


# --- the iOS Simulator destination guard (T-1282) ----------------------------
# The zero-test guard above refuses a run that executed nothing. This refuses a run that COMPILED
# nothing, which is the same failure one step earlier and wears an even better disguise.
#
# Measured 2026-09-18, on this Mac, at 93f9c4e:
#
#   xcb.sh <id> raw -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 15' build
#     -> XCODEBUILD_EXIT=70, `compile errors: 0`, `warnings: 0`, and the surrounding shell
#        pipeline exits 0.
#
# Xcode 27 ships no iPhone 15, so xcodebuild matched no destination and compiled ZERO Swift files.
# Everything an agent reads to decide a gate passed said the gate passed; the only dissent was the
# VACUOUS-COUNT banner and an absent `swift compile tasks:` line, both of which say "this count is
# about nothing" rather than "this run built nothing".
#
# It is worse than an ordinary red because of WHAT it covers up: the macOS test target never
# compiles `Cadence/iOS/`, so an agent that accepts the fake pass has not merely skipped a gate --
# it has never compiled the code it changed, and the macOS suite stays green over the top of it.
# It happened once for real on 2026-09-18 (T-1278's first iOS attempt).
#
# WHY HERE AND NOT IN A DOC. `Cadence/iOS/AGENTS.md` now records a working name, and a written-down
# name rots the next time Apple drops a device: `iPhone 15` was a correct instruction until an Xcode
# update made it the sentence above. The list of devices this Mac actually has is a question with a
# live answer, so the guard asks it rather than pinning a name -- and names the available ones in
# the refusal, the way UNKNOWN-SUITE names the suites the run could have meant.
#
# CADENCE_SIMCTL_DEVICES is a testing seam, the same one CADENCE_SUITE_FILES is for the resolver
# above: `selftest` points it at a fixture in `simctl list devices available` format, so the checks
# assert against a known device list rather than against whichever simulators this Mac has today.
SIMULATOR_GATE_EXIT=10

simctl_devices_source() {
  if [[ -n "${CADENCE_SIMCTL_DEVICES:-}" ]]; then
    cat -- "$CADENCE_SIMCTL_DEVICES" 2>/dev/null
  else
    xcrun simctl list devices available 2>/dev/null
  fi
}

# `<runtime>\t<device name>\t<udid>` per available device. The runtime is carried because an
# `iOS Simulator` destination must be answered out of the iOS runtimes and not out of watchOS's --
# `Apple Watch Series 11 (46mm)` exists on this Mac and is not an answer to `platform=iOS Simulator`.
# The two trailing parenthesised fields are stripped by anchoring at end of line, so a device whose
# NAME holds parentheses (`iPad Pro 13-inch (M5)`, `iPad (A16)`) keeps them.
available_simulators() {
  simctl_devices_source | awk '
    /^-- .* --$/ { rt = substr($0, 4, length($0) - 6); next }
    rt != "" && match($0, / \([0-9A-Fa-f-]+\) \([A-Za-z ]+\) *$/) {
      dname = substr($0, 1, RSTART - 1)
      sub(/^[ \t]+/, "", dname)
      udid = substr($0, RSTART, RLENGTH)
      sub(/^ \(/, "", udid)
      sub(/\).*$/, "", udid)
      if (dname != "") printf "%s\t%s\t%s\n", rt, dname, udid
    }'
}

# Exit $SIMULATOR_GATE_EXIT when a destination names a simulator that does not exist here.
# Prints the resolved device on the normal path: a guard whose only output is a refusal leaves a
# caller unable to tell "checked and fine" from "never looked".
resolve_destinations() {
  local -a dests; dests=("$@")
  (( ${#dests} )) || return 0

  # Which of them are even this guard's question. `generic/platform=iOS Simulator` names no device
  # ON PURPOSE (it is how you build without one), and a macOS destination has nothing to resolve.
  local -a asked; asked=()
  local d
  for d in "${dests[@]}"; do
    [[ "${d:l}" == generic/* ]] && continue
    [[ "${d:l}" == *"platform=ios simulator"* ]] && asked+=("$d")
  done
  (( ${#asked} )) || return 0

  local -a devices; devices=(${(f)"$(available_simulators)"})
  # A guard that cannot answer says so and gets out of the way -- the rule the resolver above and
  # the drift check both follow. An empty list means `simctl` is missing or refused (it is, inside
  # the App Sandbox), NOT that every device in the request is imaginary.
  if (( ${#devices} == 0 )) || [[ -z "${devices[1]}" ]]; then
    say "  -destination: not resolved (simctl listed no devices) -- proceeding"
    return 0
  fi

  local spec kv key val name id os rt dname dudid line
  local -a missing_names missing_ids os_missing
  missing_names=(); missing_ids=(); os_missing=()
  for spec in "${asked[@]}"; do
    name=""; id=""; os=""
    for kv in ${(s:,:)spec}; do
      key="${${kv%%=*}:l}"; val="${kv#*=}"
      case "$key" in
        name) name="$val" ;;
        id)   id="$val" ;;
        os)   os="$val" ;;
      esac
    done

    if [[ -n "$id" ]]; then
      # `id=` is the other way to name one device, and a UDID that no longer exists fails in
      # exactly the same silent shape as a name that never did.
      local found_id=0
      for line in "${devices[@]}"; do
        [[ "${${line##*$'\t'}:l}" == "${id:l}" ]] || continue
        found_id=1
        say "  iOS Simulator destination: ${${line#*$'\t'}%%$'\t'*} (${line%%$'\t'*}, by id)"
        break
      done
      (( found_id )) || missing_ids+=("$id")
      continue
    fi

    # `platform=iOS Simulator` alone, or with only an OS, leaves xcodebuild to choose. There is no
    # name to be wrong about, so there is nothing here to refuse.
    [[ -z "$name" ]] && continue

    local -a runtimes_with_name; runtimes_with_name=()
    for line in "${devices[@]}"; do
      rt="${line%%$'\t'*}"; dname="${${line#*$'\t'}%%$'\t'*}"
      [[ "${rt:l}" == "ios "* ]] || continue
      [[ "$dname" == "$name" ]] && runtimes_with_name+=("$rt")
    done

    if (( ${#runtimes_with_name} == 0 )); then
      missing_names+=("$name")
      continue
    fi
    # `OS=latest` is xcodebuild's own "whichever" and is never wrong here.
    if [[ -n "$os" && "${os:l}" != "latest" ]]; then
      if [[ " ${runtimes_with_name[*]} " != *" iOS $os "* ]]; then
        os_missing+=("$name|$os|${(j:, :)runtimes_with_name}")
        continue
      fi
    fi
    say "  iOS Simulator destination: $name (${runtimes_with_name[1]})"
  done

  (( ${#missing_names} + ${#missing_ids} + ${#os_missing} )) || return 0

  say ""
  say "!! REFUSING (NO-SUCH-SIMULATOR): a -destination names a simulator this Mac does not have (T-1282)."
  say "   Nothing was built and no lock was taken. xcodebuild would have matched no destination,"
  say "   compiled ZERO Swift files and exited 70 with \`compile errors: 0\` and \`warnings: 0\` --"
  say "   which reads exactly like a passing iOS gate. The macOS test target never compiles"
  say "   Cadence/iOS/, so nothing downstream would have caught it either."
  local m
  for m in "${missing_names[@]}"; do
    say ""
    say "   '$m' is not an available iOS Simulator device."
  done
  for m in "${missing_ids[@]}"; do
    say ""
    say "   id=$m matches no available simulator."
  done
  for m in "${os_missing[@]}"; do
    say ""
    say "   '${m%%|*}' exists, but not on iOS ${${m#*|}%%|*} -- it is on ${m##*|}."
  done
  say ""
  say "   Available iOS Simulator devices on this Mac:"
  for line in "${devices[@]}"; do
    rt="${line%%$'\t'*}"; dname="${${line#*$'\t'}%%$'\t'*}"
    [[ "${rt:l}" == "ios "* ]] || continue
    say "     -destination 'platform=iOS Simulator,name=$dname'   ($rt)"
  done
  say ""
  say "   Read them yourself with: xcrun simctl list devices available"
  return $SIMULATOR_GATE_EXIT
}

# --- the iOS leg (T-1956) ----------------------------------------------------
# A macOS build compiles none of `#if os(iOS)` (T-1781), and 146 files carry that fence (T-1921),
# so a green macOS `build`/`test` says nothing about the iOS surface -- and CI's `ios-build` job is
# the first thing that does, after a push, on a batch nobody can attribute it to. T-1921 measured
# the price of asking here instead: 88 s / 1392 swift compile tasks cold, 5 s / 0 tasks repeated,
# because DerivedData is keyed on the AGENT ID, so the iOS leg is cold once per agent session.
#
# So after a GREEN primary `build` or `test` that ACTUALLY COMPILED SWIFT, the same `-scheme Cadence`
# is built for `generic/platform=iOS Simulator` into the same DerivedData, and that log goes through
# `diagnostic_report` -- one iOS warning breaks the zero-warning baseline exactly as a macOS one does.
# It compiles only; no iOS test runs, so T-535's hole is narrowed to its warning half, not closed.
#
# FOUR THINGS IT MUST GET RIGHT, each a measured failure somewhere in this repository:
#   1. IT NEVER RECURSES. A run whose destination (or `-sdk`) is already iOS IS the iOS build --
#      CI's `ios-build` job is exactly that -- and building it a second time buys nothing.
#   2. THE ESCAPE HATCH ANNOUNCES ITSELF. `CADENCE_SKIP_IOS_LEG=1` skips it with a `!!` banner on
#      every run, the `CADENCE_ALLOW_WARNINGS` way, because a quiet carve-out is T-1921's latency
#      back with nothing saying so. CI's `macos-tests` sets it: `ios-build` compiles iOS beside it.
#   3. EVERY SKIP SAYS WHY. It fires on every run, which is T-986's shape, so a skip is one printed
#      line naming its reason and `selftest` induces the run AND each skip.
#   4. A VACUOUS iOS BUILD CERTIFIES NOTHING. `diagnostic_report` already says VACUOUS-COUNT at 0
#      tasks (T-1147); this goes one step further and reads the APP target, because a leg that
#      compiled a handful of `CadenceWidgets` files and no file of target `Cadence` is a tiny count
#      over nothing the iOS surface is made of. It is reported as IOS-LEG-VACUOUS and never gated,
#      exactly as the macOS vacuous count is not.
#
# It is NOT taken for `raw` (`mutate.sh`'s route, whose trees are non-baseline by construction), for a
# scheme other than `Cadence` (`CadenceMCPServer` has no iOS surface), or after a red primary run.
IOS_LEG_EXIT=11
IOS_LEG_DESTINATION='generic/platform=iOS Simulator'
# The app target's own compile tasks, in the line shape Xcode 26.6/27 writes:
# `SwiftCompile normal arm64 /…/File.swift (in target 'Cadence' from project 'Cadence')`.
IOS_LEG_APP_TASK_PATTERN="(in target 'Cadence' from project"

# Sets IOS_LEG_SKIP (a token, empty when the leg must run) and IOS_LEG_WHY (one plain sentence).
# $1 = action, $2 = the primary run's status after its gates, $3 = its compile-task count,
# $4... = the run's own arguments.
IOS_LEG_SKIP=""; IOS_LEG_WHY=""
ios_leg_decide() {
  local action=$1 primary_status=$2 compiled=$3; shift 3
  local -a a; a=("$@")
  local i v scheme=""
  IOS_LEG_SKIP=""; IOS_LEG_WHY=""
  if [[ "$action" != build && "$action" != test ]]; then
    IOS_LEG_SKIP=NOT-BUILD-OR-TEST; IOS_LEG_WHY="the action is '$action', not build or test"; return 0
  fi
  for (( i = 1; i <= ${#a}; i++ )); do
    v=""
    case "${a[i]}" in
      -scheme)        scheme="${a[i+1]:-}" ;;
      -destination)   v="${a[i+1]:-}" ;;
      -destination=*) v="${a[i]#-destination=}" ;;
      -sdk)           [[ "${${a[i+1]:-}:l}" == iphone* ]] && v="-sdk ${a[i+1]}" ;;
    esac
    if [[ "${v:l}" == *platform=ios* || "$v" == "-sdk "* ]]; then
      IOS_LEG_SKIP=ALREADY-IOS
      IOS_LEG_WHY="this run's destination is already iOS ('$v') -- it IS the iOS build, so a second one would only repeat it"
      return 0
    fi
  done
  if [[ "$scheme" != "Cadence" ]]; then
    IOS_LEG_SKIP=NO-IOS-SCHEME
    IOS_LEG_WHY="the scheme is '${scheme:-<none>}', not 'Cadence' -- only the app scheme has an iOS surface"
    return 0
  fi
  if [[ "${CADENCE_SKIP_IOS_LEG:-}" == "1" ]]; then
    IOS_LEG_SKIP=CARVED-OUT; IOS_LEG_WHY="CADENCE_SKIP_IOS_LEG=1 is set"; return 0
  fi
  if (( primary_status != 0 )); then
    IOS_LEG_SKIP=PRIMARY-RED; IOS_LEG_WHY="the primary run is red (exit $primary_status) -- fix that first"; return 0
  fi
  if (( compiled == 0 )); then
    IOS_LEG_SKIP=PRIMARY-VACUOUS
    IOS_LEG_WHY="the primary run compiled 0 Swift files, so there is no change here for an iOS build to check"
    return 0
  fi
  return 0
}

# The primary run's arguments, cut down to what an iOS `build` of the same tree needs: the scheme,
# configuration, xcconfig, DerivedData and build settings. A whitelist, deliberately -- the test-only
# flags (`-only-testing:`, `-testPlan`, `-resultBundlePath`, ...) are many and a `build` refuses or
# ignores them, and `-quiet` would strip the SwiftCompile lines the vacuity reading needs.
# $@ = the run's own arguments. Prints one argument per line.
ios_leg_args() {
  local -a a; a=("$@")
  local i
  for (( i = 1; i <= ${#a}; i++ )); do
    case "${a[i]}" in
      -scheme|-configuration|-xcconfig|-derivedDataPath)
        print -r -- "${a[i]}"; print -r -- "${a[i+1]:-}"; (( i++ )) ;;
      # A flag's VALUE is never a build setting, however it is spelt: `-destination platform=macOS`
      # reads as `platform=macOS`, and the first selftest run of this caught exactly that leaking
      # into the iOS argv. So the value-taking flags consume their value, and a setting must be
      # UPPER_SNAKE, which every setting xcodebuild takes is.
      -destination|-sdk|-arch|-resultBundlePath|-testPlan|-only-testing|-skip-testing|-xctestrun|-test-iterations)
        (( i++ )) ;;
      # `=~`, not a `[[ == ]]` glob: `#` needs EXTENDED_GLOB, and without it that matches literally (T-1074).
      *=*)
        [[ "${a[i]}" =~ '^[A-Z_][A-Z0-9_]*=' ]] && print -r -- "${a[i]}" ;;
    esac
  done
  print -r -- -destination; print -r -- "$IOS_LEG_DESTINATION"; print -r -- build
}

# --- does this selection launch an app? (T-1933) -----------------------------
# ONE QUESTION, TWO DECISIONS. The locked-screen guard (T-563) and the test-host lock (T-236) were
# each written against a different proxy for the same fact, and both proxies are the target name:
# the guard refused `[[ "${args[*]}" == *CadenceUITests* ]]` -- the string ANYWHERE in the argument
# list -- and the lock is taken for the `test` ACTION whatever the action selects. Measured
# 2026-10-01: `-only-testing:CadenceUITests/CadenceOverdrawVerdictTests` was refused with exit 5 on
# a locked Mac, and on an unlocked one the same selection queued 800 seconds behind two siblings
# for a lease it does not need. That suite launches nothing, takes no pointer and reads no screen;
# it is arithmetic over bitmaps it draws itself. Both decisions have the same input, so they now
# share one answer and one set of selftest checks.
#
# WHAT MAKES A SUITE SCREEN-FREE IS READ FROM ITS SOURCE, not from a list kept here. A list is a
# second copy of a fact, and T-1382 is thirteen days of what two copies of one rule do: a suite
# that gains an `XCUIApplication` would keep its exemption until somebody remembered this file.
# The source IS the fact -- a test that never names `XCUIApplication` cannot launch an app -- and
# `CadenceUITestLaunchFreedomTests` holds the other half, that the suite the exemption is for still
# has no way to reach one.
#
# IT FAILS CLOSED, EVERY WAY IT CAN FAIL. No `-only-testing:` at all selects the whole scheme, which
# includes this target: launches. A filter naming any target but `CadenceUITests` reaches the unit
# target, which hosts IN the app and is the T-236 container hazard: launches. A suite whose
# declaration cannot be found, or that is declared in more than one file, is unanswerable: launches.
# Only a selection where EVERY named suite was read and every one of them is screen-free is exempt.
# This is deliberately not symmetric with the refusals above it, which refuse on a positive finding:
# here the exemption is the finding, so the exemption is what has to be proven.
#
# CADENCE_UI_TEST_SOURCE_DIR is the testing seam `CADENCE_SUITE_FILES` is, and for the same reason:
# `selftest` points it at a two-file fixture so the checks assert against a known screen-free suite
# AND a known app-launching one, rather than against a live directory that changes under them. One
# fixture could not tell a working guard from a deleted one.
ui_suite_launches_an_app() {    # $1 = suite name. 0 = launches, or cannot be answered.
  local suite="$1"
  local dir="${CADENCE_UI_TEST_SOURCE_DIR:-$ROOT_DIR/CadenceUITests}"
  local -a decl
  decl=(${(f)"$(grep -lE "^[[:space:]]*(final[[:space:]]+)?(class|struct)[[:space:]]+${suite}[[:space:]]*:" -- "$dir"/*.swift(N) 2>/dev/null)"})
  (( ${#decl} == 1 )) || return 0
  [[ -n "${decl[1]}" ]] || return 0
  grep -qF 'XCUIApplication' -- "${decl[1]}" && return 0
  return 1
}

selection_launches_an_app() {   # $@ = the -only-testing: values, flag already stripped.
  (( $# )) || return 0
  local spec target rest suite
  for spec in "$@"; do
    target="${spec%%/*}"; rest=""
    [[ "$spec" == */* ]] && rest="${spec#*/}"
    [[ "$target" != "CadenceUITests" ]] && return 0
    [[ -z "$rest" ]] && return 0
    suite="${rest%%/*}"
    ui_suite_launches_an_app "$suite" && return 0
  done
  return 1
}

# --- one DerivedData, one live build; and the last full green (T-2042) -------
# Measured 2026-10-03: heartbeat runs started 04:16, 04:36, 04:56 and 05:16 under ONE id, so all four
# built into ONE `cadence-dd-heartbeat`. The 04:56 run's closing "delete <dd> when you are done" was
# followed, and removed the directory 56 s into the 05:16 run -- whose result was then no evidence
# about the code. The hint was printed when nothing else used the path; the delete came later, so a
# check at print time alone cannot carry it. Three pieces, all reading the same process list:
#   * a run REFUSES (exit 12, DD-IN-USE) when a live xcodebuild already names its -derivedDataPath --
#     in preflight, again just before launch (a run can queue 40 minutes for the test host), and
#     before the iOS leg (the lease is given back before it, so a same-id sibling can start then);
#   * `release-dd` is the delete the hint now points at, and it refuses while one does;
#   * a green full unscoped `-only-testing:CadenceTests` macOS run records HEAD plus a fingerprint
#     of the working tree, and `last-green` says whether the tree is still exactly that, so a
#     heartbeat can skip a 16-minute re-run of an unchanged tree.
# CADENCE_PS_FIXTURE (a `ps -o pid= -o args=` capture) and CADENCE_XCB_STATE_DIR /
# CADENCE_TREE_ROOT are the testing seams, the way CADENCE_SESSION_FIXTURE is for the lock.
DD_IN_USE_EXIT=12

# The pids of live xcodebuild processes whose -derivedDataPath is $1, one per line. Returns 2 when
# the process list could not be read at all: this process is always in it, so empty is a failure,
# and the callers treat it as "cannot prove free", never as "free".
dd_live_users() {
  local want="${${1:A}%/}" listing line
  local -a w
  local -i i
  if [[ -n "${CADENCE_PS_FIXTURE:-}" ]]; then
    listing="$(cat -- "$CADENCE_PS_FIXTURE" 2>/dev/null)"
  else
    listing="$(ps -axww -o pid= -o args= 2>/dev/null)"
  fi
  [[ -n "$listing" ]] || return 2
  for line in ${(f)listing}; do
    w=(${=line})
    (( ${#w} >= 4 )) || continue
    # The binary itself, or a script interpreter running something named xcodebuild (a stub).
    [[ "${w[2]:t}" == xcodebuild || "${w[3]:t}" == xcodebuild ]] || continue
    for (( i = 3; i < ${#w}; i++ )); do
      if [[ "${w[i]}" == -derivedDataPath && "${${w[i+1]:A}%/}" == "$want" ]]; then
        print -r -- "${w[1]}"
        break
      fi
    done
  done
  return 0
}

# Prints the refusal and returns 0 when $1 is in use; returns 1 when it is provably free.
# $2 = where in the run this is asked. An unreadable process list is NOT a refusal here: refusing
# every run on a host whose `ps` is denied would be the T-986 shape. It is said, and the run goes on.
dd_in_use_refusal() {
  local dd=$1 stage=$2 users
  local -i prc
  users="$(dd_live_users "$dd")"; prc=$?
  if (( prc != 0 )); then
    say "  derivedData in use: not answered (could not read the process list) -- proceeding"
    return 1
  fi
  [[ -n "$users" ]] || return 1
  say ""
  say "!! REFUSING: DD-IN-USE (T-2042, $stage): live xcodebuild pid(s) ${(j:, :)${(f)users}} already build"
  say "   into $dd. Two builds in one DerivedData corrupt each other ('build.db is locked', a"
  say "   Build/Products deleted underneath a running host), and a red from either is then no"
  say "   evidence about the code. Wait for that pid, or give this run its own id (e.g. '<id>-\$\$')."
  return 0
}

# "<HEAD> <clean|hash of the tracked diff and the untracked files>" for the git checkout rooted at
# $1, or return 1 when $1 is not the top of one (an archive tree has no .git, and a directory
# inside some OTHER checkout must not borrow that one's HEAD).
tree_fingerprint() {
  local root=$1 top head files dirt
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "$top" && "${top:A}" == "${root:A}" ]] || return 1
  head="$(git -C "$root" rev-parse --verify -q HEAD 2>/dev/null)" || return 1
  files="$(git -C "$root" ls-files --others --exclude-standard 2>/dev/null)"
  dirt="$(git -C "$root" diff HEAD --binary --no-ext-diff --no-textconv 2>/dev/null)"
  if [[ -n "$files" ]]; then
    dirt+=$'\n'"$files"$'\n'"$(print -r -- "$files" | git -C "$root" hash-object --stdin-paths 2>/dev/null)"
  fi
  if [[ -z "$dirt" ]]; then
    print -r -- "$head clean"
  else
    print -r -- "$head $(print -r -- "$dirt" | shasum | cut -c1-16)"
  fi
}

# 0 when $@ (the run's own arguments, action included) is the run a heartbeat repeats: a `test` of
# scheme Cadence on the Mac over the WHOLE CadenceTests target and nothing else. Anything narrower
# or wider is not that answer, so a green one records nothing.
full_unit_run() {
  local -a vals dests
  local scheme=""
  local -i i has_test=0
  vals=(${(f)"$(only_testing_values "$@")"})
  dests=()
  for (( i = 1; i <= $#; i++ )); do
    case "${argv[i]}" in
      test) has_test=1 ;;
      -scheme) scheme="${argv[i+1]:-}" ;;
      -destination) dests+=("${argv[i+1]:-}") ;;
      -destination=*) dests+=("${argv[i]#-destination=}") ;;
      -skip-testing*|-testPlan|-only-test-configuration|-skip-test-configuration) return 1 ;;
    esac
  done
  (( has_test )) || return 1
  [[ "$scheme" == Cadence ]] || return 1
  (( ${#vals} == 1 )) && [[ "${vals[1]}" == CadenceTests ]] || return 1
  (( ${#dests} == 1 )) && [[ "${dests[1]}" == platform=macOS || "${dests[1]}" == platform=macOS,* ]] || return 1
  return 0
}

# One record per tree root, so a scratch tree's green never answers for the checkout's.
last_green_file() {  # $1 = tree root
  local dir="${CADENCE_XCB_STATE_DIR:-$TMP_BASE}"
  [[ "$dir" != */ ]] && dir="$dir/"
  print -r -- "${dir}cadence-xcb-last-green.$(print -rn -- "${1:A}" | shasum | cut -c1-12)"
}

# `last-green`: exit 0 UNCHANGED (HEAD and the working tree are exactly the recorded green),
# 1 CHANGED, 3 NO-RECORD. Run from the tree it asks about.
last_green_report() {  # $1 = tree root
  local root=$1 file rec_sha rec_fp now now_sha now_fp
  file="$(last_green_file "$root")"
  if [[ ! -f "$file" ]]; then
    say "last-green: NO-RECORD -- no full green -only-testing:CadenceTests macOS run recorded for $root"
    return 3
  fi
  rec_sha="$(sed -n 's/^sha=//p' "$file" | head -1)"
  rec_fp="$(sed -n 's/^tree=//p' "$file" | head -1)"
  say "last-green record ($file):"
  sed 's/^/  /' "$file"
  if ! now="$(tree_fingerprint "$root")"; then
    say "last-green: CHANGED -- $root is not a git checkout now, so it cannot be compared"
    return 1
  fi
  now_sha="${now%% *}"; now_fp="${now#* }"
  if [[ "$now_sha" == "$rec_sha" && "$now_fp" == "$rec_fp" ]]; then
    say "last-green: UNCHANGED -- HEAD $now_sha and the working tree ($now_fp) are the recorded green."
    return 0
  fi
  say "last-green: CHANGED -- now HEAD $now_sha, tree $now_fp" \
      "($( [[ "$now_sha" == "$rec_sha" ]] && print -rn -- "same HEAD, working tree differs" \
           || print -rn -- "$(git -C "$root" diff --name-only "$rec_sha" "$now_sha" 2>/dev/null | grep -c .) path(s) differ from $rec_sha"))."
  return 1
}


# --- QUEUED vs RUNNING vs WEDGED (T-2071), and silence nobody is watching (T-1920) ----
# Three states that look identical from outside, and the cost of not separating them is measured
# repeatedly: agents concluded a run had DIED when it was queued behind the test-host lock and
# started a second one, and T-2067 was written up as a code red -- "every CadenceTests run since
# has produced ZERO test result lines" -- over scoped runs that were in fact passing throughout.
#
# THREE SIGNALS AGENTS REACH FOR FIRST, AND WHY EACH IS WRONG HERE.
#
#   1. `> full.log` IS NOT THE TEST LOG, and this is the big one. xcb writes xcodebuild's stream to
#      `${TMPDIR}cadence-xcb-<id>.<ts>-<pid>.log` and prints only its preflight and its final
#      summary on stdout. Measured against a live, healthy, actively-passing run: the agent's own
#      redirect held 727 bytes and 0 result lines while xcb's own log held 1,237,974 bytes and
#      3,135. An agent tailing its redirect mid-run sees zero result lines on a green suite, every
#      time. This reader counts from the xcb log and never from a redirect.
#   2. ELAPSED TIME DOES NOT DISCRIMINATE and is not read here. The full suite legitimately runs
#      19+ minutes -- individual `@Test`s in it measured 3.7s, 4.5s and 15.6s -- so a wedged run
#      and a slow run are both "quiet for fifteen minutes".
#   3. NEITHER DOES CPU, and that one is a trap rather than merely useless. A wedged xcodebuild
#      measured 12 seconds of CPU across 35 minutes; a HEALTHY one measured 9.29 seconds across
#      9:48, because `xcodebuild` is a parent process and its children do the work. Low parent CPU
#      is NORMAL during a healthy run. It is not a signal and this reader does not use it.
#
# WHAT DOES DISCRIMINATE IS LOG GROWTH, plus two facts the log's own NAME carries for free.
#
#   * The per-invocation log is `cadence-xcb-<id>.<ts>-<pid>.log` and `cadence-xcb-<id>.log` is a
#     symlink to the newest. The name is chosen at the top of the script; the redirect that
#     CREATES the file does not happen until after `test-host-lock.sh acquire` returns. So a run
#     waiting its turn is a DANGLING SYMLINK -- named, pointing at nothing -- and that is the
#     QUEUED reading, available with one `readlink` and no sampling at all.
#   * `<pid>` is that invocation's own `$$`. `kill -0` on it separates a run that is queued from
#     one whose owner is GONE, which is the state every agent who "concluded a run had died" was
#     actually trying to ask about. A dead owner with no log, or with a log that stops, is
#     ABANDONED -- a distinct answer, not a guess.
#   * Growth is the liveness signal for a run that HAS started: bytes in the xcb log between two
#     reads a sample window apart. T-2071 measured 30 seconds as enough, which is why that is the
#     default; anything shorter can land inside one slow test body.
#
# AND WEDGED IS NOT INFERRED FROM SILENCE ALONE, because silence alone cannot carry it -- that is
# exactly the error T-1920 made three times in a row, inferring a process's liveness from a status
# string and two timestamps and being wrong in a different direction each time. A silent run is
# only called WEDGED when a SECOND, independent reading agrees: the xctest session log shows a
# session that reached "Received new test session connection" and "resuming connection" and never
# "requested serialized transport". A healthy session logs the second within 3ms of the first, and
# T-2067 measured that correlation at 18-for-18 with no exception. When the run is silent and that
# signature is ABSENT, the answer is STALLED -- "quiet, and not the wedge we know" -- and never
# WEDGED. A status tool that lies is worse than none, so the honest fifth verdict stays.
#
# `/usr/bin/log`, with the path: `log` is shadowed by a shell builtin here.
RUNSTATE_SESSION_CONNECTED='Received new test session connection'
RUNSTATE_SESSION_TRANSPORT='requested serialized transport'
RUNSTATE_EXIT_RUNNING=0
RUNSTATE_EXIT_QUEUED=10
RUNSTATE_EXIT_WEDGED=11
RUNSTATE_EXIT_FINISHED=12
RUNSTATE_EXIT_STALLED=13
RUNSTATE_EXIT_ABANDONED=14
RUNSTATE_EXIT_NO_LOG=15
# A dangling pointer whose name is older than this is never read as QUEUED, however alive the pid
# in it looks. MEASURED, not guessed: a sweep of this Mac's real TMPDIR found 450 pointers and
# called FOUR of them QUEUED -- logs from three weeks ago whose long-dead owner pid had since been
# REUSED by an unrelated live process. The test-host lease is 5400s, so a run still queued two
# hours past its own name is not queued; it is a coincidence of the pid table.
RUNSTATE_STALE_AFTER=${CADENCE_RUNSTATE_STALE_AFTER:-7200}
# How far back the id-less sweep looks. The same measurement is why there is a window at all: 450
# runs, 446 of them finished or dead weeks ago, is not a report anybody reads -- and a sweep whose
# exit code is dominated by month-old logs cannot be the thing that makes a LIVE hang visible.
RUNSTATE_SINCE=${CADENCE_RUNSTATE_SINCE:-21600}
# THE SECOND WINDOW, and it exists because of a measurement taken against a live healthy run of
# this repository's own suite on 2026-10-06: the xcb log sat at **exactly 707008 bytes for 75+
# consecutive seconds** while the run was perfectly fine -- it was inside
# `theTestHostLocksOwnGuardsStillFire()`, which spawns real processes and real sleeps and prints
# nothing while it does. So T-2071's 30 seconds is enough to recognise a run that IS talking and
# nowhere near enough to conclude that one is not, and a reader that stopped there would have
# called a healthy build STALLED several times an hour. A run that grew in the first window is
# answered in 30s, as before; only a run that did NOT pays for the confirmation.
RUNSTATE_SAMPLE_LONG=${CADENCE_RUNSTATE_SAMPLE_LONG:-150}

# The testing seam, and the same one `pmset_log` uses: the live condition cannot be induced (it
# needs this Mac's testmanagerd to stop answering), so `selftest` substitutes a file in the
# format `log show` prints. The predicate is the subsystem, which is what makes the live read
# cheap -- about two seconds, no privilege, the shape T-2070's automation-mode probe established.
xctest_session_log() {
  if [[ -n "${CADENCE_XCTEST_SESSION_FIXTURE:-}" ]]; then
    cat -- "$CADENCE_XCTEST_SESSION_FIXTURE" 2>/dev/null
    return 0
  fi
  /usr/bin/log show --last "${CADENCE_RUNSTATE_LOG_WINDOW:-30m}" \
    --predicate 'subsystem == "com.apple.dt.xctest"' --style compact 2>/dev/null
}

# Sessions that connected minus sessions that got transport. Positive means at least one session
# is hanging where T-2067 hangs. Zero or negative is healthy, exactly as T-2070's probe reads it.
# Memoised for the length of one report: the live read costs about two seconds, and a sweep with
# several silent runs in it would otherwise pay that per run for an answer about the HOST, which
# is the same answer every time it asks.
RUNSTATE_OUTSTANDING_MEMO=""
runstate_transport_outstanding() {
  if [[ -n "$RUNSTATE_OUTSTANDING_MEMO" ]]; then
    print -r -- "$RUNSTATE_OUTSTANDING_MEMO"
    return 0
  fi
  local text; text="$(xctest_session_log)"
  local -i conn trans
  conn=$(print -r -- "$text" | grep -cF -- "$RUNSTATE_SESSION_CONNECTED")
  trans=$(print -r -- "$text" | grep -cF -- "$RUNSTATE_SESSION_TRANSPORT")
  RUNSTATE_OUTSTANDING_MEMO="$(( conn - trans ))"
  print -r -- "$RUNSTATE_OUTSTANDING_MEMO"
}

# The invocation pid encoded in a per-invocation log's name; empty for the unsuffixed symlink or
# any other shape, and an empty answer is never read as "dead".
runstate_log_pid() {  # $1 = log path
  local base="${1:t}" tail
  base="${base%.log}"
  tail="${base##*-}"
  [[ "$tail" == <-> ]] && print -r -- "$tail"
}

# The run's own start time, read out of the log's name (`<id>.<YYYYmmdd>-<HHMMSS>-<pid>.log`)
# rather than off the filesystem: a pointer's mtime moves when anything re-points it, and the name
# is the only record of when THIS run was named. 0 when the name does not carry one.
runstate_name_epoch() {  # $1 = a log path or basename
  local base="${1:t}" stamp
  base="${base%.log}"
  stamp="${base##*.}"          # <YYYYmmdd>-<HHMMSS>-<pid>
  stamp="${stamp%-*}"          # <YYYYmmdd>-<HHMMSS>
  [[ "$stamp" == <->-<-> ]] || { print -r -- 0; return 0 }
  date -j -f '%Y%m%d-%H%M%S' "$stamp" +%s 2>/dev/null || print -r -- 0
}

# The log THIS id's newest run writes: the symlink's target by preference, because that is the
# pointer xcb re-points on every invocation and it is correct even while the target is absent.
runstate_log_path() {  # $1 = id
  local latest="${TMP_BASE}cadence-xcb-$1.log" tgt
  if [[ -L "$latest" ]]; then
    tgt="$(readlink "$latest")"
    [[ "$tgt" != /* ]] && tgt="${TMP_BASE}${tgt}"
    print -r -- "$tgt"
    return 0
  fi
  [[ -f "$latest" ]] && { print -r -- "$latest"; return 0 }
  local -a logs
  logs=(${TMP_BASE}cadence-xcb-$1.*.log(N.om))
  (( ${#logs} )) && { print -r -- "${logs[1]}"; return 0 }
  return 1
}

# Every id that has a `cadence-xcb-<id>.log` pointer in TMPDIR. The per-invocation logs are
# skipped: their names carry a `.` in the id position, and reporting both would double-count the
# newest run of every id under two names.
runstate_ids() {
  local f b target
  local -i cutoff=$(( $(date +%s) - RUNSTATE_SINCE )) stamp=0
  for f in ${TMP_BASE}cadence-xcb-*.log(N); do
    b="${f:t}"; b="${b#cadence-xcb-}"; b="${b%.log}"
    [[ "$b" == *.* ]] && continue
    target="$(readlink "$f" 2>/dev/null)"
    [[ -z "$target" ]] && target="${f:t}"
    stamp=$(runstate_name_epoch "$target")
    # Fails OPEN: a name this cannot date is reported rather than hidden. Every log this script
    # writes carries the stamp, so the open case is somebody else's file, and a sweep that silently
    # drops what it cannot parse is the hollow instrument one layer down.
    (( stamp == 0 || stamp >= cutoff )) || continue
    print -r -- "$b"
  done
}

RUNSTATE_TERMINAL='\*\* (TEST|BUILD|CLEAN|ANALYZE|ARCHIVE|TEST EXECUTE) (SUCCEEDED|FAILED) \*\*'

# Everything that can be answered WITHOUT paying for the sample window, so a sweep sleeps once for
# all of its runs rather than once per run. Prints one `|`-joined record; the verdict is `SAMPLE`
# when growth is the only thing left to ask.
runstate_snapshot() {  # $1 = id
  local id=$1 log pid="" verdict note=""
  if ! log="$(runstate_log_path "$id")"; then
    print -r -- "NO-LOG|$id||0|0||0|unknown|0"
    return 0
  fi
  pid="$(runstate_log_pid "$log")"
  local owner="unknown"
  if [[ -n "$pid" ]]; then
    kill -0 "$pid" 2>/dev/null && owner="alive" || owner="dead"
  fi
  local -i stamp named_age
  stamp=$(runstate_name_epoch "$log")
  named_age=$(( stamp > 0 ? $(date +%s) - stamp : 0 ))
  if [[ ! -e "$log" ]]; then
    # Named and never written: the redirect has not happened, so xcodebuild has not been launched.
    # A LIVE owner means it is waiting its turn -- but only while the name is recent, because pids
    # are reused and a three-week-old pointer whose number happens to be live again is not a queue.
    # Anything else here is NOT called ABANDONED: there is no log, so there is nothing to have been
    # abandoned, and "the run died" and "TMPDIR was swept" are the same two bytes of evidence.
    if [[ "$owner" == "alive" ]] && (( stamp == 0 || named_age <= RUNSTATE_STALE_AFTER )); then
      verdict="QUEUED"
    else
      verdict="NO-LOG"
    fi
    print -r -- "$verdict|$id|$log|0|0|$pid|$named_age|$owner|0"
    return 0
  fi
  local -i size ran mtime age banner
  size=$(wc -c < "$log" 2>/dev/null | tr -d ' ')
  ran=${$(tests_seen "$log"):-0}
  mtime=$(stat -f %m "$log" 2>/dev/null || print 0)
  age=$(( $(date +%s) - mtime ))
  banner=0
  tail -n 5 "$log" 2>/dev/null | grep -qE -- "$RUNSTATE_TERMINAL" && banner=1
  # A TERMINAL BANNER IS NOT ON ITS OWN AN ENDING, and the selftest caught this reading getting it
  # wrong: `xcodebuild` prints its banner last, so a whole-file -- or even a last-five-lines --
  # search reads a build banner that a later phase went straight past as "this run is over". The
  # banner only closes a run whose OWNER IS GONE; while the owner is alive the question is still
  # the growth question, and a growing log is RUNNING whatever is written in it.
  if (( banner )) && [[ "$owner" != "alive" ]]; then
    print -r -- "FINISHED|$id|$log|$size|$ran|$pid|$age|$owner|$banner"
    return 0
  fi
  # Launched but xcodebuild has not spoken yet. T-2071's own reading of QUEUED, kept for a caller
  # that pre-creates the file; under this script the dangling-symlink branch above answers first.
  if ! grep -qF 'Command line invocation' "$log" 2>/dev/null; then
    [[ "$owner" == "dead" ]] && verdict="ABANDONED" || verdict="QUEUED"
    print -r -- "$verdict|$id|$log|$size|$ran|$pid|$age|$owner|$banner"
    return 0
  fi
  print -r -- "SAMPLE|$id|$log|$size|$ran|$pid|$age|$owner|$banner"
}

# The second half of a sampled reading: the same log, one window later.
runstate_classify() {  # $@ = the snapshot record's fields
  local id=$2 log=$3 pid=$6 owner=$8
  local -i size0=$4 ran0=$5 banner=$9
  local -i size1 ran1 outstanding
  size1=$(wc -c < "$log" 2>/dev/null | tr -d ' ')
  ran1=${$(tests_seen "$log"):-0}
  if (( size1 > size0 )); then
    print -r -- "RUNNING|$id|$log|$size1|$ran1|$pid|$(( size1 - size0 ))|$(( ran1 - ran0 ))|$banner"
    return 0
  fi
  if (( banner )); then
    print -r -- "FINISHED|$id|$log|$size1|$ran1|$pid|0|0|$banner"
    return 0
  fi
  if [[ "$owner" == "dead" ]]; then
    print -r -- "ABANDONED|$id|$log|$size1|$ran1|$pid|0|0|$banner"
    return 0
  fi
  outstanding=$(runstate_transport_outstanding)
  if (( ran1 == 0 && outstanding > 0 )); then
    print -r -- "WEDGED|$id|$log|$size1|$ran1|$pid|0|$outstanding|$banner"
    return 0
  fi
  print -r -- "STALLED|$id|$log|$size1|$ran1|$pid|0|$outstanding|$banner"
}

runstate_exit_for() {  # $1 = verdict
  case "$1" in
    RUNNING)   print -r -- $RUNSTATE_EXIT_RUNNING ;;
    QUEUED)    print -r -- $RUNSTATE_EXIT_QUEUED ;;
    WEDGED)    print -r -- $RUNSTATE_EXIT_WEDGED ;;
    FINISHED)  print -r -- $RUNSTATE_EXIT_FINISHED ;;
    STALLED)   print -r -- $RUNSTATE_EXIT_STALLED ;;
    ABANDONED) print -r -- $RUNSTATE_EXIT_ABANDONED ;;
    *)         print -r -- $RUNSTATE_EXIT_NO_LOG ;;
  esac
}

# The queue line for this id, read from the lock itself rather than guessed. `xcb.sh test` files
# its ticket as `xcb-<id>`, so the holder and the wait are both already recorded there -- and a
# QUEUED verdict that can also say "waiting 800s behind xcb-widgetdrop" is the difference between
# an agent waiting and an agent starting a second run on top of the first.
runstate_lock_line() {  # $1 = id
  # NOT `status`: that name is a zsh special (an alias for `$?`) and assigning it is a read-only
  # error printed into the middle of the verdict -- the same shape as T-1074's stray assignment.
  local lock_status holder
  lock_status="$("$ROOT_DIR/scripts/test-host-lock.sh" status 2>/dev/null)"
  [[ -z "$lock_status" ]] && return 1
  holder="$(print -r -- "$lock_status" | head -1)"
  print -r -- "test host: $holder"
  print -r -- "$lock_status" | grep -F "xcb-$1" | sed 's/^[[:space:]]*/this id on the lock: /'
  return 0
}

# One run, already classified, printed. The verdict word is the product; everything under it is
# what the next reader needs in order not to re-derive the same reading by hand.
runstate_print() {  # $@ = a classified record
  local verdict=$1 id=$2 log=$3 pid=$6 extra=$7 extra2=$8
  local -i size=$4 ran=$5
  say ""
  say "  id:        $id"
  [[ -n "$log" ]] && say "  log:       $log"
  case "$verdict" in
    NO-LOG)
      say "  run-state: NO-LOG -- there is no log to read for this id."
      say "             Either nothing ever claimed it in $TMP_BASE, or a run was named here and"
      say "             never written and its owner is gone: killed while queued, or swept out of"
      say "             TMPDIR afterwards. Those leave identical evidence, so neither is asserted."
      say "             This is not a verdict about a live run. It is the absence of one to read."
      ;;
    QUEUED)
      say "  run-state: QUEUED -- named, and xcodebuild has NOT been launched (pid $pid is alive)."
      say "             The log name is chosen before \`test-host-lock.sh acquire\` is called, so an"
      say "             absent or empty log with a live owner means this run is WAITING ITS TURN."
      say "             Do not start a second run. Elapsed time says nothing about it."
      runstate_lock_line "$id" | sed 's/^/             /'
      ;;
    RUNNING)
      say "  run-state: RUNNING -- the xcb log GREW by $extra byte(s) over the sample window"
      say "             (now $size bytes, $ran test result line(s), +$extra2 in the window)."
      say "             Growth is the liveness signal; CPU on the xcodebuild parent is not, because"
      say "             its children do the work (a healthy run measured 9.29s CPU over 9:48)."
      ;;
    WEDGED)
      say "  run-state: WEDGED -- the log did not grow, it holds ZERO test result lines, and the"
      say "             xctest session log shows $extra2 session(s) that connected and never"
      say "             \"$RUNSTATE_SESSION_TRANSPORT\" (T-2067)."
      say "             A healthy session logs that within 3ms of connecting; T-2067 measured the"
      say "             correlation 18-for-18. This run will not produce results on its own."
      say "             It is a state of this MAC, not of your change, and restarting testmanagerd"
      say "             is an admin change and the OWNER's call -- report it, do not re-run."
      ;;
    STALLED)
      say "  run-state: STALLED -- the log did not grow over the sample window, and the T-2067"
      say "             wedge verdict does NOT apply (unanswered sessions: $extra2)."
      say "             It is withheld deliberately: $ran result line(s) are already in this log, or"
      say "             the sessions are balanced, and either way silence here is as consistent with"
      say "             one slow test body as with a hang. Re-read with a longer window --"
      say "             CADENCE_RUNSTATE_SAMPLE=120 ./scripts/xcb.sh run-state $id -- before"
      say "             concluding anything. Do not kill it on this reading."
      ;;
    FINISHED)
      say "  run-state: FINISHED -- the log carries xcodebuild's own terminal banner"
      say "             ($size bytes, $ran test result line(s)). It is not growing because it is OVER."
      say "             ./scripts/xcb.sh check-test-log '$log' is the verdict; this is not."
      ;;
    ABANDONED)
      say "  run-state: ABANDONED -- the xcb.sh invocation that claimed this log (pid $pid) is GONE"
      say "             and the log is not growing. This is the state agents guess at when they say"
      say "             \"the run died\"; here it is read, not guessed, from the pid in the log name."
      say "             Its test-host lease may still be held until the owner check reclaims it."
      ;;
  esac
}

# `run-state [id...]`: the three-way discriminator, and with no id a sweep of every run this
# TMPDIR knows about. The sweep is the T-1920 half -- a hung run was invisible for three hours
# because nothing anywhere could see it, and the only thing that makes silence visible without a
# human noticing it is a cheap check something else can run on a schedule. It exits non-zero when
# any run is WEDGED or ABANDONED, so it is a gate and not only a page to read.
run_state_report() {  # $@ = ids, or none for every id in TMPDIR
  # Every local is declared ONCE, at the top, with an assignment. A bare `local x` in a zsh
  # function whose parameter is already local PRINTS `x=<value>` (T-1074), and a redeclaration
  # inside a loop puts that line straight into the middle of a verdict.
  local -a ids=("$@") snaps=() finals=() fields=() parts=() second=()
  local -A tally=()
  local -i sweep=0 sample=${CADENCE_RUNSTATE_SAMPLE:-30} needs=0 worst=0 rc=0
  local -i long=${CADENCE_RUNSTATE_SAMPLE_LONG:-150} needs_long=0 k=0
  local id="" rec="" verdict="" line=""
  if (( ${#ids} == 0 )); then
    sweep=1
    for line in ${(f)"$(runstate_ids)"}; do
      [[ -n "$line" ]] && ids+=("$line")
    done
  fi
  (( sample < 1 )) && sample=1
  say "== xcb run-state ($( (( sweep )) && print -n "sweep of $TMP_BASE" || print -n "${(j:, :)ids}" )) =="
  if (( ${#ids} == 0 )); then
    say "  run-state: NO-LOG -- no cadence-xcb-*.log in $TMP_BASE at all."
    return $RUNSTATE_EXIT_NO_LOG
  fi
  for id in $ids; do
    snaps+=("$(runstate_snapshot "$id")")
  done
  for rec in $snaps; do
    [[ "${rec%%|*}" == SAMPLE ]] && needs=1
  done
  if (( needs )); then
    say "  sampling ${sample}s of xcb-log growth (CADENCE_RUNSTATE_SAMPLE overrides)..."
    sleep "$sample"
  fi
  for rec in $snaps; do
    fields=("${(@s:|:)rec}")
    if [[ "${fields[1]}" == SAMPLE ]]; then
      finals+=("$(runstate_classify "${fields[@]}")")
    else
      finals+=("$rec")
    fi
  done
  # A silent run gets a SECOND window before the answer is published, and it is re-classified from
  # its ORIGINAL size, so growth anywhere across the whole span counts. One extra sleep for the
  # whole report, paid only when something was quiet -- and never paid at all by QUEUED, ABANDONED,
  # NO-LOG or a settled FINISHED, none of which sample anything.
  for rec in $finals; do
    verdict="${rec%%|*}"
    [[ "$verdict" == WEDGED || "$verdict" == STALLED ]] && needs_long=1
  done
  if (( needs_long )); then
    say "  no growth in the first window -- confirming over ${long}s more before saying so."
    say "  (A healthy run of this suite measured 75+ seconds at an unchanged byte count.)"
    sleep "$long"
    k=0
    for rec in $snaps; do
      (( k++ ))
      verdict="${finals[k]%%|*}"
      if [[ "${rec%%|*}" == SAMPLE && ( "$verdict" == WEDGED || "$verdict" == STALLED ) ]]; then
        fields=("${(@s:|:)rec}")
        second+=("$(runstate_classify "${fields[@]}")")
      else
        second+=("${finals[k]}")
      fi
    done
    finals=("${second[@]}")
  fi
  for rec in $finals; do
    fields=("${(@s:|:)rec}")
    runstate_print "${fields[@]}"
    verdict="${fields[1]}"
    tally[$verdict]=$(( ${tally[$verdict]:-0} + 1 ))
    rc=$(runstate_exit_for "$verdict")
    # Explicit precedence, not last-one-wins: WEDGED outranks ABANDONED outranks everything else.
    # A sweep's exit code is the one thing a scheduled caller reads, and an order that depends on
    # the alphabet is an instrument whose answer changes when somebody renames an agent.
    if [[ "$verdict" == WEDGED ]]; then
      worst=$rc
    elif [[ "$verdict" == ABANDONED ]] && (( worst != RUNSTATE_EXIT_WEDGED )); then
      worst=$rc
    elif (( worst == 0 )); then
      worst=$rc
    fi
  done
  say ""
  for verdict in ${(ko)tally}; do
    parts+=("${tally[$verdict]} $verdict")
  done
  say "  run-state summary: ${#finals} run(s) -- ${(j:, :)parts}"
  return $worst
}

# --- selftest ----------------------------------------------------------------
# `agent-commit.sh selftest` and `mutate.sh selftest` are the precedent: a guard nobody exercises
# is the hollow instrument this repository keeps finding one layer up, and this one is easy to
# hollow out by accident, because its whole job is to say nothing on the normal path. Both new
# behaviours are induced -- against a fixture index, so the assertions do not move when somebody
# adds a suite, and then against the LIVE index, so a fixture that has drifted away from the real
# parser cannot pass for one that matches it. It builds nothing and takes about a second.
selftest_only_testing() {
  local -a failures performed
  failures=(); performed=()
  check() {
    local name=$1 ok=$2 detail=${3:-}
    performed+=("$name")
    say "  $( (( ok )) && print -n "ok  " || print -n "FAIL")  $name$( (( ok )) || print -n "  <- $detail")"
    (( ok )) || failures+=("$name")
  }

  say "== xcb.sh selftest (T-1076 -only-testing: resolver) =="
  local here="$SCRIPT_PATH"
  local ws; ws=$(mktemp -d "${TMP_BASE}cadence-xcb-selftest-XXXXXX")
  # AlphaTests.swift holds two suites; SoloTests.swift holds exactly one.
  print -rl -- $'AlphaTests\tAlphaTests.swift\t3' \
               $'AlphaHelperTests\tAlphaTests.swift\t7' \
               $'SoloTests\tSoloTests.swift\t4' > "$ws/index.tsv"
  : > "$ws/empty.tsv"
  local out rc

  run_fixture() {
    out=$(CADENCE_SUITE_FILES="$1" zsh "$here" check-only-testing "${@:2}" 2>&1); rc=$?
  }

  say ""
  say " 1. an unknown suite name is REFUSED before any build"
  run_fixture "$ws/index.tsv" CadenceTests/NoSuchSuiteAnywhere
  check "unknown name exits 8" $( [[ $rc == 8 ]] && print 1 || print 0 ) "exit $rc: $out"
  check "and says what it refused" \
    $( [[ "$out" == *UNKNOWN-SUITE* && "$out" == *"'NoSuchSuiteAnywhere' is not a suite"* ]] && print 1 || print 0 ) "$out"
  # T-1074. ONE unknown name can never show this: a bare `local x` in a zsh function whose
  # parameter is already local PRINTS `x=<value>` rather than redeclaring it, so the leak starts on
  # the SECOND pass through the loop. Naming the same unknown twice is the cheapest way to buy a
  # second pass without also depending on a second name existing. Refusals are this script's whole
  # output, so a stray `n=AlphaTests` lands between "Did you mean:" and the answer.
  run_fixture "$ws/index.tsv" CadenceTests/Alpha CadenceTests/Alpha
  check "a second unknown name really does take a second pass" \
    $( [[ $rc == 8 && $(print -r -- "$out" | grep -c "is not a suite") == 2 ]] && print 1 || print 0 ) "exit $rc: $out"
  # `grep -E`, not a `[[ ]]` glob: `[a-z_]##=` needs EXTENDED_GLOB, and without it the glob form
  # matches literally and passes against an unfixed script. That happened once already (T-1074).
  check "and the refusal carries no stray zsh assignment line (T-1074)" \
    $( print -r -- "$out" | grep -qE '^[a-z_][a-z_0-9]*=' && print 0 || print 1 ) "$out"

  say ""
  say " 2. a KNOWN name with siblings is printed, and does NOT fail the run"
  run_fixture "$ws/index.tsv" CadenceTests/AlphaTests
  check "partial scope exits 0" $( [[ $rc == 0 ]] && print 1 || print 0 ) "exit $rc: $out"
  check "names the file" $( [[ "$out" == *PARTIAL-SCOPE*AlphaTests.swift* ]] && print 1 || print 0 ) "$out"
  check "names the skipped sibling and its count" \
    $( [[ "$out" == *AlphaHelperTests* && "$out" == *"(7 tests)"* ]] && print 1 || print 0 ) "$out"
  check "states the total skipped" $( [[ "$out" == *"7 tests in that file are being skipped"* ]] && print 1 || print 0 ) "$out"

  say ""
  say " 3. the notice does not become noise"
  run_fixture "$ws/index.tsv" CadenceTests/SoloTests
  check "a suite alone in its file is silent" \
    $( [[ $rc == 0 && "$out" != *PARTIAL-SCOPE* ]] && print 1 || print 0 ) "exit $rc: $out"
  run_fixture "$ws/index.tsv" CadenceTests/AlphaTests CadenceTests/AlphaHelperTests
  check "a file scoped in FULL is silent" \
    $( [[ $rc == 0 && "$out" != *PARTIAL-SCOPE* ]] && print 1 || print 0 ) "exit $rc: $out"
  run_fixture "$ws/index.tsv" CadenceTests/AlphaTests/oneSingleTest
  check "scoping to ONE test is silent (the rest of the file is the request, not a finding)" \
    $( [[ $rc == 0 && "$out" != *PARTIAL-SCOPE* ]] && print 1 || print 0 ) "exit $rc: $out"
  run_fixture "$ws/index.tsv" CadenceTests/NotASuite/oneSingleTest
  check "but a typo'd suite is still refused at test granularity" \
    $( [[ $rc == 8 && "$out" == *UNKNOWN-SUITE* ]] && print 1 || print 0 ) "exit $rc: $out"
  run_fixture "$ws/index.tsv" CadenceTests
  check "the whole target is silent" \
    $( [[ $rc == 0 && "$out" != *PARTIAL-SCOPE* && "$out" != *REFUSING* ]] && print 1 || print 0 ) "exit $rc: $out"

  say ""
  say " 4. a guard that cannot answer gets out of the way"
  run_fixture "$ws/index.tsv" CadenceUITests/AnythingAtAll
  check "an unindexed target is not refused" $( [[ $rc == 0 && "$out" != *UNKNOWN-SUITE* ]] && print 1 || print 0 ) "exit $rc: $out"
  run_fixture "$ws/empty.tsv" CadenceTests/NoSuchSuiteAnywhere
  check "an empty index proceeds instead of refusing everything" \
    $( [[ $rc == 0 && "$out" == *"not resolved"* ]] && print 1 || print 0 ) "exit $rc: $out"

  # The fixture above is a claim about the format; these are the claims about the repository. If
  # `--suite-files` ever stops answering, or answers in another shape, section 4 would let this
  # selftest pass in silence -- so the live half asserts a positive finding, not an absence.
  say ""
  say " 5. the same two behaviours against the LIVE CadenceTests index"
  # Skipped, loudly, rather than failed where the index cannot be built at all: the test host is
  # App-Sandboxed and its `/usr/bin/python3` xcrun shim refuses with "cannot be used within an App
  # Sandbox" (T-719), which is a fact about the environment and not about this guard. A skip is not
  # in `performed`, so the tally stays a count of checks that really ran.
  if (( $(suite_files_source | grep -c . ) == 0 )); then
    say "  skip  live checks: test-suite-index.sh returned no suites here (python3 unavailable?)"
    say "        the fixture checks above still pin the behaviour; run this outside a sandbox for the rest."
  else
  out=$(zsh "$here" check-only-testing CadenceTests/CadenceDeepLinkTests 2>&1); rc=$?
  check "live: CadenceDeepLinkTests warns about its sibling" \
    $( [[ $rc == 0 && "$out" == *PARTIAL-SCOPE* && "$out" == *CadenceDeepLinkGrammarAndRevealTests* ]] && print 1 || print 0 ) "exit $rc: $out"
  # AITests.swift is one of the 14 files that declare no suite named after themselves: scoping by
  # its filename is the case the zero-test guard only catches after a full build.
  # Named TWICE, for the T-1074 reason given in section 1 -- and here because the file branch is a
  # different loop body than the "Did you mean" branch above, with its own bare declaration in it.
  out=$(zsh "$here" check-only-testing CadenceTests/AITests CadenceTests/AITests 2>&1); rc=$?
  check "live: a FILE name is refused, and identified as a file" \
    $( [[ $rc == 8 && "$out" == *"It is a FILE"* && "$out" == *AIActionServiceTests* ]] && print 1 || print 0 ) "exit $rc: $out"
  check "live: and the file branch carries no stray zsh assignment line (T-1074)" \
    $( print -r -- "$out" | grep -qE '^[a-z_][a-z_0-9]*=' && print 0 || print 1 ) "$out"
  fi

  say ""
  say " 6. the diagnostic counters (T-1147)"
  # Fixture logs, not builds: the three lines below are copied verbatim out of real logs from this
  # repository on 2026-09-12 (`cadence-xcb-instrufixB/C`), which is the whole point -- the bug was a
  # pattern that matched the wrong real line, so the fixture has to be the real line.
  print -rl -- \
    "SwiftCompile normal arm64 /repo/CadenceTests/Probe.swift (in target 'CadenceTests' from project 'Cadence')" \
    "2026-09-12 04:37:24.072 appintentsmetadataprocessor[66824:4236838] warning: Metadata extraction skipped. No AppIntents.framework dependency found." \
    > "$ws/notice.log"
  print -rl -- \
    "SwiftCompile normal arm64 /repo/CadenceTests/Probe.swift (in target 'CadenceTests' from project 'Cadence')" \
    "/repo/CadenceTests/Probe.swift:15:13: warning: initialization of immutable value 'p' was never used; consider replacing with assignment to '_'" \
    > "$ws/real.log"
  print -rl -- "** BUILD SUCCEEDED **" > "$ws/noop.log"
  local dout drc
  run_counters() { dout=$(zsh "$here" check-warnings "$1" 2>&1); drc=$?; }

  run_counters "$ws/notice.log"
  check "the AppIntents tool notice is NOT counted as a warning" \
    $( [[ $drc == 0 && "$dout" == *"warnings:        0"* ]] && print 1 || print 0 ) "exit $drc: $dout"
  check "but it is still reported, as a tool notice" \
    $( [[ "$dout" == *"tool notices:    1"* ]] && print 1 || print 0 ) "$dout"
  check "and a run that compiled something is not called vacuous" \
    $( [[ "$dout" != *VACUOUS-COUNT* && "$dout" == *"swift compile tasks: 1"* ]] && print 1 || print 0 ) "$dout"

  # The half that makes the rest of it worth anything: a counter that reports 0 on everything
  # would pass every check above. This is the one real Swift warning, and it must be seen.
  run_counters "$ws/real.log"
  check "a real Swift warning IS counted" \
    $( [[ "$dout" == *"warnings:        1"* ]] && print 1 || print 0 ) "$dout"
  check "and it is not double-counted as a tool notice" \
    $( [[ "$dout" != *"tool notices:"* ]] && print 1 || print 0 ) "$dout"

  run_counters "$ws/noop.log"
  check "a run that compiled nothing says VACUOUS-COUNT rather than certifying zero" \
    $( [[ "$dout" == *VACUOUS-COUNT* && "$dout" == *"warnings:        0"* ]] && print 1 || print 0 ) "$dout"

  # --- T-1516: the category the `.swift:` anchor could not see -----------------
  # EVERY LINE OF THESE THREE FIXTURES IS VERBATIM out of real `build-for-testing` logs of this
  # repository captured 2026-09-29 (`cadence-xcb-warncountprobe` 113520 and 113642), with only the
  # absolute source path shortened to `/repo/`. That is not a formality here: the whole defect was
  # a pattern that could not match a real line, so a fixture written by hand from the ticket's
  # description would have reproduced the ticket's own mistake -- it proposed `[A-Za-z#]+`, which
  # the SECOND spelling below (an ATTACHED macro, `@`-prefixed) does not match.
  #
  # `macro.log` is a whole real diagnostic BLOCK, not just its first line, and that is the
  # non-vacuity half: four of its lines say `warning:` or `macro expansion`, and exactly ONE is
  # the diagnostic. The continuation line, the `+---` expansion banner and the `note:` line must
  # all stay out of the count, or one warning is reported as three.
  print -rl -- \
    "SwiftCompile normal arm64 Compiling\\ ZZProbeMacroWarning.swift /repo/CadenceTests/ZZProbeMacroWarning.swift (in target 'CadenceTests' from project 'Cadence')" \
    "macro expansion #expect:1:39: warning: main actor-isolated conformance of 'RemindersConnectionState' to 'Equatable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode [#IsolatedConformances]" \
    '`- /repo/CadenceTests/ZZProbeMacroWarning.swift:8:24: note: expanded code originates here' \
    ' 8 |         #expect(a == b)' \
    '   |         `- note: in expansion of macro '"'"'expect'"'"' here' \
    '   +--- macro expansion #expect ----------------------------------------' \
    '   |1 | Testing.__checkBinaryOperation(a,{ $0 == $1() },b,expression: .__fromBinaryOperation(.__fromSyntaxNode("a"),"==",.__fromSyntaxNode("b")),comments: [],isRequired: false,sourceLocation: Testing.SourceLocation.__here()).__expected()' \
    '   |  |                                       `- warning: main actor-isolated conformance of '"'"'RemindersConnectionState'"'"' to '"'"'Equatable'"'"' cannot be used in nonisolated context; this is an error in the Swift 6 language mode [#IsolatedConformances]' \
    '   +--------------------------------------------------------------------' \
    > "$ws/macro.log"
  # The second spelling. `#expect` is freestanding and spells itself `#name`; `@ObservationTracked`
  # is ATTACHED and spells itself `@name`. Both are real lines from the same batch of logs, and a
  # pattern that names only letters and `#` sees one of them.
  print -rl -- \
    "SwiftCompile normal arm64 Compiling\\ ZZProbeMacroWarning.swift /repo/CadenceTests/ZZProbeMacroWarning.swift (in target 'CadenceTests' from project 'Cadence')" \
    "macro expansion @ObservationTracked:2:24: warning: 'ZZProbeDeprecated' is deprecated: probe [#DeprecatedDeclaration]" \
    '   |  |                        `- warning: '"'"'ZZProbeDeprecated'"'"' is deprecated: probe [#DeprecatedDeclaration]' \
    > "$ws/attached-macro.log"
  # And the direction the anchor exists to protect, which is why the first pattern was not widened.
  # The AppIntents line is verbatim from this repository's own logs (it is in EVERY honest run);
  # the `ld:` and `actool:` lines are the two shapes the comment above SWIFT_WARNING_PATTERN names
  # as the reason for the anchor, written in their canonical form -- this tree emits neither today,
  # which is exactly why they have to be asserted rather than waited for.
  print -rl -- \
    "SwiftCompile normal arm64 /repo/CadenceTests/Probe.swift (in target 'CadenceTests' from project 'Cadence')" \
    "2026-09-12 04:37:24.072 appintentsmetadataprocessor[66824:4236838] warning: Metadata extraction skipped. No AppIntents.framework dependency found." \
    "ld: warning: ignoring duplicate libraries: '-lc++'" \
    "actool: warning: The app icon set \"AppIcon\" has an unassigned child." \
    > "$ws/toolnoise.log"

  run_counters "$ws/macro.log"
  check "a real macro-expansion warning IS counted, though it has no \`.swift:N:C:\` prefix (T-1516)" \
    $( [[ "$dout" == *"warnings:        1"* ]] && print 1 || print 0 ) "$dout"
  check "…and the banner says so, rather than leaving the reader grepping for a path" \
    $( [[ "$dout" == *MACRO-EXPANSION-WARNING* ]] && print 1 || print 0 ) "$dout"
  check "…and the same diagnostic's continuation and \`+---\` lines are NOT counted again" \
    $( [[ "$dout" != *"warnings:        2"* && "$dout" != *"warnings:        3"* ]] && print 1 || print 0 ) "$dout"
  run_counters "$ws/attached-macro.log"
  check "an ATTACHED macro spells itself \`@name\`, and that spelling is counted too" \
    $( [[ "$dout" == *"warnings:        1"* ]] && print 1 || print 0 ) "$dout"
  # The half that makes all of the above worth anything: widening the first pattern would have
  # passed every check in this section and turned every link and asset notice into a red build.
  run_counters "$ws/toolnoise.log"
  check "ld:, actool: and the AppIntents notice are STILL not compiler warnings" \
    $( [[ $drc == 0 && "$dout" == *"warnings:        0"* ]] && print 1 || print 0 ) "exit $drc: $dout"
  check "…and all three are still reported as tool notices rather than dropped" \
    $( [[ "$dout" == *"tool notices:    3"* ]] && print 1 || print 0 ) "$dout"
  check "…and nothing in that log is called a macro expansion" \
    $( [[ "$dout" != *MACRO-EXPANSION-WARNING* ]] && print 1 || print 0 ) "$dout"
  run_counters "$ws/real.log"
  check "an ordinary \`.swift:N:C:\` warning is not relabelled as a macro expansion" \
    $( [[ "$dout" != *MACRO-EXPANSION-WARNING* ]] && print 1 || print 0 ) "$dout"

  # --- T-1620: the CONTINUATION line is part of the diagnostic above it, not a tool notice ------
  # The fixture below is the whole point of this subsection and it must carry BOTH halves at once.
  # A log with one notice and no diagnostics passes with the defect fully intact -- `loose -
  # warnings` is right whenever there is nothing to continue -- so `notice.log` and `toolnoise.log`
  # above could never have caught this. A log with diagnostics and no notices would only show the
  # number going to zero, which a counter hard-wired to 0 also does. Both together are what
  # discriminates: two real diagnostics (four `warning:` lines) beside two real notices, where the
  # right answer is 2 and the old answer was 4.
  #
  # The diagnostic half is verbatim out of `xcrun swiftc -typecheck` of a two-deprecation probe on
  # this Mac, 2026-10-01, with the path shortened to `/repo/` -- a REAL rendering of the snippet,
  # because the defect is a pattern that has to match a real line. The notice half is the two
  # shapes already used above: the `appintentsmetadataprocessor` line every honest run of this
  # repository emits, and the canonical `ld: warning:`.
  print -rl -- \
    "SwiftCompile normal arm64 /repo/CadenceTests/Probe.swift (in target 'CadenceTests' from project 'Cadence')" \
    "/repo/CadenceTests/Probe.swift:5:13: warning: 'zzDeprecated()' is deprecated: probe [#DeprecatedDeclaration]" \
    '5 |     let p = zzDeprecated() + zzDeprecated()' \
    '  |             `- warning: '"'"'zzDeprecated()'"'"' is deprecated: probe [#DeprecatedDeclaration]' \
    "/repo/CadenceTests/Probe.swift:5:30: warning: 'zzDeprecated()' is deprecated: probe [#DeprecatedDeclaration]" \
    '5 |     let p = zzDeprecated() + zzDeprecated()' \
    '  |                              `- warning: '"'"'zzDeprecated()'"'"' is deprecated: probe [#DeprecatedDeclaration]' \
    "2026-09-12 04:37:24.072 appintentsmetadataprocessor[66824:4236838] warning: Metadata extraction skipped. No AppIntents.framework dependency found." \
    "ld: warning: ignoring duplicate libraries: '-lc++'" \
    > "$ws/diag-and-notice.log"
  # …and the SAME two notices with the diagnostics removed. This is the control that makes the
  # check a RELATION rather than a number: whatever the right notice count is, adding compiler
  # diagnostics to a log must not change it.
  print -rl -- \
    "SwiftCompile normal arm64 /repo/CadenceTests/Probe.swift (in target 'CadenceTests' from project 'Cadence')" \
    "2026-09-12 04:37:24.072 appintentsmetadataprocessor[66824:4236838] warning: Metadata extraction skipped. No AppIntents.framework dependency found." \
    "ld: warning: ignoring duplicate libraries: '-lc++'" \
    > "$ws/notices-only.log"

  notice_count() {  # $1 = a diagnostic_report banner. Absent line means zero.
    local n; n=$(print -r -- "$1" | sed -n 's/^[[:space:]]*tool notices:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    print -r -- "${n:-0}"
  }
  # The fixture really is the shape this is about -- asserted, not assumed, so that a later edit
  # that quietly drops the continuation lines out of the fixture fails here instead of passing.
  check "the fixture carries a REAL caret continuation, twice (T-1620)" \
    $( (( $(grep -c -- '`- warning:' "$ws/diag-and-notice.log") == 2 )) && print 1 || print 0 ) \
    "$(grep -c -- '`- warning:' "$ws/diag-and-notice.log")"

  local withDiagnostics withoutDiagnostics
  run_counters "$ws/diag-and-notice.log"
  withDiagnostics=$(notice_count "$dout")
  check "two real diagnostics in the same log are still counted once each" \
    $( [[ "$dout" == *"warnings:        2"* ]] && print 1 || print 0 ) "$dout"
  check "…and their caret continuations are NOT reported as tool notices (T-1620)" \
    $( (( withDiagnostics == 2 )) && print 1 || print 0 ) "tool notices: $withDiagnostics in: $dout"
  run_counters "$ws/notices-only.log"
  withoutDiagnostics=$(notice_count "$dout")
  check "…and the SAME two notices alone read the same: adding diagnostics changes nothing" \
    $( (( withDiagnostics == withoutDiagnostics && withoutDiagnostics > 0 )) && print 1 || print 0 ) \
    "with: $withDiagnostics, without: $withoutDiagnostics"
  # The macro block is the log T-1620 was measured on, and it is the stronger case: its only
  # `warning:` lines are one diagnostic and one continuation, so the old reading printed a
  # tool-notice line over a log with no tool in it at all.
  run_counters "$ws/macro.log"
  check "a macro diagnostic's continuation invents no tool notice either (T-1620)" \
    $( [[ "$dout" != *"tool notices:"* ]] && print 1 || print 0 ) "$dout"
  run_counters "$ws/attached-macro.log"
  check "…and neither does an attached macro's" \
    $( [[ "$dout" != *"tool notices:"* ]] && print 1 || print 0 ) "$dout"

  say ""
  say " 7. the warning gate (T-1149)"
  # Section 6 proves the counters COUNT. This proves something acts on the number, which is the
  # entire difference between a banner and a baseline -- and every check below reads the EXIT
  # CODE, because that is the thing the old version never touched.
  run_counters "$ws/real.log"
  check "a real Swift warning on a run that compiled exits $WARNING_GATE_EXIT, not 0" \
    $( (( drc == WARNING_GATE_EXIT )) && print 1 || print 0 ) "exit $drc: $dout"
  check "…and names the offending line rather than only the count" \
    $( [[ "$dout" == *WARNING-BASELINE* && "$dout" == *"Probe.swift:15:13"* ]] && print 1 || print 0 ) "$dout"

  # The two carve-outs, and they matter more than the gate: a gate with no carve-outs here fires on
  # the normal case, and T-986 is the record of what happens to those.
  check "the AppIntents tool notice alone does NOT trip the gate" \
    $( { run_counters "$ws/notice.log"; (( drc == 0 )) } && print 1 || print 0 ) "exit $drc: $dout"

  # T-1516. Section 6 proves the macro-expansion warning is COUNTED; this is the only check that
  # proves it GATES, which is the entire finding -- the old counter saw it, put it in the notice
  # bucket, and exited 0 over fourteen real warnings.
  run_counters "$ws/macro.log"
  check "a macro-expansion warning on a run that compiled exits $WARNING_GATE_EXIT, not 0 (T-1516)" \
    $( (( drc == WARNING_GATE_EXIT )) && print 1 || print 0 ) "exit $drc: $dout"
  check "…and the refusal QUOTES the macro-expansion line, not only the count" \
    $( [[ "$dout" == *WARNING-BASELINE* && "$dout" == *"macro expansion #expect:1:39"* ]] && print 1 || print 0 ) "$dout"
  check "the link/asset/AppIntents notices together still do NOT trip it" \
    $( { run_counters "$ws/toolnoise.log"; (( drc == 0 )) } && print 1 || print 0 ) "exit $drc: $dout"

  # A VACUOUS run carrying warnings. This is the case the gate must NOT fire on and the one a
  # naive `warnings > 0` would: the log holds a real anchored warning and no compile task at all,
  # so the count is inherited from a build this run did not do.
  print -rl -- \
    "/repo/CadenceTests/Probe.swift:15:13: warning: initialization of immutable value 'p' was never used; consider replacing with assignment to '_'" \
    "** BUILD SUCCEEDED **" \
    > "$ws/vacuous-with-warnings.log"
  run_counters "$ws/vacuous-with-warnings.log"
  check "a VACUOUS run with warnings in the log does not gate (the count is over nothing)" \
    $( (( drc == 0 )) && [[ "$dout" == *VACUOUS-COUNT* && "$dout" != *WARNING-BASELINE* ]] && print 1 || print 0 ) "exit $drc: $dout"

  local edout edrc
  edout=$(CADENCE_ALLOW_WARNINGS=1 zsh "$here" check-warnings "$ws/real.log" 2>&1); edrc=$?
  check "CADENCE_ALLOW_WARNINGS=1 downgrades the gate to a report (mutate.sh's case)" \
    $( (( edrc == 0 )) && print 1 || print 0 ) "exit $edrc: $edout"
  check "…and says out loud that it was downgraded, rather than going quiet" \
    $( [[ "$edout" == *"NOT gated"* && "$edout" == *CADENCE_ALLOW_WARNINGS* ]] && print 1 || print 0 ) "$edout"

  say ""
  say " 8. the iOS Simulator destination guard (T-1282)"
  # A fixture in `simctl list devices available` format, because the failure this guard exists to
  # stop was a PARSE of that format being absent entirely -- and because the real list changes with
  # every Xcode update, which is the whole reason the guard reads it live instead of pinning a name.
  # `iPad (A16)` is in it deliberately: a device whose NAME carries parentheses is what a parser
  # that strips "the last parenthesised thing" gets wrong, and this tree has four of them.
  # `iPhone 17 Pro` on two runtimes is the OS= case; the watch is the wrong-platform case.
  print -rl -- \
    "== Devices ==" \
    "-- iOS 26.5 --" \
    "    iPhone 17 Pro (7B642065-86FC-4987-8674-22066D32878C) (Shutdown) " \
    "    iPad (A16) (ECB5F33A-9099-4811-B190-4F4AADF6D1CB) (Shutdown) " \
    "-- iOS 18.4 --" \
    "    iPhone 17 Pro (11111111-2222-3333-4444-555555555555) (Shutdown) " \
    "-- watchOS 26.5 --" \
    "    Apple Watch Series 11 (46mm) (DBDE4F95-A9B3-4670-ACD1-707A12F895B5) (Shutdown) " \
    > "$ws/devices.txt"
  : > "$ws/no-devices.txt"
  local sout srn
  run_destination() {
    sout=$(CADENCE_SIMCTL_DEVICES="$1" zsh "$here" check-destination "${@:2}" 2>&1); srn=$?
  }

  run_destination "$ws/devices.txt" "platform=iOS Simulator,name=iPhone 15"
  check "a device this Mac does not have exits $SIMULATOR_GATE_EXIT, not 0" \
    $( (( srn == SIMULATOR_GATE_EXIT )) && print 1 || print 0 ) "exit $srn: $sout"
  check "…and says what it refused" \
    $( [[ "$sout" == *NO-SUCH-SIMULATOR* && "$sout" == *"'iPhone 15' is not an available iOS Simulator device"* ]] && print 1 || print 0 ) "$sout"
  # The half the ticket is actually about: a refusal that only says "no" sends the agent back to
  # guessing, which is how `iPhone 15` was typed in the first place.
  check "…and NAMES the available ones, as a destination that can be pasted" \
    $( [[ "$sout" == *"-destination 'platform=iOS Simulator,name=iPhone 17 Pro'"* ]] && print 1 || print 0 ) "$sout"
  check "…including one whose own name carries parentheses" \
    $( [[ "$sout" == *"name=iPad (A16)'"* ]] && print 1 || print 0 ) "$sout"
  check "…and does NOT offer a watchOS device as an iOS Simulator" \
    $( [[ "$sout" != *"Apple Watch"* ]] && print 1 || print 0 ) "$sout"
  run_destination "$ws/devices.txt" "platform=iOS Simulator,name=iPhone 15" "platform=iOS Simulator,name=iPhone 14"
  check "a second missing name really does take a second pass, and no stray zsh assignment line (T-1074)" \
    $( [[ $srn == SIMULATOR_GATE_EXIT ]] && print -r -- "$sout" | grep -qE '^[a-z_][a-z_0-9]*=' && print 0 || print 1 ) "exit $srn: $sout"

  # The controls, and they matter more than the refusal: a guard that refused any of the four
  # shapes below would be switched off the same week, and `generic/` is how the repo builds for a
  # simulator without naming one at all.
  run_destination "$ws/devices.txt" "platform=iOS Simulator,name=iPhone 17 Pro"
  check "an available device passes" $( (( srn == 0 )) && print 1 || print 0 ) "exit $srn: $sout"
  check "…and SAYS it resolved, rather than passing in silence" \
    $( [[ "$sout" == *"iOS Simulator destination: iPhone 17 Pro"* ]] && print 1 || print 0 ) "$sout"
  run_destination "$ws/devices.txt" "platform=macOS"
  check "a macOS destination is not this guard's question" \
    $( (( srn == 0 )) && [[ "$sout" != *NO-SUCH-SIMULATOR* ]] && print 1 || print 0 ) "exit $srn: $sout"
  run_destination "$ws/devices.txt" "generic/platform=iOS Simulator"
  check "a generic/ destination names no device on purpose and is not refused" \
    $( (( srn == 0 )) && [[ "$sout" != *NO-SUCH-SIMULATOR* ]] && print 1 || print 0 ) "exit $srn: $sout"
  run_destination "$ws/no-devices.txt" "platform=iOS Simulator,name=iPhone 15"
  check "an empty device list proceeds instead of refusing everything" \
    $( (( srn == 0 )) && [[ "$sout" == *"not resolved"* ]] && print 1 || print 0 ) "exit $srn: $sout"

  run_destination "$ws/devices.txt" "platform=iOS Simulator,name=iPad (A16),OS=18.4"
  check "a device that exists on another runtime is refused, and told which one it is on" \
    $( (( srn == SIMULATOR_GATE_EXIT )) && [[ "$sout" == *"not on iOS 18.4"* && "$sout" == *"it is on iOS 26.5"* ]] && print 1 || print 0 ) "exit $srn: $sout"
  run_destination "$ws/devices.txt" "platform=iOS Simulator,name=iPhone 17 Pro,OS=18.4"
  check "…but a name present on BOTH runtimes at that OS still passes" \
    $( (( srn == 0 )) && print 1 || print 0 ) "exit $srn: $sout"
  run_destination "$ws/devices.txt" "platform=iOS Simulator,id=DEADBEEF-0000-0000-0000-000000000000"
  check "a stale id= is refused too (it fails in the same silent shape)" \
    $( (( srn == SIMULATOR_GATE_EXIT )) && [[ "$sout" == *"matches no available simulator"* ]] && print 1 || print 0 ) "exit $srn: $sout"
  run_destination "$ws/devices.txt" "platform=iOS Simulator,id=7B642065-86FC-4987-8674-22066D32878C"
  check "…and a live id= passes" $( (( srn == 0 )) && print 1 || print 0 ) "exit $srn: $sout"

  say ""
  say " 9a. the interactive UI-test skip report (T-1741)"
  # Fixture logs in XCTest's real shapes. The skip message is the one
  # `CadenceUITestEnvironment.requireInteractiveUITests` throws, abbreviated only where the real
  # one wraps -- the phrase this keys on is present in full.
  print -rl -- \
    "Test Suite 'CadenceUITests' started at 2026-09-30 15:55:16.000" \
    "/repo/CadenceUITests/CadenceUITests.swift:30: CadenceUITests.testRightClickingSidebarListOpensEditPanel : Test skipped - Interactive UI tests are opt-in: they take over the pointer and the keyboard of whatever Mac they run on." \
    "Test Case '-[CadenceUITests testRightClickingSidebarListOpensEditPanel]' skipped (0.002 seconds)." \
    "Test Case '-[CadenceUITests testLaunchesToTodayWithSeededSidebarLists]' passed (7.331 seconds)." \
    "** TEST SUCCEEDED **" \
    > "$ws/interactive-skip.log"
  # The other reason this target skips, and it must NOT be reported as the opt-in.
  print -rl -- \
    "/repo/CadenceUITests/CadenceUITests.swift:9: CadenceUITests.testLaunchesToTodayWithSeededSidebarLists : Test skipped - The Mac's screen is locked, so loginwindow owns the foreground." \
    "Test Case '-[CadenceUITests testLaunchesToTodayWithSeededSidebarLists]' skipped (0.001 seconds)." \
    "** TEST SUCCEEDED **" \
    > "$ws/locked-skip.log"
  # The control that matters most: a run in which everything executed must say NOTHING, or the
  # banner becomes a line every reader learns to scroll past.
  print -rl -- \
    "Test Case '-[CadenceUITests testRightClickingSidebarListOpensEditPanel]' passed (9.100 seconds)." \
    "** TEST SUCCEEDED **" \
    > "$ws/all-ran.log"
  local iout irc
  run_skips() { iout=$(zsh "$here" check-interactive-skips "$1" 2>&1); irc=$?; }

  run_skips "$ws/interactive-skip.log"
  check "a run that skipped an interactive test says INTERACTIVE-SKIPPED" \
    $( [[ "$iout" == *INTERACTIVE-SKIPPED* ]] && print 1 || print 0 ) "exit $irc: $iout"
  check "…counts it, and counts only it (the passing test beside it is not a skip)" \
    $( [[ "$iout" == *"1 test(s) in this run SKIPPED"* ]] && print 1 || print 0 ) "$iout"
  check "…names the test, so the report is checkable rather than a number" \
    $( [[ "$iout" == *"CadenceUITests testRightClickingSidebarListOpensEditPanel"* ]] && print 1 || print 0 ) "$iout"
  check "…and names the touch that turns them on" \
    $( [[ "$iout" == *"touch "*cadence-run-interactive-ui-tests* ]] && print 1 || print 0 ) "$iout"
  check "…and never gates: it exits 0 whatever it found" \
    $( (( irc == 0 )) && print 1 || print 0 ) "exit $irc"

  run_skips "$ws/locked-skip.log"
  check "a locked-screen skip is reported, and NOT as the interactive opt-in" \
    $( [[ "$iout" == *INTERACTIVE-SKIPPED* && "$iout" == *"other than the interactive opt-in"* && "$iout" != *"touch "* ]] && print 1 || print 0 ) "$iout"

  run_skips "$ws/all-ran.log"
  check "a run in which everything executed is SILENT" \
    $( (( irc == 0 )) && [[ "$iout" != *INTERACTIVE-SKIPPED* ]] && print 1 || print 0 ) "exit $irc: $iout"

  say ""
  say " 9b. the MID-RUN locked-screen report (T-1890)"
  # The live condition cannot be induced -- it needs the host's screen to lock out from under a
  # run -- so the session dictionary is a fixture, in `ioreg -n Root -d1 -k IOConsoleUsers` shape.
  # The two CONTROLS are the load-bearing half: a report that fires on an ordinary unlocked run is
  # a line every reader learns to scroll past, which is how the preflight's own finding was missed.
  local -i snow sstart smid sold
  snow=$(date +%s); sstart=$(( snow - 600 )); smid=$(( snow - 300 )); sold=$(( snow - 99999 ))
  print -rl -- '    "IOConsoleLocked" = Yes' \
               "    \"CGSSessionScreenIsLocked\"=Yes" \
               "    \"CGSSessionScreenLockedTime\"=$smid" > "$ws/sess-locked-midrun.txt"
  print -rl -- "    \"CGSSessionScreenLockedTime\"=$smid" \
               '    "kCGSSessionUserNameKey"="someone"' > "$ws/sess-locked-then-unlocked.txt"
  print -rl -- "    \"CGSSessionScreenLockedTime\"=$sold" \
               '    "kCGSSessionUserNameKey"="someone"' > "$ws/sess-old-lock.txt"
  # Locked NOW, locked LONG BEFORE the run: the shape this Mac was actually in on 2026-10-01,
  # and the one a state-only report would have mislabelled as a mid-run lock.
  print -rl -- '    "IOConsoleLocked" = Yes' \
               "    \"CGSSessionScreenIsLocked\"=Yes" \
               "    \"CGSSessionScreenLockedTime\"=$sold" > "$ws/sess-locked-before-run.txt"
  print -rl -- '    "kCGSSessionUserNameKey"="someone"' \
               '    "kCGSSessionOnConsoleKey"=Yes' > "$ws/sess-never-locked.txt"
  local lout lrc
  run_lock() { lout=$(CADENCE_SESSION_FIXTURE="$1" zsh "$here" check-screen-lock-window "$2" 2>&1); lrc=$?; }

  run_lock "$ws/sess-locked-midrun.txt" "$sstart"
  check "a screen still locked at postflight says SCREEN-LOCKED-MID-RUN" \
    $( [[ "$lout" == *SCREEN-LOCKED-MID-RUN* ]] && print 1 || print 0 ) "exit $lrc: $lout"
  check "...and says the reds are not evidence about the code" \
    $( [[ "$lout" == *"NOT EVIDENCE"* ]] && print 1 || print 0 ) "$lout"
  run_lock "$ws/sess-locked-then-unlocked.txt" "$sstart"
  check "a screen that locked mid-run and was UNLOCKED again is still caught (the timestamp)" \
    $( [[ "$lout" == *SCREEN-LOCKED-MID-RUN* && "$lout" == *"UNDERNEATH a live run"* ]] && print 1 || print 0 ) "$lout"
  check "...and reports that it is no longer locked, rather than implying it is" \
    $( [[ "$lout" == *"still locked at postflight: no"* ]] && print 1 || print 0 ) "$lout"
  run_lock "$ws/sess-old-lock.txt" "$sstart"
  check "CONTROL: a lock BEFORE the run window is SILENT (not every past lock is a finding)" \
    $( (( lrc == 0 )) && [[ "$lout" != *SCREEN-LOCKED-MID-RUN* ]] && print 1 || print 0 ) "exit $lrc: $lout"
  run_lock "$ws/sess-locked-before-run.txt" "$sstart"
  check "a lock PREDATING the run is diagnosed as already-locked, NOT as a mid-run lock" \
    $( [[ "$lout" == *"ALREADY LOCKED before this run started"* && "$lout" != *"UNDERNEATH a live run"* ]] && print 1 || print 0 ) "$lout"
  check "...and still reports the lock TIME, which is the only thing that tells the two apart" \
    $( [[ "$lout" == *"locked at:"* && "$lout" == *"epoch $sold"* ]] && print 1 || print 0 ) "$lout"
  run_lock "$ws/sess-locked-midrun.txt" "$sstart"
  check "...while a lock inside the window is diagnosed as UNDERNEATH a live run (the contrast)" \
    $( [[ "$lout" == *"UNDERNEATH a live run"* && "$lout" != *"ALREADY LOCKED"* ]] && print 1 || print 0 ) "$lout"
  run_lock "$ws/sess-never-locked.txt" "$sstart"
  check "CONTROL: a session with no lock key at all is SILENT" \
    $( (( lrc == 0 )) && [[ "$lout" != *SCREEN-LOCKED-MID-RUN* ]] && print 1 || print 0 ) "exit $lrc: $lout"
  check "...and the report never gates: it exits 0 whatever it found" \
    $( (( lrc == 0 )) && print 1 || print 0 ) "exit $lrc"

  # T-2041. The banner explains UI-test reds; a unit-only selection has none, so it gets one line.
  # The arguments go on the command line exactly as the run's own do, so this is the production
  # reading. The UI and no-narrowing cases are the CONTROLS that the banner was not simply deleted.
  run_lock_sel() { lout=$(CADENCE_SESSION_FIXTURE="$1" zsh "$here" check-screen-lock-window "${@:2}" 2>&1); lrc=$?; }
  run_lock_sel "$ws/sess-locked-midrun.txt" "$sstart" -scheme Cadence -only-testing:CadenceTests test
  check "UNIT-ONLY (T-2041): a locked -only-testing:CadenceTests run does NOT print the UI banner" \
    $( [[ "$lout" != *SCREEN-LOCKED-MID-RUN* && "$lout" != *"NOT EVIDENCE"* && "$lout" != *"refuses this outright"* ]] && print 1 || print 0 ) "$lout"
  check "...but still says, in ONE informational line, that the screen was locked" \
    $( (( lrc == 0 )) && [[ "$lout" == *"SCREEN-LOCKED (unit-only, informational; T-2041)"* \
         && $(print -r -- "$lout" | grep -c .) == 1 ]] && print 1 || print 0 ) "exit $lrc: $lout"
  run_lock_sel "$ws/sess-locked-before-run.txt" "$sstart" -only-testing:CadenceTests/SoloTests
  check "UNIT-ONLY: a suite-scoped CadenceTests run on an already-locked Mac gets the note, not the banner" \
    $( [[ "$lout" == *"SCREEN-LOCKED (unit-only"* && "$lout" != *SCREEN-LOCKED-MID-RUN* ]] && print 1 || print 0 ) "$lout"
  run_lock_sel "$ws/sess-locked-midrun.txt" "$sstart" -only-testing:CadenceUITests/CadenceUITests
  check "CONTROL (T-2041): a locked CadenceUITests run still gets the full SCREEN-LOCKED-MID-RUN banner" \
    $( [[ "$lout" == *SCREEN-LOCKED-MID-RUN* && "$lout" == *"NOT EVIDENCE"* && "$lout" != *"unit-only"* ]] && print 1 || print 0 ) "$lout"
  run_lock_sel "$ws/sess-locked-midrun.txt" "$sstart" -only-testing:CadenceTests -only-testing:CadenceUITests
  check "CONTROL: a selection reaching BOTH targets gets the banner (fails toward the warning)" \
    $( [[ "$lout" == *SCREEN-LOCKED-MID-RUN* ]] && print 1 || print 0 ) "$lout"
  run_lock_sel "$ws/sess-locked-midrun.txt" "$sstart" -scheme Cadence test
  check "CONTROL: no -only-testing: at all is the whole scheme, UI target included: the banner" \
    $( [[ "$lout" == *SCREEN-LOCKED-MID-RUN* ]] && print 1 || print 0 ) "$lout"
  run_lock_sel "$ws/sess-locked-midrun.txt" "$sstart" -scheme Cadence -skip-testing:CadenceUITests test
  check "...unless the UI target is -skip-testing:'d wholesale, which is unit-only again" \
    $( [[ "$lout" == *"SCREEN-LOCKED (unit-only"* && "$lout" != *SCREEN-LOCKED-MID-RUN* ]] && print 1 || print 0 ) "$lout"
  run_lock_sel "$ws/sess-old-lock.txt" "$sstart" -only-testing:CadenceTests
  check "CONTROL: a unit-only run with no lock in its window is SILENT, note included" \
    $( (( lrc == 0 )) && [[ -z "$lout" ]] && print 1 || print 0 ) "exit $lrc: $lout"

  say ""
  say " 8b. a test host macOS refused to relaunch is named, not filed under the lock note (T-1992)"
  # The refusal lines are verbatim from the 2026-10-02 heartbeat log (`a037faa3`); the test that
  # passed BEFORE the last start is there so the report must pick the LAST start, not the first.
  print -rl -- \
    "◇ Test run started." \
    "◇ Test halfTwoReadsAWriteThroughAScalarBindingAsAReport() started." \
    "✔ Test halfTwoReadsAWriteThroughAScalarBindingAsAReport() passed after 0.001 seconds." \
    "◇ Test everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule() started." \
    "2026-10-02 14:05:29.634 xcodebuild[80835:49836493]  IDELaunchReport: x:y:Launching CadenceTests Finished with error: Could not launch “CadenceTests”" \
    "Recovery Suggestion: LaunchServices has returned error -10699. Please check the system logs for the underlying cause of the error." \
    "Failure Reason: Launch prevented due to \"prevent launch\" assertion" \
    "◇ Test aTestNamedOnlyByTheRelaunchNoise() started." \
    "** TEST FAILED **" > "$ws/host-refused.log"
  print -rl -- \
    "Test Case '-[CadenceTests.SomeXCTests testSomething]' started." \
    "Failure Reason: Launch prevented due to \"prevent launch\" assertion" > "$ws/host-refused-xctest.log"
  print -rl -- \
    "◇ Test run started." \
    "◇ Test everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule() started." \
    "✘ Test everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule() recorded an issue" \
    "** TEST FAILED **" > "$ws/host-ordinary-red.log"
  # T-3071: the 2026-10-08 heartbeat shape -- a red test whose issue dump prints this script's
  # source, so every refusal phrase appears, but only indented or `↳`-prefixed inside the dump.
  print -rl -- \
    "◇ Test run started." \
    "◇ Test theGuardedRunnerAsksWhetherTheCheckoutIsStillHeadBeforeTakingTheTestHost() started." \
    "✘ Test theGuardedRunnerAsksWhetherTheCheckoutIsStillHeadBeforeTakingTheTestHost() recorded an issue at CadenceBuildInvocationHygieneTests.swift:247:27: Expectation failed: commands.range(of: \"a_gate_the_test_wanted\")" \
    "↳ commands.range(of: \"a_gate_the_test_wanted\") → nil" \
    "↳   commands → \"" \
    "" \
    "    HOST_LAUNCH_REFUSAL_PATTERN='LaunchServices has returned error -10699|OSStatus error -10699|Launch prevented due to \"prevent launch\" assertion'" \
    "        \"Recovery Suggestion: LaunchServices has returned error -10699. Please check the system logs for the underlying cause of the error.\" \\" \
    "        \"Failure Reason: Launch prevented due to \\\"prevent launch\\\" assertion\" \\" \
    "    \"" \
    "✘ Test theGuardedRunnerAsksWhetherTheCheckoutIsStillHeadBeforeTakingTheTestHost() failed after 0.047 seconds with 1 issue." \
    "↳ /// a doc comment quoting OSStatus error -10699 is the test's text too" \
    "◇ Test aLaterTestThatPassed() started." \
    "✔ Test aLaterTestThatPassed() passed after 0.001 seconds." \
    "✘ Test run with 2 tests in 1 suite failed after 0.1 seconds with 1 issue." \
    "** TEST FAILED **" > "$ws/host-quoted-in-issue.log"
  # ...and the genuine refusal arriving straight after such a dump: xcodebuild's column-0 lines
  # must close the dump and still be read.
  print -rl -- \
    "◇ Test run started." \
    "◇ Test aRedTestPrintingSource() started." \
    "✘ Test aRedTestPrintingSource() recorded an issue at X.swift:1:1: Expectation failed" \
    "↳ source → \"" \
    "    Failure Reason: Launch prevented due to \"prevent launch\" assertion" \
    "    \"" \
    "2026-10-02 14:05:29.634 xcodebuild[80835:49836493]  IDELaunchReport: x:y:Launching CadenceTests Finished with error: Could not launch “CadenceTests”" \
    "Recovery Suggestion: LaunchServices has returned error -10699. Please check the system logs for the underlying cause of the error." \
    "Failure Reason: Launch prevented due to \"prevent launch\" assertion" \
    "** TEST FAILED **" > "$ws/host-refused-after-issue.log"
  local hout hrc
  run_host() { hout=$(zsh "$here" check-host-launch "$@" 2>&1); hrc=$?; }
  run_host "$ws/host-refused.log" 65
  check "a log with the -10699 relaunch refusal says HOST-LAUNCH-REFUSED" \
    $( [[ "$hout" == *HOST-LAUNCH-REFUSED* ]] && print 1 || print 0 ) "exit $hrc: $hout"
  check "...naming the LAST test started before the refusal, not an earlier or later one" \
    $( [[ "$hout" == *"before the refusal: everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule()"* \
          && "$hout" != *halfTwoReads* && "$hout" != *aTestNamedOnlyByTheRelaunchNoise* ]] && print 1 || print 0 ) "$hout"
  check "...and says to re-run, and not to mark the test flaky" \
    $( [[ "$hout" == *"Re-run before treating the run as red"* && "$hout" == *"do not mark it flaky"* ]] && print 1 || print 0 ) "$hout"
  check "...and the report never gates: it exits 0" \
    $( (( hrc == 0 )) && print 1 || print 0 ) "exit $hrc"
  run_host "$ws/host-refused-xctest.log"
  check "an XCTest start line is named too, and a log handed over alone (exit unknown) is read" \
    $( [[ "$hout" == *HOST-LAUNCH-REFUSED* && "$hout" == *"'-[CadenceTests.SomeXCTests testSomething]'"* ]] && print 1 || print 0 ) "$hout"
  run_host "$ws/host-ordinary-red.log" 65
  check "CONTROL: an ordinary red WITHOUT the refusal is silent" \
    $( (( hrc == 0 )) && [[ "$hout" != *HOST-LAUNCH-REFUSED* ]] && print 1 || print 0 ) "exit $hrc: $hout"
  run_host "$ws/host-refused.log" 0
  check "CONTROL: the refusal under exit 0 (nothing red to explain) is silent" \
    $( (( hrc == 0 )) && [[ "$hout" != *HOST-LAUNCH-REFUSED* ]] && print 1 || print 0 ) "exit $hrc: $hout"
  run_host "$ws/host-quoted-in-issue.log" 65
  check "the refusal phrases printed only inside a red test's issue dump are NOT a refusal (T-3071)" \
    $( (( hrc == 0 )) && [[ "$hout" != *HOST-LAUNCH-REFUSED* ]] && print 1 || print 0 ) "exit $hrc: $hout"
  run_host "$ws/host-refused-after-issue.log" 65
  check "...but xcodebuild's own refusal straight after an issue dump still says HOST-LAUNCH-REFUSED" \
    $( [[ "$hout" == *HOST-LAUNCH-REFUSED* && "$hout" == *"before the refusal: aRedTestPrintingSource()"* ]] && print 1 || print 0 ) "exit $hrc: $hout"
  check "...at xcodebuild's line (8), not the quoted one inside the dump (5)" \
    $( [[ "$hout" == *"at line 8."* ]] && print 1 || print 0 ) "$hout"

  say ""
  say " 8c. a DerivedData poisoned by a touched entitlements file is named, not read as a bad suite (T-2046)"
  # The shape `rowcrush` measured four times on 2026-10-03: packaging dies on the entitlements
  # check, nothing compiles, nothing runs. The error carries xcodebuild's own override hint, so the
  # report is also checked for NOT echoing it.
  print -rl -- \
    "ProcessProductPackaging /x/Cadence.entitlements /x/Cadence.app.xcent (in target 'Cadence' from project 'Cadence')" \
    "    builtin-productPackagingUtility /x/Cadence.entitlements -entitlements -format xml -o /x/Cadence.app.xcent" \
    "error: Entitlements file \"Cadence.entitlements\" was modified during the build, which is not supported. You can disable this error by setting 'CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION' to 'YES', however this may cause the built product's code signature or provisioning profile to contain incorrect entitlements. (in target 'Cadence' from project 'Cadence')" \
    "** TEST FAILED **" > "$ws/ent-poisoned.log"
  print -rl -- \
    "error: Signing for \"Cadence\" requires a development team. (in target 'Cadence' from project 'Cadence')" \
    "** BUILD FAILED **" > "$ws/ent-other-red.log"
  local eout erc
  run_ent() { eout=$(zsh "$here" check-entitlements "$@" 2>&1); erc=$?; }
  run_ent "$ws/ent-poisoned.log" 65 "$ws/cadence-dd-entdiag"
  check "a log with 'Entitlements file ... was modified during the build' says ENTITLEMENTS-POISONED-DD" \
    $( [[ "$eout" == *"!! ENTITLEMENTS-POISONED-DD (T-2046): this private DerivedData is poisoned by a metadata-only touch of Cadence.entitlements"* ]] && print 1 || print 0 ) "exit $erc: $eout"
  check "...naming release-dd on THIS DerivedData, then a fresh build" \
    $( [[ "$eout" == *"./scripts/xcb.sh release-dd $ws/cadence-dd-entdiag\` then a fresh build"* ]] && print 1 || print 0 ) "$eout"
  check "...never offering the override the error text does, and never gating (exit 0)" \
    $( (( erc == 0 )) && [[ "$eout" != *ALLOW_ENTITLEMENTS_MODIFICATION* ]] && print 1 || print 0 ) "exit $erc: $eout"
  run_ent "$ws/ent-other-red.log" 65 "$ws/cadence-dd-entdiag"
  check "CONTROL: a red build WITHOUT the entitlements error is silent" \
    $( (( erc == 0 )) && [[ -z "$eout" ]] && print 1 || print 0 ) "exit $erc: $eout"
  run_ent "$ws/ent-poisoned.log" 0
  check "CONTROL: the line under exit 0 (nothing red to explain) is silent" \
    $( (( erc == 0 )) && [[ -z "$eout" ]] && print 1 || print 0 ) "exit $erc: $eout"
  # T-2046's batch-rule half, which the PARTIAL left open and which is settled as: YES, disposable
  # the moment this fires. It is enforced rather than described -- the report MARKS the tree and
  # the next preflight refuses it -- because the thing that went wrong was nobody remembering a
  # rule at the fourth identical red, and prose does not fix that. Both ends are induced here: the
  # mark, and a REAL `xcb.sh ... build` refused by it on the production path.
  mkdir -p "$ws/cadence-dd-live"
  run_ent "$ws/ent-poisoned.log" 65 "$ws/cadence-dd-live"
  check "a poisoned DerivedData that EXISTS is marked disposable, in the tree itself" \
    $( [[ -f "$ws/cadence-dd-live/.cadence-entitlements-poisoned" && "$eout" == *"MARKED DISPOSABLE (T-2046)"* ]] && print 1 || print 0 ) "$eout"
  check "...and the mark names when and from which log, so it is not a bare flag" \
    $( [[ "$(cat "$ws/cadence-dd-live/.cadence-entitlements-poisoned")" == poisoned\ <->-<->-<->\ * && "$(cat "$ws/cadence-dd-live/.cadence-entitlements-poisoned")" == *ent-poisoned.log ]] && print 1 || print 0 ) "$(cat "$ws/cadence-dd-live/.cadence-entitlements-poisoned")"
  mkdir -p "$ws/cadence-dd-clean"
  run_ent "$ws/ent-other-red.log" 65 "$ws/cadence-dd-clean"
  check "CONTROL: a red build WITHOUT the entitlements error marks nothing" \
    $( [[ ! -f "$ws/cadence-dd-clean/.cadence-entitlements-poisoned" ]] && print 1 || print 0 ) "$(ls -a "$ws/cadence-dd-clean")"
  run_ent "$ws/ent-poisoned.log" 0 "$ws/cadence-dd-clean"
  check "CONTROL: a GREEN run marks nothing, whatever an old log in it says" \
    $( [[ ! -f "$ws/cadence-dd-clean/.cadence-entitlements-poisoned" ]] && print 1 || print 0 ) "$(ls -a "$ws/cadence-dd-clean")"
  # The refusal, on the production path: a real invocation, with a real -derivedDataPath, refused
  # at preflight -- BEFORE the destination resolver, which this deliberately hands an impossible
  # destination to prove. Exit 10 here would mean the poisoned tree was admitted and the run merely
  # died of something else later.
  # NOT `local pout prc`: both names are already local to this function (section 9 declares them),
  # and in zsh a second bare `local x` PRINTS the parameter instead of redeclaring it -- T-1074,
  # and `CadenceGuardScriptSelftestTests.noZshScriptReachesABareLocalDeclarationTwice` refuses it.
  # The stray `pout=$'...'` it emitted went into whatever the run was capturing. Own names instead.
  local entpout entprc
  entpout=$(zsh "$here" selftest-ent build -scheme Cadence -destination 'platform=iOS Simulator,name=NoSuchDeviceXYZ' \
    -derivedDataPath "$ws/cadence-dd-live" 2>&1); entprc=$?
  check "a marked DerivedData is REFUSED at preflight (exit $ENTITLEMENTS_POISONED_EXIT), before anything is paid for" \
    $( (( entprc == ENTITLEMENTS_POISONED_EXIT )) && [[ "$entpout" == *"REFUSING -- ENTITLEMENTS-POISONED-DD"* && "$entpout" == *"release-dd $ws/cadence-dd-live"* ]] && print 1 || print 0 ) "exit $entprc: $entpout"
  check "...and it never offers the override xcodebuild's own error text offers" \
    $( [[ "$entpout" == *"Do NOT reach for CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION"* ]] && print 1 || print 0 ) "$entpout"
  entpout=$(zsh "$here" selftest-ent build -scheme Cadence -destination 'platform=iOS Simulator,name=NoSuchDeviceXYZ' \
    -derivedDataPath "$ws/cadence-dd-clean" 2>&1); entprc=$?
  check "CONTROL: an UNMARKED DerivedData is admitted and dies of its own fault (exit $SIMULATOR_GATE_EXIT), not of this one" \
    $( (( entprc == SIMULATOR_GATE_EXIT )) && [[ "$entpout" != *ENTITLEMENTS-POISONED-DD* ]] && print 1 || print 0 ) "exit $entprc: $entpout"
  # The mark and the poisoning are cleared by THE SAME ACT, which is why the sentinel lives inside
  # the tree: `release-dd` deletes the directory, and nothing is left behind to refuse a fresh one.
  zsh "$here" release-dd "$ws/cadence-dd-live" >/dev/null 2>&1
  check "release-dd clears the mark because it deletes the tree the mark lives in" \
    $( [[ ! -e "$ws/cadence-dd-live" ]] && print 1 || print 0 ) "$(ls -d "$ws/cadence-dd-live" 2>&1)"

  say ""
  say " 8d. a run the Mac slept through is named, not read as a bare exit 143 (T-2048)"
  # Fixture lines in `pmset -g log` format, stamped from epochs through `date -r` so the window is
  # right in whatever timezone the selftest runs. COUNTS only, never durations. One fixture per
  # bound, so ignoring either the start or the end bound turns a specific check red.
  local -i s0=1790000000 s1=$(( 1790000000 + 3600 ))
  pm_line() {  # $1 = epoch, $2 = category, $3 = message
    print -r -- "$(date -r "$1" '+%Y-%m-%d %H:%M:%S %z') $2               	$3"
  }
  local sleepmsg="Entering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:42%) 341 secs"
  {
    print -r -- "PM ASL data store: /var/log/powermanagement"
    pm_line $(( s0 - 600 )) Sleep "$sleepmsg"
    pm_line $(( s0 + 600 )) Sleep "$sleepmsg"
    pm_line $(( s0 + 700 )) DarkWake "DarkWake from Deep Idle [CDNP] : due to SMC.OutboxNotEmpty/Maintenance Using Batt (Charge:42%) 58 secs"
    pm_line $(( s0 + 1800 )) Sleep "$sleepmsg"
    pm_line $(( s0 + 3000 )) Sleep "$sleepmsg"
    pm_line $(( s1 + 600 )) Sleep "$sleepmsg"
  } > "$ws/pm-three-inside.log"
  { pm_line $(( s0 - 60 )) Sleep "$sleepmsg"; pm_line $(( s0 + 60 )) Wake "Wake from Deep Idle [CDNP] : due to UserActivity" } > "$ws/pm-before.log"
  { pm_line $(( s0 + 60 )) Wake "Wake from Deep Idle [CDNP] : due to UserActivity"; pm_line $(( s1 + 60 )) Sleep "$sleepmsg" } > "$ws/pm-after.log"
  { pm_line $(( s0 + 60 )) Assertions "PID 1(launchd) Created PreventUserIdleSystemSleep \"x\" 00:00:00"; pm_line $(( s0 + 120 )) Wake "Wake from Deep Idle [CDNP] : due to UserActivity" } > "$ws/pm-none.log"
  local slout slrc
  run_sleep() { local f=$1; shift; slout=$(CADENCE_PMSET_LOG_FIXTURE="$f" zsh "$here" check-sleep "$@" 2>&1); slrc=$?; }
  run_sleep "$ws/pm-three-inside.log" $s0 $s1 143
  check "three Sleep entries inside the window (and two outside) say SYSTEM-SLEPT with a count of 3" \
    $( [[ "$slout" == *"!! SYSTEM-SLEPT (T-2048): \`pmset -g log\` shows 3 'Entering Sleep state' entries between"* ]] && print 1 || print 0 ) "exit $slrc: $slout"
  check "...and never gates (exit 0)" $( (( slrc == 0 )) && print 1 || print 0 ) "exit $slrc: $slout"
  run_sleep "$ws/pm-before.log" $s0 $s1 143
  check "CONTROL: a Sleep entry only BEFORE the run's start is silent" \
    $( (( slrc == 0 )) && [[ -z "$slout" ]] && print 1 || print 0 ) "exit $slrc: $slout"
  run_sleep "$ws/pm-after.log" $s0 $s1 143
  check "CONTROL: a Sleep entry only AFTER the run's end is silent" \
    $( (( slrc == 0 )) && [[ -z "$slout" ]] && print 1 || print 0 ) "exit $slrc: $slout"
  run_sleep "$ws/pm-none.log" $s0 $s1 143
  check "CONTROL: zero Sleep entries (wake and assertion lines only) is silent" \
    $( (( slrc == 0 )) && [[ -z "$slout" ]] && print 1 || print 0 ) "exit $slrc: $slout"
  run_sleep "$ws/pm-three-inside.log" $s0 $s1 0
  check "CONTROL: Sleep entries under exit 0 (nothing red to explain) are silent" \
    $( (( slrc == 0 )) && [[ -z "$slout" ]] && print 1 || print 0 ) "exit $slrc: $slout"

  say ""
  say " 8e. an unanswered \"Enable UI Automation\" prompt is named, and the probe cannot be dragged to zero by its own noise (T-2070)"
  # The live condition cannot be induced (it needs this Mac's authentication stack to stop
  # answering), so these drive `check-automation` through CADENCE_AUTOMATION_LOG_FIXTURE in the
  # format `log show --style compact` prints. THE THIRD AND FOURTH FIXTURES ARE THE POINT: the
  # probe T-2070 shipped counted /usr/bin/log's OWN invocation records, whose argv quotes the very
  # phrases being counted -- and because a probe session runs both predicates, both counters rose
  # together and `requests - granted` was dragged to zero BY PROBING. Measured on this Mac
  # 2026-10-07: 10 requests unscoped, 1 scoped. A probe that reads HEALTHY over a standing prompt
  # is worse than no probe, so the host-noise fixture is a PINNED regression, not an illustration.
  local tm="2026-10-07 16:47:08.095 Df testmanagerd[88831:488d048] [com.apple.dt.automationmode:Default]"
  local xc="2026-10-07 17:13:45.851 Df testmanagerd[88831:488d048] [com.apple.dt.xctest:Default]"
  local probe_noise='2026-10-07 17:20:00.000 Df log[91234:4900001] [com.apple.log:Default] /usr/bin/log show --last 6h --predicate process == "testmanagerd" AND eventMessage CONTAINS "Writer daemon requires authentication" / "Finished enabling Automation Mode"'
  print -rl -- "$tm Writer daemon requires authentication to enable automation mode." > "$ws/autom-outstanding.log"
  print -rl -- "$tm Writer daemon requires authentication to enable automation mode." \
               "$xc Finished enabling Automation Mode" > "$ws/autom-answered.log"
  print -rl -- "$probe_noise" "$probe_noise" "$probe_noise" > "$ws/autom-noise-only.log"
  print -rl -- "$tm Writer daemon requires authentication to enable automation mode." \
               "$probe_noise" "$probe_noise" "$probe_noise" "$probe_noise" > "$ws/autom-outstanding-plus-noise.log"
  # The SECOND reading, and the checks below are a 2x2 over the two of them. An unmatched request
  # is not by itself a standing prompt: an UNATTENDED UI run raises the owner's prompt, times out
  # after ~70s and leaves exactly this line behind, over a host that then runs unit suites fine.
  # A count-only refusal would have refused every macOS test run on this Mac for the rest of the
  # window after any such run -- siblings' unit runs included, which is T-2067's own harm.
  print -rl -- \
    "2026-10-07 17:02:01.113 Df xctest[41122:2f1] Received new test session connection" \
    "2026-10-07 17:02:01.114 Df xctest[41122:2f1] resuming connection" > "$ws/autom-sess-hanging.txt"
  print -rl -- \
    "2026-10-07 17:02:01.113 Df xctest[41122:2f1] Received new test session connection" \
    "2026-10-07 17:02:01.116 Df xctest[41122:2f1] requested serialized transport" > "$ws/autom-sess-ok.txt"
  local aout2 arc2
  run_autom() {  # $1 = automation fixture, $2 = session fixture (default: a healthy host)
    aout2=$(CADENCE_AUTOMATION_LOG_FIXTURE="$1" \
      CADENCE_XCTEST_SESSION_FIXTURE="${2:-$ws/autom-sess-ok.txt}" zsh "$here" check-automation 2>&1); arc2=$?
  }
  run_autom "$ws/autom-outstanding.log" "$ws/autom-sess-hanging.txt"
  check "a request with no grant AND a hanging session says AUTOMATION-PROMPT-OUTSTANDING and exits $AUTOMATION_PROMPT_EXIT" \
    $( (( arc2 == AUTOMATION_PROMPT_EXIT )) && [[ "$aout2" == *"AUTOMATION-PROMPT-OUTSTANDING (T-2070)"* && "$aout2" == *"requests=1 granted=0 outstanding=1"* ]] && print 1 || print 0 ) "exit $arc2: $aout2"
  check "...and it says WHY it refuses rather than notes: a session connected and never got transport" \
    $( [[ "$aout2" == *"hanging test sessions: 1"* && "$aout2" == *"the SECOND reading"* ]] && print 1 || print 0 ) "$aout2"
  run_autom "$ws/autom-outstanding.log" "$ws/autom-sess-ok.txt"
  check "CONTROL: the SAME unmatched request over a host with NO hanging session only NOTES it (exit 0)" \
    $( (( arc2 == 0 )) && [[ "$aout2" == *"AUTOMATION-PROMPT-UNMATCHED (T-2070)"* && "$aout2" != *REFUSING* ]] && print 1 || print 0 ) "exit $arc2: $aout2"
  check "...and the note names the unattended-UI-run cause, so it is not read as a mystery" \
    $( [[ "$aout2" == *"UNATTENDED UI run"* && "$aout2" == *"PER-SESSION"* ]] && print 1 || print 0 ) "$aout2"
  run_autom "$ws/autom-outstanding.log" "$ws/autom-sess-hanging.txt"
  check "...and says only the OWNER can clear it, never a daemon kill or DevToolsSecurity" \
    $( [[ "$aout2" == *"ONLY THE OWNER CAN CLEAR IT"* && "$aout2" == *"Do NOT run"*"DevToolsSecurity"* && "$aout2" == *"PER-SESSION"* ]] && print 1 || print 0 ) "$aout2"
  run_autom "$ws/autom-answered.log"
  check "CONTROL: a request that WAS granted reads HEALTHY and exits 0" \
    $( (( arc2 == 0 )) && [[ "$aout2" == *"outstanding=0"* && "$aout2" == *HEALTHY* && "$aout2" != *REFUSING* ]] && print 1 || print 0 ) "exit $arc2: $aout2"
  run_autom "$ws/autom-noise-only.log"
  check "PIN: /usr/bin/log's own invocation records are not counted at all (requests=0)" \
    $( (( arc2 == 0 )) && [[ "$aout2" == *"requests=0 granted=0 outstanding=0"* ]] && print 1 || print 0 ) "exit $arc2: $aout2"
  run_autom "$ws/autom-outstanding-plus-noise.log" "$ws/autom-sess-hanging.txt"
  check "PIN: one REAL standing prompt still reads outstanding=1 under four probe-noise lines" \
    $( (( arc2 == AUTOMATION_PROMPT_EXIT )) && [[ "$aout2" == *"requests=1 granted=0 outstanding=1"* ]] && print 1 || print 0 ) "exit $arc2: $aout2"
  # ANCHORED at column 1, and that is not decoration: unanchored, this check's OWN source line
  # quotes the patterns it searches for, so it matched ITSELF and the pin failed over its own
  # text. The assignment is the only line that starts the name in column 1.
  check "PIN: the live predicate is scoped to the emitting daemons and off the \`log\` process" \
    $( grep -q '^AUTOMATION_PROMPT_PREDICATE=.*process == "testmanagerd"' "$here" && grep -q '^AUTOMATION_PROMPT_PREDICATE=.*process != "log"' "$here" && ! grep -q '^AUTOMATION_PROMPT_PREDICATE=.*eventMessage CONTAINS' "$here" && print 1 || print 0 ) "$(grep -m1 '^AUTOMATION_PROMPT_PREDICATE=' "$here")"

  say ""
  say " 9. the per-requested-suite guard, and which of its two inputs it trusts (T-667 / T-1326)"
  # ONE LOG, TWO ARGUMENT SETS, TWO VERDICTS. That is the whole of T-1326: the log below holds the
  # literal string `-only-testing:CadenceTests/NotASuite` -- as a failing test's own prose, with the
  # trailing backtick the real measurement had -- and whether that is a finding depends entirely on
  # whether the RUN asked for that suite. Reading the log for both answers made the sentence into
  # the request, which is a false RED on a green run and an `XCODEBUILD_EXIT=6` nobody caused.
  print -rl -- \
    "Suite AlphaTests started." \
    "✔ Test somethingReal() passed after 0.001 seconds." \
    "✘ Test noTestInTheTargetIsDeclaredOutsideEverySuite() recorded an issue: a suite-less test is" \
    "  invisible to \`-only-testing:CadenceTests/NotASuite\`, so nothing scopes to it." \
    "** TEST FAILED **" \
    > "$ws/phantom.log"
  # A label that is not the type name, for the half of this guard that predates T-1326: once a suite
  # carries a display name the log speaks only in that vocabulary (T-667).
  print -rl -- $'AlphaTests\tAlphaTests' \
               $'AlphaHelperTests\tAlpha helpers' \
               $'SoloTests\tSoloTests' > "$ws/labels.tsv"
  : > "$ws/empty.log"
  local pout prc
  run_suites() {
    pout=$(CADENCE_SUITE_LABELS="$ws/labels.tsv" zsh "$here" check-suites-started "$@" 2>&1); prc=$?
  }

  run_suites "$ws/phantom.log" -scheme Cadence -destination platform=macOS -only-testing:CadenceTests test
  check "a log that merely QUOTES the flag invents no suite (T-1326)" \
    $( (( prc == 0 )) && [[ "$pout" != *T-667* && "$pout" != *NotASuite* ]] && print 1 || print 0 ) "exit $prc: $pout"
  # The same log, and now the run really did ask for it. Without this the fix above would be
  # indistinguishable from deleting the guard, which is the failure mode this section exists for.
  run_suites "$ws/phantom.log" -only-testing:CadenceTests/NotASuite test
  check "…but a suite the ARGUMENTS really requested and the log never started still exits $SUITE_GATE_EXIT" \
    $( (( prc == SUITE_GATE_EXIT )) && [[ "$pout" == *T-667*NotASuite* ]] && print 1 || print 0 ) "exit $prc: $pout"
  run_suites "$ws/phantom.log" -only-testing:CadenceTests/AlphaTests test
  check "a requested suite the log DID start is silent" \
    $( (( prc == 0 )) && [[ "$pout" != *T-667* ]] && print 1 || print 0 ) "exit $prc: $pout"
  # T-1326's second phantom shape, and it was live: the log reading kept the `/testName` tail and
  # then looked for a suite by that whole name, so scoping to ONE test failed its own run.
  run_suites "$ws/phantom.log" -only-testing:CadenceTests/AlphaTests/somethingReal test
  check "scoping to ONE test of a suite that started is silent" \
    $( (( prc == 0 )) && [[ "$pout" != *T-667* ]] && print 1 || print 0 ) "exit $prc: $pout"
  # `raw` needs no special case: it is every arg the caller passed, so the same reading covers it.
  run_suites "$ws/phantom.log" test-without-building -only-testing:CadenceTests/NotASuite
  check "a raw test-without-building run is read the same way" \
    $( (( prc == SUITE_GATE_EXIT )) && [[ "$pout" == *NotASuite* ]] && print 1 || print 0 ) "exit $prc: $pout"
  run_suites "$ws/phantom.log" -only-testing CadenceTests/NotASuite test
  check "and so is the separate-argument spelling of the flag" \
    $( (( prc == SUITE_GATE_EXIT )) && [[ "$pout" == *NotASuite* ]] && print 1 || print 0 ) "exit $prc: $pout"

  # The label path, both directions, because a guard that looked for the type name would pass every
  # check above: `AlphaHelperTests` prints as "Alpha helpers" and nothing else.
  print -rl -- "Suite \"Alpha helpers\" started." \
               "✔ Test aHelper() passed after 0.001 seconds." > "$ws/labelled.log"
  run_suites "$ws/labelled.log" -only-testing:CadenceTests/AlphaHelperTests test
  check "a display-named suite is looked for by its LABEL, not its type name" \
    $( (( prc == 0 )) && [[ "$pout" != *T-667* ]] && print 1 || print 0 ) "exit $prc: $pout"
  print -rl -- "Suite AlphaHelperTests started." \
               "✔ Test aHelper() passed after 0.001 seconds." > "$ws/typename.log"
  run_suites "$ws/typename.log" -only-testing:CadenceTests/AlphaHelperTests test
  check "…and the type name alone does NOT satisfy it (the control for the line above)" \
    $( (( prc == SUITE_GATE_EXIT )) && print 1 || print 0 ) "exit $prc: $pout"

  # The two carve-outs. A run with no per-suite scoping has nothing to diff, and a wholly empty run
  # is the zero-test guard's finding -- naming it here as well would bury both.
  run_suites "$ws/phantom.log" -scheme Cadence -destination platform=macOS build
  check "a run that scopes no suite at all is silent" \
    $( (( prc == 0 )) && [[ "$pout" != *T-667* ]] && print 1 || print 0 ) "exit $prc: $pout"
  run_suites "$ws/empty.log" -only-testing:CadenceTests/NotASuite test
  check "a run with zero test result lines defers to the zero-test guard" \
    $( (( prc == 0 )) && [[ "$pout" != *T-667* ]] && print 1 || print 0 ) "exit $prc: $pout"
  check "and the refusals above carry no stray zsh assignment line (T-1074)" \
    $( print -r -- "$pout" | grep -qE '^[a-z_][a-z_0-9]*=' && print 0 || print 1 ) "$pout"

  say ""
  say " 9d. a runner that never started is named, not blamed on the filter (T-2021)"
  # The failure line is verbatim from the 2026-10-01 xcresult T-1953 quotes. The CONTROLS carry the
  # weight: a log WITHOUT the sentence must still get the T-552 suite-name advice, and so must a log
  # that has it under an exit of 0 -- the ticket's rule is all three halves, not the string alone.
  print -rl -- \
    "Command line invocation:" \
    "    xcodebuild test -scheme Cadence -destination platform=macOS -only-testing:CadenceUITests" \
    "CadenceUITests-Runner (45302) encountered an error (The test runner failed to initialize for UI testing. (Underlying Error: Timed out while enabling automation mode.))" \
    "** TEST FAILED **" > "$ws/automation.log"
  print -rl -- \
    "Command line invocation:" \
    "    xcodebuild test -scheme Cadence -destination platform=macOS -only-testing:CadenceTests/NoSuchSuite" \
    "** TEST FAILED **" > "$ws/no-automation.log"
  local aout arc
  run_tlog() { aout=$(zsh "$here" check-test-log "$@" 2>&1); arc=$?; }
  run_tlog "$ws/automation.log" 65
  check "exit 65, 0 result lines and the automation-mode timeout: an ENVIRONMENTAL refusal" \
    $( (( arc == 4 )) && [[ "$aout" == *ENVIRONMENTAL* && "$aout" == *"DevToolsSecurity -status"* ]] && print 1 || print 0 ) "exit $arc: $aout"
  check "...and it does NOT hand out the T-552 suite-name advice" \
    $( [[ "$aout" != *"takes a SUITE name"* && "$aout" != *"called that a success"* ]] && print 1 || print 0 ) "$aout"
  # T-2049: developer mode reading enabled does NOT exhaust this symptom. The refusal must name the
  # second cause too, or the reader runs `DevToolsSecurity -status`, sees "enabled", and is stuck
  # with no next check -- which is what happened to agent `escapefix` on 2026-10-03.
  check "...and it names the second cause as well as developer mode (T-2049)" \
    $( [[ "$aout" == *"automationmode-writer"* && "$aout" == *"Writer daemon requires authentication"* ]] && print 1 || print 0 ) "$aout"
  # T-2070, and it is a CORRECTION of this refusal rather than an addition to it: the check this
  # block used to print was `log show --last 10m --predicate 'eventMessage CONTAINS "automation
  # mode"'`, which counts /usr/bin/log's OWN invocation records -- the probe's argv quotes the
  # phrase -- and therefore reads healthy over a standing prompt. docs/AGENTS_REFERENCE.md had
  # already measured the defect and recorded that this line still had it.
  check "...and the check it names is \`check-automation\`, not a bare log show that counts its own probes (T-2070)" \
    $( [[ "$aout" == *"./scripts/xcb.sh check-automation"* && "$aout" != *"Check:  log show"* ]] && print 1 || print 0 ) "$aout"
  # ANCHORED at `say "` in column 1-or-indent for the reason section 8e's predicate pin is anchored:
  # unanchored, this check's own source line is the thing it would find.
  check "PIN: no refusal in this script hands the reader a bare \`log show\` as THE check (T-2070)" \
    $( ! grep -qE '^ *say ".*Check: *log show' "$here" && print 1 || print 0 ) "$(grep -nE '^ *say ".*Check: *log show' "$here" | head -1)"
  # T-2049's SECOND sentence. The fixture line is verbatim from
  # `cadence-xcb-escapefix.20261003-211849-1974.log`, whose run compiled 1105 Swift files, linked
  # and code-signed -- so the counters were non-vacuous and ONLY the result lines were zero. The
  # controls carry the weight again: this must NOT be answered with the suite-name advice, and it
  # must NOT be answered with the developer-mode advice, which is about a different sentence.
  print -rl -- \
    "Command line invocation:" \
    "    xcodebuild test -scheme Cadence -destination platform=macOS -only-testing:CadenceTests/CadenceGuardScriptSelftestTests" \
    "Testing failed:" \
    "	Cadence (97324) encountered an error (The test runner hung before establishing connection.)" \
    "** TEST FAILED **" > "$ws/runner-hung.log"
  run_tlog "$ws/runner-hung.log" 65
  check "a test host that never connected is an ENVIRONMENTAL refusal too (T-2049)" \
    $( (( arc == 4 )) && [[ "$aout" == *ENVIRONMENTAL* && "$aout" == *"TEST HOST never connected"* ]] && print 1 || print 0 ) "exit $arc: $aout"
  check "...and it does NOT hand out the T-552 suite-name advice either" \
    $( [[ "$aout" != *"takes a SUITE name"* && "$aout" != *"called that a success"* ]] && print 1 || print 0 ) "$aout"
  check "...and it does NOT send the reader to DevToolsSecurity, which is a different sentence" \
    $( [[ "$aout" != *DevToolsSecurity* ]] && print 1 || print 0 ) "$aout"
  check "...and it says this hits UNIT runs too, so it is not read as UI-only" \
    $( [[ "$aout" == *"UNIT runs as well as UI runs"* ]] && print 1 || print 0 ) "$aout"
  check "...and it asks whether an automation prompt is standing, because that wedges UNIT runs (T-2070)" \
    $( [[ "$aout" == *"./scripts/xcb.sh check-automation"* ]] && print 1 || print 0 ) "$aout"
  run_tlog "$ws/runner-hung.log" 0
  check "CONTROL: the hung-runner sentence under exit 0 is not the environmental refusal" \
    $( (( arc == 4 )) && [[ "$aout" == *"takes a SUITE name"* && "$aout" != *"TEST HOST never connected"* ]] && print 1 || print 0 ) "exit $arc: $aout"
  run_tlog "$ws/automation.log"
  check "a log handed over alone (exit unknown) is read the same way" \
    $( (( arc == 4 )) && [[ "$aout" == *"DevToolsSecurity -status"* ]] && print 1 || print 0 ) "exit $arc: $aout"
  run_tlog "$ws/no-automation.log" 65
  check "CONTROL: an empty run WITHOUT the sentence still gets the T-552 advice" \
    $( (( arc == 4 )) && [[ "$aout" == *"takes a SUITE name"* && "$aout" != *DevToolsSecurity* ]] && print 1 || print 0 ) "exit $arc: $aout"
  run_tlog "$ws/automation.log" 0
  check "CONTROL: the sentence under exit 0 is not the environmental refusal" \
    $( (( arc == 4 )) && [[ "$aout" == *"takes a SUITE name"* && "$aout" != *DevToolsSecurity* ]] && print 1 || print 0 ) "exit $arc: $aout"

  say ""
  say " 9c. the counters read the BUILD, not the test output (T-1971)"
  # EVERY LINE OF THESE FIXTURES IS VERBATIM from the log that produced the defect
  # (`cadence-xcb-landgate-unit` 20261001-192525), with the absolute path shortened. That matters
  # here more than usual: the lines that were miscounted are THIS SCRIPT'S OWN comments and
  # fixtures, echoed by a failing test, so a fixture written from the ticket's description would
  # have been a sentence about the bug rather than the bug.
  #
  # THE CONTROL IS THE SAFETY ARGUMENT, not a formality. The hazard in a boundary is that it stops
  # counting too early and a warning gate goes quiet -- T-1516 is what that costs. So the same
  # offending line is asserted to be COUNTED when nothing says the tests started, and a real
  # build-phase warning is asserted to still gate with a test phase present.
  print -rl -- \
    "SwiftCompile normal arm64 /repo/CadenceTests/Probe.swift (in target 'CadenceTests' from project 'Cadence')" \
    "Test Suite 'Selected tests' started at 2026-10-01 23:39:17.901." \
    "◇ Test run started." \
    "✘ Test theGuardStillFires() recorded an issue at CadenceGuardScriptSelftestTests.swift:1249:9: Expectation failed" \
    "    #   /repo/CadenceTests/Probe.swift:5:13: warning: 'zzDeprecated()' is deprecated: probe" \
    "    #   macro expansion #expect:1:39: warning: main actor-isolated conformance of ..." \
    > "$ws/testecho.log"
  # The same two lines with no test phase at all: nothing says the build ended, so they are build
  # output as far as anything here can tell, and they must still be counted.
  print -rl -- \
    "SwiftCompile normal arm64 /repo/CadenceTests/Probe.swift (in target 'CadenceTests' from project 'Cadence')" \
    "    #   /repo/CadenceTests/Probe.swift:5:13: warning: 'zzDeprecated()' is deprecated: probe" \
    "    #   macro expansion #expect:1:39: warning: main actor-isolated conformance of ..." \
    > "$ws/nophase.log"
  # A REAL warning, raised in the build, in a log that also runs tests. This is the line that must
  # never be lost: it is the one the gate exists for.
  print -rl -- \
    "SwiftCompile normal arm64 /repo/CadenceTests/Probe.swift (in target 'CadenceTests' from project 'Cadence')" \
    "/repo/CadenceTests/Probe.swift:15:13: warning: initialization of immutable value 'p' was never used; consider replacing with assignment to '_'" \
    "Test Suite 'Selected tests' started at 2026-10-01 23:39:17.901." \
    "    #   macro expansion #expect:1:39: warning: main actor-isolated conformance of ..." \
    > "$ws/realplustest.log"

  run_counters "$ws/testecho.log"
  check "a failing test echoing a warning-shaped line is NOT counted as a warning" \
    $( [[ "$dout" == *"warnings:        0"* ]] && print 1 || print 0 ) "exit $drc: $dout"
  check "...and the gate does not fire on it" $( (( drc == 0 )) && print 1 || print 0 ) "exit $drc"
  check "...and it is not laundered into the tool-notice bucket either" \
    $( [[ "$dout" != *"tool notices:"* ]] && print 1 || print 0 ) "$dout"
  check "...but it is REPORTED, with the line to grep from (a guard that silently drops input)" \
    $( [[ "$dout" == *"note (T-1971): 2 line(s) AFTER testing started"* && "$dout" == *"tail -n +2 <log>"* ]] && print 1 || print 0 ) "$dout"

  run_counters "$ws/nophase.log"
  check "CONTROL: with NO test phase in the log, those same lines ARE counted" \
    $( [[ "$dout" == *"warnings:        2"* ]] && print 1 || print 0 ) "exit $drc: $dout"
  check "...and still gate, so the fallback is the OLD behaviour and not a quiet exemption" \
    $( (( drc == WARNING_GATE_EXIT )) && print 1 || print 0 ) "exit $drc"
  check "...and the note is silent when there is no test phase to have dropped anything" \
    $( [[ "$dout" != *"T-1971"* ]] && print 1 || print 0 ) "$dout"

  run_counters "$ws/realplustest.log"
  check "CONTROL: a REAL build warning in a log that also runs tests is still counted" \
    $( [[ "$dout" == *"warnings:        1"* ]] && print 1 || print 0 ) "exit $drc: $dout"
  check "...and still gates (exit 9), which is the whole point of not moving the boundary early" \
    $( (( drc == WARNING_GATE_EXIT )) && print 1 || print 0 ) "exit $drc"
  check "...and the echoed line beside it is reported separately, not added to it" \
    $( [[ "$dout" == *"note (T-1971): 1 line(s)"* ]] && print 1 || print 0 ) "$dout"

  say ""
  say " 10. does this selection launch an app (T-1933)"
  # TWO FIXTURE SUITES, AND THE SECOND IS THE WHOLE CHECK. One screen-free suite on its own passes
  # with the reading deleted and `return 1` left in its place -- the exemption would simply be
  # unconditional, and every check below it that asserts SCREEN-FREE would still be green. So the
  # app-launching sibling sits in the same fixture target and the two answers are asserted to
  # DIFFER. Everything else here is a fail-closed case: the exemption is the finding, so it is the
  # exemption that has to be proven, and anything unreadable has to come back LAUNCHES-AN-APP.
  mkdir -p "$ws/uitests"
  print -rl -- 'import XCTest' '@MainActor' 'final class ScreenFreeFixtureTests: XCTestCase {' \
               '    func testArithmeticOverABitmap() { XCTAssertEqual(1, 1) }' '}' \
               > "$ws/uitests/ScreenFreeFixtureTests.swift"
  print -rl -- 'import XCTest' 'final class LaunchingFixtureTests: XCTestCase {' \
               '    func testLaunches() { let app = XCUIApplication(); app.launch() }' '}' \
               > "$ws/uitests/LaunchingFixtureTests.swift"
  local uiout uisrc
  run_sel() { uiout=$(CADENCE_UI_TEST_SOURCE_DIR="$ws/uitests" zsh "$here" check-ui-selection "$@" 2>&1); rc=$?; }

  run_sel CadenceUITests/ScreenFreeFixtureTests
  check "a suite whose source never names XCUIApplication is SCREEN-FREE" \
    $( [[ $rc == 1 && "$uiout" == *SCREEN-FREE* ]] && print 1 || print 0 ) "exit $rc: $uiout"
  local screenfree_out="$uiout"
  run_sel CadenceUITests/LaunchingFixtureTests
  check "CONTROL: its sibling in the same target LAUNCHES-AN-APP" \
    $( [[ $rc == 0 && "$uiout" == *LAUNCHES-AN-APP* ]] && print 1 || print 0 ) "exit $rc: $uiout"
  check "...and the two selections do not get the same answer" \
    $( [[ "$uiout" != "$screenfree_out" ]] && print 1 || print 0 ) "$uiout"

  run_sel CadenceUITests/ScreenFreeFixtureTests/testArithmeticOverABitmap
  check "scoping to ONE test of a screen-free suite is screen-free too" \
    $( [[ $rc == 1 && "$uiout" == *SCREEN-FREE* ]] && print 1 || print 0 ) "exit $rc: $uiout"
  run_sel CadenceUITests
  check "FAIL-CLOSED: the whole UI target launches an app" \
    $( [[ $rc == 0 ]] && print 1 || print 0 ) "exit $rc: $uiout"
  run_sel CadenceUITests/NoSuchSuiteInTheFixture
  check "FAIL-CLOSED: a suite whose declaration cannot be found launches an app" \
    $( [[ $rc == 0 ]] && print 1 || print 0 ) "exit $rc: $uiout"
  run_sel
  check "FAIL-CLOSED: no -only-testing: at all launches an app (the whole scheme runs)" \
    $( [[ $rc == 0 ]] && print 1 || print 0 ) "exit $rc: $uiout"
  # CadenceTests is NOT exempt and must never become so: it hosts IN the app, which is the one
  # app-group container T-236 is about. Nothing about this ticket touches the unit target's lease.
  run_sel CadenceTests/CadenceOverdrawVerdictTests
  check "FAIL-CLOSED: the unit target hosts in the app, so it launches one" \
    $( [[ $rc == 0 ]] && print 1 || print 0 ) "exit $rc: $uiout"
  run_sel CadenceUITests/ScreenFreeFixtureTests CadenceTests/SomeUnitSuite
  check "FAIL-CLOSED: one launching member makes the whole selection launching" \
    $( [[ $rc == 0 ]] && print 1 || print 0 ) "exit $rc: $uiout"

  # The fixture above is a claim about the reading; this is the claim about this repository, and it
  # is section 5's argument again -- without it a fixture that had drifted from the real target
  # would pass in silence while the live suite the ticket is about stayed refused.
  run_sel() { uiout=$(zsh "$here" check-ui-selection "$@" 2>&1); rc=$?; }
  run_sel CadenceUITests/CadenceOverdrawVerdictTests
  check "LIVE: CadenceOverdrawVerdictTests is screen-free (T-1933's whole subject)" \
    $( [[ $rc == 1 && "$uiout" == *SCREEN-FREE* ]] && print 1 || print 0 ) "exit $rc: $uiout"
  run_sel CadenceUITests/CadenceTodayCompositionUITests
  check "LIVE CONTROL: a real suite that does launch an app is not exempted" \
    $( [[ $rc == 0 && "$uiout" == *LAUNCHES-AN-APP* ]] && print 1 || print 0 ) "exit $rc: $uiout"

  # ONE CONSUMER, DELIBERATELY, AND THAT IS T-1933'S OWN PROPOSAL REFUTED. The ticket said the
  # locked-screen refusal and the test-host lease share an input -- "does this selection launch an
  # app" -- and should share an answer. Half of that is right: the LEASE is about T-236's app-group
  # container, and a selection that starts no host needs none, measured at 800 seconds of queueing
  # saved. The other half is wrong, and only a locked Mac could say so: NO suite in CadenceUITests
  # runs while the screen is locked, because the UI-test RUNNER cannot initialize, so the screen
  # question does not depend on the selection at all. The count below is 1, and a future edit that
  # wires the selection back into the locked-screen guard -- which reads as the obvious fix, because
  # it was -- has to come past this check and the one under it.
  uisrc=$(grep -c 'selection_launches_an_app "\${only_testing\[@\]}"' "$here")
  check "only the test-host lease consults the selection, not the locked-screen guard (T-1933)" \
    $( (( uisrc == 1 )) && print 1 || print 0 ) "found $uisrc call site(s), want 1"
  # ...and the refusal states the measured mechanism, because the mechanism is why the per-suite
  # exemption looked correct for two days: T-563 blamed `app.launch()`, which only a suite that
  # launches something would reach.
  check "...and the locked-screen refusal names the RUNNER, not app.launch()" \
    $( [[ "$(grep -A4 'REFUSING: the screen is locked' "$here")" == *"test runner failed to"* ]] && print 1 || print 0 ) \
    "the refusal no longer says why a screen-free suite is refused too"

  say ""
  say " 11. the iOS leg after a green macOS run (T-1956)"
  # THE WHOLE RUN, NOT A HELPER. Every case below is a real `xcb.sh <id> build` through the real main
  # flow, with `$XCODEBUILD` pointed at a stub that records its argv and replays a fixture log --
  # the first call gets the primary's log, every later call the iOS one. So "the leg ran" is read
  # off the stub's call count and argv, not off a banner, and a mutation that unwires the leg from
  # the main flow goes red here even with `ios_leg_decide` intact. Logs land under `$ws` (TMPDIR),
  # and CADENCE_STALL_POLL=1 keeps the watchdog's orphaned `sleep` from holding the pipe 30 s.
  mkdir -p "$ws/leg/tmp"
  print -rl -- '#!/bin/zsh' \
    'print -r -- "${(j: :)@}" >> "$FAKE_XCB_CALLS"' \
    'if (( $(grep -c . "$FAKE_XCB_CALLS") == 1 )); then' \
    '  [[ -n "${FAKE_XCB_PS_AFTER:-}" ]] && cp -- "$FAKE_XCB_PS_AFTER" "$CADENCE_PS_FIXTURE"' \
    '  cat -- "$FAKE_XCB_PRIMARY_LOG"; exit 0' \
    'fi' \
    'cat -- "$FAKE_XCB_IOS_LOG"; exit ${FAKE_XCB_IOS_EXIT:-0}' > "$ws/leg/xcodebuild"
  chmod +x "$ws/leg/xcodebuild"
  print -rl -- \
    "SwiftCompile normal arm64 /repo/Cadence/macOS/Views/Probe.swift (in target 'Cadence' from project 'Cadence')" \
    "** BUILD SUCCEEDED **" > "$ws/leg/mac.log"
  print -rl -- \
    "SwiftCompile normal arm64 /repo/Cadence/iOS/iOSProbe.swift (in target 'Cadence' from project 'Cadence')" \
    "** BUILD SUCCEEDED **" > "$ws/leg/ios-ok.log"
  print -rl -- \
    "SwiftCompile normal arm64 /repo/Cadence/iOS/iOSProbe.swift (in target 'Cadence' from project 'Cadence')" \
    "/repo/Cadence/iOS/iOSProbe.swift:7:13: warning: initialization of immutable value 'p' was never used; consider replacing with assignment to '_'" \
    "** BUILD SUCCEEDED **" > "$ws/leg/ios-warn.log"
  print -rl -- \
    "SwiftCompile normal arm64 /repo/Cadence/iOS/iOSProbe.swift (in target 'Cadence' from project 'Cadence')" \
    "/repo/Cadence/iOS/iOSProbe.swift:7:13: error: cannot find 'zzMissing' in scope" \
    "** BUILD FAILED **" > "$ws/leg/ios-fail.log"
  # Real line shape (a widget-only compile, measured in an iOS log 2026-10-02): a non-zero count
  # that holds no file of the app target -- the "tiny count over nothing" case.
  print -rl -- \
    "SwiftCompile normal arm64 /repo/Cadence/Services/CadenceWidgetIntents.swift (in target 'CadenceWidgets' from project 'Cadence')" \
    "** BUILD SUCCEEDED **" > "$ws/leg/ios-widgets.log"
  local lcalls lsecond leg_skip=""
  run_leg() {  # $1 = primary log, $2 = iOS log, $3 = iOS exit, $4... = xcb.sh arguments after the id
    : > "$ws/leg/calls"
    lout=$(XCODEBUILD="$ws/leg/xcodebuild" FAKE_XCB_CALLS="$ws/leg/calls" FAKE_XCB_PRIMARY_LOG="$1" \
      FAKE_XCB_IOS_LOG="$2" FAKE_XCB_IOS_EXIT="$3" TMPDIR="$ws/leg/tmp/" CADENCE_STALL_POLL=1 \
      CADENCE_SKIP_IOS_LEG="$leg_skip" CADENCE_ALLOW_WARNINGS= \
      zsh "$here" selftest-ios-leg "${@:4}" 2>&1); lrc=$?
    lcalls=$(grep -c . "$ws/leg/calls" | tr -d ' ')
    lsecond=$(sed -n 2p "$ws/leg/calls")
  }
  local -a mac_args
  mac_args=(build -scheme Cadence -destination 'platform=macOS' -derivedDataPath "$ws/leg/dd"
            -resultBundlePath "$ws/leg/r.xcresult" CODE_SIGN_IDENTITY=-)

  run_leg "$ws/leg/mac.log" "$ws/leg/ios-ok.log" 0 "${mac_args[@]}"
  check "RUN: a green macOS build that compiled Swift is followed by a second xcodebuild" \
    $( [[ $lrc == 0 && $lcalls == 2 ]] && print 1 || print 0 ) "exit $lrc, $lcalls call(s): $lout"
  check "...and that call builds generic/platform=iOS Simulator, not macOS again" \
    $( [[ "$lsecond" == *"-destination generic/platform=iOS Simulator build" && "$lsecond" != *platform=macOS* ]] && print 1 || print 0 ) "argv: $lsecond"
  check "...into the SAME DerivedData, keeping the build settings and dropping test-only flags" \
    $( [[ "$lsecond" == *"-derivedDataPath $ws/leg/dd"* && "$lsecond" == *"CODE_SIGN_IDENTITY=-"* && "$lsecond" != *resultBundlePath* ]] && print 1 || print 0 ) "argv: $lsecond"
  check "...and reports both XCODEBUILD_EXIT= lines and that the iOS surface COMPILED" \
    $( [[ $(print -r -- "$lout" | grep -c 'XCODEBUILD_EXIT=0') == 2 && "$lout" == *"ios leg: COMPILED -- 1 app-target"* ]] && print 1 || print 0 ) "$lout"

  run_leg "$ws/leg/ios-ok.log" "$ws/leg/ios-ok.log" 0 build -scheme Cadence \
    -destination "$IOS_LEG_DESTINATION" -derivedDataPath "$ws/leg/dd"
  check "SKIP (no recursion): a run whose destination is already iOS builds iOS ONCE (CI's ios-build)" \
    $( [[ $lrc == 0 && $lcalls == 1 && "$lout" == *"ios leg: skipped (ALREADY-IOS)"* ]] && print 1 || print 0 ) "exit $lrc, $lcalls call(s): $lout"

  leg_skip=1
  run_leg "$ws/leg/mac.log" "$ws/leg/ios-ok.log" 0 "${mac_args[@]}"
  leg_skip=""
  check "SKIP (carve-out): CADENCE_SKIP_IOS_LEG=1 skips the second build" \
    $( [[ $lrc == 0 && $lcalls == 1 ]] && print 1 || print 0 ) "exit $lrc, $lcalls call(s): $lout"
  check "...and ANNOUNCES it, the CADENCE_ALLOW_WARNINGS way, rather than going quiet" \
    $( [[ "$lout" == *"!! IOS-LEG-SKIPPED: CADENCE_SKIP_IOS_LEG=1"* ]] && print 1 || print 0 ) "$lout"

  run_leg "$ws/noop.log" "$ws/leg/ios-ok.log" 0 "${mac_args[@]}"
  check "SKIP: a primary run that compiled nothing does not pay for an iOS build, and says so" \
    $( [[ $lcalls == 1 && "$lout" == *"ios leg: skipped (PRIMARY-VACUOUS)"* ]] && print 1 || print 0 ) "$lcalls call(s): $lout"
  run_leg "$ws/leg/mac.log" "$ws/leg/ios-ok.log" 0 build -scheme CadenceMCPServer \
    -destination 'platform=macOS' -derivedDataPath "$ws/leg/dd"
  check "SKIP: a scheme with no iOS surface (CadenceMCPServer) is not built for iOS, and says so" \
    $( [[ $lcalls == 1 && "$lout" == *"ios leg: skipped (NO-IOS-SCHEME)"* ]] && print 1 || print 0 ) "$lcalls call(s): $lout"

  run_leg "$ws/leg/mac.log" "$ws/leg/ios-warn.log" 0 "${mac_args[@]}"
  check "GATE: one iOS-only warning breaks the zero-warning baseline (exit $WARNING_GATE_EXIT)" \
    $( [[ $lrc == $WARNING_GATE_EXIT && "$lout" == *WARNING-BASELINE* && "$lout" == *"iOSProbe.swift:7:13"* ]] && print 1 || print 0 ) "exit $lrc: $lout"
  run_leg "$ws/leg/mac.log" "$ws/leg/ios-fail.log" 65 "${mac_args[@]}"
  check "GATE: an iOS compile failure under a green macOS run exits $IOS_LEG_EXIT and quotes the error" \
    $( [[ $lrc == $IOS_LEG_EXIT && "$lout" == *IOS-LEG-FAILED* && "$lout" == *"cannot find 'zzMissing'"* && "$lout" == *"XCODEBUILD_EXIT=65"* ]] && print 1 || print 0 ) "exit $lrc: $lout"

  run_leg "$ws/leg/mac.log" "$ws/leg/ios-widgets.log" 0 "${mac_args[@]}"
  check "VACUOUS: a leg that compiled no app-target file certifies NOTHING (IOS-LEG-VACUOUS)" \
    $( [[ "$lout" == *IOS-LEG-VACUOUS* && "$lout" != *"ios leg: COMPILED"* ]] && print 1 || print 0 ) "$lout"
  check "...and, like the macOS vacuous count, it does not gate" \
    $( (( lrc == 0 )) && print 1 || print 0 ) "exit $lrc"

  # The carve-out is only honest where something else builds iOS. CI is that place, so the
  # workflow is read: `macos-tests` must set it and `ios-build` must be the iOS build.
  local ciyml="$ROOT_DIR/.github/workflows/ci.yml"
  if [[ -f "$ciyml" ]]; then
    local cijob
    cijob=$(awk '/^  macos-tests:/{on=1; next} /^  [a-z][a-z0-9-]*:$/{on=0} on' "$ciyml")
    check "CI: macos-tests sets CADENCE_SKIP_IOS_LEG, so it does not rebuild iOS beside ios-build" \
      $( print -r -- "$cijob" | grep -qE "^ +CADENCE_SKIP_IOS_LEG: *'?1'?$" && print 1 || print 0 ) "macos-tests job does not set it"
    cijob=$(awk '/^  ios-build:/{on=1; next} /^  [a-z][a-z0-9-]*:$/{on=0} on' "$ciyml")
    check "CI: ...and ios-build really is an iOS build, so the carve-out loses nothing" \
      $( [[ "$cijob" == *"-destination '$IOS_LEG_DESTINATION'"* ]] && print 1 || print 0 ) "ios-build no longer builds $IOS_LEG_DESTINATION"
  else
    say "  skip  CI checks: no .github/workflows/ci.yml under $ROOT_DIR"
  fi

  say ""
  say " 12. one DerivedData, one live build; and the last full green (T-2042)"
  # The whole run again, through `raw` (no drift check, no test-host lease -- both would read the
  # live checkout and the live lock), with `$XCODEBUILD` the section-11 stub. The process list is a
  # fixture, the tree is a throwaway git repository, and the record lands under $ws.
  mkdir -p "$ws/lg/tree" "$ws/lg/state" "$ws/lg/state2"
  local lgout lgcalls lgsha lgdd="$ws/lg/cadence-dd-lg" lgps=""
  local -i lgrc
  local -a lgfull
  git -C "$ws/lg/tree" init -q 2>/dev/null
  print -r -- "one" > "$ws/lg/tree/a.txt"
  git -C "$ws/lg/tree" add a.txt 2>/dev/null
  git -C "$ws/lg/tree" -c user.name=selftest -c user.email=selftest@invalid -c core.hooksPath=/dev/null \
    -c commit.gpgsign=false commit -qm one 2>/dev/null
  lgsha="$(git -C "$ws/lg/tree" rev-parse HEAD 2>/dev/null)"
  print -rl -- \
    "SwiftCompile normal arm64 /repo/Cadence/macOS/Views/Probe.swift (in target 'Cadence' from project 'Cadence')" \
    "◇ Test run started." \
    "✔ Test aUnitTestThatPassed() passed after 0.001 seconds." \
    "** TEST SUCCEEDED **" > "$ws/lg/green.log"
  print -rl -- "4242 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project P -derivedDataPath $lgdd/ test" \
    > "$ws/lg/ps-live.txt"
  print -rl -- "4242 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project P -derivedDataPath $ws/lg/cadence-dd-other test" \
    "4243 /bin/zsh ./scripts/xcb.sh lg raw -derivedDataPath $lgdd test" > "$ws/lg/ps-other.txt"
  : > "$ws/lg/ps-empty.txt"
  run_lg() {  # $1 = state dir, $2 = primary log, $3... = xcb.sh arguments after the id
    : > "$ws/leg/calls"
    lgout=$(XCODEBUILD="$ws/leg/xcodebuild" FAKE_XCB_CALLS="$ws/leg/calls" FAKE_XCB_PRIMARY_LOG="$2" \
      FAKE_XCB_IOS_LOG="$ws/leg/ios-ok.log" TMPDIR="$ws/leg/tmp/" CADENCE_STALL_POLL=1 \
      CADENCE_XCB_STATE_DIR="$1" CADENCE_TREE_ROOT="$ws/lg/tree" CADENCE_PS_FIXTURE="$lgps" \
      CADENCE_SESSION_FIXTURE="$ws/sess-locked-midrun.txt" CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 \
      CADENCE_ALLOW_WARNINGS= zsh "$here" selftest-lg raw "${@:3}" 2>&1); lgrc=$?
    lgcalls=$(grep -c . "$ws/leg/calls" | tr -d ' ')
  }
  run_lg_green() { lgout=$(CADENCE_XCB_STATE_DIR="$ws/lg/state" CADENCE_TREE_ROOT="$ws/lg/tree" zsh "$here" last-green 2>&1); lgrc=$?; }
  lgfull=(-scheme Cadence -destination 'platform=macOS' -only-testing:CadenceTests -derivedDataPath "$lgdd" test)

  lgps="$ws/lg/ps-live.txt"
  run_lg "$ws/lg/state" "$ws/lg/green.log" "${lgfull[@]}"
  check "DD-IN-USE: a run whose -derivedDataPath a live xcodebuild names is REFUSED (exit $DD_IN_USE_EXIT)" \
    $( [[ $lgrc == $DD_IN_USE_EXIT && "$lgout" == *DD-IN-USE* && "$lgout" == *"pid(s) 4242"* ]] && print 1 || print 0 ) "exit $lgrc: $lgout"
  check "...before anything is built: xcodebuild was never called" \
    $( [[ $lgcalls == 0 ]] && print 1 || print 0 ) "$lgcalls call(s)"
  lgps="$ws/lg/ps-other.txt"
  run_lg "$ws/lg/state" "$ws/lg/green.log" "${lgfull[@]}"
  check "CONTROL: another DerivedData, or a non-xcodebuild process naming this one, does not refuse" \
    $( [[ $lgrc == 0 && $lgcalls == 1 ]] && print 1 || print 0 ) "exit $lgrc, $lgcalls call(s): $lgout"
  check "GREEN full unscoped CadenceTests run records HEAD as the last green" \
    $( [[ "$lgout" == *"last-green: recorded $lgsha (tree clean)"* && "$(sed -n 's/^sha=//p' "$ws/lg/state"/cadence-xcb-last-green.* 2>/dev/null)" == "$lgsha" ]] && print 1 || print 0 ) "$lgout"
  check "...and the result block points at release-dd, not at a bare delete" \
    $( [[ "$lgout" == *"./scripts/xcb.sh release-dd $lgdd"* && "$lgout" != *"delete $lgdd when you are done"* ]] && print 1 || print 0 ) "$lgout"
  check "WIRING (T-2041): the real run hands its arguments to the lock report -- unit-only gets the note" \
    $( [[ "$lgout" == *"SCREEN-LOCKED (unit-only"* && "$lgout" != *SCREEN-LOCKED-MID-RUN* ]] && print 1 || print 0 ) "$lgout"
  lgps=""

  run_lg_green
  check "last-green: an untouched tree is UNCHANGED (exit 0) -- a heartbeat may skip the re-run" \
    $( [[ $lgrc == 0 && "$lgout" == *"last-green: UNCHANGED"* ]] && print 1 || print 0 ) "exit $lgrc: $lgout"
  print -r -- "edited" >> "$ws/lg/tree/a.txt"
  run_lg_green
  check "last-green: an uncommitted edit on the same HEAD is CHANGED (exit 1)" \
    $( [[ $lgrc == 1 && "$lgout" == *"working tree differs"* ]] && print 1 || print 0 ) "exit $lgrc: $lgout"
  git -C "$ws/lg/tree" checkout -q -- a.txt 2>/dev/null
  print -r -- "new" > "$ws/lg/tree/b.txt"
  run_lg_green
  check "last-green: a new untracked file is CHANGED too" \
    $( [[ $lgrc == 1 ]] && print 1 || print 0 ) "exit $lgrc: $lgout"
  git -C "$ws/lg/tree" add b.txt 2>/dev/null
  git -C "$ws/lg/tree" -c user.name=selftest -c user.email=selftest@invalid -c core.hooksPath=/dev/null \
    -c commit.gpgsign=false commit -qm two 2>/dev/null
  run_lg_green
  check "last-green: a new commit is CHANGED, and says how many paths differ" \
    $( [[ $lgrc == 1 && "$lgout" == *"1 path(s) differ from $lgsha"* ]] && print 1 || print 0 ) "exit $lgrc: $lgout"
  lgout=$(CADENCE_XCB_STATE_DIR="$ws/lg/state2" CADENCE_TREE_ROOT="$ws/lg/tree" zsh "$here" last-green 2>&1); lgrc=$?
  check "last-green: no record is NO-RECORD (exit 3), never UNCHANGED" \
    $( [[ $lgrc == 3 && "$lgout" == *NO-RECORD* ]] && print 1 || print 0 ) "exit $lgrc: $lgout"

  run_lg "$ws/lg/state2" "$ws/lg/green.log" -scheme Cadence -destination 'platform=macOS' \
    -only-testing:CadenceTests -skip-testing:CadenceTests/SomeSuite -derivedDataPath "$lgdd" test
  check "CONTROL: a green NARROWED run records nothing (it is not the run a heartbeat repeats)" \
    $( [[ $lgrc == 0 && "$lgout" != *last-green* && -z "$(print -r -- "$ws/lg/state2"/cadence-xcb-last-green.*(N))" ]] && print 1 || print 0 ) "exit $lgrc: $lgout"
  run_lg "$ws/lg/state2" "$ws/noop.log" "${lgfull[@]}"
  check "CONTROL: a full run that is NOT green records nothing, and says why" \
    $( [[ $lgrc != 0 && "$lgout" == *"last-green: not recorded -- this full CadenceTests run is not green"* \
         && -z "$(print -r -- "$ws/lg/state2"/cadence-xcb-last-green.*(N))" ]] && print 1 || print 0 ) "exit $lgrc: $lgout"

  # The iOS leg runs after the lease is given back, which is when a same-id sibling can start: the
  # stub swaps the process list in AFTER the primary build, so only the pre-leg check can see it.
  cp -- "$ws/lg/ps-other.txt" "$ws/lg/ps-swapped.txt"
  : > "$ws/leg/calls"
  lgout=$(XCODEBUILD="$ws/leg/xcodebuild" FAKE_XCB_CALLS="$ws/leg/calls" FAKE_XCB_PRIMARY_LOG="$ws/leg/mac.log" \
    FAKE_XCB_IOS_LOG="$ws/leg/ios-ok.log" FAKE_XCB_PS_AFTER="$ws/lg/ps-live.txt" TMPDIR="$ws/leg/tmp/" \
    CADENCE_STALL_POLL=1 CADENCE_PS_FIXTURE="$ws/lg/ps-swapped.txt" CADENCE_SKIP_IOS_LEG= CADENCE_ALLOW_WARNINGS= \
    zsh "$here" selftest-lg build -scheme Cadence -destination 'platform=macOS' -derivedDataPath "$lgdd" 2>&1); lgrc=$?
  lgcalls=$(grep -c . "$ws/leg/calls" | tr -d ' ')
  check "DD-IN-USE before the iOS leg: the leg is NOT built into a live sibling's DerivedData, and it gates" \
    $( [[ $lgrc == $DD_IN_USE_EXIT && $lgcalls == 1 && "$lgout" == *"IOS-LEG-SKIPPED (DD-IN-USE)"* ]] && print 1 || print 0 ) "exit $lgrc, $lgcalls call(s): $lgout"
  check "...and the result block says not to delete it, naming the pid" \
    $( [[ "$lgout" == *"do NOT delete $lgdd: live xcodebuild pid(s) 4242"* ]] && print 1 || print 0 ) "$lgout"

  # The check after the test-host lease (T-2043). Every case above is refused at preflight first, so
  # deleting that call alone left this section green. A `test` through a copy of this script whose
  # `$ROOT_DIR` holds a stub test-host-lock.sh: its `acquire` swaps the live list in, so preflight
  # reads a free DerivedData and only the post-lease check can see the sibling.
  mkdir -p "$ws/lg/root/scripts"
  cp -- "$here" "$ws/lg/root/scripts/xcb.sh"
  print -rl -- '#!/bin/zsh' \
    '[[ "$1" == acquire ]] && cp -- "$FAKE_LEASE_PS_AFTER" "$CADENCE_PS_FIXTURE"' \
    'exit 0' > "$ws/lg/root/scripts/test-host-lock.sh"
  chmod +x "$ws/lg/root/scripts/test-host-lock.sh"
  cp -- "$ws/lg/ps-other.txt" "$ws/lg/ps-swapped.txt"
  : > "$ws/leg/calls"
  lgout=$(XCODEBUILD="$ws/leg/xcodebuild" FAKE_XCB_CALLS="$ws/leg/calls" FAKE_XCB_PRIMARY_LOG="$ws/lg/green.log" \
    FAKE_XCB_IOS_LOG="$ws/leg/ios-ok.log" FAKE_LEASE_PS_AFTER="$ws/lg/ps-live.txt" TMPDIR="$ws/leg/tmp/" \
    CADENCE_STALL_POLL=1 CADENCE_PS_FIXTURE="$ws/lg/ps-swapped.txt" CADENCE_XCB_STATE_DIR="$ws/lg/state2" \
    CADENCE_TREE_ROOT="$ws/lg/tree" CADENCE_SESSION_FIXTURE="$ws/sess-locked-midrun.txt" \
    CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 CADENCE_ALLOW_WARNINGS= zsh "$ws/lg/root/scripts/xcb.sh" selftest-lg test \
    -scheme Cadence -destination 'platform=macOS' -only-testing:CadenceTests -derivedDataPath "$lgdd" 2>&1); lgrc=$?
  lgcalls=$(grep -c . "$ws/leg/calls" | tr -d ' ')
  check "DD-IN-USE before launch: a sibling that starts during the test-host lease wait is REFUSED (exit $DD_IN_USE_EXIT)" \
    $( [[ $lgrc == $DD_IN_USE_EXIT && "$lgout" == *"DD-IN-USE (T-2042, before launch"* \
         && "$lgout" != *"T-2042, preflight"* && $lgcalls == 0 ]] && print 1 || print 0 ) "exit $lgrc, $lgcalls call(s): $lgout"

  mkdir -p "$lgdd"
  lgout=$(CADENCE_PS_FIXTURE="$ws/lg/ps-live.txt" zsh "$here" release-dd "$lgdd" 2>&1); lgrc=$?
  check "release-dd REFUSES (exit $DD_IN_USE_EXIT) while a live xcodebuild names the path, and deletes nothing" \
    $( [[ $lgrc == $DD_IN_USE_EXIT && "$lgout" == *DD-IN-USE* && -d "$lgdd" ]] && print 1 || print 0 ) "exit $lgrc: $lgout"
  lgout=$(CADENCE_PS_FIXTURE="$ws/lg/ps-empty.txt" zsh "$here" release-dd "$lgdd" 2>&1); lgrc=$?
  check "release-dd fails CLOSED when the process list cannot be read" \
    $( [[ $lgrc == $DD_IN_USE_EXIT && -d "$lgdd" ]] && print 1 || print 0 ) "exit $lgrc: $lgout"
  lgout=$(zsh "$here" release-dd "$ws/lg/tree" 2>&1); lgrc=$?
  check "release-dd deletes nothing that is not a cadence-dd-* directory" \
    $( [[ $lgrc == 2 && -d "$ws/lg/tree" ]] && print 1 || print 0 ) "exit $lgrc: $lgout"
  lgout=$(CADENCE_PS_FIXTURE="$ws/lg/ps-other.txt" zsh "$here" release-dd "$lgdd" 2>&1); lgrc=$?
  check "release-dd deletes a DerivedData no live xcodebuild names" \
    $( [[ $lgrc == 0 && ! -e "$lgdd" ]] && print 1 || print 0 ) "exit $lgrc: $lgout"


  say ""
  say " 13. QUEUED vs RUNNING vs WEDGED, and silence nobody is watching (T-2071 / T-1920)"
  # THE WHOLE RUN, NOT A HELPER, for the reason section 11 gives: every state below is induced by a
  # REAL `xcb.sh <id> test` through the real main flow, with `$XCODEBUILD` pointed at a stub and
  # `$ROOT_DIR/scripts/test-host-lock.sh` pointed at one. So QUEUED is a run that is genuinely
  # waiting on `acquire` and has genuinely not launched xcodebuild -- the stub's call file is the
  # control, and it is EMPTY -- rather than a fixture asserting that the word prints.
  #
  # WEDGED is the one state that cannot be induced for real: it needs this Mac's testmanagerd to
  # stop answering, which is the owner's to cause and nobody's to want. So the half of it that CAN
  # be induced is -- a started run, producing no results and no output, whose owner is alive -- and
  # the half that cannot comes from `CADENCE_XCTEST_SESSION_FIXTURE`, in the format `log show`
  # prints. The pair of checks around it is what makes that honest: the SAME live silent run reads
  # WEDGED under the T-2067 signature and STALLED under a balanced one, so the verdict is being
  # taken from the signature and not from the silence.
  local rs_xcb="$ws/rs/root/scripts/xcb.sh" rsout="" rs_fixture="" rs_sample=1 rs_long=1
  local rs_log="" rs_owner="" rs_calls=""
  local -i rsrc=0 rs_i=0 rs_bg=0 rs_wedge_bg=0 rs_live_bg=0 rs_slow_bg=0
  mkdir -p "$ws/rs/root/scripts" "$ws/rs/tmp"
  cp -- "$here" "$rs_xcb"
  # `acquire` blocks forever when FAKE_LOCK_BLOCK names a file, and returns at once otherwise; the
  # queue line `status` prints is the real script's shape, so the QUEUED verdict's "do not start a
  # second run" advice is read back from where a real waiter would read it.
  print -rl -- '#!/bin/zsh' \
    'if [[ "$1" == acquire && -n "${FAKE_LOCK_BLOCK:-}" ]]; then' \
    '  print -r -- "$$" > "$FAKE_LOCK_BLOCK"; while :; do sleep 1; done' \
    'fi' \
    'if [[ "$1" == status ]]; then' \
    '  print -r -- "locked by xcb-sibling / pid 4242 (held) for 812s"' \
    '  print -r -- "queue (1 waiting, first served first):"' \
    '  print -r -- "  xcb-rsqueue / pid 4243, waiting 812s"' \
    'fi' \
    'exit 0' > "$ws/rs/root/scripts/test-host-lock.sh"
  chmod +x "$ws/rs/root/scripts/test-host-lock.sh"
  # A stub that STARTS and then stops producing output: xcodebuild's own first line, then nothing.
  # `sleep` is an external command, so zsh has flushed the line into the log before it blocks.
  print -rl -- '#!/bin/zsh' \
    'print -r -- "${(j: :)@}" >> "$FAKE_XCB_CALLS"' \
    'print -r -- "Command line invocation:"' \
    'print -r -- "    xcodebuild test -scheme Cadence -destination platform=macOS"' \
    'while :; do sleep 1; done' > "$ws/rs/silent-xcodebuild"
  # A stub that keeps producing result lines, i.e. a healthy run.
  print -rl -- '#!/bin/zsh' \
    'print -r -- "${(j: :)@}" >> "$FAKE_XCB_CALLS"' \
    'print -r -- "Command line invocation:"' \
    'while :; do print -r -- "✔ Test aProbe() passed after 0.001 seconds."; sleep 0.2; done' > "$ws/rs/live-xcodebuild"
  # A stub that is quiet for longer than the FIRST window and then speaks: the shape a healthy run
  # of this repository's own suite really has. Measured live on 2026-10-06, the xcb log sat at
  # exactly 707008 bytes for 75+ consecutive seconds inside `theTestHostLocksOwnGuardsStillFire()`,
  # which spawns real processes and real sleeps and prints nothing meanwhile.
  print -rl -- '#!/bin/zsh' \
    'print -r -- "${(j: :)@}" >> "$FAKE_XCB_CALLS"' \
    'print -r -- "Command line invocation:"' \
    'sleep 3' \
    'while :; do print -r -- "✔ Test aSlowOne() passed after 3.000 seconds."; sleep 3; done' > "$ws/rs/slow-xcodebuild"
  chmod +x "$ws/rs/silent-xcodebuild" "$ws/rs/live-xcodebuild" "$ws/rs/slow-xcodebuild"
  # The two session logs, in `log show --style compact` shape. The first is T-2067's signature:
  # a session that connected and resumed and never got transport. The second is the healthy pair.
  print -rl -- \
    "2026-10-04 15:02:01.113 Df xctest[41122:2f1] Received new test session connection" \
    "2026-10-04 15:02:01.114 Df xctest[41122:2f1] resuming connection" > "$ws/rs/sess-wedged.txt"
  print -rl -- \
    "2026-10-04 15:02:01.113 Df xctest[41122:2f1] Received new test session connection" \
    "2026-10-04 15:02:01.114 Df xctest[41122:2f1] resuming connection" \
    "2026-10-04 15:02:01.116 Df xctest[41122:2f1] requested serialized transport" > "$ws/rs/sess-ok.txt"
  rs_fixture="$ws/rs/sess-ok.txt"
  rs_probe() {  # $@ = run-state arguments
    rsout=$(CADENCE_RUNSTATE_SAMPLE="$rs_sample" CADENCE_RUNSTATE_SAMPLE_LONG="$rs_long" \
      CADENCE_XCTEST_SESSION_FIXTURE="$rs_fixture" \
      TMPDIR="$ws/rs/tmp/" zsh "$rs_xcb" run-state "$@" 2>&1); rsrc=$?
  }

  # --- an id nothing has ever claimed ---------------------------------------------------------
  rs_probe rs-never-run
  check "an id with no log at all is NO-LOG (exit $RUNSTATE_EXIT_NO_LOG), not a guess about a dead run" \
    $( (( rsrc == RUNSTATE_EXIT_NO_LOG )) && [[ "$rsout" == *"run-state: NO-LOG"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"

  # --- QUEUED, induced for real on the production path ------------------------------------------
  : > "$ws/rs/queue-calls"; : > "$ws/rs/lock-waiter"
  XCODEBUILD="$ws/rs/live-xcodebuild" FAKE_XCB_CALLS="$ws/rs/queue-calls" \
    FAKE_LOCK_BLOCK="$ws/rs/lock-waiter" TMPDIR="$ws/rs/tmp/" CADENCE_STALL_POLL=1 \
    CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 CADENCE_ALLOW_WARNINGS= \
    zsh "$rs_xcb" rsqueue test -scheme Cadence -destination 'platform=macOS' \
    -only-testing:CadenceTests -derivedDataPath "$ws/rs/tmp/cadence-dd-rsqueue" >"$ws/rs/queue-out" 2>&1 &
  rs_bg=$!
  for rs_i in {1..300}; do [[ -s "$ws/rs/lock-waiter" ]] && break; sleep 0.2; done
  rs_calls=$(grep -c . "$ws/rs/queue-calls" | tr -d ' ')
  rs_probe rsqueue
  check "a run blocked in \`test-host-lock.sh acquire\` reads QUEUED (exit $RUNSTATE_EXIT_QUEUED)" \
    $( (( rsrc == RUNSTATE_EXIT_QUEUED )) && [[ "$rsout" == *"run-state: QUEUED"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  check "...and the CONTROL that makes it a real queue: xcodebuild was never launched ($rs_calls call(s))" \
    $( [[ "$rs_calls" == 0 ]] && print 1 || print 0 ) "$rs_calls call(s) in $ws/rs/queue-calls"
  check "...and it is not read as RUNNING, WEDGED or ABANDONED, which is the misreading it exists for" \
    $( [[ "$rsout" != *"run-state: RUNNING"* && "$rsout" != *"run-state: WEDGED"* \
         && "$rsout" != *"run-state: ABANDONED"* ]] && print 1 || print 0 ) "$rsout"
  check "...and it names the lock it is behind, so the reader does not start a second run" \
    $( [[ "$rsout" == *"locked by xcb-sibling"* && "$rsout" == *"Do not start a second run"* ]] && print 1 || print 0 ) "$rsout"
  # The same run, the same log, the same absent output -- only the OWNER's pulse changes. Nothing
  # in the log can tell these two apart, which is why the pid is read out of the log's NAME.
  rs_owner=$(cat "$ws/rs/lock-waiter" 2>/dev/null)
  # The waiter is killed and the run REAPED with `wait`, not polled with `kill -0`: an unreaped
  # zombie still answers `kill -0`, so a poll would read a dead owner as a live one and the check
  # below would pass for the wrong reason -- the same mistake the verdict itself exists to avoid.
  [[ -n "$rs_owner" ]] && kill "$rs_owner" 2>/dev/null
  wait "$rs_bg" 2>/dev/null
  kill "$rs_bg" 2>/dev/null
  rs_probe rsqueue
  # The same pointer, the same absent log -- only the OWNER's pulse changed, and the answer is NOT
  # ABANDONED. There is no log, so there is nothing that was abandoned: a run killed while queued
  # and a log swept out of TMPDIR leave byte-identical evidence, and the instrument says so rather
  # than picking the more dramatic of the two.
  check "the SAME pointer, once its owner dies, stops reading QUEUED and reads NO-LOG (exit $RUNSTATE_EXIT_NO_LOG)" \
    $( (( rsrc == RUNSTATE_EXIT_NO_LOG )) && [[ "$rsout" == *"run-state: NO-LOG"* \
         && "$rsout" != *"run-state: QUEUED"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  # PID REUSE, and this one is not hypothetical: a sweep of this Mac's real TMPDIR called FOUR
  # three-week-old pointers QUEUED because their long-dead owners' pid numbers were live again.
  # The name carries the run's own start time, so the liveness of a pid is only believed while the
  # name is recent enough for the test-host lease (5400s) to still be plausible.
  ln -sf "cadence-xcb-rsreuse.20250101-000000-$$.log" "$ws/rs/tmp/cadence-xcb-rsreuse.log"
  rs_probe rsreuse
  check "a pointer named a year ago is NOT QUEUED however live the pid in its name is (T-2071)" \
    $( (( rsrc == RUNSTATE_EXIT_NO_LOG )) && [[ "$rsout" != *"run-state: QUEUED"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"

  # --- RUNNING, induced for real on the production path ------------------------------------------
  : > "$ws/rs/live-calls"
  XCODEBUILD="$ws/rs/live-xcodebuild" FAKE_XCB_CALLS="$ws/rs/live-calls" TMPDIR="$ws/rs/tmp/" \
    CADENCE_STALL_POLL=1 CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 CADENCE_ALLOW_WARNINGS= \
    zsh "$rs_xcb" rslive test -scheme Cadence -destination 'platform=macOS' \
    -only-testing:CadenceTests -derivedDataPath "$ws/rs/tmp/cadence-dd-rslive" >"$ws/rs/live-out" 2>&1 &
  rs_live_bg=$!
  rs_log="$ws/rs/tmp/cadence-xcb-rslive.log"
  for rs_i in {1..300}; do grep -qF 'Command line invocation' "$rs_log" 2>/dev/null && break; sleep 0.2; done
  # Deliberately probed with the WEDGE fixture in place: growth must outrank the signature, or the
  # instrument reports a healthy run as a dead host, which is T-2067's own misreading inverted.
  rs_fixture="$ws/rs/sess-wedged.txt"
  rs_probe rslive
  check "a run whose xcb log GROWS reads RUNNING (exit $RUNSTATE_EXIT_RUNNING)" \
    $( (( rsrc == RUNSTATE_EXIT_RUNNING )) && [[ "$rsout" == *"run-state: RUNNING"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  check "...even with the T-2067 wedge signature in the session log: growth outranks it" \
    $( [[ "$rsout" != *"run-state: WEDGED"* && "$rsout" != *"run-state: STALLED"* ]] && print 1 || print 0 ) "$rsout"

  # --- the SECOND window: a run that is quiet, and then is not -----------------------------------
  # Without the confirming window this run is STALLED, and STALLED on a healthy build several times
  # an hour is how an instrument gets switched off. The stub below says nothing for longer than the
  # first window and then speaks; the verdict has to be RUNNING, which it can only be if the second
  # window really re-reads the log rather than re-printing the first answer.
  : > "$ws/rs/slow-calls"
  XCODEBUILD="$ws/rs/slow-xcodebuild" FAKE_XCB_CALLS="$ws/rs/slow-calls" TMPDIR="$ws/rs/tmp/" \
    CADENCE_STALL_POLL=1 CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 CADENCE_ALLOW_WARNINGS= \
    zsh "$rs_xcb" rsslow test -scheme Cadence -destination 'platform=macOS' \
    -only-testing:CadenceTests -derivedDataPath "$ws/rs/tmp/cadence-dd-rsslow" >"$ws/rs/slow-out" 2>&1 &
  rs_slow_bg=$!
  rs_log="$ws/rs/tmp/cadence-xcb-rsslow.log"
  for rs_i in {1..300}; do grep -qF 'Command line invocation' "$rs_log" 2>/dev/null && break; sleep 0.2; done
  rs_fixture="$ws/rs/sess-wedged.txt"
  rs_long=8
  rs_probe rsslow
  check "a run quiet through the FIRST window and talking in the second is RUNNING, not STALLED" \
    $( (( rsrc == RUNSTATE_EXIT_RUNNING )) && [[ "$rsout" == *"run-state: RUNNING"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  check "...and the report says it went back for a second window rather than answering on the first" \
    $( [[ "$rsout" == *"confirming over 8s more"* ]] && print 1 || print 0 ) "$rsout"
  rs_long=1
  pkill -P "$rs_slow_bg" 2>/dev/null
  wait "$rs_slow_bg" 2>/dev/null

  # --- WEDGED, and the control that proves it is read from the signature -------------------------
  : > "$ws/rs/wedge-calls"
  XCODEBUILD="$ws/rs/silent-xcodebuild" FAKE_XCB_CALLS="$ws/rs/wedge-calls" TMPDIR="$ws/rs/tmp/" \
    CADENCE_STALL_POLL=1 CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 CADENCE_ALLOW_WARNINGS= \
    zsh "$rs_xcb" rswedge test -scheme Cadence -destination 'platform=macOS' \
    -only-testing:CadenceTests -derivedDataPath "$ws/rs/tmp/cadence-dd-rswedge" >"$ws/rs/wedge-out" 2>&1 &
  rs_wedge_bg=$!
  rs_log="$ws/rs/tmp/cadence-xcb-rswedge.log"
  for rs_i in {1..300}; do grep -qF 'Command line invocation' "$rs_log" 2>/dev/null && break; sleep 0.2; done
  rs_fixture="$ws/rs/sess-wedged.txt"
  rs_probe rswedge
  check "a started run with no growth, no results and the T-2067 signature is WEDGED (exit $RUNSTATE_EXIT_WEDGED)" \
    $( (( rsrc == RUNSTATE_EXIT_WEDGED )) && [[ "$rsout" == *"run-state: WEDGED"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  check "...and it says it is a state of this MAC and not to re-run" \
    $( [[ "$rsout" == *"state of this MAC"* && "$rsout" == *"do not re-run"* ]] && print 1 || print 0 ) "$rsout"
  rs_fixture="$ws/rs/sess-ok.txt"
  rs_probe rswedge
  check "CONTROL: the SAME silent run under a BALANCED session log is STALLED, never WEDGED (exit $RUNSTATE_EXIT_STALLED)" \
    $( (( rsrc == RUNSTATE_EXIT_STALLED )) && [[ "$rsout" == *"run-state: STALLED"* \
         && "$rsout" != *"run-state: WEDGED"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  check "...and STALLED tells the reader to re-sample rather than to kill it" \
    $( [[ "$rsout" == *"Do not kill it on this reading"* ]] && print 1 || print 0 ) "$rsout"

  # --- the sweep: the T-1920 half ---------------------------------------------------------------
  # An old run, with a real log, inside the same TMPDIR. The sweep must not report it and must not
  # let it near the exit code: the same real-TMPDIR measurement that found the pid-reuse bug found
  # 450 pointers, 446 of them settled weeks earlier, and a report nobody reads cannot be the thing
  # that makes a live hang visible. Naming the id explicitly still answers about it.
  print -rl -- "Command line invocation:" "half a build, then nothing" \
    > "$ws/rs/tmp/cadence-xcb-rsold.20250101-000000-1.log"
  ln -sf "cadence-xcb-rsold.20250101-000000-1.log" "$ws/rs/tmp/cadence-xcb-rsold.log"
  # No id at all, over a TMPDIR holding a wedged run and a dead one. The point is the EXIT: a
  # scheduled caller goes red without a human having to read anything, which is what T-1920's
  # three-hour hang did not have.
  rs_fixture="$ws/rs/sess-wedged.txt"
  rs_probe
  check "the id-less sweep reports every run in TMPDIR and names the wedged one" \
    $( [[ "$rsout" == *"sweep of"* && "$rsout" == *rswedge* && "$rsout" == *rsqueue* \
         && "$rsout" == *"run-state summary:"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  check "...and the sweep EXITS non-zero on the wedge, so nobody has to be watching (T-1920)" \
    $( (( rsrc == RUNSTATE_EXIT_WEDGED )) && print 1 || print 0 ) "exit $rsrc: $rsout"
  check "...and a run older than the sweep's window is left out of it entirely" \
    $( [[ "$rsout" != *rsold* ]] && print 1 || print 0 ) "$rsout"
  check "...and the refusals above carry no stray zsh assignment line (T-1074)" \
    $( print -r -- "$rsout" | grep -qE '^[a-z_][a-z_0-9]*=' && print 0 || print 1 ) "$rsout"
  rs_probe rsold
  check "...but naming that same old id explicitly still answers about it" \
    $( [[ "$rsout" == *rsold* && "$rsout" == *"run-state: "* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"

  # Only pids this selftest launched, and the children FIRST: killing the wrapper alone leaves the
  # stub xcodebuild looping forever. With its children gone the wrapper finishes its own postflight
  # and exits, which is tidier than signalling it.
  pkill -P "$rs_wedge_bg" 2>/dev/null
  wait "$rs_wedge_bg" 2>/dev/null
  # ABANDONED is a verdict about a log that EXISTS and stopped: the wedged run's log has xcodebuild
  # output in it, no terminal banner, and an owner that is now gone. Nothing in the log itself can
  # tell this from the WEDGED reading two checks ago -- the pid in its NAME is the whole difference.
  rs_fixture="$ws/rs/sess-wedged.txt"
  rs_probe rswedge
  check "a started log that stopped, whose owner is GONE, is ABANDONED (exit $RUNSTATE_EXIT_ABANDONED)" \
    $( (( rsrc == RUNSTATE_EXIT_ABANDONED )) && [[ "$rsout" == *"run-state: ABANDONED"* \
         && "$rsout" != *"run-state: WEDGED"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  pkill -P "$rs_live_bg" 2>/dev/null
  wait "$rs_live_bg" 2>/dev/null

  # --- FINISHED, and the banner that must NOT be read from the middle of a live log --------------
  local rs_done="$ws/rs/tmp/cadence-xcb-rsdone.$(date +%Y%m%d-%H%M%S)-1.log"
  print -rl -- "Command line invocation:" \
               "✔ Test aProbe() passed after 0.001 seconds." \
               "** TEST SUCCEEDED **" > "$rs_done"
  ln -sf "${rs_done:t}" "$ws/rs/tmp/cadence-xcb-rsdone.log"
  rs_probe rsdone
  check "a log carrying xcodebuild's terminal banner is FINISHED (exit $RUNSTATE_EXIT_FINISHED), not WEDGED" \
    $( (( rsrc == RUNSTATE_EXIT_FINISHED )) && [[ "$rsout" == *"run-state: FINISHED"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  # A BANNER IS NOT AN ENDING ON ITS OWN, and this pair is what caught the first version of this
  # reading: `xcodebuild` prints its terminal banner last, so a search over the log -- even over
  # its last few lines -- reads a build banner that a later phase went straight past as "this run
  # is over", and the whole point of the instrument is that it does not lie about that. The log
  # below is named after a pid that IS alive (this selftest's own) and is still growing, so the
  # honest answer is RUNNING; the banner only closes a run that has also stopped producing output.
  local rs_mid="$ws/rs/tmp/cadence-xcb-rsmid.$(date +%Y%m%d-%H%M%S)-$$.log"
  print -rl -- "Command line invocation:" "** BUILD SUCCEEDED **" > "$rs_mid"
  ln -sf "${rs_mid:t}" "$ws/rs/tmp/cadence-xcb-rsmid.log"
  ( for rs_i in {1..60}; do print -r -- "✔ Test aLater() passed after 0.001 seconds." >> "$rs_mid"; sleep 0.2; done ) &
  rs_bg=$!
  sleep 0.5
  rs_probe rsmid
  kill "$rs_bg" 2>/dev/null
  wait "$rs_bg" 2>/dev/null
  check "a GROWING log whose banner is not its ending is RUNNING, not FINISHED" \
    $( (( rsrc == RUNSTATE_EXIT_RUNNING )) && [[ "$rsout" == *"run-state: RUNNING"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"
  # The other side of the same pair, and the branch the fixture above cannot reach: a LIVE owner,
  # a banner that really is the last line, and nothing writing. That has to be FINISHED rather than
  # WEDGED or STALLED -- a run that went quiet because it ENDED is the commonest silent log there
  # is, and calling it wedged under a wedge signature it had nothing to do with is the exact lie
  # this instrument exists not to tell.
  local rs_end="$ws/rs/tmp/cadence-xcb-rsend.$(date +%Y%m%d-%H%M%S)-$$.log"
  print -rl -- "Command line invocation:" \
               "✔ Test aProbe() passed after 0.001 seconds." \
               "** TEST SUCCEEDED **" > "$rs_end"
  ln -sf "${rs_end:t}" "$ws/rs/tmp/cadence-xcb-rsend.log"
  rs_fixture="$ws/rs/sess-wedged.txt"
  rs_probe rsend
  check "...and a settled log whose banner IS its ending is FINISHED even with a live owner and the wedge signature" \
    $( (( rsrc == RUNSTATE_EXIT_FINISHED )) && [[ "$rsout" == *"run-state: FINISHED"* \
         && "$rsout" != *"run-state: WEDGED"* && "$rsout" != *"run-state: STALLED"* ]] && print 1 || print 0 ) "exit $rsrc: $rsout"


  say ""
  say " 14. this runner cannot be rewritten underneath itself (T-2085)"
  # THE REAL FAILURE, INDUCED, not a claim about `exec`. A real `xcb.sh <id> test` is started
  # against stubs, and while it is inside xcodebuild its own script file is TRUNCATED AND REWRITTEN
  # in place -- which is exactly what an editor and `open(path, "w")` do, and exactly what happened
  # to two live runs on 2026-10-06. The injection is ~900 KB, far longer than this script, so
  # wherever the running shell's read offset sits it lands INSIDE the new text rather than at EOF.
  #
  # The CONTROL is what makes it evidence: the identical scenario with the guard switched off must
  # show the injected program running. Without it these checks would pass just as well against a
  # zsh that happened to buffer the whole file, and would be proving nothing about the guard.
  local rw_out="" rw_log="" rw_control=""
  local -i rw_bg=0 rw_i=0
  mkdir -p "$ws/rw/root/scripts" "$ws/rw/tmp" "$ws/rw/ctl/scripts" "$ws/rw/ctltmp"
  print -rl -- '#!/bin/zsh' 'exit 0' > "$ws/rw/root/scripts/test-host-lock.sh"
  chmod +x "$ws/rw/root/scripts/test-host-lock.sh"
  cp -- "$ws/rw/root/scripts/test-host-lock.sh" "$ws/rw/ctl/scripts/test-host-lock.sh"
  print -rl -- '#!/bin/zsh' \
    'print -r -- "Command line invocation:"' \
    'print -r -- "✔ Test aProbe() passed after 0.001 seconds."' \
    'sleep 6' \
    'print -r -- "** TEST SUCCEEDED **"' > "$ws/rw/xcodebuild"
  chmod +x "$ws/rw/xcodebuild"
  { repeat 24000; do print -r -- 'print -r -- "INJECTED-BY-A-MID-RUN-EDIT"'; done } > "$ws/rw/inject.zsh"

  rw_rewrite_run() {  # $1 = root dir, $2 = tmp dir, $3 = id, $4 = CADENCE_XCB_NO_REEXEC value
    cp -- "$here" "$1/scripts/xcb.sh"
    XCODEBUILD="$ws/rw/xcodebuild" TMPDIR="$2/" CADENCE_STALL_POLL=1 CADENCE_XCB_NO_REEXEC="$4" \
      CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 CADENCE_ALLOW_WARNINGS= \
      zsh "$1/scripts/xcb.sh" "$3" test -scheme Cadence -destination 'platform=macOS' \
      -only-testing:CadenceTests -derivedDataPath "$2/cadence-dd-$3" >"$2/out" 2>&1 &
    rw_bg=$!
    rw_log="$2/cadence-xcb-$3.log"
    for rw_i in {1..300}; do grep -qF 'Command line invocation' "$rw_log" 2>/dev/null && break; sleep 0.2; done
    cat -- "$ws/rw/inject.zsh" > "$1/scripts/xcb.sh"     # the hostile edit, in place
    wait "$rw_bg" 2>/dev/null
  }

  rw_rewrite_run "$ws/rw/root" "$ws/rw/tmp" rwprobe ""
  rw_out="$(cat "$ws/rw/tmp/out" 2>/dev/null)"
  check "a run whose own script is REWRITTEN in place mid-run never executes the new text" \
    $( [[ "$rw_out" != *INJECTED-BY-A-MID-RUN-EDIT* ]] && print 1 || print 0 ) "$rw_out"
  check "...and still produces exactly ONE result block, not two (T-2085's measured symptom)" \
    $( [[ $(print -r -- "$rw_out" | grep -c '== xcb result') == 1 ]] && print 1 || print 0 ) "$rw_out"
  check "...and reaches its postflight, rather than stopping at a shifted EOF" \
    $( [[ "$rw_out" == *"XCODEBUILD_EXIT=0"* ]] && print 1 || print 0 ) "$rw_out"
  check "...and leaves no snapshot behind: the private copy is unlinked while it is still running" \
    $( [[ -z "$(print -r -- "$ws/rw/tmp"/cadence-xcb-self.*(N))" ]] && print 1 || print 0 ) \
    "$(print -rl -- "$ws/rw/tmp"/cadence-xcb-self.*(N))"
  # The authentic symptom, and it is a DIAGNOSTIC rather than injected output: a shifted offset
  # lands mid-token, so what the shell usually says is `xcb.sh:<line>: ...` about its own file.
  # `widgetdrop`'s run printed `./scripts/xcb.sh:3336: command not found: the`.
  check "...and no zsh diagnostic naming its own script, which is what a shifted offset produces" \
    $( [[ "$rw_out" != *"/scripts/xcb.sh:"<->* ]] && print 1 || print 0 ) "$rw_out"

  rw_rewrite_run "$ws/rw/ctl" "$ws/rw/ctltmp" rwctl 1
  rw_control="$(cat "$ws/rw/ctltmp/out" 2>/dev/null)"
  # NON-VACUITY. Without this the four checks above would pass just as well against a zsh that
  # happened to buffer the whole file, and would prove nothing about the guard. Any of the three
  # readings counts as corruption, because the shifted offset can land on a runnable line, inside a
  # quote, or past the end -- `widgetdrop` got the second, and two result blocks with it.
  check "CONTROL: with the guard off the SAME edit really does corrupt the run" \
    $( [[ "$rw_control" == *INJECTED-BY-A-MID-RUN-EDIT* || "$rw_control" == *"/scripts/xcb.sh:"<->* \
       || $(print -r -- "$rw_control" | grep -c '== xcb result') != 1 ]] && print 1 || print 0 ) "$rw_control"

  say ""
  say " 14b. the partial-scope finding reaches the RESULT BLOCK, not only the preflight (T-3080)"
  # A REAL `xcb.sh <id> test` on the production path, against a stub xcodebuild and a stub lock,
  # because the whole finding is about WHERE in a run the notice lands. Section 2 already proves
  # the preflight half fires; asserting the same string again would have passed over the defect,
  # which is that the string is printed before the build and never again. So every check below is
  # taken over the slice of the output that starts at `== xcb result`.
  local ps_out="" ps_tail=""
  local -i ps_rc=0
  mkdir -p "$ws/ps/root/scripts" "$ws/ps/tmp"
  cp -- "$here" "$ws/ps/root/scripts/xcb.sh"
  print -rl -- '#!/bin/zsh' 'exit 0' > "$ws/ps/root/scripts/test-host-lock.sh"
  chmod +x "$ws/ps/root/scripts/test-host-lock.sh"
  # Identity labels, so the stub log can spell the suites by type name and section 9's guard stays
  # satisfied for whichever of them the run requested.
  print -rl -- $'AlphaTests\tAlphaTests' \
               $'AlphaHelperTests\tAlphaHelperTests' \
               $'SoloTests\tSoloTests' > "$ws/ps/labels.tsv"
  # BOTH suites start in the log, deliberately: the run that asks for one of them must still be
  # told about the other, and reading the log for that answer would get it wrong here.
  print -rl -- '#!/bin/zsh' \
    'print -r -- "Command line invocation:"' \
    'print -r -- "Suite AlphaTests started."' \
    'print -r -- "✔ Test somethingReal() passed after 0.001 seconds."' \
    'print -r -- "Suite AlphaHelperTests started."' \
    'print -r -- "✔ Test aHelper() passed after 0.001 seconds."' \
    'print -r -- "** TEST SUCCEEDED **"' > "$ws/ps/xcodebuild"
  chmod +x "$ws/ps/xcodebuild"
  ps_run() {   # $@ = the -only-testing: flags under test
    XCODEBUILD="$ws/ps/xcodebuild" TMPDIR="$ws/ps/tmp/" CADENCE_STALL_POLL=1 CADENCE_SKIP_IOS_LEG=1 \
      CADENCE_SUITE_FILES="$ws/index.tsv" CADENCE_SUITE_LABELS="$ws/ps/labels.tsv" \
      CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 CADENCE_ALLOW_AUTOMATION_PROMPT=1 CADENCE_ALLOW_WARNINGS= \
      zsh "$ws/ps/root/scripts/xcb.sh" psprobe test -scheme Cadence -destination 'platform=macOS' \
      "$@" -derivedDataPath "$ws/ps/tmp/cadence-dd-psprobe" >"$ws/ps/out" 2>&1
    ps_rc=$?
    ps_out="$(cat "$ws/ps/out" 2>/dev/null)"
    ps_tail="$(print -r -- "$ps_out" | sed -n '/== xcb result/,$p')"
  }

  ps_run -only-testing:CadenceTests/AlphaTests
  check "a green scoped run says PARTIAL-SCOPE-UNRUN in its RESULT block, not just its preflight" \
    $( [[ "$ps_tail" == *PARTIAL-SCOPE-UNRUN* ]] && print 1 || print 0 ) "$ps_out"
  check "...and the result block names the skipped sibling, its count and its file" \
    $( [[ "$ps_tail" == *AlphaHelperTests* && "$ps_tail" == *"(7 tests)"* && "$ps_tail" == *AlphaTests.swift* ]] && print 1 || print 0 ) "$ps_tail"
  check "...and quotes this run's own result-line count beside it, so the two are read together" \
    $( [[ "$ps_tail" == *"test result lines: 2"* && "$ps_tail" == *"result lines: 2\" then describes a fraction"* ]] && print 1 || print 0 ) "$ps_tail"
  # NON-VACUITY, and the reason this check is not redundant with the first: the fix must ADD a
  # reading, not move the preflight one down past the forty-minute lock queue it exists to avoid.
  check "...while the PREFLIGHT half still fires before the build, exactly once" \
    $( [[ $(print -r -- "$ps_out" | grep -c 'PARTIAL-SCOPE (T-1076)') == 1 \
       && $(print -r -- "$ps_out" | sed -n '1,/== xcb result/p' | grep -c 'PARTIAL-SCOPE (T-1076)') == 1 ]] && print 1 || print 0 ) "$ps_out"
  check "...and it REPORTS rather than gates: the run still exits 0 (T-1076's decision, re-taken)" \
    $( (( ps_rc == 0 )) && [[ "$ps_tail" == *"XCODEBUILD_EXIT=0"* ]] && print 1 || print 0 ) "exit $ps_rc: $ps_tail"
  # The control that keeps it from becoming noise. Without it, a restatement printed on every run
  # would pass every check above and would be scrolled past within a week.
  ps_run -only-testing:CadenceTests/AlphaTests -only-testing:CadenceTests/AlphaHelperTests
  check "CONTROL: a file scoped in FULL says nothing, in the result block or anywhere else" \
    $( (( ps_rc == 0 )) && [[ "$ps_out" != *PARTIAL-SCOPE* ]] && print 1 || print 0 ) "exit $ps_rc: $ps_out"

  say ""
  say " 15. the test-host lease ends with the primary run, not with the postflight (T-2086)"
  # A real `xcb.sh <id> test` against a stub lock whose `release` records WHERE IN THE RUN'S OWN
  # OUTPUT it was called: whether the result block had started, and whether the closing release-dd
  # hint (the last thing a run prints) was already out. The iOS leg is carved out, so the only
  # releases left are the early one and the EXIT trap -- an early release removed reads end=1.
  local lh_out="" lh_calls=""
  mkdir -p "$ws/lh/root/scripts" "$ws/lh/tmp"
  cp -- "$here" "$ws/lh/root/scripts/xcb.sh"
  print -rl -- '#!/bin/zsh' \
    'if [[ "$1" == release ]]; then' \
    '  r=0; e=0' \
    '  grep -qF "== xcb result" "$FAKE_LEASE_OUT" 2>/dev/null && r=1' \
    '  grep -qF "when you are done" "$FAKE_LEASE_OUT" 2>/dev/null && e=1' \
    '  print -r -- "release $2 result=$r end=$e" >> "$FAKE_LEASE_CALLS"' \
    '  [[ -n "${FAKE_LEASE_REFUSE:-}" ]] && { print -r -- "REFUSING: stub"; exit 1 }' \
    'fi' \
    'exit 0' > "$ws/lh/root/scripts/test-host-lock.sh"
  chmod +x "$ws/lh/root/scripts/test-host-lock.sh"
  print -rl -- '#!/bin/zsh' \
    'print -r -- "Command line invocation:"' \
    'print -r -- "✔ Test aProbe() passed after 0.001 seconds."' \
    'print -r -- "** TEST SUCCEEDED **"' > "$ws/lh/xcodebuild"
  chmod +x "$ws/lh/xcodebuild"
  lh_run() {  # $1 = FAKE_LEASE_REFUSE value
    : > "$ws/lh/calls"; : > "$ws/lh/out"
    XCODEBUILD="$ws/lh/xcodebuild" TMPDIR="$ws/lh/tmp/" CADENCE_STALL_POLL=1 CADENCE_SKIP_IOS_LEG=1 \
      FAKE_LEASE_OUT="$ws/lh/out" FAKE_LEASE_CALLS="$ws/lh/calls" FAKE_LEASE_REFUSE="$1" \
      CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 CADENCE_ALLOW_WARNINGS= \
      zsh "$ws/lh/root/scripts/xcb.sh" lhprobe test -scheme Cadence -destination 'platform=macOS' \
      -only-testing:CadenceTests -derivedDataPath "$ws/lh/tmp/cadence-dd-lhprobe" >"$ws/lh/out" 2>&1
    lh_out="$(cat "$ws/lh/out" 2>/dev/null)"; lh_calls="$(cat "$ws/lh/calls" 2>/dev/null)"
  }
  lh_run ""
  check "the lease is released ONCE, before the result block is printed (exit trap disarmed)" \
    $( [[ "$lh_calls" == "release xcb-lhprobe result=0 end=0" ]] && print 1 || print 0 ) "calls: $lh_calls"
  check "...and the result block says so" \
    $( [[ "$lh_out" == *"test-host lock: released when xcodebuild exited"* && "$lh_out" == *"XCODEBUILD_EXIT=0"* ]] && print 1 || print 0 ) "$lh_out"
  lh_run 1
  check "a refused early release leaves the exit trap armed: it is retried after the whole postflight" \
    $( [[ "$lh_calls" == $'release xcb-lhprobe result=0 end=0\nrelease xcb-lhprobe result=1 end=1' \
         && "$lh_out" == *"test-host lock: NOT released early (REFUSING: stub)"* ]] && print 1 || print 0 ) "calls: $lh_calls | $lh_out"

  say ""
  say " 16. the drift check is asked again once the test-host lock is held (T-3060)"
  # A real `xcb.sh <id> test` from a scratch git checkout whose stub lock's `acquire` plays the
  # sibling that lands work during the wait, and whose stub xcodebuild can play one that edits
  # mid-run. The stub drift check answers BEHIND-HEAD exactly while a marker file exists.
  local dl_out="" dl_rc=0 dl_calls="" dl_sha=""
  mkdir -p "$ws/dl/root/scripts" "$ws/dl/tmp" "$ws/dl/state"
  cp -- "$here" "$ws/dl/root/scripts/xcb.sh"
  print -rl -- '#!/bin/zsh' \
    'print -r -- "$1" >> "$FAKE_LOCK_CALLS"' \
    'if [[ "$1" == acquire ]]; then' \
    '  [[ "$FAKE_DURING_WAIT" == edit ]] && print -r -- "landed during the wait" >> "$FAKE_PROBE"' \
    '  [[ "$FAKE_DURING_WAIT" == behind ]] && : > "$FAKE_BEHIND"' \
    'fi' \
    'exit 0' > "$ws/dl/root/scripts/test-host-lock.sh"
  print -rl -- '#!/bin/zsh' \
    'if [[ -e "$FAKE_BEHIND" ]]; then print -r -- "WORKTREE-BEHIND-HEAD: probe.txt"; exit 3; fi' \
    'print -r -- "worktree matches HEAD"' > "$ws/dl/root/scripts/worktree-drift.sh"
  print -rl -- '#!/bin/zsh' \
    'print -r -- built >> "$FAKE_LOCK_CALLS"' \
    '[[ -n "$FAKE_MIDRUN_EDIT" ]] && print -r -- "edited mid-run" >> "$FAKE_PROBE"' \
    'print -r -- "Command line invocation:"' \
    'print -r -- "✔ Test aProbe() passed after 0.001 seconds."' \
    'print -r -- "** TEST SUCCEEDED **"' > "$ws/dl/xcodebuild"
  chmod +x "$ws/dl/root/scripts/test-host-lock.sh" "$ws/dl/root/scripts/worktree-drift.sh" "$ws/dl/xcodebuild"
  print -r -- probe > "$ws/dl/root/probe.txt"
  git -C "$ws/dl/root" init -q
  git -C "$ws/dl/root" add -A
  git -C "$ws/dl/root" -c user.name=selftest -c user.email=selftest@invalid -c core.hooksPath=/dev/null \
    commit -qm probe
  dl_sha="$(git -C "$ws/dl/root" rev-parse HEAD)"
  dl_run() {  # $1 = FAKE_DURING_WAIT, $2 = FAKE_MIDRUN_EDIT
    git -C "$ws/dl/root" checkout -q -- probe.txt
    rm -f "$ws/dl/behind" "$ws/dl/state"/cadence-xcb-last-green.*(N)
    : > "$ws/dl/calls"
    XCODEBUILD="$ws/dl/xcodebuild" TMPDIR="$ws/dl/tmp/" CADENCE_STALL_POLL=1 CADENCE_SKIP_IOS_LEG=1 \
      CADENCE_XCB_STATE_DIR="$ws/dl/state" CADENCE_TREE_ROOT= FAKE_LOCK_CALLS="$ws/dl/calls" \
      FAKE_PROBE="$ws/dl/root/probe.txt" FAKE_BEHIND="$ws/dl/behind" FAKE_DURING_WAIT="$1" FAKE_MIDRUN_EDIT="$2" \
      CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 CADENCE_ALLOW_WARNINGS= \
      zsh "$ws/dl/root/scripts/xcb.sh" dlprobe test -scheme Cadence -destination 'platform=macOS' \
      -only-testing:CadenceTests -derivedDataPath "$ws/dl/tmp/cadence-dd-dlprobe" >"$ws/dl/out" 2>&1
    dl_rc=$?
    dl_out="$(cat "$ws/dl/out" 2>/dev/null)"; dl_calls="$(cat "$ws/dl/calls" 2>/dev/null)"
  }
  dl_run "" ""
  check "a still tree is answered twice -- at preflight and again with the lock held -- and warns of nothing" \
    $( [[ $dl_rc == 0 && $(print -r -- "$dl_out" | grep -c 'worktree vs HEAD.*: worktree matches HEAD') == 2 \
         && "$dl_out" == *"worktree vs HEAD (asked again, test-host lock held): worktree matches HEAD"* \
         && "$dl_out" != *"tree changed"* && "$dl_out" == *"last-green: recorded ${dl_sha} (tree clean)"* ]] \
         && print 1 || print 0 ) "exit $dl_rc: $dl_out"
  dl_run edit ""
  check "a tree edited during the lock wait says 'tree changed while waiting', not 'during this run'" \
    $( [[ $dl_rc == 0 && "$dl_out" == *"tree changed while waiting for the test-host lock (T-3060): ${dl_sha} clean -> ${dl_sha} "* \
         && "$dl_out" != *"tree changed during this run"* ]] && print 1 || print 0 ) "exit $dl_rc: $dl_out"
  dl_run behind ""
  check "a checkout that fell behind HEAD during the wait is REFUSED with the lock held: exit 7, nothing built, lock given back" \
    $( [[ $dl_rc == 7 && "$dl_out" == *"fell behind HEAD while this run waited for the test-host lock"* \
         && "$dl_calls" == $'acquire\nrelease' ]] && print 1 || print 0 ) "exit $dl_rc, calls: $dl_calls | $dl_out"
  dl_run "" 1
  check "a tree edited mid-run says 'tree changed during this run' and records no last-green" \
    $( [[ $dl_rc == 0 && "$dl_out" == *"tree changed during this run (T-3060): ${dl_sha} clean -> ${dl_sha} "* \
         && "$dl_out" == *"last-green: not recorded -- the tree changed during the run"* \
         && -z "$(print -r -- "$ws/dl/state"/cadence-xcb-last-green.*(N))" ]] && print 1 || print 0 ) "exit $dl_rc: $dl_out"

  rm -rf "$ws"
  say ""
  # A tally derived from the checks that actually ran: a selftest gutted to `return 0` still exits
  # 0, but it cannot print a non-zero passed count.
  say "checks: $(( ${#performed} - ${#failures} )) passed, ${#failures} failed"
  if (( ${#failures} )); then
    say "SELFTEST FAILED: ${(j:, :)failures}"
    return 1
  fi
  say "SELFTEST PASSED"
  return 0
}

if [[ "${1:-}" == "check-test-log" ]]; then
  CHECK_LOG="${2:-}"
  if [[ ! -f "$CHECK_LOG" ]]; then
    say "usage: ./scripts/xcb.sh check-test-log <logfile> [xcodebuild-exit]"; exit 2
  fi
  CHECK_RAN=$(tests_seen "$CHECK_LOG")
  if (( CHECK_RAN == 0 )); then
    EMPTY_RUN_EXIT="${3:-}" empty_run_diagnostic "$CHECK_LOG"
    exit 4
  fi
  say "$CHECK_RAN test result(s) in $CHECK_LOG"
  exit 0
fi

# The per-suite guard on its own (T-1326), the way `check-test-log` exposes the zero-test guard, and
# for the reason that one is exposed: a guard reachable only through a 20-minute build is a guard
# whose own selftest has to fake the build, and the thing this one gets wrong is which of its two
# inputs it trusts. The arguments go on the command line exactly as they would to a real run, so
# what the selftest drives is the production reading and not a copy of it.
if [[ "${1:-}" == "check-suites-started" ]]; then
  shift
  CHECK_LOG="${1:-}"
  if [[ ! -f "$CHECK_LOG" ]]; then
    say "usage: ./scripts/xcb.sh check-suites-started <logfile> [the run's own args...]"; exit 2
  fi
  shift
  CHECK_RAN=$(tests_seen "$CHECK_LOG")
  say "== xcb per-suite guard ($CHECK_LOG) =="
  say "  test result lines: $CHECK_RAN"
  suite_started_guard "$CHECK_LOG" "$CHECK_RAN" "$@"
  exit $?
fi

# The counters on their own, the way `check-test-log` exposes the zero-test guard. It is what
# `selftest` drives -- a banner nothing can run without paying for a build is a banner nobody
# tests -- and it is how a caller reads the numbers back off a log some earlier run produced.
if [[ "${1:-}" == "check-warnings" ]]; then
  CHECK_LOG="${2:-}"
  if [[ ! -f "$CHECK_LOG" ]]; then
    say "usage: ./scripts/xcb.sh check-warnings <logfile>"; exit 2
  fi
  say "== xcb diagnostics ($CHECK_LOG) =="
  # Exits with the gate's own status (T-1149), so this subcommand IS the gate and not a prettier
  # `grep`: anything holding a log -- CI, a coordinator sweeping a batch's logs, this script's own
  # selftest -- enforces the baseline by running it and reading the exit code.
  diagnostic_report "$CHECK_LOG"
  exit $?
fi

# The interactive-skip report on its own (T-1741), for the two reasons `check-warnings` is
# exposed: it is what `selftest` drives, and it lets anyone holding a UI-test log ask what that
# run did not execute without re-running it. It never gates, so it always exits 0.
if [[ "${1:-}" == "check-interactive-skips" ]]; then
  CHECK_LOG="${2:-}"
  if [[ ! -f "$CHECK_LOG" ]]; then
    say "usage: ./scripts/xcb.sh check-interactive-skips <logfile>"; exit 2
  fi
  interactive_skip_report "$CHECK_LOG"
  exit 0
fi

# The mid-run locked-screen report on its own (T-1890), for the same two reasons: it is what
# `selftest` drives -- against `CADENCE_SESSION_FIXTURE`, since the live condition cannot be
# induced without locking the host's screen out from under a run -- and it lets anyone holding a
# run's start time ask whether the screen went out underneath it. It never gates, so it exits 0.
if [[ "${1:-}" == "check-screen-lock-window" ]]; then
  if [[ -z "${2:-}" ]]; then
    say "usage: ./scripts/xcb.sh check-screen-lock-window <run-start-epoch-seconds> [the run's own args...]"; exit 2
  fi
  screen_lock_report "$2" "${@:3}"
  exit 0
fi

# The refused-host-relaunch report on its own (T-1992): what `selftest` drives, and how anyone
# holding a red run's log asks whether its host was refused a relaunch. Never gates; exits 0.
if [[ "${1:-}" == "check-host-launch" ]]; then
  CHECK_LOG="${2:-}"
  if [[ ! -f "$CHECK_LOG" ]]; then
    say "usage: ./scripts/xcb.sh check-host-launch <logfile> [xcodebuild-exit]"; exit 2
  fi
  host_launch_refusal_report "$CHECK_LOG" "${3:-}"
  exit 0
fi

# The poisoned-DerivedData report on its own (T-2046): what `selftest` drives, and how anyone
# holding a red log that compiled nothing asks whether it is this. Never gates; exits 0.
if [[ "${1:-}" == "check-entitlements" ]]; then
  CHECK_LOG="${2:-}"
  if [[ ! -f "$CHECK_LOG" ]]; then
    say "usage: ./scripts/xcb.sh check-entitlements <logfile> [xcodebuild-exit] [derived-data-path]"; exit 2
  fi
  entitlements_poisoned_dd_report "$CHECK_LOG" "${3:-}" "${4:-}"
  exit 0
fi

# The automation-prompt probe on its own (T-2070): what `selftest` drives (with
# CADENCE_AUTOMATION_LOG_FIXTURE), and what an agent staring at a run that died at ~445s -- or at
# a whole batch of them -- asks before blaming a tree. Exits 0 on a healthy host and
# $AUTOMATION_PROMPT_EXIT while a prompt is outstanding, so it is scriptable as well as readable.
if [[ "${1:-}" == "check-automation" ]]; then
  autom_counts=( ${=$(automation_prompt_counts)} )
  autom_out=$(automation_prompt_outstanding)
  say "automation prompt: requests=${autom_counts[1]} granted=${autom_counts[2]} outstanding=$autom_out"
  autom_verdict=$(automation_prompt_verdict)
  if [[ "$autom_verdict" == STANDING ]]; then
    say "  hanging test sessions: $(runstate_transport_outstanding) (connected, never given transport)"
    automation_prompt_refusal
    exit $AUTOMATION_PROMPT_EXIT
  fi
  if [[ "$autom_verdict" == UNMATCHED ]]; then
    say "  hanging test sessions: $(runstate_transport_outstanding) -- nothing is hanging, so this does NOT gate."
    automation_prompt_note
    exit 0
  fi
  say "  HEALTHY -- no unanswered \"Enable UI Automation\" prompt in the window."
  exit 0
fi

# The slept-through-it report on its own (T-2048): what `selftest` drives (with
# CADENCE_PMSET_LOG_FIXTURE), and how anyone holding a red run's start/end asks whether the Mac
# slept in between. Never gates; exits 0.
if [[ "${1:-}" == "check-sleep" ]]; then
  if [[ "${2:-}" != <-> || "${3:-}" != <-> ]]; then
    say "usage: ./scripts/xcb.sh check-sleep <start-epoch> <end-epoch> [xcodebuild-exit]"; exit 2
  fi
  system_sleep_report "$2" "$3" "${4:-}"
  exit 0
fi

# The resolver on its own, the way `check-test-log` exposes the zero-test guard: it is what
# `selftest` drives, and what a caller can point at a filter it is unsure of without paying for a
# build. Accepts the value with or without the `-only-testing:` prefix.
if [[ "${1:-}" == "check-only-testing" ]]; then
  shift
  if (( $# == 0 )); then
    say "usage: ./scripts/xcb.sh check-only-testing <CadenceTests/Suite>..."; exit 2
  fi
  resolve_only_testing "${@#-only-testing:}"
  exit $?
fi

# The destination guard on its own, for the same two reasons `check-only-testing` is exposed: it
# is what `selftest` drives, and it answers "does this Mac have that simulator" for a caller that
# would otherwise find out by reading a vacuous build log. Accepts the value with or without the
# `-destination` flag in front of it.
# The selection question on its own (T-1933), for the two reasons `check-only-testing` is exposed:
# it is what `selftest` drives, and it lets a caller staring at a refused run -- or at a 13-minute
# queue for the test host -- ask why without paying for a build. It exits 0 when the selection can
# reach a test that launches an app and 1 when it provably cannot, so it is scriptable as well as
# readable. Accepts the values with or without the `-only-testing:` prefix.
if [[ "${1:-}" == "check-ui-selection" ]]; then
  shift
  if selection_launches_an_app "${@#-only-testing:}"; then
    say "ui selection: LAUNCHES-AN-APP -- refused while the screen is locked, and it takes the test-host lock."
    exit 0
  fi
  say "ui selection: SCREEN-FREE -- every named suite is screen-free, so a locked screen does not"
  say "  refuse it and no test-host lease is taken for it (T-1933)."
  exit 1
fi

if [[ "${1:-}" == "check-destination" ]]; then
  shift
  if (( $# == 0 )); then
    say "usage: ./scripts/xcb.sh check-destination 'platform=iOS Simulator,name=<device>'..."; exit 2
  fi
  resolve_destinations "${@:#-destination}"
  exit $?
fi

# The three-way discriminator on its own (T-2071), and the sweep that makes silence visible
# without a human noticing it (T-1920). With an id it answers about that run; with no id it
# answers about every run this TMPDIR knows about and exits non-zero if any of them is WEDGED or
# ABANDONED, which is what lets a scheduled caller go red instead of a reader having to look.
# Exits: 0 RUNNING, 10 QUEUED, 11 WEDGED, 12 FINISHED, 13 STALLED, 14 ABANDONED, 15 NO-LOG.
if [[ "${1:-}" == "run-state" ]]; then
  shift
  run_state_report "$@"
  exit $?
fi

# The last full green on its own (T-2042): what a heartbeat asks before paying 16 minutes to re-run
# an unchanged tree. 0 UNCHANGED, 1 CHANGED, 3 NO-RECORD.
if [[ "${1:-}" == "last-green" ]]; then
  last_green_report "${CADENCE_TREE_ROOT:-$ROOT_DIR}"
  exit $?
fi

# The delete the result block points at (T-2042). It takes an id or a path, deletes only a
# `cadence-dd-*` directory, and refuses -- exit 12, naming the pids -- while a live xcodebuild
# names that path, or when the process list cannot be read to prove it does not.
if [[ "${1:-}" == "release-dd" ]]; then
  if [[ -z "${2:-}" ]]; then
    say "usage: ./scripts/xcb.sh release-dd <id|derived-data-path>"; exit 2
  fi
  RDD="$2"
  [[ "$RDD" == */* ]] || RDD="${TMP_BASE}cadence-dd-$RDD"
  if [[ "${RDD:t}" != cadence-dd-* ]]; then
    say "REFUSING: '$RDD' is not a cadence-dd-* DerivedData; release-dd deletes nothing else."; exit 2
  fi
  RDD_USERS="$(dd_live_users "$RDD")"; RDD_RC=$?
  if (( RDD_RC != 0 )); then
    say "REFUSING: could not read the process list, so nothing proves $RDD is free. Not deleted."
    exit $DD_IN_USE_EXIT
  fi
  if [[ -n "$RDD_USERS" ]]; then
    say "!! REFUSING: DD-IN-USE (T-2042): live xcodebuild pid(s) ${(j:, :)${(f)RDD_USERS}} build into $RDD."
    say "   Deleting it now would pull it out from under that run. Not deleted."
    exit $DD_IN_USE_EXIT
  fi
  if [[ ! -e "$RDD" ]]; then
    say "release-dd: $RDD does not exist; nothing to delete."; exit 0
  fi
  rm -rf -- "$RDD"
  say "release-dd: deleted $RDD (no live xcodebuild named it)."
  exit 0
fi

if [[ "${1:-}" == "selftest" ]]; then
  selftest_only_testing
  exit $?
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
# --- the per-invocation log (T-747) ------------------------------------------
# One id, several runs: the runbook shape is "one script, one lock, several runs"
# -- acquire once, then call `xcb.sh <id> test ...` two or three times in a row.
# A log path keyed on `$ID` alone is overwritten by the second call, so a runner
# doing exactly that ends holding only the LAST run's evidence; the postflight
# counters above survive because they go to stdout, but they are aggregates, and
# an aggregate cannot be attributed back to the log that produced it once that log
# is gone. Each invocation gets its own file -- a timestamp is not enough on its
# own to be collision-proof (two calls in the same second), so `$$` (this
# process's own pid, unique among concurrent invocations) is appended too -- and
# `$LOG_LATEST` keeps the documented, unsuffixed path alive as a symlink to
# whichever run is newest, so a caller that only knows the old path still finds
# something, and finds the RIGHT something.
LOG_LATEST="${TMP_BASE}cadence-xcb-$ID.log"
LOG="${TMP_BASE}cadence-xcb-$ID.$(date +%Y%m%d-%H%M%S)-$$.log"
ln -sf "${LOG:t}" "$LOG_LATEST" 2>/dev/null

# --- preflight ---------------------------------------------------------------
say "== xcb preflight ($ID) =="
say "  derivedDataPath: $DD"
say "  log:             $LOG"
say "  log (latest):    $LOG_LATEST -> ${LOG:t}"
# Anchored, and matching the binary path: an unanchored `pgrep -f xcodebuild` counts this script
# and every wait loop whose own command text spells the word.
others=$(pgrep -f '^/Applications/.*/xcodebuild' 2>/dev/null | grep -vx "$$" | wc -l | tr -d ' ')
say "  other xcodebuild processes: $others"
# Before anything else is paid for: a second build into a live one's DerivedData (T-2042).
dd_in_use_refusal "$DD" "preflight" && exit $DD_IN_USE_EXIT
# And before anything else is paid for a SECOND time: a DerivedData an earlier run marked poisoned
# (T-2046). Twelve minutes to rediscover a permanent fact about a directory is the whole cost this
# guard exists to stop, and it is checked here -- ahead of the suite resolver, the destination
# resolver and the test-host lease -- because none of those questions matter about a tree that
# cannot link.
entitlements_poisoned_dd_refusal "$DD" && exit $ENTITLEMENTS_POISONED_EXIT
if (( $(pgrep -x Xcode 2>/dev/null | wc -l) > 0 )); then
  say "  WARNING: Xcode is running. T-117's mitigation is to quit it while a batch of agents"
  say "           builds; an open project is a standing claimant on Cadence.xcodeproj."
fi
before_entries="$(shared_cadence_entries)"

# --- what this run SELECTS, read before the guards that depend on it ---------
# Parsed here rather than beside `resolve_only_testing` below, because two guards between here and
# there now need it (T-1933): a selection is what says whether this run can reach a test that
# launches an app, and both the locked-screen refusal and the test-host lease turn on that one
# fact. The resolver itself still runs where it did -- it is a separate, more expensive question
# (does this name match a suite at all) and it is answered after the cheap refusals.
only_testing=()
for (( i = 1; i <= ${#args}; i++ )); do
  case "${args[i]}" in
    -only-testing:*) only_testing+=("${args[i]#-only-testing:}") ;;
    -only-testing)   only_testing+=("${args[i+1]:-}") ;;
  esac
done

# --- the locked-screen guard (T-563) -----------------------------------------
# A UI test cannot activate an app while the Mac's screen is locked: `loginwindow` owns the
# foreground, the app XCUITest launches stays `Running Background`, and `app.launch()` gives up
# about a minute later with "Failed to activate application ... (current state: Running
# Background)". That failure lands on whichever line called launch(), so nothing downstream runs
# and the run reads as a code regression -- which is the whole of the "flaky about 1 run in 5" this
# target was documented as having. Measured 2026-09-02 either side of one lock event at 17:48:12:
# 20 runs / 40 launches before it with zero activation failures, and 100% failure after it.
#
# The tests skip themselves in this state (CadenceUITestEnvironment), so the run is not a false red.
# It is refused here as well because a skipped-out run then trips the zero-test guard below, and
# that guard's advice -- "-only-testing: takes a SUITE name" -- would be confidently wrong here.
# Refused BEFORE the lock: a run that cannot pass must not hold the host while it fails.
# No pipe, deliberately. `ioreg ... | grep -q` returns **141** under `set -o pipefail`: grep exits
# the moment it matches, ioreg takes SIGPIPE, and pipefail reports the pipeline as that signal --
# so the probe answers "not locked" precisely when it *did* find the key. Measured while writing
# this guard, which is the same shape as the assert-toolchain.sh incident in the runbook: the
# probe's own plumbing eating the finding.
screen_is_locked() {
  [[ "$(ioreg -n Root -d1 -k IOConsoleUsers 2>/dev/null)" == *'"CGSSessionScreenIsLocked"=Yes'* ]]
}
# CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 exists so this guard can be *tested* -- a guard nobody can
# exercise is the hollow-instrument shape this repo keeps catching. It is not a way to get a UI run
# out of a locked Mac, and there is no spelling of it that makes an app reach the foreground.
# ITS OLD COMMENT SAID "with it set the tests skip instead". THAT IS FALSE FOR AT LEAST ONE SUITE
# (T-1933): `CadenceOverdrawVerdictTests` carries no skip at all, so under that variable it RUNS --
# and what happens then is the measurement below. The sentence was true of the suites the guard was
# written against and was never re-read when the target grew one that launches nothing.
#
# THE CONDITION STAYS PER-TARGET, AND T-1933'S PROPOSAL THAT IT SHOULD NOT IS REFUTED BY MEASUREMENT.
# The ticket argued -- reasonably, and this script's author believed it -- that the string match is
# too coarse: `CadenceOverdrawVerdictTests` launches no app, takes no pointer and reads no screen,
# so it was called "exactly the suite an agent still needs when the Mac has locked", and the guard
# was changed to decide per suite. Measured 2026-10-02 on a Mac locked at 01:22:41, that selection
# built clean (1095 compile tasks, 0 warnings) and then executed **0 tests**:
#
#     Testing failed:
#       CadenceUITests-Runner (82754) encountered an error (The test runner failed to initialize
#       for UI testing. (Underlying Error: Authentication canceled. System authentication is
#       running.))
#
# THE BLOCK IS NOT `app.launch()`. It is the UI-test RUNNER, which is itself an app and cannot
# initialize while loginwindow is holding an authentication session -- so it stops every suite in
# the target, including the ones that launch nothing of their own. T-563 described the right
# refusal by the wrong mechanism, and describing it by the wrong mechanism is what made the
# per-suite exemption look obviously correct. The A/B is clean: the SAME selection, the SAME tree,
# ran 10 result lines unlocked six hours earlier and 0 locked.
#
# So the coarse reading is the right one and it is now the measured one. What a per-suite exemption
# would buy is a five-minute build followed by `** TEST FAILED **` and -- worse -- the zero-test
# guard's advice, which would confidently tell the reader that `-only-testing:` takes a suite name.
# That is the exact misdiagnosis this guard's own comment warned about two paragraphs down.
#
# The selection reading `selection_launches_an_app` still exists and is still used: by the
# TEST-HOST LEASE below, which is a question about T-236's app-group container and not about the
# screen. Two decisions, one of which turned out to depend on the selection and one of which does
# not -- which is only knowable by measuring both.
if screen_is_locked && [[ "${args[*]}" == *CadenceUITests* ]] \
   && [[ "${CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN:-}" != "1" ]]; then
  say ""
  say "!! REFUSING: the screen is locked, and NO suite in CadenceUITests can run while it is --"
  say "   not even one that launches no app of its own (T-1933, measured 2026-10-02)."
  say "   The UI-test RUNNER is itself an app and cannot initialize: \"The test runner failed to"
  say "   initialize for UI testing. (Underlying Error: Authentication canceled. System"
  say "   authentication is running.)\" -- so the run builds for five minutes and executes 0 tests."
  say "   Unlock the screen and re-run (T-563)."
  exit 5
fi

# --- the unanswered automation-prompt guard (T-2070) -------------------------
# Costs 2.3s, measured on this Mac 2026-10-07 with the scoped predicate -- against a `test` action
# that is about to spend minutes building and then queue for the test host, and against the 445s
# per run plus 3h11m of wedged host that T-2067 paid for not asking. Only `test` runs ask: a
# `build` is unaffected by an outstanding prompt, and refusing one would be a lie about the host.
# Placed after the locked-screen refusal and before the test-host lease, for that guard's reason:
# a run that cannot pass must not hold the host while it fails.
run_is_a_test_action() {
  [[ "$ACTION" == "test" ]] && return 0
  [[ "$ACTION" == "raw" && " ${args[*]} " == *" test "* ]] && return 0
  return 1
}
if run_is_a_test_action && [[ "${CADENCE_ALLOW_AUTOMATION_PROMPT:-}" != "1" ]]; then
  case "$(automation_prompt_verdict)" in
    STANDING)  automation_prompt_refusal; exit $AUTOMATION_PROMPT_EXIT ;;
    UNMATCHED) automation_prompt_note ;;
  esac
fi

# --- resolve -only-testing: before anything expensive (T-1076) ---------------
# Ahead of the drift check and the test-host lock on purpose. A name that selects nothing costs
# a full build to discover through the zero-test guard, and a `test` action queues behind a lock
# that has been reaching forty minutes; neither is worth paying to learn that a suite is misspelt.
# (The flags themselves are parsed further up, where the locked-screen guard needs them.)
if (( ${#only_testing} )); then
  resolve_only_testing "${only_testing[@]}" || exit 8
fi

# --- resolve -destination before anything expensive (T-1282) -----------------
# Beside the resolver above and for the same reason: a destination that matches no device costs a
# whole build to discover, and what it produces then is not a red -- it is `compile errors: 0` over
# zero compiled files. Every action is checked, `raw` included: the measured fake pass was a
# `raw ... build`, and this question is about the Mac rather than about the tree, so a scratch tree
# or a mutation run is answered exactly as the checkout is.
destinations=()
for (( i = 1; i <= ${#args}; i++ )); do
  case "${args[i]}" in
    -destination=*) destinations+=("${args[i]#-destination=}") ;;
    -destination)   destinations+=("${args[i+1]:-}") ;;
  esac
done
if (( ${#destinations} )); then
  resolve_destinations "${destinations[@]}" || exit $SIMULATOR_GATE_EXIT
fi

# --- the drifted-worktree guard (T-975) --------------------------------------
# `agent-commit.sh` commits through a private index, so a landed commit never writes the shared
# checkout -- deliberately, because writing it would clobber a sibling mid-edit. The cost is that
# the checkout drifts behind HEAD and NOTHING SAYS SO: `git status` prints ` M <path>` for a stale
# copy exactly as it does for real in-flight work. Measured four times between 2026-09-04 and
# 2026-09-05; the worst instance had `docs/TODO.md` five ticket ids behind and a test file 101
# lines behind a fix already committed, with an integration run already launched against it.
#
# So a `test` action asks first, and the reasoning is the locked-screen guard's: a run that cannot
# be trusted must not hold the test host while it produces an answer about the wrong code.
# `build` is not gated -- a build tells you about the files you handed it, and an agent that has
# deliberately not synced a sibling's landed change still needs to compile its own.
# `raw` is not gated either, and that is load-bearing: `mutate.sh` runs `raw test` inside a scratch
# tree it has deliberately mutated (and which may not be a git checkout at all), so gating `raw`
# would refuse every mutation run whose needle deletes lines.
#
# Only WORKTREE-BEHIND-HEAD refuses, and that distinction is load-bearing rather than tidy. The
# standing advice for a batch is to build in a `git archive HEAD` tree, which has no `.git` at all,
# so the check there answers NOT-REPO-ROOT -- *a question that could not be asked*. Refusing on
# that would refuse the very workflow the runbook prescribes. A guard that cannot answer says so
# and gets out of the way; only a real, positive finding stops the run.
#
# ASKED TWICE (T-3060). The preflight answer is about the tree as it was BEFORE the lock queue,
# and that queue has reached forty minutes: observed 2026-10-08, a heartbeat run printed
# "worktree matches HEAD", waited 555 s behind a sibling that committed during the wait, compiled
# the half-edited tree and went red with nothing saying the tree had moved. So a run that took the
# lock asks again once it holds it, with the same verdicts -- WORKTREE-BEHIND-HEAD refuses (exit 7,
# the EXIT trap gives the lock back), anything else is printed and the run proceeds -- and it
# compares the git fingerprint (`tree_fingerprint`: HEAD plus every uncommitted byte) taken at
# each reading. A moved tree WARNS rather than refuses, for the reason only BEHIND-HEAD refuses at
# preflight: in-flight edits are the ordinary case, and the run is about the tree it now compiles.
# The postflight compares the fingerprint once more ("tree changed during this run").
DRIFT_PRE_FP=""; DRIFT_LOCK_FP=""
worktree_drift_gate() {  # $1 = preflight | after-lock
  local when="$1" label="worktree vs HEAD"
  [[ "$when" == after-lock ]] && label="worktree vs HEAD (asked again, test-host lock held)"
  DRIFT_OUT="$(cd "$ROOT_DIR" && "$ROOT_DIR/scripts/worktree-drift.sh" check 2>&1)"; DRIFT_STATUS=$?
  if [[ "$DRIFT_OUT" == *WORKTREE-BEHIND-HEAD* ]]; then
    say ""
    print -r -- "$DRIFT_OUT"
    say ""
    say "!! REFUSING: this run would test a checkout that is not HEAD (T-975). Nothing was built"
    if [[ "$when" == after-lock ]]; then
      say "   -- the checkout fell behind HEAD while this run waited for the test-host lock (T-3060);"
      say "   the lock is given back as this exits."
    else
      say "   and the test-host lock was not taken."
    fi
    exit 7
  elif (( DRIFT_STATUS != 0 )); then
    say "  $label: not answered ($(print -r -- "$DRIFT_OUT" | tail -1 | cut -c1-70)) -- proceeding"
  else
    say "  $label: $(print -r -- "$DRIFT_OUT" | head -1)"
  fi
}
if [[ "$ACTION" == "test" ]]; then
  worktree_drift_gate preflight
  DRIFT_PRE_FP="$(tree_fingerprint "$ROOT_DIR")"
fi

# --- the test-host lock ------------------------------------------------------
# Only `test` needs it: it is the app-group container that two hosts corrupt (T-236), not the
# build output. Acquire and release under the SAME id -- a mismatch makes `release` refuse and
# strands the lock for the rest of its lease.
#
# AND ONLY A `test` THAT STARTS A HOST NEEDS IT (T-1933). The lease was taken per ACTION, which is
# a proxy for "does this run start an app" that is wrong in exactly one direction: measured
# 2026-10-01, `-only-testing:CadenceUITests/CadenceOverdrawVerdictTests` queued **800 seconds**
# behind two siblings for a container it never opens. The condition is the locked-screen guard's,
# deliberately -- one input, one answer -- and it fails closed the same way, so every selection
# that could reach a host still queues. It is NOT the `raw` escape hatch: `raw` skips the lock on
# the caller's word, this skips it on a reading of the selection, and a run that skips it here is
# still a run the zero-test, warning and suite guards all gate.
LOCK_HELD=0
if [[ "$ACTION" == "test" ]] && ! selection_launches_an_app "${only_testing[@]}"; then
  say "  test-host lock: not taken -- this selection launches no app (T-1933)."
elif [[ "$ACTION" == "test" ]]; then
  "$ROOT_DIR/scripts/test-host-lock.sh" acquire "${CADENCE_LOCK_TIMEOUT:-5400}" "xcb-$ID" || exit 1
  trap "\"$ROOT_DIR/scripts/test-host-lock.sh\" release 'xcb-$ID'" EXIT INT TERM
  LOCK_HELD=1
  # T-3060: the queue above can be long; ask again about the tree this run will now compile.
  worktree_drift_gate after-lock
  DRIFT_LOCK_FP="$(tree_fingerprint "$ROOT_DIR")"
  if [[ -n "$DRIFT_PRE_FP" && "$DRIFT_LOCK_FP" != "$DRIFT_PRE_FP" ]]; then
    say "  !! tree changed while waiting for the test-host lock (T-3060): ${DRIFT_PRE_FP} -> ${DRIFT_LOCK_FP:-unreadable}"
    say "     the preflight answer above is about the earlier tree; this run compiles the tree as it is now."
  fi
fi

# Give the lease back as soon as the primary xcodebuild has exited (T-2086). The lease guards the
# app-group container two live test hosts share (T-236), and that hazard ends with the run: no
# postflight step starts a host or opens the container. The reports read this run's own log, the
# session dictionary and `pmset`; `last-green` fingerprints the git tree; the DD-IN-USE checks read
# the process list, and a same-id sibling never needed the lease to build into this DerivedData
# (a `build` takes none) -- the pre-leg check is what refuses that. Held to script exit, a red run
# kept siblings queued through every report, the ~24 s `pmset -g log` read included. Idempotent;
# when `release` fails the EXIT trap is left armed so the exit retries it. The trap itself is
# cleared by the CALLER, at top level: in zsh `trap - EXIT` inside a function names the function's
# own exit, so the script's trap survived it and released a second time (caught by selftest 15).
LEASE_NOTE=""
give_back_test_host_lease() {
  (( ${LOCK_HELD:-0} )) || return 0
  local out
  if out="$("$ROOT_DIR/scripts/test-host-lock.sh" release "xcb-$ID" 2>&1)"; then
    LOCK_HELD=0
    LEASE_NOTE="released when xcodebuild exited, before this postflight (T-2086)"
  else
    LEASE_NOTE="NOT released early ($(print -r -- "$out" | tail -1)); the exit trap retries (T-2086)"
  fi
}

# --- the T-117 stall watchdog ------------------------------------------------
# Reports, never kills. `sample` on our own child is what turns silence into a verdict.
watchdog() {  # $1 = pid, $2 = the log it writes (the primary run's when omitted; T-1956's leg passes its own)
  local target="$1" log="${2:-$LOG}" still=0 last=-1
  while sleep "$STALL_POLL"; do
    kill -0 "$target" 2>/dev/null || return 0
    local size=$(wc -c < "$log" 2>/dev/null | tr -d ' ')
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

# Taken immediately before the run so a lock landing any time after this point is inside the
# window `screen_lock_report` tests at postflight (T-1890).
# Asked again here, after the test-host lease, because the queue for it has reached forty minutes and
# a same-id sibling can start building into this DerivedData at any point in that wait (T-2042).
dd_in_use_refusal "$DD" "before launch, after the test-host lease" && exit $DD_IN_USE_EXIT
# A full unscoped CadenceTests run fingerprints its tree NOW and again at the end; only a run whose
# tree did not move underneath it may be recorded as the last green (T-2042).
LG_ROOT="${CADENCE_TREE_ROOT:-$ROOT_DIR}"
LG_FULL=0; LG_START=""
if full_unit_run "${run_args[@]}"; then
  LG_FULL=1
  LG_START="$(tree_fingerprint "$LG_ROOT")"
fi
SLEEP_WAKE_START="$(pmset_sleep_wake_sum)"   # T-2048: the cheap reading the postflight compares against
RUN_START_EPOCH=$(date +%s)
"$XCODEBUILD" -project "$ROOT_DIR/Cadence.xcodeproj" "${run_args[@]}" > "$LOG" 2>&1 &
XCB_PID=$!
watchdog "$XCB_PID" &
WATCHDOG_PID=$!
# A test run holds an idle- and (on AC) system-sleep assertion for exactly xcodebuild's lifetime
# (T-2048): `-w` ends it with the pid, so nothing outlives the run. It does NOT stop a lid-close or
# a forced sleep, and it is not `-d` -- the screen can still lock (see SCREEN-LOCKED-MID-RUN).
CAFFEINATE_PID=""
if (( IS_TEST_RUN )) && command -v caffeinate >/dev/null 2>&1; then
  caffeinate -i -s -w "$XCB_PID" >/dev/null 2>&1 &
  CAFFEINATE_PID=$!
fi
wait "$XCB_PID"; STATUS=$?
RUN_END_EPOCH=$(date +%s)
kill "$WATCHDOG_PID" 2>/dev/null
[[ -n "$CAFFEINATE_PID" ]] && kill "$CAFFEINATE_PID" 2>/dev/null
give_back_test_host_lease; (( LOCK_HELD )) || trap - EXIT INT TERM

# --- postflight --------------------------------------------------------------
say ""
say "== xcb result ($ID) =="
say "  XCODEBUILD_EXIT=$STATUS"
[[ -n "$LEASE_NOTE" ]] && say "  test-host lock: $LEASE_NOTE"
# T-3060: the tree this run started compiling (after the lock when it took one) against the tree
# now. A red with this line under it may be a sibling's half-landed edit rather than HEAD.
DRIFT_RUN_FP="${DRIFT_LOCK_FP:-$DRIFT_PRE_FP}"
if [[ "$ACTION" == "test" && -n "$DRIFT_RUN_FP" ]]; then
  DRIFT_END_FP="$(tree_fingerprint "$ROOT_DIR")"
  if [[ "$DRIFT_END_FP" != "$DRIFT_RUN_FP" ]]; then
    say "  !! tree changed during this run (T-3060): ${DRIFT_RUN_FP} -> ${DRIFT_END_FP:-unreadable}"
    say "     the result above may be about a half-edited tree, not HEAD; re-run on a still tree before triaging a red."
  fi
fi
XCODEBUILD_STATUS=$STATUS   # before any gate below can overwrite STATUS (T-2021 reads the raw one)
# Both counts spelled the way AGENTS.md requires, and the denominator with them (T-1147): a loose
# `grep -c 'error:'` counts a test failure whose message contains the word and reads a real kill as
# a build break, and the loose warning reading it sat beside reported the AppIntents tool notice as
# a compiler warning on every test run this repository has ever made.
diagnostic_report "$LOG" || { (( STATUS == 0 )) && STATUS=$WARNING_GATE_EXIT }
if (( IS_TEST_RUN )); then
  RAN=$(tests_seen "$LOG")
  # Not a test count (T-721): this counts per-test RESULT LINES, and swift-testing prints two for a
  # failing test (`recorded an issue` and `failed after`), so a 2-test suite reads 2 green, 3 with
  # one failure, 4 with two. Right for the zero-test guard below; wrong to quote as "N tests ran".
  say "  test result lines: $RAN"
  if (( RAN == 0 )); then
    EMPTY_RUN_EXIT=$XCODEBUILD_STATUS empty_run_diagnostic "$LOG" "${run_args[@]}"
    (( STATUS == 0 )) && STATUS=4
  else
    # The T-667 per-suite diff, whose inputs are the run's own ARGUMENTS and this run's log --
    # see `suite_started_guard`. Only reached when RAN > 0: a wholly empty run is the case above.
    suite_started_guard "$LOG" "$RAN" "${run_args[@]}" || { (( STATUS == 0 )) && STATUS=$SUITE_GATE_EXIT }
  fi
  # The preflight's partial-scope finding, said again where a green run is read (T-3080). Outside
  # the RAN branch and BELOW both guards above, because it is the quietest of the three and the
  # only one that can be true of a run that is entirely green: zero tests is the empty-run guard's
  # finding, a requested suite that contributed nothing is T-667's, and a suite nobody requested
  # at all -- living in a file this run did execute -- is this one. It never touches $STATUS.
  partial_scope_postflight "$RAN"
  # After both, and outside the RAN branch on purpose (T-1741): a run whose every test skipped has
  # RAN == 0 and is refused above, and the interactive opt-in is the likeliest reason it did --
  # so the report that names it must not be the one thing that branch omits.
  interactive_skip_report "$LOG"
  # Last of the test-run reports, and outside the RAN branch for the same reason: a mid-run lock
  # produces BOTH shapes -- an empty-tree run full of reds (RAN > 0) and a skipped-out one
  # (RAN == 0) -- depending only on whether the lock beat `setUpWithError` to it (T-1890).
  # The refused host relaunch first, so its note sits above the lock note that would otherwise
  # be the only explanation offered for it (T-1992).
  host_launch_refusal_report "$LOG" "$XCODEBUILD_STATUS"
  screen_lock_report "$RUN_START_EPOCH" "${run_args[@]}"
fi
# Outside the test-run branch: a `build` dies the same way (T-2046). Last of the primary-run
# reports, so it sits below the VACUOUS-COUNT and 0-tests readings it explains.
entitlements_poisoned_dd_report "$LOG" "$XCODEBUILD_STATUS" "$DD"
# Any action can be slept through (T-2048). The ~24 s log read happens only on a red run whose
# sleep/wake counters moved, or could not be read at either end.
if (( XCODEBUILD_STATUS != 0 )); then
  SLEEP_WAKE_END="$(pmset_sleep_wake_sum)"
  if [[ -z "$SLEEP_WAKE_START" || -z "$SLEEP_WAKE_END" || "$SLEEP_WAKE_START" != "$SLEEP_WAKE_END" ]]; then
    system_sleep_report "$RUN_START_EPOCH" "$RUN_END_EPOCH" "$XCODEBUILD_STATUS"
  fi
fi
# --- the iOS leg (T-1956) ----------------------------------------------------
# After every primary-run report and before the leak check, so a shared entry the leg's own
# `xcodebuild` created is reported too. The reasoning, and the four things it must get right, are
# beside `ios_leg_decide` above. Read DIAG_COMPILED NOW: the leg's own report overwrites it.
ios_leg_decide "$ACTION" "$STATUS" "$DIAG_COMPILED" "${args[@]}"
# The lease is given back before the leg, so this is the moment a same-id sibling can be mid-build
# in this DerivedData (T-2042). A leg that cannot run is not a green iOS surface: it gates.
if [[ -z "$IOS_LEG_SKIP" ]] && dd_in_use_refusal "$DD" "before the iOS leg"; then
  IOS_LEG_SKIP=DD-IN-USE
  IOS_LEG_WHY="another live xcodebuild is building into $DD, so the leg was not run"
  (( STATUS == 0 )) && STATUS=$DD_IN_USE_EXIT
fi
if [[ "$IOS_LEG_SKIP" == CARVED-OUT ]]; then
  say ""
  say "!! IOS-LEG-SKIPPED: CADENCE_SKIP_IOS_LEG=1 is set, so this run did NOT compile the iOS surface"
  say "   (T-1956). A macOS build compiles none of \`#if os(iOS)\`, so nothing above says anything about"
  say "   it. That is right only where something else builds iOS -- CI's \`ios-build\` job beside"
  say "   \`macos-tests\`. Anywhere else, unset it."
elif [[ "$IOS_LEG_SKIP" == DD-IN-USE ]]; then
  say "!! IOS-LEG-SKIPPED (DD-IN-USE): $IOS_LEG_WHY -- the iOS surface is NOT compiled (T-2042)."
elif [[ -n "$IOS_LEG_SKIP" ]]; then
  say "  ios leg: skipped ($IOS_LEG_SKIP) -- $IOS_LEG_WHY (T-1956)"
else
  # The leg needs no test host (88 s cold, T-1921). The lease is normally already back since the
  # primary exited (T-2086); this second call only matters when that release failed.
  give_back_test_host_lease; (( LOCK_HELD )) || trap - EXIT INT TERM
  IOS_LOG="${TMP_BASE}cadence-xcb-$ID-ios.$(date +%Y%m%d-%H%M%S)-$$.log"
  ln -sf "${IOS_LOG:t}" "${TMP_BASE}cadence-xcb-$ID-ios.log" 2>/dev/null
  ios_args=("${(@f)$(ios_leg_args "${args[@]}")}")
  say ""
  say "== xcb ios leg ($ID): -destination '$IOS_LEG_DESTINATION' build (T-1956) =="
  say "  log:             $IOS_LOG"
  "$XCODEBUILD" -project "$ROOT_DIR/Cadence.xcodeproj" "${ios_args[@]}" > "$IOS_LOG" 2>&1 &
  IOS_PID=$!
  watchdog "$IOS_PID" "$IOS_LOG" &
  IOS_WATCHDOG_PID=$!
  wait "$IOS_PID"; IOS_STATUS=$?
  kill "$IOS_WATCHDOG_PID" 2>/dev/null
  say "  XCODEBUILD_EXIT=$IOS_STATUS"
  diagnostic_report "$IOS_LOG"; IOS_GATE=$?
  IOS_APP_TASKS=$(grep -E "$SWIFT_COMPILE_TASK_PATTERN" "$IOS_LOG" 2>/dev/null \
    | grep -cF "$IOS_LEG_APP_TASK_PATTERN" | tr -d ' ')
  say "  app-target ('Cadence') compile tasks: $IOS_APP_TASKS"
  if (( IOS_STATUS != 0 )); then
    say ""
    say "!! IOS-LEG-FAILED: the primary run was green and the iOS build of the SAME tree exited"
    say "   $IOS_STATUS (T-1956). A macOS build compiles none of \`#if os(iOS)\`; this is what it hid:"
    grep -E "$SWIFT_ERROR_PATTERN|^error:|\*\* BUILD FAILED" "$IOS_LOG" 2>/dev/null | head -20 | sed 's/^/     /'
    say "   Read the rest in $IOS_LOG."
    (( STATUS == 0 )) && STATUS=$IOS_LEG_EXIT
  elif (( IOS_GATE != 0 )); then
    (( STATUS == 0 )) && STATUS=$IOS_GATE
  elif (( IOS_APP_TASKS == 0 )); then
    say "  !! IOS-LEG-VACUOUS: the iOS leg compiled no file of the app target 'Cadence' ($DIAG_COMPILED"
    say "     compile task(s) in all), so it certifies NOTHING about the iOS surface -- an incremental"
    say "     leg reuses object files. Not gated (T-1147); it is not evidence your change builds on iOS."
  else
    say "  ios leg: COMPILED -- $IOS_APP_TASKS app-target Swift compile task(s), 0 warnings."
  fi
fi
if [[ "$(shared_cadence_entries)" != "$before_entries" ]]; then
  say ""
  say "!! LEAK: a shared DerivedData entry appeared during this run, despite the private path."
  say "   Something in the build reached the default location. ./scripts/xcb.sh audit lists them."
fi
# --- the declined-hunk backstop (T-781) --------------------------------------
# `agent-commit.sh` records the lines a `<path>=<content-file>` reconstruction declined and refuses
# the NEXT commit of that path unless it carries them. If nobody ever commits that path again, no
# commit-time check fires at all, and the only instruments are `status` (a habit) and
# DECLINED-HUNK-STALE, which does nothing for 30 minutes and then refuses EVERY commit in the
# checkout at once. Measured 2026-09-05: an agent died mid-commit and left a stranded record on
# `docs/TODO.md`; nothing surfaced it, and it was found by a coordinator running `check` by hand
# during a sweep. Another half hour and it would have walled off the whole batch.
#
# So the listing goes where somebody is already looking -- the end of a build log -- with the age
# and the deadline on it, which is what turns "there is a record" into something anyone can act on.
#
# IT REPORTS AND IT DOES NOT GATE, deliberately. That is the distinction T-986 settled: `check`
# EXITS 3 while any record is outstanding, and every intra-batch run would then see a sibling's
# freshly declined, perfectly normal in-flight hunk -- the exact case DECLINED-HUNK-STALE's grace
# period exists NOT to block. `mutate.sh` alone runs this dozens of times per needle. So `$STATUS`
# is never touched here; the gate stays in the coordinator heartbeat, where the cadence fits.
declined_backstop() {
  local base="${TMPDIR:-/private/tmp/}"; [[ "$base" != */ ]] && base="$base/"
  local ledger="${CADENCE_DECLINED_LEDGER:-${base}cadence-declined-hunks}"
  [[ -d "$ledger" ]] || return 0
  local -a records; records=("$ledger"/*.declined(N))
  (( ${#records} )) || return 0
  local stale_after="${CADENCE_DECLINED_STALE_MINUTES:-30}"
  say ""
  say "!! DECLINED HUNKS OUTSTANDING (T-781): ${#records} record(s) hold lines that are in no commit."
  local r age left
  for r in "${records[@]}"; do
    age=$(( ( $(date +%s) - $(stat -f %m -- "$r" 2>/dev/null || date +%s) ) / 60 ))
    left=$(( stale_after - age ))
    say "   $(sed -n 's/^# path: //p' "$r" | head -1)  (declined by $(sed -n 's/^# by: //p' "$r" | head -1) at $(sed -n 's/^# commit: //p' "$r" | head -1), ${age}m ago)"
    grep -v '^# ' "$r" | head -4 | sed 's/^/     | /'
    if (( left > 0 )); then
      say "     in ${left}m this refuses EVERY agent-commit.sh commit in this checkout (DECLINED-HUNK-STALE)."
    else
      say "     this is ALREADY refusing every agent-commit.sh commit in this checkout."
    fi
  done
  say "   Fold them into a commit of that path, or -- if abandoned on purpose --"
  say "   ./scripts/agent-commit.sh accept <path>"
  return 0
}
declined_backstop

# --- the last full green (T-2042) --------------------------------------------
if (( LG_FULL )); then
  if (( STATUS != 0 )); then
    say "  last-green: not recorded -- this full CadenceTests run is not green (exit $STATUS)."
  elif [[ -z "$LG_START" ]]; then
    say "  last-green: not recorded -- $LG_ROOT is not the top of a git checkout."
  elif LG_END="$(tree_fingerprint "$LG_ROOT")" && [[ "$LG_END" == "$LG_START" ]]; then
    LG_FILE="$(last_green_file "$LG_ROOT")"
    if print -rl -- "sha=${LG_START%% *}" "tree=${LG_START#* }" "root=${LG_ROOT:A}" \
         "when=$(date '+%Y-%m-%dT%H:%M:%S%z')" "id=$ID" "log=$LOG" \
         "ios_leg=${IOS_LEG_SKIP:-compiled}" > "$LG_FILE.$$" 2>/dev/null && mv -f "$LG_FILE.$$" "$LG_FILE"; then
      say "  last-green: recorded ${LG_START%% *} (tree ${LG_START#* }) -- ./scripts/xcb.sh last-green"
      say "              exits 0 while HEAD and the working tree are still exactly this (T-2042)."
    else
      rm -f "$LG_FILE.$$" 2>/dev/null
      say "  last-green: not recorded -- could not write $LG_FILE."
    fi
  else
    say "  last-green: not recorded -- the tree changed during the run (${LG_START} -> ${LG_END:-unreadable})."
  fi
fi

# The delete is asked of `release-dd`, which re-reads the process list AT DELETE TIME: what is
# true now says nothing about a run a later heartbeat starts into this path (T-2042).
DD_USERS="$(dd_live_users "$DD")"
if [[ -n "$DD_USERS" ]]; then
  say "  !! do NOT delete $DD: live xcodebuild pid(s) ${(j:, :)${(f)DD_USERS}} use it (T-2042)."
else
  say "  (when you are done: ./scripts/xcb.sh release-dd $DD -- it refuses while a live"
  say "   xcodebuild uses that path, which a bare rm does not; a full one is ~1.7 GB)"
fi
exit $STATUS
