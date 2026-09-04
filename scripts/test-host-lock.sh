#!/bin/zsh
# An ACTUAL mutex for the macOS test host, and since T-650 a FAIR one. Use this
# instead of polling.
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
# Why the queue (T-650). Excluding is not the same as ordering. Every waiter used
# to race on release, so the winner was whoever's 10-second sleep happened to end
# first -- arrival order counted for nothing, and a run that arrived at the right
# instant beat one that had been waiting an hour. Measured starvation with 3-4
# agents: 65 minutes in Batch A, then 21, 23, 35 and 40 minutes across Batches F
# and G, the single largest wall-clock cost in those runs. A mutation batch is
# many short acquisitions in a row, so the starved agent is starved repeatedly.
# The fix is a FIFO of tickets: a waiter files one on arrival and only the ticket
# at the head of the queue is allowed to call `mkdir`. Everyone else stands
# aside, so "next" means "waiting longest", not "luckiest phase".
#
# Why the head also checks $PPID (T-748). Waiting its turn is not the same as
# having somewhere to go: a waiter whose caller was killed keeps its ticket, keeps
# waiting, and eventually reaches the head anyway -- `pkill -f 'run-batch-<tag>.sh'`
# does not match this script's own `acquire` child, so the orphan survives the kill
# that was meant to remove it. With nobody checking, it took the lock, recorded its
# own already-dead $PPID as owner, and stranded it for the full LEASE. So the head
# checks, at the moment it would `mkdir`, that its caller is still alive; an orphan
# declines and drops its ticket instead, which is what a caller with nothing left
# to run under should do.
#
# Why the held lock ALSO checks the owner's pulse (T-956). T-748 covers a waiter
# that dies before it ever takes the lock. Nothing covered the symmetric case: an
# owner that dies AFTER taking it. That owner never runs its `release` trap, so the
# lock just sits there, and the reclaim branch below used to gate on lease age
# alone -- meaning a dead owner stranded every waiter for the full 2700s LEASE
# even though `kill -0` on the recorded owner pid would have said "gone" instantly.
# Measured: released by hand mid-run because nobody was going to wait 45 minutes.
# The fix checks the owner pid the same way T-748 checks $PPID -- but a dead owner
# pid is NOT sufficient by itself to reclaim: the owner's shell can die (SIGKILL,
# a crash) while a `nohup`'d `xcodebuild test` it started keeps running detached,
# same as the existing lease-expiry path. So a dead owner only shortcuts the LEASE
# wait; it still defers to `live_test_hosts` before actually removing the lock.
#
#   ./scripts/test-host-lock.sh acquire [timeout_seconds] [id]  # blocks, exits 0 when held
#   ./scripts/test-host-lock.sh release [id]
#   ./scripts/test-host-lock.sh status                          # holder + the queue behind it
#   ./scripts/test-host-lock.sh selftest                        # proves the three properties below
#
# Typical use, and note the trap -- releasing only on the happy path is how a lock
# gets stranded and every later agent waits out the full timeout:
#   ./scripts/test-host-lock.sh acquire 5400 || exit 1
#   trap './scripts/test-host-lock.sh release' EXIT INT TERM
#   xcodebuild test ... ; echo "EXIT=$?"
#
# If you pass an explicit id to `acquire`, you MUST pass the same id to `release`.
# Measured 2026-08-30: an agent acquired as `c1a`, released with the idiom above,
# which defaults the id to $PPID -- that mismatched the recorded owner, the owner
# pid was still alive, so release REFUSED and the lock sat stranded for 19 minutes
# while later agents queued behind it. The refusal is correct (it stops one agent
# freeing another's lock); passing no id to `acquire` or the same id to both is
# what makes it a no-op:
#
#   ./scripts/test-host-lock.sh acquire 5400 "$MYID" || exit 1
#   trap "./scripts/test-host-lock.sh release '$MYID'" EXIT INT TERM
#
# FAIRNESS HAS A PRICE, AND IT IS THE ONE YOU WANT. Release-and-immediately-
# re-acquire no longer wins: you go to the back of the queue like everyone else.
# That is the whole point, but it means a mutation batch of a dozen short runs
# now interleaves with siblings instead of monopolising the host. If you need one
# lease across many runs, take it once and use `scripts/xcb.sh <id> raw test ...`,
# which skips the lock and keeps the zero-test guard -- that is the supported
# escape hatch, and wrapping `xcb.sh <id> test` in an outer `acquire` is not (it
# deadlocks the runner against its own lease).

