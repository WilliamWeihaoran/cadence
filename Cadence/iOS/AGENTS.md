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

## Bundle Panel And Bundle-Forming Drops

- Bundle inspection uses its own host for the same lifetime reason as the task inspector.
- `iOSBundleInspectorHost()` is installed at the root.
- Bundle-forming drag/drop is an opt-in surface behavior, not a default row behavior.
- Only scheduled cards/blocks can form bundles; no slot means no bundle block to create.
- Nested cards that claim a drag must say so to avoid parent column drop handling.
- The shared mutation is `CadenceTaskMutationSupport.insertBundle(from:adding:)`.

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
