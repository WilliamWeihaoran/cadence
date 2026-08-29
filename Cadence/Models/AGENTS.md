# Models Guide

These are shared SwiftData models. Changes here are high impact because they affect persistence, CloudKit sync, migrations, UI queries, and MCP/read-only surfaces.

## Core Rules

- All SwiftData `@Model` relationship arrays intended for CloudKit must be optional arrays, for example `[AppTask]?`.
- Read optional to-many relationships with `?? []`.
- Append by assigning a new array:

```swift
area.tasks = (area.tasks ?? []) + [task]
```

  **The two halves of that rule have different standing. Do not restate it without them (T-401).**
  - *Delete side — a repair.* T-296 measured the window: between `modelContext.delete(subtask)` and
    the next flush the parent's array still holds the deleted row, so a surface re-rendering in
    between draws a gone object. Sever both sides by hand;
    `CadenceTaskMutationSupport.deleteSubtask` is the one spelling.
  - *Create side — a convention, measured **not** to be a repair.* Inside the owning `ModelContext`
    SwiftData back-populates the inverse *and* the array synchronously: T-387 dropped
    `parent.subtasks = existing + [subtask]`, then dropped `subtask.parentTask = parent`, and
    **both mutations survived**. Write both sides anyway so no reader has to know which direction
    is authoritative — but **a one-sided create is not a defect, and needs a failing test before it
    is filed as one.** Two independent audits filed it as one (T-338, T-387) and T-294 hit it a
    third time, recording the correction only in a test comment.
    `CadenceSubtaskInverseParityTests.swiftDataBackPopulatesEitherSideOfANewSubtaskInverse` pins
    the measurement; red there means SwiftData changed and this half became a repair.

- Avoid adding required persisted fields unless you also handle migration/default behavior.
- Store day-level dates as `yyyy-MM-dd` strings. Use `DateFormatters` helpers.
- Keep computed properties side-effect free.
- Relationship inverse behavior matters during deletion. If touching relationships, inspect deletion helpers and any crash reports involving CoreData/SwiftData faults.

## Important Models

`CadenceSchema.swift` is the authoritative list. Live models:

- `Context` - top-level grouping.
- `Area` / `Project` - list containers; both own tasks and list metadata.
- `AppTask` / `Subtask` - schedulable work and nested checklist items. `AppTask` also carries the full recurrence field set and `bundle`/`bundleOrder`/`tags`.
- `TaskBundle` - several tasks grouped into one timeline block (declared in `AppTask.swift`). `tasks` uses a `.nullify` delete rule; verify bundle/task deletion order carefully.
- `Tag` - cross-cutting label, many-to-many with both `AppTask` and `Note`.
- `Goal`, `GoalListLink`, `Habit`, `HabitCompletion` - long-running progress and recurring behavior. `Goal` nests via `parentGoal`/`subGoals`: a top-level goal is a direction (usually `kind == .ongoing`), its sub-goals read as milestones.
  **`GoalListLink` has one write path** — `ModelContext.attachList` / `detachGoalListLink` /
  `toggleGoalListLink` in `Shared/GoalListLinkHelpers.swift`, never a hand-rolled
  `insert(GoalListLink(...))`. Attach is idempotent — but **not** because a duplicate link
  double-counts that list's tasks in the goal's progress. It cannot: `contributingTasks` ends in
  `dedupe(...)`, which filters by task `id`. What a duplicate breaks is everything counting
  *links* — `linkedListCount`, the "N lists" chip, the attribution line, two MCP DTOs, and a second
  identical row in both inspectors. Detach severs the link's own references before deleting
  the row. Rationale and the substring-grep trap: `Cadence/Shared/AGENTS.md`.
- `Note` - the single live note model (see below).
- `SavedLink`, `MarkdownImageAsset` - list bookmarks and editor image assets.

Non-`@Model` types that live in this folder: `TaskSectionConfig` / `TaskSectionDefaults`
(in `AppTask.swift`) and `GoalContributionSummary`. Two more *files* here declare no type at all —
`GoalPresentation.swift` (an `extension Goal`) and `HabitInsights.swift` (an `extension Habit`,
listed here as a type for a long time; there is no `HabitInsights` symbol to reference) — and two
this list omitted for a long time carry rules of their own:

