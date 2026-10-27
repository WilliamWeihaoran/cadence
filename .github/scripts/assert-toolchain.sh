#!/bin/bash
# Fail loudly and early when the runner image's Xcode cannot build this project.
#
# This project's macOS deployment target is 26.1 and its iOS target is 26.1, so it needs an Xcode
# 26.x toolchain. A runner image one major version behind does not produce a clear error: it
# produces a wall of "is only available in macOS 26.0 or newer" diagnostics that read like a code
# regression. That misread is the exact failure mode this repository's AGENTS.md "Red-Run Triage"
# section exists to prevent, so the check belongs in front of the build, not in the log.
#
# Two ordering rules, both learned from run 33355551830, where this script aborted with exit 134
# and printed nothing at all:
#   1. Report the environment BEFORE probing it. A probe that dies before its own header turns a
#      diagnostic into a mystery, and an unexplained non-zero here reads as a code regression --
#      precisely what this file exists to prevent.
#   2. No probe may be fatal. Under `set -euo pipefail`, `v=$(xcodebuild -version | head -1)` kills
#      the script if xcodebuild aborts, and a `2>/dev/null` on it discards the only evidence of why.
#      Every probe below tolerates its own failure and keeps its stderr.
set -euo pipefail

# THE EXACT MINOR, NOT THE MAJOR (T-4742, owner ruling 2026-10-26). This build is minor-sensitive
# (T-1318 measured it; T-3215 was 26 of 31 red runs from one diagnostic one Xcode emits and another
# does not). Asserting only the major let CI take whichever Xcode 26 sorted first on the image, so
# the day 26.0.x left the image CI would move to 26.1.1 with no annotation. Now a moved image is a
# loud red here instead. Bumping it is deliberate: change this value and the `runs-on: macos-26`
# label in .github/workflows/ci.yml together, in one commit. `26.0` accepts 26.0 and 26.0.x.
REQUIRED_MINOR=26.0

# 0 when an `xcodebuild -version` number ("26.0.1") is the pinned minor or a patch of it.
# Field-wise, never a prefix test: "26.01" and "26.0x" are not 26.0.
version_is_required_minor() {
  local v="$1"
  [ -n "$v" ] || return 1
  [ "$(printf '%s\n' "$v" | cut -d. -f1-2)" = "$REQUIRED_MINOR" ] || return 1
  # A bare major ("26") has no second field, and `cut` would hand back "26" -- already rejected
  # above, because "26" != "26.0".
  return 0
}

# --- report first, so this step is never silent -------------------------------
echo "== runner =="
echo "image: ${ImageOS:-unknown} / ${ImageVersion:-unknown}"
echo "uname: $(uname -smr 2>&1 || true)"
echo "selected developer dir: $(xcode-select -p 2>&1 || echo '<none>')"
echo "installed Xcodes:"
ls -d /Applications/Xcode*.app 2>/dev/null || echo "  <none found>"

# Probe each candidate without letting a bad one kill the run. Keep stderr: if an Xcode aborts,
# the reason is the whole value of this step.
probe_version() {
  local app="$1" out=""
  out=$(DEVELOPER_DIR="$app/Contents/Developer" \
        "$app/Contents/Developer/usr/bin/xcodebuild" -version 2>&1) || {
    echo "  $app -> probe failed (exit $?):" >&2
    printf '    %s\n' "$out" >&2
    return 1
  }
  printf '%s\n' "$out" | head -1 | awk '{print $2}'
}

echo "== versions =="
for candidate in /Applications/Xcode*.app; do
  [ -d "$candidate" ] || continue
  if v=$(probe_version "$candidate"); then
    echo "  $candidate -> $v"
  fi
done

# --- select the pinned Xcode minor if the image ships one ---------------------
# Every installed Xcode is asked for its version; the first whose version is the pinned minor wins.
# A bundle's NAME is never trusted: on image 20261021.0445.8 `Xcode_26.0.app` reports 26.0.1 and
# `Xcode.app` reports 26.6.
selected=""
for candidate in /Applications/Xcode*.app; do
  [ -d "$candidate" ] || continue
  v=$(probe_version "$candidate") || continue
  if version_is_required_minor "$v"; then
    selected="$candidate"
    break
  fi
done

if [ -n "$selected" ]; then
  echo "selecting: $selected"
  sudo xcode-select -s "$selected/Contents/Developer" || {
    echo "::warning::could not xcode-select $selected; continuing with the image default"
  }
fi

# --- the gate -----------------------------------------------------------------
active=$(xcodebuild -version 2>&1 | head -1 || true)
echo "active xcodebuild: $active"
swift --version 2>&1 | head -2 || true

active_version=$(printf '%s\n' "$active" | awk '{print $2}')
if ! version_is_required_minor "$active_version"; then
  echo "::error::This runner's Xcode is ${active_version:-<unreadable>}; Cadence pins Xcode ${REQUIRED_MINOR} (T-4742)."
  echo "No installed Xcode reported ${REQUIRED_MINOR} or ${REQUIRED_MINOR}.x -- the 'versions' list above is what the image ships."
  echo "The runner image moved under the pin. Bump REQUIRED_MINOR in .github/scripts/assert-toolchain.sh"
  echo "and the runs-on label in .github/workflows/ci.yml together, deliberately, in one commit."
  echo "MACOSX_DEPLOYMENT_TARGET is 26.1 and IPHONEOS_DEPLOYMENT_TARGET is 26.1 (Cadence.xcodeproj)."
  echo "Do NOT read the resulting availability errors as a code regression."
  exit 1
fi

echo "macosx SDK: $(xcodebuild -showsdks 2>/dev/null | grep -m1 'macosx' || echo unknown)"
