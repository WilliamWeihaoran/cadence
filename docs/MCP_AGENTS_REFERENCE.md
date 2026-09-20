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
