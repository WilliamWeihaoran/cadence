#!/bin/zsh
# T-1920. DID THE HEARTBEAT LAND ANY WORK, READ FROM MARKS THAT ONLY MOVE WHEN IT DID.
#
#   ./scripts/heartbeat-progress.sh report [<window-minutes>]   # default 60; exit 0 ADVANCING,
#                                                               #   1 SILENT, 3 NO-MARKS
#   ./scripts/heartbeat-progress.sh selftest
#
# WHY THIS EXISTS, AND WHY IT IS NOT A FIFTH TELL
#
# T-1920 nominated a shape as the tell for a hung 20-minute heartbeat -- status `running`,
# `last_activity_at` seconds after `started_at`, `now - last_activity_at` in hours -- and then
# refuted it, replaced it, and refuted the replacement. Three readings, all wrong, and the entry's
# own diagnosis of why is correct and is the reason this script exists: **all three inferred a
# process's liveness from a run list that reports two timestamps and a status string, and nothing
# in those three fields distinguishes `waiting`, `wedged` and `slow`.** A limit-waiting run and a
# hung one are the same row. The entry's closing instruction is explicit -- do not propose a fourth
# tell from the same three fields -- and this script does not. It never reads the run list; it
# cannot, because the task lives at `~/.claude/scheduled-tasks/cadence-heartbeat-resume/SKILL.md`,
# outside this repository, and its run state is not on disk at all.
#
# What the entry *did* leave buildable is one sentence: the heartbeat's progress is visible from
# this checkout even though its run list is not. A heartbeat that is working moves `git` HEAD,
# writes an `xcb.sh last-green` record, and grows an xcb log. All three are **advancing marks** of
# exactly the kind the refuted readings lacked -- a value that cannot move unless work happened --
# and all three are on this Mac's disk. That is what this reads.
#
# THE QUESTION IT ANSWERS IS PROGRESS, NOT LIVENESS, AND THE DIFFERENCE IS THE WHOLE POINT
#
# `ADVANCING` is sound in one direction and that direction is the useful one: a mark moved, so the
# heartbeat did something inside the window, and no amount of status-string ambiguity can take that
# back. `SILENT` is the honest half -- **it says no work landed, and it deliberately does not say
# why.** A heartbeat waiting out a usage limit is silent and perfectly healthy; so is one that is
# wedged. This script does not guess between them, because guessing between them is precisely what
# killed the three earlier readings, and a reading that kills healthy runs gets switched off inside
# a week.
#
# That non-claim is not a weakness, because the thing T-1920 actually wanted visible was never a
# hang in the abstract. It was this, in the entry's own words: *the heartbeat ran for over 26 hours
# and committed nothing -- HEAD did not move.* That is a SILENT verdict, it is measurable without
# inferring anything, and the non-zero exit means nobody has to be watching for it. The original
# complaint was that the hang was invisible for three hours; silence is only visible if something
# other than a human can run the check.
#
# WHAT IS STILL OWED AND IS NOT HERE
#
# Stopping a stuck run, and adding `./scripts/ci-run-coverage.sh report` to the heartbeat's section
# 1, both edit the owner's file outside this repository. Neither is in reach of a script in this
# checkout and neither is pretended at here.

set -u
setopt NULL_GLOB

say() { print -r -- "$@" }

TMP_BASE="${TMPDIR:-/private/tmp/}"; [[ "$TMP_BASE" != */ ]] && TMP_BASE="$TMP_BASE/"

# zsh writes here-document temp files to $TMPPREFIX, which zsh itself sets to `/tmp/zsh` at startup
# -- never $TMPDIR. `/tmp` is unwritable from the App-Sandboxed test host that runs this selftest
# (T-719), so every heredoc would fail there with nothing useful on stderr. Same line, same reason,
# as `agent-scratch.sh` and `mutate.sh`.
export TMPPREFIX="${CADENCE_TMPPREFIX:-${TMP_BASE}zsh}"

