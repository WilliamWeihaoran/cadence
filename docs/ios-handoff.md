# iOS handoff — issues found during a macOS/shared audit

These were found while auditing `Cadence/Shared/` and the macOS surface. They are all in
`Cadence/iOS/` (or are iOS-only consequences of shared code). **Every item below has now been
fixed** — the sections are kept so the reasoning and the reproductions stay on record, each with a
note on what landed and where the coverage is.

Repo conventions that apply: no hardcoded colours (use `Theme.*`); test runs **must** be scoped
with `-only-testing:CadenceTests`, since an unscoped run pulls in `CadenceUITests`, which cannot
launch headless and aborts the whole run; warning baseline is 3. There is **no
`SchemaMigrationPlan`**, so removing a SwiftData stored property drops user data rather than
cleaning anything up — none of the fixes below required that.

---

## 1 — Deleting a task on iOS leaves an empty timeline block and fires a notification for a task that no longer exists — **fixed**

`Cadence/Shared/CadenceTaskMutationSupport.swift` `delete(_:modelContext:)` was iOS's only delete
path. Compared with macOS's `TaskDeleteHelpers.deleteTasks(withIDs:)` it was missing three things:

- **`deleteEmptyBundles`.** Delete the last task in a `TaskBundle` on iPhone and the empty bundle
  survived. `CadenceCalendarPlanningSupport.bundlesByDate` does not filter empty bundles, so an
  empty block kept rendering on the Mac timeline indefinitely.
- **`NotificationManager.cancel(taskIDs:)`.** Delete a task whose `scheduledStartMin` was two
  minutes away and stay in the app: the pending local notification was never cancelled and fired,
  naming a task that was gone. Reconciliation only converges at the next `scenePhase` transition.
- **`SchedulingActions.removeFromCalendar`** for legacy non-empty `calendarEventID` values.

It also used `(try? modelContext.fetch(...)) ?? []` to feed
`repairDanglingRecurrenceLinks(forDeleted:allTasks:)` — the shape macOS treats as unsafe, because
with `?? []` a failed read gives the repair nothing to re-point, so the predecessor keeps believing
its successor is alive and the recurring series silently stalls.

**Fixed as one shared core.** `CadenceTaskMutationSupport.deleteTasks(withIDs:modelContext:
willDelete:didDeleteBundles:)` is now the single implementation — bundle disposal, subtask
unlink-and-delete, relationship detachment (including clearing a legacy `calendarEventID`),
recurrence repair, `processPendingChanges`, and the notification cancel. It returns `false` and
touches nothing when either fetch fails. macOS's `ModelContext.deleteTasks(withIDs:)` is now a
thin wrapper supplying its two AppKit-shaped hooks: singleton state teardown
(`cancelTaskState`) and the focus session a disposed bundle invalidates. Add behaviour to the
shared core, not the wrapper.

Coverage: `CadenceTests/TaskDeleteParityTests.swift` (bundle disposal both ways, recurrence
repair, subtask cascade, legacy `calendarEventID`, the `willDelete` hook firing only when there is
real work, the `didDeleteBundles` report, and a macOS-only assertion that both entry points leave
an identical store). `TaskDeleteHelpersScenarioTests` still passes unchanged and now exercises the
shared core.

---

## 2 — iPad Today silently drops over-do tasks that macOS Today shows — **fixed**

`Cadence/Shared/CadenceTaskQuerySupport.activeTodayTasks`, the helper `iPadTodayView` calls, had no
`scheduledDate < todayKey` clause, while macOS's `TasksPanelDerivedState` has an explicit
`overdoTasks` bucket.

**Reproduction:** task "Draft Q3 report", do date 2026-08-10, **no due date**, not done. Open
Today on 2026-08-11. macOS showed it in the over-do group; iPad Today showed it nowhere.

**Fixed.** `activeTodayTasks` now covers all four buckets macOS shows. `todayGroups` gained a
matching `.pastDo` group (`CadenceTodayTaskGroupKind`), so an over-do task gets its own "Past Do"
section rather than being filed under "Planned Today" — the group order and the flat `todayRank`
sort order both now read past due → past do → due today → do today, matching
`TasksPanel.todayDateSections`.

Coverage: `CadenceTests/TodayScopeParityTests.swift` — one task per bucket, asserting the shared
helper and `TasksPanelDerivedState.todayEligibleTasks` return the same id set, plus the grouping
and flat-sort order.

---

## 3 — Completed overdue tasks still render red on iOS — **fixed**

