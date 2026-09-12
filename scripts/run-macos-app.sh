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
#   -CadenceSuiteName <id>       preferences redirected to the private suite
#                                com.haoranwei.Cadence.agent.<id>   (T-1157)
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

set -uo pipefail
CMD="${1:-status}"
ID="${3:-${2:-agent-$$}}"
[[ "$CMD" == "start" ]] && ID="${3:-agent-$$}"
RUNDIR="${TMPDIR:-/tmp}/CadenceAgentRuns"; mkdir -p "$RUNDIR"
PIDFILE="$RUNDIR/$ID.pid"
# Where the sandboxed app actually puts CADENCE_UI_TEST_STORE_ID -- see the header.
APP_STORE_ROOT="$HOME/Library/Containers/com.haoranwei.Cadence/Data/tmp/CadenceUITestStores"
# ...and where its PREFERENCES land, which is a different store and was not isolated at all
# until T-1157. `CADENCE_UI_TEST_STORE_ID` redirects SwiftData and nothing else; with no
# `-CadenceSuiteName` argument `CadenceDefaults.store` IS `UserDefaults.standard`, i.e. the file
# below without the `.agent.<id>` -- the signed-in person's own 86-key plist, measured 2026-09-12.
APP_PREFS_ROOT="$HOME/Library/Containers/com.haoranwei.Cadence/Data/Library/Preferences"
SUITE_PREFIX="com.haoranwei.Cadence.agent."
SUITE_PLIST="$APP_PREFS_ROOT/$SUITE_PREFIX$ID.plist"

case "$CMD" in
  start)
    APP="${2:-}"
    [[ -d "$APP" ]] || { print -r -- "usage: $0 start <path/to/Cadence.app> [id]"; exit 2 }
    # T-1157, and it is checked before anything else because it is a property of the ARGUMENT.
    # The id becomes a preferences FILENAME, and `CadenceDefaults.suiteName(forAgentID:)` answers
    # nil for anything outside [A-Za-z0-9-_.] -- and nil means "use the shared domain". So an id
    # the app rejects does not fail the launch: it silently lands it on the signed-in person's own
    # plist with `-CadenceSuiteName` present and looking right. Refuse where it can be read.
    if [[ -z "$ID" || -n "${ID//[A-Za-z0-9_.-]/}" ]]; then
      print -r -- "REFUSING: id '$ID' cannot name a preferences suite (only A-Za-z0-9 - _ . )."
      print -r -- "   An id the app rejects falls back to the shared defaults domain -- the user's"
      print -r -- "   own com.haoranwei.Cadence.plist. Pass a plain agent id (T-1157)."
      exit 4
    fi
    # Refuse to add a writer if the user's own copy is up. Their session wins.
    if pgrep -f "/Applications/Cadence.app/Contents/MacOS/Cadence" >/dev/null 2>&1; then
      print -r -- "REFUSING: the user's own Cadence is running. Do not add a second writer."
      exit 3
    fi
    CADENCE_LOCAL_STORE_ONLY=1 CADENCE_UI_TEST_STORE_ID="$ID" \
      "$APP/Contents/MacOS/Cadence" -CadenceSuiteName "$ID" >"$RUNDIR/$ID.log" 2>&1 &
    print -r -- "$!" > "$PIDFILE"
    sleep 2
    if kill -0 "$(<$PIDFILE)" 2>/dev/null; then
      print -r -- "started pid $(<$PIDFILE)  id=$ID  store=$APP_STORE_ROOT/$ID"
      print -r -- "  defaults: $SUITE_PREFIX$ID   (-CadenceSuiteName, T-1157)"
      print -r -- "REMEMBER: $0 stop $ID   — in this same turn."
    else
      print -r -- "app exited immediately; see $RUNDIR/$ID.log"; tail -5 "$RUNDIR/$ID.log"; exit 1
    fi
    ;;
  stop)
    if [[ -f "$PIDFILE" ]]; then
      pid=$(<"$PIDFILE")
      kill "$pid" 2>/dev/null && print -r -- "sent TERM to $pid"
      sleep 2
      kill -0 "$pid" 2>/dev/null && { kill -9 "$pid" 2>/dev/null; print -r -- "escalated to KILL (it hung — this is the documented failure)" }
      rm -f "$PIDFILE"
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
esac
