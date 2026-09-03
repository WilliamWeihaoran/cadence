#!/bin/zsh
# Regenerate CadenceTests/CadenceRealTreeSweepManifest.txt -- the exact list of every `@Test` that
# sweeps the real product tree (T-808).
#
#   ./scripts/real-tree-sweep-manifest.sh <id>            # check only; says what would change
#   ./scripts/real-tree-sweep-manifest.sh <id> --write    # rewrite the manifest from the scan
#
# WHY THE MANIFEST EXISTS
#
# An audit measured 216 tests that walk `Cadence/`, `CadenceWidgets/` or `CadenceMCPServer/` and
# found 0 of them pinned: delete any one of those `@Test` functions and no other test goes red,
# because the ledgers, parsers and fixtures beside it all keep passing while the app-wide sweep
# quietly stops happening. The manifest is the one shared thing that makes such a deletion visible.
#
# WHY IT IS GENERATED AND NOT TYPED
#
# A hand-maintained list of 200-odd names is the next stale ledger, which is the failure this
# repository keeps re-finding. So the classification lives in Swift, in
# `CadenceTests/CadenceRealTreeSweepScan.swift`, where `CadenceTestTargetHygieneTests` fails on it
# every run; this script only *runs* that scan and copies what it computed into the file.
#
# WHY NOT `scripts/test-suite-index.sh`
#
# That script answers "which suite declares this test", by parsing `@Test ... func` and attributing
# each to the type whose braces enclose it. It is the right precedent and this script deliberately
# does not re-implement it -- but it has no notion of what a test's body *reaches*, and the
# classification here is exactly that: a walk needle, a product-root path literal and Swift-source
# evidence, unioned across every declaration the test transitively names. Adding that to a shell
# script would put the rule somewhere no test can fail on it, which is the same shape as the hole
# it is meant to close. The Swift scan is the authority; this is its typist.
#
# HOW THE OUTPUT GETS OUT OF THE TEST
#
# The hygiene test prints the regenerated file between two banners when the committed one disagrees
# with it, so the file travels through the `xcodebuild` log rather than through a write from an
# App-Sandboxed test host into the repository.
set -uo pipefail
ROOT_DIR="${0:A:h:h}"
ID="${1:-}"
MODE="${2:-}"
if [[ -z "$ID" ]]; then
    print -r -- "usage: real-tree-sweep-manifest.sh <id> [--write]" >&2
    exit 2
fi
if [[ -n "$MODE" && "$MODE" != "--write" ]]; then
    print -r -- "real-tree-sweep-manifest.sh: unknown option '$MODE'" >&2
    exit 2
fi

MANIFEST="$ROOT_DIR/CadenceTests/CadenceRealTreeSweepManifest.txt"
_tmp_base="${TMPDIR:-/tmp/}"; [[ "$_tmp_base" != */ ]] && _tmp_base="$_tmp_base/"
LOG="${_tmp_base}cadence-real-tree-sweep-${ID}.log"

print -r -- "real-tree-sweep-manifest.sh: running the scan (log: $LOG)"
"$ROOT_DIR/scripts/xcb.sh" "$ID" test \
    -scheme Cadence -destination 'platform=macOS' \
    -only-testing:CadenceTests/CadenceTestTargetHygieneTests > "$LOG" 2>&1
RUN_STATUS=$?

# The banners are spelled by CadenceRealTreeSweepScan.regeneratedBanner. `awk` rather than `sed -n`
# so an absent banner is distinguishable from an empty section: no lines out means the scan never
# printed, which is a failed run, not an empty manifest.
REGENERATED="${_tmp_base}cadence-real-tree-sweep-${ID}.manifest"
awk '/^--- BEGIN REGENERATED REAL-TREE SWEEP MANIFEST$/ {capture=1; next}
     /^--- END REGENERATED REAL-TREE SWEEP MANIFEST$/ {capture=0}
     capture {print}' "$LOG" > "$REGENERATED"

if [[ ! -s "$REGENERATED" ]]; then
    if (( RUN_STATUS == 0 )); then
        print -r -- "real-tree-sweep-manifest.sh: the manifest already matches the scan."
        exit 0
    fi
    print -r -- "real-tree-sweep-manifest.sh: the run failed and printed no manifest; see $LOG" >&2
    exit 1
fi

print -r -- "real-tree-sweep-manifest.sh: the scan differs from the committed manifest."
diff -u "$MANIFEST" "$REGENERATED"

if [[ "$MODE" != "--write" ]]; then
    print -r -- "real-tree-sweep-manifest.sh: pass --write to apply the difference above."
    exit 1
fi

cp "$REGENERATED" "$MANIFEST"
print -r -- "real-tree-sweep-manifest.sh: wrote $MANIFEST"
