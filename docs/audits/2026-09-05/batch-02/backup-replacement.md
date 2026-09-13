# Backup Replacement and Rollback Safety

```text
Tree read: 9b31280
Dirty entries at capture: 24 (git status --short; untracked directories count as one)
Source examined: clean git archive of 9b31280; dirty work excluded
Mode: source-only audit; no app launches, builds, or tests
```

## BR-1: Cleanup Deletes Displaced Originals Even When Putting Them Back Fails

**P2 / conditional failure-path defect / inferred. Extends T-326's staged-restore guarantee; not the already-fixed failure-before-staging case.**

**Can this happen today?** The user stages a local backup restore in macOS Settings and relaunches. Replacement then fails during a file move, followed by a failed rollback move or removal. Persistent permission/I/O failures can affect both forward and compensating operations. No such filesystem failure was induced in this audit.

**Exact spots:**
- [PersistenceController.swift:816](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:816): catch begins rollback after a multi-file replacement failure.
- [PersistenceController.swift:820](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:820): removal of newly installed items is swallowed.
- [PersistenceController.swift:824](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:824): moving originals back is also swallowed.
- [PersistenceController.swift:829](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:829): displaced directory is removed regardless of whether those originals were restored.
- [PersistenceController.swift:796](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:796): a later swap also deletes a preexisting displaced directory without reconciling it.
- [SettingsDataSafetySection.swift:227](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsDataSafetySection.swift:227): shipped restore scheduling entry point.

**Inferred consequence:** the immediate rollback copy can be destroyed while the primary store remains incomplete. This contradicts the nearby guarantee that every thrown restore leaves the live store unchanged. **Do not call it irreversible loss of all data:** applyRestore first creates a pre-restore backup at [line 705](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:705), and that separate backup is not deleted by this catch.

A process interruption during the multi-file swap is a related unverified recovery gap: deferred cleanup and catch blocks are not a crash journal. This report does not assert that a crash was reproduced or that all interruption points are unsafe.

## 30-Second Confirmation

```sh
git show 9b31280:Cadence/Services/PersistenceController.swift | sed -n '695,733p'
git show 9b31280:Cadence/Services/PersistenceController.swift | sed -n '790,834p'
git show 9b31280:CadenceTests/CadenceStoreRestoreTests.swift | sed -n '423,461p'
```

The source confirms unconditional cleanup after swallowed compensation errors. It does not measure filesystem failure frequency.

## Suggested Fix

Track rollback success per item. Keep the displaced directory whenever any original cannot be restored; surface both the original failure and the recovery failure, with the retained path. Never describe the primary store as intact until verified.

Do not merely remove the final cleanup: the next attempt's initial deletion at line 798 must also preserve/reconcile unfinished recovery evidence. Use a small explicit transaction marker or quarantined recovery directory before allowing a later restore to reuse these paths. Keep the pre-restore backup and existing staging verification.

**Existing correct pattern:** stage and verify before touching the live store; quarantine failed restore intent in `performPendingRestoreIfNeeded` at [line 683](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:683). Extend that conservative handling to failed compensation, rather than inventing a second restore mechanism.

## Test Gap, Separately

[CadenceStoreRestoreTests.swift:127](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadenceStoreRestoreTests.swift:127) exercises a forward swap failure with real temporary files and verifies restoration. Its FileManager fault predicates deliberately avoid sabotaging rollback ([line 428](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadenceStoreRestoreTests.swift:428)). That is good coverage of a **single** failure, not proof of recovery from a second failure. No existing second-failure case was found in this suite.

Acceptance checks, not run:
- Fail a staging-to-live move, then fail a displaced-to-live move; retained originals remain byte-identifiable.
- Fail removal of a newly installed destination; do not destroy the displaced original when moving it back fails.
- A later launch/restore refuses to erase the retained recovery directory.
- Successful rollback still restores all original store components.
- Keep pre-restore backup provenance in the resulting error/recovery notice.

## Looks Solid

Replacement is fully staged before the first live move; sidecar files participate; failed restore intent is quarantined to avoid a launch loop. Existing tests verify staging failure and ordinary rollback using isolated filesystem fixtures. Preserve these tests and add the second-failure discriminator.

## Patch Order

Add the double-failure fixture; preserve recovery evidence and correct the claimed outcome; then define interrupted-transaction reconciliation. Do not broaden into backup retention policy.
