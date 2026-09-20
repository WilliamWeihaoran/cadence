# R52: irrecoverable loss and recovery boundaries

```text
Tree read: 1857938
Dirty files: 0 at source snapshot
Evidence: source and test inspection; no destructive experiment or user-store access
```

## Correct the premises first

**MEASURED-SOURCE:** there are **zero explicit `.cascade` delete rules** in `Cadence/Models`.
The destructive cascades are application code, principally `CadenceListDeleteHelpers`,
`CadenceTaskMutationSupport` and `TrackingDeleteHelpers`. The “nine model types” framing is stale;
`CadenceSchema.swift:4` now lists 23 types.

**MEASURED-SOURCE:** newer archive **format versions** already have a rejection test:
`CadenceArchiveImportSurfaceTests.swift:628`. Newer **builds using the same version** are a
different case, covered below. No claim that the existing test passed today is made.

## Ranked exposure inventory

Ordering is **REASONED likelihood**, not measured incident frequency. A recoverable copy may
exist in a startup snapshot or independent export; none was inspected. “No guaranteed copy” is
not the same as “the owner's data is already lost.”

| Rank | Path and reachability | Recovery boundary / disposition |
| --- | --- | --- |
| 1 | Ordinary same-note editing on two devices, especially offline | A competing scalar body can replace one edit. No durable note-revision table or conflict-copy UI in this schema. Startup backups may precede both edits. High-value product protection, not a newly demonstrated framework bug. |
| 2 | Context deletion includes tasks belonging to another list/context via a goal | Reachable through the unrestricted iOS milestone picker. Specific ownership hazard below; potentially destructive beyond the user's intended context. |
| 3 | Ordinary hard task/note/list/goal/habit deletion, or overwriting existing archive rows | Intentional destructive operations, not bugs simply because they delete. No per-operation independent backup is required by these paths. A startup backup can recover old state, not necessarily the most recent edit. |
| 4 | Explicit privacy reset, then discovery that the chosen archive is old or incomplete | Intentionally deletes all current model rows **and local backups**, plus retained originals. Requires typed confirmation; no guarantee of an external export. Particularly risky when used to force exact restore, which ordinary merge does not do. |
| 5 | Cross-version archive partial read followed by discarding the original export | Newer optional tables can be skipped by an older reader. The original file remains the recoverable copy; importing/re-exporting is not lossless conversion. |
| 6 | Automatic duplicate/migration repair chooses a canonical record | Content is often merged, but competing metadata is not all retained. Startup snapshot helps; MCP preparation is a separate caller without this app-startup backup wrapper. |
| 7 | Deleting a parent before all its remote children arrive | T-623's parked local-replica limitation. Can orphan/hide later children; not automatically physical deletion of those unseen rows. Do not call hidden, still-exportable rows irrecoverably erased. |
| 8 | Filesystem restore, backup retention/cleanup, device/app-container loss | Restore has staging and retained-original protections. Automatic snapshots are finite and colocated with the store. Successful restore/cleanup and loss of the container can still exhaust copies. |
| 9 | Deleting/editing real Apple Calendar events | `CalendarManager.swift:345` calls EventKit removal, with recurrence scope. Cadence JSON exports links/notes, not a backup of the external calendar. Provider recovery is outside this app's guarantee. |

## P1 candidate: context deletion crosses container ownership

**MEASURED-SOURCE:**
[CadenceListDeleteHelpers.swift:56](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceListDeleteHelpers.swift:56)
unions `goals.flatMap { $0.tasks ?? [] }` into the doomed tasks, without checking their list or
context. The iOS picker fetches all goals and filters only completion status at
[iOSTaskRowActionViews.swift:442](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSTaskRowActionViews.swift:442);
`:481` changes only `task.goal`. It does not move that task's project or context.
The inspector also offers the unscoped goal set (`iOSTaskDetailSheet.swift:45`) and assigns it
through `iOSTaskDetailSheetSections.swift:419`, including for a task with no existing milestone.

**REASONED live witness:** create Work and Personal contexts; keep task A in Personal's project;
assign it to a Work milestone using the iOS picker; delete Work. A enters the deletion sweep even
though its Personal project survives. This does not require corrupt or historic data. CloudKit
can subsequently propagate the deletion. No runtime reproduction was performed.

