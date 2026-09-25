# MCP Agent Reference

This is prose lifted out of `CadenceMCPServer/AGENTS.md`, preserved so no boundary detail is lost
while the active scoped guide stays under its 200-line context budget
(`CadenceTests/AgentContextBudgetTests.swift`). Nothing here is new: every section below was in the
guide verbatim until it went over the cap. Do not load this whole file by default; the guide names
the section you need at the point where it needs it.

## Why The Prohibition Was Wrong

`CadenceMCPServer/AGENTS.md` used to say: *"Do not edit it during normal app UI/model refactors
unless the task explicitly asks for MCP work."* Four other guides carried a variant. That rule was
wrong, and being wrong in five places is what made it ignorable.

It was written by anticipation, not by incident — `5790cc5` created thirteen `AGENTS.md` files in
one sweep eight days after this surface appeared, which is why it carries no reason. Meanwhile
**roughly half the commits that touch these paths are not MCP work**: `842c82d` moved the read
service onto the unified `Note` model, `89db417` added tags, `acea9ce` was the Pursuit→Goal merge,
`1363e7e` the Notes rework, `0ff391d` data-integrity repair, `f94361a` the `nonisolated` sweep.
They *had* to reach in. So "do not touch MCP" cannot mean what it says, and a change that obeys it
produces one of two failures:

- **A broken target.** `670e299` and `62dc384` are both this: shared code edited app-side, the
  `Cadence` scheme green, `CadenceMCPServer` not compiling.
- **A silently stale response schema**, which is worse because nothing goes red. The `Pursuit`
  relationships were missing from MCP summaries until `0040f24` noticed.

The replacement rule — review the boundary deliberately, build this scheme, change response DTOs on
purpose or not at all — is in the guide and is the part to act on.

## What The Smoke Test Missed Before T-259

`plugins/cadence-mcp/scripts/smoke-test.py` ran 21 of 30 arms until T-259, with `update_task`,
`schedule_task`, `complete_task`, `reopen_task` and `cancel_task` executed by nothing anywhere —
five of the eight write tools at the time, each with its own argument wiring, and `schedule_task`
the only place `minuteOfDay`, `durationMinutes` and `clearScheduledDate` are read together. It now
drives a full create → update → schedule → complete → reopen → cancel lifecycle against the fixture
store, asserts the resulting DTO key sets, and records every `tools/call` so an unexercised arm
fails the run.

The same ticket is why `CadenceMCPToolContractTests` also pins that every non-private helper in
`CadenceMCPArgumentParsing` has a router call site: T-260 deleted two that did not.

## Why The Build Log Is Grepped With No Path Filter

Exit 0 says nothing about warnings. This target sat at two warnings under a zero baseline precisely
because a check read its exit status and never read its output. A later isolation regression then
surfaced only under synthesized-macro paths, which a `grep "/Cadence/"` would have missed. Grep the
whole log; the private `-derivedDataPath` is separately non-negotiable, for the reason the root
`AGENTS.md` gives about a shared DerivedData and a running app.

## The Truncation That Produced The `CadencePage` Envelope

T-382 put every list tool behind `CadencePage`. The brief followed in T-385, where an undisclosed
`prefix(50)` on `inbox` alone turned 51 tasks into 50 with no count and no way for the caller to
raise it. That is the failure the envelope's `totalCount` / `hasMore` / `nextOffset` exist to make
impossible, and the reason a new list tool must take an `offset` beside its `limit`: a `hasMore:
true` the caller cannot act on is worse than the silent truncation it replaced.

## Why In-Memory Sort Is Settled, Not Deferred (T-415, closed as X-09)

Reads go through `fetchAll` / `fetchFirst` and push what they can into the predicate, but
`offset`/`limit` still slice in memory. What is *not* pushable:

- Full-text scoring — `search_cadence`, and the `textQuery` arm of `list_tasks`.
- The explicit `statuses` filter. It compares `statusRaw.lowercased()`, which the predicate grammar
  has no equivalent for.
- The **sort**. Computed sort legs (`AppTask.isDone`, `Note.displayTitle`),
  `localizedCaseInsensitiveCompare` against `SortDescriptor`'s numeric-aware `.localizedStandard`,
  and candidate lists that are relationship edges or cross-kind merges rather than fetches.

