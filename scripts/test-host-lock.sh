#!/bin/zsh
# An ACTUAL mutex for the macOS test host. Use this instead of polling.
#
# Why polling does not work: every agent runs `until ! pgrep -f xcodebuild test`,
# they all observe an idle host in the same gap, and they all start. Measured on
# 2026-08-22: six concurrent runs and a 15-minute load average of 157 while every
# agent believed it was waiting politely. Concurrent macOS test runs corrupt each
# other (docs/TODO.md T-236) because a private -derivedDataPath does not isolate
# the test host's app-group container -- so those six runs were producing numbers
# nobody should trust.
#
# `mkdir` is atomic on APFS: exactly one caller can create a given directory, so
# it is the lock. A pidfile inside lets a stale lock be reclaimed when its owner
# died without releasing.
#
#   ./scripts/test-host-lock.sh acquire [timeout_seconds]   # blocks, exits 0 when held
#   ./scripts/test-host-lock.sh release
#   ./scripts/test-host-lock.sh status
#
# Typical use, and note the trap -- releasing only on the happy path is how a lock
# gets stranded and every later agent waits out the full timeout:
#   ./scripts/test-host-lock.sh acquire 5400 || exit 1
#   trap './scripts/test-host-lock.sh release' EXIT INT TERM
#   xcodebuild test ... ; echo "EXIT=$?"

set -uo pipefail
LOCK="${TMPDIR:-/tmp}/cadence-macos-test-host.lock"
# A held lock survives this long without a release before anyone may reclaim it.
# Longer than the slowest cold build+test seen here (~25 min), short enough that a
# killed agent does not block the queue for the rest of the night.
LEASE=${CADENCE_LOCK_LEASE:-2700}
# CADENCE_LOCK_LEASE exists for testing this script. It is floored at the default
# for any lock this process did not create, because a short override reclaims a
# lock another agent is actively holding -- which is exactly what happened once
# while testing it against the live lock.
(( LEASE < 2700 )) && [[ -z "${CADENCE_LOCK_TESTING:-}" ]] && LEASE=2700
CMD="${1:-status}"

case "$CMD" in
  acquire)
    # Identity is an explicit id, NOT $$: acquire and release routinely run in
    # different subshells (nohup, background, a trap), so comparing $$ made every
    # release warn and release anyway -- meaning one agent could free another's
    # lock. Default the id to the caller's directory, which is stable across
    # subshells of the same agent.
    # Default to $PPID, NOT ${PWD:t}: every agent cds to the repo first, so a
    # directory-derived id is "Cadence" for all of them and the identity check
    # below compares equal for strangers -- defeating the whole point. $PPID is
    # the caller's shell, unique per agent. Pass an explicit id if you prefer.
    timeout="${2:-5400}"; ID="${3:-$PPID}"; waited=0
    while (( waited < timeout )); do
      if mkdir "$LOCK" 2>/dev/null; then
        # $PPID, never $$: $$ is THIS script, which exits the instant acquire
        # returns, so the liveness check below would find every lock stale and
        # hand it to the next caller immediately -- a mutex that never excludes.
        # $PPID is the caller's shell, which lives for the duration of its run.
        print -r -- "$PPID" > "$LOCK/pid"; print -r -- "$ID" > "$LOCK/id"; date +%s > "$LOCK/since"
        print -r -- "acquired after ${waited}s (id $ID, owner pid $PPID)"; exit 0
      fi
      # Reclaim on a LEASE, not on liveness. Agents run each shell command in a
      # separate process, so the pid recorded at `acquire` is already dead by the
      # time the build runs in the next call -- a liveness check therefore hands a
      # held lock straight to the next caller. Measured: one agent's lock "expired
      # during the long build window" and rolled over to two other agents while its
      # own test run was still going. A lease expires only on wall-clock age, which
      # survives the acquiring shell exiting.
      if [[ -f "$LOCK/since" ]]; then
        age=$(( $(date +%s) - $(cat "$LOCK/since" 2>/dev/null || print 0) ))
        if (( age > LEASE )); then
          print -r -- "lease expired after ${age}s (limit ${LEASE}s); reclaiming from $(cat "$LOCK/id" 2>/dev/null)"
          rm -rf "$LOCK"; continue
        fi
      fi
      sleep 10; (( waited += 10 ))
      (( waited % 300 == 0 )) && print -r -- "  still waiting (${waited}s), held by $(cat "$LOCK/pid" 2>/dev/null)"
    done
    print -r -- "TIMED OUT after ${timeout}s; did NOT acquire. Do not run anyway."
    exit 1
    ;;
  release)
    ID="${2:-$PPID}"
    if [[ -d "$LOCK" ]]; then
      owner_id=$(cat "$LOCK/id" 2>/dev/null); owner_pid=$(cat "$LOCK/pid" 2>/dev/null)
      if [[ -n "$owner_id" && "$owner_id" != "$ID" ]]; then
        if kill -0 "$owner_pid" 2>/dev/null; then
          print -r -- "REFUSING: lock is held by '$owner_id' (pid $owner_pid, alive), not '$ID'"; exit 1
        fi
        print -r -- "owner '$owner_id' is dead; reclaiming"
      fi
    fi
    rm -rf "$LOCK"; print -r -- "released ($ID)"
    ;;
  status)
    if [[ -d "$LOCK" ]]; then
      owner=$(cat "$LOCK/pid" 2>/dev/null); since=$(cat "$LOCK/since" 2>/dev/null); oid=$(cat "$LOCK/id" 2>/dev/null)
      age=$(( $(date +%s) - ${since:-0} ))
      alive=$( (( age > LEASE )) && print "LEASE EXPIRED" || print held )
      print -r -- "locked by ${oid:-?} / pid $owner ($alive) for $(( $(date +%s) - ${since:-0} ))s"
    else
      print -r -- "free"
    fi
    print -r -- "live test hosts: $(pgrep -f 'Developer/usr/bin/xcodebuild test' | wc -l | tr -d ' ')"
    ;;
esac
