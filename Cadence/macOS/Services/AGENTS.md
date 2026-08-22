# macOS Services Guide

These services coordinate desktop-only behavior: EventKit calendar, focus timers,
global hotkeys, hover-driven shortcuts, deletion overlays, scheduling, navigation, quick task
panels, note export, and Sign in with Apple.

Beyond the long-standing managers, note:

- **`RemindersManager` is not here either.** EventKit **reminders** (separate authorization from
  calendar) moved to `Cadence/Services/CadenceRemindersManager.swift` when iOS gained its own
  Settings -> Reminders screen. Nothing in it was ever AppKit-bound — the `#if os(macOS)` guard
  and the folder were an accident of where it was written, and that accident is what made
  Apple Reminders unreachable from iOS Settings. A 2-line tombstone `RemindersManager.swift`
  remains here recording the move.
- **`CalendarVisibilityPreferences` and `CalendarWorkHoursPreferences` are not here, and nothing
  marks the spot any more.** Both are cross-platform and live in `Cadence/Shared/`
  (`CadenceCalendarVisibilityPreferences.swift` — the *file* carries the `Cadence` prefix, the
  *type* does not — and `CalendarWorkHoursPreferences.swift`), so iOS and macOS share one
  hidden-calendar store and one work-hours window. This guide listed them as macOS services, and
  `CLAUDE.md` was corrected while this file was not — which left the doc system's own precedence
  rule ("the scoped guide is closer to the code") pointing at the wrong doc.
  **The 2-line `CalendarVisibilityPreferences.swift` tombstone this bullet used to promise is
  gone**, deleted by `6f71a70`: it declared nothing, and once no file of that base name existed
  anywhere in the project the `.stringsdata` collision that made the `Cadence` prefix necessary
  could not apply in either direction, so the tombstone had no name left to own. `CLAUDE.md` still
  said it "could be deleted" after it had been. The three tombstones below and beside it are
  recent, deliberate, and stay.
- `TaskDragPayload` is not here either — same shape, `Cadence/Shared/TaskDragPayload.swift`,
  `nonisolated` because the drop delegates that parse it run in `@Sendable` closures.
- `NoteExportService.swift` - markdown + rendered-PDF export. Presents the save panel off the blocking `runModal()` path; keep it that way.
- `AppleAccountManager.swift` - optional Sign in with Apple identity, entitlement-gated.
- **`ListDeleteHelpers` is not here any more either.** The three list/context delete cascades
  (`deleteContext`, `deleteArea`, `deleteProject`) moved to
  `Cadence/Services/CadenceListDeleteHelpers.swift` in `c84732e` — prefixed file, unprefixed
  `ListDeleteHelpers` type name in the extension it declares — when iOS gained Delete on a list and
  a context. Fourth instance of the same shape: an `#if os(macOS)` around code that imports nothing
  platform-specific, and the cost was iOS being unable to delete a list or a context at all.
  A comment-only tombstone `ListDeleteHelpers.swift` remains here.
  **It carries exactly one `#if os(macOS)` seam and must not grow a second**:
  `cascadeDeleteTasks(withIDs:)`, because `ModelContext.deleteTasks(withIDs:)` genuinely *is*
  macOS-only — it tears down `FocusManager`, `HoveredTaskManager`, the completion-animation manager
  and the subtask-entry manager. iOS calls
  `CadenceTaskMutationSupport.deleteTasks(withIDs:modelContext:)`, the same core, directly. Nothing
  about the cascade itself is duplicated, and
  `CadenceListDeletionSurfaceTests.theCascadesLiveInServicesWithExactlyOnePlatformSeam` fails if a
  second seam appears.
- **`PrivacyDataResetService` is not here any more either.** It moved to
  `Cadence/Services/CadencePrivacyDataResetService.swift` when iOS gained its own
  Settings -> Data Safety delete action — 45 lines importing only Foundation and SwiftData, with
  zero AppKit references, so the `#if os(macOS)` was an accident of where it was written. The
  consequence was not academic: `docs/privacy.html` and `docs/app-review-notes.md` both promised
  in-app account and data deletion that iOS had no route to. A comment-only tombstone
  `PrivacyDataResetService.swift` remains here recording the move. Add new `@Model` types to the
  service at its new path when you add them to `CadenceSchema`, or a reset leaves orphans.
- `CadenceMCPRefreshCoordinator.swift` - watches a `.cadence-mcp-refresh` marker file beside the
  store so the app reloads after the MCP server writes to it from another process. See
  `CadenceMCPServer/AGENTS.md`.
- Also here and previously unlisted: `NoteExportService.swift`, `AppleAccountManager.swift`,
  `GlobalSearchManager.swift`.

## Working Rules

- Keep SwiftData mutations in named service/helper methods when behavior is reused or side-effectful.
- Calendar/EventKit work belongs in `CalendarManager.swift` or explicitly named scheduling helpers.
- Deletion flows must avoid touching stale SwiftData relationships after deleting related objects.
- Hover managers drive keyboard shortcuts. Preserve delayed-clear behavior when it prevents regroup/layout churn.
- Quick task panel code is AppKit-heavy; keep NSPanel/window logic isolated.

## Risk Notes

- `CalendarManager.swift` can trigger permission prompts and external calendar side effects.
- `SchedulingService.swift` links task creation/drop behavior with timeline/calendar UI.
- `TaskWorkflowService.swift` handles recurring completion flow. It no longer declares
  `TaskContainerLifecycleService`: T-215 moved that to
  `Cadence/Services/CadenceTaskContainerLifecycleService.swift`, because it sat inside this
  file's `#if os(macOS)` while importing nothing platform-specific, and the guard is what left
  iOS's list archive a bare `status = .archived` while macOS's cancelled the list's remaining
  active tasks. That is a **comment** tombstone at the top-level of the surviving file, not a
  fourth whole-file tombstone — `TaskWorkflowService` itself stays here, so the count of
  tombstone *files* in this folder is still three.
- `TaskDeleteHelpers.swift` here, and `Cadence/Services/CadenceListDeleteHelpers.swift`, are crash-sensitive because of SwiftData inverse relationships. The `ListDeleteHelpers.swift` still in this folder is a tombstone comment — editing it changes nothing.

## Verification

Run the macOS build after changes. For calendar/deletion changes, manually exercise create/update/delete flows in the app.
