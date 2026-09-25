# Services Guide

This folder contains shared app services and persistence-adjacent support (62 top-level `.swift`
files at the time of writing — `ls Cadence/Services/*.swift | wc -l` — plus `AI/` and `MCPReadOnly/`). It is cross-platform: macOS-only managers live in `Cadence/macOS/Services/`.

The rules are here. The measurements, the incidents and the arguments behind them are in
`../../docs/SERVICES_AGENTS_REFERENCE.md`, one section per bullet below, named where it is needed.
Open a section when you are about to change the behaviour it explains, not to obey the rule.

## Families

- **Schema/persistence** - `CadenceSchema.swift`, `CadenceStoreSupport.swift`, `PersistenceController.swift` (legacy shim that also kicks off migrations). **A startup failure's reason goes through `PersistenceController.storeFailureReason(_:)`, never through `error.localizedDescription` directly** (T-1319): a `ModelContainer` that will not open throws one identical `SwiftData.SwiftDataError` sentence for **every** cause, the real one reachable only by reflection into `_underlyingCocoaError`. All five startup sentences (primary open, preflight, recovery, in-memory, maintenance save) share that extractor. Measurement: reference, "Why The Store-Failure Reason Goes Through An Extractor".
- **Silent-push registration** - `CadenceRemoteNotificationRegistrar.swift`. The one place the app asks either platform to subscribe to CloudKit's pushes, so there is exactly one `registerForRemoteNotifications()` call site in the tree; each platform's app delegate calls it once at launch and nothing else may, and a second `#if`-guarded body here is the regression `CadenceLaunchWiringTests` is built to catch (T-626). A refusal lands in `CadencePushRegistrationMonitor` in the same file and **degrades the Settings > iCloud Sync card on both platforms** rather than only logging (T-1309). The entitlement is per-platform: `Cadence/Cadence-iOS.entitlements` carries the bare `aps-environment`, `Cadence/Cadence.entitlements` the `com.apple.developer.` spelling, and the two files must otherwise stay identical. Reference: "Silent-Push Registration, And The Build With No Entitlement".
- **Migration/repair** - `NoteMigrationService.swift` (legacy note models -> `Note`), `PursuitToGoalMigration.swift`, `DataIntegrityRepairService.swift`.
- **Markdown** - 30 `Markdown*.swift` files plus `CadenceMarkdownSourceInventory.swift`, which does not match the glob. **Re-count when you add one**; the glob and the number have disagreed here before. **This is where markdown logic lives, not `macOS/Editor/`** — parsing, attributed-string building, list/quote/checklist rules, typing transforms, backspace and line-break behavior, slash-command core, link/reference/task-embed support, inline preview, image assets. The `macOS/Editor/` files are the AppKit bridge that calls into these. Reference: "The Markdown File Count, And Why It Is Re-Counted".
- **Markdown image lifecycle** - `CadenceMarkdownSourceInventory.swift` enumerates every stored field in `CadenceSchema` that can hold markdown, and it is the *only* answer to "what still references this image". `ModelContext.deleteUnreferencedMarkdownImageAssets` reads it; nothing else should re-derive the set. **Adding a markdown-bearing field to a model means adding a `Source` case** — the reader switches exhaustively, and `CadenceMarkdownSourceInventoryTests` fails on any stored `String` in `Cadence/Models/` that is neither in the inventory nor declared plain. Use `MarkdownImageAssetService.referencedIDs` (unanchored) for lifecycle questions and `standaloneReferencedIDs` (anchored) only for rendering; over-counting defers garbage, under-counting destroys a picture. Reference: "The Markdown Image Lifecycle Sweep" (T-411).
- **Notes/tags/tasks** - `MarkdownNoteSupport.swift`, `NoteReferenceSupport.swift`, `TagSupport.swift`, `TaskCreationService.swift`. **A pass that resolves tags for many rows reads the `Tag` table once and hands a `TagSlugIndex` down** (T-1314); `TagSupport.resolution`'s `index:` parameter is that, and left `nil` it reads the table itself, which is right for the one-name-at-a-time pickers and was catastrophic for the launch sweep. Two tests hold it. Reference: "The Tag Slug Index, Measured" — quadratic to linear, 694.5s to 0.741s.
- **Notifications** - `NotificationScheduling.swift` (pure planner) + `NotificationManager.swift` (reconciler). Stateless reconciliation, not schedule-on-mutation.
- **Privacy data reset** - `CadencePrivacyDataResetService.swift` (prefixed file, unprefixed `PrivacyDataResetService` type). Wipes every model in `CadenceSchema` and cancels pending Cadence notifications; `deleteCadenceDataAndLocalArtifacts` adds the OpenAI key, the widget snapshot, the pending restore and the local backups, and is the one sequence **both** Settings > Data Safety screens run. **Add a new `@Model` here whenever you add one to `CadenceSchema`** — `CadencePrivacyDataResetSurfaceTests` drives the coverage check off the schema. **Two failure rules, both load-bearing to a claim the app makes about deletion**: the store sweep commits through `CadencePendingChangePersistence.commitDelete(in:commit:building:)` so a refusal leaves the shared context where it was (T-1102), and the OpenAI key deletion is **reported, not swallowed**, through `PrivacyDataResetOutcome.retainedAPIKeyReason` (T-1101). Reference: "Privacy Data Reset: Two Failure Rules".
- **Data export** - `CadenceDataExportService.swift`. The *other* half of data safety, and the one
  `StoreBackupManager` does not cover. One JSON archive of **every** entity in `CadenceSchema` —
  relationships as id references, image bytes as base64, ISO-8601 dates, pretty-printed with sorted
  keys so two exports diff. **Add a new `@Model` here whenever you add one to `CadenceSchema`**, the
  same standing rule as the reset above and enforced the same way by
  `CadenceDataExportSurfaceTests`. **A new `Date` field on a record goes through
  `CadenceArchiveTimestamp.normalized(_:)`**, not straight from the model: the archive's stated
  precision is the **millisecond** (`DateFormatters.archiveTimestamp`) and stock `.iso8601` writes
  whole seconds, which shipped once and broke `TaskOrdering`'s `createdAt` tie-break.
  `everyTimestampInTheArchiveIsAtTheArchivesPrecision` names the field that skipped it.
  `exportArchive(in:)` is the one call both Settings > Data Safety screens make; the copy they show
  is `Shared/CadenceDataExportPresentation.swift`. **Import shipped** with T-274/T-1082:
  `CadenceArchiveImportService.importArchive`/`.apply`, surfaced by
  `Shared/CadenceArchiveImportPresentation.swift`; it restores `linkedCalendarID` verbatim and its
  preview counts those links (T-1084). Keep that warning: a CloudKit restore is not a local write.
  Reference: "Data Export: The Archive Timestamp, And Import".
