#!/bin/zsh
# Regenerate CadenceTests/CadenceRealTreeSweepManifest.txt -- the exact list of every `@Test` that
# sweeps the real product tree (T-808).
#
#   ./scripts/real-tree-sweep-manifest.sh <id>            # check only; says what would change
#   ./scripts/real-tree-sweep-manifest.sh <id> --write    # rewrite the manifest from the scan
#   ./scripts/real-tree-sweep-manifest.sh <id> selftest   # T-873: prove a stale manifest still
#                                                          # yields a non-empty regenerated body
#   ./scripts/real-tree-sweep-manifest.sh <id> selftest -derivedDataPath <path> CODE_SIGN_IDENTITY=...
#                                                          # T-977: anything after the mode is
#                                                          # forwarded verbatim to the internal
#                                                          # `xcb.sh <id> test` call -- CI.yml's
#                                                          # macos-tests job needs this to reuse its
#                                                          # own derived data and signing overrides
#                                                          # rather than paying for a second full
#                                                          # build under an unrelated identity.
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
#
# T-873. The banners are printed by the `xcodebuild test` invocation itself, and `scripts/xcb.sh`
# writes THAT output to its own fixed path -- "${TMP_BASE}cadence-xcb-$ID.log" -- not to the stdout
# this script used to capture and scan. That stdout is only xcb.sh's own preflight/result summary,
# so the awk below found nothing on the one path anyone runs this for: a failing run (a stale
# manifest, i.e. every real invocation) has `RUN_STATUS != 0`, which skipped the "already matches"
# read of that emptiness and reported "the run failed and printed no manifest" instead -- even
# though the scan printed a full manifest every time, just into a file this script never opened.
# `selftest` below pins exactly this: a deliberately stale manifest must still yield a non-empty
# regenerated body.
set -uo pipefail
ROOT_DIR="${0:A:h:h}"
ID="${1:-}"
MODE="${2:-}"
if [[ -z "$ID" ]]; then
    print -r -- "usage: real-tree-sweep-manifest.sh <id> [--write|selftest]" >&2
    exit 2
fi
if [[ -n "$MODE" && "$MODE" != "--write" && "$MODE" != "selftest" ]]; then
    print -r -- "real-tree-sweep-manifest.sh: unknown option '$MODE'" >&2
    exit 2
fi
# Anything past <id> <mode> is passed straight through to the internal `xcb.sh test` call. Empty
# in every caller this repository already had; T-977's CI wiring is the first to use it.
EXTRA_XCB_ARGS=("${@:3}")

MANIFEST="$ROOT_DIR/CadenceTests/CadenceRealTreeSweepManifest.txt"
_tmp_base="${TMPDIR:-/tmp/}"; [[ "$_tmp_base" != */ ]] && _tmp_base="$_tmp_base/"
LOG="${_tmp_base}cadence-real-tree-sweep-${ID}.log"
XCB_LOG="${_tmp_base}cadence-xcb-${ID}.log"
REGENERATED="${_tmp_base}cadence-real-tree-sweep-${ID}.manifest"

# Runs the scan once against whatever $MANIFEST currently holds and populates $REGENERATED and
# $RUN_STATUS. Shared by the normal flow and `selftest` so the corruption below exercises the exact
# same path a real drift does.
run_scan_once() {
    print -r -- "real-tree-sweep-manifest.sh: running the scan (log: $LOG, xcodebuild log: $XCB_LOG)"
    "$ROOT_DIR/scripts/xcb.sh" "$ID" test \
        -scheme Cadence -destination 'platform=macOS' \
        -only-testing:CadenceTests/CadenceTestTargetHygieneTests \
        "${EXTRA_XCB_ARGS[@]}" > "$LOG" 2>&1
    RUN_STATUS=$?

    # The banners are spelled by CadenceRealTreeSweepScan.regeneratedBanner. `awk` rather than
    # `sed -n` so an absent banner is distinguishable from an empty section: no lines out means the
    # scan never printed, which is a failed run, not an empty manifest.
    awk '/^--- BEGIN REGENERATED REAL-TREE SWEEP MANIFEST$/ {capture=1; next}
         /^--- END REGENERATED REAL-TREE SWEEP MANIFEST$/ {capture=0}
         capture {print}' "$XCB_LOG" > "$REGENERATED" 2>/dev/null
}

if [[ "$MODE" == "selftest" ]]; then
    if [[ ! -f "$MANIFEST" ]]; then
        print -r -- "real-tree-sweep-manifest.sh: selftest: no manifest at $MANIFEST" >&2
        exit 2
    fi
    BACKUP="${_tmp_base}cadence-real-tree-sweep-${ID}.manifest-backup"
    cp "$MANIFEST" "$BACKUP"
    # Always put the committed file back, pass or fail -- this must never leave the repo stale.
    trap 'cp "$BACKUP" "$MANIFEST"; rm -f "$BACKUP"' EXIT

    # Deliberately stale: drop the first real (non-comment, non-blank) entry so the scan and the
    # manifest disagree, the same shape as the T-873 repro (a merged-HEAD failure).
    STALE_LINE=$(grep -n '^[^#[:space:]]' "$MANIFEST" | head -1 | cut -d: -f1)
    if [[ -z "$STALE_LINE" ]]; then
        print -r -- "real-tree-sweep-manifest.sh: selftest: found no entry line to remove" >&2
        exit 2
    fi
    REMOVED=$(sed -n "${STALE_LINE}p" "$MANIFEST")
    sed -i '' "${STALE_LINE}d" "$MANIFEST"
    print -r -- "real-tree-sweep-manifest.sh: selftest: staled the manifest (removed \"$REMOVED\")"

    run_scan_once

    if (( RUN_STATUS == 0 )); then
        print -r -- "real-tree-sweep-manifest.sh: selftest FAILED: the run passed over a manifest it should have rejected" >&2
        exit 1
    fi
    if [[ ! -s "$REGENERATED" ]]; then
        print -r -- "real-tree-sweep-manifest.sh: selftest FAILED: a stale manifest produced an empty regenerated body -- T-873 is back; see $XCB_LOG" >&2
        exit 1
    fi
    if ! grep -qF "$REMOVED" "$REGENERATED"; then
        print -r -- "real-tree-sweep-manifest.sh: selftest FAILED: the regenerated body does not contain the entry the stale manifest was missing" >&2
        exit 1
    fi
    print -r -- "real-tree-sweep-manifest.sh: selftest passed: a stale manifest yielded a $(wc -l < "$REGENERATED" | tr -d ' ')-line regenerated body"
    exit 0
fi

run_scan_once

if [[ ! -s "$REGENERATED" ]]; then
    if (( RUN_STATUS == 0 )); then
        print -r -- "real-tree-sweep-manifest.sh: the manifest already matches the scan."
        exit 0
    fi
    print -r -- "real-tree-sweep-manifest.sh: the run failed and printed no manifest; see $XCB_LOG (summary: $LOG)" >&2
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
