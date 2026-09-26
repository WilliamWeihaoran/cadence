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
  - *Delete side — a repair.* Between `modelContext.delete(subtask)` and the next flush the
    parent's array still holds the deleted row, so a surface re-rendering in between draws a gone
    object (T-296). Sever both sides by hand; `CadenceTaskMutationSupport.deleteSubtask` is the
    one spelling.
  - *Create side — a convention, measured **not** to be a repair.* Inside the owning
    `ModelContext` SwiftData back-populates the inverse *and* the array synchronously (T-387).
    Write both sides anyway so no reader has to know which direction is authoritative — but **a
    one-sided create is not a defect, and needs a failing test before it is filed as one**, which
    three separate audits did not have.
    `CadenceSubtaskInverseParityTests.swiftDataBackPopulatesEitherSideOfANewSubtaskInverse` pins
    the measurement; red there means SwiftData changed and this half became a repair. Both
    measurements: `../../docs/MODELS_AGENTS_REFERENCE.md`, "The two halves of the to-many rule".

- Avoid adding required persisted fields unless you also handle migration/default behavior.
- Store day-level dates as `yyyy-MM-dd` strings. Use `DateFormatters` helpers.
- Keep computed properties side-effect free.
- Relationship inverse behavior matters during deletion. If touching relationships, inspect deletion helpers and any crash reports involving CoreData/SwiftData faults.

## A New `@Model` Needs A CloudKit Console Deploy

SwiftData auto-creates a record type in the **Development** database as a debug build runs; the
**Production** database gets it only when a human presses *Deploy Schema Changes* in the CloudKit
Console. That is owner-only, and Production has been live since 2026-09-05.

**The blast radius is the whole store, not the new type** (T-1294 / R49): a missing Production
schema, a record **type** *or a* **field**, can abort mirroring for every type at once — so an
additive optional property on an already-deployed model is **not** the safer route.

**Schema first, then the writer.** Test the final additive model in Development → deploy its
types, fields and indexes to Production → test there → *then* publish the build that writes it.
`CD_SidebarLayoutPreference` and `CD_LookPreference` are undeployed today; record an owed deploy
in `docs/apple-release-readiness.md`, which is where the owner reads it. **Never take a model back
out of `CadenceSchema` to quieten a red sync test** (T-1294 rejected that by name), and **degrade
to a device-local fallback and add no notice** — nothing can tell "not deployed" from "no row has
synced yet", and `CadenceSidebarLayoutPreferenceStore` (T-1274) is the worked example. TN3164, the
claim it falsifies, the one about CloudKit records that is *not* established, and T-528's two
readings: `../../docs/MODELS_AGENTS_REFERENCE.md`, "Why a new model type needs a Console deploy".

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
  `insert(GoalListLink(...))`. Attach is idempotent, and **detach deletes the row and edits
  nothing** — a pre-commit edit is what Xcode 26's `rollback()` undoes late, so readers filter
  `isDeleted` ([[T-1321]]). What a duplicate link does and does *not* break:
  `../../docs/MODELS_AGENTS_REFERENCE.md`, "The one write path for a goal list link"; the
  substring-grep trap is in `Cadence/Shared/AGENTS.md`.
- `Note` - the single live note model (see below).
- `SavedLink`, `MarkdownImageAsset` - list bookmarks and editor image assets.
- `SidebarLayoutPreference` - the sidebar's visible rows and their order, **synced** (T-1274: the
  owner chose across devices). Two comma-separated `CadenceFeatureDestination` raw-value strings,
  not a to-many. Read and written only through `Shared/CadenceSidebarLayoutPreferenceStore.swift`,
  which owns the duplicate rule (**newest `updatedAt` wins**, `id` breaks a tie, losers are left
  alone rather than deleted), the device-local fallback, and the one-visible-row floor. A
  destination the stored strings never name keeps its declared slot and stays visible, so a future
  enum case needs no migration; an unrecognised token is dropped on read.
- `LookPreference` - the **synced** accent palette, sidebar tints and each surface's sort, grouping
  and show-completed (T-1307, [[T-1288]]). Read only via `CadenceLookPreferenceStore`: the record is
  truth across devices, the local defaults its **mirrors** — how the widget reads the accent.

Non-`@Model` types that live in this folder: `TaskSectionConfig` / `TaskSectionDefaults`
(in `AppTask.swift`) and `GoalContributionSummary`. Two more *files* here declare no type at all —
`GoalPresentation.swift` (an `extension Goal`) and `HabitInsights.swift` (an `extension Habit`,
listed here as a type for a long time; there is no `HabitInsights` symbol to reference) — and two
this list omitted for a long time carry rules of their own:

