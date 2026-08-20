# macOS Services Guide

These services coordinate desktop-only behavior: EventKit calendar, focus timers,
global hotkeys, hover-driven shortcuts, deletion overlays, scheduling, navigation, quick task
panels, note export, Sign in with Apple, and the privacy data reset.

Beyond the long-standing managers, note:

- **`RemindersManager` is not here either.** EventKit **reminders** (separate authorization from
  calendar) moved to `Cadence/Services/CadenceRemindersManager.swift` when iOS gained its own
  Settings -> Reminders screen. Nothing in it was ever AppKit-bound — the `#if os(macOS)` guard
  and the folder were an accident of where it was written, and that accident is what made
  Apple Reminders unreachable from iOS Settings. A 2-line tombstone `RemindersManager.swift`
  remains here recording the move.
- **`CalendarVisibilityPreferences` and `CalendarWorkHoursPreferences` are not here.** Both are
  cross-platform and live in `Cadence/Shared/` (`CadenceCalendarVisibilityPreferences.swift` — the
  *file* carries the `Cadence` prefix, the *type* does not — and `CalendarWorkHoursPreferences.swift`),
  so iOS and macOS share one hidden-calendar store and one work-hours window. This guide listed
  them as macOS services, and `CLAUDE.md` was corrected while this file was not — which left the
  doc system's own precedence rule ("the scoped guide is closer to the code") pointing at the
  wrong doc. What remains in this folder is a 2-line `CalendarVisibilityPreferences.swift`
  containing only a tombstone comment recording the move.
- `TaskDragPayload` is not here either — same shape, `Cadence/Shared/TaskDragPayload.swift`,
  `nonisolated` because the drop delegates that parse it run in `@Sendable` closures.
- `NoteExportService.swift` - markdown + rendered-PDF export. Presents the save panel off the blocking `runModal()` path; keep it that way.
- `AppleAccountManager.swift` - optional Sign in with Apple identity, entitlement-gated.
- `PrivacyDataResetService.swift` - wipes every model including the legacy note types and `Pursuit`. Add new `@Model` types here when you add them to the schema, or a reset will leave orphans.
- `CadenceMCPRefreshCoordinator.swift` - watches a `.cadence-mcp-refresh` marker file beside the
  store so the app reloads after the MCP server writes to it from another process. See
  `CadenceMCPServer/AGENTS.md`.
- Also here and previously unlisted: `NoteExportService.swift`, `PrivacyDataResetService.swift`,
  `AppleAccountManager.swift`, `GlobalSearchManager.swift`.

## Working Rules

- Keep SwiftData mutations in named service/helper methods when behavior is reused or side-effectful.
- Calendar/EventKit work belongs in `CalendarManager.swift` or explicitly named scheduling helpers.
- Deletion flows must avoid touching stale SwiftData relationships after deleting related objects.
- Hover managers drive keyboard shortcuts. Preserve delayed-clear behavior when it prevents regroup/layout churn.
- Quick task panel code is AppKit-heavy; keep NSPanel/window logic isolated.

## Risk Notes

- `CalendarManager.swift` can trigger permission prompts and external calendar side effects.
- `SchedulingService.swift` links task creation/drop behavior with timeline/calendar UI.
- `TaskWorkflowService.swift` handles recurring completion flow.
- `TaskDeleteHelpers.swift` and `ListDeleteHelpers.swift` are crash-sensitive because of SwiftData inverse relationships.

## Verification

Run the macOS build after changes. For calendar/deletion changes, manually exercise create/update/delete flows in the app.
