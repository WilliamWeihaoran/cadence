# macOS Services Guide

These services coordinate desktop-only behavior: EventKit calendar *and* reminders, focus timers,
global hotkeys, hover-driven shortcuts, deletion overlays, scheduling, navigation, quick task
panels, note export, Sign in with Apple, and the privacy data reset.

Beyond the long-standing managers, note:

- `RemindersManager.swift` - EventKit **reminders** (separate authorization from calendar), surfaced through Settings -> Reminders.
- `CalendarVisibilityPreferences.swift` / `CalendarWorkHoursPreferences.swift` - which calendars render, and the work-hours window the timeline emphasizes.
- `NoteExportService.swift` - markdown + rendered-PDF export. Presents the save panel off the blocking `runModal()` path; keep it that way.
- `AppleAccountManager.swift` - optional Sign in with Apple identity, entitlement-gated.
- `PrivacyDataResetService.swift` - wipes every model including the legacy note types and `Pursuit`. Add new `@Model` types here when you add them to the schema, or a reset will leave orphans.
- `CadenceMCPRefreshCoordinator.swift` - bridges app state to the MCP surface.

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
