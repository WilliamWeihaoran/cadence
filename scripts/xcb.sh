#!/bin/zsh
# Guarded xcodebuild. Use this instead of calling xcodebuild directly.
#
#   ./scripts/xcb.sh <id> build [extra xcodebuild args...]
#   ./scripts/xcb.sh <id> test  [extra xcodebuild args...]     # takes the test-host lock
#   ./scripts/xcb.sh <id> raw   <every arg, including the action>
#   ./scripts/xcb.sh audit                                     # report shared-DerivedData leaks
#   ./scripts/xcb.sh check-test-log <log>                      # the zero-test guard, on its own
#   ./scripts/xcb.sh check-warnings <log>                      # the diagnostic counters, on their own
#   ./scripts/xcb.sh check-only-testing <CadenceTests/Suite>   # resolve a filter, no build
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
SWIFT_ERROR_PATTERN='\.swift:[0-9]+:[0-9]+: error:'
SWIFT_WARNING_PATTERN='\.swift:[0-9]+:[0-9]+: warning:'
SWIFT_COMPILE_TASK_PATTERN='^[[:space:]]*(SwiftCompile|CompileSwift|CompileSwiftSources|CompileC) '

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
  local errors warnings loose compiled notices
  errors=$(grep -cE "$SWIFT_ERROR_PATTERN" "$log" 2>/dev/null | tr -d ' ')
  warnings=$(grep -cE "$SWIFT_WARNING_PATTERN" "$log" 2>/dev/null | tr -d ' ')
  loose=$(grep -c 'warning:' "$log" 2>/dev/null | tr -d ' ')
  compiled=$(grep -cE "$SWIFT_COMPILE_TASK_PATTERN" "$log" 2>/dev/null | tr -d ' ')
  notices=$(( loose - warnings ))
  DIAG_WARNINGS=$warnings
  DIAG_COMPILED=$compiled
  say "  compile errors:  $errors"
  say "  warnings:        $warnings"
  if (( notices > 0 )); then
    say "  tool notices:    $notices  (lines saying \`warning:\` that are not a compiler diagnostic;"
    say "                   the baseline of zero is about the line above. grep the log to read them.)"
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
  grep -E "$SWIFT_WARNING_PATTERN" "$log" 2>/dev/null | head -20 | sed 's/^/     /'
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
# CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1 exists so this guard, and the skip it pairs with, can be
# *tested* -- a guard nobody can exercise is the hollow-instrument shape this repo keeps catching.
# It is not a way to get a UI run out of a locked Mac: with it set the tests skip instead, which is
# the behaviour worth confirming. There is no spelling of it that makes an app reach the foreground.
if screen_is_locked && [[ "${args[*]}" == *CadenceUITests* ]] \
   && [[ "${CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN:-}" != "1" ]]; then
  say ""
  say "!! REFUSING: the screen is locked, and no UI test in CadenceUITests can pass while it is."
  say "   loginwindow holds the foreground, so the launched app never leaves Running Background"
  say "   and app.launch() fails after ~60s per test. Unlock the screen and re-run (T-563)."
  exit 5
fi

# --- resolve -only-testing: before anything expensive (T-1076) ---------------
# Ahead of the drift check and the test-host lock on purpose. A name that selects nothing costs
# a full build to discover through the zero-test guard, and a `test` action queues behind a lock
# that has been reaching forty minutes; neither is worth paying to learn that a suite is misspelt.
only_testing=()
for (( i = 1; i <= ${#args}; i++ )); do
  case "${args[i]}" in
    -only-testing:*) only_testing+=("${args[i]#-only-testing:}") ;;
    -only-testing)   only_testing+=("${args[i+1]:-}") ;;
  esac
done
if (( ${#only_testing} )); then
  resolve_only_testing "${only_testing[@]}" || exit 8
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
    empty_run_diagnostic "$LOG"
    (( STATUS == 0 )) && STATUS=4
  else
    # --- the per-requested-suite guard (T-667) ---------------------------------
    # The check above answers "did the run execute anything at all", which cannot see one
    # REQUESTED suite, among several, that contributed nothing -- the T-667 shape exactly: a
    # 52-suite scoped run reported 593 tests and SUCCEEDED while 4 of the 52 executed zero, caught
    # only by a human diffing `✔ Suite` lines against the requested flags. This automates that
    # diff. Only runs when RAN > 0: a wholly empty run is already the case above.
    #
    # A suite's own Swift type name does not appear in swift-testing's event stream once it or its
    # cases carry a display name (T-667) -- the log speaks only in display-name vocabulary then --
    # so this asks `test-suite-index.sh --label`, which reads the same source `xcb.sh` cannot, for
    # the string the log will actually use, rather than grepping for the type name itself.
    requested=(${(f)"$(grep -oE -- '-only-testing:CadenceTests/[^ "'"'"']*' "$LOG" 2>/dev/null | sed 's#^-only-testing:CadenceTests/##' | sort -u)"})
    if (( ${#requested} )); then
      # One process for every suite in the target, not one per requested suite: `--labels` walks
      # `CadenceTests/` once and prints `TypeName<TAB>label` for each, so a 52-suite request costs
      # one subprocess here instead of 52.
      typeset -A suite_label_map
      while IFS=$'\t' read -r type_name suite_label; do
        [[ -z "$type_name" ]] && continue
        suite_label_map[$type_name]="$suite_label"
      done < <("$ROOT_DIR/scripts/test-suite-index.sh" --labels 2>/dev/null)
      for suite in $requested; do
        [[ -z "$suite" ]] && continue
        label="${suite_label_map[$suite]:-$suite}"
        if [[ "$label" == "$suite" ]]; then
          marker="Suite $suite started"
        else
          marker="Suite \"$label\" started"
        fi
        if ! grep -qF -- "$marker" "$LOG" 2>/dev/null; then
          say ""
          say "!! T-667: requested suite '$suite' never started (expected \"$marker\" somewhere in"
          say "   the log) even though this run's total test result lines is $RAN. It contributed 0"
          say "   -- a typo'd suite name, or one folded into a larger passing run that hid it."
          (( STATUS == 0 )) && STATUS=6
        fi
      done
    fi
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
