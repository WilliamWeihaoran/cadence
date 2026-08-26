# Refactor Phases 4–6 — Audit Findings

## How to use this file

This is a standing worklist produced by a read-only audit of Cadence, taken around commit
`249b475`. It assumes you have no context beyond the repo itself. Nothing here has been fixed.

Three sections:

- **Phase 4 — tests that do not discriminate.** Tests that pass whether or not the code under
  them is correct. Each finding names the exact one-line mutation to *production* code that would
  leave the suite green, and the assertion that would fix it. Also: tests over helpers that have
  zero production callers (a test whose subject nothing calls is documentation, not coverage).
- **Phase 5 — structure and object design.** Two-sources-of-truth, god-ish derived-state
  objects, `*SupportViews` files split by size rather than responsibility, anaemic models.
- **Phase 6 — risk hotspots.** `SchedulePanel*` / `Timeline*` / EventKit. Separated into
  *genuinely fragile* (silently breaks when an unrelated edit violates an unwritten assumption)
  and *merely intricate* (hard to read, but self-checking or compiler-enforced).

Every finding has a stable ID, `file:line`, the concrete failure, a fix, and an effort estimate
(**S** ≈ under an hour, **M** ≈ half a day, **L** ≈ multi-day, needs a plan).

Line numbers were correct at the time of the audit — **verify each one before editing**. Several
files were being edited concurrently while this ran, notably `Models/HabitInsights.swift`,
`macOS/Views/GoalsSupportViews.swift`, `macOS/Views/HabitsSupportViews.swift`, and the
`Services/Markdown*Support.swift` / `macOS/Editor/` tree. Where a line number no longer matches,
the symbol name in each finding is the durable identifier; grep for that.

**Ground rules that constrain the fixes:**

- `Cadence/Models/` is compiled into **every** target — the app, `CadenceWidgets`, and
  `CadenceMCPServer`. `Cadence/Shared/` is **not**. Anything the widget or MCP target needs must
  live in `Models/`. This has already forced two helpers to move; several findings below are
  instances of the same pressure.
- Run tests scoped: `-only-testing:CadenceTests`. An unscoped run pulls in `CadenceUITests`,
  which cannot launch headless and aborts the whole run.
- Warning baseline is 3 (`MarkdownLinkSupport`, `SchedulingService`,
  `SettingsNotificationsSection`). Any increase is a regression.
- `Cadence/macOS/Editor/` was deliberately excluded from this audit.

**The dominant defect shape in this repo is one idea implemented more than once, then
drifting.** Already confirmed and consolidated before this audit: seven copies of `priorityRank`,
two `TaskDragPayload` declarations, four copies of a container-visibility predicate, three
habit-toggle implementations, two estimate pickers, three kanban cards. Findings marked
**⚠ ALREADY DIVERGED** are copies that disagree *today*, not ones that might someday.

---

# Phase 4 — Tests that do not discriminate

## P4-01 — `taskPriorityRank` is an eighth `priorityRank` the consolidation test does not cover ⚠ ALREADY DIVERGED

**Test:** `priorityRankIsOneOrderingSharedByEveryCaller`
— `CadenceTests/TrackingDeleteHelpersTests.swift:154`

**Claims to cover:** the doc comment says "It existed as six independent switches; the enum owns
it now, and **the surviving free-function spellings delegate**."

**Reality:** the test asserts the enum's own constants (`TaskPriority.high.rank >
TaskPriority.medium.rank`, …) and then exactly *one* forwarder,
`CadenceTaskQuerySupport.priorityRank`. Three hand-written `switch` copies survive and are not
asserted by anything:

- `Cadence/macOS/Views/TaskSortHelpers.swift:4` — `taskPriorityRank`, used at `:47-48` by
  `taskSortPrecedes`, which drives **every** macOS task sort
- `Cadence/iOS/iOSMarkdownAccessoryViews.swift:145`
- `Cadence/iOS/iOSMarkdownEditingSurface.swift:437`

**Mutation that keeps the suite green:** in `Cadence/macOS/Views/TaskSortHelpers.swift:7-8`, swap
the two lowest cases —

```swift
case .none: return 1
case .low:  return 0
```

`TrackingDeleteHelpersTests` never touches `taskPriorityRank`, and
`TaskSortHelperTests.prioritySortDescendingKeepsHigherPriorityFirstAndFallsBackByOrder`
(`CadenceTests/TaskSortHelperTests.swift:42`) only uses `none`/`medium`/`high`, so it never
compares `.low` against `.none`. Suite stays green; every macOS "sort by priority" now ranks a
low-priority task below an unprioritised one.

**Fix:** delete `taskPriorityRank` and call `priority.rank` at `TaskSortHelpers.swift:47-48`.
Delete the two `private func priorityRank` copies under `iOS/` (they are `private` inside view
structs, so they cannot be asserted from the test target — the only real fix is deletion).
Then extend the test to iterate every *public* spelling:

```swift
for priority in TaskPriority.allCases {
    #expect(CadenceTaskQuerySupport.priorityRank(priority) == priority.rank)
    #expect(CadenceCalendarPlanningSupport.priorityRank(priority) == priority.rank) // needs internal access
}
```

**Effort: S.**

---

## P4-02 — `classifyTasksByDate` has zero production callers; the copy production uses is untested

**Test:** `classifyTasksByDatePrioritizesDueBucketsOverScheduledToday`
— `CadenceTests/TaskSortHelperTests.swift:59`

**Subject:** `classifyTasksByDate` / `TaskDateBuckets` at
`Cadence/macOS/Views/TaskSortHelpers.swift:62-96`.

**Reality:** `classifyTasksByDate` has **zero** references anywhere in `Cadence/`,
`CadenceWidgets/`, or `CadenceMCPServer/` outside its own declaration. The bucketing production
actually runs is `CadenceTaskQuerySupport.dateBuckets` at
`Cadence/Shared/CadenceTaskQuerySupport.swift:272` (feeding `dateDisplayGroups` at `:115`),
returning `CadenceTaskDateBuckets` at `Cadence/Shared/CadenceTaskPlanningSupport.swift:68`. The
two implementations are line-for-line identical, down to the two-pass structure and the variable
names — they differ only in the struct name. `dateBuckets` is `private`, so the test cannot reach
it.

**Mutation that keeps the suite green:** at
`Cadence/Shared/CadenceTaskQuerySupport.swift:280`, change `else if task.dueDate == todayKey` to
`else if false`. Today's "Due Today" group empties out. The suite stays green, because the only
test of this logic tests the dead twin.

**Fix:** delete `TaskDateBuckets` and `classifyTasksByDate` from `TaskSortHelpers.swift`; make
`CadenceTaskQuerySupport.dateBuckets` internal (not `private`) and repoint the test at it.
Assert through the public surface as well:

```swift
let groups = CadenceTaskQuerySupport.dateDisplayGroups(from: tasks, todayKey: todayKey)
#expect(groups.first { $0.id == "due-today" }?.tasks.map(\.id) == [dueTodayAndScheduled.id])
```

**Effort: S.** (See also **P5-06**, the six-way duplication this is one arm of.)

---

## P4-03 — The near-midnight drop test asserts a bound its own input already satisfies

**Test:** `droppingTaskNearMidnightOnANewDayClampsStartMinuteWithoutCrossingIntoTheFollowingDay`
— `CadenceTests/TimelineMetricsTests.swift:325`

**Claims to cover:** that `SchedulingActions.dropTask` clamps a drop near the bottom of a day
column to a valid in-range minute for *that* day.

**Reality:** the test passes `startMin: 1438` and asserts `task.scheduledStartMin < 1440` and
`>= 0`. 1438 already satisfies both. The clamp
(`Cadence/macOS/Services/SchedulingService.swift:254-256`,
`min(max(dayStartMin, startMin), dayEndMin - minimumBundleDuration)`) actually produces 1435 —
which the test never checks.

**Mutation that keeps the suite green:** replace the body of `clampedStartMin` at
`Cadence/macOS/Services/SchedulingService.swift:255` with `startMin`. Every clamp in the
scheduling layer disappears; the suite stays green.

**Fix:** feed it an out-of-range value and assert the exact clamped result:

```swift
SchedulingActions.dropTask(task, to: "2026-06-02", startMin: 1_600)
#expect(task.scheduledStartMin == 1_435)  // dayEndMin - minimumBundleDuration
SchedulingActions.dropTask(task, to: "2026-06-02", startMin: -50)
#expect(task.scheduledStartMin == 0)
```

**Effort: S.**

---

## P4-04 — The `endHovering` guard test asserts synchronously and is satisfied by a *different* guard

**Test:** `endHoveringIgnoresATaskThatIsNoLongerTheHoveredOne`
— `CadenceTests/HoveredTaskManagerTests.swift:72`

**Claims to cover:** the guard in `HoveredTaskManager.endHovering(_:)` that ignores a stale
`endHovering` call for a task that is no longer hovered.

**Reality:** `endHovering` (`Cadence/macOS/Services/HoveredTaskManager.swift:53-67`) does not
mutate anything synchronously — it only schedules a `DispatchWorkItem` for `now + 0.08`. The test
asserts `manager.hoveredTask?.id == b.id` immediately, so it returns before the work item could
ever fire. Worse, the work item carries its **own** identity guard
(`guard self.hoveredTask?.id == task.id`, `:57`), so even after the delay the outer guard's
removal is unobservable.

**Mutation that keeps the suite green:** delete
`Cadence/macOS/Services/HoveredTaskManager.swift:54` — `guard hoveredTask?.id == task.id else {
return }`. No test in the suite changes behaviour.

**Fix:** the outer guard is currently *dead* — its only distinguishable effect would be
cancelling a pending clear belonging to another task. Either delete it (and say so), or make it
observable and assert it:

```swift
manager.beginHovering(a, source: .list)
manager.endHovering(a)                 // schedules a's clear
manager.beginHovering(b, source: .list) // cancels it, b is now hovered
manager.endHovering(a)                 // stale: must NOT schedule a clear for b
try await Task.sleep(nanoseconds: 160_000_000)
#expect(manager.hoveredTask?.id == b.id)
```

Then remove the redundant inner guard so exactly one of the two is load-bearing.
**Effort: S.**

---

## P4-05 — `timelineDayIndexForMonthViewReturn` has zero production callers; the real return path is a second copy

**Test:** `monthToTimelineReturnUsesTheDayTheVisibleBlockWasShowing`
— `CadenceTests/CadenceTests.swift:261`

**Subject:** `CalendarPageStateSupport.timelineDayIndexForMonthViewReturn` at
`Cadence/macOS/Views/CalendarPageStateSupport.swift:171`.

**Reality:** zero references outside its own declaration. Its doc comment
(`CalendarPageStateSupport.swift:168-170`) reads: *"Day-index form of `dateKeyForVisibleMonth`,
expressed through it rather than beside it — a second copy of 'which day does this block stand
for' is a second chance to disagree with the grid."* The second copy **is** beside it: production
leaves the month grid through `CalendarPageDataSupport.handleViewModeChange`
(`Cadence/macOS/Views/CalendarPageDataSupport.swift:60-73`), which calls `dateKeyForVisibleMonth`
and `timelineDayIndex` inline.

**Mutation that keeps this test green:** at `Cadence/macOS/Views/CalendarPageDataSupport.swift:72`
change `visibleTimelineDayIndex = targetDay` to `visibleTimelineDayIndex = todayDayIdx`. Leaving
the month view now always returns to today rather than to the month you were looking at. This
test stays green. (`calendarViewModeChangeCommitsVisibleTimelineDayBeforeOpeningMonth`,
`CadenceTests.swift:349`, only exercises `.week → .month`, not the return.)

**Fix:** delete `timelineDayIndexForMonthViewReturn`, and add a `.month → .week` case to the
`handleViewModeChange` test:

```swift
var visibleTimelineDayIndex: Int? = nil
CalendarPageDataSupport.handleViewModeChange(oldMode: .month, newMode: .week, visibleMonthIdx: &60, ...)
#expect(visibleTimelineDayIndex == 122)
#expect(anchorDateKey == "2026-05-03")
```

Alternatively keep the helper and make `handleViewModeChange` call it — that was clearly the
intent. **Effort: S.**

---

## P4-06 — `boardDateByMovingMonth` tests navigation the Calendar Board does not have

**Test:** `calendarBoardMonthNavigationClampsToValidDay` — `CadenceTests/CadenceTests.swift:388`

**Subject:** `CalendarPageStateSupport.boardDateByMovingMonth` at
`Cadence/macOS/Views/CalendarPageStateSupport.swift:153`. Zero production callers.

**Reality:** the Calendar Board's back/forward controls call
`CalendarPageView.moveBoardWindow(by:)` (`Cadence/macOS/Views/CalendarPageView.swift:257-264`),
which uses `CalendarBoardPlannerSupport.dateByMovingWindow`
(`Cadence/Shared/CadenceCalendarPlanningSupport.swift:170`) — a **day**-based window shift
(`delta * visibleDayCount`), not a month shift. `boardDateByMovingMonth` is a leftover from an
earlier board design. `dateByMovingWindow` and `canMoveWindow` have **no tests at all**.

**Fix:** delete `boardDateByMovingMonth` and its test. Write the test the board actually needs:

```swift
#expect(CalendarBoardPlannerSupport.dateByMovingWindow(anchor, by: 1, calendar: cal)
        == cal.date(byAdding: .day, value: CalendarBoardPlannerSupport.visibleDayCount, to: anchor))
