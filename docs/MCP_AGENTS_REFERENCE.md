# MCP Agent Reference

This is prose lifted out of `CadenceMCPServer/AGENTS.md`, preserved so no boundary detail is lost
while the active scoped guide stays under its 200-line context budget
(`CadenceTests/AgentContextBudgetTests.swift`). Nothing here is new: every section below was in the
guide verbatim until it went over the cap. Do not load this whole file by default; the guide names
the section you need at the point where it needs it.

## Why The Prohibition Was Wrong

_The guide's own summary of this section, displaced here verbatim on 2026-09-26 (T-1391)
when the guide ran out of headroom. The guide now states the replacement rule and links here._

This file used to say *"do not edit it during normal app UI/model refactors unless the task
explicitly asks for MCP work,"* and four other guides carried a variant. It was written by
anticipation rather than by incident, and roughly half the commits touching these paths are not MCP
work and *had* to reach in — so it cannot mean what it says. Obeying it produces either **a broken
target** or **a silently stale response schema**, and the second is worse because nothing goes red.
Both have happened; the commits are in the reference, under "Why the prohibition was wrong".

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

## Why One Kind Had No Constructor (T-1122)

Displaced from `CadenceMCPServer/AGENTS.md` when T-1122's second pass pushed it past its 200-line
cap again. **It was three until [[T-1406]] built `create_tag`, two until T-1122's third pass built
`create_list_note`, and none since its eighth pass built `create_task_bundle`.** Kept because the
*shape* of the refusal is what the next arm-shaped question gets measured against, not because the
refusal still stands.

- **Task bundle, built 2026-10-07, and it fell to exactly the condition the refusal named.** The
  objection had two halves and both were paid rather than argued away. (1) The **file**:
  `CadenceTaskMutationSupport.swift` calls `NotificationManager` (`import UserNotifications`) and,
  through `CadenceWidgetRefreshCenter`, reaches WidgetKit — two stacks in a headless tool, and a
  Sources phase compiles whole files. The fix was **not** to move the five bundle members to a new
  type, which three source-text scans pinned by spelling; it was to move the **declaration**, so
  `Cadence/Shared/CadenceTaskBundleMutationSupport.swift` declares `enum CadenceTaskMutationSupport`
  on `Foundation`/`SwiftData` alone and the old file became an `extension` of it. Every call site
  and every pin stayed character-identical. (2) **Nothing on this surface could put a task into a
  bundle**, so the arm alone would have made empty blocks and turned `list_task_bundles` from
  dispatched-and-empty into dispatched-over-rows nobody could fill. `add_task_to_bundle` is that
  half, and the two landed in one pass because a file added to the Sources phase with **no caller
  in the target** is the defect [[T-3010]] removed three files for.
- **The membership rule is called, not copied, and that was the whole point of the ticket.**
  `CadenceTaskMutationSupport.assignTask(_:to:)` writes five fields — `bundle`, `bundleOrder`,
  `scheduledDate`, a cleared `scheduledStartMin`, and a cleared `calendarEventID`, which was the
  one field the macOS and iOS add-to-bundle paths disagreed on until T-760 made them one function.
  It moved into the declaration file and stopped being `private` so the arm could ask it. A second
  copy of those five lines inside `CadenceWriteService` — in a process with no timeline in front of
  it — is the failure T-1122 existed to refuse, and it is the thing to check first if this arm is
  ever rewritten.
- **List note, built.** The refusal was that `CadenceNoteFolderSupport` owned both the folder-path
  rule and the seeded `# Title` *and* declared four SwiftUI `View`s reading `Theme`, so compiling
  it here would have dragged the theme layer into a command-line tool to reach two string rules.
  The named condition was that file splitting, and it has:
  `Cadence/Shared/CadenceListNoteFiling.swift` now holds `CadenceNoteFolderPath`,
  `CadenceListNoteFiling` and `CadenceListNoteSupport` on `Foundation`/`SwiftData` alone, and
  `CadenceNoteFolderSupport.swift` keeps the grouping and the four rows. **The arm's own scoped
  refusal is the body**: `MarkdownNoteTitleSync` — which holds `Note.title` equal to the first
  `# H1` of the content on every app commit — is in `MarkdownNoteSupport.swift`, which this target
  does not compile and cannot cheaply, since `NoteKind.syncsTitleFromH1` is declared on the model
  precisely because T-741 called across that line. So `create_list_note` seeds `# title` and takes
  no `content`; a caller-supplied body could arrive with a heading that disagrees with the title,
  and the next app launch would silently rename the note to whatever the body said.

