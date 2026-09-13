# Terminal Recovery Export Audit

```text
Tree read: 4799e3c
Dirty files at capture: 10
Source examined: clean git archive of 4799e3c; all 10 workspace changes excluded
Mode: source/history inspection only; no app launches, builds, or tests
```

## RE-1: Store Fallback Stops Before the Export Can Fail

**P2 conditional recovery gap / inferred / not reproduced. Extends the recovery work in T-813/T-817; it is not their missing-file or write-permission case.**

**Can this happen today?** Only under exceptional conditions: normal startup, separate recovery-store startup, and even in-memory startup must all fail to reach this screen. After that, one candidate must open read-only but throw while fetching or encoding the archive, while a later candidate could export. That combination is plausible but was not produced in this audit. This is not evidence of ordinary CloudKit failure causing data loss.

**Exact spots:**
- [PersistenceController.swift:291](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:291): returns the first successfully initialized ModelContainer.
- [CadenceTerminalRecoveryView.swift:181](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/Components/CadenceTerminalRecoveryView.swift:181): candidate selection is already finished before the context is made.
- [CadenceTerminalRecoveryView.swift:189](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/Components/CadenceTerminalRecoveryView.swift:189): export throws into a UI failure state; it cannot ask for the next candidate.
- [CadenceDataExportService.swift:107](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceDataExportService.swift:107): archive construction performs throwing entity fetches after the open.

**Consequence, inferred:** an open-but-not-exportable first store blocks a later exportable store. Clicking again repeats the same candidate order. The UI reports failure honestly, but the recovery search is incomplete.

**30-second confirming command:**
```sh
git show 4799e3c:Cadence/Services/PersistenceController.swift | sed -n '240,305p'
git show 4799e3c:Cadence/Shared/Components/CadenceTerminalRecoveryView.swift | sed -n '176,196p'
```
This confirms the control-flow split, not the corrupted-store scenario.

**Suggested fix:** If an open-successful/export-failing fixture confirms the need, let a recovery coordinator try **open plus archive construction** per candidate. Return source provenance, record count, and preceding failures with the archive. Keep candidate order and `allowsSave: false` / `cloudKitDatabase: .none`. Do not silently merge stores or choose the largest archive. A destination file-save failure is different: retry saving the already-built document, not searching another source.

**Acceptance checks, not run:**
- Inject first open success + export failure, then a second candidate containing a sentinel record; recover the sentinel.
- First fully exportable candidate still wins; all failures are reported.
- Destination write failure does not choose a different source.
- Existing tests that refuse writes and avoid creating nonexistent stores remain valid.
- Zero records are not represented as proof that all historical user data was recovered.

## RE-2: Recovery Copy Calls a Separate Store a Backup

**P3 / copy correctness / inferred from startup implementation. Reachable only on the same terminal screen.**

[CadenceTerminalRecoveryView.swift:91](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/Components/CadenceTerminalRecoveryView.swift:91) says startup tried a "backup location" and asserts low memory/storage is the usual explanation. [PersistenceController.swift:184](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:184) instead opens a separate `recovery.store`, potentially new, without restoring primary data into it. No failure-frequency measurement was found supporting "usually."

**Suggested fix:** Say that Cadence could not open its main, recovery, or temporary store. Name the recorded error below; do not imply a backup was tried or diagnose the usual cause. This is a small copy correction, not a demand to add backup restoration.

```sh
git show 4799e3c:Cadence/Shared/Components/CadenceTerminalRecoveryView.swift | sed -n '89,95p'
git show 4799e3c:Cadence/Services/PersistenceController.swift | sed -n '184,218p'
```
Acceptance: distinguish an existing backup from a separate fallback database; leave export's existing "tries to get a backup" promise appropriately conditional.

## R32 Premise Correction

"The recovery view takes no model context on any path" is too strong. It has no dependency on a failed **ambient** model context, but [line 187](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/Components/CadenceTerminalRecoveryView.swift:187) deliberately constructs its own ModelContext after a successful read-only open. That is the correct architecture, not a defect to fix.

## Looks Solid

- Terminal presentation avoids constructing the normal model-dependent shell when the container is nil.
- [PersistenceControllerTerminalRecoveryTests.swift:195](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/PersistenceControllerTerminalRecoveryTests.swift:195) and its neighboring tests exercise real temporary stores: successful reads, missing-first fallback, first-existing ordering, refused saves, and the actual export service. This is not an untested feature or just source-token coverage.
- [CadenceDataExportService.swift:107](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceDataExportService.swift:107) builds all 21 entity record tables with throwing fetches; it does not quietly omit a failed table.
- The file exporter reports destination errors at [CadenceTerminalRecoveryView.swift:82](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/Components/CadenceTerminalRecoveryView.swift:82).

## Patch Order

Correct RE-2 independently. For RE-1, first pin the cross-candidate export-failure case through injected operations, then change orchestration only if the desired recovery contract is agreed. Do not remove existing real-store tests or add redundant existence checks retired by T-817.
