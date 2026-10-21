#!/bin/zsh
# Launch the macOS Cadence app for visual verification, against a PRIVATE store.
#
# Launching the app is legitimate — macOS is the primary surface and some things
# can only be seen by looking. What is not legitimate is launching the shipping
# configuration: that opens the user's real CloudKit-backed app-group store at
# ~/Library/Containers/com.haoranwei.Cadence/Data/ as a SECOND WRITER while their
# own copy may be running, and instances have hung and needed a force-quit, one of
# them for 15 hours.
#
# So this wrapper always sets:
#   CADENCE_LOCAL_STORE_ONLY=1   no CloudKit, and CadenceAppDelegate skips
#                                registerForRemoteNotifications()
#   CADENCE_UI_TEST_STORE_ID=..  store redirected to
#                                <app tmp>/CadenceUITestStores/<id>/default.store
#                                -- and, since T-1448, the BACKUPS beside it: the startup
#                                backup, the pending restore, the automatic-backup purge and
#                                the list under Settings > Data Safety all now resolve
#                                <that same directory>/Cadence Store Backups
#   -CadenceSuiteName <id>       preferences redirected to the private suite
#                                com.haoranwei.Cadence.agent.<id>   (T-1157)
#
# THE BACKUPS HALF IS NEW TOO, AND THE STORE REDIRECT NEVER IMPLIED IT (T-1448). `StoreBackupManager`
# resolved `CadenceStoreSupport.primaryStoreDirectoryURL()` directly, so it never learned this launch
# had been redirected. T-1448 was filed over a read -- an agent saw the owner's two real backups
# listed in Settings > Data Safety -- but the same path was written, not only read:
# `PersistenceController.init` ran its whole preflight against the app-group directory, so every
# agent launch copied ~16 MB of the OWNER'S store into the OWNER'S backups folder and then applied
# their retention policy to the rest. Four such `...-startup` folders existed for 2026-09-28 alone,
# one of them `20260928-143941-startup` against a log in this script's own run directory written the
# same minute. A pending restore of theirs would likewise have been APPLIED by the agent's process.
# Nothing here has to clean the new path up separately: it is inside <app tmp>/CadenceUITestStores/<id>,
# which `stop` already removes whole.
#
# THE THIRD LINE IS NEW AND THE FIRST TWO NEVER IMPLIED IT. This header used to say the two
# environment variables meant "the launched app cannot see or touch the user's data", and that
# sentence was false for UserDefaults for as long as it stood: a debug build carries bundle id
# com.haoranwei.Cadence, so it gets the user's own sandbox container, and with no
# -CadenceSuiteName argument CadenceDefaults.store IS UserDefaults.standard -- their own
# Data/Library/Preferences/com.haoranwei.Cadence.plist, 86 keys, written the same morning
# (measured 2026-09-12 at 4efd003). Every @AppStorage value this app wrote went into it.
#
# What is STILL shared, and is shared on purpose: the app-group suite
# group.com.haoranwei.Cadence, which `Theme` and `CadenceWidgetRefreshCenter` reach because the
# widget is a separate process and the accent id and the reload state are what the two must agree
# about. A launched agent app can therefore still change the accent colour the user's widget
# draws. That is the residue, and it is named rather than assumed away.
#
# Also still shared: the LEGACY-STORE MIGRATION's source directories, which is a deliberate
# exception rather than an oversight (T-1448). `migrateLegacyStoreIfNeeded` copies a pre-app-group
# store into a target that has no store items yet, and a private store directory is empty on its
# first launch -- so following the redirect would have IMPORTED the owner's real data into the
# agent's throwaway store. A launch with a private store now skips that step outright instead.
#
# `<app tmp>` is NOT this shell's $TMPDIR. `PersistenceController.resolvedStoreURL()`
# builds the path from `FileManager.default.temporaryDirectory`, and Cadence.app is
# sandboxed, so for the launched app that is
#   ~/Library/Containers/com.haoranwei.Cadence/Data/tmp/
# and never /var/folders/<user>/T/. Measured 2026-09-05 (T-1064): `stop` had been
# deleting the $TMPDIR path, which the app never writes, so every agent run since
# this script was written left its private store behind -- 76 of them by that date.
# The store is still throwaway and still nowhere near the user's real store at
# Data/Library/Application Support/, but it has to be deleted where it is written.
#
#   ./scripts/run-macos-app.sh start <path/to/Cadence.app> [id]
#   ./scripts/run-macos-app.sh stop  [id]
#   ./scripts/run-macos-app.sh status
#
# ALWAYS pair a start with a stop in the same turn, AND PASS THE SAME ID. `stop` is
# idempotent over the process, and it removes the private store -- but it now reports
# that removal from the filesystem and exits non-zero when there was nothing to remove
# (T-1066), because `stop` with the wrong id, or none, used to print success over a
# store it had never looked at.
#
# HOW TO ACTUALLY SEE THE WINDOW, INCLUDING THROUGH A LOCKED SCREEN (T-3231, 2026-10-19).
#
# Starting the app is half the job; a ledger line that says "macOS not verified on screen" is
# usually the other half failing. A full-screen `screencapture -x out.png` returns the LOCK SCREEN
# when the screen is locked -- a clock on black -- and that is what "I could not capture the Mac
# app" has meant here. Measured the same session: capture the WINDOW instead and it works.
#
#   1. Get the window number (NOT the pid). `CGWindowListCopyWindowInfo` with
#      `[.excludeDesktopElements]` lists every window; match `kCGWindowOwnerName == "Cadence"` and
#      read `kCGWindowNumber`. A ~12-line Swift file run with `xcrun swift <file>` is enough; the
#      system python3 has no Quartz module, so do not reach for pyobjc.
#   2. `screencapture -x -o -l<windowNumber> out.png`   (`-x` no sound, `-o` no window shadow)
#
# That returns the window's own backing store, so the app's live content comes out even with
# `loginwindow` in front of it. Verified 2026-10-19 on Darwin 27: screen locked since 00:26, app
# launched by this script at 00:44, capture at 00:45 showed the real Today list -- rows, sidebar,
# seeded data -- while the full-screen capture one minute earlier showed only the clock.
#
# WHAT IT NEEDS, and what it does NOT:
#   * Screen Recording for the controlling process. REQUIRED, and cheap to confirm before you rely
#     on it: if the window list comes back with `kCGWindowName` populated (real titles, not empty
#     strings), you have it. Without it `screencapture` produces nothing useful either.
#   * Accessibility: NOT USED. Nothing in this path touches an AX API or System Events, so an
#     Accessibility grant is irrelevant to it. This reads a window; it cannot click one.
#   * No unlock, no foreground, no interaction, and the user'"'"'s session is not disturbed.
#
# LIMITS, stated so the next agent does not over-claim it. This captures what the window has
# DRAWN. A window that has never rendered, or one that was closed, yields nothing; and because
# there is no way to click, this verifies a VIEW, not a flow. For anything needing interaction the
# screen still has to be unlocked.

