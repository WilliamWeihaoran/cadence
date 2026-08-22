# iOS Guide

The iOS/iPadOS app is a large, actively-developed surface (93 `.swift` files at the time of writing, covering Today, Calendar, Tasks, Focus, Goals, Habits, Notes, Lists, Search, Settings) — not early/stubbed. Re-count with `ls Cadence/iOS/*.swift | wc -l` when you add one rather than trusting the figure. Do not assume macOS feature parity by default; check the actual view file.

## Working Rules

- Keep iOS-specific UI in this subtree.
- Use shared models/services/components where appropriate, but avoid importing macOS-only managers or AppKit assumptions.
- This is real, shipping UI — treat changes here with the same care as macOS, not as placeholder work.
- When adding real iOS behavior, check shared SwiftData models and platform conditionals carefully.

## Current State

The macOS app is the primary product surface. iOS is a large, real, actively-developed surface. `iOSRootView.swift` is an adaptive root shell: `iPadMacStyleRootShell` (sidebar) at regular width, `iOSCompactRootShell` (bottom tab bar) at compact width, routing to full implementations of most macOS feature areas.

## The Task Inspector Is Presented By A Host, Never By A Row

**A row, a card or a timeline block must not own a `.sheet` that presents `iOSTaskDetailSheet`.**
Ask for it from the environment instead:

```swift
@Environment(\.iOSTaskInspector) private var taskInspector
...
.onTapGesture { taskInspector(task) }
```

`iOSTaskInspectorHost()` is applied **once**, in `iOSRootView`, above both shells and beside
`cadenceStartupIssueBanner` — one call, so "every page has a host" is true by construction instead
of by remembering. It holds the selection in its own `@State` and presents the sheet from a lifetime
that outlives any row's. The action is a callable
(`iOSTaskInspectorPresentAction`), deliberately not a binding, so a call site *cannot* hold the
selection even if it wants to.

Why the rule rather than a guard: a row lives inside a filtered `ForEach`, and a sheet is torn down
with the view that presents it. `iOSTaskRow` owned `@State showDetail` plus
`.sheet(isPresented:)`, so any status write made *from inside the inspector* — Cancel, Restore, mark
done — moved the task out of its section, SwiftUI removed the row, and the panel went with it. The
control experiment is the one that dates the bug: **Start** ran the identical `onSetStatus` path and
left the panel open, because an in-progress task stays in the same section. Nothing was calling
`dismiss()`; the defect was ownership. Four surfaces had it — `iOSTaskRow`, `iOSBoardTaskCard`,
`iOSTimelineTaskBlock` and Today's `iOSScheduleReadyTaskRow` (T-201, `4562d4e`) — which is what a
pattern reached for by habit looks like, and why this is written down: the next agent adding a task
surface will otherwise reach for `@State showDetail` and add a fifth.

**Four presenters keep their own `.sheet(item:)`, deliberately. Do not "finish the job".**
`iOSSearchView`, `iOSMarkdownEditingSurface`, `iOSMarkdownReferenceSupport` and
`iOSCalendarBundleDetailSheet` each present from a surface that does not re-filter under them, so
they have nothing to be torn down by — and **three of them present from inside a sheet**, where a
host above is already presenting and a second request from it silently does nothing at all.
Converting them for uniformity would trade a correct pattern for a dead tap.

**A held model is gone when `isDeleted || modelContext == nil` — both signals, measured.** The
decision lives in `Shared/CadenceDetailPanelPresentation.swift` (in `Shared/` because this folder
is inside `#if os(iOS)` and invisible to the macOS-built `CadenceTests`), and it is **one** type read
by both hosts since T-217: it was `CadenceTaskInspectorPresentation`, with `task`-shaped parameter
names, until the bundle panel needed exactly it — nothing in the rule was ever about an `AppTask`,
so the names lost the noun rather than the rule gaining a second copy. Against a real store:
between `delete(_:)` and the save, `isDeleted` is `true` with `modelContext` still set; **after the
save `isDeleted` reads `false` again** while `modelContext` goes `nil` and the property snapshot
stays readable — so a guard on `isDeleted` alone never fires for the committed delete, which is the
only one that can reach a panel from outside it. That is not hypothetical: it is what the first
draft did, and the test that killed it is why both signals are there.

Leaving the page's query is **not** a reason to close, and `resolve` takes
`subjectLeftThePageQuery` as an ignored parameter so that saying so is a test failure rather than a
comment. After cancelling a task from Today the next thing a user may want is Restore, which lives
in the panel that used to vanish.

## The Bundle Panel Has Its Own Host, For The Same Reason

**T-217, closed.** `iOSCalendarBundleDetailSheet` had the identical defect on a different sheet:
`iOSCalendarBoardBundleCard` and `iOSTimelineBundleBlock` each owned `@State showDetail` plus
`.sheet(isPresented:)`, and both are drawn from a `ForEach(bundles)` already filtered by day — by
*hour* as well on Today's schedule pane. `iOSBundleInspectorHost()` is now applied once in
`iOSRootView` beside `iOSTaskInspectorHost()`, over `@Environment(\.iOSBundleInspector)`, and both
cards ask for the panel instead of owning it.

