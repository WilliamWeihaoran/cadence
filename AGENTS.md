# Cadence Agent Guide

This file is the first stop for coding agents. Keep it compact: `CLAUDE.md` is the Claude Code
startup router, and `docs/AGENTS_REFERENCE.md` preserves the former long root guide.

## Project Snapshot

Cadence is a native SwiftUI productivity app with a fully built macOS surface, shared SwiftData
models, CloudKit sync, EventKit calendar/reminder integration, widgets, MCP support, and a large
real iOS/iPadOS surface.

Primary target:

- Project: `Cadence.xcodeproj`
- Scheme: `Cadence`
- Platform: macOS

Build from repo root with private DerivedData:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-build-$$ build
```

Tests must be scoped to `CadenceTests`:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-test-$$ -only-testing:CadenceTests
```

Unscoped tests pull in `CadenceUITests`, which cannot launch headless. The warning baseline is zero.
Any new warning is a regression.

## Where Things Live

- `Cadence/CadenceApp.swift` - app entry, model container, CloudKit setup, recovery.
- `Cadence/Models/` - shared SwiftData models.
- `Cadence/Services/` - shared services, migrations, notifications, markdown logic, AI, MCP.
- `Cadence/Shared/` - theme tokens, shared components, date/time utilities, presentation helpers.
- `Cadence/macOS/` - primary desktop app surface.
- `Cadence/macOS/Views/` - macOS feature screens and support views.
- `Cadence/macOS/Services/` - macOS-only managers for focus, calendar, hotkeys, deletion, scheduling.
- `Cadence/macOS/Editor/` - AppKit-backed markdown editor bridge. High risk.
- `Cadence/iOS/` - large iOS/iPadOS surface, not a stub; parity with macOS is not guaranteed.
- `CadenceWidgets/` - widget extension; the `Cadence` scheme already builds it.
- `CadenceMCPServer/`, `plugins/cadence-mcp/` - separate MCP boundary.
- `CadenceTests/` - unit tests. Look for an existing file before adding one.
- `docs/` - shipped docs plus detailed agent references.

## Scoped Guides

Read the nearest scoped `AGENTS.md` before editing under that tree:

- `Cadence/AGENTS.md`
- `Cadence/Models/AGENTS.md`
- `Cadence/Services/AGENTS.md`
- `Cadence/Shared/AGENTS.md`
- `Cadence/iOS/AGENTS.md`
- `Cadence/macOS/AGENTS.md`
- `Cadence/macOS/Services/AGENTS.md`
- `Cadence/macOS/Editor/AGENTS.md`
- `Cadence/macOS/Views/AGENTS.md`
- `CadenceMCPServer/AGENTS.md`
- `plugins/cadence-mcp/AGENTS.md`

Long references, searchable only when needed:

- `docs/CONTEXT_INDEX.md` - small routing map by change type.
- `docs/AGENTS_REFERENCE.md` - detailed root runbook and red-run history.
- `docs/SHARED_AGENTS_REFERENCE.md` - detailed Shared guide.
- `docs/IOS_AGENTS_REFERENCE.md` - detailed iOS guide.
- `docs/CLAUDE_REFERENCE.md` - detailed product/feature history.

## Non-Negotiable Patterns

- No hardcoded colours. Use `Theme.*` or user-owned `colorHex`; no bare `.white`, `.black`, `.gray`,
  or `Color(hex:)` literals outside `Theme.swift`.
- Persisted dates are `yyyy-MM-dd` strings unless an existing model says otherwise.
- Use `DateFormatters` and `TimeFormatters`; do not create ad hoc `DateFormatter()` instances in views.
- SwiftData/CloudKit to-many relationships must be optional arrays (`[Type]?`). Read with `?? []`;
  append by assigning a new array.
- Page headers do not describe the page the user is already on. Search rows, empty states, and
  picker rows may keep subtitles.
- Use one hover/selection layer at one radius.
- Prefer one shared component over near-copies.
- iPhone and iPad share one style; they differ by layout, not by row/chip/header vocabulary.
- Do not revert unrelated user or agent changes.

## Build And Run Safety

- Always build into a private `-derivedDataPath` when another build may be running.
- A private DerivedData path isolates build output, not the macOS test host's app-group container.
  Use `scripts/test-host-lock.sh` for macOS test runs.
- If `xcodebuild` sits at `Command line invocation` with 0% CPU, suspect a project-file lock before
  debugging Swift.
- Never create simulator devices. Use one existing stock simulator and `scripts/simulator-claim.sh`.
- Launch the macOS app only through `scripts/run-macos-app.sh start <Cadence.app> <id>`, and pair it
  with `stop <id>` in the same turn.
- Use one scratch directory per agent and clean only inside it.
- For isolated verification, prefer `rsync` over `git archive`, then restore unrelated dirty paths
  in the copy back to HEAD before testing.
- Long build/test runs should launch and poll in one shell invocation.
- Confirm the build log names the tree you intended to test.

## Red-Run Triage

Before treating a red run as a code regression, check:

- Macro/plugin/load errors only, `build.db is locked`, or `unable to spawn swift-frontend`: concurrent
  builds. Re-run.
- Thousands of zero-second test failures and multiple `My Mac - Cadence (...)` host PIDs: concurrent
  macOS test hosts. Re-run under `scripts/test-host-lock.sh`.
- A few zero-second failures and one host PID: inspect the `.xcresult`; the test runner may have
  exited early.
- UI-test failures in an ordinary test run: the run was not scoped to `CadenceTests`.
- Compile failures that name your file are real until proven otherwise.

Full incident details are in `docs/AGENTS_REFERENCE.md`.

## Risk Hotspots

- `Cadence/Models/` and `Cadence/Services/CadenceSchema.swift` - schema changes need migration and
  CloudKit awareness.
- `Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift` and `MarkdownEditorSupport.swift` -
  AppKit/SwiftUI bridge, custom caret/drawing/slash commands/undo.
- `Cadence/macOS/Views/Timeline*`, `SchedulePanel*`, `CalendarPage*` - timeline math, drag/drop,
  EventKit, schedule state.
- `Cadence/macOS/Views/TasksPanel*`, `ListDetail*`, `Inbox*`, `Kanban*` - task surfaces, sorting,
  grouping, drag reorder, completion animations.
- `Cadence/macOS/Services/CalendarManager.swift`, `SchedulingService.swift`,
  `TaskWorkflowService.swift`, deletion helpers - data mutations and EventKit side effects.
- Model or shared-service changes must review the MCP boundary; build `CadenceMCPServer` separately
  when relevant.

## Refactor Guidance

Keep SwiftUI roots thin. Split by responsibility: root view for state/orchestration, support views
for rows/sections, support/state files for derived state and geometry, services for persistence
mutations and external side effects. Keep edits scoped, follow existing patterns, and run
`git diff --check` plus the relevant build/test command after structural changes.
