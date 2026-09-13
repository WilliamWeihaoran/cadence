# Five-Area Source Audit, 2026-09-05

```text
Tree read: 4799e3c
Dirty files at capture: 10
Source examined: clean git archive of 4799e3c; all 10 workspace changes excluded
Mode: source/history inspection only; no app launches, builds, or tests
```

## Additional Batch

[Batch 02: backup replacement, privacy reset, focus continuity, photo-import transactions, and Reminders refresh ordering](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/batch-02/README.md)
audits `9b31280` and was completed on 2026-09-06. It is separate from the five reports below.

## Results

| Report | Result | Next action |
| --- | --- | --- |
| [First-run creation](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/first-run-creation.md) | Fresh macOS sidebar has no first-list entry point; extends T-559. Tasks and All Tasks Kanban do not need organizational setup. | Add a reachable use of the existing optional-context sheet. |
| [Recovery export](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/recovery-export.md) | Candidate fallback ends before export is attempted. Terminal copy also describes a recovery store as a backup. | Verify the rare open-success/export-failure case; correct copy independently. |
| [AppKit behavior](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/appkit-behavior.md) | Two right-click overlays ignore spatial hit testing. Seven custom view subclasses and seven representables inventoried. | Reproduce out-of-bounds routing, then preserve the superclass hit test. |
| [Grouping spacing](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/grouping-spacing.md) | One equal-gap design candidate; no new confirmed rendering defect. Existing sidebar composition gap is already reported. | Review Contexts settings grouping; do not reopen T-1041. |
| [Commit ledger](/Users/williamwei/Desktop/Projects/Cadence/docs/audits/2026-09-05/commit-ledger.md) | Six modern commit IDs lack formal entries in either ledger. Large legacy gap is already known. | Restore only the six modern entries and consider an incremental guard. |

## Evidence Policy

- **Measured** means an executed inventory, arithmetic calculation, or history query. It does not mean the app reproduced a behavior.
- **Inferred** means control-flow, framework-contract, or design analysis. Runtime consequences remain unverified unless explicitly stated.
- These are five targeted audits, not a whole-repo correctness certificate. No production fixes were made.
- References name lines in the committed snapshot, not sibling agents' changing worktree. Retrieve with `git show 4799e3c:path` when current lines differ.
- Existing tickets and previous request responses were checked before writing. Report-local IDs are not new T-number assignments.

## Suggested Patch Order

1. Verify and fix the two right-click hit-test overrides together (AK-1).
2. Expose first-list creation using the already-correct sheet (FR-1).
3. Correct terminal recovery copy (RE-2); separately validate the rare export fallback gap before changing orchestration (RE-1).
4. Repair the six modern ledger omissions; do not mass-backfill old history (CL-1).
5. Decide the Contexts settings spacing candidate visually before any cosmetic change (SP-1).

## Handoff Tree Drift

HEAD advanced to `eab61a0` during this batch, via `52edd7c` (release-readiness documentation) and
`eab61a0` (window restoration and sidebar keyboard behavior). The changed paths were inspected
with `git diff --name-only 4799e3c..eab61a0`. The right-click overrides, recovery implementation,
first-list entry points, and settings spacing finding were not changed by those commits.
The AppKit census's sidebar row and all ledger counts intentionally remain snapshot-specific;
do not apply their old property/count values to the newer tree without rerunning the relevant check.
Other agents' ongoing uncommitted changes are not certified by this audit.

## Existing Request Coverage

R32: recovery-context premise and first-run subset only; manifest and marketing claims remain unaudited here.
R33: full reachable-history ID inventory, not exhaustive semantic classification of every repeated ID.
R34: current task/list/board entry paths and fixture gate, not every surface's click count or all removed seeders.
R37: source inventory complete for the declarations located; inherited framework values and live rendering not measured.
R38: representative grouping compositions, not every grouping in the repository.

The broader requests are intentionally not marked closed by this batch.