#expect(CalendarBoardPlannerSupport.canMoveWindow(from: today, by: -1, notBefore: today, calendar: cal) == false)
```

**Effort: S.**

---

## P4-07 — The non-breaking-space test asserts the canonical label while two live renderers use a plain space ⚠ ALREADY DIVERGED

**Test:** `durationLabelsUseANonBreakingSpaceBetweenHoursAndMinutes`
— `CadenceTests/DateFormatterSupportTests.swift:60`

**Claims to cover:** that duration labels never contain a breakable space, because they are drawn
in hard-clipped fixed-width chrome where a wrap turns "1h 30m" into a silently wrong "1h".

**Reality:** the test asserts `CadenceTaskPresentationSupport.estimateLabel` and
`TimeFormatters.durationLabel`. Two *other* production duration renderers ignore both and use an
ordinary space today:

- `Cadence/macOS/Views/TimelineEventBlockSupportViews.swift:71` — `return m == 0 ? "\(h)h" :
  "\(h)h \(m)m"`, drawn inside a timeline event block, which is exactly the clipped narrow
  container the rule exists for
- `Cadence/Models/GoalContributionSummary.swift:47` — `focusLabel`, `"\(hours)h \(minutes)m"`

**Mutation not required** — the defect is already shipped. The test's subject is not the code
that breaks.

**Fix:** route both through `CadenceTaskPresentationSupport.estimateLabel(minutes:)` (adding an
`emptyPlaceholder:` parameter so `TimelineEventBlockSupportViews` keeps its `–` sentinel), then
assert the joined surface:

```swift
#expect(!GoalContributionSummary(...).focusLabel.contains(" "))
```

**Effort: S.** See **P5-05** for the full five-way duplication.

---

## P4-08 — The habit widget intent's refresh side effects are untested because the tests call a shim

**Tests:** `toggleHabitCompletionIntentLogsAndRemovesTodayCheckIn`
(`CadenceTests/WidgetSupportTests.swift:298`) and
`habitWidgetSnapshotPrefersRecentCompletionOverride`
(`CadenceTests/WidgetSupportTests.swift:347`).

**Reality:** `ToggleHabitCompletionIntent.toggleHabitCompletion`
(`Cadence/Services/CadenceWidgetIntents.swift:157`) is a `@discardableResult` shim with **zero
production callers** — it throws away `habitID` and `isDoneToday`. `perform()`
(`Cadence/Services/CadenceWidgetIntents.swift:143-153`) calls the richer
`toggleHabitCompletionResult` and then does the part that matters:
`CadenceWidgetRefreshCenter.markHabitCompletion(habitID, isDoneToday:)` followed by
`reloadAllWidgets(force: true)`. That optimistic override is precisely what the *other* test at
`:347` exists to support — and nothing ties the two together.

**Mutation that keeps the suite green:** delete the
`CadenceWidgetRefreshCenter.markHabitCompletion(...)` call at
`Cadence/Services/CadenceWidgetIntents.swift:146-149`. Tapping a habit in the widget stops
showing the check-in until the next full timeline reload. Suite green.

**Fix:** make `toggleHabitCompletionResult` internal, delete the shim, and assert the join with an
injected `UserDefaults` suite (the pattern `WidgetSupportTests.swift:35-55` already uses):

```swift
let result = try ToggleHabitCompletionIntent.toggleHabitCompletionResult(habitID: ..., in: ctx)
CadenceWidgetRefreshCenter.markHabitCompletion(result.habitID!, isDoneToday: result.isDoneToday, userDefaults: defaults)
#expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now, userDefaults: defaults)[habit.id] == true)
```

Better still: extract the mark-then-reload block into a testable
`CadenceWidgetIntents.applyHabitToggleSideEffects(_:)` and assert `perform()`'s contract directly.
**Effort: S–M.**

---

## P4-09 — `HabitHeatmapGrid.dateKeys` has zero production callers

**Tests:** `heatmapGridRunsThroughTodayOnEveryWeekday`
(`CadenceTests/HabitInsightsAuditTests.swift:321`) and
`heatmapGridStopsAtTheEndOfTheCurrentWeek` (`:340`).

**Subject:** `HabitHeatmap.HabitHeatmapGrid.dateKeys` at
`Cadence/macOS/Views/HabitsSupportViews.swift:374`. Zero production callers — the view body reads
`cells(...)` at `:400`.

**Severity: low.** `dateKeys` is `cells(...).map(\.key)`, so the tests *do* transitively cover the
rendered sequence, and the file's own doc comment at `:362-364` records that this exact "no
production caller" problem was already fixed once. But `dateKeys` is now dead production code
kept alive only by tests, and the comment claims a discipline the file no longer follows.

**Uncovered next to it:** the month-label rail (`months`, `HabitsSupportViews.swift:385-398`)
re-derives week starts from `startDate` independently of `cells`, and nothing asserts that the
label column indices line up with the cell columns.

**Fix:** delete `dateKeys`; have the tests call `cells(...).map(\.key)`. Add one assertion that
the month labels index the same grid:

```swift
let cells = HabitHeatmap.HabitHeatmapGrid.cells(weeks: 52, today: today, calendar: cal)
// every month label's weekCol must name the month of cells[weekCol * 7]
```

**Effort: S.**

---

## P4-10 — The AI provider test asserts its own input back

**Test:** `providerBuildsResponsesRequestWithAuthModelAndStructuredOutput`
— `CadenceTests/AITests.swift:49`

**Reality:** the test constructs the `OpenAIResponseRequest` itself — including `model:
"gpt-test"` and `text: .init(format: .taskDraftsSchema)` — and hands it to
`AIProvider.makeURLRequest`, which only sets URL/method/headers and JSON-encodes the body it was
given (`Cadence/Services/AI/AIProvider.swift:154-161`). So `#expect(json["model"] as? String ==
"gpt-test")` proves `JSONEncoder` round-trips a literal, and the three `format[...]` assertions
read back `OpenAITextFormat.taskDraftsSchema`'s own constants. Only the two header assertions test
anything. The code that *assembles* the body is untouched.

**Mutation that keeps the suite green:** at `Cadence/Services/AI/AIProvider.swift:140`, change
`text: .init(format: .taskDraftsSchema),` to `text: nil,`. Structured JSON output is silently
disabled for every real "extract tasks" call. Equally, `Cadence/Services/AI/AIProvider.swift:130`
`model: model,` → `model: "gpt-4o-mini",` hard-codes the wrong model while `manager.model` is
still saved and displayed.

**Fix:** `session` and `endpoint` are already injectable
(`Cadence/Services/AI/AIProvider.swift:101-106`). Stub the session, call `extractTasks`, and
assert what was actually sent:

```swift
_ = try? await provider.extractTasks(from: AITextNoteContext(title: "T", content: "C", containerName: nil))
let sent = try #require(JSONSerialization.jsonObject(with: stub.lastBody!) as? [String: Any])
#expect(sent["model"] as? String == "gpt-test")
#expect(((sent["text"] as? [String: Any])?["format"] as? [String: Any])?["name"] as? String == "cadence_task_drafts")
```

**Effort: M** (needs a URLProtocol stub).

---

## P4-11 — `MarkdownQuoteSupport.continuation` is a dead reimplementation of the live Return handler

**Test:** `continuesListsInsideQuoteLines` — `CadenceTests/MarkdownQuoteSupportTests.swift:31`

**Reality:** `MarkdownQuoteSupport.continuation(after:)`
(`Cadence/Services/MarkdownQuoteSupport.swift:44`) has **zero production callers** — the only
references to `MarkdownQuoteSupport.` in `Cadence/` are `lineInfo`. The live editor path is
`MarkdownLineBreakSupport.quoteContinuationPrefix`
(`Cadence/Services/MarkdownLineBreakSupport.swift:73`), a separate reimplementation.
`MarkdownLineBreakSupportTests.continuesQuoteLinesAndQuotedLists` covers only `"> Keep going"`
and `"> - item"`; the quoted-**ordered** and quoted-**checklist** cases exist only on the dead
copy.

**Mutation that keeps the suite green:** at
`Cadence/Services/MarkdownLineBreakSupport.swift:81`, change
`return quotePrefix + continuedListPrefix(for: prefixMatch)` to
`return quotePrefix + prefixMatch.prefix`. For `.dash` the two are identical (`"- "`), so the live
test still passes — but `"> 1. first"` now repeats `1.` forever instead of advancing, and
`"> - [ ] task"` emits `- [ ] ` instead of the canonical `○ `.

**Fix:** delete `MarkdownQuoteSupport.continuation` and move its cases onto the live path:

```swift
let quotedOrdered = try #require(MarkdownLineBreakSupport.mutation(
    in: "> 1. first", selection: NSRange(location: 10, length: 0)))
#expect(quotedOrdered.replacement == "\n> 2. ")
let quotedTodo = try #require(MarkdownLineBreakSupport.mutation(
    in: "> - [ ] task", selection: NSRange(location: 12, length: 0)))
#expect(quotedTodo.replacement == "\n> ○ ")
```

**Effort: S.**

---

## P4-12 — The template-override test never enters the branch it names

**Test:** `matchingDefaultValuesDoNotPersistAnOverride`
— `CadenceTests/NoteTemplateLibraryTests.swift:40`

**Claims to cover:** editing a template back to its default values must not persist an override.

**Reality:** the test calls `setOverride(…, in: "")` — starting from *no* overrides. The
`if normalized == default` branch calls `overrides.removeValue(forKey: id)` on an already-empty
dictionary, so the assertion `overrides(from: raw).isEmpty` is satisfied purely by not entering
the `else` branch. The removal is never exercised. The real case — user customizes, then types
the defaults back — is untested; `resetOverrideRestoresDefaultTemplate` covers `resetOverride`,
a different function.

**Mutation that keeps the suite green:** delete
`Cadence/Services/MarkdownNoteSupport.swift:66` (`overrides.removeValue(forKey: id)`). A user who
edits a template back to its defaults keeps a stale override forever and `isCustomized` keeps
reporting `true`.

**Fix:** start from a customized state.

```swift
let customized = NoteTemplateLibrary.setOverride(
    for: defaultTemplate.id, title: "Custom", subtitle: "Custom", body: "# Custom", in: "")
#expect(NoteTemplateLibrary.overrides(from: customized)[defaultTemplate.id] != nil)
let restored = NoteTemplateLibrary.setOverride(
    for: defaultTemplate.id, title: defaultTemplate.title,
    subtitle: defaultTemplate.subtitle, body: defaultTemplate.body, in: customized)