`iOSTaskViews.swift` re-derived overdue inline with no `isDone` guard, so a task due 2026-08-05 and
completed today showed a red flag badge reading "6 days ago" while macOS showed it dim grey.

**Fixed.** `iOSTaskRow` now reads `CadenceDueUrgency.evaluate(dueDateKey:isDone:)`, which collapses
a finished task to `.later`. Two more inline re-derivations went the same way:
`iOSTaskDetailComponents` (which also lacked the guard) and `iOSCalendarBoardCards` now call
`AppTask.isOverdue(todayKey:)`.

Coverage: the predicates themselves are pinned by `TaskOverdueSupportTests`; the iOS call sites are
view code and are not separately unit-testable. **Do not re-derive overdue inline on iOS** — that
inline spelling is what drifted.

---

## 4 — iOS list editor loses a kanban column's colour and due date when the column is renamed — **fixed**

The model-side half was already fixed (`Area.sectionNames` / `Project.sectionNames` preserve
archived configs). What remained was iOS-side: the editor edited columns as a newline-separated
list of *names*, so a rename minted a fresh `TaskSectionConfig` and dropped its `colorHex`,
`dueDate` and `isCompleted`; nothing reassigned `task.sectionName`, stranding tasks on a name no
column had any more (which surfaced on macOS as a phantom column via `CadenceReadService`'s
`extraSections`); and iOS read `sectionConfigs` in zero production files, so there was no
per-column colour, due-date, completion or archive UI at all.

**Fixed.** New shared `Cadence/Shared/CadenceSectionEditingSupport.swift` carries a
`CadenceSectionDraft` — the config's `uuid` plus its `originalName` — through the edit, so a rename
is a rename. `iOSListEditorSheet` now reads and writes `sectionConfigs` directly, with a row per
column exposing name, colour swatches, due date, completed and archived, plus add / delete /
reorder. On save it re-points every task whose column was renamed, and hands tasks from a deleted
column to Default — the same promise macOS's "Delete Column?" confirmation makes.

Coverage: `CadenceTests/SectionConfigRoundTripTests.swift` — three configs, one archived, one
renamed; all three survive with uuid, colour and due date intact; a no-op save changes nothing;
renames that are only capitalization are not moves; and no task is left naming a column the list no
longer has.

---

## 5 — iOS month grid weekday header — **already fixed, listed so it is not re-broken**

`iOSCalendarMonthViews.swift:25` used `calendar.shortWeekdaySymbols` directly. That array is
indexed by weekday *number*, so `[0]` is always Sunday however `firstWeekday` is set — localized
in content, fixed in order — while the grid honours `firstWeekday`. In Germany the header read
`So Mo Di` over columns that started on Monday; under `ar_SA` the skew was six columns.

It now calls `CadenceScheduleSupport.weekdaySymbols(calendar:)`, which rotates to match
`monthGridDays`. Covered by `CrossPlatformParityTests.monthGridHeadingsNameTheWeekdayOfTheirOwnColumn`
for all seven `firstWeekday` values. **Do not go back to `shortWeekdaySymbols` directly.**

---

## 6 — Work-hours preferences are macOS-only despite platform-neutral keys — **fixed**

`CalendarWorkHoursPreferences` was `#if os(macOS)` in `macOS/Services/`, despite keys in a
`calendar.*` namespace, not `macos.*`. Set work hours 07:00–15:00 on the Mac and the iPad day view
showed a flat 6–23 timeline with no emphasis, with no iOS control to discover or change it.

**Fixed.** The type now lives unfenced in `Cadence/Shared/CalendarWorkHoursPreferences.swift`.
`iOSCalendarTimelineGrid` reads the same two keys once (not per day column) and each day column
draws the band; `iOSCalendarSettingsSection` gained a Work Hours card with the same start/end
pickers and the same `normalizedRange` repair-on-appear macOS has.

`highlightFrame` gained a second spelling that takes the caller's own minute → Y closure, because
macOS has `TimelineMetrics` and the iOS day column has its own linear `yOffset`. The existing
`metrics:` overload is now a one-line forward to it, so there is still exactly one extent
calculation — **do not** reintroduce an `(startHour, endHour, hourHeight)` parameter list here.
`TimelineMetrics` itself was deliberately left in `macOS/Views/` and untouched.

Coverage: `CadenceTests/WorkHoursParityTests.swift` — the two overloads cannot disagree, the band
is clipped to visible hours, an out-of-range window draws nothing, weekends are suppressed.

---

## 7 — Smaller iOS-side divergences

