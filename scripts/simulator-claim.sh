#!/bin/zsh
# One agent per simulator device, and a private store even so.
#
# THE FAILURE THIS EXISTS FOR (docs/TODO.md T-225): two agents share one booted
# simulator. Agent A boots an iPad and seeds state; agent B lists devices, sees it
# booted, and installs its own build to it -- wiping A's data mid-run. Nothing in
# the brief told B to check whether the device was already in use.
#
# Two facts make that unavoidable without coordination:
#   1. A bundle id is unique per device. `simctl install` REPLACES whatever is
#      there; two agents cannot both own com.haoranwei.Cadence on one device.
#   2. Cadence's real store is in the APP GROUP container, which on a simulator is
#      one device-wide directory -- verified on the live fleet:
#        .../Devices/<udid>/data/Containers/Shared/AppGroup/<uuid>/
#           Library/Application Support/Cadence/default.store
#      It survives reinstall and is shared by every install of the app. Two agents
#      launching on one device are two writers on one SQLite file.
#
# So this script does BOTH halves, and both are load-bearing:
#   * An exclusive per-device CLAIM (atomic `mkdir`, same mutex shape as
#     scripts/test-host-lock.sh) so only one agent installs/launches on a device.
#     This is what stops the install from clobbering; a store id cannot, because
#     install replaces the bundle no matter where the data goes.
#   * A per-agent STORE ID, the way scripts/run-macos-app.sh does it, passed
#     through `SIMCTL_CHILD_CADENCE_UI_TEST_STORE_ID`. `PersistenceController`
#     redirects the store to <app data container>/tmp/CadenceUITestStores/<id>/,
#     so the shared app-group store above is never opened at all. Defence in
#     depth: if the claim is ever wrong, the two agents still do not merge data.
#     `SIMCTL_CHILD_CADENCE_LOCAL_STORE_ONLY=1` comes with it -- no CloudKit.
#   * A per-agent USER DEFAULTS SUITE, passed as the launch argument
#     `-CadenceSuiteName <id>` (T-735). The store id above isolates SwiftData and
#     NOTHING ELSE: every @AppStorage value and every remembered scroll position
#     lives in one device-wide defaults domain that survives reinstall. That cost
#     twenty minutes on 2026-09-03, when the compact Calendar tab opened on August
#     2026 with Aug 17 selected against an EMPTY private store -- which reads as a
#     date bug and was another agent's leftover position. `CadenceDefaults` reads
#     the argument (NSArgumentDomain, per-launch, nothing persisted) and the scene
#     redirects `@AppStorage` to that suite. NOT covered: an app started by tapping
#     its icon carries no launch arguments and is back on the shared domain.
#
# WHAT THIS SCRIPT WILL NEVER DO, each because it was done and cost something:
#   * It has no `create` command. Cloning a device per agent is how the pool went
#     3.8 GB -> 7.7 GB in one batch; a created device keeps all its data after
#     `shutdown`. If every booted device is claimed, `claim` WAITS.
#   * It has no `erase`, `shutdown` or `delete`. `release` leaves the device
#     booted and byte-identical -- you did not create it, so it is not yours to
#     reclaim.
#   * It has no `privacy` command and never will. `simctl privacy` KILLS the
#     running app by design (tccd: "Terminating com.haoranwei.Cadence[...]"), on
#     whatever agent happens to be driving it, and it reads exactly like a crash.
#     That misread cost T-267 a top-priority ticket against an innocent view.
#   * It kills nothing. Nothing here matches on the name "Cadence" and sends a
#     signal; the user's own Mac app is usually running and killing it once cost
#     them two hours.
#
#   ./scripts/simulator-claim.sh                       # status; changes nothing
#   ./scripts/simulator-claim.sh claim  <id> [timeout]  # blocks; prints UDID=...
#   ./scripts/simulator-claim.sh env    <id>            # eval-able exports
#   ./scripts/simulator-claim.sh boot           [--apply]
#   ./scripts/simulator-claim.sh install <id> <app.app> [--apply]
#   ./scripts/simulator-claim.sh launch  <id>           [--apply] [--relaunch]
#   ./scripts/simulator-claim.sh renew   <id>
#   ./scripts/simulator-claim.sh release <id>
#   ./scripts/simulator-claim.sh selftest                # proves the queue is fair
#
# Like agent-cleanup.sh, the commands that touch a DEVICE report by default and
# act only with --apply. claim/env/renew/release touch nothing but $TMPDIR.
#
# Typical use -- and note the trap, because a claim released only on the happy
# path is a device no sibling can take until the lease runs out:
#   ./scripts/simulator-claim.sh claim b4 1800 || exit 1
#   trap './scripts/simulator-claim.sh release b4' EXIT INT TERM
#   eval "$(./scripts/simulator-claim.sh env b4)"   # $CADENCE_SIM_UDID + the redirect
#   ./scripts/simulator-claim.sh install b4 "$APP" --apply
#   ./scripts/simulator-claim.sh launch  b4 --apply
#
# WHY `claim` IS A FIFO QUEUE (T-749). It was a plain `sleep 5; waited += 5` poll,
# the exact shape `scripts/test-host-lock.sh` had before T-650: excluding is not
# the same as ordering, so the winner on every release was whoever's poll happened
# to land right after it, not whoever had been waiting longest. Measured in the
# same batch that produced T-650's 65-minute test-host starvation: a 16-minute
# claim wait, on the same "arrived first, served last" shape. The fix is the same
# fix, ported rather than reinvented: a waiter files a ticket on arrival, and only
# the ticket at the head of the queue may attempt to claim a device. Everyone else
# stands aside, so "next" means "waiting longest".

