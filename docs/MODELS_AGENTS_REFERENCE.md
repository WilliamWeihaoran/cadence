# Models Agent Reference

This is prose lifted out of `Cadence/Models/AGENTS.md`, preserved so no model detail is lost while
the active scoped guide stays under its 199-line context budget
(`CadenceTests/AgentContextBudgetTests.swift`). Nothing here is new: every section below stood in
the guide verbatim until the guide reached 199 lines of 199 and T-1391 displaced it.
Do not load this whole file by default; the guide names the section you need where it needs it.

The guide keeps the rule. This file keeps the measurement, the incident and the argument — the
three things an agent needs only when changing the behaviour, not when obeying it.

## The Two Halves Of The To-Many Rule

_Displaced verbatim from `Cadence/Models/AGENTS.md` on 2026-09-26 (T-1391). The rule stays in
the guide; the measurement, the incident and the argument are here._

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

## Why A New Model Type Needs A Console Deploy

_Displaced verbatim from `Cadence/Models/AGENTS.md` on 2026-09-26 (T-1391). The rule stays in
the guide; the measurement, the incident and the argument are here._

SwiftData auto-creates a record type in the **Development** database as a debug build runs; the
**Production** database gets it only when a human presses *Deploy Schema Changes* in the CloudKit
Console. That is owner-only, and Production has been live since 2026-09-05.

**The blast radius is the whole store, not the new type.** This section used to say the type
"silently does not sync while every older type syncs normally"; Apple's TN3164 falsifies that — a
missing Production schema, a record **type** *or a* **field**, can fail mirroring *initialisation*
and abort exports for every type at once (T-1294 / R49). So an additive optional property on an
already-deployed model is **not** the safer route: a new field is the same mismatch one level down.

**Schema first, then the writer.** Test the final additive model in Development → deploy its types,
fields and indexes to Production → test there → *then* publish the build that writes it. Deployment
copies schema, not records, so a deployed schema with no shipped writer is the state to pass through
rather than a compromise. `CD_SidebarLayoutPreference` and `CD_LookPreference` are undeployed today.
Record an owed deploy in `docs/apple-release-readiness.md`, which is where the owner reads it.

**Never take a model back out of `CadenceSchema` to quieten a red sync test** (T-1294 rejected that
by name). For a type in use it risks local migration failure and rows the app can no longer reach;
that it *also* deletes the CloudKit records is **not** established — do not repeat "destroys data".

**Degrade to a device-local fallback and add no notice.** Nothing can tell "not deployed" from "no
row has synced yet" — also every new device for the first seconds of every CloudKit launch (T-528's
two readings). `CadenceSidebarLayoutPreferenceStore` (T-1274) is the worked example, its tests pin
it, and T-1290 is why.

## The One Write Path For A Goal List Link

_Displaced verbatim from `Cadence/Models/AGENTS.md` on 2026-09-26 (T-1391). The rule stays in
the guide; the measurement, the incident and the argument are here._

  **`GoalListLink` has one write path** — `ModelContext.attachList` / `detachGoalListLink` /
  `toggleGoalListLink` in `Shared/GoalListLinkHelpers.swift`, never a hand-rolled
  `insert(GoalListLink(...))`. Attach is idempotent — but **not** because a duplicate link
  double-counts that list's tasks in the goal's progress. It cannot: `contributingTasks` ends in
  `dedupe(...)`, which filters by task `id`. What a duplicate breaks is everything counting
  *links* — `linkedListCount`, the "N lists" chip, the attribution line, two MCP DTOs, and a second
  identical row in both inspectors. **Detach deletes the row and edits nothing** — a pre-commit edit is what Xcode 26's
  `rollback()` undoes late, so readers filter `isDeleted` ([[T-1321]]). Rationale and the substring-grep trap: `Cadence/Shared/AGENTS.md`.

## Why The Enums And The Comparator Live Here

_Displaced verbatim from `Cadence/Models/AGENTS.md` on 2026-09-26 (T-1391). The rule stays in
the guide; the measurement, the incident and the argument are here._

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

## Why The Calendar Link Is A Bare Identifier

_Displaced verbatim from `Cadence/Models/AGENTS.md` on 2026-09-26 (T-1391). The rule stays in
the guide; the measurement, the incident and the argument are here._

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

_Displaced verbatim from `Cadence/Models/AGENTS.md` on 2026-09-26 (T-1391). The rule stays in
the guide; the measurement, the incident and the argument are here._

There is no `SchemaMigrationPlan` in this project, so removing a stored property **drops that
column's data** in every existing store — it cleans nothing up. Two fields look like dead code and
must not be deleted: `AppTask.calendarEventID`, which exactly three files touch and **all three
only ever assign `""`**, for values an earlier build left on disk and in CloudKit; and
`Goal.dependsOnGoalIDsJSON`, zero readers and zero writers, accessor already removed, tombstone
comment in `macOS/Views/GoalsSupportViews.swift`. A dead-code pass finds no references, no UI and
no tests for either, and that is not evidence. **Re-grep before describing the first** — the same
field name on **`Note`** is live and in use — and read the three files, and the two claims
`1d81864` corrected about them, in `docs/CLAUDE_REFERENCE.md`, "Calendar / Events".

## Why The Default Column Has No Lifecycle

_Displaced verbatim from `Cadence/Models/AGENTS.md` on 2026-09-26 (T-1391). The rule stays in
the guide; the measurement, the incident and the argument are here._

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