#expect(NoteTemplateLibrary.overrides(from: restored).isEmpty)
```

**Effort: S.**

---

## P4-13 — The synchronous-restyle regression test greps a string that appears twice

**Test:** `markdownStylingRestylesSynchronouslyOnEveryKeystroke`
— `CadenceTests/NoteEditorPerformanceRegressionTests.swift:28`

**Reality:** the positive assertion is
`#expect(source.contains("applyStyling(to: textView, in: textView.enclosingScrollView)"))`. That
exact string appears **twice** in
`Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift` — at `:1205` inside
`textDidChange` and at `:1231` inside `textDidEndEditing`. The three negative assertions only
prove the old debounce identifiers are gone, which is also true if styling stops running on
keystrokes entirely.

**Mutation that keeps the suite green:** delete
`Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift:1205`. Typing produces plain
unstyled text until the field loses focus — the exact regression this test is named for.

**Fix:** replace the grep with a behavioural check (`MarkdownStylist.apply` is already driven
directly in `MarkdownHiddenRangeSupportTests`):

```swift
let textView = NSTextView(); textView.string = "**bold**"
coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
#expect(textView.textStorage?.attribute(.cadenceMarkdownHidden, at: 0, effectiveRange: nil) as? Bool == true)
```

If a source grep must be kept, at minimum pin the count to 2.

> `Cadence/macOS/Editor/` was out of scope for the Phase 6 review and is under active work. The
> *test* is in scope and can be fixed independently; coordinate the production line number before
> editing.

**Effort: S–M.**

---

## P4-14 — The PDF export test is satisfied by a PDF containing no image

**Test:** `notePDFExportRendersMarkdownImages`
— `CadenceTests/MarkdownImageAssetServiceTests.swift:131`

**Reality:** the only assertions are `data.starts(with: "%PDF")` and `data.count > 1_000`.
Neither is image-specific. `renderedPDFData` renders the note text through `MarkdownStylist` over
an offscreen `NSTextView` with an opaque background and embedded font resources — a text-only
page is comfortably over 1 KB, and the *un*-rendered variant is longer, because the raw
`![Preview](cadence-image://…)` line stays visible. The asset the test creates is never
distinguished from its absence.

**Mutation that keeps the suite green:** at
`Cadence/macOS/Services/NoteExportService.swift:120`, change
`textView.markdownImageAssets = Dictionary(uniqueKeysWithValues: …)` to
`textView.markdownImageAssets = [:]`. Every exported PDF loses its images.

**Fix:** compare against the no-asset render.

```swift
let withoutImage = try #require(NoteExportService.renderedPDFData(content: content, imageAssets: []))
#expect(data.count > withoutImage.count * 2)
```

**Effort: S.**

---

## P4-15 — The "clickable but invisible chip" sweep is unfalsifiable by construction

**Test:** `droppedChipsAreNeitherDrawnNorHitTestable`
— `CadenceTests/MarkdownTaskEmbedChipLayoutTests.swift:121`

**Claims to cover:** "every point that hit-tests to a field has to belong to a chip the card
actually drew, so nothing is clickable-but-invisible."

**Reality:** `chipRects` (`Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift:80-84`) and
`fieldHit` (`:66-72`) both call `fieldRects(task:cardRect:chips: displayChips(for: task))` with
identical arguments, and `fieldRects` (`:186`) is pure. `renderedFields` and the hittable set are
therefore the same value *by construction* — the production doc comment at `:216-218` states this
as a structural invariant. The test never touches `drawCard`, which is the only place "drawn" can
diverge from "hittable".

**Mutation that keeps the suite green:** at
`Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift:119`, change
`for chipRect in layout.chips {` to `for chipRect in layout.chips.dropLast() {`. The card draws
one fewer chip than it hit-tests — precisely the bug the comment names.