# `/usr/bin/git` is an xcrun shim and xcrun refuses inside an App Sandbox, so from the test host
# every git call fails with that on stderr and nothing else -- which reads like a broken
# repository. Same probe, same reason, as `worktree-drift.sh`.
if ! git --version >/dev/null 2>&1; then
    for _candidate in /Applications/Xcode.app/Contents/Developer/usr/bin /opt/homebrew/bin /usr/local/bin; do
        [[ -x "$_candidate/git" ]] || continue
        "$_candidate/git" --version >/dev/null 2>&1 || continue
        PATH="$_candidate:$PATH"; break
    done
fi

# `$0` inside a zsh function is the FUNCTION name, so both of these are captured here,
# at top level, where `$0` is still the script.
SELF_PATH="${0:A}"
ROOT_DIR="${SELF_PATH:h:h}"

# The seams, and the first two are deliberately the SAME names `xcb.sh` already uses for the same
# two things, so there is no second spelling to drift: `CADENCE_TREE_ROOT` is the checkout whose
# HEAD is read, `CADENCE_XCB_STATE_DIR` is where the `last-green` record lives, `TMPDIR` is where
# the xcb logs are. `CADENCE_HBP_NOW` substitutes the clock, which is what lets the selftest pin a
# window without sleeping through one.
hbp_root()      { print -r -- "${CADENCE_TREE_ROOT:-$ROOT_DIR}" }
hbp_state_dir() { local d="${CADENCE_XCB_STATE_DIR:-$TMP_BASE}"; [[ "$d" != */ ]] && d="$d/"; print -r -- "$d" }
hbp_now()       { print -r -- "${CADENCE_HBP_NOW:-$(date +%s)}" }

# `last-green`'s record is one file per tree root, named by a hash of the root's absolute path.
# This is `xcb.sh`'s own `last_green_file`, and it has to stay its twin: a different hash reads a
# file that is never there and this script would report NO-MARKS forever while the heartbeat worked.
hbp_last_green_file() {  # $1 = tree root
  print -r -- "$(hbp_state_dir)cadence-xcb-last-green.$(print -rn -- "${1:A}" | shasum | cut -c1-12)"
}

hbp_mtime() {  # $1 = path -> epoch seconds, or nothing
  [[ -e "$1" ]] || return 1
  stat -f %m "$1" 2>/dev/null
}

hbp_age_words() {  # $1 = epoch, $2 = now
  local secs=$(( $2 - $1 ))
  (( secs < 0 )) && secs=0
  if (( secs < 120 )); then print -r -- "${secs}s ago"
  elif (( secs < 7200 )); then print -r -- "$(( secs / 60 ))m ago"
  else print -r -- "$(( secs / 3600 ))h$(( (secs % 3600) / 60 ))m ago"
  fi
}

