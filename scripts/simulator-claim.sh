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

set -uo pipefail

SIMCTL=${CADENCE_SIMCTL:-"xcrun simctl"}
BUNDLE_ID=${CADENCE_BUNDLE_ID:-com.haoranwei.Cadence}
CLAIMS="${TMPDIR:-/tmp}/CadenceSimClaims"
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
    say "  lease ${LEASE}s"
    ;;

  claim)
    ID="${POS[1]:-agent-$PPID}"; TIMEOUT="${POS[2]:-1800}"; waited=0
    # Re-entrant on purpose. An agent gets one process per command, so `claim`
    # is routinely re-run across calls in one session; without this it would
    # take a SECOND device each time and starve the fleet it is protecting.
    if existing=$(claim_udid_for_id "$ID"); then
      date +%s > "$CLAIMS/$existing.claim/since"
      emit_claim "$existing" "already held, lease renewed" "$ID"; exit 0
    fi
    while (( waited <= TIMEOUT )); do
      local -a udids; udids=($(booted_udids))
      if (( ${#udids} == 0 )); then
        say "no booted simulator. This script will NOT create one."
        say "  $SELF boot --apply     # boots one stock device, under a lock"
        exit 4
      fi
      for u in $udids; do
        if mkdir "$CLAIMS/$u.claim" 2>/dev/null; then
          # $PPID, not $$: this script exits the moment claim returns.
          print -r -- "$ID"   > "$CLAIMS/$u.claim/id"
          print -r -- "$PPID" > "$CLAIMS/$u.claim/pid"
          date +%s            > "$CLAIMS/$u.claim/since"
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
      sleep 5; (( waited += 5 ))
      (( waited % 120 == 0 )) && say "  still waiting (${waited}s); all ${#udids} booted device(s) claimed"
    done
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
    say "== launch on $u with a private store =="
    say "  store: <app data container>/tmp/CadenceUITestStores/$ID/default.store"
    say "  the shared app-group store (Library/Application Support/Cadence) is not opened"
    run_or_report "SIMCTL_CHILD_CADENCE_LOCAL_STORE_ONLY=1 SIMCTL_CHILD_CADENCE_UI_TEST_STORE_ID=${(q)ID} ${SIMCTL} launch$extra $u $BUNDLE_ID"
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

  *)
    say "usage: $SELF [status|claim|env|boot|install|launch|renew|release]"; exit 2
    ;;
esac