- **List/context deletion** - `CadenceListDeleteHelpers.swift` (prefixed file, unprefixed
  `ListDeleteHelpers` name on the `ModelContext` extension it declares). `deleteContext`,
  `deleteArea` and `deleteProject` — the recursive cascades that take a list's tasks, notes, links,
  goal links, image assets and nested projects with it. **One `#if os(macOS)` seam and no more**, in
  `cascadeDeleteTasks(withIDs:)`; `CadenceListDeletionSurfaceTests.theCascadesLiveInServicesWithExactlyOnePlatformSeam`
  counts the directives and fails at two. The user-facing copy is
  `Shared/CadenceListDeletionSummary.swift`, **two types with two audiences**:
  `CadenceListDeletionKind.cascadeSentence` is read by five macOS dialog sites *and* iOS so that
  copy cannot drift, while the `CadenceListDeletionSummary` counts are read by iOS alone.
  **A cascade reaching an object through its container may not take more than the cascade aimed at
  that object directly** (T-1312). Goal **nesting** is the one decided exception (T-1324):
  `deleteGoal` walks `subGoals` with no container filter while `deleteContext` deletes
  `context.goals` alone. `CadenceListDeletionSummary` mirrors these legs and moves with them.
  Reference: "List And Context Deletion Cascades" — both readings, and why they are not the same
  question.