# `report`: the three marks, each read on its own, and a verdict that is the OR of them.
#
# Each mark is reported whether or not it moved, and that is deliberate -- a mark that is present
# and stale is a different fact from a mark that is absent, and collapsing them is how
# "no record yet" gets read as "no progress". `NO-MARKS` is the separate verdict for a machine
# where none of the three exists at all; it exits 3, the way `last-green`'s own NO-RECORD does,
# rather than claiming silence it has no standing to claim.
heartbeat_progress_report() {  # $1 = window minutes
  local window_min=$1 root now cutoff
  local -a moved stale absent
  root="$(hbp_root)"; now="$(hbp_now)"; cutoff=$(( now - window_min * 60 ))

  say "== heartbeat-progress (window ${window_min}m, tree $root) =="

  local head_sha head_at
  if head_sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null)" && [[ -n "$head_sha" ]]; then
    head_at="$(git -C "$root" log -1 --format=%ct 2>/dev/null)"
    say "  HEAD:       $head_sha committed $(hbp_age_words "$head_at" "$now")"
    if (( head_at >= cutoff )); then moved+=(HEAD); else stale+=(HEAD); fi
  else
    say "  HEAD:       absent -- $root is not a git checkout this process can read"
    absent+=(HEAD)
  fi

  local lg_file lg_at lg_sha
  lg_file="$(hbp_last_green_file "$root")"
  if lg_at="$(hbp_mtime "$lg_file")"; then
    lg_sha="$(sed -n 's/^sha=//p' "$lg_file" 2>/dev/null | head -1)"
    say "  LAST-GREEN: ${lg_sha:-(no sha in record)} recorded $(hbp_age_words "$lg_at" "$now")"
    if (( lg_at >= cutoff )); then moved+=(LAST-GREEN); else stale+=(LAST-GREEN); fi
  else
    say "  LAST-GREEN: absent -- no full green recorded for this tree ($lg_file)"
    absent+=(LAST-GREEN)
  fi

  local -a logs
  logs=("$TMP_BASE"cadence-xcb-*.log(N))
  if (( ${#logs} )); then
    local newest="" newest_at=0 l lat
    for l in $logs; do
      lat="$(hbp_mtime "$l")" || continue
      (( lat > newest_at )) && { newest_at=$lat; newest=$l }
    done
    say "  XCB-LOG:    ${newest:t} grew $(hbp_age_words "$newest_at" "$now") (${#logs} log(s) in $TMP_BASE)"
    if (( newest_at >= cutoff )); then moved+=(XCB-LOG); else stale+=(XCB-LOG); fi
  else
    say "  XCB-LOG:    absent -- no cadence-xcb-*.log in $TMP_BASE"
    absent+=(XCB-LOG)
  fi

  if (( ${#moved} )); then
    say "  heartbeat-progress: ADVANCING -- ${(j:, :)moved} moved inside the last ${window_min}m."
    return 0
  fi
  if (( ${#stale} == 0 )); then
    say "  heartbeat-progress: NO-MARKS -- none of the three marks exists yet, so there is nothing"
    say "              to have advanced. This is a machine that has not run the heartbeat, not a"
    say "              heartbeat that has stopped; the two are not the same and this does not"
    say "              report them the same."
    return 3
  fi
  say "  heartbeat-progress: SILENT -- no mark moved in ${window_min}m (${(j:, :)stale} stale)."
  say "              NOT A LIVENESS VERDICT. This says no work landed, and deliberately does not"
  say "              say why: a heartbeat waiting out a usage limit is silent and healthy, and"
  say "              nothing on disk separates it from one that is stuck. Three readings on T-1920"
  say "              died guessing that difference. What is claimed here is only what the marks"
  say "              show -- HEAD did not move, no green was recorded, no xcb log grew."
  return 1
}

# --- selftest ----------------------------------------------------------------------------------
#
# Every check runs against throwaway fixtures under $TMPDIR, so it says nothing about -- and does
# nothing to -- this checkout, and is safe alongside siblings committing in it. The clock is
# substituted rather than waited on, which is the only reason a window check costs no wall clock.
#
# The shape that matters is the three single-mark checks: each mark on its own must be able to
# produce ADVANCING over two stale companions. A reading that ORs three marks is exactly the kind
# where one input silently stops being read and the other two keep the verdict looking right.

selftest() {
  local ws passed=0 failed=0
  ws="$(mktemp -d "${TMP_BASE}cadence-hbp-selftest.XXXXXX")" || { say "selftest: cannot make a workspace"; return 1 }
  trap "rm -rf '$ws'" EXIT INT TERM

  check() {  # $1 = name, $2 = 1|0, $3 = evidence
    if [[ "$2" == 1 ]]; then print -r -- "  PASS $1"; (( passed++ ))
    else print -r -- "  FAIL $1"; print -r -- "       $3"; (( failed++ )); fi
  }

  local here="$SELF_PATH"
  mkdir -p "$ws/tree" "$ws/state" "$ws/tmp" "$ws/empty-state" "$ws/empty-tmp" "$ws/not-a-repo"

  git -C "$ws/tree" init -q 2>/dev/null
  git -C "$ws/tree" config user.email hbp@example.invalid
  git -C "$ws/tree" config user.name hbp
  print -r -- one > "$ws/tree/a.txt"
  git -C "$ws/tree" add a.txt
  git -C "$ws/tree" commit -qm "one"
  local fixture_at; fixture_at="$(git -C "$ws/tree" log -1 --format=%ct)"

  # $1 = now, $2 = state dir, $3 = tmp base, $4 = tree root, $@[5,-1] = report args
  probe() {
    local now=$1 state=$2 tmpb=$3 root=$4; shift 4
    out="$(CADENCE_HBP_NOW="$now" CADENCE_XCB_STATE_DIR="$state" TMPDIR="$tmpb" CADENCE_TREE_ROOT="$root" \
           zsh -f "$here" report "$@" 2>&1)"; rc=$?
    # The verdict is echoed on every probe, PASS or FAIL. Without this the three verdict strings
    # reach stdout only when a check fails, and `CadenceGuardScriptSelftestTests`, which requires
    # them by name, would be requiring something only a broken run ever prints.
    print -r -- "     seen: $(print -r -- "$out" | grep -o 'heartbeat-progress: [A-Z-]*' | head -1) (exit $rc)"
  }

  say "== heartbeat-progress selftest =="
  say "-- 1. nothing on disk is NO-MARKS, never SILENT"
  probe "$fixture_at" "$ws/empty-state" "$ws/empty-tmp/" "$ws/not-a-repo" 60
  check "no git checkout, no record, no log -> NO-MARKS (exit 3)" \
    $( (( rc == 3 )) && [[ "$out" == *"heartbeat-progress: NO-MARKS"* && "$out" != *SILENT* ]] && print 1 || print 0 ) "exit $rc: $out"

  say "-- 2. HEAD alone advances, and alone goes stale"
  probe "$fixture_at" "$ws/empty-state" "$ws/empty-tmp/" "$ws/tree" 60
  check "a commit inside the window -> ADVANCING, naming HEAD" \
    $( (( rc == 0 )) && [[ "$out" == *"heartbeat-progress: ADVANCING"* && "$out" == *"HEAD moved"* ]] && print 1 || print 0 ) "exit $rc: $out"

  probe $(( fixture_at + 26 * 3600 )) "$ws/empty-state" "$ws/empty-tmp/" "$ws/tree" 60
  check "the same commit 26h later -> SILENT (exit 1), which is T-1920's own complaint" \
    $( (( rc == 1 )) && [[ "$out" == *"heartbeat-progress: SILENT"* && "$out" == *"HEAD stale"* ]] && print 1 || print 0 ) "exit $rc: $out"

  say "-- 3. SILENT must not claim a hang -- the non-claim is the finding, so it is pinned"
  check "SILENT carries NOT A LIVENESS VERDICT and the usage-limit caveat" \
    $( [[ "$out" == *"NOT A LIVENESS VERDICT"* && "$out" == *"waiting out a usage limit is silent and healthy"* ]] && print 1 || print 0 ) "$out"
  check "SILENT says neither hung nor wedged" \
    $( [[ "${out:l}" != *hung* && "${out:l}" != *wedged* ]] && print 1 || print 0 ) "$out"

  say "-- 4. each mark on its own can produce ADVANCING over two stale companions"
  # Spelled without spaces inside the arithmetic on purpose. `CadenceShellLocalScan` splits a
  # declaration line on spaces, so `local stale_now=$(( fixture_at + 26 * 3600 ))` hands it
  # `fixture_at` as a second, bare declaration and it reports a redeclaration that is not there.
  local stale_now=$((fixture_at+26*3600))
  local tree_abs="${ws:A}/tree" lg
  lg="$ws/state/cadence-xcb-last-green.$(print -rn -- "$tree_abs" | shasum | cut -c1-12)"
  print -r -- "sha=deadbeef" > "$lg"
  touch -t "$(date -r $(( stale_now - 600 )) +%Y%m%d%H%M.%S)" "$lg"
  probe "$stale_now" "$ws/state" "$ws/empty-tmp/" "$ws/tree" 60
  check "a last-green record written 10m ago, HEAD 26h old -> ADVANCING, naming LAST-GREEN" \
    $( (( rc == 0 )) && [[ "$out" == *"ADVANCING"* && "$out" == *"LAST-GREEN moved"* && "$out" == *"deadbeef"* ]] && print 1 || print 0 ) "exit $rc: $out"

  print -r -- "building" > "$ws/tmp/cadence-xcb-capdial.1-2.log"
  touch -t "$(date -r $(( stale_now - 300 )) +%Y%m%d%H%M.%S)" "$ws/tmp/cadence-xcb-capdial.1-2.log"
  probe "$stale_now" "$ws/empty-state" "$ws/tmp/" "$ws/tree" 60
  check "an xcb log grown 5m ago, HEAD 26h old and no record -> ADVANCING, naming XCB-LOG" \
    $( (( rc == 0 )) && [[ "$out" == *"ADVANCING"* && "$out" == *"XCB-LOG moved"* ]] && print 1 || print 0 ) "exit $rc: $out"

  say "-- 5. the window is read, not decorative"
  probe $(( fixture_at + 90 * 60 )) "$ws/empty-state" "$ws/empty-tmp/" "$ws/tree" 60
  check "HEAD 90m old against a 60m window -> SILENT" \
    $( (( rc == 1 )) && [[ "$out" == *SILENT* ]] && print 1 || print 0 ) "exit $rc: $out"
  probe $(( fixture_at + 90 * 60 )) "$ws/empty-state" "$ws/empty-tmp/" "$ws/tree" 180
  check "the same HEAD against a 180m window -> ADVANCING" \
    $( (( rc == 0 )) && [[ "$out" == *ADVANCING* ]] && print 1 || print 0 ) "exit $rc: $out"

  say "-- 6. an absent mark and a stale mark are different facts"
  probe "$stale_now" "$ws/empty-state" "$ws/empty-tmp/" "$ws/tree" 60
  check "HEAD present-but-stale prints stale while the other two print absent" \
    $( [[ "$out" == *"HEAD:"*"committed"* && "$out" == *"LAST-GREEN: absent"* && "$out" == *"XCB-LOG:    absent"* ]] && print 1 || print 0 ) "$out"
  # Measured the hard way while writing this: a typo made the HEAD age a reference to a name that
  # exists only in the selftest, so under `set -u` the age substitution died in its subshell -- and
  # every check above still PASSED, because each reads the verdict and the verdict was right. The
  # verdict is not the whole report.
  check "no probe leaves a shell error in its report: set -u, bad substitution, missing command" \
    $( [[ "$out" != *"parameter not set"* && "$out" != *"bad substitution"* \
          && "$out" != *"command not found"* && "$out" != *"no such file"* ]] && print 1 || print 0 ) "$out"
  check "every mark line carries a rendered age, not an empty one" \
    $( [[ "$out" == *"committed "[0-9]*"h"*"m ago"* ]] && print 1 || print 0 ) "$out"

  say "-- 7. the last-green record this reads is xcb.sh's own, by construction"
  # A different hash reads a file that is never there, and this tool would report NO-MARKS forever
  # while the heartbeat worked. The two spellings are compared as TEXT rather than trusted to agree.
  local spelling mine theirs
  spelling='cadence-xcb-last-green.$(print -rn -- "${1:A}" | shasum | cut -c1-12)'
  mine="$(grep -cF -- "$spelling" "$here" 2>/dev/null)"
  theirs="$(grep -cF -- "$spelling" "${here:h}/xcb.sh" 2>/dev/null)"
  check "the record filename is spelled identically here and in scripts/xcb.sh" \
    $( [[ "${mine:-0}" -ge 1 && "${theirs:-0}" -ge 1 ]] && print 1 || print 0 ) "here=$mine site(s), xcb.sh=$theirs site(s)"

  say "checks: $passed passed, $failed failed"
  (( failed == 0 ))
}

# --- dispatch ----------------------------------------------------------------------------------

case "${1:-}" in
  report)
    window="${2:-60}"
    [[ "$window" == <-> ]] && (( window > 0 )) || { say "usage: ./scripts/heartbeat-progress.sh report [<window-minutes>]"; exit 2 }
    heartbeat_progress_report "$window"; exit $?
    ;;
  selftest) selftest; exit $? ;;
  *)
    say "usage: ./scripts/heartbeat-progress.sh report [<window-minutes>]"
    say "       ./scripts/heartbeat-progress.sh selftest"
    exit 2
    ;;
esac