**Why the tag refusal fell and these two did not.** The tag was always the odd one out: it cost
**zero** new files, because `TagSupport` was already in the Sources phase, and what refused it was
a *rule* rather than an import. Both halves of that rule objection have now gone. The first went
on its own — `TagSupport.creationDecision(for:in:)` owns the four clauses both Settings editors
used to hand-roll, so an MCP arm is the third *caller* rather than the third *copy*. The second,
the `.archived` branch whose app-side answer is a Restore button, is answered the way [[T-1365]]
answers a caller with no confirmation sheet: refuse by default, name the row in the refusal, and
take the act only on an explicit `unarchive`. Refusing with no remedy would have been a dead end,
because there is no `update_tag` arm to unarchive through; unarchiving silently would be a write
nobody asked for. The two refusals that remained after T-1406 had no equivalent move available, because what
blocked them is an `import`, and no argument on a tool changes what a Sources phase compiles —
which is why the list note needed a *file split* rather than an argument, and why the bundle would
need the same before its own second objection could even be reached.

**`create_task(tagNames:)` keeps its own rule, and that is not the third spelling T-1122 feared.**
It asks `TagSupport.resolution`, which resolves by slug and inserts what it does not find — the
app's **attachment** rule, shared with every inline picker through
`TagSupport.resolveTagsCommittingInsertions` and with note markdown sync. `creationDecision` is
the app's **catalogue** rule, asked only where a user manages the tag list. The app has had both
since T-631 and has exactly two; routing `create_task` through `creationDecision` would make this
surface the only place in the repo where attaching an existing archived tag to a task fails, which
is a disagreement with the app rather than an agreement with `create_tag`. The visible consequence
is pinned by a test rather than left to be rediscovered:
`attachingTagsKeepsTheAppsAttachRuleWhileCreateTagKeepsTheCatalogueRule`.

Do not re-decide any of these from a summary. The measurements are in T-1122's and T-1406's
ledger entries.

## Why The Tracking Helpers Cost Four Files (T-1122)

`create_goal` and `create_habit` added four files to the Sources phase rather than one, and the
closure is the reason. `CadenceTrackingMutationSupport` owns `saveGoal`/`saveHabit` — both already
take a `commit:`, so the deferred-commit shape `appendCoreNote` uses works unchanged — and it
reaches `GoalAssignmentRules`, `CadenceOrderAllocation` and `CadencePluralization`. All four are
`import Foundation`/`SwiftData` only, which is exactly what the three unbuilt kinds' helpers were
not: that import list, not the file count, is what makes a helper eligible here. T-1122's third
pass took the same measurement one step further — a helper whose *own* imports are clean but whose
*file's* are not can be made eligible by splitting the file, which is how `CadenceListNoteFiling`
became the ninth `Shared/` member.

**The heading is past tense now.** [[T-2077]] removed both arms at 0.14.0 and [[T-3010]]
(`3be4b126`) took three of the four files back out of the Sources phase; `CadenceOrderAllocation`
is the one that stayed, and it stayed for `create_tag` and `create_container` rather than for
anything the tracking arms wanted. Read this section for *why four files*, which is the reusable
part — the closure, not the count — and "Why ten shared files joined the Sources phase" for what
the phase holds today.

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

## Why This Target's Swift 6 Isolation Is Load-Bearing

_Displaced verbatim from `CadenceMCPServer/AGENTS.md` on 2026-09-26 (T-1391), which had no
headroom left under its 199-line budget. The rule stays in the guide; the argument, the
measurement and the enumeration are here._

It is also the only target on `SWIFT_VERSION = 6.0` with `SWIFT_STRICT_CONCURRENCY = targeted` and
**without** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The app and the widgets default their
value types to the main actor; this target does not, and it is on Swift 6, where the isolation
mismatch is an error rather than a warning. That asymmetry is the whole reason a `nonisolated`
enum in `Models/` is load-bearing (see `Cadence/Models/AGENTS.md`) and the reason a change that
compiles in a view is not evidence it compiles here.

## What The Write Path Does To The Real Store