#
# A SEEDED, CAPTURABLE WINDOW IN ONE COMMAND (T-3247). `start` alone opens an EMPTY private store,
# so a capture showed whatever an empty Today draws. Use instead:
#
#   ./scripts/run-macos-app.sh up <scenario|none> <id>   # Debug build into private DerivedData
#                                                        # (xcb.sh), start, wait, print WINDOW=<n>
#   ./scripts/run-macos-app.sh capture <id> <out.png>    # screencapture -x -o -l<n> of THAT pid
#   ./scripts/run-macos-app.sh window <id> [secs]        # just the CGWindow number
#   ./scripts/run-macos-app.sh stop <id>                 # quits ONLY the pid this id launched
#   ./scripts/run-macos-app.sh selftest
#
# <scenario> is a `CadenceUITestScenarioSeed.Scenario` raw value, read from that file, never
# retyped here (today-geometry, today-row-crush, popover-anchors, calendar-hues at T-3247). It
# sets CADENCE_UI_TEST_MODE=1 + CADENCE_UI_TEST_SCENARIO, which seeds the stock three lists plus
# the scenario into the private store, and (calendar-hues) serves the fixture events instead of
# EventKit. Seeding is opt-in: `none`, or `start` without a 4th argument, launches as before.
# Side effect of CADENCE_UI_TEST_MODE: the launch also claims its store dir with an `.owner` lock
# and sweeps DEAD `CadenceUITests` siblings (`CadenceUITestStoreDirectory.claimAndSweep`); a store
# with no `.owner` -- every unseeded agent run -- is never swept.
# THE PAGE (T-3200). The app lands on Today unless a 3rd `up` / 5th `start` argument names a
# `CadenceUITestLaunchPage` raw value (read from that file, never retyped here: today, all-tasks,
# inbox, notes, calendar, focus, settings at T-3200), which sets CADENCE_UI_TEST_PAGE and -- because
# the app ignores it outside UI-test mode -- CADENCE_UI_TEST_MODE=1 even with scenario `none`:
#   ./scripts/run-macos-app.sh up calendar-hues <id> calendar
# `start` refuses any bundle that is not `.../Build/Products/Debug/Cadence.app` (exit 5): never
# the shipping configuration, never /Applications. `stop` kills the recorded pid only if `ps`
# still names the binary `start` launched (exit 6 otherwise) -- it never matches by name.
# `-ApplePersistenceIgnoreState YES` keeps the launch from restoring or rewriting the OWNER'S saved
# window state, which lives in the same container (same bundle id).

