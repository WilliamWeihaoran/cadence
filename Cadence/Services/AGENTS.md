# Services Guide

This folder contains shared app services and persistence-adjacent support (50 top-level `.swift`
files at the time of writing — `ls Cadence/Services/*.swift | wc -l` — plus `AI/` and `MCPReadOnly/`). It is cross-platform: macOS-only managers live in `Cadence/macOS/Services/`.

## Families

- **Schema/persistence** - `CadenceSchema.swift`, `CadenceStoreSupport.swift`, `PersistenceController.swift` (legacy shim that also kicks off migrations).
- **Migration/repair** - `NoteMigrationService.swift` (legacy note models -> `Note`), `PursuitToGoalMigration.swift`, `DataIntegrityRepairService.swift`.
- **Markdown** - 27 `Markdown*.swift` files, 25 of them named `*Support.swift` (the other two are `MarkdownImageAssetService.swift` and `MarkdownPreviewParser.swift`). Re-count when you add one; the glob and the number have disagreed here before. **This is where markdown logic lives, not `macOS/Editor/`** — parsing, attributed-string building, list/quote/checklist rules, typing transforms, backspace and line-break behavior, slash-command core, link/reference/task-embed support, inline preview, image assets. The `macOS/Editor/` files are the AppKit bridge that calls into these.
- **Notes/tags/tasks** - `MarkdownNoteSupport.swift`, `NoteReferenceSupport.swift`, `TagSupport.swift`, `TaskCreationService.swift`.
- **Notifications** - `NotificationScheduling.swift` (pure planner) + `NotificationManager.swift` (reconciler). Stateless reconciliation, not schedule-on-mutation.
- **Privacy data reset** - `CadencePrivacyDataResetService.swift` (prefixed file, unprefixed `PrivacyDataResetService` type — the old `macOS/Services/` path keeps a tombstone under the unprefixed name). Wipes every model in `CadenceSchema`, including the legacy note types and `Pursuit`, and cancels pending Cadence notifications; `deleteCadenceDataAndLocalArtifacts` adds the OpenAI key, the widget snapshot, the pending restore and the local backups, and is the one sequence **both** Settings > Data Safety screens run. **Add a new `@Model` here whenever you add one to `CadenceSchema`** — `CadencePrivacyDataResetSurfaceTests` drives the coverage check off the schema, so it fails if you don't. Same story as reminders below: it sat under `macOS/Services/` behind an `#if os(macOS)` while importing only Foundation and SwiftData, and the shipped privacy policy promised iOS a deletion route that did not exist.
- **List/context deletion** - `CadenceListDeleteHelpers.swift` (prefixed file, unprefixed
  `ListDeleteHelpers` name on the `ModelContext` extension it declares). `deleteContext`,
  `deleteArea` and `deleteProject` — the recursive cascades that take a list's tasks, notes, links,
  goal links, image assets and nested projects with it. Moved here from `macOS/Services/` by
  `c84732e`, which is what let iOS delete a list or a context at all. **One `#if os(macOS)` seam
  and no more**, in `cascadeDeleteTasks(withIDs:)`: `ModelContext.deleteTasks(withIDs:)` really is
  macOS-only (it tears down the focus, hover, completion-animation and subtask-entry managers), so
  iOS calls the shared `CadenceTaskMutationSupport.deleteTasks(withIDs:modelContext:)` core
  directly. `CadenceListDeletionSurfaceTests.theCascadesLiveInServicesWithExactlyOnePlatformSeam`
  counts the `#if` directives in the file and fails at two. The user-facing copy is
  `Shared/CadenceListDeletionSummary.swift`, and it is **two types with two audiences**:
  `CadenceListDeletionKind.cascadeSentence` is the categorical sentence read by five macOS dialog
  sites (`EditListSheet` x2, `SettingsView` x3) *and* iOS, so that copy cannot drift; the
  `CadenceListDeletionSummary` counts ("1 project", "7 tasks") are read by iOS alone, because
  macOS's dialog reports scope categorically and cannot state a number.