The reason the guide used to give — that `UUID` is not `Comparable` — was never checked and is
false: Foundation conforms `UUID` to `Comparable`. Closing T-415 needs a stored sort key and a
migration. The live copy of this list is written out on `CadencePage.paging`.

## Why Two Field Snapshots Stay Local To `CadenceWriteService.swift`

`CadenceTaskFieldSnapshot` and `CadenceListEditSnapshot` are not reused from `Cadence/Shared/`, for
two reasons that are also on the local types: the shared candidates share a file with types reaching
`CadenceWindDownReconciler`, which this target does not compile; and `CadenceTaskFieldSnapshot`'s
documented boundary excludes `notes` and `tags`, which `updateTask` writes.

## Why Deletion Is Refused

Displaced from `CadenceMCPServer/AGENTS.md` when T-1182 and T-1122 pushed it past its 200-line cap.
The claim stays there; the argument is here, and it is also written out on
`CadenceUpdateContextOptions`. Two measured reasons, either one sufficient:

- **The cascade is not reachable from this target.**
  `Cadence/Services/CadenceListDeleteHelpers.swift` is not in the explicit Sources phase and cannot
  cheaply be put there: its task sweep reaches `CadenceTaskMutationSupport.deleteTasks`, which calls
  `NotificationManager.shared`, which lazily touches `UNUserNotificationCenter.current()` behind a
  guard that covers an XCTest host and an Xcode Preview host and **not** a bundle-less command-line
  tool. It is the same boundary that makes `createTask` insert its subtasks by hand.
- **`deleteContext` reads this device's local relationship arrays** — `context.areas ?? []`,
  `context.tasks ?? []`, and so on down. A CloudKit record that has not arrived in this replica is
  in none of them, so a delete arm could not honestly report what it removed: it would answer
  "deleted" over rows it never saw, which then arrive afterwards with their container gone.

The framing T-1120 expected — no confirmation, no undo, `mcp-audit.log` for a record — is true and
is *not* the binding constraint: `CadencePendingChangePersistence.commitCascade` is an undo for a
delete, and the cascades already return `false` for the caller to roll back.

## Why Three Kinds Have No Constructor (T-1122)

Displaced from `CadenceMCPServer/AGENTS.md` when T-1122's second pass pushed it past its 200-line
cap again. A tag, a list note and a task bundle are each **refused with a measurement**, not left
undecided, and the three refusals share one shape: the app's only helper for that kind lives
somewhere this target cannot compile, or has no single owner at all.

- **Task bundle.** `CadenceTaskMutationSupport` calls `NotificationManager`, which is
  `import UserNotifications` — the same boundary that already makes `createTask` insert its
  subtasks by hand, and the same one deletion is refused on.
- **List note.** `CadenceNoteFolderSupport` owns both the folder-path rule and the seeded
  `# Title`, and also declares four SwiftUI `View`s reading `Theme`. Compiling it here would drag
  the theme layer into a command-line tool to reach two string rules.
- **Tag.** There is no shared owner for the create rule to call. `create_task(tagNames:)` already
  mints tags by a *different* rule than either settings editor uses, so adding `create_tag` would
  have been a third spelling. `TagSupport.creationDecision(for:in:)` now owns the editors' rule,
  which removes half of that objection; the other half stands — the archived-match branch's answer
  is "offer restore", which a headless caller cannot take.

Do not re-decide any of these from a summary. The measurements are in T-1122's ledger entry.

## Why The Tracking Helpers Cost Four Files (T-1122)

`create_goal` and `create_habit` added four files to the Sources phase rather than one, and the
closure is the reason. `CadenceTrackingMutationSupport` owns `saveGoal`/`saveHabit` — both already
take a `commit:`, so the deferred-commit shape `appendCoreNote` uses works unchanged — and it
reaches `GoalAssignmentRules`, `CadenceOrderAllocation` and `CadencePluralization`. All four are
`import Foundation`/`SwiftData` only, which is exactly what the three unbuilt kinds' helpers are
not: that import list, not the file count, is what makes a helper eligible here.

## Why Bulk Cancel Got A Cap And A Dry Run (T-1365)

`bulk_cancel_tasks` is the only arm on this surface whose selector is a **pattern**. Every other
write arm names one entity the caller already resolved. Until T-1365 the prefix branch guarded
exactly one thing — `prefix.count >= 8` — lowercased the prefix, filtered the whole table and
cancelled whatever came back; `CadenceBulkCancelResult` reported the count *afterwards*.

