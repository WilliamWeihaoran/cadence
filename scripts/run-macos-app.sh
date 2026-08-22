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
#                                $TMPDIR/CadenceUITestStores/<id>/default.store
# Together those mean the launched app cannot see or touch the user's data.
#
#   ./scripts/run-macos-app.sh start <path/to/Cadence.app> [id]
#   ./scripts/run-macos-app.sh stop  [id]
#   ./scripts/run-macos-app.sh status
#
# ALWAYS pair a start with a stop in the same turn. `stop` is idempotent and also
# removes the private store, so it is safe to call even if the app already exited.

set -uo pipefail
CMD="${1:-status}"
ID="${3:-${2:-agent-$$}}"
[[ "$CMD" == "start" ]] && ID="${3:-agent-$$}"
RUNDIR="${TMPDIR:-/tmp}/CadenceAgentRuns"; mkdir -p "$RUNDIR"
PIDFILE="$RUNDIR/$ID.pid"

case "$CMD" in
  start)
    APP="${2:-}"
    [[ -d "$APP" ]] || { print -r -- "usage: $0 start <path/to/Cadence.app> [id]"; exit 2 }
    # Refuse to add a writer if the user's own copy is up. Their session wins.
    if pgrep -f "/Applications/Cadence.app/Contents/MacOS/Cadence" >/dev/null 2>&1; then
      print -r -- "REFUSING: the user's own Cadence is running. Do not add a second writer."
      exit 3
    fi
    CADENCE_LOCAL_STORE_ONLY=1 CADENCE_UI_TEST_STORE_ID="$ID" \
      "$APP/Contents/MacOS/Cadence" >"$RUNDIR/$ID.log" 2>&1 &
    print -r -- "$!" > "$PIDFILE"
    sleep 2
    if kill -0 "$(<$PIDFILE)" 2>/dev/null; then
      print -r -- "started pid $(<$PIDFILE)  id=$ID  store=${TMPDIR:-/tmp}CadenceUITestStores/$ID"
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
    rm -rf "${TMPDIR:-/tmp}/CadenceUITestStores/$ID"
    print -r -- "private store removed; remaining agent app processes: $(pgrep -f 'Build/Products/Debug/Cadence.app' 2>/dev/null | wc -l | tr -d ' ')"
    ;;
  status)
    local -a pf; pf=("$RUNDIR"/*.pid(N))
    print -r -- "tracked runs: ${#pf}"
    print -r -- "debug-build processes: $(pgrep -f 'Build/Products/Debug/Cadence.app' 2>/dev/null | wc -l | tr -d ' ')"
    local -a st; st=(${TMPDIR:-/tmp}/CadenceUITestStores/*(N/))
    print -r -- "private stores: ${#st}"
    ;;
esac