- **Container wind-down** - `CadenceTaskContainerLifecycleService.swift` (prefixed file, unprefixed
  `TaskContainerLifecycleService` type). Completing or archiving an area, a project or a kanban
  column settles the work still open inside it. It settles through
  `CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries` and **must not** be rerouted
  through `markDone` / `markCancelled` / `applyStatusCompletion`: those spawn the next recurrence
  occurrence into the same area, project and section, so a wind-down would refill the container it
  just closed (T-213, T-214). `remainingActiveTasks(...)` is public so a confirmation can count
  before the fact from the *same* array the settle walks; `CadenceContainerWindDownSummary` in the
  same file is that count plus its one sentence, read by `Cadence/iOS/iOSListWindDownSupport.swift`
  and `Cadence/iOS/iOSColumnWindDownSupport.swift`. All three factories — `forArea`, `forProject`,
  `forColumn` — take the `outcome` (`CadenceWindDownOutcome.cancelled` / `.done`) as a **required**
  argument since T-214; a default there is how a completion comes to promise "cancelled" over a
  correct number. It is deliberately **not** in `Shared/`: this is a persistence mutation, and
  `Shared/CadenceTaskRecurrenceWorkflowSupport.swift` compiles into `CadenceWidgets` and
  `CadenceMCPServer`. Since T-241 the settle also **reconciles notifications** for the batch through
  an injected `CadenceWindDownReconciler` (`nil` resolves to `.live`, or `.inert` under
  `NotificationManager.isTestEnvironment`), which is what makes the `in context:` parameters
  load-bearing; deleting the call is a red test. Reference: "Container Wind-Down".
- **EventKit reminders** - `CadenceRemindersManager.swift` (prefixed file, unprefixed `RemindersManager` type — the old path keeps a tombstone under the unprefixed name). Separately authorized from calendar, and cross-platform: both platforms read it in the Inbox and in Settings -> Reminders. Its pure presentation half (`RemindersConnectionState`, `RemindersSyncSummary`) is in `Shared/CadenceRemindersPresentationSupport.swift`, where `CadenceTests` can reach it. Reference: "EventKit Reminders Lived Behind An `#if os(macOS)`".
- **Widgets** - `Cadence*WidgetSupport.swift`, `CadenceWidgetIntents.swift`, `CadenceWidgetRefreshCenter.swift`, `CadenceDeepLink.swift`. These compile into the `CadenceWidgets` target too.
- **`AI/`** - `AIActionService.swift`, `AIProvider.swift`, `AISettingsManager.swift`. Optional, user-supplied OpenAI key.
- **`MCPReadOnly/`** - read/write services, DTOs, search matcher, audit log, container factory backing the MCP surface.

## Boundaries

- `CadenceSchema.swift` is the canonical schema list. Update it only with matching model intent.
- `PersistenceController.swift` is legacy/compatibility support; SwiftData is the primary persistence path.
- `CadenceStoreSupport.makeSharedWriteContainer` is the **only** write-capable open of the
  app-group store outside `PersistenceController`'s startup, because a write-capable open *creates*
  a missing store and could skip the legacy migration permanently (T-311). The gate refuses rather
  than migrating. Reference: "The Shared Write-Capable Container Gate".
- Migration and repair services should be deterministic, idempotent, and conservative.
- Markdown/note services should avoid blocking UI flows and should prefer structured parsing/helpers over ad hoc string edits when possible.
- `MCPReadOnly/` is integration-facing **and compiles into two targets** — the app and
  `CadenceMCPServer`, the latter on Swift 6 without `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  **When a model or a shared service you touch is mirrored here, update it and verify it**: build
  the `CadenceMCPServer` scheme into a private `-derivedDataPath` and grep the log. Do not *redesign*
  the tool surface or the response DTOs as a side effect of app work. This bullet used to forbid
  touching it at all, which contradicted `Models/AGENTS.md` and shipped stale response schemas;
  reference, the section on why that prohibition was wrong. See `CadenceMCPServer/AGENTS.md`.

## Risk Notes

- Deletion and repair flows can trigger SwiftData/CoreData fault crashes if stale relationships are touched after a model is deleted.
- Calendar/task/note references may store external identifiers; handle missing targets gracefully.
- AI provider settings are user configuration. Avoid logging secrets or persisting transient request data.

## Verification

Run the macOS build after touching shared services. Add focused tests if changing migration, deletion, or parsing behavior.