set -uo pipefail
CMD="${1:-status}"
SELF="${0:A}"
ROOT_DIR="${SELF:h:h}"
SCENARIO=""
PAGE=""
case "$CMD" in
  start) ID="${3:-agent-$$}"; SCENARIO="${4:-}"; PAGE="${5:-}" ;;
  up)    SCENARIO="${2:-}"; ID="${3:-agent-$$}"; PAGE="${4:-}" ;;
  *)     ID="${2:-agent-$$}" ;;
esac
[[ "$SCENARIO" == "none" ]] && SCENARIO=""
RUNDIR="${CADENCE_LAUNCH_RUNDIR:-${TMPDIR:-/tmp}/CadenceAgentRuns}"; mkdir -p "$RUNDIR"
PIDFILE="$RUNDIR/$ID.pid"
BINFILE="$RUNDIR/$ID.bin"
SCENARIO_SOURCE="$ROOT_DIR/Cadence/Services/CadenceUITestScenarioSeed.swift"
PAGE_SOURCE="$ROOT_DIR/Cadence/Services/CadenceUITestLaunchPage.swift"
TMP_BASE="${TMPDIR:-/private/tmp/}"; [[ "$TMP_BASE" != */ ]] && TMP_BASE="$TMP_BASE/"
# Where the sandboxed app actually puts CADENCE_UI_TEST_STORE_ID -- see the header.
APP_STORE_ROOT="$HOME/Library/Containers/com.haoranwei.Cadence/Data/tmp/CadenceUITestStores"
# ...and where its PREFERENCES land, which is a different store and was not isolated at all
# until T-1157. `CADENCE_UI_TEST_STORE_ID` redirects SwiftData and nothing else; with no
# `-CadenceSuiteName` argument `CadenceDefaults.store` IS `UserDefaults.standard`, i.e. the file
# below without the `.agent.<id>` -- the signed-in person's own 86-key plist, measured 2026-09-12.
APP_PREFS_ROOT="$HOME/Library/Containers/com.haoranwei.Cadence/Data/Library/Preferences"
SUITE_PREFIX="com.haoranwei.Cadence.agent."
SUITE_PLIST="$APP_PREFS_ROOT/$SUITE_PREFIX$ID.plist"

# T-1157, and it is checked before anything else because it is a property of the ARGUMENT.
# The id becomes a preferences FILENAME, and `CadenceDefaults.suiteName(forAgentID:)` answers
# nil for anything outside [A-Za-z0-9-_.] -- and nil means "use the shared domain". So an id
# the app rejects does not fail the launch: it silently lands it on the signed-in person's own
# plist with `-CadenceSuiteName` present and looking right. Refuse where it can be read.
refuse_bad_id() {
  if [[ -z "$ID" || -n "${ID//[A-Za-z0-9_.-]/}" ]]; then
    print -r -- "REFUSING: id '$ID' cannot name a preferences suite (only A-Za-z0-9 - _ . )."
    print -r -- "   An id the app rejects falls back to the shared defaults domain -- the user's"
    print -r -- "   own com.haoranwei.Cadence.plist. Pass a plain agent id (T-1157)."
    exit 4
  fi
}

# The scenarios this tree's app can seed, read from the enum rather than retyped (T-3247).
known_scenarios() {
  [[ -r "$SCENARIO_SOURCE" ]] || return 1
  grep -oE 'case [A-Za-z]+ = "[a-z0-9-]+"' "$SCENARIO_SOURCE" | sed -E 's/.*"(.*)"/\1/'
}

