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
# Whole directories rather than the handful of files this list used to name (T-1095). It named
# `CadenceSchema.swift`, `MarkdownMetadataSupport.swift` and `DateFormatters.swift` while the
# target's Sources phase also compiles `TagSupport`, `NoteMigrationService`,
# `DataIntegrityRepairService`, `NoteReferenceSupport`, `CadenceStoreSupport`,
# `CadenceHabitCompletionStore`, `CadenceSearchMatcher`, `CadenceTaskRecurrenceWorkflowSupport` and
# now three more `Shared/` files — so editing any of those left the warm binary stale and the next
# smoke test measuring the previous build. Over-rebuilding on an unrelated edit costs time;
# under-rebuilding costs a measurement nobody can tell is wrong. `Cadence/Models` was already a
# directory for the same reason.
SOURCE_PATHS=(
  "$ROOT_DIR/CadenceMCPServer"
  "$ROOT_DIR/Cadence/Models"
  "$ROOT_DIR/Cadence/Services"
  "$ROOT_DIR/Cadence/Shared"
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
