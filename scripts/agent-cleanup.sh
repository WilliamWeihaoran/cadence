#!/bin/zsh
# Reclaim everything a coding agent can leak on this machine.
#
# Written because the same three leaks kept recurring and each one presents as
# something else: leaked simulators drive the load average past 40 and kill other
# agents on a 600s watchdog; a hung macOS Cadence build sits as a second writer on
# the user's real CloudKit-backed store until they force-quit it; and leftover
# verification trees filled the disk twice, at which point git starts failing with
# `mmap failed: Operation canceled` and reads exactly like repo corruption.
#
#   ./scripts/agent-cleanup.sh          # report only, changes nothing
#   ./scripts/agent-cleanup.sh --apply  # actually reclaim
#
# SAFE BY CONSTRUCTION: only ever touches simulator devices whose name matches
# an agent-created pattern, Cadence processes owned by a *simulator* or a debug
# build, and scratch directories under this session's scratchpad root. It never
# touches stock simulators, the user's installed Cadence, or another project's
# devices (e.g. PoolStats-ClaudeSession).

set -uo pipefail
APPLY=0; [[ "${1:-}" == "--apply" ]] && APPLY=1
SCRATCH_ROOT="/private/tmp/claude-501"
say() { print -r -- "$@" }
run() { if (( APPLY )); then eval "$1" >/dev/null 2>&1; else say "    would run: $1"; fi }

say "== agent-created simulator devices =="
# Anything an agent named for itself. Stock devices ("iPhone 17 Pro") never match.
xcrun simctl list devices -j 2>/dev/null | python3 -c "
import json,sys,re
pat = re.compile(r'(Cadence[-_].*Agent|.*-Agent(-iPad)?$|agent-t[0-9]+)', re.I)
for rt, devs in json.load(sys.stdin)['devices'].items():
    for d in devs:
        if pat.search(d.get('name','')):
            print(d['udid'], d['state'], d['name'])
" | while read -r udid state name; do
  say "  $state  $name  ($udid)"
  run "xcrun simctl shutdown $udid"
  run "xcrun simctl delete $udid"
done

say "== Cadence processes that should not outlive a run =="
# A macOS debug build launched by hand writes to the real app-group store, and has
# hung and needed a force-quit. But `Build/Products/Debug/Cadence.app` ALSO matches
# xcodebuild's own test host, which is a legitimate, short-lived process — killing
# it mid-suite destroys another agent's run and looks like a flaky test. So: skip
# every match while any xcodebuild is alive, and only reclaim ones that are stale.
_xcb=$(pgrep -f "Developer/usr/bin/xcodebuild" 2>/dev/null | wc -l | tr -d " ")
pgrep -fl "Build/Products/Debug/Cadence.app" 2>/dev/null | while read -r pid rest; do
  age=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d " ")
  if (( _xcb > 0 )); then
    say "  macOS debug build  pid $pid  age $age  -- xcodebuild is running, this is probably its TEST HOST; left alone"
  elif [[ "$age" == *-* || "$age" == *:*:* ]]; then
    say "  macOS debug build  pid $pid  age $age  (stale, >1h)"
    run "kill $pid"
  else
    say "  macOS debug build  pid $pid  age $age  -- recent; left alone"
  fi
done
# Private stores from run-macos-app.sh whose process is gone.
for sd in ${TMPDIR:-/tmp}/CadenceUITestStores/*(N/); do
  say "  orphaned private store  ${sd:t}"
  run "rm -rf ${(q)sd}"
done
# Orphaned MCP servers hold default.store / -shm / -wal open; four were once found
# holding the user's live store for 25 hours.
pgrep -x CadenceMCPServer 2>/dev/null | while read -r pid; do
  say "  CadenceMCPServer  pid $pid  (holds $(lsof -p $pid 2>/dev/null | grep -c com.haoranwei.Cadence) store handles)"
  run "kill $pid"
done

say "== simulator claims (scripts/simulator-claim.sh) =="
# A claim is a directory, not a process, so an agent killed mid-run leaves one and
# the device it names is unavailable to siblings until its lease runs out.
# --apply reclaims ONLY claims naming a device that is no longer booted: those are
# unambiguously dead. An expired lease on a *booted* device is merely reported --
# a sibling may be legitimately mid-run and simply slower than its lease, and
# `simulator-claim.sh claim` already reclaims that case itself, after checking for
# a live simctl op. Deleting it from here would be the T-225 install one step
# earlier: taking a device out from under an agent that is still using it.
_booted=$(xcrun simctl list devices booted 2>/dev/null | sed -n 's/.*(\([0-9A-Fa-f-]\{8\}-[0-9A-Fa-f-]*\)) (Booted).*/\1/p')
for c in ${TMPDIR:-/tmp}/CadenceSimClaims/*.claim(N/); do
  udid=${${c:t}%.claim}
  age=$(( $(date +%s) - $(cat "$c/since" 2>/dev/null || print 0) ))
  owner=$(cat "$c/id" 2>/dev/null)
  if print -r -- "$_booted" | grep -q "$udid"; then
    if (( age > 2700 )); then
      say "  '$owner' on $udid, ${age}s (LEASE EXPIRED) -- device still booted; left alone, claim reclaims it"
    else
      say "  '$owner' on $udid, ${age}s (held) -- left alone"
    fi
  else
    say "  '$owner' on $udid, ${age}s -- device is NOT booted, so nobody can be using it"
    run "rm -rf ${(q)c}"
  fi
done

say "== stranded builds =="
# Match the binary path: `pgrep -f "xcodebuild test"` also matches the shell running
# this script, so a wait loop written that way never exits.
pgrep -f "Developer/usr/bin/xcodebuild" 2>/dev/null | while read -r pid; do
  say "  xcodebuild  pid $pid  elapsed $(ps -o etime= -p $pid | tr -d ' ')"
done
say "  (not killed automatically — a live build may be another agent's)"

say "== scratch directories =="
# ONLY stale ones. A directory an agent is still building in must never be deleted:
# an isolated tree removed from under a running build makes the failed `cd` fall
# through to the live repo, and the run then reports exit 0 against the wrong
# sources. Staleness = untouched for 30 minutes, which a live build never is.
# `find -newermt` is NOT usable for this. Measured 2026-08-27: on this machine it
# matches nothing even against a file created one second ago, so every directory read
# as stale and `--apply` deleted live agents' trees -- it took a running agent's
# isolated copy out from under it mid-run. Compare mtimes numerically instead.
for d in "$SCRATCH_ROOT"/*/*/scratchpad/(agent|lead)-*(N/); do
  sz=$(du -sh "$d" 2>/dev/null | cut -f1)
  newest=$(find "$d" -type f -exec stat -f %m {} + 2>/dev/null | sort -rn | head -1)
  age=$(( $(date +%s) - ${newest:-0} ))
  if (( age < 1800 )); then
    say "  $sz  ${d:t}  -- ACTIVE, left alone"
  else
    say "  $sz  ${d:t}  (stale)"
    run "rm -rf ${(q)d}"
  fi
done

say "== after =="
say "  booted simulators: $(xcrun simctl list devices booted 2>/dev/null | grep -c Booted)"
say "  scratchpad: $(du -sh "$SCRATCH_ROOT" 2>/dev/null | cut -f1)"
df -h /System/Volumes/Data | tail -1 | awk '{print "  disk free: "$4}'
if (( ! APPLY )); then say ""; say "  (dry run — pass --apply to reclaim)"; fi