**Fix:** assert against actually-drawn output (render the card into an `NSImage` and check the
dropped chip's rect is empty), or at minimum pin the drop *set* so a ranking change is visible:

```swift
#expect(Set(fields(for: task, textContainerWidth: 240))
        == Set([.dueDate, .container, .scheduledDate, .priority, .status]))
```

Same `Editor/` caveat as **P4-13**. **Effort: S** for the set assertion, **M** for the pixel check.

---

## P4-16 — The image display-width test asserts a bound its input already satisfies

**Test:** `createsImageAssetWithMetadataAndDisplayWidth`
— `CadenceTests/MarkdownImageAssetServiceTests.swift:98`

**Reality:** the input is 800 px wide and the assertion is
`asset.displayWidth == Double(MarkdownImageAssetService.defaultDisplayWidth)` — it re-reads the
production constant, and the input already sits on the far side of both clamps. No test anywhere
passes an image narrower than `defaultDisplayWidth` (520) or `minDisplayWidth` (120).

**Mutation that keeps the suite green:** at
`Cadence/Services/MarkdownImageAssetService.swift:93`, change
`let displayWidth = min(defaultDisplayWidth, normalized.pixelSize.width)` to
`let displayWidth = defaultDisplayWidth`. Every narrow image — a 200 px icon, a screenshot crop —
is now upscaled to 520 pt in the editor. The `max(minDisplayWidth, …)` floor at `:101` is
likewise deletable.

**Fix:**

```swift
let narrow = try #require(MarkdownImageAssetService.createAsset(
    from: testImage(size: CGSize(width: 200, height: 100)), in: context))
#expect(narrow.displayWidth == 200)
let tiny = try #require(MarkdownImageAssetService.createAsset(
    from: testImage(size: CGSize(width: 40, height: 40)), in: context))
#expect(tiny.displayWidth == 120)
```

and change line 115 to the literal `#expect(asset.displayWidth == 520)`. **Effort: S.**

---

## P4-17 — A locale-dependent assertion, on a formatter that forgot to pin its locale

**Test:** `monthGroupingFormsRunsOverTheFilteredList`
— `CadenceTests/NotesListVisibilityTests.swift:225`

`#expect(groups[0].title == "AUGUST 2026")` runs through `NotesListGrouping.monthTitle` →
`DateFormatters.monthYear` (`Cadence/Shared/DateFormatters.swift:23-27`), which sets `dateFormat`
but **no `locale`** — unlike `DateFormatters.ymd` two declarations above, which pins
`en_US_POSIX`. On any non-English host the test fails against a *correct* implementation
("AOÛT 2026"). It is also the only assertion covering `monthTitle`, so it is simultaneously
host-dependent and the sole gate on that function.

**Fix:** pin the locale in production (`f.locale = Locale(identifier: "en_US_POSIX")` at
`Cadence/Shared/DateFormatters.swift:24`), which is the house rule `ymd` already follows, and keep
the assertion. This belongs with `CrossPlatformParityTests`, whose whole premise is that
"invisible on the author's machine" is this repo's highest-yield bug category. **Effort: S.**

---

## P4-18 — Miscellaneous non-discriminating assertions

| ID | Test | Problem |
|---|---|---|
| P4-18a | `example()` — `CadenceTests/CadenceTests.swift:19` | Empty Xcode-template test body. Delete. **S** |
| P4-18b | `barFrameHandlesRangeFarOutsideVisibleWindowWithoutCrashing` — `CadenceTests/GoalProgressAuditTests.swift:309` | All four assertions (`width > 0`, `x > 0`, `.isFinite`) are structurally satisfied by a 30-day span at `dayWidth: 48` starting after `rangeStart`. Nothing about "far outside the visible window" is asserted. If windowing/clamping is expected, assert the clamped `x`; if not, the test name is wrong. **S** |
| P4-18c | `pixelConversionFunctionsHandleUnscheduledAndOutOfRangeMinutesWithoutCrashing` — `CadenceTests/TimelineMetricsTests.swift:255` | `frame.width >= 0` and `.isFinite` cannot fail for any plausible implementation. The interesting question — what `yOffset(for: -1)` *should* be — is unasserted, and **P6-16** shows `-1` reaching the canvas is a live hazard. Assert exact values. **S** |
| P4-18d | `GoalTimelineDateMathTests` helper `date(_:)` — `CadenceTests/GoalTimelineDateMathTests.swift:109` | `DateFormatters.date(from: key) ?? Date()` silently substitutes *now* on a parse failure, so a broken parser reads as a passing test with nonsense inputs. Use `try #require`. Same pattern at `HabitInsightsAuditTests.swift:42, 53, 67`. **S** |

---

## P4-19 — Untested surfaces where one cheap assertion pays for itself

| ID | Surface | Why it matters |
|---|---|---|
| P4-19a | `Habit.last30DayCompletionRate` — `Cadence/Models/HabitInsights.swift:66` | Rendered on the macOS habit detail (`HabitsSupportViews.swift:232`), the iOS detail (`iOSFeatureDetailViews.swift:232`), and averaged across all habits on the habits page (`HabitsView.swift:112`). **Zero tests.** It walks `cal.date(byAdding: .day, value: -i, to: startOfToday)` with a hard-wired `Calendar.current` and no injectable calendar — the exact wall-clock-preserving drift that `bestStreakSurvivesAMidnightDSTTransition` (`HabitInsightsAuditTests.swift:147`) was written to catch on the streak walk. Add a `calendar:` parameter and reuse the Santiago fixture. **S** |
| P4-19b | `Habit.last7DayStates` — `Cadence/Models/HabitInsights.swift:56` | Drives the iOS 7-day dot strip (`iOSFeatureDetailViews.swift:236`). Zero tests; same `Calendar.current` problem; also `compactMap` silently *shortens* the array on a nil date, so the strip can render 6 dots. Assert `count == 7` and the today-last ordering. **S** |
| P4-19c | `Habit.frequencyShortLabel` — `Cadence/Models/HabitInsights.swift:35` | Feeds the habit widget (`CadenceHabitWidgetSupport.swift:168`). Zero tests. `.daysOfWeek` with an empty `frequencyDays` renders `"0x/week"` while `frequencySummary` renders `"Custom days"` for the same habit. **S** |
| P4-19d | Canonical-note-key agreement | `DataIntegrityRepairService.canonicalNoteKey` (`:452`) and `NoteMigrationService.canonicalKey` (`:430`) already disagree (see **P5-01**). `DataIntegrityRepairServiceTests` covers only the repair side. One test that runs a migration and then a repair over the same dateless daily notes and asserts a stable note count would have caught it. **S** |
| P4-19e | `CalendarBoardPlannerSupport.dateByMovingWindow` / `canMoveWindow` — `Cadence/Shared/CadenceCalendarPlanningSupport.swift:170, 177` | The board's only navigation. Zero tests (the test that looks like it covers this covers a dead helper — **P4-06**). **S** |
| P4-19f | `CalendarPageDataSupport.handleViewModeChange` `.month → .week` branch — `Cadence/macOS/Views/CalendarPageDataSupport.swift:60-73` | Only the `.week → .month` direction is tested. See **P4-05**. **S** |
| P4-19g | `AppTask.calendarEventID` clearing invariant | `docs/CLAUDE_REFERENCE.md` documents that nothing may ever write this field a non-empty value, and lists seven `SchedulingService` clear sites plus `CalendarLinkedTaskSupport`. Nothing asserts it. One test — create a task through every scheduling entry point and assert `calendarEventID.isEmpty` — pins a documented invariant currently held only by convention. **S** |
| P4-19h | `MarkdownImageAssetService.setDisplayWidth(_:for:in:)` — `Cadence/Services/MarkdownImageAssetService.swift:178` | The `min(max(width, minDisplayWidth), maxDisplayWidth)` clamp has no test at all, and it is the drag-to-resize handler (`MarkdownEditorInteractionSupport.swift:549`). One line: `setDisplayWidth(5_000, for: asset.id, in: [asset]); #expect(asset.displayWidth == 1_200)`. **S** |
| P4-19i | `NoteMigrationHealthReport.issueCount` — `Cadence/Services/NoteMigrationService.swift:44-50` | The sum omits `meetingNoteMissingCalendarIDCount`, so a store whose only defect is meeting notes missing their calendar ID reports `issueCount == 0` — "healthy" — to `CadenceReadService.swift:813`. `healthCheckReportsLegacyGapsAndBadRelationships` asserts both figures side by side, blessing the gap. Build a store with only that defect and assert `issueCount == 1`. **S** |
| P4-19j | `NoteMigrationService.migrateAndRecordFailure(in:source:saveChanges:)` — `Cadence/Services/NoteMigrationService.swift:100` | Completely untested, including the `catch { return lastReport() }` path — and it is the app's startup entry point. **S–M** |
| P4-19k | `NotesListVisibility.notepadNotes` tie-break — `Cadence/macOS/Views/NotesListVisibilitySupport.swift:86` (`$0.id.uuidString > $1.id.uuidString`) | The whole point is deterministic order for notes created in the same instant; no test constructs two notes with equal `createdAt`. The mirrored `<` tie-break at `NoteMigrationService.swift:405` has the same gap — and they sort in *opposite* directions, which nothing checks. **S** |
| P4-19l | `MarkdownImageAssetService.unescapedAltText(_:)` — `Cadence/Services/MarkdownImageAssetService.swift:208` | Public, called directly from `MarkdownInlinePreviewSupport.swift:188`, tested only indirectly through `references(in:)`. One line. **S** |
| P4-19m | `NoteTemplateLibrary.isCustomized` / `noteKinds(containing:)` / `editableTemplates(overridesRaw:)` — `Cadence/Services/MarkdownNoteSupport.swift:79, 87, 33` | All three back the template-settings UI; none has any test. **S** |

---

# Phase 5 — Structure and object design

## P5-01 — Two canonical-note-key functions that disagree ⚠ ALREADY DIVERGED

- `Cadence/Services/DataIntegrityRepairService.swift:452` — `canonicalNoteKey(for:)`
- `Cadence/Services/NoteMigrationService.swift:430` — `canonicalKey(for:)`

| case | RepairService | MigrationService |
|---|---|---|
| `.daily` with empty/whitespace `dateKey` | trims, falls back to `"daily-note:<uuid>"` (unique per note) | `"daily:"` — every dateless daily note collides |
| `.weekly` with empty `weekKey` | `"weekly-note:<uuid>"` | `"weekly:"` — same collision |
| whitespace-padded key | trimmed, matches clean keys | not trimmed; `"daily: 2026-08-11"` ≠ `"daily:2026-08-11"` |
| `.meeting` with empty `calendarEventID` | trims, then per-uuid fallback | `isEmpty` check only, no trim |

`NoteMigrationService.canonicalKeys` (`:138`, `:313`) therefore treats all dateless daily notes as
one key and skips real notes as "already migrated"; the repair pass then sees them as distinct
and refuses to merge. Two passes over the same rows reach opposite conclusions.

**Fix:** one `Note.canonicalKey` on the model. `Models/` is compiled by every target and both
services already import it. Delete both private copies. **Effort: S.**

## P5-02 — `overdueCount` / `regularCount` ignores `isDone` in the list-detail copy ⚠ ALREADY DIVERGED

- `Cadence/macOS/Views/TasksPanelSupport.swift:193, 198` — **authoritative**
  (`!$0.isDone && !$0.dueDate.isEmpty && $0.dueDate < todayKey`)
- `Cadence/macOS/Views/TasksPanel.swift:736, 740` — forwards ✓
- `Cadence/macOS/Views/AllTasksListView.swift:218, 222` — forwards ✓
- `Cadence/macOS/Views/ListDetailComponents.swift:175, 180` — **own body, no `isDone` filter**

A completed task with a past due date counts as overdue in list detail and not in Today. The same
list reports two different numbers depending on which screen you are on.

**Fix:** forward to `TasksPanelSupport`. **Effort: S.**

## P5-03 — A third `statusColor(TaskStatus)` with different colours ⚠ ALREADY DIVERGED

- `Cadence/Shared/Theme.swift:85` — authoritative
- `Cadence/Shared/CadenceTaskPresentationSupport.swift:72` — forwards ✓
- `Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift:407` — own switch:
  `.todo → Theme.dim` (should be `muted`), `.cancelled → Theme.dim.opacity(0.7)` (should be `dim`)

The task-embed status picker paints two of four statuses in colours no other surface uses. (A
fourth, `NSColor`-flavoured copy lives at `macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift:272`
— out of audit scope, same idea.)

**Fix:** delete the popover copy, call `Theme.statusColor`. **Effort: S.**

## P5-04 — Six `isOverdue` predicates, three of which omit `isDone` ⚠ ALREADY DIVERGED

- `Cadence/Shared/CadenceFocusPlanningSupport.swift:58` — `CadenceFocusSupport.isOverdue(dueDateKey:todayKey:)`, does **not** consider `isDone`; every caller must remember `&& !task.isDone` (they do)
- `Cadence/macOS/Views/KanbanCardComputedSupport.swift:5` — guards `!task.isDone`
- `Cadence/macOS/Views/TasksPanelComponents.swift:398` — byte-identical re-implementation of the Kanban one (as are `isOverdo` at `:403` and `isDoToday` at `:408`, duplicating `KanbanCardComputedSupport.swift:10` and `:15`)
- `Cadence/iOS/iOSTaskViews.swift:292` — **no `isDone` guard and no caller-side guard**: a completed iOS task row with a past due date renders as overdue. Live bug.
- `Cadence/Models/GoalContributionSummary.swift:129` — `overdueTasks(among:now:)`, the only one that parses to `Date` and compares `Date`s rather than `yyyy-MM-dd` strings; for an unparseable due date the string comparators say "overdue" and this one says "not overdue"
- `Cadence/macOS/Views/GoalsSupportViews.swift:627` — `Goal.isOverdue`, a sixth spelling, macOS-gated (see **P5-12**)

**Fix:** one `AppTask.isOverdue(todayKey:)` in `Models/` that decides the `isDone` question once;
point all task-side callers at it. Keep the goal-side one separate but name it distinctly.
**Effort: M** (five call-site families; one behaviour change to verify on iOS).

## P5-05 — Minutes→"1h 30m" written six times, three spellings, three empty sentinels ⚠ ALREADY DIVERGED

`Cadence/Shared/CadenceTaskPresentationSupport.swift:44` `estimateLabel(minutes:)` is documented
as canonical and uses U+00A0 deliberately.

- `Cadence/Shared/DateFormatters.swift:218` `durationLabel(actual:estimated:)` — NBSP ✓, duplicated on purpose (documented widget-target isolation)
- `Cadence/macOS/Views/TimelineEventBlockSupportViews.swift:71` — **ordinary space**, sentinel `"–"` (U+2013)
- `Cadence/Models/GoalContributionSummary.swift:47` `focusLabel` — **ordinary space**, sentinel `"0m"`
- `Cadence/macOS/Views/KanbanCardStateSupport.swift:7` — a sixth format entirely: `"H:MM"`
- Forwarders (fine): `TaskEmbedFieldEditorPopover.swift:357`, `TimelineDayCanvasShellViews.swift:35`, `FocusSessionSupport.swift:10`

**Fix:** add `emptyPlaceholder:` to `estimateLabel` and route the two plain-space sites through
it. **Effort: S–M.** Pairs with **P4-07**.

## P5-06 — The today-bucket predicate exists six times

- `Cadence/Shared/CadenceTaskQuerySupport.swift:209` — `todayRank(_:todayKey:)`
- `Cadence/Shared/CadenceTaskQuerySupport.swift:272` — `dateBuckets(for:todayKey:)`
- `Cadence/macOS/Views/TaskSortHelpers.swift:72` — `classifyTasksByDate`, line-for-line identical to `dateBuckets` (dead — **P4-02**)
- `Cadence/Services/CadenceTodayWidgetSupport.swift:181` — `rank(_:todayKey:)`, verbatim copy of `todayRank`
- `Cadence/Services/CadenceTodayWidgetSupport.swift:80-88` — the same if/else-if chain inlined a second time for the counts
- `Cadence/Shared/CadenceTaskQuerySupport.swift:43-54` — `todayGroups`, a third structural spelling

Already-visible consequence: `CadenceTaskQuerySupport.activeTodayTasks` (`:13`) sorts by the
user's `CadenceTaskSortMode` while `CadenceTodayWidgetSupport.todayTasks` (`:150`) hard-codes
rank → priority → order. The widget's "top 3 today" is not the app's top 3.

**Fix:** hoist one `nonisolated` `todayRank` into `Models/` (the widget target needs it), delete
`classifyTasksByDate`, and collapse `TaskDateBuckets` / `CadenceTaskDateBuckets` into one struct.
**Effort: M.**

## P5-07 — Two sort taxonomies for the same lists, with opposite priority direction ⚠ ALREADY DIVERGED

- **macOS:** `TaskSortField {custom,date,priority}` × `TaskSortDirection`
  (`macOS/Views/TasksPanelSupport.swift:10, 17`), comparator `taskSortPrecedes`
  (`macOS/Views/TaskSortHelpers.swift:25`)
- **Shared/iOS:** `CadenceTaskSortMode {listOrder,priority,doDate,dueDate,newest}`
  (`Shared/CadenceTaskPlanningSupport.swift:4`), comparator `CadenceTaskQuerySupport.sortTasks`
  (`Shared/CadenceTaskQuerySupport.swift:228`)

Divergences today:

- **Priority direction.** Shared always sorts high-first (`:242`). macOS honours `direction`, and
  `.ascending` — the persisted default in several views — puts **low priority first**
  (`TaskSortHelpers.swift:47-51`). Same menu item, opposite result on the two platforms.
- **Tie-break.** macOS is fully deterministic (order → createdAt → title → uuid,
  `TaskSortHelpers.swift:13`); Shared falls back to `lhs.order` alone, leaving equal-order tasks
  unstably ordered.
- **"No date" sentinel.** `"9999-99-99"` at `TaskSortHelpers.swift:30-31` and
  `CadenceTaskQuerySupport.swift:311`; `"9999-12-31"` at `Models/GoalContributionSummary.swift:156,
  157, 160, 161`, `Services/CadenceMilestoneWidgetSupport.swift:176`, and
  `Shared/CadenceTaskRecurrenceWorkflowSupport.swift:253`. Four sites, two spellings.

**Fix:** one sort-mode enum and one comparator in `Shared/`, with `direction` orthogonal; make
`TaskSortField` a presentation-only mapping onto it. Extract the sentinel to one constant.
**Effort: L** — plan this one; it touches every task surface.

## P5-08 — `Area` and `Project` carry ~105 lines of byte-identical section-config code

Every `sectionConfigsRaw` encode/decode site — all four of them — lives in these two files:

- `Cadence/Models/Area.swift:57-83` (`sectionNames` get/set), `:87-109` (`sectionConfigs` get/set), `:111` (`normalizedSectionConfigs`)
- `Cadence/Models/Project.swift:58-84`, `:88-110`, `:112`

Diffing `Area.swift:44-147` against `Project.swift:46-148` yields **one line** of difference (a
doc-comment offset) — including the long comment about archived-column destruction, i.e. the same
bug story pasted twice. The legacy `sectionNamesRaw` newline-split fallback is duplicated too.
They agree today, which is the state that precedes drift; the failure mode (silent loss of
archived kanban columns) is unrecoverable and has already shipped once, which is what
`CrossPlatformParityTests.swift:79-133` was written for — and those tests assert `Area` and
`Project` *separately*, because there is nothing shared to assert.

**Fix:** a `TaskSectionConfigCodec` enum in `Models/` holding
`decode(configsRaw:namesRaw:)` / `encode(_:) -> (namesRaw, configsRaw)` / `normalized(_:)`, or a
`SectionConfigContaining` protocol with a default implementation. Each model keeps two stored
strings and two forwarding computed properties. **Effort: M.**

## P5-09 — `normalizedSectionName` three times; only the MCP copy trims

- `Cadence/Shared/CadenceTaskMutationSupport.swift:146` — no trimming; used by `assignContainer` (`:162`) and `iOS/iOSTaskDetailSheet.swift:51`
- `Cadence/Services/TaskCreationService.swift:54` — no trimming
- `Cadence/Services/MCPReadOnly/CadenceMCPServiceSupport.swift:84` — **trims**, treats empty as "first section"

`AppTask.resolvedSectionName` (`Cadence/Models/AppTask.swift:215`) trims on read. So a section
name written with trailing whitespace through the UI fails to match on write but matches on read
— the task silently lands in the fallback section instead of the one the user picked.

The "sections for this container" lookup is separately duplicated at
`Shared/CadenceTaskMutationSupport.swift:136`, `Services/TaskCreationService.swift:44`,
`macOS/Views/SchedulePanelComponents.swift:24`, `macOS/Views/QuickCreateChoicePopover.swift:272`,
plus inline at `macOS/Views/ListDetailComponents.swift:26` and `iOS/iOSListDetailView.swift:90`.

**Fix:** one `TaskSectionResolver.normalized(_ requested: String?, in: [String]) -> String` that
trims, plus one container→sections lookup. **Effort: M.**

## P5-10 — Container selection is a bare string protocol re-parsed with magic offsets in five files

Encode: `macOS/Sheets/CreateGoalSheet.swift:148, 151, 160, 163`; `iOS/iOSChoicePicker.swift:147,
159` (and `"inbox"` at `:140`); `iOS/iOSTaskDetailSheet.swift:329, 331`.

Decode, each hand-rolling `dropFirst(5)` / `dropFirst(8)`:
`macOS/Sheets/CreateGoalSheet.swift:301, 305`; `iOS/iOSTaskDetailSheet.swift:55, 60`;
`iOS/iOSCalendarQuickCreateSheet.swift:57, 64`; `iOS/iOSTaskDetailSheetSections.swift:35, 40`.

`5` and `8` are `"area:".count` and `"project:".count` written as literals in four files —
renaming either prefix breaks three files silently. A typed `TaskContainerSelection` already
exists in `Services/TaskCreationService.swift` and these surfaces simply do not use it.

Same shape, separate encoding: `"listTask:\(uuid)"` + `dropFirst(9)` appears verbatim in
`macOS/Views/InboxSupportViews.swift:293, 295` and `macOS/Views/ListDetailSupportViews.swift:50,
52`, bypassing `Shared/TaskDragPayload.swift:14`, which is the shared codec everything else uses.
And the `"list:"` / `"a_"` / `"p_"` drop-key prefixes are produced in
`macOS/Views/TasksPanelSupport.swift:99, 100, 151, 154, 253, 259, 266` and parsed in
`macOS/Views/TasksPanel.swift:346, 353, 582, 589` and `macOS/Views/AllTasksListView.swift:129, 136`
with no shared constant.

**Fix:** make `TaskContainerSelection: RawRepresentable` own both directions; add
`TaskDragPayload.listTaskString` / `.listTaskID`. **Effort: M.**

## P5-11 — The "Inbox" fallback identity is invented at ~12 sites ⚠ ALREADY DIVERGED

`AppTask.containerName` (`Models/AppTask.swift:207`) returns `""` for inbox and
`containerColor` (`:211`) falls back to `"#6b7a99"`. Every surface then re-invents the display:

| site | icon | colour |
|---|---|---|
| `macOS/Views/KanbanCardView.swift:203-204` | `"tray.fill"`, project-first | `#6b7a99` |
| `macOS/Views/TasksPanelSupport.swift:186-188` | `"tray.fill"` | `Theme.dim` |
| `macOS/Views/TaskTitleEntryField.swift:189`, `QuickCreateChoicePopover.swift:294`, `ContainerPickerSupportViews.swift:101` | `"tray"` | `Theme.dim` |
| `iOS/iOSChoicePicker.swift:140` | **`"tray.full.fill"`** | **`Theme.blue`** |
| `macOS/Views/GlobalSearchSupportViews.swift:203` | `"tray.fill"` | **`#5AA2FF`** (a hardcoded hex — also a Theme violation) |

Plus bare `containerName.isEmpty ? "Inbox" : containerName` at `iOS/iOSCalendarView.swift:140`,
`iOS/iPadTodayCompactViews.swift:496`, `macOS/Views/GoalsSupportViews.swift:501`,
`macOS/Views/TaskBundlePickerSupportViews.swift:319`, `iOS/iOSSearchView.swift:524`,
`iOS/iOSMarkdownAccessoryViews.swift:230`.

Separately, `macOS/Views/GlobalSearchIndexSupport.swift:129` and
`Services/MCPReadOnly/CadenceReadService.swift:665` resolve the container **project-first** while
`AppTask.containerName` is **area-first** — harmless only while "never both set" holds, and
nothing enforces that (`SchedulePanelComponents.swift:45, 49` and
`TasksPanelComponents.swift:383, 387` set the pair by hand).

**Fix:** `AppTask.containerDisplay -> (name: String, icon: String, color: Color)` in `Models/`,
plus one `TaskContainerIdentity.inbox` constant for picker rows. **Effort: M.**

## P5-12 — Anaemic models: `Goal`'s domain logic lives in a macOS view file

`Cadence/macOS/Views/GoalsSupportViews.swift:605-631` declares `extension Goal` with
`startDateDate`, `endDateDate`, `rangeLabel`, `progressSummary`, `daysSummary`, and `isOverdue` —
inside a `#if os(macOS)` block in a *views* file. Consequences:

- iOS, `CadenceWidgets`, and `CadenceMCPServer` cannot see any of it, so each re-derives it or
  goes without. `Goal.isOverdue` is the sixth `isOverdue` in the app (**P5-04**).
- `startDateDate` / `endDateDate` call `DateFormatters.ymd.date(from:)` directly, bypassing
  `DateFormatters.date(from:in:)`, the timezone-safe API `Shared/DateFormatters.swift:112-118`
  documents. `DateFormatters.ymd` is a shared mutable singleton with no pinned timezone.
- `progressSummary` reaches into `GoalContributionResolver` from a view file, inverting the
  intended direction of dependency.

**Fix:** move the whole extension into `Cadence/Models/Goal.swift` (or a `GoalInsights.swift`
alongside `HabitInsights.swift`), switch to `DateFormatters.date(from:in:)`, and take a
`calendar:` / `today:` parameter instead of reading `Calendar.current` and `Date()` inline so it
can be tested. **Effort: S–M.**

The same shape, smaller: `Cadence/Models/HabitInsights.swift:56, 66, 89` read `Calendar.current`
and `Date()` directly with no injection point, which is why **P4-19a/b** have no tests.

## P5-13 — `*SupportViews` files split by size, not responsibility

| ID | File | What it actually contains |
|---|---|---|
| P5-13a | `Cadence/macOS/Views/macOSRootSupportViews.swift` (645 lines) | Three unrelated jobs: generic reusable chrome (`DesktopPageHeader:6`, `DesktopControlBar:78`, the `CadenceQuietPill` family `:99-188`, `RootSidebarToggleButton:204`); the root shell's five modal overlay layers (`TaskCreationLayerView:260` … `GlobalSearchLayerView:352`, `DeleteConfirmationOverlay:498`, `HoveredTaskDatePickerOverlay:368`); and an entire **page**, `AllTasksPageView:579`. A page in a "root support views" file is the clearest single symptom. Split into `Shared/Components/CadenceQuietControls.swift`, `macOS/Views/macOSRootOverlayLayers.swift`, and `macOS/Views/AllTasksPageView.swift`. **M** |
| P5-13b | `Cadence/macOS/Views/TasksPanelSupportViews.swift` (712 lines) | A grab bag: page header, two overdue cards, a subtask row, `ContainerPickerBadge:173`, `TaskSectionPickerBadge:302` + `SectionPickerRow:463`, a hover `ViewModifier:501`, two group headers, and a generic `CadenceEnumPickerBadge:610` with a `TaskSortDirection` conformance at `:603`. The two picker badges (~330 lines) are a self-contained feature with their own tests (`ContainerPickerFilterSupportTests`, `TaskPickerHighlightSupportTests`) and belong in their own file; `CadenceEnumPickerBadge` is a generic control that belongs in `Shared/Components/`. **M** |
| P5-13c | `Cadence/Shared/CadenceCalendarPlanningSupport.swift` (651 lines) | Two unrelated namespaces plus six enums: `CadenceCalendarViewMode:4`, `CadenceCalendarPresentation:20`, `CalendarBoardRail:32`, `CalendarBoardDropTarget:59`, `CalendarBoardDropAction:66`, `CalendarBoardAddAction:74`, `CalendarBoardPlannerSupport:79` (≈330 lines), `CalendarBoardSortKey:407`, and then `CadenceScheduleSupport:427` — month grids, weekday symbols, calendar titles, date shifting — which has nothing to do with board planning. Split `CadenceScheduleSupport` into its own file. **S** |
| P5-13d | `Cadence/macOS/Views/GoalsSupportViews.swift` (632 lines) | Mixes derived state (`GoalStatusFilter:10`, `GoalMissionGroup:34`, `GoalMissionGrouping:76`) with fifteen view structs and the model extension from **P5-12**. Move the derived state to a `GoalsStateSupport.swift` and the extension to `Models/`. **M** |

**Rule to apply, from `AGENTS.md`:** root view = state and orchestration; support-view file =
reusable UI sections and rows; state/support file = derived state, sorting, grouping, coordinate
math; service = persistence and side effects. Where a file spans more than one of those, split on
that boundary rather than on line count.

## P5-14 — Repeated `@AppStorage` key literals with no shared constant

Each key is typed as a bare string in two or three unrelated files; a typo in one silently creates
a second, empty preference. The default value is duplicated alongside it, so a settings screen and
the screen it configures can disagree about the default.

| key | sites |
|---|---|
| `"sidebarHiddenTabs"` | `SettingsView.swift:14`, `SidebarView.swift:18`, `GlobalSearchView.swift:12` |
| `"sidebarTabOrder"` | `SettingsView.swift:15`, `SidebarView.swift:19` |
| `"sidebarTabColors"` | `SettingsView.swift:16`, `SidebarView.swift:20` |
| `"listDetailDefaultPage"` | `ListDetailView.swift:67`, `SettingsView.swift:13` |
| `"ios.today.layoutMode"` | `iPadTodayView.swift:14`, `iOSSettingsView.swift:14` |
| `"ios.calendar.viewMode"` | `iOSCalendarView.swift:10`, `iOSSettingsView.swift:15` |
| `"ios.calendar.presentation"` | `iOSCalendarView.swift:11`, `iOSSettingsView.swift:16` |
| `"ios.calendar.zoomLevel"` | `iOSCalendarView.swift:12`, `iOSSettingsView.swift:17` |

`Shared/CadenceCalendarVisibilityPreferences.swift:6` already shows the right pattern
(`hiddenCalendarIDsKey` as one named constant); nothing else follows it.

**Fix:** one `CadencePreferenceKeys` enum pairing each key with its default. **Effort: S.**

## P5-15 — Smaller duplications

| ID | Finding | Fix | Effort |
|---|---|---|---|
| P5-15a | `planningKey(for:)` (`Shared/CadenceTaskQuerySupport.swift:299`) and `railAnchorKey(for:)` (`Shared/CadenceCalendarPlanningSupport.swift:353`) are the same "earliest anchor date" idea under two names in adjacent files | one function | S |
| P5-15b | ISO-week-Monday resolution built twice: `Shared/DateFormatters.swift:175-186` (inside `weekLabel`) and `macOS/Views/NotesListRows.swift:322-334` (`NotesListGrouping.weekStartDateKey`). Identical `Calendar(identifier: .iso8601)` + `en_US_POSIX` + `weekday = 2` construction; neither inherits a timezone the way `DateFormatters.storageCalendar` requires | `DateFormatters.weekStartDate(forWeekKey:)`, called from both | S |
| P5-15c | `storageCalendar` + `dateKey(from:calendar:)` + key parsing exist twice: `Shared/DateFormatters.swift:85-104, 118` and `Services/CadenceTodayWidgetSupport.swift:217-238, 294`. Documented as deliberate (main-actor isolation) and matching today — but the doc comment itself records that the last divergence made both widgets render permanently empty | move into a `nonisolated enum CadenceDateKeys` in `Models/`; have both forward. This is the same move already made for `dueLabel` | M |
| P5-15d | The iOS markdown task-reference picker duplicates its filter+rank block: `iOS/iOSMarkdownAccessoryViews.swift:50-61` and `iOS/iOSMarkdownEditingSurface.swift:331-345`. Identical, except one applies `.prefix(6)` — so the sheet and the inline popup show different-length lists built from separately maintained code | one `MarkdownReferenceCandidates.tasks(from:query:limit:)` in `Services/` | S |
| P5-15e | `"active"` / `"done"` / `"archived"` raw values are re-declared across `ProjectStatus` / `AreaStatus` / `GoalStatus` (`Models/ModelEnums.swift:147-168`), repeated as `statusRaw` defaults in four model files, and typed again as `#Predicate` string literals in `macOS/Views/SidebarView.swift:17`, `iOS/iOSCompactHomeView.swift:10`, `iOS/iOSRootSidebar.swift:44`, `iOS/iOSWorkspaceDrawer.swift:12`. `#Predicate` genuinely cannot see the enum, but the literal should reference one constant | `enum CadenceStatusRaw { static let active = "active" … }` | S |

## P5-16 — Dead production helpers kept alive only by tests

These have zero references outside their own declaration. Each is a small maintenance tax and a
false coverage signal.

| symbol | declaration | tested at |
|---|---|---|
| `classifyTasksByDate` / `TaskDateBuckets` | `macOS/Views/TaskSortHelpers.swift:62, 72` | `TaskSortHelperTests.swift:59` (**P4-02**) |
| `timelineDayIndexForMonthViewReturn` | `macOS/Views/CalendarPageStateSupport.swift:171` | `CadenceTests.swift:261` (**P4-05**) |
| `boardDateByMovingMonth` | `macOS/Views/CalendarPageStateSupport.swift:153` | `CadenceTests.swift:388` (**P4-06**) |
| `HabitHeatmapGrid.dateKeys` | `macOS/Views/HabitsSupportViews.swift:374` | `HabitInsightsAuditTests.swift:331` (**P4-09**) |
| `ToggleHabitCompletionIntent.toggleHabitCompletion` | `Services/CadenceWidgetIntents.swift:157` | `WidgetSupportTests.swift:298` (**P4-08**) |
| `MarkdownQuoteSupport.continuation(after:)` | `Services/MarkdownQuoteSupport.swift:44` | `MarkdownQuoteSupportTests.swift:26, 31, 37` (**P4-11**) — live path is `MarkdownLineBreakSupport.quoteContinuationPrefix` |
| `MarkdownInlinePreviewSupport.plainText(in:)` | `Services/MarkdownInlinePreviewSupport.swift:60` | `MarkdownInlinePreviewSupportTests.swift:22` — live entry point is `runs` |
| `MarkdownReferenceDisplaySupport.replacingWikiLinksWithDisplayText` | `Services/MarkdownReferenceDisplaySupport.swift:149` | `MarkdownReferenceDisplaySupportTests.swift:38` — live path is `inlineSegments` |
| `MarkdownTaskEmbedParser.isLegacyChecklistMarkerCharacter` | `Services/MarkdownTaskEmbedSupport.swift:218` | `NoteReferenceSupportTests.swift:157-159` — live path is `legacyChecklistMarkerRange` |
| `NoteReferenceParser.noteLinks(in:)` | `Services/NoteReferenceSupport.swift:28` | `NoteReferenceSupportTests.swift:10, 62` — live path is `noteReferences(in:)` |
| `CadenceWidgetRefreshCenter.reloadTodayWidgets` | `Services/CadenceWidgetRefreshCenter.swift:37` | `WidgetSupportTests.swift:100` |

The last three delegate to a production-used function, so the underlying logic is exercised
transitively — but the test names advertise coverage of symbols nothing consumes. The first four
do not: **P4-11** shows the live copy diverging from the tested one.

**Fix:** delete each, repointing its test at the symbol production actually calls. Where the
production symbol is `private`, widen it to internal rather than keeping a public shim.
**Effort: S each; M for the batch.**

---

# Phase 6 — Risk hotspots (`SchedulePanel*`, `Timeline*`, EventKit)

`Cadence/macOS/Editor/` was excluded by scope.

## Genuinely fragile

*Silently breaks when an unrelated edit violates an unwritten assumption.*

### P6-01 — The draft ghost and its popover anchor position the same rect two different ways

`Cadence/macOS/Views/TimelineDayCanvasShellViews.swift:72` uses `.offset(x: style.leadingInset,
y: y)`; `:104-105` uses `.padding(.top, y)` + `.padding(.leading, style.leadingInset)`.
`TimelineDraftGhostLayer` (the visual) and `TimelineDraftPopoverAnchor` (the popover attachment
rect) must occupy the identical rect, and **neither uses `.position`**. They coincide only
because `.padding` on a `Color.clear` inside a `.topLeading` `ZStack` happens to land at the same
origin as `.offset`. Change the ZStack alignment, wrap either in a container, or add padding to
the parent, and the popover arrow points at empty canvas. Both also duplicate the same three
computations (`y`, `height`, `ghostWidth`) at `:40-42` and `:88-90`.

**Invariant:** the draft ghost rect and the popover anchor rect are derived once and positioned by
the same mechanism, `.position(x:centerX, y:centerY)`.

**This is a direct violation of the coordinate rule `docs/CLAUDE_REFERENCE.md` documents.** Every real block type
(`TimelineTaskBlock.swift:149`, `TimelineEventBlock.swift:144`, `TimelineBundleBlock.swift:150`,
`TimelineDraggedTaskPreview.swift:77`) obeys it; only the draft overlay does not.

**Fix:** compute one `TimelineBlockFrame` for the draft range via `computeTimelineBlockFrame` and
give both views `.position(x: frame.centerX, y: frame.centerY)`. **Effort: S.**

### P6-02 — The draft ghost is never the width of the block it creates

`TimelineDayCanvasShellViews.swift:42` and `:90` compute `max(0, width - leadingInset -
trailingInset)`. `TimelineMetricsSupport.swift:47` multiplies by `style.blockWidthFraction`
(0.9 / 0.95). Editing `blockWidthFraction` — documented at `TimelineMetrics.swift:41-43` as
reserving a drag-to-create strip — moves every real block but not the ghost or the popover anchor.

**Invariant:** every rect drawn on the timeline canvas derives its width from
`TimelineMetricsSupport.computeBlockFrame`, never from `totalWidth - insets`.

**Fix:** route the draft rect through `computeTimelineBlockFrame(column: 0, totalColumns: 1, …)`.
**Effort: S.**

### P6-03 — "Effective duration of a zero-estimate task" is implemented six ways, and they already disagree ⚠ ALREADY DIVERGED

| site | rule | consequence for `estimatedMinutes == 0` |
|---|---|---|
| `macOS/Views/TimelineMetricsSupport.swift:44` | `duration > 0 ? duration : 60` | block **drawn** 60 min tall |
| `macOS/Views/TimelineMetricsSupport.swift:73` | `max(est > 0 ? est : 30, 5)` | overlap **columns** computed as 30 min |
| `macOS/Views/TimelineTaskBlockInteractionSupport.swift:9` | `max(est, 5)` | block **labels itself** "9:00 – 9:05" |
| `macOS/Views/SchedulePanel.swift:203` | `max(est, 30)` | **export** says 30 min |
| `Models/AppTask.swift:204` | `max(est, 30)` | model's `scheduledEndMin` says 30 |
| `macOS/Views/TimelineDayCanvasOverlaySupport.swift:44` | `est > 0 ? est : 30` | drag preview 30 min |

A zero-estimate task today renders a 60-minute-tall block, is laid out for overlap as if it were
30 minutes (so it can visually overlap a neighbour it was columned against), and prints a
5-minute range inside itself.

**Invariant:** one function owns "effective timeline duration of a task"; every renderer, layout
pass, label, and exporter calls it.

**Fix:** `AppTask.timelineDurationMinutes` in `Models/` (the widget needs it too), replacing all
six. **Effort: M.**

### P6-04 — Edge-resize offset math is written three times, verbatim

`macOS/Views/TimelineTaskBlockInteractionSupport.swift:107-126`,
`macOS/Views/TimelineBundleBlock.swift:350-365`, `macOS/Views/TimelineEventBlock.swift:211-226`.

Identical `switch edge { case .start: localY; case .end: max(0, frame.height - handleHeight) +
localY }` → `snappedMinute(fromY: frame.y + offset)` → `min/max(±5)`. They already differ in what
they write to: the event copy writes `@State liveStartMin`/`liveDurationMinutes`, the task copy
writes straight to the SwiftData model, the bundle copy calls `SchedulingActions.updateBundleTime`.

**Invariant:** edge-resize converts a handle-local Y to a snapped minute through exactly one
shared function parameterised by (frame, metrics, edge, origin range).

**Fix:** extract `TimelineMetrics.resizedRange(edge:localY:frame:originStart:originEnd:)`.
**Effort: M.** Do this before **P6-05**.

### P6-05 — Resize math assumes `frame.height == duration × hourHeight/60`, but `height(for:)` clamps

`TimelineMetrics.swift:27-29` returns `max(minHeight, …)`. The `.end` resize at
`TimelineTaskBlockInteractionSupport.swift:112` reconstructs the pointer's absolute Y as
`frame.y + frame.height - 8 + localY`. Once the block is shorter than `style.minHeight` (24 pt for
`.schedule`), `frame.height` stops shrinking while the true duration keeps shrinking, so the
reconstruction is wrong by up to `minHeight - duration × hourHeight/60`.

In `SchedulePanel` at zoom 1 with a 600 pt viewport, `hourHeight == 50`, so **every block under
~29 minutes has a mistracking end handle** — it stops following the cursor and jumps when dragged
back down.

**Invariant:** `frame.height` must equal `duration × hourHeight / 60` for the `.end` handle's
offset reconstruction to be 1:1 with the pointer.

**Fix:** in the extracted function from **P6-04**, use the *unclamped* geometric height
(`CGFloat(duration) * hourHeight / 60`) for the offset, and reserve `minHeight` for drawing.
**Effort: S** after P6-04, **M** standalone.

### P6-06 — Drag-to-create reconstructs canvas Y from a `VStack` row index

`macOS/Views/TimelineDayCanvasSupportLayers.swift:14-27` builds `TimelineCreateGridLayer` as a
`VStack(spacing: 0) { ForEach(startHour..<endHour) { TimelineCreateRow(…) } }`, and
`macOS/Views/TimelineCreateRowGeometrySupport.swift:6` reconstructs absolute Y as
`CGFloat(hour - startHour) * hourHeight + localY`.

This is the only interactive layer on the canvas not positioned from a `TimelineBlockFrame`. It
silently assumes (a) `VStack` spacing is exactly 0, (b) each row's height is exactly
`metrics.hourHeight` with no padding or border, (c) the VStack starts at canvas Y = 0. Add a 1 pt
divider or any spacing to `TimelineCreateRow`
(`macOS/Views/TimelineDayCanvasSupportViews.swift:15-32`) and every drag-to-create lands at a
progressively wronger minute the further down the day you drag, with a per-hour accumulating
error and no crash or warning. The same reconstruction feeds `isInsideBlockedBlock`
(`TimelineCreateRowGeometrySupport.swift:20-27`), a hand-rolled second hit test against block
frames, so the "don't start a drag inside a block" gate drifts with it.

**Fix:** replace the row grid with one full-height `Color.clear` using
`DragGesture(coordinateSpace: .named("timelineCanvas"))` — the named space already exists at
`TimelineDayCanvas.swift:188` — and draw grid lines as a non-interactive overlay. That deletes
`TimelineCreateRowGeometrySupport` entirely. **Effort: M.**

### P6-07 — Draft-creation state is four `@State`s coalesced field-by-field

`macOS/Views/TimelineDayCanvas.swift:35-38` holds `dragStartMin`, `dragEndMin`, `pendingStartMin`,
`pendingEndMin`. `macOS/Views/TimelineDayCanvasOverlaySupport.swift:20-21` coalesces them:

```swift
guard let start = dragStartMin ?? pendingStartMin,
      let end   = dragEndMin   ?? pendingEndMin,
```

The `??` is applied per field, so a state where `dragStartMin != nil` but `dragEndMin == nil`
yields a hybrid range built from a live drag's start and a committed draft's end. Today
`beginDraftSelection` / `commitDraftSelection`
(`macOS/Views/TimelineDayCanvasStateSupport.swift:21-69`) always move the pair in lockstep —
which is exactly why nobody will notice when a future edit nils one of the four.

**Fix:** `enum DraftSelection { case live(ClosedRange<Int>); case pending(ClosedRange<Int>) }` as a
single `@State?`. **Effort: S.**

### P6-08 — The quick-create popover displays one range and creates a different one

`macOS/Views/TimelineDayCanvas.swift:264-301`. `quickCreatePopover(start:end:)` receives the ghost
range and passes it to `QuickCreateChoicePopover(startMin: start, endMin: end)` at `:267-268` —
but all three creation closures (`:271`, `:285`, `:291`) shadow those parameters and re-read
`pendingStartMin` / `pendingEndMin`.

The divergence is reachable today: `commitDraftSelection` clamps `actualEnd` to `actualStart + 5`
(`TimelineDayCanvasStateSupport.swift:63`) while the ghost may still be showing the raw pair. Drag
out a sub-5-minute selection and the created task's time does not match the time you were shown.

**Fix:** delete the `pendingStartMin` / `pendingEndMin` reads inside the closures; use the
`start` / `end` parameters. **Effort: S.**

### P6-09 — Bundle-drop vs canvas-drop is arbitrated by a 750 ms wall-clock race

`macOS/Views/TimelineDayCanvas.swift:206-209` sets `recentlyBundledTaskDropExpiresAt =
Date().addingTimeInterval(0.75)`, consumed by
`macOS/Views/TimelineDropInteractionSupport.swift:88-89, 122-133`. The racing producer is
`macOS/Views/TimelineTaskBlock.swift:296-313`.

Both `TimelineTaskBundleDropDelegate.performDrop` and `TimelineDropDelegate.performDrop` fire for
one user drop, and both resolve the payload through **async** `provider.loadObject` callbacks
hopping to `@MainActor`. Correctness depends on the shelf's callback winning. If the canvas's
completes first, `shouldSuppressTaskMoveDrop` returns false and the task is *moved to a minute*
instead of *bundled* — silently, and only sometimes. `TimelineTaskBlock.swift:298-300` also calls
`onDropAccepted` synchronously *and* again in the async callback at `:309`, arming the 0.75 s
window twice.

**Invariant:** for a single drop, exactly one of {bundle-into, move-to-minute} runs, chosen by
hit-test geometry, not callback arrival order.

**Fix:** have the shelf's `DropDelegate` return `true` and stop the canvas delegate from receiving
the same point (the shelf is above the canvas in z-order). Failing that, encode the target in the
drag payload rather than in a timer. **Effort: M.**

### P6-10 — `dragGrabOffset` goes stale when a save has not round-tripped

`macOS/Views/TimelineEventBlock.swift:92-97` recomputes the grab offset only `if liveStartMin ==
nil`; `liveStartMin` is cleared only by `.onChange(of: item.startMin)` at `:146-150`. The comment
at `:103` states live state is deliberately kept until EventKit round-trips.

So: drag an event, release, grab it again before `EKEventStoreChanged` arrives (or after a save
that silently failed — see **P6-14**) → `liveStartMin != nil` → the previous gesture's grab offset
is reused → the block teleports by the difference on the first pointer move.

**Fix:** track gesture start explicitly (`@State private var isDragging` reset in `onEnded`)
rather than inferring "new gesture" from `liveStartMin == nil`. **Effort: S.**

### P6-11 — `liveDurationMinutes` is never cleared after a resize

`macOS/Views/TimelineEventBlock.swift:146-150` watches only `item.startMin`, but `:220-225` sets
both `liveStartMin` and `liveDurationMinutes`. A pure end-edge resize leaves `startMin` unchanged,
so the EventKit round-trip fires no `onChange` and `liveDurationMinutes` stays set for the
lifetime of the view. From then on the block renders its stale local duration and ignores every
external change to the event's length — edits from Calendar.app, from the popover at `:118-143`,
from a recurrence-scope change.

**Invariant:** live-edit state must be cleared by an observation that fires for every mutation it
could have made.

**Fix:** `.onChange(of: [item.startMin, item.durationMinutes])`. **Effort: S.**

### P6-12 — Minute-of-day → `Date` is asymmetric with its own inverse, and wrong across DST

`macOS/Services/CalendarManager.swift:179-181` uses `startOfDay(for:).addingTimeInterval(
TimeInterval(startMin * 60))`; `:225-226` and `:280-281` use `cal.date(byAdding: .minute, value:
startMin, to: baseDate)`. Both add **elapsed** minutes from midnight.

The reverse conversion — `macOS/Views/CalendarEventPresentationSupport.swift:60-61` — reads
**wall clock** (`calendar.dateComponents([.hour, .minute], from: segmentStart)`). On a
spring-forward day, `startOfDay + 600 min` is 11:00 local, not 10:00. Drop a block at 10:00 on
8 March and the created event lands at 11:00; the round-trip through `startMin` then reports 660
and the block jumps an hour after the store refresh. Two days a year, silently. Same asymmetry in
`eventDateRangeForEditedSegment` (`CalendarEventPresentationSupport.swift:87-88`).

**Invariant:** `minute-of-day → Date` and `Date → minute-of-day` must both be wall-clock, never
elapsed-offset.

**Fix:** one `TimelineDateMath.date(dateKey:minuteOfDay:calendar:)` using
`calendar.date(bySettingHour:minute:second:of:)`, with a documented policy for the nonexistent
02:00–03:00 hour, used by all three sites. **Effort: M.**

### P6-13 — `Date` derived from a `yyyy-MM-dd` key without a pinned timezone

`macOS/Services/CalendarManager.swift:222` and `:278` call `DateFormatters.date(from: dateKey)`;
`macOS/Views/CalendarEventPresentationSupport.swift:86` does the same inside a function that takes
`calendar: Calendar = .current`.

`DateFormatters.ymd` (`Shared/DateFormatters.swift:8-13`) pins locale but **not** timezone, so it
parses in the system zone; each site then does calendar arithmetic with a `calendar` parameter the
caller can override. `Shared/DateFormatters.swift:112-118` documents this exact hazard and
provides `date(from:in:)` as the correct API — these three sites don't use it. `ymd` is also a
shared mutable singleton: one `DateFormatters.ymd.timeZone = …` anywhere shifts every key parse in
the app.

**Fix:** replace with `DateFormatters.date(from: dateKey, in: calendar)`. **Effort: S.**

### P6-14 — EventKit writes mutate the in-memory `EKEvent` before saving and never roll back

`macOS/Services/CalendarManager.swift:223-231` (`convertAllDayEventToTimed`) and `:303-318`
(`updateEvent`) set `isAllDay` / `startDate` / `endDate` and *then* call `try store.save`. Errors
are swallowed by `print` at `:188`, `:230`, `:317`, `:330`, `:348`.

`EKEvent` is a reference type and the same instance is held by `CalendarEventItem.ekEvent`
(`macOS/Views/CalendarEventPresentationSupport.swift:78`) and rendered by the timeline. If `save`
throws — read-only calendar, access revoked mid-session, iCloud conflict — the UI shows a mutated
event that does not exist in the store, and nothing clears it: no `EKEventStoreChanged`, so
`storeVersion` never bumps and no refetch happens. Combined with **P6-11**, the block is stuck
showing a phantom edit.

**Invariant:** an `EKEvent` mutated for a save is either persisted or `reset()`.

**Fix:** `do { try store.save(…) } catch { event.reset(); surface the error }`, and return
`Bool`/`throws` so `TimelineEventBlock.updateEventRange` (`:284-296`) can clear its live state.
**Effort: M.**

### P6-15 — Drag-to-create a calendar event fails completely silently

`macOS/Views/SchedulePanel.swift:131-133` → `CalendarManager.createStandaloneEvent`
(`macOS/Services/CalendarManager.swift:170-176`): `guard isAuthorized else { return }`, then
`guard let calendar, allowsContentModifications, isActiveCalendar else { return }`, plus a
swallowed `catch` at `:188`.

Three silent early returns. If the user has no writable calendar, has hidden their only calendar
via `CalendarVisibilityPreferences`, or has revoked access mid-session, the gesture completes, the
popover dismisses, `finishDraftCreation()` clears the ghost, and nothing appears. No error the
user can see.

**Fix:** return `Result`/`throws` and surface through the existing confirmation/alert
infrastructure. **Effort: M.**

### P6-16 — `computeUnifiedLayouts` has an undocumented `scheduledStartMin >= 0` precondition

`macOS/Views/TimelineMetricsSupport.swift:72-74` uses `task.scheduledStartMin` raw;
`TimelineDayCanvas.swift:310` and `TimelineTaskBlockInteractionSupport.swift:25` feed it straight
to `computeBlockFrame`. The `-1` sentinel is filtered by both current callers
(`Shared/CadenceCalendarPlanningSupport.swift:457` and `:567`), and `SchedulingActions` writes
`-1` in seven places (`SchedulingService.swift:90, 98, 110, 142, 175, 187, 240`). Nothing in the
timeline layer guards or documents it.

A `-1` task reaching the canvas yields `yOffset(-1) ≈ -0.83 pt` — a block drawn just above the
canvas with a hit target at negative Y, a "11:59 PM – 12:29 AM" label from `TimeFormatters`'
modulo normalisation (`Shared/DateFormatters.swift:195`), and silent occupation of column 0 for
the whole day in the overlap solver. `TimelineMetricsTests.swift:285` asserts this case "does not
crash" without asserting what it should do.

**Fix:** filter at the top of `computeUnifiedLayouts` and document the precondition (**S**). The
real fix is making the sentinel unrepresentable — `var scheduledStartMin: Int?` — which is a
schema change (**L**).

### P6-17 — Minute clamping implemented four ways ⚠ ALREADY DIVERGED

- `macOS/Views/TimelineMetrics.swift:16` — clamps to `[startHour*60, endHour*60 - 5]` (the **visible** range)
- `macOS/Services/SchedulingService.swift:254-256` — `clampedStartMin`, `[0, 1440 - 5]` (the **day**)
- `macOS/Services/SchedulingService.swift:84` — its own inline duration-aware clamp for bundles
- `macOS/Views/TaskEmbedFieldEditorPopover.swift:293` — `[0, 1425]`, a bare literal that is `1440 - 15`, disagreeing with the `-5` used everywhere else

A canvas with `startHour != 0` would let a drop resolve to a minute the canvas cannot draw.

**Fix:** `TimelineMetrics.clampStart(_:duration:)` plus a shared day-range constant.
**Effort: S.** Pairs with **P4-03**, which is the test that should have caught this.

### P6-18 — Grab offset behaves differently for same-day and cross-day drags

`macOS/Views/TimelineDropInteractionSupport.swift:30-40` computes `dragYOffset` only when
`activeDragTaskID` / `activeDragBundleID` is set. Those are `@State` **per `TimelineDayCanvas`**
(`TimelineDayCanvas.swift:46`), set by `TimelineTaskBlock.onDrag` (`TimelineTaskBlock.swift:126`).

Dragging within one day column preserves the grab point. Dragging to an adjacent day column hits
*that* column's canvas, whose `activeDragTaskID` is nil → `dragYOffset = 0` → the block's **top**
snaps to the cursor instead of the grabbed point, jumping by up to the block's height.

**Invariant:** the grab offset belongs to the drag session, not to the canvas the pointer is over.

**Fix:** encode the grab offset in `TaskDragPayload`, or hoist drag-session state into a shared
`@Observable`. **Effort: M.**

### P6-19 — Minute→pixel conversion reimplemented outside `TimelineMetrics`

Canonical: `macOS/Views/TimelineMetrics.swift:24` (`yOffset(for:)`). Copies:
`macOS/Views/TimelineTaskBlockSupportViews.swift:96-98` (the current-time line, CGFloat variant)
and `macOS/Services/CalendarWorkHoursPreferences.swift:87-88` (the work-hours band). If
`yOffset` ever gains a top inset, a half-pixel alignment fix, or a non-linear zoom, the red
current-time line and the amber work-hours band sit at the wrong Y while every block moves.

**Fix:** add a `yOffset(forFractionalMinute: CGFloat)` overload to `TimelineMetrics`; pass
`metrics` into `CalendarWorkHoursPreferences.highlightFrame` instead of
`(startHour, endHour, hourHeight)`. **Effort: S.**

### P6-20 — Zoom-level → `hourHeight` mapping duplicated three times

`macOS/Views/SchedulePanelShellViews.swift:83-84`,
`macOS/Views/SchedulePanelStateSupport.swift:6-7`, `macOS/Views/CalendarTimelineSupport.swift:38,
44` — all three literally `zoomLevel == 1 ? 12 : zoomLevel == 2 ? 8 : 4`.

The render path and the scroll-position persistence path
(`SchedulePanelStateSupport.clampedRememberedHour`) must agree exactly, or the remembered scroll
hour saved on exit restores to the wrong hour. The zoom control at
`macOS/Services/SchedulingService.swift:288-309` is generic over `range: ClosedRange<Int>` and
`SchedulePanelShellViews.swift:24` passes `1...3` — widen that to `1...4` and all three ternaries
silently collapse level 4 into "4 hours" with no compiler complaint.

**Fix:** `enum TimelineZoom { static func targetHours(_:); static func hourHeight(viewportHeight:level:) }`.
**Effort: S.**

### P6-21 — Duplicated geometry constants

- `resizeHandleHeight = 8` is declared at `macOS/Views/TimelineTaskBlockInteractionSupport.swift:6`
  (correctly reused by `TimelineBundleBlock.swift:314, 355`) **and again** at
  `macOS/Views/TimelineEventBlock.swift:39`. The event block's resize reconstruction (`:214`) uses
  its own copy, so enlarging the shared handle leaves event resizing with a constant offset.
- The handle capsule `min(18, max(10, frame.width - 18))` appears at
  `TimelineTaskBlock.swift:177`, `TimelineEventBlock.swift:185`, `TimelineBundleBlock.swift:320`.
- `CalendarTimelineSupport.swift:19-21` declares `calTimeWidth = 44`, `calTimeInset = 10`, and
  `calTimeTotalWidth = 54` as three independent literals, where `SchedulePanel.swift:33-35`
  correctly *derives* the equivalent. Change `calTimeWidth` and the gutter and the content offset
  disagree by the delta.

**Fix:** one constant each; derive `calTimeTotalWidth`. **Effort: S.**

### P6-22 — Block content-tier thresholds are eight unrelated literals

`TimelineTaskBlockSupportViews.swift:195` (`>= 58`), `:201` (`>= 38`);
`TimelineEventBlock.swift:302` (`>= 36`), `:322` (`>= 54`); `TimelineBundleBlock.swift:200`
(`>= 54`), `:221` (`>= 42`), `:232` (`>= 58`), `:261` (`>= 42`).

Three block types answer "is there room for the time label / member rows / a second title line"
with six different numbers, all hard-clipped (`.clipped()` at `:259`, `:331`, `:274`). None derive
from `style.verticalPadding` or the font sizes they gate, so changing
`TimelineBlockStyle.verticalPadding` (`TimelineMetrics.swift:52, 65`) silently starts clipping
labels the thresholds thought would fit.

**Fix:** `enum TimelineBlockDensity { case minimal, compact, full; init(height:style:) }` shared by
all three bodies. **Effort: M.** Low severity — visual clipping, not data loss.

### P6-23 — Deleting a calendar event confirms twice, via three confirm-then-delete copies

`TimelineEventBlock.swift:68-75` (hover delete → confirm → `requestEventMutation(.delete)`) →
`:239-245` → `:272-281`, which **confirms again**. A third copy at `:133-141` (popover delete)
confirms and calls `calendarManager.deleteEvent` directly, bypassing `requestEventMutation` and
therefore the recurrence-scope dialog.

For a non-recurring event the hover path shows "Delete Calendar Event?" twice in a row. The
triplication is the fragile part — the popover copy has already diverged.

**Fix:** make `requestEventMutation(.delete)` the single entry point; drop the confirmation from
the two callers. **Effort: S.**

## Merely intricate — hard to read, not fragile

Recorded so a later reader does not spend time re-deriving that these are safe.

- **All four real block types obey the `.position` invariant.** `TimelineTaskBlock.swift:149`,
  `TimelineEventBlock.swift:144`, `TimelineBundleBlock.swift:150`,
  `TimelineDraggedTaskPreview.swift:77` each place block, resize handles, drop shelf, and popover
  inside one `.frame` positioned by a single `.position(x: frame.centerX, y: frame.centerY)` from
  the same `TimelineBlockFrame`. Only the draft overlay (**P6-01**) violates it.
- **`.offset` on `TimelineWorkHoursHighlightLayer`** (`TimelineDayCanvasSupportLayers.swift:62`)
  and `TimelineCurrentTimeOverlay` (`TimelineTaskBlockSupportViews.swift:115, 124`) violate the
  letter of the rule but carry `.allowsHitTesting(false)` and have no paired hit target — nothing
  can desync. (Their duplicated Y math is **P6-19**; the positioning mechanism is fine.)
- **Resize origin state** — `activeResizeEdge` / `resizeOriginStartMin` / `resizeOriginEndMin`,
  three `@State`s in each of three views. `updateResize` guards on both origins being non-nil,
  `beginResizeIfNeeded` guards on `activeResizeEdge == nil`, and `endResize` clears all three
  together. Self-checking.
- **All six EventKit write sites are authorization-guarded** (`CalendarManager.swift:171, 222, 278,
  302, 322, 344`). **P6-14** and **P6-15** are about failure *handling*, not the guard.
- **`CalendarManager.dayBounds`** (`:357-361`) uses calendar day arithmetic rather than a 24-hour
  offset, is documented, and is injectable. Done right — use it as the model for **P6-12**.
- **`beginDraftSelection` / `commitDraftSelection` min/max swap**
  (`TimelineDayCanvasStateSupport.swift:35-45, 56-69`). Looks like duplicated clamping; it is
  genuinely symmetric, documented, and self-consistent.
- **`computeUnifiedLayouts` O(n²) overlap solve** (`TimelineMetricsSupport.swift:87-101`). Bounded
  by one day's blocks.
- **`snap5` truncating toward zero for negative minutes** (`TimelineMetrics.swift:12`). Reachable
  only by calling `snap5` directly; `snappedMinute` clamps to `>= startHour * 60` first.
- **`TimelineDropDelegate` rebuilt every `body`.** All its mutable state is `@Binding` into
  `TimelineDayCanvas`'s `@State`, so recreation is harmless.
- **`SchedulingService.swift:69-71`** has a `guard let task = …` with an unused binding — a
  compiler warning, harmless, part of the documented warning baseline.

---

# Suggested execution order

Ordered so that each step reduces the risk of the next, and so that no test is repaired before the
duplication it was supposed to catch is collapsed.

### Stage 1 — Delete dead code (unblocks everything, near-zero risk)

1. **P5-16** — delete the eleven dead helpers, repointing each test at the symbol production
   calls. This resolves **P4-02**, **P4-05**, **P4-06**, **P4-08**, **P4-09**, and **P4-11** as a
   side effect and removes the false coverage signal that hides Stage 2. **M**
2. **P4-18a** — delete the empty `example()` test. **S**

### Stage 2 — Fix already-diverged duplicates (live bugs, user-visible)

3. **P5-01** — one `Note.canonicalKey`; migration and repair currently disagree. **S**
4. **P5-02** — list-detail overdue count. **S**
5. **P5-04** — one `AppTask.isOverdue`; the iOS row is wrong today. **M**
6. **P5-03** — one `statusColor`. **S**
7. **P5-05** + **P4-07** — one duration label, one empty sentinel. **S–M**
8. **P6-03** — one effective-duration function; the timeline currently draws, columns, and labels
   the same task three different lengths. **M**
9. **P6-12** + **P6-13** — wall-clock minute↔`Date`, timezone-pinned key parsing. **M**
10. **P4-17** — pin `DateFormatters.monthYear`'s locale; the assertion is already correct and
    fails today on a non-English host. **S**

### Stage 3 — Repair the tests, now that the subjects are singular

11. **P4-01** — `taskPriorityRank` deletion + full-coverage assertion. **S**
12. **P4-03** — real clamp assertion (do this with **P6-17**). **S**
13. **P4-04** — one load-bearing guard in `HoveredTaskManager`, asserted past the debounce. **S**
14. **P4-12** / **P4-14** / **P4-16** — three assertions that currently cannot fail:
    template-override removal, PDF image embedding, image display-width clamps. **S**
15. **P4-13** / **P4-15** — replace two source-grep / structurally-tautological editor tests with
    behavioural ones. Coordinate with whoever is working in `macOS/Editor/`. **S–M**
16. **P4-10** — stub the AI provider's session and assert the body it actually sends. **M**
17. **P4-19a/b/c** — inject `calendar:` into `HabitInsights` and test the three untested metrics.
    **S**
18. **P4-19d–m** — the remaining cheap missing assertions. **S** each
19. **P4-18b/c/d** — tighten the smoke tests. **S**

### Stage 4 — Timeline fragility (highest blast radius; land as its own reviewable change)

20. **P6-01** + **P6-02** — the draft ghost onto `.position` and `computeTimelineBlockFrame`. **S**
21. **P6-08** — popover creates what it displays. **S**
22. **P6-07** — one `DraftSelection` state. **S**
23. **P6-04** then **P6-05** — one resize function, unclamped height for the offset. **M**
24. **P6-17** + **P6-19** + **P6-20** + **P6-21** — collapse the clamp, the minute→pixel
    conversion, the zoom table, and the geometry constants into `TimelineMetrics`. **S** each
25. **P6-06** — replace the row-index grid with a named-coordinate-space drag. **M**
26. **P6-16** — guard and document the `-1` precondition. **S**

### Stage 5 — EventKit correctness

27. **P6-11** — clear `liveDurationMinutes`. **S**
28. **P6-10** — explicit gesture-start tracking. **S**
29. **P6-14** — roll back `EKEvent` on save failure. **M**
30. **P6-23** — one confirm-then-delete path. **S**
31. **P6-15** — surface silent creation failures. **M**
32. **P6-09** — replace the 750 ms drop race with a geometric decision. **M**

### Stage 6 — Structure (do last; large diffs, no behaviour change)

33. **P5-14** — one `CadencePreferenceKeys`. **S**
34. **P5-15a–e** — the five small consolidations. **S–M**
35. **P5-12** — move `extension Goal` into `Models/`. **S–M**
36. **P5-08** — one section-config codec shared by `Area` and `Project`. **M**
37. **P5-09** — one section-name resolver that trims. **M**
38. **P5-06** — one today-rank in `Models/`. **M**
39. **P5-10** — `TaskContainerSelection: RawRepresentable`. **M**
40. **P5-11** — one `containerDisplay`. **M**
41. **P5-13a–d** — split the four support files on responsibility. **M** each
42. **P6-22** — one block-density enum. **M**
43. **P5-07** — one sort taxonomy. **L.** Plan this separately; it touches every task surface and
    changes user-visible ordering on at least one platform.