**Important counterevidence:** the confirmation counts the same broad union at
`CadenceListDeletionSummary.swift:253`, so this is **not** an undercount allegation. The existing
test's `goalTask` is also explicitly in the deleted context
(`ListDeleteHelpersTests.swift:38`); it does not settle the cross-context case. Product intent
needs a decision: relationship adjacency is not necessarily ownership.

**Suggested fix:** reuse the preservation rule in
[TrackingDeleteHelpers.swift:18](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/TrackingDeleteHelpers.swift:18):
goal removal severs associations while preserving tasks/habits. Define ownership once, use it in
the context sweep and its confirmation, and preserve externally filed tasks while clearing their
doomed goal. Keep same-context tasks deleting as intended. Add a two-context fixture that checks
the surviving task through a fresh context, including its subtasks, markdown assets and goal link;
add a refused-commit variant. No matching cross-context ticket was found in TODO.

Confirm the source chain:

```sh
sed -n '39,86p' Cadence/Services/CadenceListDeleteHelpers.swift
sed -n '433,486p' Cadence/iOS/iOSTaskRowActionViews.swift
sed -n '30,44p' CadenceTests/ListDeleteHelpersTests.swift
```

## Reset: rollback is fixed, whole-operation partial reporting is not

**MEASURED-SOURCE, protected before commit:**
`CadencePrivacyDataResetService.swift:116` wraps both the fetch/delete sweep and save in
`commitDelete`. Tests at `CadencePrivacyDataResetSurfaceTests.swift:596,629,666` assert that a
refused save or mid-sweep throw cannot leak deletion into a later save and does not cancel
notifications. These are real behavioral assertions, not just source-string checks. T-1102 is
fixed in code; do not refile it. A shared-context rollback still is not field-selective undo for
other uncommitted edits.

**P2 remaining reporting defect, REASONED from measured sequence:**
[CadencePrivacyDataResetService.swift:224](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadencePrivacyDataResetService.swift:224)
commits deletion and awaits notification cleanup; catches Keychain failure into a typed warning;
then `:232,235` call throwing backup/original cleanup. A filesystem failure after the commit
propagates to the same generic “Could not delete ...” catch on iOS (`iOSDataResetSettingsSection.swift:95`)
and macOS (`SettingsDataSafetySection.swift:264`). The store is already empty; some cleanup may
already have succeeded. On macOS, the later profile sign-out is skipped. This is not an atomic
reset failure and must not imply that the user's rows survived.

**Suggested fix:** keep the pre-commit throw boundary; after commit return a result recording each
artifact outcome and attempt independent remaining cleanup. Follow `legacyNoteFoldFailure` in the
archive importer and the reset's own retained-key warning. Inject both cleanup failures in tests
and assert “store deleted, some local artifacts retained,” not a fictitious full rollback. This
is unfinished scope of the earlier privacy-reset audit's partial-result suggestion, not another
Keychain finding. A reset should not silently make a fresh backup contrary to its privacy purpose;
offer an independent export beforehand if the owner chooses that product behavior.

## Archive import and version direction

**MEASURED-SOURCE:** `importArchive` uses its own context (`CadenceArchiveImportService.swift:101`).
`apply` validates before writing (`:153`), rolls back failed commit (`:164`) and returns a warning
for a failed second-stage legacy fold (`:175`). Default merge keeps matched rows; overwrite mode
replaces their fields/relationships without deleting unmatched rows. Tests assert those semantics
at `CadenceArchiveImportSurfaceTests.swift:255,284,301,318,826,853`. Focus reconciliation can raise
an existing counter even in merge mode (`:349`), so “merge changes no existing value” is too strong.
An overwrite has the incoming copy in the archive, but no required export of the displaced local
value. Suggest an explicit pre-overwrite export/preview if stronger recovery is desired.

**MEASURED-SOURCE:** current `formatVersion` remains 1 (`CadenceDataExportService.swift:58`);
`sidebarLayoutPreferences` and `lookPreferences` are optional (`:267,286`). The pre-Look reader
at `58c75ef^` lacks the Look table while using the same version. Synthesized keyed decoding does
not retain unknown keys; the known-table reader can import the older subset.
`makePlan` identifies unsupported entities from `schemaEntityNames` (`CadenceArchiveImportService.swift:477`)
and `unreadableKindsNote` warns in the preview (`CadenceArchiveImportPresentation.swift:205`).
The warning itself is tested (`CadenceArchiveImportEntryPointTests.swift:578`).

