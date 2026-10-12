# macOS Guide

This is the main product surface. Most implemented functionality lives here.

## Structure

- `macOSRootView.swift` and `macOSRoot*` support files own the desktop shell, commands, overlays, lifecycle, search presentation, sidebar visibility, and routing.
- `Views/` contains feature views and their support files.
- `Services/` contains macOS-only managers: Calendar/EventKit, focus, hotkeys, hover state, scheduling, task creation, deletion confirmation, navigation.
- `Sheets/` contains create/edit sheets.
- `Editor/` contains the AppKit-backed markdown editor.

## Working Rules

- Keep root/shell views thin. Move repeated UI sections into dedicated subview structs.
- Keep service-like work out of SwiftUI views when it mutates SwiftData, talks to EventKit, handles deletion, or coordinates global app state.
- Preserve keyboard shortcut behavior. Many commands are hover-driven via macOS service managers.
- **Nothing installs an `UndoManager` on the model context (T-367).** There is one `ModelContext`
  in this app, so a global Cmd+Z reverts whatever that context recorded last rather than what the
  user last did, and every destructive path pairs its store write with effects no undo stack saw —
  cancelled reminders, disposed bundles, repaired recurrence links, torn-down focus state. Two
  sheets tell the user "This cannot be undone", and that is now true. Editor undo is the text
  view's own and is reached through the responder chain; leave it alone. Pinned by
  `CadenceGlobalUndoSurfaceTests`, and the reasoning is on `macOSRootLifecycleSupport.handleAppear`.
- Preserve dark theme styling and shared hover treatments.
- Avoid iOS-only modifiers in macOS views.
- Use AppKit bridges narrowly and keep them isolated.

## High-Risk Areas

- `Editor/` - NSTextView lifecycle, undo, hidden markdown markers, slash command popovers.
- `Views/Timeline*`, `Views/SchedulePanel*`, `Views/CalendarPage*` - timeline geometry, scrolling, drag/drop, calendar events.
- `Views/TasksPanel*`, `Views/ListDetail*`, `Views/Inbox*`, `Views/Kanban*` - shared task behavior, sorting/grouping, drag reorder, completion animations.
- `Services/CalendarManager.swift`, `Services/SchedulingService.swift`, `Services/TaskWorkflowService.swift`, deletion helpers - data mutation and external calendar side effects.

## Build Check

Build through `scripts/xcb.sh <id> build|test`. The two invocations, the two load-bearing flags
(`-only-testing:CadenceTests` and a private `-derivedDataPath`) and what each one is protecting
against are in the root `AGENTS.md` — "Project Snapshot" and "Build And Run Safety" — and are not
restated here, because a second copy is a second thing to keep in step.