set -uo pipefail
# zsh writes here-document temp files to $TMPPREFIX, which zsh itself sets at startup to
# `/tmp/zsh` -- never $TMPDIR, and never empty, so a `[[ -z $TMPPREFIX ]]` guard would never fire.
# A caller that cannot write /tmp (an App-Sandboxed test host, for one) dies with "can't create
# temp file for here document" before `selftest`'s fake `simctl` is even written. Same fix as
# scripts/mutate.sh, which found this first (T-719): point it at $TMPDIR.
_tmp_base="${TMPDIR:-/tmp/}"; [[ "$_tmp_base" != */ ]] && _tmp_base="$_tmp_base/"
export TMPPREFIX="${CADENCE_TMPPREFIX:-${_tmp_base}zsh}"

SIMCTL=${CADENCE_SIMCTL:-"xcrun simctl"}
BUNDLE_ID=${CADENCE_BUNDLE_ID:-com.haoranwei.Cadence}
CLAIMS="${TMPDIR:-/tmp}/CadenceSimClaims"
# CADENCE_SIM_CLAIMS_DIR exists so `selftest` can exercise this script without
# touching the real claims directory, which sibling agents may be using while you
# read this. Honoured ONLY under CADENCE_SIM_CLAIM_TESTING, same reason as
# test-host-lock.sh's CADENCE_LOCK_DIR: a stray override in a real agent's
# environment would silently split the claim store in two and hand back exactly
# the double-booked device this script exists to prevent.
[[ -n "${CADENCE_SIM_CLAIM_TESTING:-}" && -n "${CADENCE_SIM_CLAIMS_DIR:-}" ]] && CLAIMS="$CADENCE_SIM_CLAIMS_DIR"
mkdir -p "$CLAIMS"

# A claim survives this long without a renew before anyone may reclaim it. Long
# enough for a cold build + install + a driven session; short enough that an agent
# killed mid-run does not hold a device all night.
LEASE=${CADENCE_SIM_LEASE:-2700}
# CADENCE_SIM_LEASE exists for testing this script, and is floored at the default
# unless CADENCE_SIM_CLAIM_TESTING is set -- the same guard test-host-lock.sh
# needed after a short override reclaimed a lock a live agent was holding.
(( LEASE < 2700 )) && [[ -z "${CADENCE_SIM_CLAIM_TESTING:-}" ]] && LEASE=2700

CMD="${1:-status}"
APPLY=0; RELAUNCH=0; typeset -a POS; POS=()
if (( $# > 1 )); then
  for a in "${@[2,-1]}"; do
    case "$a" in
      --apply)    APPLY=1 ;;
      --relaunch) RELAUNCH=1 ;;
      --*) print -r -- "unknown flag: $a"; exit 2 ;;
      *) POS+=("$a") ;;
    esac
  done
fi

SELF="${ZSH_ARGZERO:-$0}"

say() { print -r -- "$@" }

