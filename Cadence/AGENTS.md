# Cadence Source Guide

This subtree contains the app target source. Prefer reading `../AGENTS.md` first for repo-wide rules.

## Top-Level Shape

- `CadenceApp.swift` owns app startup, SwiftData model container setup, CloudKit configuration, and recovery behavior.
- `Models/` contains shared SwiftData `@Model` types.
- `Services/` contains shared services, migrations, notifications, widget support, the markdown/note parsing layer, schema, and `AI/` + `MCPReadOnly/`.
- `Shared/` contains design tokens (`Theme.swift`), common components, date/time formatting, and cross-platform presentation/query/mutation support.
- `macOS/` contains the fully implemented desktop app — the primary product surface.
- `iOS/` is a **large, actively-developed iOS/iPadOS surface — 93 `.swift` files at the time of
  writing, not stubs.** (`ls Cadence/iOS/*.swift | wc -l` — run it; this line said 79 while the
  root guides said 86 and the directory held 87, and it has been behind at every reading since.)
  `iOSRootView.swift` is an adaptive root shell — `iPadMacStyleRootShell` (sidebar) at regular
  width, `iOSCompactRootShell` (a hand-built **four-tab bottom bar**, `[ Tasks ] [ Calendar ]
  ( + ) [ Notes ] [ More ]`) at compact width — routing to real implementations of Today,
  Calendar, Tasks/Inbox, Focus, Goals, Habits, Notes (its own markdown editor stack), Lists,
  Search, and Settings. Feature parity with macOS is not guaranteed by design — check the actual
  view file. See `iOS/AGENTS.md` before touching the shell, and before adding any surface that
  opens a task: the inspector is presented by `iOSTaskInspectorHost`, and a row that owns the
  `.sheet` is the bug that guide's second section exists to stop you re-shipping.

  This file described the compact shell as a "`TabView`" long after `iOS/AGENTS.md` was rewritten
  to refute exactly that. There is no SwiftUI `TabView` anywhere under `iOS/`; the shell is a
  `VStack` of content and a bar that is a **sibling** of the content, not an overlay and not a
  `safeAreaInset`, with one type-erased `NavigationPath` per tab. Both of those are corrections of
  shipped bugs, and "shells are `TabView`s" is the assumption that produced them — which is why
  the wrong sentence mattered here, in the guide that is read before the iOS one.

## Working Rules

- Keep model and persistence changes separate from view-only refactors when possible.
- Treat iOS changes with the same care as macOS. It is shipping UI, not placeholder work — but do not assume a macOS feature exists there, and do not import AppKit-only assumptions.
- Prefer shared helpers in `Shared/` only when behavior is genuinely cross-platform.
- Use `#if os(macOS)` / `#if os(iOS)` at platform boundaries instead of leaking AppKit/EventKit assumptions into shared code.
- When adding new Swift files, this project uses synchronized filesystem groups; still confirm the target compiles.

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
