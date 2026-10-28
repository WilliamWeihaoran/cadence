# iOS Guide

`Cadence/iOS/` is a large, actively developed iPhone/iPad surface, not a stub. Keep this guide
compact. The full former guide is preserved at `../../docs/IOS_AGENTS_REFERENCE.md`.

## Working Rules

- Treat iOS as shipping UI. Do not assume parity with macOS; read the actual files.
- iPhone and iPad share visual language. They differ by layout, not by row/chip/header styling.
- Prefer shared components and support types from `Cadence/Shared/` before adding iOS-only copies.
- Keep the compact shell, task inspector host, bundle host, focus handoff, markdown styling, and
  wind-down flows on their established paths.
- When detail is missing here, search `../../docs/IOS_AGENTS_REFERENCE.md` for the relevant section
  rather than reading the full reference.
- **The iOS leg is mandatory: the macOS test target never compiles this directory, so skipping it
  means an iOS change was never compiled at all** (T-1282). Build against one of the two standing
  devices `docs/AGENT_BRIEF.md` names by UDID, claimed through `scripts/simulator-claim.sh` —
  never a device you did not create, and never the owner's. A destination this Mac does not have
  used to fail as a *fake pass*: `XCODEBUILD_EXIT=70` with `compile errors: 0` and `warnings: 0`
  over zero compiled files, dissented from only by `VACUOUS-COUNT`. `xcb.sh` now refuses it
  outright (`NO-SUCH-SIMULATOR`, exit 10) and names the devices it does have.