refuse_bad_scenario() {
  [[ -z "$SCENARIO" ]] && return 0
  local -a known; known=("${(@f)$(known_scenarios)}")
  if (( ! ${known[(Ie)$SCENARIO]} )); then
    print -r -- "REFUSING: unknown scenario '$SCENARIO'. Known (from ${SCENARIO_SOURCE:t}): ${known[*]:-<none read>} | none"
    print -r -- "   The app would seed NOTHING for it and say so only in its log (T-3247)."
    exit 2
  fi
}

# The pages this tree's app can open on, read from the enum rather than retyped (T-3200).
known_pages() {
  [[ -r "$PAGE_SOURCE" ]] || return 1
  grep -oE 'case [A-Za-z]+ = "[a-z0-9-]+"' "$PAGE_SOURCE" | sed -E 's/.*"(.*)"/\1/'
}

refuse_bad_page() {
  [[ -z "$PAGE" ]] && return 0
  local -a known; known=("${(@f)$(known_pages)}")
  if (( ! ${known[(Ie)$PAGE]} )); then
    print -r -- "REFUSING: unknown page '$PAGE'. Known (from ${PAGE_SOURCE:t}): ${known[*]:-<none read>}"
    print -r -- "   The app would ignore it and open on Today, and the capture would show the wrong page (T-3200)."
    exit 2
  fi
}

# Refuse to add a writer if the user's own copy is up. Their session wins.
refuse_if_owner_running() {
  if pgrep -f "/Applications/Cadence.app/Contents/MacOS/Cadence" >/dev/null 2>&1; then
    print -r -- "REFUSING: the user's own Cadence is running. Do not add a second writer."
    exit 3
  fi
}

# The executable a live pid is running, by pid -- never by name (T-3247).
pid_executable() { ps -o comm= -p "$1" 2>/dev/null | sed -e 's/^ *//' -e 's/ *$//' }