_Displaced verbatim from `CadenceMCPServer/AGENTS.md` on 2026-09-26 (T-1391), which had no
headroom left under its 199-line budget. The rule stays in the guide; the argument, the
measurement and the enumeration are here._

- **The write path mutates the real store, from a second process, with no UI and no undo.**
  `CadenceModelContainerFactory.makeReadWriteContainer()` opens the app-group store
  (`group.com.haoranwei.Cadence`, `Library/Application Support/Cadence/default.store`) with
  `allowsSave: true` — the same file the running app has open. It is gated on the
  `CADENCE_MCP_ENABLE_WRITES` environment flag and defaults to read-only, but when enabled there is
  no confirmation step: `createContext`, `updateContext`, `createContainer`, `updateContainer`,
  `updateContainerColumns`, `createTask`, `updateTask`, `scheduleTask`, `completeTask`,
  `reopenTask`, `cancelTask`, `bulkCancelTasks`, `appendCoreNote`, `createSavedLink`, `createTag`,
  `createListNote`, `createTaskBundle` and `addTaskToBundle` — **eighteen arms** — write and save. *No undo stack* is no longer true of any
  of them (T-1121): every arm goes through `saveNotifyAndAudit(_:inserted:undo:)`, which un-inserts
  what the call added and restores what it changed in place before the caller is told. The one
  residue went with it (T-1181): the core-note accessors take a `commit:` and `append_core_note`
  defers their insert into its own `inserted:` list. `mcp-audit.log` beside the store is the only
  record, and `CadenceMCPRefreshCoordinator` (macOS Services) watches a `.cadence-mcp-refresh`
  marker file so the app reloads after an external write. **`bulk_cancel_tasks` selects by
  *pattern*, so it alone has a breadth control** ([[T-1365]]): `titlePrefix` refuses a selection
  above `CadenceMCPServiceSupport.maximumPageSize` naming the count it matched, `dryRun` returns
  that selection uncapped without cancelling, and the 8-character floor was only ever a typo guard.
  Why both halves and why `taskIds` stays uncapped: `../docs/MCP_AGENTS_REFERENCE.md`, "Why bulk
  cancel got a cap and a dry run". Treat a write-path change as a data-safety change.

## What Is And Is Not Executed Under This Target

_Displaced verbatim from `CadenceMCPServer/AGENTS.md` on 2026-09-26 (T-1391), which had no
headroom left under its 199-line budget. The rule stays in the guide; the argument, the
measurement and the enumeration are here._

- **Nothing under `CadenceMCPServer/` is unit-*executed*.** `CadenceTests` covers the app-side half
  (`CadenceReadServiceTests`, `CadenceWriteServiceTests`, `CadenceSearchMatcherTests`); the router,
  the tool definitions and the argument parsing are *run* only by
  `plugins/cadence-mcp/scripts/smoke-test.py`, because none of those three files is in the app
  target's Sources phase and `CadenceTests` therefore cannot even reference a symbol in them.
  `CadenceMCPToolContractTests` is a **source scan**, not an execution: it pins the three-way name
  contract below, the write gate, that every non-private helper in `CadenceMCPArgumentParsing` has
  a router call site, and that the smoke test still checks its own dispatch coverage. Do not read
  it as behavioural coverage of the router.

## Why Verification Builds This Scheme And Not The App's

_Displaced verbatim from `CadenceMCPServer/AGENTS.md` on 2026-09-26 (T-1391), which had no
headroom left under its 199-line budget. The rule stays in the guide; the argument, the
measurement and the enumeration are here._

Build **this** scheme. The old advice here was "build the app target if shared model code changed",
which is exactly backwards — the `Cadence` scheme staying green is the thing that hides the break.
`CadenceTests/CadenceTargetSourceMembershipTests.swift` catches the commonest shape of it from
inside the app scheme (T-409) by reading this target's Sources phase, but it sees types, not free
functions or extension members: it narrows the window rather than closing it.

## Why The Reads Fetch What They Return

_Displaced verbatim from `CadenceMCPServer/AGENTS.md` on 2026-09-26 (T-1391), which had no
headroom left under its 199-line budget. The rule stays in the guide; the argument, the
measurement and the enumeration are here._