set -uo pipefail
LOCK="${TMPDIR:-/tmp}/cadence-macos-test-host.lock"
# CADENCE_LOCK_DIR exists so `selftest` can exercise this script without touching
# the real lock, which sibling agents are holding while you read this. It is
# honoured ONLY under CADENCE_LOCK_TESTING, because a stray override in one
# agent's environment would silently split the mutex in two and hand back exactly
# the concurrent test hosts the file exists to prevent.
[[ -n "${CADENCE_LOCK_TESTING:-}" && -n "${CADENCE_LOCK_DIR:-}" ]] && LOCK="$CADENCE_LOCK_DIR"
# The queue of waiters, one file per waiter, named by arrival. Deliberately NOT
# inside $LOCK: `release` does `rm -rf "$LOCK"`, which would delete the queue of
# everyone waiting for it.
QUEUE="${LOCK}.queue"
# A held lock survives this long without a release before anyone may reclaim it.
# Longer than the slowest cold build+test seen here (~25 min), short enough that a
# killed agent does not block the queue for the rest of the night.
LEASE=${CADENCE_LOCK_LEASE:-2700}
# CADENCE_LOCK_LEASE exists for testing this script. It is floored at the default
# for any lock this process did not create, because a short override reclaims a
# lock another agent is actively holding -- which is exactly what happened once
# while testing it against the live lock.
(( LEASE < 2700 )) && [[ -z "${CADENCE_LOCK_TESTING:-}" ]] && LEASE=2700
# How often a waiter looks. Halved from the historical 10s with the queue: with a
# FIFO the head is the only caller that may take the lock, so this interval is now
# pure handoff latency paid on every release, not a race window.
POLL=${CADENCE_LOCK_POLL:-5}
# A ticket is proof that a waiter is still waiting: every poll touches it. A
# ticket nobody has touched in this long belongs to a waiter that is gone -- or
# stopped, which is indistinguishable from gone and just as bad for the queue --
# and is removed so the queue moves on. A live waiter that loses its ticket this
# way re-files it under its ORIGINAL arrival stamp, so pruning cannot cost anyone
# their place; the worst case is a redundant write.
TICKET_STALE=${CADENCE_LOCK_TICKET_STALE:-60}
CMD="${1:-status}"
SELF="${0:A}"

# The live-test-host probe. ANCHOR the pattern: `pgrep -f` matches whole command
# lines, so the unanchored form counts every agent shell whose own command text
# contains the literal -- including the wait loops written to avoid contention.
# That inverts them into a deadlock: each waiting agent sees the others waiting
# and counts them as running. One agent held the lock 23 minutes with zero real
# hosts on the box. The override is testing-only for the same reason as
# CADENCE_LOCK_DIR: it decides whether a lease may be reclaimed.
HOST_PATTERN='^/Applications/.*/xcodebuild test'
[[ -n "${CADENCE_LOCK_TESTING:-}" && -n "${CADENCE_LOCK_PGREP:-}" ]] && HOST_PATTERN="$CADENCE_LOCK_PGREP"
live_test_hosts() { pgrep -f "$HOST_PATTERN" 2>/dev/null | wc -l | tr -d ' ' }

# --- the queue ---------------------------------------------------------------
# Arrival order is a wall-clock stamp with microseconds, zero-padded to a fixed
# width so a plain lexical sort (zsh's default glob order) is arrival order. The
# pid suffix breaks ties between two waiters that arrive in the same microsecond.
zmodload zsh/datetime 2>/dev/null
arrival_stamp() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then printf '%017.6f' "$EPOCHREALTIME"
  else printf '%017.6f' "$(date +%s).000000"
  fi
}

