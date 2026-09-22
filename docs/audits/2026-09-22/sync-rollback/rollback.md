# R65: Rollback Contract And Delete Recovery

```text
Tree read: d819a4c
Dirty files: 1 at start; committed snapshot used, dirty performance probe excluded
Evidence: source/test inspection plus current Apple API and release-note research
No SwiftData runtime probes, app/test builds, or cross-toolchain runs
```

## Answer First

**DOCUMENTED:** Apple says `ModelContext.rollback()` cancels unsaved insertions/deletions, returns
modified models to their last committed values, and clears the undo stack. Restoration itself is
**not an undocumented behavior**. [Apple rollback API](https://developer.apple.com/documentation/swiftdata/modelcontext/rollback%28%29),
[ModelContext overview](https://developer.apple.com/documentation/swiftdata/modelcontext).

**Not established:** an official 26-to-27 change in the timing of an already-held model reference or
its inverse arrays. Repository T-1296 records differing CI/local observations; this audit did not
reproduce them. The public major-version notes inspected do not identify a rollback change. Treat
the observed discrepancy as a compatibility issue to contain, not evidence Apple intentionally
changed the contract or that one toolchain restores every graph correctly.

**T-1321's implementation is a useful simplification, not a complete proof of UI recovery.** Removing
explicit `nil` assignments removes those application-written edits. But `delete` followed by
`processPendingChanges` still asks SwiftData to alter relationship state. A variable backed by
SwiftData is not an ordinary Swift variable that can change only when this method assigns it.

**T-1336 should not become "never edit before delete" as a blanket rule.** Some manual clearing is
redundant; recurrence rewiring is not. The correct house rule is: a refused deletion must preserve
the persisted graph and restore the app's visible state, without leaving pending mutations or
running success-only side effects. Verify that operation-level behavior instead of bounding away
user-visible failures because a framework varies.

## What Was Researched

Current public DocC JSON content was fetched successfully from Apple's official domain, after the
sandbox's direct network request failed. Inspected primary prose for `rollback` and relevant
SwiftData/inverse sections:

| Apple major release notes | Rollback mentions in inspected prose |
|---|---|
| [iOS/iPadOS 26](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes) | 0 |
| [iOS/iPadOS 27](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes) | 0 |
| [macOS 26](https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes) | 0 |
| [macOS 27](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes) | 0 |
| [Xcode 26](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes) | 0 |
| [Xcode 27](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes) | 0 |

**MEASURED-RESEARCH, bounded negative result:** iOS/macOS 27's SwiftData section names a background
actor/Query deadlock fix (178113288), not rollback restoration. This search does not cover every
point-release note, Feedback report, private DTS answer or unannounced framework fix. Therefore
"no documented change found in these sources" is warranted; "known stable on both" is not.

Xcode label alone is insufficient provenance: compare Xcode build, linked SDK, **runtime OS build**,
SwiftData implementation, store configuration, autosave setting and whether the first read occurs
before a fetch. The CI/local split changed more than one variable. Installing another Xcode on the
same Mac would not by itself reproduce the older OS framework. Current API documentation is a
contract reference, not a measured version-by-version behavior matrix.

Apple documents `processPendingChanges()` as recording changes with the undo manager. It does not
provide a substitute guarantee that every SwiftUI observation/inverse has synchronously refreshed.
Likewise, `transaction(block:)` documents running a closure and saving pending changes; it is not
evidence of an operation-local rollback that preserves unrelated work.
[ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext),
[transaction](https://developer.apple.com/documentation/swiftdata/modelcontext/transaction%28block%3A%29).

## T-1321: Right Simplification, Missing User-Level Assertion

**MEASURED-SOURCE:** [`GoalListLinkHelpers.swift:464`](../../../../Cadence/Shared/GoalListLinkHelpers.swift#L464)
now only deletes, processes pending changes, and calls `commitDelete`. Its three old nil writes are
gone. Presentation and progress readers filter deleted links; that is a correct success-path defense.
`CadencePendingChangePersistence.swift:130` rolls back on save refusal. Nothing here proves that
the *already materialized parent's array* has reacquired the link when the alert is shown.

**P2, confirmed coverage gap (extends T-1321), not a reproduced production failure:**
[`CadenceGoalListLinkSurfaceTests.swift:365`](../../../../CadenceTests/CadenceGoalListLinkSurfaceTests.swift#L365)
asserts `held == drawn`. It accepts both `true/true` and **`false/false`**. The latter is a missing
relationship row in the inspector even though the fresh context at `:372` correctly finds the join
row on disk. Non-nil `link.goal`/`link.area` does not imply membership of `goal.listLinks`.

30-second confirmation:

```sh
ruby -e 'held=false; drawn=false; puts "assertion passes=#{held == drawn}; link visible=#{drawn}"'
sed -n '348,376p' CadenceTests/CadenceGoalListLinkSurfaceTests.swift
```

**Can happen today?** The weak assertion is present today. Actual missing-row behavior after a
failed detach remains REASONED/unmeasured. Do not report it as an observed Xcode 26 incident.

Suggested test/fix order: retain the framework observation as diagnostic data, then assert that the
**app's chosen recovery path** produces the original visible link, list count and progress. If an
explicit refresh/re-query is required, invoke the real recovery operation and test its result.
Use a persisted fixture and an injected refusing commit; assert the live view model, fresh-context
graph and absence of pending changes separately. Do not simply replace this bound with a raw
framework assertion and repeat the CI/local failure. `:397`'s source guard is useful but cannot
stand in for that behavior test.

## T-1336: Which Edits Are Actually Necessary?

| Path | Source and classification | Conservative direction |
|---|---|---|
| Goal cascade | `TrackingDeleteHelpers.swift:70` computes the recursive deletion list. `:79-89` nulls surviving tasks/habits, clears doomed arrays and severs parent links. | Membership of the doomed set is app logic and must remain. With nullify relationships, many clearings duplicate framework deletion semantics. Removing them may be viable only after all same-turn readers tolerate pending-deleted references; enumerate readers before changing it. |
| Habit delete | `TrackingDeleteHelpers.swift:115-122`: completions and habit are all doomed; explicit nils/array clears precede deletion. | Closest candidate for T-1321-style simplification. Still verify parent goal/context inverse arrays after success and failure. Reminder cancellation is already below the commit at `:127`: keep that pattern. |
| Context cascade | `CadenceListDeleteHelpers.swift:100,116` sweeps owned tasks, then severs surviving foreign tasks/habits from doomed goals. | T-1312's ownership boundary must remain. A failed commit needs original surviving relationships visible, not merely undeleted context rows. No direct `deleteContext` commit exists; the caller owns it. |
| Task sweep reached from every list cascade | `CadenceTaskMutationSupport.swift:782,917-943` repairs recurrence and edits surviving area/project/context/goal/bundle/tag arrays, then clears doomed task fields. | Not a small local removal: empty-bundle decisions at `:950` currently depend on the edited arrays. Compute remaining membership from the planned deletion IDs before eliminating that mutation. |
| Surviving recurrence predecessor | `CadenceTaskRecurrenceWorkflowSupport.swift:102,116` rewires a survivor's `recurrenceSpawnedTaskID`. | **Not removable.** This is a persisted UUID string, not a SwiftData relationship; nullify cannot repair it. Dropping it would leave a deleted successor recorded as live and can stall spawning. |

**REASONED severity:** existing T-1336 is important because failed destructive actions can leave a
misleading UI. This inspection does not prove new permanent CloudKit data loss on refusal. The
store-level rollback behavior and graph-observation behavior are different claims.

### Suggested Implementation Shape

1. Preserve the exact owned/deleted-ID plan, recurrence repair, asset-retention rules and bundle
   semantics. Remove only redundant edits whose readers and decisions have been accounted for.
2. Where survivor edits remain necessary, prefer a **dedicated operation context**, resolving
   stable IDs there and committing once, similar to the isolation boundary at
   `CadenceArchiveImportService.swift:101`. Failure then does not mutate the UI's materialized
   graph. This is a proposal, not a drop-in verified patch: define how pending UI edits are handled,
   how success refreshes readers, and how dirty parents/callers avoid cross-context objects.
3. If retaining the shared-context architecture, use an explicit operation snapshot/recovery path
   that restores survivor state *and* proves there is no leftover pending change. Do not blindly
   assign snapshots after rollback and assume the context is clean; do not save in the failure
   handler to clear `hasChanges`, since that can commit unrelated work. The subtask captured-array
   repair is existing evidence (`CadenceSubtaskInverseParityTests.swift:225`), not automatic proof
   that a much larger cascade is safe.
4. Keep rollback for undoing deletion. `commitEdit(undo:)` alone cannot un-delete rows. Never use
   `deleteAllData`, reset the context, or introduce a migration to solve an observation problem.

Tests: refused goal with tasks/habits/list links and nested milestones; refused habit with completed
days; refused context with externally filed goal-linked task; refused mid-series task with a
surviving predecessor and partially occupied bundle; a later unrelated save; and pre-existing
unsaved unrelated work. Specify the unsaved-work policy instead of silently rolling it away.
Assert restored **relationships and derived progress**, not just row counts. Existing
`CadenceListCascadeRollbackTests` pins important row/commit behavior but does not replace this matrix.

## P2: A Cascade Can Cancel Reminders Before Its Commit Is Refused

**MEASURED-SOURCE; independent of the Xcode timing question.**
`CadenceListDeleteHelpers.swift:225` calls the task sweep with `commitsImmediately: false`.
The sweep skips its save but still schedules `NotificationManager.cancel(taskIDs:)` at
`CadenceTaskMutationSupport.swift:804`. Context deletion independently schedules habit cancellation
at `CadenceListDeleteHelpers.swift:132`, also before returning to its caller's commit.
`iOSListDeletionSupport.swift:121` encloses that construction in `commitCascade`; a thrown commit
rolls models back, but it does not revoke either previously scheduled Task. NotificationManager's
`:133,142` methods remove pending notification requests.

**Can happen today:** a user deletes a context/list containing scheduled reminders, the construction
finishes but the outer save fails, and the queued cancellation runs. The records survive; reminders
can remain absent until a later reconcile. This is a reachable source path, not a notification-center
runtime reproduction. It does not require Xcode 26, malformed stored data, or a failed inverse.
An empty/unnotified fixture hides the consequence.

```sh
sed -n '219,234p' Cadence/Services/CadenceListDeleteHelpers.swift
sed -n '789,805p' Cadence/Shared/CadenceTaskMutationSupport.swift
sed -n '128,134p' Cadence/Services/CadenceListDeleteHelpers.swift
sed -n '117,133p' Cadence/iOS/iOSListDeletionSupport.swift
```

**Suggested fix:** deferred sweeps return/accumulate pending side effects; the outermost successful
commit releases them. Direct task deletion still cancels after its own successful commit. Same
principle applies to `willDelete`/`didDeleteBundles` UI/focus callbacks at `:765,790`; do not move a
state-destructive callback earlier under a new name. Reuse the single-habit path's existing
postcommit ordering, not a save inside each child helper.

Add injectable cancellation/callback spies: refused outer commit emits **zero** side effects,
successful outer commit emits the expected IDs once, failure halfway through construction emits
none, direct-delete behavior remains intact. Search of TODO/TODO_DONE and prior audit reports found
no exact deferred-cancellation entry; extends the transaction scope of T-1336, distinct from
T-1301's already-fixed single-habit ordering.

## Patch Order And What Looks Solid

1. Fix/verify outer-commit side-effect ordering; it is not waiting on another toolchain.
2. Add a real visible-state witness for refused detach without pinning raw framework timing.
3. Resolve T-1336's operation boundary, preserving recurrence and ownership semantics.
4. Record a diagnostic runtime matrix only where needed; do not install tools merely to decide
   whether the application should recover correctly.

Good existing patterns: injected commit closures; task sweeps defer persistence to their owner;
single-habit notification cancellation follows commit; explicit snapshots for edits; link readers
filter `isDeleted`; recursive goal counting shares the deletion traversal. These are useful pieces,
but none alone certifies cross-context UI restoration. All tests mentioned were read, not run.