- **`ModelEnums.swift`** — the ten data enums (`TaskPriority`, `TaskStatus`,
  `TaskRecurrenceRule`, `TaskRecurrenceEndMode`, `ProjectStatus`, `AreaStatus`, `GoalStatus`,
  `GoalKind`, `GoalProgressType`, `HabitFrequency`). Every one is `nonisolated`, and a new one
  must be too: a status enum written without it builds fine in the app and breaks `CadenceWidgets`
  and `CadenceMCPServer`, the second as an error rather than a warning.
  `CadenceTests/NonisolatedValueTypeTests` is the guard.
- **`TaskOrdering.swift`** — `TaskSortField`, `TaskSortDirection`, and `TaskOrdering`, the app's
  one task comparator. It lives here rather than in `Shared/` or `macOS/` because the widget and
  MCP targets order tasks and compile only `Models/`. **The tie-break must stay total**
  (`fallbackPrecedes`: `order` → `createdAt` → `title` → `id`), which `TaskOrderingTests` pins by
  sorting a tie-heavy set from two permutations and requiring byte-identical output. And **the raw
  values are persisted** in `@AppStorage` and per-list `UserDefaults` keys — renaming a case is
  fine, changing a raw value silently resets every saved sort preference. Why a partial order
  reshuffles rows between renders, and what `SWIFT_DEFAULT_ACTOR_ISOLATION` does to a bare value
  type: `../../docs/MODELS_AGENTS_REFERENCE.md`, "Why the enums and the comparator live here".

## The List Calendar Link Is An Identifier, And That Is A Decision

`Area.linkedCalendarID` / `Project.linkedCalendarID` hold a bare `EKCalendar.calendarIdentifier`
and nothing else. T-390 decided that deliberately: EventKit identifiers are treated as opaque and
permanent, so a calendar Apple Calendar deleted and recreated leaves the link **visibly** dead
rather than being re-matched by name, and `CadenceEventNoteSupport` matches `calendarID` exactly.
Adding `linkedCalendarTitle` / `linkedCalendarSource` is a stored-property change on two `@Model`
types with no `SchemaMigrationPlan` behind it, so it is blocked until one exists — do not add it
in passing, and `CadenceEventKitPlatformParityTests` fails if a second `linkedCalendar*` property
appears. Why a broken link the user can see beats auto-rebinding:
`../../docs/MODELS_AGENTS_REFERENCE.md`, "Why the calendar link is a bare identifier".

## Persisted Fields With No Readers

There is no `SchemaMigrationPlan` in this project, so removing a stored property **drops that
column's data** in every existing store — it cleans nothing up. Two fields look like dead code and
must not be deleted: `AppTask.calendarEventID` and `Goal.dependsOnGoalIDsJSON`. A dead-code pass
finds no references, no UI and no tests for either, and that is not evidence. **Re-grep before
describing the first** — the same field name on **`Note`** is live and in use. Which files touch
them and what each one does: `../../docs/MODELS_AGENTS_REFERENCE.md`, "Persisted fields with no
readers", and `docs/CLAUDE_REFERENCE.md`, "Calendar / Events".

## Sections Are Not A Model

A kanban/list section is a `TaskSectionConfig` (uuid, name, colorHex, dueDate, isCompleted,
isArchived) JSON-encoded into `Area.sectionConfigsRaw` / `Project.sectionConfigsRaw`, read back
through the `sectionConfigs` computed property. `AppTask.sectionName` is only the string that
points at one. The legacy `sectionNamesRaw` is the pre-config fallback the getter migrates from.
Never hand-edit the raw strings; go through `sectionConfigs`.

**The Default column has no lifecycle, and that is a model rule, not a UI preference.**
`Area.normalizedSectionConfigs` / `Project.normalizedSectionConfigs` force `isCompleted` and
`isArchived` false on the column named `Default` on **every read and every write**, because a
completed-or-archived Default would be an invisible bucket still collecting every new task in the
list. Ask `TaskSectionConfig.supportsLifecycle` before offering a column a Complete or Archive
control. Offering one anyway is not a no-op, and what it did on macOS's kanban column is in
`../../docs/MODELS_AGENTS_REFERENCE.md`, "Why the Default column has no lifecycle".

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