# A waiter is alive if its process is alive AND is still this script. The second
# half is not pedantry: pids are reused, and a recycled pid that happened to land
# on some long-lived process would pin a dead waiter at the head of the queue
# forever.
waiter_alive() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [[ "$(ps -o command= -p "$pid" 2>/dev/null)" == *test-host-lock* ]]
}

# Drop tickets whose waiter is gone. Both halves are needed: `kill -0` catches the
# killed runner immediately, and the touch age catches the cases a pid cannot --
# a stopped process, a pid reused by another copy of this script, a ticket left
# behind by a machine that rebooted mid-batch. A queue that keeps dead tickets is
# worse than no queue at all, because the head never moves.
prune_queue() {
  [[ -n "$QUEUE" && -d "$QUEUE" ]] || return 0
  local t pid rest now age
  now=$(date +%s)
  for t in "$QUEUE"/*(N.); do
    read -r pid rest < "$t" 2>/dev/null || pid=""
    if ! waiter_alive "$pid"; then rm -f "$t" 2>/dev/null; continue; fi
    age=$(( now - $(stat -f %m "$t" 2>/dev/null || print "$now") ))
    (( age > TICKET_STALE )) && rm -f "$t" 2>/dev/null
  done
}

# The queue, in arrival order, one name per line -- and NOTHING at all when it is
# empty. `print -rl --` with no arguments still prints a newline, which would make
# an empty queue read as one waiter and put every caller behind a phantom.
queue_names() {
  local -a t; t=("$QUEUE"/*(N.:t))
  (( ${#t} )) && print -rl -- "${t[@]}"
  return 0
}

case "$CMD" in
  acquire)
    # Identity is an explicit id, NOT $$: acquire and release routinely run in
    # different subshells (nohup, background, a trap), so comparing $$ made every
    # release warn and release anyway -- meaning one agent could free another's
    # lock. Default the id to $PPID, NOT ${PWD:t}: every agent cds to the repo
    # first, so a directory-derived id is "Cadence" for all of them and the
    # identity check below compares equal for strangers -- defeating the whole
    # point. $PPID is the caller's shell, unique per agent.
    timeout="${2:-5400}"; ID="${3:-$PPID}"; waited=0
    # File a ticket before the first attempt, so arrival order is recorded even
    # for the caller that finds the lock free and never waits.
    TICKET=""
    if mkdir -p "$QUEUE" 2>/dev/null; then
      TICKET="$QUEUE/$(arrival_stamp)-$$"
      # $$ (this script), not $PPID: this process is the one that blocks for the
      # whole wait, so it is the honest liveness handle for the ticket. $PPID is
      # what gets recorded as the lock's owner, which is a different question --
      # an owner legitimately outlives the shell that acquired for it.
      print -r -- "$$ $ID $(date +%s)" > "$TICKET"
      # A waiter that dies must not hold its place forever. The trap covers the
      # ordinary kill; prune_queue's liveness check covers SIGKILL, which no trap
      # can. Killing a queued runner still does not kill this child (see
      # docs/SUBAGENT_RUNBOOK.md) -- but now the orphan waits in line rather than
      # ahead of it.
      trap 'rm -f "$TICKET" 2>/dev/null' EXIT INT TERM
    fi
    while (( waited < timeout )); do
      if [[ -n "$TICKET" ]]; then
        # Re-file under the same name if a prune took it while we were sleeping;
        # the name carries the arrival stamp, so this cannot jump or lose a place.
        if [[ -f "$TICKET" ]]; then touch "$TICKET" 2>/dev/null
        else print -r -- "$$ $ID $(date +%s)" > "$TICKET" 2>/dev/null; fi
        prune_queue
      fi
      # Only the head of the queue may take the lock. With no queue directory at
      # all (a $TMPDIR we cannot write) everyone is the head, which is the old
      # unfair behaviour -- degraded, but never deadlocked.
      first=""
      [[ -n "$TICKET" ]] && first="$(queue_names | head -1)"
      if [[ -z "$first" || "$first" == "${TICKET:t}" ]]; then
        # T-748: a waiter whose caller is dead has nothing to hold the lock FOR.
        # $PPID is the shell that invoked `acquire` and is blocking on it; if that
        # shell is gone, this process is an orphan (T-650's queue made it wait its
        # turn rather than jump it, which surfaced the failure mode rather than
        # fixing it: the orphan reaches the head anyway, `mkdir`s, records its own
        # already-dead $PPID as owner, and strands the lock for the full LEASE with
        # nobody left to release it). Checked at the moment of taking the lock, not
        # once at the top: the caller can die at any point during the wait.
        if ! kill -0 "$PPID" 2>/dev/null; then
          print -r -- "declining: caller (pid $PPID) is dead; nothing to hold the lock for"
          [[ -n "$TICKET" ]] && rm -f "$TICKET" 2>/dev/null
          exit 1
        fi
        if mkdir "$LOCK" 2>/dev/null; then
          # $PPID, never $$: $$ is THIS script, which exits the instant acquire
          # returns, so a liveness check on it would find every lock stale and
          # hand it to the next caller immediately -- a mutex that never excludes.
          # $PPID is the caller's shell, which lives for the duration of its run.
          print -r -- "$PPID" > "$LOCK/pid"; print -r -- "$ID" > "$LOCK/id"; date +%s > "$LOCK/since"
          [[ -n "$TICKET" ]] && rm -f "$TICKET" 2>/dev/null
          # CADENCE_LOCK_ACQUIRE_DELAY exists for testing a caller's OWN race against this moment
          # (T-955): the lock is real and on disk the instant `mkdir` above returns, but a caller
          # that records "I hold it" only after THIS PROCESS exits has a gap between the two -- a
          # gap normally microseconds wide. This widens it to whole seconds so a plain SIGTERM sent
          # from a test can land inside it reliably. Gated under CADENCE_LOCK_TESTING for the same
          # reason every other testing knob here is: an unwanted delay on the real lock would look
          # exactly like the contention this file exists to report honestly.
          if [[ -n "${CADENCE_LOCK_TESTING:-}" && -n "${CADENCE_LOCK_ACQUIRE_DELAY:-}" ]]; then
            sleep "$CADENCE_LOCK_ACQUIRE_DELAY"
          fi
          print -r -- "acquired after ${waited}s (id $ID, owner pid $PPID)"; exit 0
        fi
        # Reclaim on a LEASE, not on liveness, and only from the head of the
        # queue -- a reclaim is a decision about someone else's run, so the one
        # caller entitled to the lock makes it. Agents run each shell command in a
        # separate process, so the pid recorded at `acquire` is already dead by the
        # time the build runs in the next call -- a liveness check therefore hands a
        # held lock straight to the next caller. Measured: one agent's lock "expired
        # during the long build window" and rolled over to two other agents while its
        # own test run was still going. A lease expires only on wall-clock age, which
        # survives the acquiring shell exiting.
        if [[ -f "$LOCK/since" ]]; then
          age=$(( $(date +%s) - $(cat "$LOCK/since" 2>/dev/null || print 0) ))
          # T-956: the owner's pulse, checked the moment we would otherwise sit out
          # the whole LEASE. $LOCK/pid is the owner shell recorded at acquire time
          # (see the $PPID comment above); if it is gone, that shell can never run
          # its `release` trap, so there is no reason to wait for lease age at all.
          owner_pid=$(cat "$LOCK/pid" 2>/dev/null)
          owner_dead=0
          [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null && owner_dead=1
          if (( age > LEASE || owner_dead )); then
            # A lease alone is not enough to reclaim, and neither is a dead owner
            # pid alone. Measured 2026-08-25: an agent's batch overran the 45-minute
            # lease by 9 seconds and a sibling took the lock while the first was
            # still mid-run -- which starts a SECOND test host against the same
            # app-group container, i.e. exactly the T-236 contention this lock
            # exists to prevent. The same risk applies to a dead owner pid: its
            # shell can die while a `nohup`'d `xcodebuild test` it started keeps
            # running detached. So either trigger still defers to a live test host:
            # if a real `xcodebuild test` is running, someone is legitimately using
            # the host no matter how old the lock is or whether its owner shell
            # survived.
            live=$(live_test_hosts)
            if (( live > 0 )); then
              if (( owner_dead )); then
                print -r -- "  owner pid $owner_pid is dead but ${live} test host(s) still running; NOT reclaiming"
              else
                print -r -- "  lease expired (${age}s) but ${live} test host(s) still running; NOT reclaiming"
              fi
              sleep "$POLL"; (( waited += POLL )); continue
            fi
            if (( owner_dead )); then
              print -r -- "owner pid $owner_pid is dead (age ${age}s), no live test host; reclaiming from $(cat "$LOCK/id" 2>/dev/null)"
            else
              print -r -- "lease expired after ${age}s (limit ${LEASE}s), no live test host; reclaiming from $(cat "$LOCK/id" 2>/dev/null)"
            fi
            rm -rf "$LOCK"; continue
          fi
        fi
      fi
      sleep "$POLL"; (( waited += POLL ))
      if (( waited % 300 < POLL )); then
        pos=1; for n in $(queue_names); do [[ "$n" == "${TICKET:t}" ]] && break; (( pos++ )); done
        print -r -- "  still waiting (${waited}s), position ${pos} of $(queue_names | wc -l | tr -d ' '), held by $(cat "$LOCK/id" 2>/dev/null) / pid $(cat "$LOCK/pid" 2>/dev/null)"
      fi
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
      # T-956: report a dead owner distinctly and first -- it is reclaimable as
      # soon as live_test_hosts is zero, regardless of lease age, so "LEASE
      # EXPIRED" alone would undersell how close a dead-owner lock is to freeing.
      if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
        alive="OWNER DEAD"
      elif (( age > LEASE )); then
        alive="LEASE EXPIRED"
      else
        alive="held"
      fi
      print -r -- "locked by ${oid:-?} / pid $owner ($alive) for ${age}s"
    else
      print -r -- "free"
    fi
    prune_queue
    n=$(queue_names | wc -l | tr -d ' ')
    if (( n > 0 )); then
      print -r -- "queue (${n} waiting, first served first):"
      now=$(date +%s)
      for t in "$QUEUE"/*(N.); do
        read -r wpid wid wsince < "$t" 2>/dev/null
        print -r -- "  ${wid:-?} / pid ${wpid:-?}, waiting $(( now - ${wsince:-$now} ))s"
      done
    else
      print -r -- "queue: empty"
    fi
    print -r -- "live test hosts: $(live_test_hosts)"
    ;;
  selftest)
    # The three properties this file has to keep, run for real rather than
    # asserted in a comment. Everything happens in a throwaway lock directory: the
    # real lock is in use by sibling agents whenever this is worth running.
    [[ -n "${CADENCE_LOCK_SELFTEST_TARGET:-}" ]] && SELF="${CADENCE_LOCK_SELFTEST_TARGET:A}"
    root=$(mktemp -d "${TMPDIR:-/tmp}/cadence-lock-selftest.XXXXXX") || exit 2
    # CADENCE_LOCK_DIR steers this script; TMPDIR steers any *other* build of it
    # (an older copy, for the failing-first comparison) to the same throwaway path.
    export CADENCE_LOCK_TESTING=1 TMPDIR="$root/" CADENCE_LOCK_DIR="$root/cadence-macos-test-host.lock"
    export CADENCE_LOCK_POLL=1 CADENCE_LOCK_LEASE=4 CADENCE_LOCK_TICKET_STALE=10
    print -r -- "selftest: target $SELF"
    print -r -- "selftest: lock $CADENCE_LOCK_DIR"
    fails=0
    kids=()
    # Kill only what this selftest started, by pid. NOT `pkill -f
    # 'test-host-lock.sh acquire'`: sibling agents are waiting on the real lock
    # with that exact command line, and a selftest that reaps their waiters would
    # be a far worse bug than the one it is testing. `pkill -P` reaches the
    # acquire grandchild, which a plain kill of the subshell would orphan.
    cleanup_kids() {
      local k
      for k in $kids; do pkill -P "$k" 2>/dev/null; kill "$k" 2>/dev/null; done
      kids=()
      wait 2>/dev/null
    }

    # 1. ORDERING, posed as the failure that was actually measured: "a short run
    #    that arrives at the right instant beats a long one that has been waiting
    #    an hour". w1..w3 queue behind a held lock; w4 arrives at the moment of
    #    release. Without a queue w4's very first `mkdir` lands on a free lock
    #    while w1..w3 are still inside their sleep, so the newest arrival is
    #    served first -- deterministically, which is why this discriminates where
    #    a trial of evenly staggered waiters does not. With the queue w4 files its
    #    ticket behind three older ones and is served last.
    waiter() {
      # `; :` keeps zsh from exec'ing the acquire in place of the subshell, so the
      # waiter is a grandchild with a parent to be cleaned up through.
      ( "$SELF" acquire 90 "$1" >/dev/null 2>&1 \
        && print -r -- "$1" >> "$order" \
        && "$SELF" release "$1" >/dev/null 2>&1; : ) &
      kids+=($!)
    }
    "$SELF" acquire 30 holder >/dev/null || { print -r -- "selftest: could not take the lock"; exit 2; }
    order="$root/order"; : > "$order"
    for w in w1 w2 w3; do waiter "$w"; sleep 1.2; done
    "$SELF" release holder >/dev/null
    waiter w4
    for _ in {1..90}; do (( $(wc -l < "$order") >= 4 )) && break; sleep 1; done
    got="$(tr '\n' ' ' < "$order")"
    if [[ "${got% }" == "w1 w2 w3 w4" ]]; then print -r -- "PASS ordering: $got"
    else print -r -- "FAIL ordering: got '${got% }', wanted 'w1 w2 w3 w4'"; (( fails++ )); fi
    cleanup_kids; rm -rf "$CADENCE_LOCK_DIR" "$CADENCE_LOCK_DIR.queue"

    # The two properties below are statements about THIS implementation -- one of
    # them needs a probe only this copy can be told to use -- so a foreign target
    # (the failing-first comparison against an older copy) stops here rather than
    # reporting a fixture gap as that copy's bug.
    if [[ -n "${CADENCE_LOCK_SELFTEST_TARGET:-}" ]]; then
      cleanup_kids; pkill -f "$root" 2>/dev/null; rm -rf "$root"
      print -r -- "selftest: foreign target, ordering only; $fails failure(s)"
      exit $(( fails > 0 ))
    fi

    # 2. A DEAD OWNER PID IS NOT A STALE LOCK. The conjunction -- expired lease AND
    #    zero live test hosts -- is what stops a second host starting against the
    #    same app-group container while a nohup'd run outlives its shell.
    export CADENCE_LOCK_PGREP="$root/fakehost"
    # A stand-in for a real `xcodebuild test`, matched through CADENCE_LOCK_PGREP.
    # It sleeps in a child, so killing it later means killing that child too --
    # a `kill $host` alone leaves the sleep holding this selftest's stdout open.
    print -r -- 'sleep 90' > "$root/fakehost"; zsh "$root/fakehost" & host=$!
    ( "$SELF" acquire 10 ghost >/dev/null; : )  # subshell exits: owner pid is now dead
    sleep 6                                     # lease (4s) has expired
    ghost_pid=$(cat "$CADENCE_LOCK_DIR/pid" 2>/dev/null)
    if kill -0 $host 2>/dev/null && [[ -d "$CADENCE_LOCK_DIR" ]] \
       && [[ -n "$ghost_pid" ]] && ! kill -0 "$ghost_pid" 2>/dev/null; then
      out="$("$SELF" acquire 6 prober 2>&1)"; rc=$?
      if (( rc != 0 )) && [[ "$out" == *"NOT reclaiming"* ]] && [[ "$(cat "$CADENCE_LOCK_DIR/id" 2>/dev/null)" == ghost ]]; then
        print -r -- "PASS no-reclaim: expired lease + live host + dead owner pid stayed with 'ghost'"
      else print -r -- "FAIL no-reclaim: rc=$rc out='$out'"; (( fails++ )); fi
    else print -r -- "FAIL no-reclaim: fixture did not set up"; (( fails++ )); fi
    pkill -P $host 2>/dev/null; kill $host 2>/dev/null; wait $host 2>/dev/null
    out="$("$SELF" acquire 20 prober 2>&1)"
    if [[ "$out" == *reclaiming* ]]; then print -r -- "PASS reclaim: with the host gone the expired lease was reclaimable"
    else print -r -- "FAIL reclaim: '$out'"; (( fails++ )); fi
    unset CADENCE_LOCK_PGREP
    cleanup_kids; rm -rf "$CADENCE_LOCK_DIR" "$CADENCE_LOCK_DIR.queue"

    # 3. A KILLED WAITER DOES NOT BLOCK THE QUEUE. SIGKILL, so no trap can help:
    #    the ticket has to be pruned by the next waiter that looks.
    "$SELF" acquire 30 holder2 >/dev/null || { print -r -- "selftest: could not retake the lock"; exit 2; }
    "$SELF" acquire 90 zombie >/dev/null 2>&1 & zpid=$!   # the script itself, so SIGKILL lands on the waiter
    sleep 2
    survivor="$root/survivor"; : > "$survivor"
    ( "$SELF" acquire 60 alive >/dev/null 2>&1 && print -r -- ok >> "$survivor" \
      && "$SELF" release alive >/dev/null 2>&1; : ) &
    kids+=($!)
    sleep 2
    kill -9 $zpid 2>/dev/null; wait $zpid 2>/dev/null
    "$SELF" release holder2 >/dev/null
    for _ in {1..40}; do [[ -s "$survivor" ]] && break; sleep 1; done
    if [[ -s "$survivor" ]]; then print -r -- "PASS killed-waiter: the waiter behind a SIGKILLed one still got the lock"
    else print -r -- "FAIL killed-waiter: queue stalled behind the dead ticket"; (( fails++ )); fi

    cleanup_kids; rm -rf "$CADENCE_LOCK_DIR" "$CADENCE_LOCK_DIR.queue"

    # 4. AN ORPHANED WAITER DECLINES RATHER THAN TAKING THE LOCK (T-748). The
    #    orphan has to be a REAL orphan, not merely a killed process: a wrapper is
    #    spawned as the acquire's actual parent, and only the WRAPPER is killed --
    #    `; :` (same trick as `waiter()` above) stops zsh exec'ing the acquire in
    #    the wrapper's place, so the acquire survives as a distinct, still-running
    #    child reparented off the dead wrapper, exactly the shape `pkill -f
    #    'run-batch-<tag>.sh'` produces against a real runner. Its own $PPID, fixed
    #    at start, still names the now-dead wrapper -- which is the fact this fix
    #    reads.
    "$SELF" acquire 30 holder3 >/dev/null || { print -r -- "selftest: could not retake the lock (dead-parent)"; exit 2; }
    ( "$SELF" acquire 90 orphan >/dev/null 2>&1; : ) &
    wrap_pid=$!
    for _ in {1..20}; do (( $(queue_names | wc -l) > 0 )) && break; sleep 0.5; done
    kill -9 $wrap_pid 2>/dev/null; wait $wrap_pid 2>/dev/null
    "$SELF" release holder3 >/dev/null   # frees the lock: the orphan is now free to reach the head
    owner=""; qn=1
    for _ in {1..20}; do
      owner=$(cat "$CADENCE_LOCK_DIR/id" 2>/dev/null)
      qn=$(queue_names | wc -l | tr -d ' ')
      [[ "$owner" == "orphan" ]] && break
      (( qn == 0 )) && break
      sleep 0.5
    done
    if [[ "$owner" != "orphan" ]] && (( qn == 0 )); then
      print -r -- "PASS dead-parent-declines: an orphaned waiter (dead PPID) did not take the lock and left the queue"
    else
      print -r -- "FAIL dead-parent-declines: lock owner='$owner', queue has ${qn} entries"; (( fails++ ))
    fi
    out="$("$SELF" acquire 20 afterward 2>&1)"; rc=$?
    if (( rc == 0 )); then
      print -r -- "PASS dead-parent-recovers: a live waiter still got the lock after the orphan declined"
      "$SELF" release afterward >/dev/null
    else
      print -r -- "FAIL dead-parent-recovers: queue stuck behind the declined orphan; rc=$rc out='$out'"; (( fails++ ))
    fi
    cleanup_kids; rm -rf "$CADENCE_LOCK_DIR" "$CADENCE_LOCK_DIR.queue"

    # 5. A DEAD LOCK OWNER RECLAIMS WITHOUT WAITING OUT THE LEASE (T-956). Property
    #    2 already proves a dead owner pid does not bypass a live test host; this
    #    proves the other half -- with no live host, a dead owner must not have to
    #    wait for LEASE to become reclaimable, which is exactly the strand this
    #    ticket fixes. LEASE is bumped far above this property's own timeout so a
    #    prompt reclaim can only be explained by the owner-pulse check, not by the
    #    lease having quietly expired anyway.
    saved_lease=$CADENCE_LOCK_LEASE
    export CADENCE_LOCK_LEASE=300
    ( "$SELF" acquire 20 deadowner2 >/dev/null 2>&1; : )  # subshell exits: owner pid dies immediately
    sleep 1
    dead_pid=$(cat "$CADENCE_LOCK_DIR/pid" 2>/dev/null)
    if [[ -n "$dead_pid" ]] && ! kill -0 "$dead_pid" 2>/dev/null; then
      start=$(date +%s)
      out="$("$SELF" acquire 15 prober2 2>&1)"; rc=$?
      elapsed=$(( $(date +%s) - start ))
      if (( rc == 0 )) && (( elapsed < 10 )); then
        print -r -- "PASS dead-owner-reclaims-early: reclaimed in ${elapsed}s despite a ${CADENCE_LOCK_LEASE}s lease"
        "$SELF" release prober2 >/dev/null
      else
        print -r -- "FAIL dead-owner-reclaims-early: rc=$rc elapsed=${elapsed}s out='$out'"; (( fails++ ))
      fi
    else
      print -r -- "FAIL dead-owner-reclaims-early: fixture did not set up (pid '$dead_pid' still alive or missing)"; (( fails++ ))
    fi
    cleanup_kids; rm -rf "$CADENCE_LOCK_DIR" "$CADENCE_LOCK_DIR.queue"

    # 5b. ...but a dead owner still defers to a live test host even with the lease
    #     bumped: the fix is "dead owner pid shortcuts the LEASE wait", not "dead
    #     owner pid always wins" -- that second reading would restart T-236.
    export CADENCE_LOCK_PGREP="$root/fakehost2"
    print -r -- 'sleep 90' > "$root/fakehost2"; zsh "$root/fakehost2" & host2=$!
    ( "$SELF" acquire 10 deadowner3 >/dev/null 2>&1; : )
    sleep 1
    dead_pid2=$(cat "$CADENCE_LOCK_DIR/pid" 2>/dev/null)
    if kill -0 $host2 2>/dev/null && [[ -n "$dead_pid2" ]] && ! kill -0 "$dead_pid2" 2>/dev/null; then
      out="$("$SELF" acquire 6 prober3 2>&1)"; rc=$?
      if (( rc != 0 )) && [[ "$out" == *"NOT reclaiming"* ]] && [[ "$(cat "$CADENCE_LOCK_DIR/id" 2>/dev/null)" == deadowner3 ]]; then
        print -r -- "PASS dead-owner-defers-to-live-host: dead owner + live host stayed with 'deadowner3'"
      else
        print -r -- "FAIL dead-owner-defers-to-live-host: rc=$rc out='$out'"; (( fails++ ))
      fi
    else
      print -r -- "FAIL dead-owner-defers-to-live-host: fixture did not set up"; (( fails++ ))
    fi
    pkill -P $host2 2>/dev/null; kill $host2 2>/dev/null; wait $host2 2>/dev/null
    unset CADENCE_LOCK_PGREP
    export CADENCE_LOCK_LEASE=$saved_lease
    cleanup_kids; rm -rf "$CADENCE_LOCK_DIR" "$CADENCE_LOCK_DIR.queue"

    cleanup_kids; pkill -f "$root" 2>/dev/null; rm -rf "$root"
    print -r -- "selftest: $fails failure(s)"
    exit $(( fails > 0 ))
    ;;
esac
