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

## Archiving *Or Completing* A List Is A Wind-Down, Not A Status Flip

**T-215, and T-214 beside it.** `archive(_ area:)` here was `area.status = .archived` and a save. macOS's archive has
always also **cancelled the list's remaining active tasks**, through
`TaskContainerLifecycleService`, which sat inside `macOS/Services/TaskWorkflowService.swift`'s
`#if os(macOS)` while importing nothing platform-specific. So the same area wound down to two
different sets of open work depending on which device the swipe happened on, and the Mac's All
Tasks kept surfacing work the phone had filed away. The service is
`Cadence/Services/CadenceTaskContainerLifecycleService.swift` now — sixth instance of that shape.

**T-214** is the other direction, and closing it did not add a second mechanism. iOS offered no
**Complete** action for a list at all while macOS's `EditListSheet` had one on both branches; the
service was already cross-platform, public and tested (that was T-215's un-guard), so what was
missing was an affordance. `iOSListArchiveSupport.swift` is `iOSListWindDownSupport.swift` now, with
an `iOSListWindDownAction` beside the list — exactly the shape `iOSColumnWindDownTarget` already
had, because the column needed both directions first.

Five things about the iOS wiring that are easy to get wrong:

- **One wind-down call site, for both directions.** `ModelContext.windDownList(_:)` in
  `iOSListWindDownSupport.swift` is the only place `status = .archived` or a list's
  `status = .done` is written on this platform, and the only place the settle is reached.
  `CadenceListWindDownSurfaceTests` sweeps the whole folder for both and fails on a second one —
  which is the bug both tickets were about. The `.done` sweep is spelled `area.status = .done` /
  `project.status = .done` rather than bare, because `AppTask` legitimately carries that status and
  `iOSSampleDataSupport` writes it.
- **The confirmation is conditional, and that is the design.** macOS's archive is behind an edit
  sheet you had to open; iOS's is a row swipe and a long-press item, so the ceremony has to come
  from somewhere. But a sheet that appears over a list where nothing is open is a sheet people
  learn to dismiss without reading. `CadenceContainerWindDownSummary.requiresConfirmation` is the
  test, it is asked **once** (in `iOSListsView.requestWindDown`), and the iPad pane calls up into
  that rather than deciding for itself. (The type was `CadenceListArchiveSummary` until T-247
  shared it with the kanban column, which needed the identical four members with one word changed.)
- **The rule does not get stricter for completion, and the copy does.** `requiresConfirmation` asks
  whether anything irreversible happens, not how big a claim the action makes, so completing an
  empty list is still one tap. What differs is what the settle *asserts*: a cancellation records
  that work was abandoned, a completion records that it happened, and
  `GoalContributionSummary.progress` reads `completedTasks / totalTasks` over `filter(\.isDone)` —
  so bulk completion can move a goal's bar where bulk cancellation cannot, since a cancelled task
  stays in the denominator and out of the numerator. The completion sheet says so and names where
  the list goes; the destination is **not** symmetrical — an archived list stays on the Lists page
  under "Archived" one tap from Restore, a completed one leaves the page and is reopened from
  Settings › Lists.
- **Completion is a context-menu item on both surfaces and a swipe action on neither.**
  `iOSListRowSwipeActions` (in `iOSListSupportViews.swift`) still declares `archive` and nothing
  else, and a test fails if it grows a `complete`. A swipe is one flick with no beat to read
  anything in, and the confirmation deliberately does not appear for a list with nothing open — so a
  two-action tray would put "this work is finished" one mis-flick from "file it away". It is also
  not `role: .destructive`: finishing work is not destruction, and the sheet derives its own green
  from the outcome.
- **The count comes from the settle's own array.** `TaskContainerLifecycleService.remainingActiveTasks`
  is public for exactly this: a confirmation that counted by a second walk would eventually
  over-promise. An area rolls up its child projects, because a child keeps its own `status` and its
  tasks stay reachable after the parent is filed away. `forArea` / `forProject` take the outcome as
  a **required** argument rather than defaulting to `.cancelled`, so a completion cannot quietly
  promise the wrong verb over the right number.

Do **not** reach for `markDone` / `markCancelled` / `applyStatusCompletion` on either branch: they
spawn the next recurrence occurrence into the same area, project and section, so a wind-down routed
through them refills the container it just closed. That bites hardest on completion — the list
would read finished and immediately carry fresh open work.

## A Kanban Column Winds Down Too, And It Is An Action Rather Than A Draft

**T-247, the sibling of T-215 one level down.** macOS's `KanbanSectionColumnView` has called
`TaskContainerLifecycleService` on both column transitions all along — cancel on archive, done on
complete. iOS drew them as two `Toggle`s bound to a `CadenceSectionDraft` inside
`iOSSectionDraftRow`, committed with the rename and the colour on the list editor's Save, and no
task changed status. Same divergence as T-215, in a shape that could not have been fixed by adding
a call at the save.

- **A draft flag cannot host a truthful count.** The confirmation's number has to be the settle's
  own array (`remainingActiveTasks(in:area:project:)`), and a flag is committed arbitrarily later —
  after `reassignTasks` has re-pointed `AppTask.sectionName` for every renamed or removed column.
  Any number stated at flip time is a promise about a different array. That is the whole reason the
  toggle became an action rather than gaining a confirmation where it stood.
- **A draft flag also makes one gesture mean two things.** Flip and flip back and Save settles
  nothing; flip and Save cancels twelve tasks forever. `applyColumnWindDown` writes the flag *and*
  the settle to the model together, then brings the draft into step so the row reads truthfully and
  the sheet's own Save cannot write the flag back off.
- **Reversal is not a wind-down.** `ModelContext.reopenColumn` clears both flags and settles
  nothing, so it asks nothing — and it has to stay in the editor, because `Area.sectionNames`
  filters archived columns out and iOS has no "Show Archived" board mode, so the editor is the only
  surface where an archived column is visible at all.
- **No `!isCompleted` guard on the archive branch, unlike macOS.** macOS skips the cancel when the
  column is already complete. That is normally a no-op and is wrong the moment a task is added to a
  completed column: the count promised and the settle performed would disagree. The settle here
  always walks the array `summary` counted.
- **One decision point, one sheet.** `iOSListEditorSheet.requestColumnWindDown` asks
  `requiresConfirmation` once; `iOSWindDownConfirmationSheet` (in `iOSWindDownConfirmation.swift`)
  is the *same* sheet the list archive presents, parameterised by `iOSWindDownSubject`.
  `CadenceColumnWindDownSurfaceTests` sweeps the folder for `$draft.isArchived` /
  `$draft.isCompleted` — the `$` is what makes it the bug — and fails on either.

## A Focus Session Is Entered By Handing Over A Target, Not By Un-Guarding `FocusManager`

**T-266.** macOS starts a session from four places outside its Focus screen, all of them
`FocusManager.startFocus(…)` — whose `wantsNavToFocus` is what moves the shell. That singleton is
**still macOS-only and still correctly so**: iOS keeps its stopwatch in `iOSFocusView`'s own
`CadenceFocusTimerState`, so a cross-platform `FocusManager` would be a second timer authority with
nothing incrementing its `elapsed`. What iOS was missing is the *message*, and that is
`Shared/CadenceFocusHandoff.swift` — a `CadenceFocusHandoff` (a `CadenceFocusTarget` plus a token)
in a one-slot `CadenceFocusHandoffCenter`, the same shape as `CadenceDeepLinkManager` and injected
beside it.

Five things about the wiring that are easy to get wrong:

- **The shell routes, the screen adopts.** `iOSRootView.routeToFocus()` knows which tab owns Focus
  and nothing about clocks; `iOSFocusView.accept(_:)` knows about the clock and nothing about tabs.
  A root view that also decided what happens to a running session would be the thing T-242 rejected,
  one level up. The route reads `CadenceFocusHandoff.destination.compactRoute` rather than spelling
  "More, pushed", and it **guards on path equality** — replacing the stack with an equal-valued
  `NavigationPath` while the user is on Focus risks a fresh view identity, and a fresh
  `iOSFocusView` is a fresh `@State` clock, i.e. the running session vanishing at the exact moment
  the handoff was meant to be banked into it.
- **Both arrival routes, or the affordance works only sometimes.** `onAppear` covers the cold case
  (More was never visited, or was showing Goals); `onChange(of:pending?.id)` covers the warm one —
  the compact shell keeps every *visited* tab alive at zero opacity, so a Focus screen with a
  running session is usually still standing behind whatever tab you are on.
- **A handoff is not a play tap.** `CadenceFocusSupport.timerState(afterPlayTapOn:…)` *toggles*, so
  routing a handoff through it would **pause** the session whenever the subject asked for is the
  subject already running. `timerState(startRequestFor:…)` never pauses; a different subject still
  starts from zero, after `commitElapsed` has banked the outgoing one.
- **The commit is not re-spelled.** `accept(_:)` calls `select(_:)`, which already commits, and
  only adds the start on top. `FocusSessionSwitchCommitTests` counts
  `CadenceFocusSupport.commitElapsed(` in this file **exactly twice** for that reason — a third
  would mean a second body for "leaving a session".
- **The target is not a `UUID`, and the lookup is not the picker.** `pickItem(for:)` falls back to
  the whole store, because a handoff arrives from surfaces that have no idea what "ready" means: a
  task do-dated next month has a long-press menu like any other, and a lookup confined to
  `pickItems` would make Focus silently do nothing on exactly the task you went looking for.

**Leaving the screen now banks the session** (`.onDisappear` → `CadenceFocusSupport.endSession`),
which is what macOS calls `FocusManager.endSession()`. That was a pre-existing discard — the clock
is `@State` — and it is fixed here rather than filed because a route *into* Focus from a task row
makes backing straight out of it the common case. A tab switch is not a disappear in this shell.

**Where the affordances are, and why not elsewhere.** `iOSTaskRowContextMenu` for tasks: one entry
reaching Today, All Tasks, Inbox, list detail, the calendar inspector and the month agenda, because
`iOSTaskRow` is *the* task row. `iOSCalendarBundleDetailSheet` for blocks, because on iOS both the
board card and the timeline block open that sheet — a permanently visible ▶ on every block card is
clutter on the one surface whose job is reading a day at a glance, and a finger cannot reveal a
control without committing to it the way a pointer can. The **swipe tray was rejected**: a swipe is
for the two or three things you do to a task without looking, and this one changes screens.
`iOSTaskDetailSheet` has no Focus action yet — see T-273, and note that the sheet is presented by a
host, so its button has to dismiss while the shell routes underneath.

## Today's Rollover Notice Is Shared, And Only Half Of T-195 Is Done

**T-195, banner half.** Today's "leftover tasks are rolling over" notice was macOS-only in three
separate pieces, none of them AppKit-shaped: the `@AppStorage` key, an inline visibility predicate
on `TasksPanel`, and a withhold-while-showing method on `TasksPanelDerivedState` — over a mutation
(`SchedulingActions.rollOverTaskToToday`) that sat in `macOS/Services/` importing nothing
platform-specific. All four are now `Shared/CadenceTodayRolloverSupport.swift`,
`Shared/Components/CadenceTodayRolloverBanner.swift` and
`CadenceTaskMutationSupport.rollOverTaskToToday`, and **macOS was rewired onto them** rather than
left beside them.

Four things about the iOS wiring that are easy to get wrong:

- **The host decides, the list draws.** `iPadTodayView` holds the `@AppStorage` day key and builds
  an `iOSTodayRolloverNotice` (tasks + action, opted into whole — the same shape as
  `iOSBoardTaskCardBundleDrop`); `iOSTodayTaskSections` is the only thing that renders the banner,
  which is what makes "both widths show it" true by construction instead of by remembering. The
  iPad's compact pane forwards the value and decides nothing. A second
  `CadenceTodayRolloverBanner(` anywhere under this folder is a test failure.
- **One `UserDefaults` key, deliberately.** `CadenceTodayRolloverSupport.dismissedDateStorageKey`
  is the *same* key macOS reads. Dismissing is a statement about the day — the value is a
  `yyyy-MM-dd` key, so it expires at midnight without anything clearing it — not about the device.
  Two keys would mean the phone re-offered a roll the Mac had already performed, over tasks that
  are no longer past-do.
- **While the banner is up, the grouped list is deliberately short of the tasks it lists**, so
  `todayGroups` can legitimately return *nothing* on a day whose only open work is yesterday's.
  `iOSTodayTaskSections.isEmpty` therefore counts the notice as content; without that clause the
  list draws "nothing planned" directly under a banner listing four things to do.
- **The banner's bucket yields to a due date.** `pastDoTasks` excludes anything Overdue or Due
  Today already claims, because `CadenceTaskQuerySupport.todayGroups` hands those groups their
  tasks before `.pastDo` sees what is left. A predicate that disagreed would put a task in the
  banner and in a section under it at once.

**T-195 is closed, both halves.** Sections-due-today shipped in `2dcc948`: the summaries are
`CadenceTodayOverdueListSummary` / `CadenceTodayOverdueSectionSummary` in
`Shared/CadenceTodayOverdueSummarySupport.swift`, the cards are
`Shared/Components/CadenceTodayOverdueSummaryCards.swift`, and `iOSTodayTaskSections.swift` renders
both. This paragraph claimed the opposite — "zero references under this folder" — while the folder
held two. A scoped guide is supposed to be closer to the code than `CLAUDE.md`; when it is stale it
is worse than silence, because it is trusted more.

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
