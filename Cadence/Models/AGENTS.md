# Models Guide

These are shared SwiftData models. Changes here are high impact because they affect persistence, CloudKit sync, migrations, UI queries, and MCP/read-only surfaces.

## Core Rules

- All SwiftData `@Model` relationship arrays intended for CloudKit must be optional arrays, for example `[AppTask]?`.
- Read optional to-many relationships with `?? []`.
- Append by assigning a new array:

```swift
area.tasks = (area.tasks ?? []) + [task]
```

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
- `Note` - the single live note model (see below).
- `SavedLink`, `MarkdownImageAsset` - list bookmarks and editor image assets.

Non-`@Model` types that live in this folder: `TaskSectionConfig` / `TaskSectionDefaults`
(in `AppTask.swift`), `GoalContributionSummary`, `HabitInsights`, `GoalPresentation.swift` (an
`extension Goal`), and two files this list omitted for a long time and that carry rules of their
own:

- **`ModelEnums.swift`** — the eleven data enums (`TaskPriority`, `TaskStatus`,
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

## Persisted Fields With No Readers

There is no `SchemaMigrationPlan` in this project, so removing a stored property **drops the
column's data** for every existing store — it does not clean anything up. Two fields currently
look like dead code and are not safe to delete:

- `AppTask.calendarEventID` — has readers but no writer that sets it non-empty. They exist to
  clear stale identifiers, delete a linked event when its task is deleted, and repair
  relationships, all for values an earlier build left on disk and in CloudKit.
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