- **`ModelEnums.swift`** — the ten data enums (`TaskPriority`, `TaskStatus`,
  `TaskRecurrenceRule`, `TaskRecurrenceEndMode`, `ProjectStatus`, `AreaStatus`, `GoalStatus`,
  `GoalKind`, `GoalProgressType`, `HabitFrequency`). Every one is `nonisolated`, and a new one
  must be too. The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which hands a bare
  value type a main-actor *synthesized* `Equatable` — and `Models/` compiles straight into
  `CadenceWidgets`, whose timeline providers run off the main actor, and into `CadenceMCPServer`,
  which is on Swift 6 where that is an error rather than a warning. So a status enum written
  without `nonisolated` builds fine in the app and breaks two other targets.
  `CadenceTests/NonisolatedValueTypeTests` is the guard.
- **`TaskOrdering.swift`** — `TaskSortField`, `TaskSortDirection`, and `TaskOrdering`, the app's
  one task comparator. It lives here rather than in `Shared/` or `macOS/` for the same reason:
  the widget and MCP targets order tasks and compile only `Models/`. Two rules attach to it.
  **The tie-break must stay total** (`fallbackPrecedes`: `order` → `createdAt` → `title` → `id`).
  `order` is assigned *per container*, so any cross-list surface routinely compares tasks with
  equal `order`; a comparator that stops there is a partial order, `sort` may return either
  arrangement, and rows visibly reshuffle between renders and between devices.
  `TaskOrderingTests` pins it by sorting a tie-heavy set from two permutations and requiring
  byte-identical output. And **the raw values are persisted** in `@AppStorage` and per-list
  `UserDefaults` keys — renaming a case is fine, changing a raw value silently resets every saved
  sort preference.

## The List Calendar Link Is An Identifier, And That Is A Decision

`Area.linkedCalendarID` / `Project.linkedCalendarID` hold a bare `EKCalendar.calendarIdentifier`
and nothing else — no title, no source, nowhere in the app. T-390 decided that deliberately:
EventKit identifiers are treated as opaque and permanent, so a calendar Apple Calendar deleted and
recreated leaves the link **visibly** dead (the list reads as unlinked) rather than being
re-matched by name. Auto-rebinding on a title match, without a conflict UI, is worse than a broken
link the user can see. Meeting notes stay filed under the old identifier; `CadenceEventNoteSupport`
matches `calendarID` exactly, including in its date/title fallback.

Adding `linkedCalendarTitle` / `linkedCalendarSource` so a stale link could warn and offer
rebinding is the other branch. It is a stored-property change on two `@Model` types with no
`SchemaMigrationPlan` behind it, so it is blocked until one exists — do not add it in passing.
`CadenceEventKitPlatformParityTests` fails if a second `linkedCalendar*` property appears.

## Persisted Fields With No Readers

There is no `SchemaMigrationPlan` in this project, so removing a stored property **drops the
column's data** for every existing store — it does not clean anything up. Two fields currently
look like dead code and are not safe to delete:

- `AppTask.calendarEventID` — has readers but no writer that sets it non-empty. There are exactly
  three, and **all three only ever assign `""`**: `SchedulingService` (7 assignments, no reads),
  `CalendarLinkedTaskSupport` (reads the identifier, looks the event up, clears it when EventKit no
  longer has it), and `CadenceTaskMutationSupport.detachRelationships(for:)` on delete. They exist
  for values an earlier build left on disk and in CloudKit.
  This bullet used to credit the readers with *deleting the linked event* when a task is deleted
  and with *repairing relationships*, and both were wrong — `1d81864` corrected the same two claims
  in the long Claude reference and did not reach this file. Nothing anywhere deletes an event on
  task delete, and `DataIntegrityRepairService`'s one `calendarEventID` line is on **`Note`**, inside note merging,
  where the field is live and in use. Re-grep before repeating either claim, and read the hits:
  `grep -rn calendarEventID --include='*.swift' Cadence` also returns `Note`'s uses of the same
  field name — the event-linked-note path, which is live — so the three files above are the
  `AppTask` ones specifically, not the whole grep.
