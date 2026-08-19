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

Run from the **repo root** — agent shells reset their working directory between calls, so a
relative `-project ../Cadence.xcodeproj` will not resolve.

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-build-$$ build
```

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-test-$$ -only-testing:CadenceTests
```

Both flags are load-bearing and both are non-negotiables in the root `AGENTS.md`, which explains
them: `-only-testing:CadenceTests` keeps `CadenceUITests` out of the run (it cannot launch headless
and aborts everything, in a way that reads as a broken suite), and the private `-derivedDataPath`
keeps a build from deleting the shared `Build/Products/` out from under a running app — every
failure mode that causes is misattributed by default. Confirm the private path appears in the log
before trusting a green run.
