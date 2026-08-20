# Services Guide

This folder contains shared app services and persistence-adjacent support (~41 files plus two
subfolders). It is cross-platform: macOS-only managers live in `Cadence/macOS/Services/`.

## Families

- **Schema/persistence** - `CadenceSchema.swift`, `CadenceStoreSupport.swift`, `PersistenceController.swift` (legacy shim that also kicks off migrations).
- **Migration/repair** - `NoteMigrationService.swift` (legacy note models -> `Note`), `PursuitToGoalMigration.swift`, `DataIntegrityRepairService.swift`.
- **Markdown** - ~21 `Markdown*Support.swift` files. **This is where markdown logic lives, not `macOS/Editor/`** — parsing, attributed-string building, list/quote/checklist rules, typing transforms, backspace and line-break behavior, slash-command core, link/reference/task-embed support, inline preview, image assets. The `macOS/Editor/` files are the AppKit bridge that calls into these.
- **Notes/tags/tasks** - `MarkdownNoteSupport.swift`, `NoteReferenceSupport.swift`, `TagSupport.swift`, `TaskCreationService.swift`.
- **Notifications** - `NotificationScheduling.swift` (pure planner) + `NotificationManager.swift` (reconciler). Stateless reconciliation, not schedule-on-mutation.
- **EventKit reminders** - `CadenceRemindersManager.swift` (prefixed file, unprefixed `RemindersManager` type — the old path keeps a tombstone under the unprefixed name). Separately authorized from calendar, and cross-platform: macOS reads it in the Inbox and in Settings -> Reminders, iOS in Settings -> Reminders only. It lived under `macOS/Services/` behind an `#if os(macOS)` for a long time despite touching no AppKit. Its pure presentation half (`RemindersConnectionState`, `RemindersSyncSummary`) is in `Shared/CadenceRemindersPresentationSupport.swift`, where `CadenceTests` can reach it.
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