- **Reads go through `fetchAll` / `fetchFirst`, never a bare `FetchDescriptor`** (T-384). `limit`
  used to cap the response while every read fetched the whole table, filtered and sorted in memory,
  and then sliced — so `list_tasks(limit: 1)` and `list_tasks(limit: 5000)` did identical work.
  Detail lookups take a predicate and `fetchLimit = 1`; a container-scoped read resolves the
  container and walks its `tasks` / `notes` / `links` edge rather than filtering a whole table by
  `area?.id`; simple status, kind, archived and date filters go into the predicate.
  `CadenceReadService.fetchedRowCount` is the instrument — it counts rows materialised through a
  fetch descriptor, and `CadenceReadServiceTests` asserts bounded numbers against it. Full-text
  scoring, the explicit `statuses` filter and the **sort** are not pushable, so `offset`/`limit`
  still slice in memory; that is **settled, not deferred** (T-415, X-09) — see the reference.

## What The Create And Update Arms Cover

_Displaced verbatim from `CadenceMCPServer/AGENTS.md` on 2026-09-26 (T-1391), which had no
headroom left under its 199-line budget. The rule stays in the guide; the argument, the
measurement and the enumeration are here._

- **The write surface can mint, re-shape, rename and retire a context or a list — and cannot
  delete one** (T-799, T-1095, T-1120). The create arms exist because `create_task` took a
  `containerId` the surface could not produce and a `sectionName` it refused unless the column
  already existed, so a kanban board could not be seeded at all. `update_context` and
  `update_container` are the editors for everything that is not a task or a column: name,
  description, colour, icon, filing, due date, **status/`isArchived`**, and — since [[T-1182]] — a
  **position** plus the two `hide*IfEmpty` flags. A position is a zero-based index into the
  destination bucket, not the stored number, and the arm renumbers that whole bucket densely;
  re-filing alone still renumbers nothing. `linkedCalendarID` stays refused, on T-390's opacity and
  the absence of any picker here; the reasoning is on `CadenceUpdateContainerOptions`.
  **`create_link`, `create_tag`, `create_list_note`, `create_task_bundle` and `add_task_to_bundle`
  are the constructors outside the context/list/task triangle, and there is no kind left that this
  surface cannot mint ([[T-1122]]; `create_goal` and `create_habit` were two more until [[T-2077]]
  removed them, because the app itself stopped minting either).** Every refusal in this family
  shared one shape — no eligible owner this target can compile — and the section above, "Why one
  kind had no constructor", records which fell and to what. Do not re-decide any of them from a
  summary.
  **Nothing deletes anything, and that is settled, not deferred.** Two measured reasons, either
  sufficient — the cascade is unreachable from this target, and `deleteContext` walks *local*
  relationship arrays so it could not honestly report what it removed — written out on
  `CadenceUpdateContextOptions` and in `../docs/MCP_AGENTS_REFERENCE.md`, "Why deletion is refused".
  Archiving is offered instead: reversible from the same tool, destroys nothing, and it is
  `update_container_columns`' own argument about column removal one size up.

## Why Ten Shared Files Joined The Sources Phase

_Displaced verbatim from `CadenceMCPServer/AGENTS.md` on 2026-09-26 (T-1391), which had no
headroom left under its 199-line budget. The rule stays in the guide; the argument, the
measurement and the enumeration are here._

- **Ten `Cadence/Shared/` files are in the Sources phase, and never for the obvious reason.**
  Three came with `update_container_columns` and not for the one T-1095 predicted — the merge's
  `base`/`edited`/`current` is *not* what earns them; `applySectionNameChanges` is (without it a
  rename strands every card on a name no column has), plus `mutateSectionConfigs`' T-915 guard and
  `CadencePendingChangePersistence`. The fourth came with `create_link`, and not for the
  persistence half it is named after — `saveNotifyAndAudit` owns the commit here — but for
  `CadenceSavedLinkURL.normalized`, T-509's case-insensitive scheme rule, which a third hand-rolled
  copy would re-break. The last four came with `create_goal`/`create_habit`; why that is four files
  rather than one is in the reference, "Why the tracking helpers cost four files". The ninth came
  with `create_list_note`, and it was for a while the only one that cost a **split** rather than a
  file (the eleventh, below, is the second):
  `CadenceListNoteFiling` carries `CadenceNoteFolderPath.normalized` and the seeded `# Title`, and
  it had to be lifted out of a file declaring four SwiftUI views before it was eligible at all.
  Full reasoning in T-1095's and T-1122's ledger entries. Adding a file here is still not casual: it is another
  path by which an app-side edit breaks a target no scheme builds.