- `Goal.dependsOnGoalIDsJSON` — finish-to-start dependency IDs as a JSON array of UUID strings.
  Zero readers, zero writers; its JSON accessor was already removed, leaving a tombstone comment
  in `macOS/Views/GoalsSupportViews.swift`.

A dead-code pass will find no references, no UI and no tests for either. That is not evidence.

## Sections Are Not A Model

A kanban/list section is a `TaskSectionConfig` (uuid, name, colorHex, dueDate, isCompleted,
isArchived) JSON-encoded into `Area.sectionConfigsRaw` / `Project.sectionConfigsRaw`, read back
through the `sectionConfigs` computed property. `AppTask.sectionName` is only the string that
points at one. The legacy `sectionNamesRaw` is the pre-config fallback the getter migrates from.
Never hand-edit the raw strings; go through `sectionConfigs`.

**The Default column has no lifecycle, and that is a model rule, not a UI preference.**
`Area.normalizedSectionConfigs` / `Project.normalizedSectionConfigs` force `isCompleted` and
`isArchived` false on the column named `Default` on **every read and every write** — it is
*synthesised* when absent, `AppTask.resolvedSectionName` funnels every task with no section name
into it, and `sectionNames` hides archived columns, so a completed-or-archived Default would be an
invisible bucket still collecting every new task in the list. Ask `TaskSectionConfig
.supportsLifecycle` before offering a column a Complete or Archive control. Offering one anyway is
not a no-op: the settle beside the flag (`TaskContainerLifecycleService`) marks every open task in
the column done or cancelled and only the *flag* is discarded, so the action appears to work and
the column re-renders Active with its cards gone. That shipped on macOS's kanban column
(`docs/TODO.md` T-268).

## Notes: One Live Model, Five Legacy Ones

`Note` is the canonical note model. `NoteKind` is `daily` / `weekly` / `permanent` / `list` /
`meeting`, with `dateKey`, `weekKey`, calendar-event fields, `folderPath`, `area`/`project`, and
`tags` all on the one type.

`DailyNote`, `WeeklyNote`, `PermNote`, `Document`, and `EventNote` are **legacy migration
sources only**. They stay in the schema so `NoteMigrationService` can read pre-merge rows, and
`PrivacyDataResetService` deletes them. The one extra survival is `Document`: `Area.documents`
and `Project.documents` still exist as relationship declarations, so `ListDeleteHelpers` and
`DataIntegrityRepairService` touch them during cascade deletes. Do not build UI on any of them.

## Pursuit Was Merged Into Goal

The retired `Pursuit` model folded into `Goal`: a pursuit is now a top-level goal
(`parentGoal == nil`) with `kind == .ongoing`. `Pursuit.swift`, `Goal.pursuit`, `Habit.pursuit`,
`Context.pursuits`, and the `Pursuit.self` schema entry survive so `PursuitToGoalMigration` can
read pre-merge rows. Do not read or write them from feature code. Two non-migration callers are
legitimate and deliberate: `ListDeleteHelpers` (cascade-deletes surviving pursuit rows with a
context) and `PrivacyDataResetService` (wipes them). See the removal checklist in
`Cadence/Services/PursuitToGoalMigration.swift`.

## Before Finishing

- Build the macOS target — and, because `Models/` compiles into them directly, the
  `CadenceWidgets` and `CadenceMCPServer` schemes too. Only the last of those is on Swift 6, so it
  is the one that turns an isolation mistake here into an error.
- If the schema changed, check `Cadence/Services/CadenceSchema.swift` and migration/repair services.
- Check any read-only API or export surface that mirrors models — in practice
  `Cadence/Services/MCPReadOnly/`'s DTOs and services. A model change that skips them compiles and
  ships a stale response schema; `CadenceMCPServer/AGENTS.md` has the procedure.
- Add new `@Model` types to `PrivacyDataResetService` as well, or a data reset leaves orphans.
- Classify any new stored `String`: a field that can hold markdown needs a `CadenceMarkdownSourceInventory.Source` case, and everything else goes in the plain list in `CadenceMarkdownSourceInventoryTests`. That inventory is the definition of "still referenced" for `MarkdownImageAsset`, so a markdown field it cannot see is a picture the next delete collects — T-411, where the sweep knew only `Note.content` and `AppTask.notes` was invisible to it. The test fails on anything unclassified, in both directions.
