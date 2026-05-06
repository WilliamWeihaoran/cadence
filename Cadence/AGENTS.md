# Cadence Source Guide

This subtree contains the app target source. Prefer reading `../AGENTS.md` first for repo-wide rules.

## Top-Level Shape

- `CadenceApp.swift` owns app startup, SwiftData model container setup, CloudKit configuration, and recovery behavior.
- `Models/` contains shared SwiftData `@Model` types.
- `Services/` contains shared services, migrations, markdown/note utilities, schema, and AI helpers.
- `Shared/` contains design tokens, common components, date/time formatting, and shared UI helpers.
- `macOS/` contains the fully implemented desktop app.
- `iOS/` contains early/stub views only.

## Working Rules

- Keep model and persistence changes separate from view-only refactors when possible.
- Do not introduce cross-platform assumptions from macOS into iOS stubs.
- Prefer shared helpers in `Shared/` only when behavior is genuinely cross-platform.
- Use `#if os(macOS)` / `#if os(iOS)` at platform boundaries instead of leaking AppKit/EventKit assumptions into shared code.
- When adding new Swift files, this project uses synchronized filesystem groups; still confirm the target compiles.

## Build Check

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project ../Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' build
```
