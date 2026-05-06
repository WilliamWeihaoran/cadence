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
- Preserve dark theme styling and shared hover treatments.
- Avoid iOS-only modifiers in macOS views.
- Use AppKit bridges narrowly and keep them isolated.

## High-Risk Areas

- `Editor/` - NSTextView lifecycle, undo, hidden markdown markers, slash command popovers.
- `Views/Timeline*`, `Views/SchedulePanel*`, `Views/CalendarPage*` - timeline geometry, scrolling, drag/drop, calendar events.
- `Views/TasksPanel*`, `Views/ListDetail*`, `Views/Inbox*`, `Views/Kanban*` - shared task behavior, sorting/grouping, drag reorder, completion animations.
- `Services/CalendarManager.swift`, `Services/SchedulingService.swift`, `Services/TaskWorkflowService.swift`, deletion helpers - data mutation and external calendar side effects.

## Build Check

From repo root:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' build
```