# The tracked pid, but only while it is still the process `start` launched. Prints the pid;
# returns 1 with no pidfile, 2 if it is gone, 6 if the pid now names some other executable.
tracked_pid() {
  local p want have
  [[ -f "$PIDFILE" ]] || return 1
  p=$(<"$PIDFILE")
  kill -0 "$p" 2>/dev/null || return 2
  have=$(pid_executable "$p")
  if [[ -f "$BINFILE" ]]; then
    want=$(<"$BINFILE")
    [[ -n "$have" && "$have" == "$want" ]] || { print -r -- "$have"; return 6 }
  else
    # A pidfile from before T-3247 has no binfile: accept only a Debug-product Cadence.
    [[ "$have" == */Build/Products/Debug/Cadence.app/Contents/MacOS/Cadence ]] || { print -r -- "$have"; return 6 }
  fi
  [[ "$have" != /Applications/* ]] || { print -r -- "$have"; return 6 }
  print -r -- "$p"
}

# The CGWindow number of the largest ordinary window owned by pid $1, or nothing. Reads
# `CGWindowListCopyWindowInfo` through JXA (no Accessibility, no Apple Events). Exit 6 when no
# window on the system has a `kCGWindowName`, which is what missing Screen Recording looks like.
window_for_pid() {
  osascript -l JavaScript - "$1" <<'JXA'
ObjC.import('CoreGraphics');
function run(argv) {
  var pid = parseInt(argv[0], 10), best = null, bestArea = 0, named = 0;
  var list = ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionAll | $.kCGWindowListExcludeDesktopElements, $.kCGNullWindowID));
  for (var i = 0; i < list.count; i++) {
    var w = list.objectAtIndex(i), nm = w.objectForKey('kCGWindowName');
    if (nm && nm.js && nm.js.length) named++;
    if (w.objectForKey('kCGWindowOwnerPID').intValue !== pid) continue;
    if (w.objectForKey('kCGWindowLayer').intValue !== 0) continue;
    var b = w.objectForKey('kCGWindowBounds'), wd = b.objectForKey('Width').doubleValue, ht = b.objectForKey('Height').doubleValue;
    if (ht < 200 || wd < 200) continue;
    if (wd * ht > bestArea) { bestArea = wd * ht; best = w.objectForKey('kCGWindowNumber').intValue; }
  }
  if (named === 0) return 'NO-SCREEN-RECORDING';
  return best === null ? '' : String(best);
}
JXA
}

# Wait up to $1 seconds for the tracked pid's window; print its number.
wait_window() {
  local secs="${1:-60}" i p rc w
  for (( i = 0; i < secs; i++ )); do
    p=$(tracked_pid); rc=$?
    if (( rc == 6 )); then print -r -- "REFUSING: pid in $PIDFILE now runs '$p', not what start launched." >&2; return 6; fi
    (( rc )) && { print -r -- "no live tracked app for id=$ID (see $RUNDIR/$ID.log)" >&2; return 1 }
    w=$(window_for_pid "$p")
    if [[ "$w" == NO-SCREEN-RECORDING ]]; then
      print -r -- "!! no window anywhere has kCGWindowName: this process lacks Screen Recording; screencapture -l would capture nothing useful." >&2
      return 7
    fi
    [[ -n "$w" ]] && { print -r -- "$w"; return 0 }
    sleep 1
  done
  print -r -- "!! no window for pid $p after ${secs}s (see $RUNDIR/$ID.log)" >&2
  return 1
}

case "$CMD" in
  start)
    APP="${2:-}"
    [[ -d "$APP" ]] || { print -r -- "usage: $0 start <path/to/Debug/Cadence.app> [id] [scenario|none] [page]"; exit 2 }
    refuse_bad_id
    # Never the shipping configuration (T-3247): only a Debug product, never /Applications.
    APP="${APP:A}"
    if [[ "$APP" != */Build/Products/Debug/Cadence.app || "$APP" == /Applications/* ]]; then
      print -r -- "REFUSING: '$APP' is not a .../Build/Products/Debug/Cadence.app -- only a Debug build may be launched."
      exit 5
    fi
    refuse_bad_scenario
    refuse_bad_page
    refuse_if_owner_running
    BIN="$APP/Contents/MacOS/Cadence"
    # The seed half (T-3247) is its own word list, not more VAR= words on the launch line: the
    # launch line is parsed by `CadenceEventKitLaunchGateTests`, which requires every CADENCE_
    # variable ON it to disarm EventKit alone. The scenario does not, and is not meant to.
    typeset -a seed_env; seed_env=()
    [[ -n "$SCENARIO" ]] && seed_env=("CADENCE_UI_TEST_MODE=1" "CADENCE_UI_TEST_SCENARIO=$SCENARIO")
    # The page (T-3200) is read only in UI-test mode, so it brings the mode with it.
    if [[ -n "$PAGE" ]]; then
      (( ${seed_env[(Ie)CADENCE_UI_TEST_MODE=1]} )) || seed_env+=("CADENCE_UI_TEST_MODE=1")
      seed_env+=("CADENCE_UI_TEST_PAGE=$PAGE")
    fi
    env "${seed_env[@]}" CADENCE_LOCAL_STORE_ONLY=1 CADENCE_UI_TEST_STORE_ID="$ID" \
      "$BIN" -CadenceSuiteName "$ID" -ApplePersistenceIgnoreState YES >"$RUNDIR/$ID.log" 2>&1 &
    print -r -- "$!" > "$PIDFILE"
    print -r -- "$BIN" > "$BINFILE"
    sleep 2
    if kill -0 "$(<$PIDFILE)" 2>/dev/null; then
      print -r -- "started pid $(<$PIDFILE)  id=$ID  store=$APP_STORE_ROOT/$ID  scenario=${SCENARIO:-none}  page=${PAGE:-today (default)}"
      print -r -- "  defaults: $SUITE_PREFIX$ID   (-CadenceSuiteName, T-1157)"
      print -r -- "REMEMBER: $0 stop $ID   — in this same turn."
    else
      print -r -- "app exited immediately; see $RUNDIR/$ID.log"; tail -5 "$RUNDIR/$ID.log"; exit 1
    fi
    ;;
  up)
    refuse_bad_id
    [[ -n "${2:-}" ]] || { print -r -- "usage: $0 up <scenario|none> <id> [page]"; exit 2 }
    refuse_bad_scenario
    refuse_bad_page
    # Checked before the build too, so a refused launch does not first spend minutes compiling.
    refuse_if_owner_running
    # xcb.sh owns the private DerivedData (${TMP_BASE}cadence-dd-<id>) and every build guard.
    "$ROOT_DIR/scripts/xcb.sh" "$ID" build -scheme Cadence -destination 'platform=macOS' -configuration Debug
    brc=$?
    (( brc )) && { print -r -- "!! build failed (xcb.sh exit $brc); nothing launched."; exit 1 }
    APP="${TMP_BASE}cadence-dd-$ID/Build/Products/Debug/Cadence.app"
    [[ -x "$APP/Contents/MacOS/Cadence" ]] || { print -r -- "!! no product at $APP"; exit 1 }
    zsh "$SELF" start "$APP" "$ID" "${SCENARIO:-none}" $PAGE || exit $?
    WIN=$(wait_window 60); wrc=$?
    if (( wrc )); then print -r -- "!! no capturable window (exit $wrc). Still run: $0 stop $ID"; exit $wrc; fi
    print -r -- "WINDOW=$WIN"
    print -r -- "  capture: $0 capture $ID <out.png>   (or: screencapture -x -o -l$WIN <out.png>)"
    print -r -- "REMEMBER: $0 stop $ID   — in this same turn."
    ;;
  window)
    wait_window "${3:-60}"; exit $?
    ;;
  capture)
    OUT="${3:-}"
    [[ -n "$OUT" ]] || { print -r -- "usage: $0 capture <id> <out.png>"; exit 2 }
    WIN=$(wait_window 30) || exit $?
    rm -f "$OUT"
    screencapture -x -o -l"$WIN" "$OUT"
    crc=$?
    if (( crc )) || [[ ! -s "$OUT" ]]; then print -r -- "!! screencapture -l$WIN exited $crc; no image at $OUT"; exit 1; fi
    print -r -- "captured window $WIN of pid $(<$PIDFILE) -> $OUT ($(sips -g pixelWidth -g pixelHeight "$OUT" 2>/dev/null | awk '/pixel/ {printf "%s ", $2}')px)"
    ;;
  stop)
    if [[ -f "$PIDFILE" ]]; then
      pid=$(tracked_pid); trc=$?
      if (( trc == 6 )); then
        # The pid was recycled (or the file was edited): it is not ours. Kill nothing.
        print -r -- "!! REFUSING to signal pid $(<$PIDFILE): it now runs '$pid', not $(cat "$BINFILE" 2>/dev/null || print -r -- 'a Debug Cadence.app'). Nothing killed."
        rm -f "$PIDFILE" "$BINFILE"
        exit 6
      elif (( trc == 0 )); then
        kill "$pid" 2>/dev/null && print -r -- "sent TERM to $pid"
        sleep 2
        kill -0 "$pid" 2>/dev/null && { kill -9 "$pid" 2>/dev/null; print -r -- "escalated to KILL (it hung — this is the documented failure)" }
      else
        print -r -- "pid $(<$PIDFILE) already gone"
      fi
      rm -f "$PIDFILE" "$BINFILE"
    else
      print -r -- "no pidfile for id=$ID"
    fi
    # Both roots: the app's own (where the store really is) and the $TMPDIR one, which
    # a seeding script pointed at the same id may have written.
    #
    # T-1066: the removal is now REPORTED FROM THE FILESYSTEM, never assumed. This line used to
    # print "private store removed" unconditionally -- before or after the `rm`, it made no
    # difference, because nothing looked. Two ways it lied, both reproduced 2026-09-06:
    #   1. the pre-T-1064 script removed the $TMPDIR path, which the sandboxed app never writes,
    #      and printed success over a surviving 327680-byte default.store;
    #   2. `stop` with the id omitted resolves ID=agent-$$ -- a path that never existed -- and
    #      printed the same success over the store the matching `start <id>` had left.
    # A `stop` that found nothing is NOT a `stop` that cleaned up, and saying so is the whole
    # point: this is the only cleanup an agent is told to run, so a silent failure here is
    # uncatchable by the agent that caused it. 84 stores had accumulated by the time it was fixed.
    typeset -a removed survived missing
    for root in "$APP_STORE_ROOT" "${TMPDIR:-/tmp}/CadenceUITestStores"; do
      target="$root/$ID"
      if [[ ! -e "$target" ]]; then missing+=("$target"); continue; fi
      rm -rf "$target"
      if [[ -e "$target" ]]; then survived+=("$target"); else removed+=("$target"); fi
    done
    # T-1157: the private PREFERENCES suite, same rule as the store -- reported from the
    # filesystem, never assumed. Removed rather than left, because that directory already holds
    # 7803 plists (measured 2026-09-12), 7800 of them the residue T-516 found at 7,727 and stopped
    # growing -- it is not a place to start adding one file per agent run.
    #
    # `start` validates the id; `stop` does not, and this is the one line in the script that
    # deletes inside the user's Preferences directory, so it re-derives its own safety instead of
    # inheriting it. The resolved path must live DIRECTLY in that directory and its name must
    # begin with `com.haoranwei.Cadence.agent.`, which the user's own `com.haoranwei.Cadence.plist`
    # does not. Nothing an id can spell gets past both halves.
    if [[ "${SUITE_PLIST:h}" != "$APP_PREFS_ROOT" || "${SUITE_PLIST:t}" != "$SUITE_PREFIX"* ]]; then
      print -r -- "!! REFUSING to touch '$SUITE_PLIST': not a com.haoranwei.Cadence.agent.* file in $APP_PREFS_ROOT"
    elif [[ -e "$SUITE_PLIST" ]]; then
      rm -f "$SUITE_PLIST"
      if [[ -e "$SUITE_PLIST" ]]; then print -r -- "!! DEFAULTS SUITE NOT REMOVED: $SUITE_PLIST"
      else print -r -- "defaults suite removed: $SUITE_PLIST"; fi
    else
      print -r -- "no defaults suite at $SUITE_PLIST (the app may not have written one)"
    fi
    procs=$(pgrep -f 'Build/Products/Debug/Cadence.app' 2>/dev/null | wc -l | tr -d ' ')
    if (( ${#survived} )); then
      print -r -- "!! PRIVATE STORE NOT REMOVED: ${survived[*]}"
      print -r -- "   The rm ran and the path is still there. Delete it by hand and say so."
      print -r -- "   remaining agent app processes: $procs"
      exit 1
    elif (( ${#removed} )); then
      print -r -- "private store removed: ${removed[*]}"
      print -r -- "remaining agent app processes: $procs"
    else
      print -r -- "!! NOTHING REMOVED: no store at ${missing[*]}"
      print -r -- "   Nothing was cleaned up. Either the app never wrote one, or the id is wrong --"
      print -r -- "   \`stop\` without an id resolves to agent-\$\$, which never matches a \`start <id>\`."
      print -r -- "   Check: $0 status"
      print -r -- "   remaining agent app processes: $procs"
      exit 1
    fi
    ;;
  status)
    local -a pf; pf=("$RUNDIR"/*.pid(N))
    print -r -- "tracked runs: ${#pf}"
    print -r -- "debug-build processes: $(pgrep -f 'Build/Products/Debug/Cadence.app' 2>/dev/null | wc -l | tr -d ' ')"
    local -a st; st=("$APP_STORE_ROOT"/*(N/))
    print -r -- "private stores: ${#st}   ($APP_STORE_ROOT)"
    ;;
  selftest)
    # T-3247. Every refusal above, induced for real against a throwaway run directory. Launches
    # NO app: the "own" process is /bin/sleep under `exec -a <fake Debug binary>`, the stranger is
    # a plain /bin/sleep, and both are started -- and reaped -- by this selftest alone.
    ws=$(mktemp -d "${TMP_BASE}cadence-launch-selftest.XXXXXX") || exit 2
    typeset -i passed=0 failed=0
    check() {  # $1 name, $2 1|0, $3 detail
      if [[ "$2" == 1 ]]; then passed+=1; print -r -- "PASS $1"; else failed+=1; print -r -- "FAIL $1: $3"; fi
    }
    st() { CADENCE_LAUNCH_RUNDIR="$ws/run" zsh "$SELF" "$@" 2>&1 }
    dbg="$ws/fk/Build/Products/Debug/Cadence.app"; rel="$ws/fk/Build/Products/Release/Cadence.app"
    mkdir -p "$dbg/Contents/MacOS" "$rel/Contents/MacOS" "$ws/run"
    fakebin="$dbg/Contents/MacOS/Cadence"

    out=$(st start "$dbg" 'a/b'); rc=$?
    check bad-id $(( rc == 4 )) "exit $rc: $out"
    out=$(st start "$rel" "st-rel-$$"); rc=$?
    check shipping-config-refused $(( rc == 5 )) "exit $rc: $out"
    out=$(st start /Applications/Cadence.app "st-apps-$$"); rc=$?
    check applications-refused $(( rc == 5 || rc == 2 )) "exit $rc: $out"
    out=$(st start "$dbg" "st-scn-$$" bogus-scenario); rc=$?
    check unknown-scenario $(( rc == 2 )) "exit $rc: $out"
    out=$(st up bogus-scenario "st-up-$$"); rc=$?
    check unknown-scenario-before-build $(( rc == 2 )) "exit $rc: $out"
    out=$(st start "$dbg" "st-pg-$$" none bogus-page); rc=$?
    check unknown-page $(( rc == 2 )) "exit $rc: $out"
    out=$(st up none "st-uppg-$$" bogus-page); rc=$?
    check unknown-page-before-build $(( rc == 2 )) "exit $rc: $out"
    pg=("${(@f)$(known_pages)}")
    check pages-read-from-source $(( ${pg[(Ie)calendar]} > 0 && ${pg[(Ie)today]} > 0 )) "read: ${pg[*]}"
    sc=("${(@f)$(known_scenarios)}")
    check scenarios-read-from-source $(( ${sc[(Ie)today-geometry]} > 0 )) "read: ${sc[*]}"

    /bin/sleep 60 & stranger=$!
    print -r -- "$stranger" > "$ws/run/st-stranger.pid"; print -r -- "$fakebin" > "$ws/run/st-stranger.bin"
    out=$(st stop st-stranger); rc=$?
    check stop-spares-recycled-pid $(( rc == 6 )) "exit $rc: $out"
    check stranger-still-alive $( kill -0 $stranger 2>/dev/null && print 1 || print 0 ) "pid $stranger died"
    print -r -- "$stranger" > "$ws/run/st-legacy.pid"
    out=$(st stop st-legacy); rc=$?
    check stop-spares-stranger-without-binfile $(( rc == 6 )) "exit $rc: $out"
    check stranger-alive-after-legacy $( kill -0 $stranger 2>/dev/null && print 1 || print 0 ) "pid $stranger died"
    kill $stranger 2>/dev/null; wait $stranger 2>/dev/null

    ( exec -a "$fakebin" /bin/sleep 60 ) & own=$!
    sleep 0.3
    print -r -- "$own" > "$ws/run/st-own.pid"; print -r -- "$fakebin" > "$ws/run/st-own.bin"
    out=$(st window st-own 2); rc=$?
    check window-times-out-without-a-window $(( rc == 1 || rc == 7 )) "exit $rc: $out"
    [[ $rc == 7 ]] && print -r -- "   (note: this process lacks Screen Recording -- the live capture path cannot work here)"
    out=$(st stop st-own); rc=$?
    sleep 0.3
    check stop-kills-its-own-pid $( kill -0 $own 2>/dev/null && print 0 || print 1 ) "pid $own survived: $out"
    check stop-clears-pidfile $( [[ ! -e "$ws/run/st-own.pid" && ! -e "$ws/run/st-own.bin" ]] && print 1 || print 0 ) "$(ls "$ws/run")"
    kill $own 2>/dev/null; wait $own 2>/dev/null

    # The launch line is the one place the private store, the private defaults and the saved-state
    # opt-out meet; losing any of them is the T-1157 / T-1448 shape again.
    # Anchored on `env` at line start so this check's own needles below cannot satisfy it, and
    # spelled STORE[_]ID because `CadenceEventKitLaunchGateTests` requires exactly ONE live line
    # carrying that assignment.
    ll=("${(@f)$(grep -E -A1 '^[[:space:]]*env .*CADENCE_UI_TEST_STORE[_]ID=' "$SELF")}")
    check launch-line-isolated $( [[ "${ll[*]}" == *'CADENCE_LOCAL_STORE_ONLY=1'* && "${ll[*]}" == *'-CadenceSuiteName "$ID"'* && "${ll[*]}" == *'-ApplePersistenceIgnoreState YES'* ]] && print 1 || print 0 ) "${ll[*]}"

    rm -rf "$ws"
    print -r -- "selftest: $passed passed, $failed failed"
    (( failed == 0 && passed > 0 ))
    exit $?
    ;;
esac
