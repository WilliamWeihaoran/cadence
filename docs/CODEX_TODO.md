# Codex Todo Handoff — **RETIRED, 2026-10-20**

**This file is spent and is kept as a record, not as a queue.** Nothing in the repository links to
it, nothing reads it, and every finding it carried has been dispositioned in `docs/TODO.md`.

It was a lightweight handoff queue for Codex-found work: 22 findings, `CXT-001` to `CXT-022`, from
a read-only source audit taken at `1706226` on 2026-08-31, plus a pointer to a later batch of five
on 2026-09-07. All 22 were routed into the ticket ledger between 2026-09-01 and 2026-09-18 and
closed there. The `CXT-` ids are dead: they allocate nothing, nothing tracks them, and the ledger
entry is the live record in every case.

**What was cut when this was retired**, and why: the 22 per-finding write-ups, and the two patch
orders that sequenced them. Each was a *suggested implementation with acceptance checks* — handoff
guidance for an agent about to do the work, explicitly not a claim that the proposed patch compiled.
That guidance is superseded by the commit that landed, and in three cases it is worse than
superseded: `CXT-003`, `CXT-012` and `CXT-015` were re-checked against the source and closed as
**not defects under the rule they were filed under**, so the write-ups argued for changes the repo
decided against. Leaving 86 KB of unrouted proposals standing beside a ledger that contradicts three
of them is how a future reader re-opens settled work. The full text is in git history.

**What was kept**: the audit provenance stamps below, so the dispositions can be traced to the tree
they were read from; the 2026-09-07 batch pointer, which carries its own disposition table; and
`Checked But Not Filed`, which is the only reasoning here that is not duplicated in the ledger —
it records what the audit looked at and deliberately did *not* file, which a closed ticket cannot.

## Disposition — every finding, and where it actually lives

Read with `./scripts/ledger-view.sh show T-NNNN`. Verified 2026-10-20 against `docs/TODO.md`.