- **An iOS UI test runs through `CadenceUITestsOnly`, never through `Cadence`** (T-2074).
  `xcodebuild` builds every testable in the scheme whatever `-only-testing:` says. (The reason first
  given here, that `CadenceTests` cannot compile for iOS, ended with [[T-3244]]: it compiles, and its
  three whole-file `#if os(iOS)` suites run through `-scheme Cadence` on `Cadence-iPhone15` — 22
  tests, measured 2026-10-25, [[T-6541]] -- and in CI's `ios-build` simulator step, [[T-6821]].) The shared
  `CadenceUITestsOnly` scheme holds `CadenceUITests` alone: `scripts/simulator-claim.sh claim <id>`,
  then `scripts/xcb.sh <id> test -scheme CadenceUITestsOnly -destination 'platform=iOS Simulator,id=<udid>'
  -only-testing:CadenceUITests/<Suite>`. Measured 2026-10-09: 2 tests, 0 failures, 27.9 s against
  exit 65 and 0 test result lines through `Cadence`. It needs no automation-mode grant; that is the
  macOS half (T-2049). Pinned by
  `CadenceBuildInvocationHygieneTests.theUITestsOnlySchemeHoldsTheUITargetAloneSoAnIOSRunNeverBuildsTheMacOnlyUnitTarget`.

## Current Shape

- `iOSRootView.swift` owns the adaptive root shell and installs global hosts.
- iPad regular width uses a sidebar shell.
- iPhone compact width uses a custom four-tab bottom bar, not `TabView`.
- The compact tabs are Tasks, Calendar, Notes, More. The center `+` presents capture and is not a tab.
- Each compact tab owns its own type-erased `NavigationPath`.
- Tasks, Today, Calendar, Focus, Goals, Habits, Notes, Lists, Search, Settings, reminders, export,
  reset, notifications, and note markdown are real surfaces.

## Task Inspector

The task inspector is presented by a host, never by a row.

- `iOSTaskInspectorHost()` is installed once in `iOSRootView`.
- Surfaces open it through `@Environment(\.iOSTaskInspector)`.
- Rows/cards must not own `@State showDetail` plus `.sheet` for `iOSTaskDetailSheet`.
- A row in a filtered `ForEach` can disappear when the inspector mutates the task, taking its own
  sheet with it. This is the shipped bug the host pattern prevents.
- Leave deliberate non-task-inspector sheets alone; see the archived reference before changing a
  presenter.

## Blocks ("Bundles") Are Gone From iOS

- [[T-3170]] removed every iOS Block surface. There is no Block card, no Block panel, no Block
  host and no `TaskBundle` query anywhere under `Cadence/iOS/`.
- `iOSBundleInspectorHost()` and `iOSCalendarBundleDetailSheet` are deleted; do not re-add a
  second inspector host. `iOSTaskInspectorHost` is the only one, and the lifetime rule it exists
  for is in "Task Inspector" above.
- Do not re-add a bundle-forming drop. A task dropped on a task is a reorder or a no-op, per
  surface; the gesture that made a block is gone from both platforms.
- `TaskBundle` itself stays a `@Model` until a build ships that no device can hold a record for
  — see `Cadence/Services/CadenceTaskBundleRetirement.swift`. Keeping the entity is not
  permission to draw it.
- Pinned by `CadenceTests/CadenceBundleInspectorHostTests`.

## List And Column Wind-Down

Archiving or completing a list/column is a wind-down, not a raw status flip.

- Use the shared lifecycle service/model-context helpers; do not hand-set status at the row.
- The confirmation asks the settle operation for the tasks it will affect, so counts match the
  mutation.
- Completion is not archive with different copy: it asserts work happened and can move goal progress.
- Completion is a context-menu item, not a swipe action.
- Reopening a column/list is not a wind-down; use the dedicated reopen path.

## Focus Handoff

iOS enters Focus by handing over a target, not by un-guarding macOS `FocusManager`.

- `CadenceFocusHandoffCenter` carries requests from task rows or bundle sheets to Focus.
- `iOSRootView.routeToFocus()` navigates only.
- `iOSFocusView.accept(_:)` adopts the target only.
- A handoff is not a play tap; requesting focus should not pause the current subject by accident.
- Use `CadenceFocusTarget`, not a bare `UUID`.
- Leaving Focus must commit elapsed time through the shared support path.

## Today

- Today's rollover banner and decision logic are shared.
- One `UserDefaults` date key controls dismissal.
- While the banner is visible, over-do tasks can be withheld from normal groups deliberately.
- The banner bucket yields to due/overdue buckets.
- Today groups by intent, using shared Today grouping support.

## Markdown

All mobile markdown styling is split by responsibility:

- `iOSMarkdownStylingSupport.swift` - base attributes and pass order.
- `iOSMarkdownStylingLineSupport.swift` - quote/list/checkbox line styling.
- `iOSMarkdownStylingBlockSupport.swift` - fenced code, tables, dividers, images, task embeds.
- `iOSMarkdownStylingInlineSupport.swift` - emphasis, links, wiki/task references, image tokens.

Markdown parsing/mutation logic generally belongs in `Cadence/Services/Markdown*Support.swift`,
not in platform editor files.

## Compact Tab Shell

- `iOSCompactTabShell.swift` declares the compact root shell, tab bar, capture button, and helpers.
  `../../docs/ios-tab-shell-plan.md` is its design record and the only place three owner-directed
  cuts are written down — the up-next hero, the Today capture bar, the `VStack`-sibling bar. Where
  it and the code disagree, the code wins.
- The `+` is not a tab and never renders selected state.
- The bar is a sibling of content in a `VStack`, not an overlay or `safeAreaInset`.
- Tabs are built on first visit and kept alive to preserve state.
- `Cadence/Shared/CadenceCompactTab.swift` owns tab routing.
- iPad regular width is not part of the compact-tab implementation.

## Reference Sections

Search `../../docs/IOS_AGENTS_REFERENCE.md` for:

- `The Task Inspector Is Presented By A Host`
- `The Bundle Panel Has Its Own Host`
- `Two Tasks Become A Block`
- `Archiving Or Completing A List`
- `A Kanban Column Winds Down`
- `A Focus Session Is Entered By Handing Over A Target`
- `Today's Rollover Notice`
- `The markdown styling layer`
- `The iPhone tab shell`