A separate host, because it presents a different sheet on a different model; the **same**
`CadenceDetailPanelPresentation` for when to close, because that rule was never task-shaped.

**Two presenters of the bundle sheet keep their own `.sheet(item:)`, and the reason differs from the
four above.** `iOSCalendarDayInspector` and `iOSCalendarMonthAgendaList` hold `@State
selectedBundle` on the *pane*, with `.sheet(item:)` above the conditional that decides whether the
pane lists anything — so a bundle edited out of that day or month empties a section rather than
removing the presenter. Neither presents from inside a sheet, so a host above them would work; they
keep ownership because ownership is not the bug there. `CadenceBundleInspectorHostTests` pins the
whole set at three, so a fourth appearing anywhere is a test failure.

Reproducing it on a simulator: the reachable write is a member task's completion circle *inside* the
panel, not the date field. The panel's Save calls `dismiss()` itself, so a date edit cannot show the
difference — but finishing the last active member makes the block `isCompleted`, and every surface
queries bundles with `includeCompleted: false`. Two members gives the control for free: the first
circle leaves the card in place, the second removes it.

## Two Tasks Become A Block On The Board, And Nowhere Else Yet

**T-190.** "Drop a task on a task and the two become a block" was macOS-only because
`SchedulingActions.createBundle(from:adding:)` sat inside `#if os(macOS)`. The mutation is
`CadenceTaskMutationSupport.insertBundle(from:adding:)` now and the Mac delegates to it, so there is
one implementation. **Do not add a second** — the whole ticket was about a `Shared/`-shaped mutation
hiding behind a platform guard.

iOS wires it on the **Calendar Board** (`iOSCalendarBoardView`), not on the timeline, and the reason
is not preference: `iOSCalendarTimelineViews.swift` has no `.draggable` and no `.dropDestination`
anywhere, so `iOSTimelineTaskBlock` cannot be dragged at all. That file's own comment records why
nobody has added one — it carries a `simultaneousGesture` pinch, and `.draggable` "delays the
touches of everything under it". See T-243 before attempting it.

Three things about the board wiring that are easy to get wrong:

- **The card opts in, whole.** `iOSBoardTaskCard` takes an optional `iOSBoardTaskCardBundleDrop`
  bundling the task list, the drop handler and the targeting callback, because the three are
  useless apart. `iOSListSupportViews` draws the same card and passes `nil`, and so does the
  column's *completed* footer — a finished card is not something you plan around.
- **Only a card with a slot offers it.** `bundleFormingDrop(onto:)` returns `nil` unless
  `task.scheduledStartMin >= 0`. A bundle is `dateKey` **plus** `startMin`; the shared mutation
  refuses a do-dated-only target, so without this guard the card would light up amber and then
  silently do nothing. Declining instead lets the day column read the release as the reschedule it
  already is.
- **A nested card that claims a drag must say so.** The column has its own `dropDestination`, and it
  fires on the same release. `nestedDropTargetID` plus the short-lived `recentlyBundledTaskID`
  window is what stops the task being rescheduled straight back out of the block it was just put
  into. That state used to be `targetedBundleID`, named for its only user; a task card needed the
  identical mechanism, which is the same lesson the `CadenceTaskInspectorPresentation` →
  `CadenceDetailPanelPresentation` rename recorded — **a helper named for one subject is why the
  second one never got checked against it.**

The `.dropDestination` is attached in an `if let` branch rather than always-on-returning-`false`,
because `isTargeted` fires whether or not the closure accepts the drop — an always-attached version
would highlight cards on surfaces that cannot bundle.

## Archiving A List Is A Wind-Down, Not A Status Flip

**T-215.** `archive(_ area:)` here was `area.status = .archived` and a save. macOS's archive has
always also **cancelled the list's remaining active tasks**, through
`TaskContainerLifecycleService`, which sat inside `macOS/Services/TaskWorkflowService.swift`'s
`#if os(macOS)` while importing nothing platform-specific. So the same area wound down to two
different sets of open work depending on which device the swipe happened on, and the Mac's All
Tasks kept surfacing work the phone had filed away. The service is
`Cadence/Services/CadenceTaskContainerLifecycleService.swift` now — sixth instance of that shape.

Three things about the iOS wiring that are easy to get wrong:

- **One archive call site.** `ModelContext.archiveList(_:)` in `iOSListArchiveSupport.swift` is the
  only place `status = .archived` is written on this platform, and the only place the wind-down is
  reached. `CadenceListArchiveSurfaceTests` sweeps the whole folder for a hand-written
  `status = .archived` and fails on a second one — which is the bug the ticket was about.