- **Container wind-down** - `CadenceTaskContainerLifecycleService.swift` (prefixed file, unprefixed
  `TaskContainerLifecycleService` type). Completing or archiving an area, a project or a kanban
  column settles the work still open inside it. It lived in `macOS/Services/TaskWorkflowService.swift`
  behind that file's `#if os(macOS)` until T-215 while importing only Foundation, SwiftData, the
  models and `CadenceTaskRecurrenceWorkflowSupport` — the sixth instance of the shape the three
  tombstones in `macOS/Services/` record — and the guard is what left iOS's list archive a bare
  `status = .archived` while macOS's cancelled the list's remaining active tasks. It settles through
  `CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries` and **must not** be rerouted
  through `markDone` / `markCancelled` / `applyStatusCompletion`: those spawn the next recurrence
  occurrence into the same area, project and section, so a wind-down would refill the container it
  just closed (T-213, T-214). `remainingActiveTasks(...)` is public so a confirmation can count
  before the fact from the *same* array the settle walks; `CadenceContainerWindDownSummary` in the
  same file is that count plus its one sentence, and it is what
  `Cadence/iOS/iOSListArchiveSupport.swift` and `Cadence/iOS/iOSColumnWindDownSupport.swift` read.
  That struct was `CadenceListArchiveSummary` until T-247 gave the kanban column the same confirmed
  action, which needed the identical four members with one word changed — hence the `outcome`
  dimension (`CadenceWindDownOutcome.cancelled` / `.done`) rather than a second struct beside it. It is deliberately **not** in `Shared/`: this is a persistence mutation, and
  `Shared/CadenceTaskRecurrenceWorkflowSupport.swift` compiles into `CadenceWidgets` and
  `CadenceMCPServer`, which have no business with a bulk container wind-down.
  Since T-241 the settle also **reconciles notifications** for the batch, which is what finally
  makes the `in context:` parameters on all six entry points load-bearing — they were declared and
  unread from T-212 until then. It goes through an injected `CadenceWindDownReconciler` rather than
  calling `HabitNotificationReconcileSupport.scheduleReconcile` directly: that helper spawns an
  unstructured `Task` doing two full-store fetches into the `@MainActor` `NotificationManager`, so
  an unconditional call would have handed eighteen existing wind-down tests async work outliving
  their bodies. `nil` (the default) resolves to `.live` in the app and `.inert` under
  `NotificationManager.isTestEnvironment`; a test proves the wiring by injecting a recorder, which
  is why deleting the call is a red test and not a silent regression.

- **EventKit reminders** - `CadenceRemindersManager.swift` (prefixed file, unprefixed `RemindersManager` type — the old path keeps a tombstone under the unprefixed name). Separately authorized from calendar, and cross-platform: both platforms read it in the Inbox and in Settings -> Reminders. It lived under `macOS/Services/` behind an `#if os(macOS)` for a long time despite touching no AppKit. Its pure presentation half (`RemindersConnectionState`, `RemindersSyncSummary`) is in `Shared/CadenceRemindersPresentationSupport.swift`, where `CadenceTests` can reach it.
- **Widgets** - `Cadence*WidgetSupport.swift`, `CadenceWidgetIntents.swift`, `CadenceWidgetRefreshCenter.swift`, `CadenceDeepLink.swift`. These compile into the `CadenceWidgets` target too.
- **`AI/`** - `AIActionService.swift`, `AIProvider.swift`, `AISettingsManager.swift`. Optional, user-supplied OpenAI key.
- **`MCPReadOnly/`** - read/write services, DTOs, search matcher, audit log, container factory backing the MCP surface.

## Boundaries

- `CadenceSchema.swift` is the canonical schema list. Update it only with matching model intent.
- `PersistenceController.swift` is legacy/compatibility support; SwiftData is the primary persistence path.
- Migration and repair services should be deterministic, idempotent, and conservative.
- Markdown/note services should avoid blocking UI flows and should prefer structured parsing/helpers over ad hoc string edits when possible.
- `MCPReadOnly/` is integration-facing **and compiles into two targets** — the app and
  `CadenceMCPServer`, the latter on Swift 6 without `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  This line used to say "do not edit it unless the task explicitly asks for MCP/read-only API
  work", which contradicted `Models/AGENTS.md`'s correct instruction to *check any read-only API
  or export surface that mirrors models* for the same edit — and the model changes that skipped it
  shipped stale response schemas. When a model or a shared service you touch is mirrored here,
  update it and verify it: build the `CadenceMCPServer` scheme into a private `-derivedDataPath`
  and grep the log. What still holds is the narrower rule: do not *redesign* the tool surface or
  the response DTOs as a side effect of app work. See `CadenceMCPServer/AGENTS.md`.

## Risk Notes

- Deletion and repair flows can trigger SwiftData/CoreData fault crashes if stale relationships are touched after a model is deleted.
- Calendar/task/note references may store external identifiers; handle missing targets gracefully.
- AI provider settings are user configuration. Avoid logging secrets or persisting transient request data.

## Verification

Run the macOS build after touching shared services. Add focused tests if changing migration, deletion, or parsing behavior.
