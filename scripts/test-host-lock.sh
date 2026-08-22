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
CMD="${1:-status}"

case "$CMD" in
  acquire)
    # Identity is an explicit id, NOT $$: acquire and release routinely run in
    # different subshells (nohup, background, a trap), so comparing $$ made every
    # release warn and release anyway -- meaning one agent could free another's
    # lock. Default the id to the caller's directory, which is stable across
    # subshells of the same agent.
    timeout="${2:-5400}"; ID="${3:-${PWD:t}}"; waited=0
    while (( waited < timeout )); do
      if mkdir "$LOCK" 2>/dev/null; then
        # $PPID, never $$: $$ is THIS script, which exits the instant acquire
        # returns, so the liveness check below would find every lock stale and
        # hand it to the next caller immediately -- a mutex that never excludes.
        # $PPID is the caller's shell, which lives for the duration of its run.
        print -r -- "$PPID" > "$LOCK/pid"; print -r -- "$ID" > "$LOCK/id"; date +%s > "$LOCK/since"
        print -r -- "acquired after ${waited}s (id $ID, owner pid $PPID)"; exit 0
      fi
      # Reclaim a lock whose owner is gone -- an agent killed by a watchdog or a
      # usage limit never runs its release.
      if [[ -f "$LOCK/pid" ]]; then
        owner=$(<"$LOCK/pid")
        if ! kill -0 "$owner" 2>/dev/null; then
          print -r -- "owner $owner is dead; reclaiming stale lock"
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
    ID="${2:-${PWD:t}}"
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
      alive=$(kill -0 "$owner" 2>/dev/null && print held || print STALE)
      print -r -- "locked by ${oid:-?} / pid $owner ($alive) for $(( $(date +%s) - ${since:-0} ))s"
    else
      print -r -- "free"
    fi
    print -r -- "live test hosts: $(pgrep -f 'Developer/usr/bin/xcodebuild test' | wc -l | tr -d ' ')"
    ;;
esac
