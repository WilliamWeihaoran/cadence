# High-ROI Audit Batch

```text
Tree read: 4ad2178
Dirty files at initial capture: 22
Source: clean git archive; all workspace changes excluded
Mode: source/history inspection and arithmetic only; no builds, tests, app, or simulator
Product code, tests, and docs/TODO.md unchanged
HEAD at final check: 2c95a84
Drift: two sibling commits landed; audited implementation files are unchanged
```

Four focused audits found five actionable issues. Runtime consequences below are **REASONED**, not reproduced in a running app. Source searches and the arithmetic witness are **MEASURED**. Local IDs identify this batch only; they do not allocate T-numbers.

| ID | Priority | Finding | Can It Happen Today? |
| --- | --- | --- | --- |
| ROI-03 | P2 | Import does not reconcile pending reminders | Valid import on Mac/iOS with notifications enabled; stale until another reconciliation trigger |
| ROI-04 | P2 | Imported focus logs and stored totals can disagree | Valid merge containing a newer session for an existing task/list |
| ROI-01 | P2 | Import reports undifferentiated failure after data has committed | A post-commit migration fetch/save fails; conditional, not observed |
| ROI-02 | P2 | Import accepts parent-goal cycles that have no Goals-page root | Edited or already-invalid archive, including a cycle completed through destination rows |
| ROI-05 | P3 | New-tag attachment failure says nothing changed after tag creation committed | iOS implementation only; first commit succeeds, second fails; not a released Mac defect |

## Reports

- [Restore failure boundaries](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-07/import-recovery.md): ROI-01 and the misleading one-commit test claim.
- [Imported graph validation](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-07/import-graph.md): ROI-02, with an effective-graph validation proposal.
- [Post-import reconciliation](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-07/import-reconciliation.md): ROI-03/04, including current recovery triggers.
- [Recent fix claims](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-07/recent-fix-claims.md): a7184f2 and 7ae1c61; main fixes present, ROI-05 is a narrower remaining case.

## Patch Order

1. Distinguish committed import plus migration warning from a refused import (ROI-01). This gives post-commit consumers an accurate outcome even when migration fails.
2. Reconcile notifications from fresh committed state, not the app's potentially stale context (ROI-03).
3. Restore focus aggregate consistency using the existing raise-only ledger rule (ROI-04); explicitly document derived-counter behavior under merge.
4. Reject newly introduced goal cycles before writes, accounting for merge mode and existing destination edges (ROI-02).
5. Narrow the iOS tag attachment failure sentence; preserve the successful tag mint unless atomic creation/attachment is deliberately chosen (ROI-05).

Each report names suggested checks for Claude to implement. No claim is made about current test passes or mutation-test results. Existing T-1084 calendar-link portability and T-1088 split habit-day decisions were checked and deliberately not re-filed.

**Final verification:** Markdown links/code fences and whitespace checked; `scripts/agent-commit.sh check` exited 0. The intervening commits changed MCP/container creation and reserved older audit tickets T-1096..T-1108; those reservations do not duplicate this batch's five findings. No commits made here.