| Finding | Subject | Disposition |
| --- | --- | --- |
| CXT-001 | markdown image insert commits after referencing | **CLOSED** [T-629] |
| CXT-002 | macOS Move Note dismisses before saving | **CLOSED** [T-630] |
| CXT-003 | calendar settings link save handling | **CLOSED as not-a-defect** under [T-636]; an in-place field edit, which the rule deliberately leaves alone |
| CXT-004 | task composer inserts a tag before the task exists | **CLOSED** [T-631] |
| CXT-005 | embedded task-card quick edits repaint over a swallowed commit | **CLOSED** [T-636] (a); the root was the app-wide completion spine, not the note repaint |
| CXT-006 | macOS kanban column editor closes over a swallowed save | **CLOSED** [T-632] |
| CXT-007 | `-> Bool` drop handlers report success after swallowing | **CLOSED** [T-636] (b); the real gap was the `Optional` half of the same sentence |
| CXT-008 | focus completion resets timers after a swallowed commit | **CLOSED** [T-636] (c) |
| CXT-009 | iOS recurrence row closes its scope state before the save | **CLOSED** [T-633] |
| CXT-010 | macOS task-status controls mutate with no explicit commit | **CLOSED** [T-636] (a) and [T-643] (`setStatus`, the spine's other door) |
| CXT-011 | macOS bundle popover end actions close with no commit path | **CLOSED** [T-645] |
| CXT-012 | macOS calendar-event surfaces discard typed EventKit failures | **CLOSED as not-a-defect** under [T-636] (d) — EventKit writes, not `ModelContext` commits, and every failure path records on `lastWriteFailure`. Real residue was lost draft text: [T-658], closed |
| CXT-013 | task-detail subtask insert/delete advance the UI first | **CLOSED** [T-634] |
| CXT-014 | Today rollover dismisses before the batch commits | **CLOSED** [T-635] |
| CXT-015 | macOS timeline quick-create discards the typed failure | **CLOSED as not-a-defect** under [T-636] (d), same reasoning as CXT-012 |
| CXT-016 | iOS omits the `remote-notification` background mode | **CLOSED** [T-626] |
| CXT-017 | a delete can erase an image asset whose reference has not arrived | **CLOSED** [T-620] |
| CXT-018 | hard list deletion walks only the local replica | **CLOSED** [T-623], as a recorded decision to park |
| CXT-019 | two devices fork one recurring task's successor chain | **CLOSED** [T-622] |
| CXT-020 | a device-local EventKit identifier is stored in CloudKit | **CLOSED** [T-624], as a decision rather than a repair |
| CXT-021 | focus minutes are read-modify-write counters | **CLOSED** [T-621] |
| CXT-022 | T-358's two-device section merge needs the remote edit local | **CLOSED** [T-625], a claim-accuracy narrowing |

**The audit was wrong in both directions, and that is the useful part.** Three findings closed as
non-defects; against that, two of T-636's five parts turned out not to be what the audit said they
were, and both corrections came from an agent reading the source instead of the write-up. A finding
here was a place to look, never a verdict.


## Latest Audit Batch: 2026-09-07

```text
Tree read: 4ad2178
Dirty files at initial capture: 22; excluded via clean git archive
Mode: source/history and arithmetic only; no build, tests, app, or simulator
```

See the [new audit batch](audits/2026-09-07/README.md) for five findings across four focused
reviews: import partial-failure reporting, goal-cycle validation, post-import notification/focus
reconciliation, and iOS tag-attachment failure wording. Each has exact references, confirming
commands, suggested fixes, acceptance checks, and existing-ticket context. Runtime effects there are
reasoned, not reproduced. The batch's own local ROI IDs allocate no T-numbers; the tickets do.
All five are now closed, so this pointer is history too — re-verified 2026-10-20.

| Finding | Disposition |
| --- | --- |
| ROI-01 — import reports failure over rows that committed | **Fixed**, `docs/TODO.md` [T-1111] |
| ROI-03 — import does not reconcile pending reminders | **Fixed**, `docs/TODO.md` [T-1112] |
| ROI-02 — import accepts a rootless goal cycle | **CLOSED** [T-1109], 2026-09-09 |
| ROI-05 — new tag survives behind "Nothing was changed" (iOS) | **CLOSED** [T-1110], 2026-09-09 |
| ROI-04 — merged focus sessions leave their cached totals behind | **CLOSED** [T-1114], 2026-09-11 |

The `docs/audits/2026-09-07/` directory itself is untouched historical record and is not retired by
this file; the CXT dispositions are in the table at the top.

## Repo Stamp

- Tree read: `1706226`
- Latest commit: `1706226 2026-08-31 23:18:16 +0800 The ten hairline weights were eight, and two of them were agreements`
- Dirty files at audit time: `52`
- Audit mode: read-only; no build; no tests
- TODO checked first: `docs/TODO.md`

## Follow-up Audit Stamp

- Tree read: `1706226`
- Dirty files before appending CXT-004..CXT-006: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`

## Deep Audit Stamp

- Tree read: `1706226`
- Dirty files before appending CXT-007..CXT-009: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`

## Deep Audit Stamp 2

- Tree read: `1706226`
- Latest commit: `1706226 2026-08-31 23:18:16 +0800 The ten hairline weights were eight, and two of them were agreements`
- Dirty files before appending CXT-010..CXT-012: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`

## Deep Audit Stamp 3

- Tree read: `1706226`
- Latest commit: `1706226 2026-08-31 23:18:16 +0800 The ten hairline weights were eight, and two of them were agreements`
- Dirty files before appending CXT-013..CXT-015: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`

## iCloud Cross-Device Audit Stamp

- Tree read: `1706226`
- Latest commit: `1706226 2026-08-31 23:18:16 +0800 The ten hairline weights were eight, and two of them were agreements`
- Dirty files before appending CXT-016..CXT-022: `53`
- Audit mode: read-only source scans plus this document edit; no build; no tests
- TODO checked first: `docs/TODO.md`
- External contracts checked: Apple Core Data with CloudKit setup/sync documentation and Apple
  EventKit identifier documentation

## Checked But Not Filed

- `TagSupport.resolveTags(named:in:)` inserts, but it takes `ModelContext` as a parameter. The caller
  owns the unit of work, and `CadenceSaveCommitDisciplineTests` documents that exemption.
- `CadenceListNoteFiling.createNote` is already guarded with `commitInsert`.
- Known save-rule exemptions in `CadenceSaveCommitDisciplineTests` were not re-filed here.
- `Cadence/macOS/Views/KanbanCardMetaSupportViews.swift` `select` and
  `Cadence/iOS/iOSMarkdownReferenceSupport.swift` `body` are already named by T-497/T-566 and were
  not duplicated here.
- macOS/iOS context reorder disagreement is already open as T-614, so it was not duplicated here.
- iOS calendar board's bundle drag save swallow was used as a counterexample, not filed: the source
  documents that it reports nothing and dismisses nothing after the save attempt.
- Broad `CadenceTaskMutationSupport` `try? save()` usage was not filed as one mega-ticket. The useful
  items are the surfaces that report, dismiss, animate, or trigger side effects around those writes.
- CalendarManager's global `lastWriteFailure` means CXT-012 is about discarded typed/local failure
  handling, not about every EventKit failure being completely invisible.
- The widget/App Intent publish path already saves through throwing helpers, emits the external-write
  marker, and is pinned by `CadenceExternalWriteReconcileTests`; no widget persistence finding was
  filed in this batch.
- Notification reconciliation has several closed tickets and is already part of CXT-006/CXT-008/
  CXT-010. No standalone notification finding was added without a new reachable path.
- `AppTask.calendarEventID` still has no non-empty writer, so the old linked-task EventKit cleanup
  residue remains existing-data-only and was not re-filed.
- T-497 already owns the two flush-then-dismiss editors; they were not duplicated as new findings.
