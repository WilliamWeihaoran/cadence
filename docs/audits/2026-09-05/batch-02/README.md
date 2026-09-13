# Five High-ROI Audits, Batch 02

```text
Tree read: 9b31280
Dirty entries at capture: 24 (git status --short; untracked directories count as one)
Source examined: clean git archive of 9b31280; dirty work excluded
Mode: source-only audit; no app launches, builds, or tests
```

## Findings and Order

| Priority | Audit | Finding | Classification |
| --- | --- | --- | --- |
| P2 | [Backup replacement](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/batch-02/backup-replacement.md) | Failed rollback is followed by deletion of displaced originals. | Conditional failure-path defect, inferred. Pre-restore backup still offers recovery. |
| P2 | [Privacy reset](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/batch-02/privacy-reset.md) | Keychain deletion failure is swallowed; database failure can leave a partial delete pending. | Two distinct failure-path defects, inferred. |
| P2 | [Focus continuity](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/batch-02/focus-continuity.md) | Mac banks received timer ticks, with the only producer inside a conditional screen. | Live navigation/elapsed-time risk, inferred. |
| P2 | [Image import transaction](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/batch-02/image-import-transaction.md) | iOS creates pending image rows between photo-loading suspension points. | Interleaving risk extending T-629, inferred. |
| P2 | [Reminders refresh ordering](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/batch-02/reminders-refresh-ordering.md) | Older fetches can overwrite newer state or successful completion. | Async ordering risk, inferred. |

Six findings across five areas. No arbitrary minimum was applied per report.

## How to Use

Each report provides exact snapshot references, current reachability, existing-ticket context, a short confirming command, a scoped suggested fix, and tests for the implementing agent. The confirming commands inspect code; **none is presented as an executed runtime reproduction**.

Measured evidence in this batch consists of source searches and call-site inventories. Runtime consequences are inferred and explicitly require verification. Test files were inspected, not executed; coverage gaps are not claims that a mutation was run and survived.

Recommended sequence: preserve restore rollback evidence first; fix privacy reset's independent failure boundaries; move the Mac stopwatch off view ticks; remove the image import's pending-write suspension window; add Reminders request invalidation. These changes should be separate patches.

## Handoff

Completed on 2026-09-06 (Asia/Shanghai); retained under the batch's starting-date folder.
HEAD advanced from `9b31280` to `5aac94d` during the pass. The intervening commit changes Kanban
column/reorder behavior and associated models/tests; `git diff --name-only 9b31280..5aac94d`
contains none of these findings' primary source files. Findings and references remain anchored
to `9b31280`. Ongoing dirty work is not certified.

## Scope

- Backup audit concerns multi-file store replacement, not the preceding batch's terminal export screen.
- Privacy audit concerns destructive reset and its credential/artifact boundary, not a general legal-policy review.
- Focus audit concerns time ownership and navigation, not recurrence or session-log conflict merging.
- Image audit concerns async photo import transaction ownership, not the sibling in-flight markdown toolbar edits.
- Reminders audit concerns callback freshness, not permission wording or sorting.

No production code, tests, TODO.md, or existing dirty work were edited. New report-local IDs are not assigned T-ticket numbers.
