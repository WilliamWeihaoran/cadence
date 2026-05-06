# macOS Services Guide

These services coordinate desktop-only behavior: EventKit, focus timers, global hotkeys, hover-driven shortcuts, deletion overlays, scheduling, navigation, and quick task panels.

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
