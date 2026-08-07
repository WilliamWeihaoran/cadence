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

- `Context` - top-level grouping.
- `Area` / `Project` - list containers; both own tasks and list metadata.
- `AppTask` / `Subtask` - schedulable work and nested checklist items.
- `TaskBundle` if present in this tree in future changes - scheduled grouped work; verify bundle/task deletion order carefully.
- `Goal`, `Habit`, `HabitCompletion` - long-running progress and recurring behavior. `Goal` nests via `parentGoal`/`subGoals`: a top-level goal is a direction (usually `kind == .ongoing`), its sub-goals read as milestones. The retired `Pursuit` model was merged into `Goal`; `Pursuit.swift`, `Goal.pursuit`, `Habit.pursuit`, and `Context.pursuits` exist only for `PursuitToGoalMigration` - do not read or write them anywhere else.
- `Note`, `DailyNote`, `WeeklyNote`, `PermNote`, `EventNote`, `MarkdownImageAsset` - notes and linked editor assets.

## Before Finishing

- Build the macOS target.
- If the schema changed, check `Cadence/Services/CadenceSchema.swift` and migration/repair services.
- Check any read-only API or export surface that mirrors models.
