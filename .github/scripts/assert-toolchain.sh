#!/bin/bash
# Fail loudly and early when the runner image's Xcode cannot build this project.
#
# This project's macOS deployment target is 26.1 and its iOS target is 26.2, so it needs an Xcode
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

REQUIRED_MAJOR=26

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

# --- select an Xcode 26 if the image ships one --------------------------------
selected=""
for candidate in /Applications/Xcode_"$REQUIRED_MAJOR"*.app /Applications/Xcode.app; do
  [ -d "$candidate" ] || continue
  v=$(probe_version "$candidate") || continue
  case "$v" in
    "$REQUIRED_MAJOR".*)
      selected="$candidate"
      break
      ;;
  esac
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

major=$(printf '%s\n' "$active" | awk '{print $2}' | cut -d. -f1)
if [ "$major" != "$REQUIRED_MAJOR" ]; then
  echo "::error::This runner's Xcode is ${major:-<unreadable>}.x; Cadence needs ${REQUIRED_MAJOR}.x."
  echo "MACOSX_DEPLOYMENT_TARGET is 26.1 and IPHONEOS_DEPLOYMENT_TARGET is 26.2 (Cadence.xcodeproj)."
  echo "Pin a runner label whose image ships Xcode ${REQUIRED_MAJOR} (e.g. macos-26), or lower the"
  echo "deployment targets. Do NOT read the resulting availability errors as a code regression."
  exit 1
fi

echo "macosx SDK: $(xcodebuild -showsdks 2>/dev/null | grep -m1 'macosx' || echo unknown)"