- **`iOSHabitFrequencyEditor` offered an unreachable weekly target** (`1...14` versus macOS's
  `1...7`), so a habit created on iPhone with a target of 10 had `currentStreak == 0` permanently.
  **Fixed:** the bound is now `HabitFrequency.weeklyTargetRange` (`1...7`), used by both platforms'
  editors, and both edit sheets clamp a stored value through
  `HabitFrequency.clampedWeeklyTarget(_:)` on open — macOS previously showed `10` with `+` disabled
  and saved it straight back. Coverage: `CadenceTests/HabitWeeklyTargetTests.swift`, including the
  behavioural reason for the cap (a perfect week cannot satisfy a target above seven).
- **Two more copies of `priorityRank`** at `iOSMarkdownAccessoryViews.swift` and
  `iOSMarkdownEditingSurface.swift`. **Fixed:** both now use `TaskPriority.rank`.
- **`TaskDragPayload` was declared twice** — `Shared/iOSTaskDragPayload.swift` (`#if os(iOS)`) and
  `macOS/Services/TaskDragPayload.swift` (`#if os(macOS)`) — same type name, byte-identical bodies,
  no compiler relationship between them. **Fixed** (`0625091`): one unfenced
  `Cadence/Shared/TaskDragPayload.swift`. These strings are the wire format between a drag source
  and a drop target, so a one-sided edit would have produced a platform whose drags silently
  stopped matching.
- **iOS rendered raw YAML frontmatter** in the note editor where macOS hides it. **Fixed.** iOS was
  not calling the parser that already existed: `MarkdownMetadataParser`. The "what to suppress"
  rule — the parsed block *plus* the blank lines under it — was spelled out inline in macOS's
  `MarkdownStylist.applyFrontmatter`, so it is now
  `MarkdownMetadataParser.hiddenFrontmatterRange(in:)` and both stylers call it; hiding a block to
  two different extents would put the caret in two different places for the same note.
  `iOSMarkdownStyler` applies it last (so no earlier pass restyles it back into view), removes the
  `.attachment` the divider pass hung on the `---` fences — `hide` only shrinks glyphs, an
  attachment image draws regardless — and tags the run `cadenceMarkdownFrontmatter`, which is what
  the *already-present* `MarkdownHiddenRangeSupport.snappedCaretLocation` call in
  `iOSMarkdownEditor` needs to push the caret past the block. Only in live mode: raw `.edit` mode
  exists to show the file as written, and its caret is deliberately un-snapped.
  `MarkdownPreviewParser` skips the block too — `---` is divider syntax and `tags: [a]` is a
  paragraph, so preview mode and every `plainPreviewText` excerpt were rendering rule / prose /
  rule. It starts its scan at `frontmatterLineCount` rather than parsing a stripped string, because
  the `lineIndex` a `.checklist` carries is used to toggle that line in the original note.
  Coverage: `TagSupportTests` (both new helpers) and `MarkdownPreviewParserTests` (skips the block,
  keeps the note's line numbering, still renders a divider pair that is *not* frontmatter).
- **iOS had no delete for goals or habits.** A habit created with no context and no goal could not
  be removed on iOS by any means short of a full data reset. **Fixed:** `TrackingDeleteHelpers`
  moved to `Cadence/Shared/` and lost its `#if os(macOS)` fence — nothing in it is AppKit-shaped —
  and `iOSGoalsView` / `iOSHabitsView` grew a long-press delete on the list rows with a
  confirmation naming what actually goes. The affordance is on the *row* rather than the detail
  view on purpose: in the compact layout the detail is a pushed view, so deleting from inside it
  would leave a screen bound to a row that no longer exists. Coverage:
  `TrackingDeleteHelpersTests` (already existed; now runs unfenced).

---

## Where to check parity in future

The single highest-yield pattern in this codebase has been *one idea implemented more than once,
then drifting* — and the drift is almost always invisible on whichever platform the author is
using. `Cadence/Shared/` is not really a shared layer: most of its symbols have callers on exactly
one platform, and the other platform has a near-copy. When adding anything to `Shared/`, check
whether the other platform already has its own version, and if so delete that one rather than
adding a third.

Three of the fixes above took the same shape and it is worth naming: the fix was not to write an
iOS version of a macOS thing, but to move the macOS thing into `Shared/` and leave the platform a
thin wrapper for the parts that are genuinely AppKit-shaped (`TaskDeleteHelpers` → two hooks,
`CalendarWorkHoursPreferences` → one geometry closure, `TrackingDeleteHelpers` → nothing at all).
