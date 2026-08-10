# Cadence Source Guide

This subtree contains the app target source. Prefer reading `../AGENTS.md` first for repo-wide rules.

## Top-Level Shape

- `CadenceApp.swift` owns app startup, SwiftData model container setup, CloudKit configuration, and recovery behavior.
- `Models/` contains shared SwiftData `@Model` types.
- `Services/` contains shared services, migrations, notifications, widget support, the markdown/note parsing layer, schema, and `AI/` + `MCPReadOnly/`.
- `Shared/` contains design tokens (`Theme.swift`), common components, date/time formatting, and cross-platform presentation/query/mutation support.
- `macOS/` contains the fully implemented desktop app — the primary product surface.
- `iOS/` is a **large, actively-developed iOS/iPadOS surface — 64 files, not stubs.**
  `iOSRootView.swift` is an adaptive root shell (iPad regular-width sidebar, compact
  `TabView`) routing to real implementations of Today, Calendar, Tasks/Inbox, Focus, Goals,
  Habits, Notes (its own markdown editor stack), Lists, Search, and Settings. Feature parity
  with macOS is not guaranteed by design — check the actual view file. See `iOS/AGENTS.md`.

## Working Rules

- Keep model and persistence changes separate from view-only refactors when possible.
- Treat iOS changes with the same care as macOS. It is shipping UI, not placeholder work — but do not assume a macOS feature exists there, and do not import AppKit-only assumptions.
- Prefer shared helpers in `Shared/` only when behavior is genuinely cross-platform.
- Use `#if os(macOS)` / `#if os(iOS)` at platform boundaries instead of leaking AppKit/EventKit assumptions into shared code.
- When adding new Swift files, this project uses synchronized filesystem groups; still confirm the target compiles.

## Build Check

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project ../Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' build
```