**REASONED:** this is deliberate partial compatibility, **not** a silently complete restore and
not a reason to reject all otherwise useful old-reader imports. New fields on an existing entity
are a separate hole: entity names alone cannot warn that an older decoder dropped a field.
The higher-version test does not cover either same-version evolution case.

**Suggested coverage, not a product fix already proved necessary:** keep fixtures from real old
writers/readers; test new-to-old import and old-reader re-export; verify the unknown-table warning
and that the source file is retained. Establish when to bump the format or add a minimum-reader /
capabilities field for semantic changes. No format addition can retroactively teach already
shipped older decoders to preserve unknown data. The current optional-table tests at `:669,701`
correctly protect the opposite direction, old archives into the new reader.

Confirm:

```sh
rg -n 'formatVersion|lookPreferences|sidebarLayoutPreferences' Cadence/Services/CadenceDataExportService.swift
rg -n 'entityNamesOnlyInTheArchive|unsupportedFormatVersion' Cadence/Services/CadenceArchiveImportService.swift
rg -n 'NewerBuild|OlderBuild|BeforeThe.*Table|kindsThisBuild' CadenceTests/CadenceArchiveImport*Tests.swift
```

## Offline conflicts and automatic repair

**DOCUMENTED:** Apple's Core Data/CloudKit discussion describes last-writer-wins for conflicting
flat values and explicitly demonstrates one of two text contributions being lost. It recommends
modeling independent contributions when both must survive.
[Apple WWDC19, conflict/collaboration section](https://developer.apple.com/videos/play/wwdc2019/202/?time=912).
**REASONED for Cadence:** `Note.content` is one string (`Models/Note.swift:42`); `updatedAt` is not a
custom conflict resolver. Do not promise a whole-record winner, device-clock ordering, or
character-level merge. Verify the exact current SwiftData/OS behavior with disposable two-device
fixtures. A local-only test cannot establish cloud conflict safety. A revision/conflict-copy
design for high-value note text has stronger value than assuming CloudKit is backup.

**MEASURED-SOURCE:** startup repair groups notes by canonical key, appends distinct body content
and unions tags, then deletes the source (`DataIntegrityRepairService.swift:797,818,833`). Competing
nonempty titles/folder metadata are selected rather than archived. Same-name Context/Area/Project
merges and recurrence/habit duplicate cleanup are also destructive transforms (`:291,460,510,549`).
This is not the same as preserving all versions of an edited cloud record. `NoteMigrationService`
keeps legacy source rows; `PursuitToGoalMigration.swift:76,114` rewires then deletes legacy pursuits.
App startup backs up before maintenance (`PersistenceController.swift:76,99`); MCP preparation
also runs note/tag maintenance (`CadenceModelContainerFactory.swift:40`) without that wrapper.
Treat malformed/duplicate state and partial imports as test inputs, not a reason for global orphan
deletion. T-328/T-620's conservative image handling is the existing correct practice.

## What looks solid, and what a backup actually guarantees

**MEASURED-SOURCE:** goal deletion preserves associated tasks/habits/lists; bundle removal nullifies
tasks; list deletion only removes list-kind notes and candidate image assets with no surviving
reference (`CadenceListDeleteHelpers.swift:108,282`). Cascade refusal goes through one rollback
boundary (T-291). Restore stages and verifies before swapping, retaining displaced originals when
rollback fails (`PersistenceController.swift:909,1012,1091`, T-1100).

**MEASURED-SOURCE:** automatic retention is bounded: five dense startup snapshots, seven-day and
four-week buckets, and five pre-restore snapshots (`PersistenceController.swift:548,1193`). Manual
snapshots are excluded from automatic purging. All are inside the app container; privacy reset
explicitly removes them. **REASONED:** an independent JSON export, kept outside that container and
verified with the intended reader version, is the strongest existing recovery path. It does not
back up external EventKit events, Keychain secrets or every in-memory unsaved edit. This review
does not certify filesystem snapshots against concurrent external writers or process termination.