**The 8-character floor is not a breadth control and raising it does not make it one.** It was
chosen against typos: it stops `MCP` matching every task with `MCP` in front. A longer prefix is
not a smaller selection — `MCP TEST ` matches 3 tasks or 3,000 depending on the store, and the
caller finds out which by having done it.

**It also is not covered by the undo.** T-1121's `saveNotifyAndAudit(_:inserted:undo:)` undoes a
*refused* save. A successful cancellation of 500 rows is exactly the case it does not reach.
`mcp-audit.log` holds summaries, not before-images, so recovery there is a restore from backup
rather than a reversal, and `reopen_task` is not a general transactional undo either — it clears
`status`/`completedAt` and says nothing about the recurrence successors `markCancelled` spawned.

The ticket named three readings. Two shipped, and the third falls out of them:

- **(a) Cap the executed selection, refusing with the number.** `CadenceWriteError`
  `bulkSelectionTooBroad(matched:limit:)`, structural the way `updateContainerColumns` refuses
  rather than half-applies. The bound is `CadenceMCPServiceSupport.maximumPageSize` — the read
  surface's own page ceiling — on the argument that an executed *pattern* cancellation may not
  exceed what the caller could have read back in one look. Inventing a fresh number would have
  been a second scale for "one look at a list" on a surface that already has one.
- **(b) `dryRun`, which resolves the selection and cancels nothing.** This is the half a headless
  caller actually needs: the app-side answer to "are you sure about 500 rows" is a confirmation
  sheet, and there is no sheet here. Same reasoning as T-1122's refusals — a branch whose answer
  is "ask the user" is unavailable to this caller, so the surface has to hand back the
  measurement instead. It is deliberately **not** capped: a preview that refuses to describe a
  large selection withholds the exact measurement the cap exists to make actionable.
- **(c) Require explicit `taskIds` above a threshold** was not built as a separate mechanism,
  because it is what (a) and (b) already produce. Over the cap the prefix stops executing and the
  dry run still answers, so the prefix *is* the finder and `taskIds` is the executor. Building it
  as its own rule would have meant the caller assembling the id list from `list_tasks`, whose
  matcher is not `title.lowercased().hasPrefix` — a finder that disagrees with the executor is
  worse than no finder, because the disagreement is silent. The `taskIds` branch is therefore
  left uncapped: there the caller named every entity, the standard every other write arm meets.

Neither half is sufficient alone, which is why both shipped. A cap with no preview leaves a
headless caller guessing at a selection it has no UI to inspect, and it fails *closed* on a
legitimate 300-task cleanup with no way forward. A preview with no cap is advisory, and nothing
makes a caller use it.

Two smaller decisions are on the function and worth not re-litigating. A dry run over an empty
selection answers with an empty selection rather than `noChanges`: "your prefix matches nothing"
is the question it was asked, and making it `isError` puts a typo'd prefix and a malformed request
in one bucket. And `CadenceBulkCancelResult` carries `matchedTasks` *and* `cancelledTasks` rather
than one list whose meaning depends on `dryRun`, because this surface's standing failure mode is a
caller that reads only the shape of a success.

## Why The Write Path's Undo Is Two Composed Primitives (T-1121)

Displaced from `CadenceMCPServer/AGENTS.md` when T-1365's breadth-control note pushed it past the
200-line cap. Nothing here is new; it stood in the guide verbatim.

`saveNotifyAndAudit(_:inserted:undo:)` *composes* the two `CadencePendingChangePersistence`
primitives rather than re-spelling either. `commitInsert` deletes the rows this call added and
rethrows; `commitEdit` then runs the field restore and rethrows. Nesting them is what gives
`completeTask` — a status change **and** a spawned successor — one undo covering both, and it is
what lets `bulkCancelTasks` put back a whole batch instead of whichever prefix of it was pending.

Neither is a `rollback()`, and that is the point: one long-lived `ModelContext` per process means a
rollback discards whatever else happens to be pending, including work from an unrelated earlier
call. The undo is scoped to what this call did.

Two field snapshots (`CadenceMCPTaskFieldSnapshot`, `CadenceMCPContainerFieldSnapshot`) stay local
to `CadenceWriteService.swift` rather than being reused from `Cadence/Shared/`; both reasons are on
the local types and in "Why Two Field Snapshots Stay Local To `CadenceWriteService.swift`" above.