booted_udids() {
  ${=SIMCTL} list devices booted 2>/dev/null \
    | sed -n 's/.*(\([0-9A-Fa-f-]\{8\}-[0-9A-Fa-f-]*\)) (Booted).*/\1/p'
}
device_name() {
  ${=SIMCTL} list devices booted 2>/dev/null | grep -- "$1" \
    | sed 's/^ *//; s/ (.*//' | head -1
}
claim_field() { cat "$CLAIMS/$1.claim/$2" 2>/dev/null }
claim_age()   { local s; s=$(claim_field "$1" since); print -r -- $(( $(date +%s) - ${s:-0} )) }

# "Is somebody legitimately mid-operation on this device right now?" A claim's
# recorded pid is useless for this: agents run each command in a fresh process, so
# the acquiring shell is already gone by the time the build runs (test-host-lock.sh
# learned that the hard way and reclaims on a LEASE for the same reason). What is
# meaningful is a live `simctl` aimed at this udid -- an install or a --console
# launch. ANCHOR on the word simctl: an unanchored match on the udid alone would
# also match every waiting agent's own claim loop, which is how a mutex inverts
# into a deadlock.
live_simctl_for() { pgrep -f "simctl .*$1" 2>/dev/null | wc -l | tr -d ' ' }

claim_udid_for_id() {
  local c u
  for c in "$CLAIMS"/*.claim(N/); do
    u=${${c:t}%.claim}
    [[ "$(cat "$c/id" 2>/dev/null)" == "$1" ]] && { print -r -- "$u"; return 0 }
  done
  return 1
}

# --- the fairness queue (T-749) -----------------------------------------------
# Ported from scripts/test-host-lock.sh's T-650 fix rather than reinvented; see
# that file for the property in full. The one thing that does NOT carry over
# unchanged: `$QUEUE` is `"${CLAIMS}.queue"`, a SIBLING of `$CLAIMS`, not a
# directory under it. `release` only ever `rm -rf`s one device's OWN
# `$CLAIMS/$u.claim`, never `$CLAIMS` itself, so a queue nested inside `$CLAIMS`
# would in fact survive today -- but the lesson test-host-lock.sh paid for is that
# the queue must outlive whatever it is a queue FOR, on its own, not because
# nothing currently deletes the parent. A sibling is safe against both the
# reclaim path above and anything a future command does to `$CLAIMS` wholesale.
QUEUE="${CLAIMS}.queue"
# How often a waiter looks, and how long an untouched ticket may sit before it is
# read as abandoned. Same defaults and same reasoning as CADENCE_LOCK_POLL /
# CADENCE_LOCK_TICKET_STALE in test-host-lock.sh.
POLL=${CADENCE_SIM_CLAIM_POLL:-5}
TICKET_STALE=${CADENCE_SIM_CLAIM_TICKET_STALE:-60}
zmodload zsh/datetime 2>/dev/null
arrival_stamp() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then printf '%017.6f' "$EPOCHREALTIME"
  else printf '%017.6f' "$(date +%s).000000"
  fi
}
# Alive, AND still this script -- a recycled pid landing on some unrelated
# long-lived process must not pin a dead waiter at the head forever.
waiter_alive() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [[ "$(ps -o command= -p "$pid" 2>/dev/null)" == *simulator-claim* ]]
}
# Liveness catches a killed waiter immediately; the touch-age catches what
# liveness cannot -- a stopped process, a pid reused by another copy of this
# script, a ticket orphaned by a reboot mid-batch. A live waiter that loses its
# ticket to this re-files it under its ORIGINAL arrival stamp (see the `claim`
# loop below), so pruning can never cost anyone their place in line; the worst
# case is a redundant write.
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
# In arrival order, one name per line -- and nothing at all when empty. A bare
# `print -rl --` with no arguments still emits a newline, which would make an
# empty queue read as one waiter and put every caller behind a phantom.
queue_names() {
  local -a t; t=("$QUEUE"/*(N.:t))
  (( ${#t} )) && print -rl -- "${t[@]}"
  return 0
}

# Every device-touching command routes through here, so "dry run by default" is
# one decision in one place rather than three that can drift.
run_or_report() {
  if (( APPLY )); then
    say "  running: $1"
    eval "$1"
    return $?
  fi
  say "  would run: $1"
  say "  (dry run -- pass --apply)"
  return 0
}

# The refusal goes to STDERR. Callers read this function's stdout to get the udid,
# so a refusal printed there is a refusal the agent never sees -- it lands in a
# variable and the exit code carries the whole message.
require_claim() {
  local id="$1" u
  u=$(claim_udid_for_id "$id") || {
    print -r -- "REFUSING: '$id' holds no simulator claim. Run: $SELF claim $id" >&2
    print -r -- "  Installing without one is exactly T-225: you would replace whatever" >&2
    print -r -- "  build and app-group store another agent is mid-run on." >&2
    return 1
  }
  print -r -- "$u"
}

emit_claim() {
  local u="$1" how="$2" id="$3"
  say "UDID=$u"
  say "DEVICE=$(device_name "$u")"
  say "STORE_ID=$id   ($how)"
  say ""
  say "  eval \"\$($SELF env $id)\"    # UDID + the SIMCTL_CHILD_ store redirect"
  say "  $SELF release $id            # in this same turn, via a trap"
}

case "$CMD" in

  status)
    say "== booted simulators =="
    typeset -a booted; booted=($(booted_udids))
    if (( ${#booted} == 0 )); then
      say "  (none) -- '$SELF boot --apply' will start ONE stock device. Never create one."
    fi
    for u in $booted; do
      if [[ -d "$CLAIMS/$u.claim" ]]; then
        age=$(claim_age "$u")
        state=$( (( age > LEASE )) && print "LEASE EXPIRED" || print held )
        say "  CLAIMED by '$(claim_field "$u" id)' for ${age}s ($state)  $(device_name "$u")  ($u)"
      else
        say "  free                                        $(device_name "$u")  ($u)"
      fi
    done
    say "== claims on devices that are no longer booted =="
    for c in "$CLAIMS"/*.claim(N/); do
      u=${${c:t}%.claim}
      (( ${booted[(I)$u]} )) || say "  stale: '$(cat "$c/id" 2>/dev/null)' on $u (device not booted)"
    done
    prune_queue
    n=$(queue_names | wc -l | tr -d ' ')
    if (( n > 0 )); then
      say "== claim queue (${n} waiting, first served first) =="
      now=$(date +%s)
      for t in "$QUEUE"/*(N.); do
        read -r wpid wid wsince < "$t" 2>/dev/null
        say "  ${wid:-?} / pid ${wpid:-?}, waiting $(( now - ${wsince:-$now} ))s"
      done
    else
      say "== claim queue: empty =="
    fi
    say "  lease ${LEASE}s"
    ;;

  claim)
    ID="${POS[1]:-agent-$PPID}"; TIMEOUT="${POS[2]:-1800}"; waited=0
    # Re-entrant on purpose. An agent gets one process per command, so `claim`
    # is routinely re-run across calls in one session; without this it would
    # take a SECOND device each time and starve the fleet it is protecting.
    # Bypasses the queue entirely: an agent that already holds a claim is not
    # competing for one.
    if existing=$(claim_udid_for_id "$ID"); then
      date +%s > "$CLAIMS/$existing.claim/since"
      emit_claim "$existing" "already held, lease renewed" "$ID"; exit 0
    fi
    # File a ticket before the first attempt, so arrival order is recorded even
    # for the caller that finds a free device and never waits. Degrades to the
    # old unfair-but-not-deadlocked behaviour if $TMPDIR cannot be written to.
    TICKET=""
    if mkdir -p "$QUEUE" 2>/dev/null; then
      TICKET="$QUEUE/$(arrival_stamp)-$$"
      print -r -- "$$ $ID $(date +%s)" > "$TICKET"
      trap 'rm -f "$TICKET" 2>/dev/null' EXIT INT TERM
    fi
    while (( waited <= TIMEOUT )); do
      if [[ -n "$TICKET" ]]; then
        if [[ -f "$TICKET" ]]; then touch "$TICKET" 2>/dev/null
        else print -r -- "$$ $ID $(date +%s)" > "$TICKET" 2>/dev/null; fi
        prune_queue
      fi
      local -a udids; udids=($(booted_udids))
      if (( ${#udids} == 0 )); then
        say "no booted simulator. This script will NOT create one."
        say "  $SELF boot --apply     # boots one stock device, under a lock"
        [[ -n "$TICKET" ]] && rm -f "$TICKET" 2>/dev/null
        exit 4
      fi
      # Only the head of the queue may attempt a device. This is the actual T-749
      # fix: without it, every waiter races `mkdir` on every release regardless of
      # who filed first, which is exactly the measured 16-minute starvation.
      first=""
      [[ -n "$TICKET" ]] && first="$(queue_names | head -1)"
      if [[ -z "$first" || "$first" == "${TICKET:t}" ]]; then
        for u in $udids; do
          if mkdir "$CLAIMS/$u.claim" 2>/dev/null; then
            # $PPID, not $$: this script exits the moment claim returns.
            print -r -- "$ID"   > "$CLAIMS/$u.claim/id"
            print -r -- "$PPID" > "$CLAIMS/$u.claim/pid"
            date +%s            > "$CLAIMS/$u.claim/since"
            [[ -n "$TICKET" ]] && rm -f "$TICKET" 2>/dev/null
            emit_claim "$u" "acquired after ${waited}s" "$ID"; exit 0
          fi
          # Lost the mkdir race, or it was already claimed. Either way move to the
          # next device rather than failing -- with several booted devices two
          # agents starting together should end up on two of them, not one queued
          # behind the other.
          age=$(claim_age "$u"); owner=$(claim_field "$u" id)
          if (( age > LEASE )); then
            live=$(live_simctl_for "$u")
            if (( live > 0 )); then
              say "  $u: lease expired (${age}s) but ${live} live simctl op(s); NOT reclaiming"
              continue
            fi
            say "  $u: reclaiming from '$owner' (lease ${age}s > ${LEASE}s, no live simctl)"
            rm -rf "$CLAIMS/$u.claim"
          fi
        done
      fi
      sleep "$POLL"; (( waited += POLL ))
      if (( waited % 120 < POLL )); then
        if [[ -n "$TICKET" ]]; then
          pos=1; for n in $(queue_names); do [[ "$n" == "${TICKET:t}" ]] && break; (( pos++ )); done
          say "  still waiting (${waited}s), position ${pos} of $(queue_names | wc -l | tr -d ' '); all ${#udids} booted device(s) claimed"
        else
          say "  still waiting (${waited}s); all ${#udids} booted device(s) claimed"
        fi
      fi
    done
    [[ -n "$TICKET" ]] && rm -f "$TICKET" 2>/dev/null
    say "TIMED OUT after ${TIMEOUT}s; did NOT claim. Do not install anyway --"
    say "there is a live agent on every booted device."
    exit 1
    ;;

  env)
    ID="${POS[1]:?usage: $SELF env <id>}"
    u=$(require_claim "$ID") || exit 3
    print -r -- "export CADENCE_SIM_UDID=$u"
    print -r -- "export CADENCE_SIM_STORE_ID=$ID"
    print -r -- "export SIMCTL_CHILD_CADENCE_LOCAL_STORE_ONLY=1"
    print -r -- "export SIMCTL_CHILD_CADENCE_UI_TEST_STORE_ID=$ID"
    ;;

  boot)
    # The boot DECISION is serialised, not just the boot. Two agents that both see
    # an empty fleet both boot, and that is one of the ways the pool grows.
    BOOTLOCK="$CLAIMS/.boot.lock"; waited=0
    until mkdir "$BOOTLOCK" 2>/dev/null; do
      if [[ -f "$BOOTLOCK/since" ]] && (( $(date +%s) - $(cat "$BOOTLOCK/since") > 300 )); then
        rm -rf "$BOOTLOCK"; continue
      fi
      sleep 5; (( waited += 5 )); (( waited > 300 )) && { say "boot lock stuck"; exit 5 }
    done
    date +%s > "$BOOTLOCK/since"
    typeset -a booted; booted=($(booted_udids))
    if (( ${#booted} > 0 )); then
      say "already booted: $(device_name ${booted[1]}) (${booted[1]}) -- not booting a second device."
      rm -rf "$BOOTLOCK"; exit 0
    fi
    # A STOCK device, chosen by name from what is already in the pool. Never
    # `simctl create`, and never a device whose name looks agent-made.
    target=$(${=SIMCTL} list devices available 2>/dev/null \
      | grep -E '^ +iPhone [0-9]' | grep -viE 'agent|cadence' \
      | sed -n 's/.*(\([0-9A-Fa-f-]\{8\}-[0-9A-Fa-f-]*\)).*/\1/p' | head -1)
    [[ -n "$target" ]] || { say "no stock iPhone available"; rm -rf "$BOOTLOCK"; exit 5 }
    say "== boot =="
    say "  target: $target"
    run_or_report "${SIMCTL} boot $target && ${SIMCTL} bootstatus $target -b"
    rm -rf "$BOOTLOCK"
    ;;

  install)
    ID="${POS[1]:?usage: $SELF install <id> <app> [--apply]}"; APP="${POS[2]:-}"
    [[ -d "$APP" ]] || { say "usage: $SELF install <id> <path/to/Cadence.app> [--apply]"; exit 2 }
    u=$(require_claim "$ID") || exit 3
    date +%s > "$CLAIMS/$u.claim/since"
    say "== install on $u (claimed by '$ID') =="
    run_or_report "${SIMCTL} install $u ${(q)APP}"
    ;;

  launch)
    ID="${POS[1]:?usage: $SELF launch <id> [--apply]}"
    u=$(require_claim "$ID") || exit 3
    date +%s > "$CLAIMS/$u.claim/since"
    # --terminate-running-process is opt-in. We hold this device exclusively so
    # the only copy of the app on it is ours, but nothing here should terminate
    # anything by default -- see the header.
    extra=$( (( RELAUNCH )) && print -- " --terminate-running-process" || print -- "" )
    say "== launch on $u with a private store and a private defaults suite =="
    say "  store:    <app data container>/tmp/CadenceUITestStores/$ID/default.store"
    say "  defaults: com.haoranwei.Cadence.agent.$ID   (-CadenceSuiteName, T-735)"
    say "  the shared app-group store (Library/Application Support/Cadence) is not opened"
    run_or_report "SIMCTL_CHILD_CADENCE_LOCAL_STORE_ONLY=1 SIMCTL_CHILD_CADENCE_UI_TEST_STORE_ID=${(q)ID} ${SIMCTL} launch$extra $u $BUNDLE_ID -CadenceSuiteName ${(q)ID}"
    ;;

  renew)
    ID="${POS[1]:?usage: $SELF renew <id>}"
    u=$(require_claim "$ID") || exit 3
    date +%s > "$CLAIMS/$u.claim/since"
    say "renewed: '$ID' on $u"
    ;;

  release)
    ID="${POS[1]:?usage: $SELF release <id>}"; found=0
    # Only ever removes a claim whose recorded id is ours. There is no override:
    # freeing a stranger's claim is the same act as the install this file exists
    # to prevent, one step earlier.
    for c in "$CLAIMS"/*.claim(N/); do
      u=${${c:t}%.claim}
      if [[ "$(cat "$c/id" 2>/dev/null)" == "$ID" ]]; then
        rm -rf "$c"; say "released $u ('$ID')"; found=1
      fi
    done
    (( found )) || say "no claim held by '$ID' (already released, or never taken)"
    say "  device left BOOTED and untouched -- not shut down, not erased, not deleted."
    ;;

  selftest)
    # The two properties the queue exists for, run for real rather than asserted
    # in a comment -- same shape as test-host-lock.sh's selftest, and for the same
    # reason: a fairness fix nobody re-runs is a habit, not a guarantee. Everything
    # happens against a throwaway claims root and a fake `simctl`: the real fleet
    # may have sibling agents on it while this is worth running.
    root=$(mktemp -d "${TMPDIR:-/tmp}/cadence-sim-claim-selftest.XXXXXX") || exit 2
    FAKE_UDID="11111111-2222-3333-4444-555555555555"
    cat > "$root/fake-simctl" <<FAKESIMCTL
#!/bin/zsh
if [[ "\$1 \$2 \$3" == "list devices booted" ]]; then
  print -r -- "-- iOS 18.0 --"
  print -r -- "    iPhone SelftestFake (${FAKE_UDID}) (Booted)"
fi
exit 0
FAKESIMCTL
    chmod +x "$root/fake-simctl"
    CADENCE_SIM_CLAIMS_DIR="$root/CadenceSimClaims"
    # `/bin/zsh <path>`, not the bare path: an App-Sandboxed caller (T-719's family of findings)
    # can fail to exec a freshly-written, freshly-chmod'd file directly, even with +x set, while
    # exec'ing the already-trusted `zsh` binary and handing it the path as a script argument works.
    # Measured 2026-09-04 inside CadenceGuardScriptSelftestTests: the bare-path form died with
    # "could not claim the fake device" and nothing else, before `booted_udids` ever saw a device.
    export CADENCE_SIM_CLAIM_TESTING=1 CADENCE_SIM_CLAIMS_DIR CADENCE_SIMCTL="/bin/zsh $root/fake-simctl"
    export CADENCE_SIM_LEASE=4 CADENCE_SIM_CLAIM_POLL=1 CADENCE_SIM_CLAIM_TICKET_STALE=10
    print -r -- "selftest: target $SELF"
    print -r -- "selftest: claims $CADENCE_SIM_CLAIMS_DIR, fake device $FAKE_UDID"
    fails=0
    kids=()
    # Kill only what this selftest started, by pid -- not a name-pattern kill,
    # which on this script would match every sibling agent's own `claim` wait
    # loop against the REAL fleet.
    cleanup_kids() {
      local k
      for k in $kids; do pkill -P "$k" 2>/dev/null; kill "$k" 2>/dev/null; done
      kids=()
      wait 2>/dev/null
    }

    # 1. ORDERING, posed as the failure T-749 actually measured: with exactly one
    #    booted (fake) device, w1..w3 queue behind a held claim and w4 arrives at
    #    the moment of release. Without a queue, w4's very first `mkdir` lands on
    #    the just-freed claim while w1..w3 are still inside their poll sleep -- the
    #    newest arrival served first, deterministically. With the queue, w4 files
    #    behind three older tickets and goes last.
    waiter() {
      ( "$SELF" claim "$1" 90 >/dev/null 2>&1 \
        && print -r -- "$1" >> "$order" \
        && "$SELF" release "$1" >/dev/null 2>&1; : ) &
      kids+=($!)
    }
    "$SELF" claim holder 30 >/dev/null || { print -r -- "selftest: could not claim the fake device"; exit 2; }
    order="$root/order"; : > "$order"
    for w in w1 w2 w3; do waiter "$w"; sleep 1.2; done
    "$SELF" release holder >/dev/null
    waiter w4
    for _ in {1..90}; do (( $(wc -l < "$order") >= 4 )) && break; sleep 1; done
    got="$(tr '\n' ' ' < "$order")"
    if [[ "${got% }" == "w1 w2 w3 w4" ]]; then print -r -- "PASS ordering: $got"
    else print -r -- "FAIL ordering: got '${got% }', wanted 'w1 w2 w3 w4'"; (( fails++ )); fi
    cleanup_kids; rm -rf "$CADENCE_SIM_CLAIMS_DIR" "${CADENCE_SIM_CLAIMS_DIR}.queue"; mkdir -p "$CADENCE_SIM_CLAIMS_DIR"

    # 2. A KILLED WAITER DOES NOT BLOCK THE QUEUE. SIGKILL, so no trap can help:
    #    the ticket has to be pruned by the next waiter that looks -- this is the
    #    prune_queue liveness check, exercised for real rather than read off it.
    "$SELF" claim holder2 30 >/dev/null || { print -r -- "selftest: could not reclaim the fake device"; exit 2; }
    "$SELF" claim zombie 90 >/dev/null 2>&1 & zpid=$!   # the script itself, so SIGKILL lands on the waiter
    sleep 2
    survivor="$root/survivor"; : > "$survivor"
    ( "$SELF" claim alive 60 >/dev/null 2>&1 && print -r -- ok >> "$survivor" \
      && "$SELF" release alive >/dev/null 2>&1; : ) &
    kids+=($!)
    sleep 2
    kill -9 $zpid 2>/dev/null; wait $zpid 2>/dev/null
    "$SELF" release holder2 >/dev/null
    for _ in {1..40}; do [[ -s "$survivor" ]] && break; sleep 1; done
    if [[ -s "$survivor" ]]; then print -r -- "PASS killed-waiter: the waiter behind a SIGKILLed one still got the device"
    else print -r -- "FAIL killed-waiter: queue stalled behind the dead ticket"; (( fails++ )); fi

    cleanup_kids; pkill -f "$root" 2>/dev/null; rm -rf "$root"
    print -r -- "selftest: $fails failure(s)"
    exit $(( fails > 0 ))
    ;;

  *)
    say "usage: $SELF [status|claim|env|boot|install|launch|renew|release|selftest]"; exit 2
    ;;
esac
