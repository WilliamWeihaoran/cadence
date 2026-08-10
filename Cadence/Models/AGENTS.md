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

Non-`@Model` types that still live in this folder: `TaskSectionConfig` / `TaskSectionDefaults`
(in `AppTask.swift`), `GoalContributionSummary`, `HabitInsights`.

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

- Build the macOS target.
- If the schema changed, check `Cadence/Services/CadenceSchema.swift` and migration/repair services.
- Check any read-only API or export surface that mirrors models.
