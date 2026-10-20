# Cadence Source Guide

This subtree contains the app target source. Prefer reading `../AGENTS.md` first for repo-wide rules.

## Top-Level Shape

- `CadenceApp.swift` owns app startup, SwiftData model container setup, CloudKit configuration, and recovery behavior.
- `Models/` contains shared SwiftData `@Model` types.
- `Services/` contains shared services, migrations, notifications, widget support, the markdown/note parsing layer, schema, and `AI/` + `MCPReadOnly/`.
- `Shared/` contains design tokens (`Theme.swift`), common components, date/time formatting, and cross-platform presentation/query/mutation support.
- `macOS/` contains the fully implemented desktop app — the primary product surface.
- `iOS/` is a **large, actively-developed iOS/iPadOS surface, not stubs.** Count it with
  `ls Cadence/iOS/*.swift | wc -l` rather than trusting a number in a guide: every figure written
  down here has been behind the directory at its next reading, by as much as 2x.
  `iOSRootView.swift` is an adaptive root shell — `iPadMacStyleRootShell` (sidebar) at regular
  width, `iOSCompactRootShell` (a hand-built **four-tab bottom bar**, `[ Tasks ] [ Calendar ]
  ( + ) [ Notes ] [ More ]`) at compact width — routing to real implementations of Today,
  Calendar, Tasks/Inbox, Focus, Goals, Habits, Notes (its own markdown editor stack), Lists,
  Search, and Settings. Feature parity with macOS is not guaranteed by design — check the actual
  view file. See `iOS/AGENTS.md` before touching the shell, and before adding any surface that
  opens a task: the inspector is presented by `iOSTaskInspectorHost`, and a row that owns the
  `.sheet` is the bug that guide's second section exists to stop you re-shipping.

  **There is no SwiftUI `TabView` anywhere under `iOS/`.** The shell is a `VStack` of content and
  a bar that is a **sibling** of the content, not an overlay and not a `safeAreaInset`, with one
  type-erased `NavigationPath` per tab. Both halves are corrections of shipped bugs, and "shells
  are `TabView`s" is the assumption that produced them.

## Working Rules

- Keep model and persistence changes separate from view-only refactors when possible.
- Treat iOS changes with the same care as macOS. It is shipping UI, not placeholder work — but do not assume a macOS feature exists there, and do not import AppKit-only assumptions.
- Prefer shared helpers in `Shared/` only when behavior is genuinely cross-platform.
- Use `#if os(macOS)` / `#if os(iOS)` at platform boundaries instead of leaking AppKit/EventKit assumptions into shared code.
- When adding new Swift files, this project uses synchronized filesystem groups; still confirm the target compiles.

## Build Check

Build through `scripts/xcb.sh <id> build|test`. The invocations and the two load-bearing flags are
in the root `AGENTS.md`, "Project Snapshot"; the refusals are in `docs/AGENT_BRIEF.md`. Neither is
restated here, because a second copy is a second thing to keep in step.
