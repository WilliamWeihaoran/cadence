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

**Warning baseline: 0 on macOS, 0 on iOS.** It was three until `651694b` (`MarkdownLinkSupport`
was itself a main-actor isolation warning and went with the `nonisolated` pass), then two —
`SchedulingService` and `SettingsNotificationsSection` — until T-96 cleared both. Neither was a
bug: the first was a `guard let task` whose body had been emptied when the three scheduling
assignments moved into `TaskCreationDraft`, the second an `await MainActor.run` wrapper that was
already on the main actor and discarded `NSWorkspace.open`'s `Bool`. The baseline is now zero, so
**any** warning is a regression introduced by the change in hand.

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
- **Build into a private `-derivedDataPath` whenever another build may be running.** The shared
  DerivedData is a single mutable directory: a clean build deletes `Build/Products/`, and anything
  launched from there dies in `libsecinit` before `main()` with an `EXC_BREAKPOINT` that looks like
  an app crash and is not. It also produces `build.db is locked` failures that look like flaky tests.
  Every failure mode it causes is **misattributed by default** — it never says "another build is
  running", it says whatever the half-deleted directory happened to look like when you read it. On
  2026-08-18 it reported unresolvable swift-nio modules (`DequeModule`, `Atomics`) from a corrupt
  `SourcePackages`, which read as a broken checkout and briefly made a correct agent report look
  wrong. Rule: a build failure you cannot explain is a private-`derivedDataPath` re-run before it is
  a finding. Note `-derivedDataPath` requires `-scheme`; it is rejected with `-target` alone.
- **Check the log says which tree it built.** The scratchpad is shared, so an isolated tree can be
  deleted out from under a running build; the failed `cd` then falls through to the live repo and
  the run reports **exit 0 against the wrong sources**. This happened on 2026-08-18 and was caught
  only by grepping the log for the path xcodebuild echoes. Use a PID-unique directory, and confirm
  the isolated path appears in the log before trusting the result. `build.db is locked` and `unable
  to spawn swift-frontend` on a fresh private path are the same contention and clear on re-run.
- **Commit with `git commit --only <paths>` when agents share a working tree.** `git add <paths>`
  adds your paths *to whatever is already staged*, so another agent's `git mv` or `git rm` sitting in
  the index rides along into your commit. This has happened three times. The third was the expensive
  one: `c9d2d78` swept in a staged deletion of two view files whose callers were not yet committed,
  so **HEAD did not build for iOS** until the next commit — and it was invisible to verification,
  because isolating a change with `git archive HEAD` reproduces HEAD's *tree*, not its index, so the
  files were still present in every check. `--only` takes the paths and ignores the index. Failing
  that, read `git status --porcelain` for staged entries you did not stage before every commit.
- **iPhone and iPad are one style, not two.** They differ in *layout* — a tab bar against a
  sidebar, one pane against two — and should not differ in how a row, a chip, a header or a
  picker looks or behaves. So: a change asked for on one is a change to both unless it is
  genuinely shape-specific, and the default implementation is one view parameterised by size
  class rather than an `iPhoneFoo` beside an `iPadFoo`. When a request names only one of them,
  say which of the two it is and act accordingly rather than silently doing half.

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
  This file is also what keeps the app target on `SWIFT_VERSION = 5.0`.
  `CadenceLayoutManager` is main-actor isolated by the project default while `NSLayoutManager` is
  not, so its overrides disagree with what they override. `init`, `init(coder:)` and `drawGlyphs`
  are now `nonisolated` and clean; `drawBackground` is not, because its decoration passes need
  `MarkdownStylist`, `Theme` and `CadenceTextView`, and Swift 6 region isolation refuses the
  `MainActor.assumeIsolated` hop back (non-`Sendable` `self` cannot be sent). See the comment on
  the class — the fix is a refactor of where the decoration pass lives, not an annotation.
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
