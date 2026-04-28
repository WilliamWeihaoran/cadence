#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
XCODEBUILD="${XCODEBUILD:-/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild}"
DERIVED_DATA_PATH="$ROOT_DIR/.codex-build"
BINARY="$DERIVED_DATA_PATH/Build/Products/Debug/CadenceMCPServer"

if [[ ! -x "$BINARY" ]]; then
  "$XCODEBUILD" \
    -project "$ROOT_DIR/Cadence.xcodeproj" \
    -scheme CadenceMCPServer \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build >/dev/stderr
fi

exec "$BINARY"
