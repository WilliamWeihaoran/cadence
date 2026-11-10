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
- Tasks, Today, Calendar, Focus, Notes, Lists, Search, Settings, reminders, export,
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
- Switching subject must commit elapsed time through the shared support path.
- Leaving the Focus screen ends nothing (T-15548): the session lives in `CadenceFocusSessionOwner`,
  as the Mac's lives in `FocusManager.shared`; the screen reads it, never `@State`.

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

## Simulator Taps

Limits of Claude Code's simulator `control` transport, measured on the standing devices; a control
that "does nothing" is not evidence until these are ruled out.

- **A SwiftUI `Toggle` needs `duration: 0.12`.** A zero-duration tap left the Do panel's
  `Without time` switch unchanged four times out of four at three aim points; the first tap with
  `duration: 0.12` flipped it. Plain `Button`s on the same panel take a zero-duration tap. Only a
  `Toggle` was measured; send any other UIKit-backed control (a stepper) a duration too ([[T-8465]]).
- **Paired taps** (a completion circle): two taps sent as sequential calls land ~1.5-3 s apart, so a "second tap within
  1.2 s" check is never driven, and the second lands on whatever row slid into the slot -- it
  completed the WRONG task twice. Sent as parallel calls they land ~100-250 ms apart, but 6 of 10
  pairs delivered only one tap, and three or four parallel taps coalesce to at most two. Read a
  paired-tap trial only off a capture, never off the end state ([[T-8464]]).
- **A press-and-hold lift cannot be driven.** A `touch_path` held still 0.8 s or 1.5 s then dragged
  scrolls the Calendar timeline instead of lifting a timed block. A third-tap-cancels check and a
  hold-to-lift check need a human finger on an attended run.
- **`xcrun simctl io <udid> screenshot <file>` is the authoritative capture; the MCP `screenshot`
  action is not.** The MCP action served pixel-identical frames with a frozen clock for minutes
  while the app had moved two screens on ([[T-11401]]; trigger not identified). Use it to aim, but
  re-take any load-bearing frame, and every "the control did nothing" verdict, with `simctl`.
- **A mid-gesture frame IS capturable -- by RECORDING, not by screenshotting.** The line above this
  one used to end the matter; it does not. `xcrun simctl io <udid> recordVideo --codec h264 --force
  <file>`, started in the background for the duration of a `touch_path` and stopped with `kill -INT`
  on its OWN pid (check `ps` first -- a sibling may be recording too), captures the whole gesture;
  pull frames out with a short `AVAssetImageGenerator` script run through `xcrun swift`. 23.7 s
  recorded gave 95 frames at 0.25 s and finally measured [[T-8321]]'s 2pt drop rule, which two runs
  had written off as unreachable. There is no ffmpeg, PyObjC or OpenCV on this Mac, so AVFoundation
  via `xcrun swift` is the extraction route that works. Do **not** attempt this with screenshots:
  `xcrun simctl io ... screenshot` measured **6.9-9.7 s** per frame under load, and seven launched in
  parallel 1 s apart returned seven BYTE-IDENTICAL files -- the grab happens when the call
  completes, not when it starts ([[T-13523]]).
- **`press_key` has no `escape`, and the `text` action is literal.** The key set is closed:
  `return`, `delete`, `forward_delete`, the four arrows, `home`, `end`, `page_up`, `page_down`,
  `select_all`, `undo`, `redo`. `escape` is refused by the schema, and sending `\u001b` through
  `text` types those six characters into the field. With no `simctl` key-injection subcommand and
  the hardware keyboard belonging to the host Simulator.app, an Escape check -- or any modified key
  -- is a HUMAN sighting, not an agent one ([[T-11051]], [[T-13282]]).

- **A midnight rollover is drivable** ([[T-15200]]). In a Debug build, launch with
  `SIMCTL_CHILD_CADENCE_UI_TEST_MODE=1 SIMCTL_CHILD_CADENCE_UI_TEST_TODAY=yyyy-MM-dd` exported
  before `simulator-claim.sh launch`, then each
  `xcrun simctl spawn <udid> notifyutil -p com.haoranwei.Cadence.uitest.advanceToday` moves
  `todayKey()` one day on and fires the day-change signal. Only `todayKey()` moves, not raw `Date()`
  reads: `docs/OWNER_SIGHTINGS.md` section E.

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
