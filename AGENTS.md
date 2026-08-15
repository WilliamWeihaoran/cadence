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

Tests **must** be scoped to `CadenceTests`:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' -only-testing:CadenceTests
```

An unscoped `test` run also pulls in `CadenceUITests`, which cannot launch headless and aborts
the whole run. The failure reads like a broken suite rather than a harness problem — do not
conclude "tests can't run here" from it.

**Warning baseline is 3**: `MarkdownLinkSupport`, `SchedulingService`,
`SettingsNotificationsSection`. Treat any increase as a regression introduced by the change in
hand.

## Where Things Live

- `Cadence/CadenceApp.swift` - app entry, model container, CloudKit setup, recovery.
- `Cadence/Models/` - shared SwiftData models. Read this before changing persistence or relationships.
- `Cadence/Services/` - ~41 shared services: schema, migrations, notifications, widget support, the ~21 `Markdown*Support` parsing/mutation files, plus `AI/` and `MCPReadOnly/`. Note the markdown *logic* lives here, not in `macOS/Editor/`.
- `Cadence/Shared/` - design tokens (`Theme.swift`), shared components, date/time utilities, hover styling, and cross-platform presentation/query support (`Cadence*Support.swift`).
- `Cadence/macOS/` - main product surface. Most active work happens here.
- `Cadence/macOS/Views/` - macOS feature screens and support views (~165 files).
- `Cadence/macOS/Services/` - macOS-only managers for focus, calendar, reminders, hotkeys, task creation, hover state, deletion, scheduling, note export, privacy reset, Apple account.
- `Cadence/macOS/Editor/` - AppKit-backed markdown editor bridge (6 files). High risk; preserve NSTextView behavior carefully.
- `Cadence/iOS/` - large, real iOS/iPadOS surface (68 files: Today, Calendar, Tasks, Focus, Goals, Habits, Notes, Lists, Search, Settings). iPhone runs a four-tab bottom bar (`iOSCompactTabShell`); iPad keeps its sidebar. Do not assume feature parity with macOS.
- `CadenceWidgets/` - widget extension. Compiles a subset of app sources (models, `Theme.swift`, `Cadence*WidgetSupport.swift`) directly into the extension target.
- `CadenceMCPServer/` and `plugins/cadence-mcp/` - MCP server/plugin surfaces. Treat as separate integration boundaries.
- `CadenceTests/`, `CadenceUITests/` - test targets.
- `docs/` - support, privacy, and App Review notes (the public site + submission material).

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

These four are restated by the user more often than anything else. They are enforced by the
code, and every one of them has been violated by a shipped change at least once.

- **No hardcoded colours.** Every colour comes from `Theme.*`, or from a user-owned
  `colorHex` on a list/calendar/habit/tag/section. No `Color(hex:)` literals, no bare
  `.white`/`.black`/`.gray` — `Theme` has named tokens for foreground-on-colour, scrims,
  shadows and borders precisely so call sites stop inventing their own. This includes the
  `CadenceWidgets` target, which has `Theme.swift` in its Sources phase so it can comply.
- **Page headers do not describe the page you are already on.** A subtitle under "Notes"
  saying "Write and organize your notes" is noise; the `subtitle` parameter has been deleted
  from `DesktopPageHeader`, `CommitmentPageHeader`, and `CadenceSettingsHeader`. Search
  result rows, empty states, and picker rows *keep* their subtitles — those say something the
  screen does not.
- **One hover/selection layer at one radius.** Stacked hover backgrounds at mismatched radii
  have shipped independently in the task inspector, group headers, tab bars, sidebar rows,
  and the notes action menu. If a row already has a `rowBackground`, do not add a second
  `.background()` on another layer.
- **Prefer one shared component over near-copies.** The three kanban boards and the two
  estimate pickers each drifted apart before being unified. `KanbanCard`, `BoardColumnHeader`
  and `KanbanColumnScroll` are now shared by the list board, the All Tasks board, and the
  Calendar Board — parameterize them, never fork them.

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
- `Cadence/macOS/Views/Timeline*`, `SchedulePanel*`, `CalendarPage*`, `CalendarBoard*` - timeline coordinate math, drag/drop, EventKit, and schedule state.
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
