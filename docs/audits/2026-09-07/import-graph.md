# Imported Graph Validation Audit

```text
Tree read: 4ad2178
Dirty files at initial capture: 22; excluded via clean git archive
Mode: source/history only; no builds, tests, app, or simulator
```

## ROI-02: Resolvable Parent IDs Can Still Create an Invisible Goal Cycle

**P2 / input-validation defect / REASONED.** Extends T-274's referential-integrity contract. No matching importer cycle-validation ticket found. This is not the already-filed T-1088 habit-count merge decision.

**Can this happen today?** A user can import an edited or historically invalid archive through either Data Safety screen. Normal single-device goal creation prevents self-parent selection; this audit does not claim the user's current archive contains a cycle. The new import path can write one without using that editor.

**Minimal witness:** one archive Goal with `parentGoalID` equal to its own `id`. It has no dangling reference and no repeated record ID. Validation accepts the ID; wiring assigns the goal as its own parent. Two goals A -> B -> A also satisfy every existence check. A cycle may additionally be completed through destination rows, so checking only archive-internal edges is insufficient.

**Evidence:**

- [CadenceArchiveImportService.swift:279](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceArchiveImportService.swift:279) checks that `parentGoalID` exists in the archive/destination union. The validation pass contains no ancestry/cycle check.
- [CadenceArchiveImportService.swift:776](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceArchiveImportService.swift:776) assigns the parent directly.
- [GoalAssignmentRules.swift:17](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/GoalAssignmentRules.swift:17) defines top-level goals by `parentGoal == nil`.
- [GoalsSupportViews.swift:86](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/GoalsSupportViews.swift:86) starts every displayed group at those roots. [GoalsView.swift:42](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/GoalsView.swift:42) uses that grouping and renders it at 296.

**Result inferred from these paths:** a rootless cycle has no Goals-page group. Its records still exist; other search/detail entry points may find them. This is disappearance from the primary Goals grouping, not proven total data loss or an infinite-recursion crash. `nestedGoals` and deletion already maintain visited sets, which limit recursion but do not invent a missing root.

## Confirm in 30 Seconds

```sh
git show 4ad2178:Cadence/Services/CadenceArchiveImportService.swift | sed -n '274,282p;770,778p'
git show 4ad2178:Cadence/Shared/GoalAssignmentRules.swift | sed -n '15,20p'
git show 4ad2178:Cadence/macOS/Views/GoalsSupportViews.swift | sed -n '82,120p'
```

The counterexample is analytical; no malformed archive was imported into a live store.

## Suggested Fix

Before mutation, construct the effective goal-parent map for the chosen import mode: existing rows retained in merge mode, incoming parent edges applied for new/overwritten rows. Reject newly introduced cycles with a table/record/field error using the importer's existing validation failure pattern. Include paths through destination-only rows. Avoid rejecting an unrelated import merely because an untouched destination component was already corrupt; at minimum validate the changed edges and the ancestry they can reach.

Do not silently break parent links or add a hard two-level limit as part of this fix. macOS currently flattens deeper descendants deliberately; an arbitrary depth limit would change a different policy.

**Existing correct patterns:** [CreateGoalSheet.swift:67](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Sheets/CreateGoalSheet.swift:67) excludes self and restricts normal parent offers. `GoalAssignmentRules.deletionCascade` already demonstrates visited-ID traversal. The importer already rejects bad references before any write; extend that boundary rather than repair after import.

**Acceptance checks:** self-cycle; two-row cycle; overwrite completing a cycle through a destination-only goal; safe merge where a conflicting incoming matched edge is ignored; valid deep acyclic hierarchy; unchanged unrelated corrupt component. Rejection must leave counts and relationships unchanged in a second context. A valid imported hierarchy must still appear in the real `GoalMissionGrouping` result.

## Looks Solid

**REASONED:** duplicate IDs and dangling references are checked before inserts; cross-table references are typed by entity; wiring is a separate pass. UUID preservation makes retries row-idempotent. None of these properties implies an acyclic hierarchy, which is the missing invariant here.
