#!/bin/bash
# Fail loudly and early when the runner image's Xcode cannot build this project.
#
# This project's macOS deployment target is 26.1 and its iOS target is 26.2, so it needs an Xcode
# 26.x toolchain. A runner image one major version behind does not produce a clear error: it
# produces a wall of "is only available in macOS 26.0 or newer" diagnostics that read like a code
# regression. That misread is the exact failure mode this repository's AGENTS.md "Red-Run Triage"
# section exists to prevent, so the check belongs in front of the build, not in the log.
set -euo pipefail

REQUIRED_MAJOR=26

# Prefer an explicitly installed Xcode 26 if the image ships several.
for candidate in /Applications/Xcode_26*.app /Applications/Xcode.app; do
  [ -d "$candidate" ] || continue
  v=$("$candidate/Contents/Developer/usr/bin/xcodebuild" -version 2>/dev/null | head -1 | awk '{print $2}')
  case "$v" in
    "$REQUIRED_MAJOR".*)
      sudo xcode-select -s "$candidate/Contents/Developer"
      break
      ;;
  esac
done

echo "== toolchain =="
xcodebuild -version
swift --version 2>&1 | head -2
echo "runner image: ${ImageOS:-unknown} / ${ImageVersion:-unknown}"
echo "available Xcodes:"; ls -d /Applications/Xcode*.app 2>/dev/null || true

major=$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1)
if [ "$major" != "$REQUIRED_MAJOR" ]; then
  echo "::error::This runner's Xcode is $major.x; Cadence needs ${REQUIRED_MAJOR}.x."
  echo "MACOSX_DEPLOYMENT_TARGET is 26.1 and IPHONEOS_DEPLOYMENT_TARGET is 26.2 (Cadence.xcodeproj)."
  echo "Pin a runner label whose image ships Xcode ${REQUIRED_MAJOR} (e.g. macos-26), or lower the"
  echo "deployment targets. Do NOT read the resulting availability errors as a code regression."
  exit 1
fi

# The macOS SDK has to be able to build for the deployment target too, not just Xcode's version.
echo "macosx SDK: $(xcodebuild -showsdks 2>/dev/null | grep -m1 'macosx' || echo unknown)"
