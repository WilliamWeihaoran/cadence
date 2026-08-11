# iOS handoff — issues found during a macOS/shared audit

These were found while auditing `Cadence/Shared/` and the macOS surface. They are all in
`Cadence/iOS/` (or are iOS-only consequences of shared code) and were deliberately **not** fixed,
so nothing here has been touched. Each has a concrete reproduction.

Repo conventions that apply: no hardcoded colours (use `Theme.*`); test runs **must** be scoped
with `-only-testing:CadenceTests`, since an unscoped run pulls in `CadenceUITests`, which cannot
launch headless and aborts the whole run; warning baseline is 3. There is **no
`SchemaMigrationPlan`**, so removing a SwiftData stored property drops user data rather than
cleaning anything up — none of the fixes below require that.

---

## 1 — Deleting a task on iOS leaves an empty timeline block and fires a notification for a task that no longer exists

`Cadence/Shared/CadenceTaskMutationSupport.swift` `delete(_:modelContext:)` (~:236-253) is iOS's
only delete path. Compared with macOS's `TaskDeleteHelpers.deleteTasks(withIDs:)` it is missing
three things:

- **`deleteEmptyBundles`.** Delete the last task in a `TaskBundle` on iPhone and the empty bundle
  survives. `CadenceCalendarPlanningSupport.bundlesByDate` does not filter empty bundles, so an
  empty block keeps rendering on the Mac timeline indefinitely. Deleting the same task on macOS
  disposes of the bundle.
- **`NotificationManager.cancel(taskIDs:)`.** Delete a task whose `scheduledStartMin` is two
  minutes away and stay in the app: the pending local notification is never cancelled and fires,
  naming a task that is gone. Reconciliation only converges at the next `scenePhase` transition.
  This matters more since habit reminders became repeating.
- **`SchedulingActions.removeFromCalendar`** for legacy non-empty `calendarEventID` values.
  `CLAUDE.md` documents that field as read-only-by-design for rows written by an earlier build;
  the reader should be added on this path, not the field removed.

It also uses `(try? modelContext.fetch(...)) ?? []` to feed
`repairDanglingRecurrenceLinks(forDeleted:allTasks:)`. macOS now treats that exact shape as
unsafe and returns `false` without touching anything — see the 17-line comment at the top of
`TaskDeleteHelpers.deleteTasks(withIDs:)`. With `?? []` a failed read gives the repair nothing to
re-point, so the predecessor keeps believing its successor is alive and **the recurring series
silently stalls**.

**Suggested fix:** bring the shared delete up to parity with `TaskDeleteHelpers`, or have it call
into a shared core that both platforms use. Test: `TaskDeleteParityTests` — delete a bundled,
recurring, scheduled task through each path and assert bundle disposal, subtask disposal, and
predecessor `recurrenceSpawnedTaskID` repair are identical.

---

## 2 — iPad Today silently drops over-do tasks that macOS Today shows

`Cadence/Shared/CadenceTaskQuerySupport.swift` (~:10-16), the helper only `iPadTodayView.swift:33`
calls:

```swift
return task.scheduledDate == todayKey ||
    task.dueDate == todayKey ||
    (!task.dueDate.isEmpty && task.dueDate < todayKey)
```

There is no `scheduledDate < todayKey` clause. macOS's `TasksPanelDerivedState` has an explicit
`overdoTasks` bucket for exactly that case.

**Reproduction:** task "Draft Q3 report", do date 2026-08-10, **no due date**, not done. Open
Today on 2026-08-11. macOS shows it in the over-do group and offers the rollover banner. iPad
Today shows it nowhere — every clause above is false. Same account, same moment.

`CLAUDE.md`'s "Today view task scope" section documents past-do as in scope; the shared helper
does not implement it.

**Test:** `TodayScopeParityTests` — seed one task per bucket (do-today, due-today, over-do,
past-due) and assert the shared helper and `TasksPanelDerivedState` return the same id set.

---

## 3 — Completed overdue tasks still render red on iOS

`Cadence/iOS/iOSTaskViews.swift:~292`:

```swift
private var isOverdue: Bool {
    !task.dueDate.isEmpty && task.dueDate < DateFormatters.todayKey()
}
```

No `isDone` guard, and the badge renders whenever `!task.dueDate.isEmpty` (~:228). Both macOS
equivalents guard: `MacTaskRow.isOverdue` has `!task.isDone`, and the shared
`CadenceDueUrgency.evaluate` collapses a done task to `.later`.

**Reproduction:** task due 2026-08-05, completed today. The iOS list shows a red flag badge
reading "6 days ago"; macOS shows it dim grey. The user is told a settled deadline is still urgent.

