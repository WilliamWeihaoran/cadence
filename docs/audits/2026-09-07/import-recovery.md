# Import Recovery Audit

```text
Tree read: 4ad2178
Dirty files at initial capture: 22; excluded via clean git archive
Mode: source/history only; no builds, tests, app, or simulator
```

## ROI-01: A Migration Failure Hides an Already-Committed Import

**P2 / production error-contract gap / REASONED runtime consequence.** Extends T-274/T-1082's new import path; no matching post-commit failure ticket found in TODO, TODO_DONE, or the prior audit reports.

**Can this happen today?** Both Data Safety screens call the shared flow. If archive persistence succeeds but the subsequent legacy-note migration fetch or save fails, the user sees only `Import failed: ...` although imported/overwritten rows are already durable. A legacy archive plus a failure in its second write is one concrete setup. No store failure was induced here. This is not a claim that every import fails or that the imported rows are lost.

**Evidence:**

- [CadenceArchiveImportService.swift:135](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceArchiveImportService.swift:135) commits all imported rows. Its rollback catch only surrounds this first save.
- [CadenceArchiveImportService.swift:146](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceArchiveImportService.swift:146) subsequently calls throwing migration with `saveChanges: true`.
- [NoteMigrationService.swift:245](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/NoteMigrationService.swift:245) fetches the canonical notes; later migration steps fetch legacy tables. [Line 260](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/NoteMigrationService.swift:260) performs another save when it inserted folded notes.
- [CadenceArchiveImportPresentation.swift:396](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadenceArchiveImportPresentation.swift:396) catches both phases identically and clears the preview/pending data in `defer`. Its failure sentence at 216 carries no committed counts or migration-phase distinction.

The service comment already acknowledges that a migration failure leaves imported rows in place and launch can retry the fold. The defect is that this knowledge never reaches the user-facing outcome. A generic failure is not an explicit false "nothing changed" promise, but it omits the most consequential fact for deciding whether to retry, especially in overwrite mode.

## Test Gap, Not Another Production Finding

**MEASURED source observation:** `CadenceNoteFolderMoveCommitTests.theImporterHoldsExactlyOneCommitForTheWholeArchive`, [line 249](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadenceNoteFolderMoveCommitTests.swift:249), counts one literal `modelContext.save()` in the importer file. That fact is true; the stronger test name is false for a legacy archive whose migration inserts a note. Counting only this file cannot see `context.save()` in the migration service.

The existing round-trip tests cover successful legacy folding, not a failure after the first commit. Do not read the new one-commit test as atomicity evidence or re-file it as a separate data-loss bug.

## Confirm in 30 Seconds

```sh
git show 4ad2178:Cadence/Services/CadenceArchiveImportService.swift | sed -n '125,160p'
git show 4ad2178:Cadence/Services/NoteMigrationService.swift | sed -n '240,265p'
git show 4ad2178:Cadence/Shared/CadenceArchiveImportPresentation.swift | sed -n '395,413p'
git show 4ad2178:CadenceTests/CadenceNoteFolderMoveCommitTests.swift | sed -n '245,260p'
```

These confirm control flow, not an induced disk failure.

## Suggested Fix

Retain the intentional private import context. Represent the persisted import outcome separately from post-import migration status. On a migration failure, preserve inserted/overwritten counts and display a warning such as "Import saved; older notes could not be brought forward yet" with the retry/relaunch behavior. Do not claim rollback of the already-committed import or delete those rows to make the message true.

Use the existing `CadenceArchiveImportOutcome`/presentation boundary for this distinction. Clean up any failed migration's pending work in the private context as appropriate without touching the app's shared context. If atomic import plus migration is chosen instead, it is a deliberate transaction change requiring tests of migration reads over pending rows, not a blind relocation of one save.

**Acceptance checks:** inject a migration failure after a successful import save; inspect a second context to prove imported rows survive; assert the UI outcome names committed work. Separately refuse the first save and assert no import rows survive. Exercise a successful legacy fold and a retry without duplicate canonical notes. Rename the source-shape test to the narrower no-per-row-save guarantee, or instrument actual commit attempts if it is meant to assert transaction count.

## Looks Solid

**REASONED:** validation runs before writes; the first save has rollback protection; `importArchive` allocates its own context, avoiding rollback of unrelated edits. The folder helper correctly uses the importer's non-committing path. Preserve these behaviors.
