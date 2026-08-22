#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
XCODEBUILD="${XCODEBUILD:-/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild}"
# Defaults to the shared `.codex-build` so the installed plugin keeps reusing one warm build.
# Override it when verifying an MCP change: the shared path is the one the live plugin process
# and Codex are already using, and a concurrent rebuild into it is the `-derivedDataPath`
# non-negotiable in the root `AGENTS.md`.
DERIVED_DATA_PATH="${CADENCE_MCP_DERIVED_DATA:-$ROOT_DIR/.codex-build}"
BINARY="$DERIVED_DATA_PATH/Build/Products/Debug/CadenceMCPServer"
SOURCE_PATHS=(
  "$ROOT_DIR/CadenceMCPServer"
  "$ROOT_DIR/Cadence/Models"
  "$ROOT_DIR/Cadence/Services/CadenceSchema.swift"
  "$ROOT_DIR/Cadence/Services/MCPReadOnly"
  "$ROOT_DIR/Cadence/Services/MarkdownMetadataSupport.swift"
  "$ROOT_DIR/Cadence/Shared/DateFormatters.swift"
  "$ROOT_DIR/Cadence.xcodeproj/project.pbxproj"
)

needs_build=false
if [[ ! -x "$BINARY" ]]; then
  needs_build=true
else
  for source_path in "${SOURCE_PATHS[@]}"; do
    if [[ -e "$source_path" ]] && [[ -n "$(find "$source_path" -newer "$BINARY" -print -quit)" ]]; then
      needs_build=true
      break
    fi
  done
fi

if [[ "$needs_build" == true ]]; then
  "$XCODEBUILD" \
    -project "$ROOT_DIR/Cadence.xcodeproj" \
    -scheme CadenceMCPServer \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build >/dev/stderr
fi

exec "$BINARY"