**The count has been nine, thirteen and ten, and the heading now tracks it.** `mcpfinish`
re-measured on 2026-10-06 and found **thirteen**, not nine: the ninth above was the last one
anybody had written down, and four more had arrived since. It kept the heading at *nine* because
`CadenceTests/AgentContextBudgetTests.guideReferencePairings` pins this title as a string
`CadenceMCPServer/AGENTS.md` must still quote, so renaming it is a three-file edit — guide,
reference and test — that has to land in one commit or the test reddens. [[T-3010]] (`3be4b126`,
agent `mcpsources`) made that edit, and the number it settled on is **ten**.

**What [[T-3010]] removed, and why the removal is the lesson rather than the arithmetic.** Of the
four files the tracking helpers brought, `CadenceOrderAllocation` earns its place independently of
the arms it arrived with — `create_tag` and `create_container` both call `nextOrder`
(`CadenceWriteService.swift:1368` and `:1429`) — and stays. The other three,
`CadenceTrackingMutationSupport`, `GoalAssignmentRules` and `CadencePluralization`, had had **no
caller anywhere in this target** since [[T-2077]] removed `create_goal` and `create_habit` at
0.14.0, and were still being compiled into it. Each declares exactly one top-level `enum` and
nothing else — no extension, no free function, no conformance — so a static member can only be
reached through the type name; sweeping all 56 files of the phase for the three type names returned
each file's own declaration and one doc comment, and a second sweep of the member names found no
unqualified use. **Only the membership went**: the three `PBXBuildFile` entries and their Sources
lines, with the `PBXFileReference` entries and group children kept, because all three still have
app callers (`GoalAssignmentRules` has 68 references outside its own file). **The standing rule
this leaves behind:** retiring a tool arm does not retire the files it dragged in, and nothing in
this repository notices — no scheme builds this target, and dead weight here emits no diagnostic.
Sweep the phase when an arm is removed, not only when one is added.

**The count is ELEVEN since [[T-1122]]'s eighth pass (2026-10-07), and the eleventh is the second
file here that cost a SPLIT rather than a file.** `Cadence/Shared/CadenceTaskBundleMutationSupport.swift`
joined with `create_task_bundle` and `add_task_to_bundle`. The heading above still says *ten* for
the reason the paragraph before last gives — `AgentContextBudgetTests.guideReferencePairings` pins
it as a string the guide must quote, so renaming it is a three-file edit — and the measured number
is the one to take. **What is worth carrying away is the shape of the split, which is not
`CadenceListNoteFiling`'s.** That one moved a *type* out of a file full of SwiftUI views. This one
could not: the five bundle members are `static` on `enum CadenceTaskMutationSupport`, whose name
three source-text scans pin by spelling at their call sites —
`CadenceCreateTaskCommitSurfaceTests` against `iOSCalendarQuickCreateSheet`, and both
`CadenceBundleCreationParityTests` and `CadenceSaveCommitDisciplineTests` against
`SchedulingService` — so moving them to a second type was a re-point worth three or four suites,
and an `extension` in the new file would still have required the old one to declare the enum,
which was the whole problem. **So the DECLARATION moved and the old file became the extension.**
The new file declares the enum on `Foundation`/`SwiftData` alone and holds six members — the four
clamps-and-constructor plus `assignTask(_:to:)`, the five-field membership rule — while
`CadenceTaskMutationSupport.swift` keeps the other sixty-two and reaches `NotificationManager` and
WidgetKit as it always did. Every call site and every pin stayed character-identical, and the
whole type-reference closure of the new file — `AppTask`, `TaskBundle`,
`CadencePendingChangePersistence`, `ModelContext` — was already in the phase, so nothing followed
it in. The inverse direction was costed and **refused**: splitting
`CadenceTaskReopenWidgetEffects.live` out instead would turn red
`CadenceTests/CadenceCodexWidgetReopenTests.swift`, which scans
`Cadence/Shared/CadenceTaskMutationSupport.swift` **by path** for that body, and it was dearer
besides — the whole 1,788-line file needs three more, one of which imports SwiftUI. Do not
re-cost it.
