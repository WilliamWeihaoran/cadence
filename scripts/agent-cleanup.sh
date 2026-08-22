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
for d in "$SCRATCH_ROOT"/*/*/scratchpad/(agent|lead)-*(N/); do
  sz=$(du -sh "$d" 2>/dev/null | cut -f1)
  if [[ -n $(find "$d" -newermt '-30 minutes' -print -quit 2>/dev/null) ]]; then
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
