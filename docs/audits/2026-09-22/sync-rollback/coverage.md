# R64: What Actually Syncs?

```text
Tree read: d819a4c
Dirty files: 1 at start; committed snapshot used, dirty performance probe excluded
Coverage: all model declarations, main/shared store configurations, preference bridges,
          defaults/file/keychain write-site census, relevant readers and tests
No runtime sync, Production console, signed-artifact, or device verification
```

## Verdict

**MEASURED-SOURCE:** all 23 `@Model` types are explicitly present in
[`CadenceSchema.swift:4`](../../../../Cadence/Services/CadenceSchema.swift#L4). This includes unified
notes, legacy notes, task notes, image bytes, tags, goals, habits/completions, focus logs, saved links,
and the two preference records. There is no missing model registration to fix in this tree.

**Not all user-authored data is modeled:** customized note templates remain in device-local defaults.
That is the clearest coverage gap relative to the owner's new question. Geometry/navigation and
credentials have different reasons to stay local and should not be swept into sync indiscriminately.

**Cannot certify arrival from source.** The reported September 22 Production deploy is request
context, not something inspected here. Model membership establishes intended coverage, not whether
the owner's current devices have exported/imported every row, field, or asset.

## Field And Constraint Check

The [complete inventory](model-fields.md) enumerates every stored field with type and source line.
The [source inventory](model_inventory.rb) measured **256 stored declarations: 194 attributes,
62 relationship endpoints, 33 to-many endpoints**. Every stored declaration has a default; all
relationships are optional; all to-many fields are optional arrays. No model uses `@Transient`,
`.unique`, or `.deny`. All 31 relationship pairs have a source counterpart; 30 pairs explicitly
name their inverse at one end. The remaining pair is `AppTask.subtasks` / `Subtask.parentTask`,
both optional and unambiguous in source. Generated macro/Core Data metadata was not inspected.

**Premise correction:** Apple permits SwiftData to infer an inverse reliably; an explicit annotation
at every relationship declaration is not required. Therefore the Subtask pair is not a demonstrated
CloudKit defect and should not be changed reflexively in a deployed schema. This is a source
registration check, not an inspection of the effective generated schema. No type absence exists
here. [Apple sync guide](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices),
[ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer).

The same guide requires optional relationships, disallows unique constraints and deny deletion for
CloudKit, and requires promoting the schema before release. A bad configuration can prevent opening
or initializing mirroring, not merely reject one model's export. This audit respects the repo's
additive-only constraint; it proposes no migration plan or destructive schema change.

## Write Routes

| Route | What the source establishes |
|---|---|
| Normal Mac/iPhone/iPad app | `PersistenceController.swift:274` uses the complete schema and private `iCloud.com.haoranwei.Cadence`. `CadenceApp.swift:90,106` attaches the look bridge inside the same container on both platforms. |
| Widgets and App Intents | `CadenceStoreSupport.swift:66,128` opens the same app-group store, defaulting to `.none`. `CadenceWidgetIntents.swift:75,130,201` uses that gate. These are local writes to the app's replica, not a second unrelated database; the main app's mirroring must subsequently export them. No immediate cross-device delivery is promised. |
| MCP default store | `CadenceModelContainerFactory.swift:69,81` opens the shared schema/store with `.none`; `:111` permits an explicit store override. Writes to an override are not writes to the owner's synced replica. |
| Recovery | `PersistenceController.swift:283` creates a separate local recovery store; `:300` can fall back to memory. Rows entered there are not automatically shipped into the normal synced store. Recovery is surfaced, not a silent alternate sync route. |
| Local-only test/diagnostic configuration | `PersistenceController.swift:264` selects `.none`. Check the running configuration before calling a failure to sync a coverage defect. |
| Push setup | `project.pbxproj:760,802` selects the iOS entitlement file; `Cadence-iOS.entitlements:16` has bare `aps-environment`, macOS's file `:18` has its platform key. This confirms source routing, not the signed archive or delivery. |

An app-group directory is shared between processes **on one device**, not a cloud filesystem.
CloudKit's scheduling and local-store replication are separate from that sharing. Read-only widget
loads do not pull a complete remote database on demand. [Apple synchronization overview](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer).

## Outside The Synced Models

| Data | Current destination and interpretation |
|---|---|
| Customized template title/subtitle/body | `MarkdownNoteSupport.swift:10,17,64`; `iOSSettingsView.swift:14,237`; macOS `SettingsView.swift:23,212`: JSON in `noteTemplateOverrides`, via local defaults. **User content, not merely layout. Not synced.** |
| Accent and sidebar tint | `LookPreference` is authoritative across devices. `CadenceLookPreferenceSync.swift:62,72,77` adopts into local/app-group mirrors; `:116` publishes local changes. Both roots are wired. |
| Sidebar order/hidden destinations | `SidebarLayoutPreference`; queried by `iOSRootSidebar.swift:145,187` and `SidebarView.swift:29,270`, written by both settings surfaces. Not just local defaults anymore. |
| Task sort/group/show-completed | Exactly the 7 Mac and 8 iOS mirror mappings in `CadenceLookPreferenceStore.swift:163`, not every sort key in the app. Unknown/platform-only record pairs are preserved. |
| Mac per-list task/kanban sorts | Local ID-keyed keys at `ListDetailView.swift:394,397,412,415,418`; deliberately excluded at `CadenceLookPreferenceStore.swift:160`. iOS's global list-detail sort is a different setting. **Known scope difference**, not evidence the bridge is absent. |
| Work hours | Local keys `calendar.workHours.startMinute.v1` / `.endMinute.v1`, `CalendarWorkHoursPreferences.swift:22`; both settings surfaces write them. **Decision needed:** personal working hours may deserve sync, unlike canvas geometry; current owner intent alone does not settle it. |
| Calendar visibility/ID observations | Local `calendar.hiddenCalendarIDs.v1`, `CadenceCalendarVisibilityPreferences.swift:4`, and observed IDs at `CadenceCalendarLinkObservations.swift:112`. Account availability and local permissions can differ. Do not blindly copy raw IDs to solve calendar parity. |
| Navigation/geometry | Local selected tabs, task scope, side panel, collapsed groups, sidebar width, zoom, month detail, remembered dates/hours, default list page and note folds. Examples: `iOSRootView.swift:45`, `iOSCalendarView.swift:15`, `macOSRootShellViews.swift:11`, `ListDetailView.swift:391`, `CadenceNotesListSupport.swift:763`. This is consistent with different per-device layouts. |
| AI credential/model | `AISettingsManager.swift:48,58` uses ThisDeviceOnly Keychain accessibility and no synchronizable attribute; model selection is local at `:96,106`. **Intentional security boundary:** set up each device; do not sync secrets through a new model. |
| App Sign in with Apple profile | Local defaults, `AppleAccountManager.swift:34,58`. This is not the device's iCloud login and is not what selects the CloudKit account. |
| Notification authorization/pending requests | OS/device-owned; `notificationsEnabled` is local, `NotificationManager.swift:18,83`. Habit reminder times and task schedule fields are modeled, but each device must authorize/reconcile its own notifications. |
| Active focus timer | In memory, `FocusManager.swift:16,35` and `iOSFocusView.swift:16,20`. **No live session handoff**; committed `FocusSessionLog` and counters are modeled and eligible to sync. |
| Backups/exports/repair reports/MCP logs | Local or user-chosen files, not CloudKit model rows: `PersistenceController.swift:763,893,1209`, `NoteExportService.swift:40,50`, `NoteMigrationService.swift:608`, `DataIntegrityRepairService.swift:961`, `CadenceMCPAuditLog.swift:38`. A destination the user separately syncs is outside Cadence's model pipeline. |
| Widget reload/tap markers | Local app-group defaults/files: `CadenceWidgetRefreshCenter.swift:32,153,206`, `CadenceStoreSupport.swift:150,226`. Transport/cache coordination, not missing user content. |
| EventKit calendars/events/reminders | EventKit/provider-owned, not replicated as complete events by Cadence. Synced task/note calendar identifiers are strings pointing at external objects; a copied string does not prove that another device can resolve it. |

Embedded images are the important counterexample to "files do not sync":
`MarkdownImageAsset.swift:6` stores bytes as a model attribute with `.externalStorage`, and
`MarkdownImageAssetService.swift:143,333,403` embeds UUID references and inserts the asset.
The external storage option describes on-disk placement; it does not make the attribute transient.
Remote HTTP links and arbitrary `file:` links in markdown are references, not uploaded file copies.
[Apple externalStorage](https://developer.apple.com/documentation/swiftdata/schema/attribute/option/externalstorage).

## Actions, Ranked

### P2: Customized Templates Do Not Follow The Notes

**MEASURED-SOURCE; reachable today.** Edit a template in either platform's Settings. The new title,
subtitle and body go to local `noteTemplateOverrides`; neither preference model nor the mirror
allowlist transports them. A fresh device uses built-in templates. Applying the template into a
saved note is different: the resulting `Note.content` is modeled and eligible to sync.

Suggested fix **if the owner wants this content shared:** a dedicated additive template-override
record keyed by stable template ID, with explicit reset/tombstone semantics, timestamps and a
deterministic duplicate policy. Reuse the preference-store committed-write pattern, not its short
semicolon grammar for arbitrary markdown. Preserve local overrides until adoption is verified;
avoid three devices blindly seeding defaults or overwriting genuine customizations on first import.
Add defaulted fields/new model only through the normal schema/deploy/archive/reset coverage review.
Do not silently widen `LookPreference.taskPresentationRaw` into a content store.

Tests to request: edit/adopt round-trip with multiline markdown and empty body; offline duplicate
override; reset racing an edit; local override present before first remote row. Existing semantic
pattern: `NoteTemplateLibrary.resolved` and the deterministic preference winner.

```sh
rg -n 'noteTemplateOverrides|NoteTemplateLibrary.storageKey' Cadence
rg -n 'template|Template' Cadence/Models/LookPreference.swift Cadence/Shared/CadenceLookPreferenceStore.swift
```

No existing exact template-sync ticket found in targeted TODO/TODO_DONE searches; older template
editor tickets do not cover this policy. This is a gap against the new "all user data" request, not
proof that the previously shipped template feature promised synchronization.

### Existing Preference Limits Should Be Explicit

**MEASURED-SOURCE / known design:** Mac Today stores its adopted sort in defaults but `TasksPanel`
initializes its sort `@State` once; `CadenceLookPreferenceStore.swift:153` explicitly documents
next-launch visibility. Per-list sorts are intentionally absent from the mapping. Extend T-1307's
scope documentation, rather than refile either as an undiscovered transport failure.

**REASONED failure candidate, not a reproduced incident:** `CadenceLookPreferenceSync.swift:33`
promises retry on next launch, but `:159` runs `adopt`, not `publish`, and failed local edits have no
durable dirty marker. With an existing older record, a later adopt can replace a locally changed
mirror after the publish save failed. `lastFailureNotice` is memory-only. Do not promise durable
retry from this code; a focused save-failure/relaunch test is needed before designing a persisted
outbox. The current store-level refusal test (`CadenceLookPreferenceTests.swift:241`) does not test
host relaunch ordering. A new-device coverage claim should disclose this limit.

## What A New Device Receives

**REASONED from documented sync plus source:** a normal signed build under the same iCloud account
opens a local replica and eventually imports available model rows/attributes/assets. Relationship
updates are not atomic, so rows and their related data can appear at different times. Defaults,
permissions, templates, credentials, active timers and backup files are not that replica.

Startup deliberately avoids seeding default tags into an apparently empty replica
(`PersistenceController.swift:205`); preference adoption with no record is a no-op. The app can
temporarily look empty or use fallback settings while data arrives. Absence of a row is not proof
that the person has never created it. A configured container or green in-memory test is not proof
that initial import has completed. Same-note concurrent editing/conflict preservation is a separate
audit question; this report does not certify lossless merging.

**Minimal remaining device check, not performed:** use expendable records on Mac, iPhone and iPad;
for each model family check create/edit, body text, relationship identity, images, and delete in
both directions after ordinary sync settles. Include a custom template as a deliberate non-sync
control, plus palette/sidebar/task-sort changes. Verify widget/MCP writes with the app subsequently
opened, and a first-install device with existing server data. Record build, OS, account/container
environment, UUIDs and expected fields. Do not reset the owner's store to manufacture a fresh one.

## Looks Solid / Limits

Source coverage is comprehensive for model fields. Both platform roots attach the same preference
bridge; the store preserves unknown sort pairs and deterministic duplicate winners; normal and
recovery configurations are distinct. No missing-type patch is warranted. Limits: no generated
schema validation, live remote records, actual signed entitlements, exhaustive UI reachability, or
all-write-site save-failure audit. The companion inventory is the cheap recheck for future fields.