- **The confirmation is conditional, and that is the design.** macOS's archive is behind an edit
  sheet you had to open; iOS's is a row swipe and a long-press item, so the ceremony has to come
  from somewhere. But a sheet that appears over a list where nothing is open is a sheet people
  learn to dismiss without reading. `CadenceListArchiveSummary.requiresConfirmation` is the test,
  it is asked **once** (in `iOSListsView.requestArchive`), and the iPad pane calls up into that
  rather than deciding for itself.
- **The count comes from the settle's own array.** `TaskContainerLifecycleService.remainingActiveTasks`
  is public for exactly this: a confirmation that counted by a second walk would eventually
  over-promise. An area rolls up its child projects, because a child keeps its own `status` and its
  tasks stay reachable after the parent is filed away.

Deliberately not changed: list **completion** is still macOS-only (T-214) — un-guarding the service
makes it a call site and nothing more, but nothing on iOS offers the action yet — and archiving a
kanban **column** on iOS is still a draft toggle in the list editor that settles nothing (T-247).
Do **not** reach for `markDone` / `markCancelled` / `applyStatusCompletion` for either: they spawn
the next recurrence occurrence into the same area, project and section, so a wind-down routed
through them refills the container it just closed.

## The markdown styling layer

`iOSMarkdownStyler` is **four files** since T-121, all extensions on the one enum:

- **`iOSMarkdownStylingSupport.swift`** — base attributes, `attributedString` (the pass order),
  `applyFrontmatter`, `styleLine` (the per-line dispatch), the font helpers, `drawCanvas`, `hide`.
- **`iOSMarkdownStylingLineSupport.swift`** — quote/list/checkbox line styling, the matchers, and
  `iOSMarkdownQuoteMatch` / `iOSMarkdownListMatch`. It held the heading type *ramp* until T-180;
  that is `MarkdownHeadingRamp` in `Services/` now, because `iOSMarkdownPreview` had a second,
  smaller ramp of its own and the same H1 rendered at two sizes on one platform.
- **`iOSMarkdownStylingBlockSupport.swift`** — fenced code, tables, dividers, images, task-embed
  cards; `collapseLine`.
- **`iOSMarkdownStylingInlineSupport.swift`** — emphasis spans, links, wiki/task references, image
  references, hashtags.

**Nothing in them decides what a string means.** That half went to `Services/` where the
macOS-built test target can reach it — `MarkdownStyleRanges` (heading marker visibility, block
ranges, the reveal test, the inline exclusion set), `MarkdownInlineMarkerRanges` (which marker
characters disappear, the hashtag and image-reference patterns), `MarkdownTableParser.tableBlock`
(the table walk, shared with `MarkdownPreviewParser`), and `MarkdownStyleSignature` (renamed from
`iOSMarkdownStyleSignature`). A styling bug that is really a parsing bug is fixed there, with a
test; only the attributes belong here.

## The iPhone tab shell

Earlier versions of this file and of `CLAUDE.md` described a "compact `TabView` shell". That was
wrong — there was no `TabView` anywhere in this folder. The compact shell was one `NavigationStack`
over one `NavigationPath`, rooted at `iOSCompactHomeView`, a grid of eight tiles that existed only
because there was no bar. `iOSCompactHomeView` is deleted. What is actually here now:

- **`iOSCompactTabShell.swift`** — `iOSCompactRootShell`, the bar, the capture button, the quick
  capture sheet, and `iOSCompactTabPaths`. Four tabs and a centre `+`:
  `[ Tasks ] [ Calendar ] ( + ) [ Notes ] [ More ]`.
- **The `+` is not a tab.** It presents; it never selects. `CadenceCompactTab` has four cases on
  purpose, so no code path can hand it a selected state.
- **One `NavigationPath` per tab, each type-erased.** A homogeneous
  `[CadenceFeatureDestination]` silently discards a `NavigationLink(value:)` of any other type —
  that shipped once, and made every Lists row dead. Four paths, four chances to repeat it.
- **The bar is a sibling of the content in a `VStack`, not an overlay and not a
  `safeAreaInset`.** `safeAreaInset(edge: .bottom)` was tried first and came back as no inset at
  all on screens that paint `Theme.bg.ignoresSafeArea()` behind their scroll view: the last row of
  All Tasks sat under the bar at full scroll. Do not reintroduce per-screen bottom padding to
  compensate for the bar; the layout is what guarantees the clearance.
- **Tabs are built on first visit and kept alive** (`visitedTabs`), which is what preserves scroll
  position and in-progress edits across a tab switch. A cold launch builds Tasks only.
- **`Cadence/Shared/CadenceCompactTab.swift`** owns the routing table — which tab owns each
  `CadenceFeatureDestination`, which Tasks segment, and what a `CadenceDeepLink` resolves to. It
  lives in `Shared/` because this folder is inside `#if os(iOS)` and invisible to the macOS-built
  `CadenceTests`. `CadenceCompactTabTests` pins that every destination is either a tab root or a
  More row, so nothing can become unreachable.
- **iPad regular width is untouched.** All of the above is compact width only.
