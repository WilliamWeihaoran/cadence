# Cadence Agent Guide

This file is the first stop for coding agents. `CLAUDE.md` has a longer product and feature history; this file is the compact working map.

## Project Snapshot

Cadence is a native SwiftUI productivity app with a fully built macOS surface, shared SwiftData models, CloudKit sync, Apple Calendar/EventKit integration, and a large, actively-developed iOS/iPadOS surface (not a stub — see `Cadence/iOS/AGENTS.md`).

Primary target:
- `Cadence.xcodeproj`
- scheme: `Cadence`
- platform: macOS

Useful build command:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' build
```

## Where Things Live

- `Cadence/CadenceApp.swift` - app entry, model container, CloudKit setup, recovery.
- `Cadence/Models/` - shared SwiftData models. Read this before changing persistence or relationships.
- `Cadence/Services/` - shared services, migrations, markdown/note support, schema, AI support, plus read-only MCP support.
- `Cadence/Shared/` - design tokens, shared components, date/time utilities, hover styling.
- `Cadence/macOS/` - main product surface. Most active work happens here.
- `Cadence/macOS/Views/` - macOS feature screens and support views.
- `Cadence/macOS/Services/` - macOS-only managers for focus, calendar, hotkeys, task creation, hover state, deletion, scheduling.
- `Cadence/macOS/Editor/` - AppKit-backed markdown editor. High risk; preserve NSTextView behavior carefully.
- `Cadence/iOS/` - large, real iOS/iPadOS surface (~55 files: Today, Calendar, Tasks, Focus, Goals/Pursuits, Habits, Notes, Lists, Search, Settings). Do not assume feature parity with macOS.
- `CadenceMCPServer/` and `plugins/cadence-mcp/` - MCP server/plugin surfaces. Treat as separate integration boundaries.
- `CadenceTests/`, `CadenceUITests/` - test targets.

## Scoped Guides

Read the nearest scoped `AGENTS.md` before editing under that tree:

- `Cadence/AGENTS.md` - app-wide source rules.
- `Cadence/Models/AGENTS.md` - SwiftData relationship and persistence rules.
- `Cadence/Services/AGENTS.md` - service/migration boundaries.
- `Cadence/Shared/AGENTS.md` - shared UI/utilities rules.
- `Cadence/iOS/AGENTS.md` - iOS surface boundary (large, real UI — not a stub; parity with macOS is not guaranteed).
- `Cadence/macOS/AGENTS.md` - macOS feature architecture.
- `Cadence/macOS/Services/AGENTS.md` - macOS manager/service boundaries.
- `Cadence/macOS/Editor/AGENTS.md` - AppKit-backed markdown editor cautions.
- `Cadence/macOS/Views/AGENTS.md` - view splitting and current feature map.
- `CadenceMCPServer/AGENTS.md` and `plugins/cadence-mcp/AGENTS.md` - MCP boundaries.

Do not add an agent guide to every folder by default. Add one when a subtree has unique rules, high churn, or a boundary that agents repeatedly misunderstand.

## Non-Negotiable Patterns

- All persisted dates are `yyyy-MM-dd` strings unless an existing model says otherwise.
- Use `DateFormatters` and `TimeFormatters`; do not create ad hoc `DateFormatter()` instances in views.
- SwiftData/CloudKit to-many relationships must be optional arrays (`[Type]?`). Read optional relationships with `?? []`, and append by assigning a new array.
- macOS is the primary, most fully-featured app surface; iOS is large and actively developed but not guaranteed to be at full feature parity.
- Keep SwiftUI view roots thin. Prefer dedicated subview structs and support files over long computed `some View` fragments.
- Preserve shared hover behavior. Do not turn task/event/bundle hover states gray; preserve original color and use brightness/lift style treatments from shared hover helpers.
- Avoid broad refactors in markdown editor files unless you are intentionally working on editor behavior.
- Do not touch MCP server/plugin code unless the task explicitly asks for MCP work.
- Do not revert unrelated user changes.

## Risk Hotspots

Use extra caution in these areas:

- `Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift` and `MarkdownEditorSupport.swift` - large AppKit/SwiftUI bridge with custom caret, drawing, slash commands, and undo behavior.
- `Cadence/macOS/Views/Timeline*`, `SchedulePanel*`, `CalendarPage*` - timeline coordinate math, drag/drop, EventKit, and schedule state.
- `Cadence/macOS/Views/TasksPanel*`, `ListDetail*`, `Inbox*`, `Kanban*` - shared task surface behavior, grouping, sorting, drag reorder, completion animations.
- `Cadence/macOS/Services/CalendarManager.swift`, `SchedulingService.swift`, `TaskWorkflowService.swift`, deletion helpers - can affect SwiftData relationships and EventKit side effects.
- `Cadence/Models/` and `Cadence/Services/CadenceSchema.swift` - schema changes require migration and CloudKit awareness.

## Refactor Guidance

Good refactor targets are files that combine orchestration, state, row rendering, popovers, and domain operations. Split by responsibility:

- root view: state and orchestration
- support view file: reusable UI sections and rows
- state/support file: derived state, sorting, grouping, coordinate math
- service: persistence mutations, deletion flows, EventKit interactions, migrations

After structural refactors, run `git diff --check` and the macOS build command above.