Worth noting more broadly: `CadenceDueUrgency` has **seven callers, all macOS**. iOS re-derives
urgency inline everywhere, which is why this drifted. Routing iOS through it would fix this case
and prevent the next one.

---

## 4 — iOS list editor loses a kanban column's colour and due date when the column is renamed

The data-loss half of this is **already fixed** on the model side: `Area.sectionNames` /
`Project.sectionNames` used to rebuild the whole config array from the assigned value, so every
write destroyed archived columns — and `iOSListEditorViews.swift` (~:243, 251, 261, 270) edits a
list purely through that property, meaning opening a list on iPhone and tapping Save with no
changes deleted every archived column. The setter now preserves archived configs, and
`CrossPlatformParityTests` covers it.

What remains is iOS-side:

- **Renaming still loses metadata.** The setter matches existing configs by name, so a renamed
  column mints a fresh `TaskSectionConfig` and drops its `colorHex`, `dueDate` and `isCompleted`.
  Fixing this needs column *identity* in the editor (carry `TaskSectionConfig.uuid` through the
  edit) rather than a smarter guess in the model.
- **iOS never reassigns `task.sectionName` on rename.** macOS's
  `KanbanSectionColumnView` calls `moveTasks`; iOS does not, so tasks are stranded on the old
  section name. Those then surface on macOS as a phantom column via `CadenceReadService`'s
  `extraSections`.
- **iOS reads `sectionConfigs` in zero production files** (only `iOSSampleDataSupport.swift`, for
  debug seeding). There is no per-column colour, due-date, completion or archive UI on iOS at all.

**Suggested fix:** have the iOS editor read and write `sectionConfigs` directly. Test:
`SectionConfigRoundTripTests` — three configs, one archived, one renamed; assert all three survive
with uuid, colour and due date intact.

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

## 6 — Work-hours preferences are macOS-only despite platform-neutral keys

`CalendarWorkHoursPreferences` is `#if os(macOS)`. Its keys are
`calendar.workHours.startMinute.v1` / `.endMinute.v1` — a `calendar.*` namespace, not `macos.*`,
which reads like an oversight rather than a decision. Only `TimelineDayCanvas` reads them and only
`SettingsCalendarWorkHoursSection` writes them.

**Reproduction:** set work hours 07:00–15:00 on the Mac. The iPad day view shows a flat 6–23
timeline with no emphasis, and iOS Settings exposes no control to discover or change it.

**Suggested fix:** draw the work-hours band on the iOS/iPad timeline and add the control to iOS
Settings → Calendar, reading the same shared keys. The preference object needs to lose its
`#if os(macOS)` fence and move to `Shared/`.

---

## 7 — Smaller iOS-side divergences

- **`iOSHabitFrequencyEditor` offers an unreachable weekly target.** It allows `1...14` times per
  week (`iOSTrackingEditorComponents.swift:~198`) while macOS's stepper is `1...7`. Since toggling
  is one row per day with no counter UI, a week can contribute at most 7, so a habit created on
  iPhone with a target of 10 has `currentStreak == 0` permanently and reads "10x/week · no streak"
  on both platforms. macOS's edit sheet shows `10` with `+` disabled but never clamps it down, so
  saving writes `10` straight back. Clamp to `1...7`, or make the target reachable.
- **Two more copies of `priorityRank`** live at `iOSMarkdownAccessoryViews.swift:~145` and
  `iOSMarkdownEditingSurface.swift:~437`. The other five were consolidated onto
  `TaskPriority.rank` (in `Models/ModelEnums.swift`, `nonisolated` so widget timeline providers can
  reach it). These two should call it.
- **`TaskDragPayload` is declared twice** — `Shared/iOSTaskDragPayload.swift` (`#if os(iOS)`) and
  `macOS/Services/TaskDragPayload.swift` (`#if os(macOS)`) — same type name, byte-identical bodies,
  no compiler relationship between them. One shared declaration would remove a whole class of
  silent drift.
- **iOS renders raw YAML frontmatter** in the note editor where macOS hides it.
- **iOS has no delete for goals or habits.** macOS now has both, with confirmation. A habit created
  with no context and no goal cannot be removed on iOS by any means short of a full data reset.

---

## Where to check parity in future

The single highest-yield pattern in this codebase has been *one idea implemented more than once,
then drifting* — and the drift is almost always invisible on whichever platform the author is
using. `Cadence/Shared/` is not really a shared layer: most of its symbols have callers on exactly
one platform, and the other platform has a near-copy. When adding anything to `Shared/`, check
whether the other platform already has its own version, and if so delete that one rather than
adding a third.
