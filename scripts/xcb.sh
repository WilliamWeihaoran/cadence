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
#   ./scripts/xcb.sh check-only-testing <CadenceTests/Suite>   # resolve a filter, no build
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
#    first and exits 7 without taking the test-host lock if any tracked file is behind HEAD.
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

runner_never_started() {  # $1 = log, $2 = xcodebuild's exit status ("" when unknown)
  [[ "${2:-}" != "0" ]] && grep -qF -- "$AUTOMATION_MODE_TIMEOUT" "$1" 2>/dev/null
}

automation_mode_refusal() {
  say ""
  say "!! REFUSING: this test run executed 0 tests because the UI-test RUNNER never initialized."
  say "   This is an ENVIRONMENTAL refusal -- not evidence about the code, and not about the"
  say "   -only-testing: filter (T-2021). The log says: \"$AUTOMATION_MODE_TIMEOUT.\""
  say "   That is the ~70s timeout macOS returns when enabling automation turns into an"
  say "   authentication request, which a DISABLED developer mode does (T-1953, T-1957)."
  say "   Check:  DevToolsSecurity -status    -- it must say developer mode is currently enabled."
  say "   Enabling it is an admin change to this Mac and the owner's call; re-run once it reads enabled."
}

# Everything the caller needs to fix an empty run, printed where the empty run happened.
# EMPTY_RUN_EXIT is xcodebuild's own exit status when the caller has it; unset means unknown.
empty_run_diagnostic() {
  local log="$1"; shift
  if runner_never_started "$log" "${EMPTY_RUN_EXIT:-}"; then
    automation_mode_refusal
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
  done
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

screen_lock_report() {
  local -i run_start=${1:-0}
  local session; session="$(session_dictionary)"
  local -i locked_now=0
  [[ "$session" == *'"CGSSessionScreenIsLocked"=Yes'* ]] && locked_now=1
  local lock_time; lock_time="$(screen_lock_time)"
  local -i locked_during=0
  if [[ -n "$lock_time" ]] && (( run_start > 0 )) && (( lock_time >= run_start )); then
    locked_during=1
  fi
  (( locked_now || locked_during )) || return 0

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

host_launch_refusal_report() {  # $1 = log, $2 = xcodebuild's exit status ("" when unknown)
  local log=$1 xstatus=${2:-}
  [[ "$xstatus" == "0" ]] && return 0   # a green run has no red to explain
  local first; first=$(grep -anE -m1 -- "$HOST_LAUNCH_REFUSAL_PATTERN" "$log" 2>/dev/null | cut -d: -f1)
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
    'if (( $(grep -c . "$FAKE_XCB_CALLS") == 1 )); then cat -- "$FAKE_XCB_PRIMARY_LOG"; exit 0; fi' \
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
    say "usage: ./scripts/xcb.sh check-screen-lock-window <run-start-epoch-seconds>"; exit 2
  fi
  screen_lock_report "$2"
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
if [[ "$ACTION" == "test" ]]; then
  DRIFT_OUT="$(cd "$ROOT_DIR" && "$ROOT_DIR/scripts/worktree-drift.sh" check 2>&1)"; DRIFT_STATUS=$?
  if [[ "$DRIFT_OUT" == *WORKTREE-BEHIND-HEAD* ]]; then
    say ""
    print -r -- "$DRIFT_OUT"
    say ""
    say "!! REFUSING: this run would test a checkout that is not HEAD (T-975). Nothing was built"
    say "   and the test-host lock was not taken."
    exit 7
  elif (( DRIFT_STATUS != 0 )); then
    say "  worktree vs HEAD: not answered ($(print -r -- "$DRIFT_OUT" | tail -1 | cut -c1-70)) -- proceeding"
  else
    say "  worktree vs HEAD: $(print -r -- "$DRIFT_OUT" | head -1)"
  fi
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
if [[ "$ACTION" == "test" ]] && ! selection_launches_an_app "${only_testing[@]}"; then
  say "  test-host lock: not taken -- this selection launches no app (T-1933)."
elif [[ "$ACTION" == "test" ]]; then
  "$ROOT_DIR/scripts/test-host-lock.sh" acquire "${CADENCE_LOCK_TIMEOUT:-5400}" "xcb-$ID" || exit 1
  trap "\"$ROOT_DIR/scripts/test-host-lock.sh\" release 'xcb-$ID'" EXIT INT TERM
  LOCK_HELD=1
fi

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
RUN_START_EPOCH=$(date +%s)
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
  screen_lock_report "$RUN_START_EPOCH"
fi
# --- the iOS leg (T-1956) ----------------------------------------------------
# After every primary-run report and before the leak check, so a shared entry the leg's own
# `xcodebuild` created is reported too. The reasoning, and the four things it must get right, are
# beside `ios_leg_decide` above. Read DIAG_COMPILED NOW: the leg's own report overwrites it.
ios_leg_decide "$ACTION" "$STATUS" "$DIAG_COMPILED" "${args[@]}"
if [[ "$IOS_LEG_SKIP" == CARVED-OUT ]]; then
  say ""
  say "!! IOS-LEG-SKIPPED: CADENCE_SKIP_IOS_LEG=1 is set, so this run did NOT compile the iOS surface"
  say "   (T-1956). A macOS build compiles none of \`#if os(iOS)\`, so nothing above says anything about"
  say "   it. That is right only where something else builds iOS -- CI's \`ios-build\` job beside"
  say "   \`macos-tests\`. Anywhere else, unset it."
elif [[ -n "$IOS_LEG_SKIP" ]]; then
  say "  ios leg: skipped ($IOS_LEG_SKIP) -- $IOS_LEG_WHY (T-1956)"
else
  # The leg needs no test host. Give the lease back now rather than hold it across a build that
  # was measured at 88 s cold (T-1921) while siblings queue FIFO behind it.
  if (( ${LOCK_HELD:-0} )); then
    "$ROOT_DIR/scripts/test-host-lock.sh" release "xcb-$ID" >/dev/null 2>&1
    trap - EXIT INT TERM
    LOCK_HELD=0
  fi
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

say "  (delete $DD when you are done; a full one is ~1.7 GB)"
exit $STATUS
