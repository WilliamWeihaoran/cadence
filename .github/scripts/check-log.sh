#!/bin/bash
# The repository's own red-run rules, applied to a CI log. Usage: check-log.sh <log> build|test
#
# Every rule here is lifted from AGENTS.md / docs/SUBAGENT_RUNBOOK.md rather than invented, and
# each exists because the naive spelling gives a WRONG answer on this project:
#
#  * Compile errors are counted with `\.swift:N:C: error:`, not `grep -c 'error:'`. A failing test
#    whose message contains the word "error" (e.g. `Caught error: .notFound(...)`) matches the loose
#    pattern, so a genuine test failure reads as a build break.
#  * A toolchain crash emits NO `error:` lines at all, so the strict count returns 0 on a build that
#    failed. The count is therefore always paired with the exit code and with a crash probe.
#  * Warnings are counted with `\.swift:N:C: warning:`, not `grep -c 'warning:'`. Measured
#    2026-08-31: any full `Cadence` build emits exactly one non-source line reading
#    "appintentsmetadataprocessor[...] warning: Metadata extraction skipped. No AppIntents.framework
#    dependency found." A zero-warning gate written the loose way is red on every single run.
set -uo pipefail

LOG="${1:?usage: check-log.sh <log> build|test}"
KIND="${2:-build}"
rc=0

if [ ! -f "$LOG" ]; then
  echo "::error::log $LOG does not exist; the build step never produced one."
  exit 1
fi

errors=$(grep -cE '\.swift:[0-9]+:[0-9]+: error:' "$LOG" | tr -d ' ')
warnings=$(grep -cE '\.swift:[0-9]+:[0-9]+: warning:' "$LOG" | tr -d ' ')
crash=$(grep -ci 'please submit a bug report' "$LOG" | tr -d ' ')
# `build-for-testing` prints "** TEST BUILD SUCCEEDED **", which a (BUILD|TEST) alternation does
# not match -- so the naive pattern reports a clean build as bannerless. Measured 2026-08-31.
succeeded=$(grep -cE '\*\* [A-Z ]*SUCCEEDED \*\*' "$LOG" | tr -d ' ')

echo "== gates =="
echo "  compile errors (strict): $errors"
echo "  swift warnings (strict): $warnings"
echo "  toolchain crash markers: $crash"
echo "  SUCCEEDED banners:       $succeeded"

if [ "$crash" -gt 0 ]; then
  echo "::error::the Swift toolchain crashed. A crash emits no error: lines, so the error count above is meaningless."
  grep -m3 -i -B5 'please submit a bug report' "$LOG" || true
  rc=1
fi

if [ "$errors" -gt 0 ]; then
  echo "::error::$errors compile error(s)."
  grep -E '\.swift:[0-9]+:[0-9]+: error:' "$LOG" | head -40
  rc=1
fi

# The warning baseline is ZERO and any new warning is a regression (AGENTS.md).
if [ "$warnings" -gt 0 ]; then
  echo "::error::$warnings Swift warning(s); the baseline is zero and any new warning is a regression."
  grep -E '\.swift:[0-9]+:[0-9]+: warning:' "$LOG" | head -40
  rc=1
fi

if [ "$succeeded" -eq 0 ]; then
  echo "::error::no BUILD/TEST SUCCEEDED banner in the log."
  tail -40 "$LOG"
  rc=1
fi

if [ "$KIND" = "test" ]; then
  # T-552: `-only-testing:` with a name that matches nothing is a GREEN run over zero tests.
  # xcb.sh already refuses that (exit 4); re-asserted here so the gate stands alone, and so the
  # count is visible in the job summary rather than only in a failure.
  #
  # The pattern is case-INSENSITIVE on the "test case" half, and that is not cosmetic.
  # scripts/xcb.sh spells it `Test Case ` (capital C, the classic XCTest form). Xcode 26.6's
  # PARALLEL swift-testing log writes `Test case '...' passed` (lowercase c). Measured
  # 2026-08-31: a parallel run with 33 real results was counted as 0 by that pattern and
  # refused with "this test run executed 0 tests" -- a FALSE zero-test failure. This gate runs
  # serial, so it would not hit it today; it is spelled safely so that enabling parallelism
  # later cannot turn the guard into a liar. Same family as AGENTS.md's note that parallel mode
  # changes the log format and silently breaks greps written for the serial one.
  ran=$(grep -acE "(✔|✘) Test [A-Za-z0-9_]+\(\)|[Tt]est [Cc]ase '[^']*' (passed|failed)" "$LOG" | tr -d ' ')
  failed=$(grep -acE "✘ Test [A-Za-z0-9_]+\(\)|[Tt]est [Cc]ase '[^']*' failed" "$LOG" | tr -d ' ')
  echo "  tests executed:          $ran"
  echo "  tests failed:            $failed"
  if [ "$ran" -eq 0 ]; then
    echo "::error::this test run executed 0 tests, and xcodebuild called that a success (T-552)."
    rc=1
  fi
  # A concurrency collision on this project shows up as a large number of ZERO-SECOND failures
  # (T-236). Naming it here keeps CI from being triaged as a code regression.
  if [ "$failed" -gt 100 ]; then
    echo "::warning::$failed failures. On this project a failure count in the hundreds with"
    echo "  zero-second durations means two test hosts shared one app-group container, not"
    echo "  broken code. See AGENTS.md 'Red-Run Triage'. A hosted runner should never see this"
    echo "  unless parallel testing was enabled."
  fi
fi

exit $rc
