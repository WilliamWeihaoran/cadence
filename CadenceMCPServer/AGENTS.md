# Cadence MCP Server Guide

This is the canonical description of the MCP boundary. The other guides that mention it
(`../AGENTS.md`, `../CLAUDE.md`, `../docs/CLAUDE_REFERENCE.md`, `../Cadence/Services/AGENTS.md`,
`../plugins/cadence-mcp/AGENTS.md`) state the procedure in one line and point here.
The measured detail behind several rules below — commit archaeology, the T-259/T-409/T-415
histories, the build-log forensics — lives in `../docs/MCP_AGENTS_REFERENCE.md`. Read the section a
pointer names; do not load it by default.

## The rule is a procedure, not a prohibition

The old ban — *"do not edit it during normal app UI/model refactors unless the task explicitly asks
for MCP work,"* carried by four other guides, was written by anticipation rather than by incident,
and obeying it produces either a broken target or, worse because nothing goes red, a silently stale
response schema. Both have happened: `../docs/MCP_AGENTS_REFERENCE.md`, "Why the prohibition was wrong".

What replaces it: **when model or shared-service code changes, review this boundary deliberately.**
Build it on its own scheme into a private `-derivedDataPath`, grep the log for warnings, and change
response DTOs on purpose or not at all. Do not redesign the tool surface as a side effect of a UI
refactor — that part of the old rule was right, it was just spelled as a ban on reading the folder.

## Why app→MCP coupling is silent

`CadenceMCPServer` is a command-line tool target with an **explicit** Sources build phase: it
compiles a hand-picked subset of app source directly, not a framework. Currently that is most of
`Cadence/Models/`, all of `Cadence/Services/MCPReadOnly/`, eight `Services/` files —
`CadenceSchema`, `CadenceStoreSupport`, `NoteMigrationService`, `DataIntegrityRepairService`,
`TagSupport`, `NoteReferenceSupport`, `MarkdownMetadataSupport`, `CadenceHabitCompletionStore` —
and **all ten** `Shared/` files, enumerated because a list that drops a name reads as the phase
not holding it: `CadenceSearchMatcher`, `DateFormatters`, `CadenceTaskRecurrenceWorkflowSupport`,
`CadencePendingChangePersistence`, `CadenceSectionConfigMerge`, `CadenceSectionEditingSupport`,
`CadenceDefaults`, `CadenceSavedLinkPersistence`, `CadenceOrderAllocation`,
`CadenceListNoteFiling` — plus this folder's four files.
**Adding a file to `Models/` does not add it here.** A new type that an existing compiled file
references is a link error in this target and nothing at all in the app.

It is also the only target on `SWIFT_VERSION = 6.0` with `SWIFT_STRICT_CONCURRENCY = targeted` and
**without** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an isolation mismatch that is only a
warning in the app is an error here. That is why a `nonisolated` enum in `Models/` is load-bearing
(see `Cadence/Models/AGENTS.md`), and why a change that compiles in a view is no evidence at all
that it compiles here.

## What crosses the boundary, and what it can do

`Cadence/Services/MCPReadOnly/` is compiled into **both** the app and this target.
`CadenceReadService` / `CadenceWriteService` are the app-side half; `CadenceMCPToolDefinitions`,
`CadenceMCPToolRouter` and `CadenceMCPArgumentParsing` are the wire half.

- **The write path mutates the real store, from a second process, with no UI and no confirmation.**
  `CadenceModelContainerFactory.makeReadWriteContainer()` opens the app-group store with
  `allowsSave: true` — the same file the running app has open — gated on `CADENCE_MCP_ENABLE_WRITES`
  and read-only by default. **Sixteen arms** write and save, and every one of them goes through
  `saveNotifyAndAudit(_:inserted:undo:)`, so a refused save is undone rather than left pending for
  somebody else's commit (T-1121, T-1181). `mcp-audit.log` beside the store is the only record, and
  `CadenceMCPRefreshCoordinator` (macOS Services) watches a `.cadence-mcp-refresh` marker file so the
  app reloads after an external write. **`bulk_cancel_tasks` selects by *pattern*, so it alone has a
  breadth control** ([[T-1365]]): `titlePrefix` refuses a selection above
  `CadenceMCPServiceSupport.maximumPageSize` naming the count it matched, `dryRun` returns that
  selection uncapped without cancelling, and the 8-character floor was only ever a typo guard.
  Treat a write-path change as a data-safety change. The sixteen arms by name, and why `taskIds`
  stays uncapped: `../docs/MCP_AGENTS_REFERENCE.md`, "What the write path does to the real store"
  and "Why bulk cancel got a cap and a dry run".
- **Both containers open the owner's CloudKit-MIRRORED store with `cloudKitDatabase: .none`**
  ([[T-3018]]). `makeReadOnlyContainer()` and `makeReadWriteContainer()` resolve
  `CadenceStoreSupport.primaryStoreURL()` and pass `.none`
  (`Cadence/Services/MCPReadOnly/CadenceModelContainerFactory.swift:68-93`), while the running app
  has that same file open with `.private("iCloud.com.haoranwei.Cadence")`
  (`Cadence/Services/PersistenceController.swift:384`). The read-only one is `allowsSave: false`
  and harmless. The read-write one is `allowsSave: true` — **one store open under two different
  configurations**, [[T-2053]]'s family again — and what follows is not a sync *delay*: a writer
  whose container has mirroring off does not maintain the mirroring metadata the app's own
  container exports from, so **an MCP write may never reach the owner's other devices, and may
  not register there as a change at all**. Nothing in the write path says so and no test can say
  it: this target is not unit-executed, and the only store a test or a script may point at is a
  throwaway. Whether an out-of-process writer should mirror, refuse, or keep running the repair
  named in the next bullet is an **owner decision about the sync contract**, open in [[T-3018]];
  do not settle it as a side effect of a write-path change.
- Opening the read-write container also runs `CadenceMCPStorePreparation.prepare` — note
  migration, tag **sync**, integrity repair — against live data. A migration bug reaches users
  through this door as much as through app launch. The tag **seed** was a fourth step until T-528
  removed it, on the argument the bullet above restates; **the repair was left, and it is the
  destructive one** — `DataIntegrityRepairService` deletes duplicate `Context`, `Area`, `Project`
  and `Note` rows and saves, with no user in front of it, from a process that is not the app.
- **Nothing under `CadenceMCPServer/` is unit-*executed*.** `CadenceTests` covers the app-side half
  (`CadenceReadServiceTests`, `CadenceWriteServiceTests`, `CadenceSearchMatcherTests`); the router,
  the tool definitions and the argument parsing are *run* only by
  `plugins/cadence-mcp/scripts/smoke-test.py`, because none of those three files is in the app
  target's Sources phase and `CadenceTests` therefore cannot even reference a symbol in them.
  `CadenceMCPToolContractTests` is a **source scan**, not an execution, so do not read it as
  behavioural coverage of the router. The four things it does pin:
  `../docs/MCP_AGENTS_REFERENCE.md`, "What is and is not executed under this target".
- **The smoke test dispatches all 38 arms and asserts that it does.** It drives a full create →
  update → schedule → complete → reopen → cancel lifecycle against the fixture store, asserts the
  resulting DTO key sets, and records every `tools/call` so an unexercised arm fails the run. Its
  error-path checks assert the error *text*: a deleted arm answers "Unknown tool" and a renamed
  argument key answers "Missing required argument", and a bare `isError` check is green for both.
  What it missed before T-259, and why, is in the reference.
- **The 38 tool names are a contract in three places at once**: `CadenceMCPToolDefinitions.swift`
  (the advertised schema), `CadenceMCPToolRouter.swift` (38 `case` arms), and the smoke test's
  expectations. Renaming or adding one means all three, and the definitions/router pair will
  compile perfectly while disagreeing. `CadenceTests/CadenceMCPToolContractTests.swift` is the
  guard: it fails when those three sets diverge, and separately when
  `CadenceMCPToolDefinitions.writeToolNames`, the router arms that call `requireWriteService`, and
  the smoke test's `WRITE_TOOLS` stop naming the same sixteen tools. That second assertion is the
  data-safety one — a mutating arm missing from `writeToolNames` is **advertised and executable in
  the default read-only mode**, which is not a typo-class failure.

## Verification

Build **this** scheme; the `Cadence` scheme staying green is the thing that hides the break.
`CadenceTests/CadenceTargetSourceMembershipTests.swift` catches the commonest shape of it from
inside the app scheme (T-409), but it sees types, not free functions or extension members.

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Cadence.xcodeproj -scheme CadenceMCPServer -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-mcp-$$ build 2>&1 | tee /tmp/mcp-build-$$.log
```

Then **grep the log**, with no path filter. Exit 0 says nothing about warnings, and a `grep
"/Cadence/"` misses the synthesized-macro paths a real isolation regression surfaced under — both
measured, both in the reference. The private `-derivedDataPath` is not optional; see the
non-negotiable in `../AGENTS.md` for what the shared one does to a running app.

Run `plugins/cadence-mcp/scripts/smoke-test.py` after any router, tool-definition or
argument-parsing change. It verifies read-only mode and then drives a temp fixture store via
`CADENCE_MCP_STORE_URL`, so it never touches the app-group store: `resolvedStoreURL()` prefers that
override over `CadenceStoreSupport.primaryStoreURL()`, and `auditLogURL()` and `refreshMarkerURL()`
derive from it, so the entire write path lands in the temp directory. That is the whole safety
argument — check it in `CadenceModelContainerFactory.swift` rather than trusting this line. Set
`CADENCE_MCP_DERIVED_DATA` to a path you have **already** built into, or the launcher rebuilds into
the shared `.codex-build` and the lazy build outlasts the 45-second per-response timeout, failing
as `timed out waiting for response 100` rather than naming a build.

## Working Rules

- **Every `list_*` tool, `search_cadence`, `get_recent_mcp_writes` and each of `get_today_brief`'s
  four task sections answer with `CadencePage`, not a bare array** (T-382, and T-385 for the brief
  — the undisclosed `prefix(50)` that turned 51 inbox tasks into 50 is in the reference). The
  envelope is `items`, `offset`, `returnedCount`, `totalCount`, `hasMore`, `nextOffset`, declared
  once in `Cadence/Services/MCPReadOnly/CadenceReadDTOs.swift`. Add a new list tool through
  `CadencePage.paging` and give it an `offset` argument beside its `limit`; a `hasMore: true` the
  caller cannot act on is worse than the silent truncation the envelope replaced. `CadenceTests`
  pins the schema/router halves of that pairing by scan
  (`everyLimitBearingToolAdvertisesTheOffsetThatMakesHasMoreActionable`), because nothing here is
  unit-executed.
- **`CadencePage.paging` takes one already-ordered candidate list, so a tool that draws from two
  sources must merge before it pages.** `listContainers` used to sort areas and projects
  separately, concatenate, and cap — returning zero projects whenever areas outnumbered the limit
  (T-383, reproducible after T-372). `CadenceMCPOrdering.precedes` is total across kinds already;
  use it on one merged list rather than re-introducing a per-kind cap.
- **Reads go through `fetchAll` / `fetchFirst`, never a bare `FetchDescriptor`** (T-384). Detail
  lookups take a predicate and `fetchLimit = 1`; a container-scoped read walks the resolved
  container's `tasks` / `notes` / `links` edge rather than filtering a whole table by `area?.id`;
  simple status, kind, archived and date filters go into the predicate.
  `CadenceReadService.fetchedRowCount` is the instrument `CadenceReadServiceTests` asserts bounded
  numbers against. Full-text scoring, the explicit `statuses` filter and the **sort** are not
  pushable, so `offset`/`limit` still slice in memory: **settled, not deferred** (T-415, X-09).
  Both measurements: `../docs/MCP_AGENTS_REFERENCE.md`, "Why the reads fetch what they return" and
  "Why in-memory sort is settled, not deferred".
- **Read-write startup prepares the store exactly once** (T-309). The four-step sequence — note
  migration, tag seeding, tag sync, integrity repair — lives in `CadenceMCPStorePreparation.prepare`
  and is run by `makeReadWriteContainer()`. `main.swift` then passes `performsMigrations: false` and
  `preparesStore: false`, because the services default to preparing and used to re-run the sequence
  twice more over the same context, against a live store, before any tool call. Do not guard inside
  `prepare` instead: the flag is readable at the call site, which is where the mistake was.
- **The write surface can mint, re-shape, rename and retire a context or a list — and cannot delete
  one** (T-799, T-1095, T-1120). `update_context` and `update_container` are the editors for
  everything that is not a task or a column: name, description, colour, icon, filing, due date,
  **status/`isArchived`**, and — since [[T-1182]] — a **position** (a zero-based index into the
  destination bucket, which the arm renumbers densely; re-filing alone renumbers nothing) plus the
  two `hide*IfEmpty` flags. `linkedCalendarID` stays refused, on T-390's opacity. `create_link`,
  `create_tag` and `create_list_note` are the constructors outside the context/list/task triangle;
  nothing creates a task bundle, and **nothing deletes anything** — each of those **refused with a
  measurement**, settled rather than deferred ([[T-1122]]). **`create_goal` and `create_habit` were
  two more until [[T-2077]] removed them**, with the version going 0.13.0 -> 0.14.0: the owner
  retired goals and habits and the app itself stopped writing either model, so a write surface that
  kept minting them would have been the one exception. They **disappear** from `tools/list` rather
  than remaining advertised and refusing — that list is the only capability contract a client can
  read. `list_goals`, `get_goal` and `list_habits` still read the existing rows.
  Archiving is offered instead. **`create_list_note` is the one whose refusal was lifted by moving
  a file, and the shape of that measurement is the thing to carry away**: the blocker was never the
  arm, it was that `CadenceListNoteFiling.createNote` shared a file with the four SwiftUI rows that
  draw folders and a Sources phase compiles whole files.
  `Cadence/Shared/CadenceListNoteFiling.swift` is the split that lifted it. The arm still takes no
  **body**, and that refusal is scoped and measured too: a list note's `title` is the first `# H1`
  of its content, and `MarkdownNoteTitleSync` — the rule holding those equal on every app commit —
  is in `MarkdownNoteSupport.swift`, which this target does not compile, so the note is seeded
  `# title` and cannot be born disagreeing with itself. **`create_tag` was itself refused twice and is the
  one to read before adding another arm shaped like it** ([[T-1406]]): it exists only because
  `TagSupport.creationDecision(for:in:)` came to own the rule both Settings editors hand-rolled,
  and its `unarchive` argument is [[T-1365]]'s answer to a branch whose app-side reply is a button
  a headless caller cannot press. It does **not** change how `create_task(tagNames:)` mints tags —
  that path keeps `TagSupport.resolution`, the app's *attachment* rule, and the two are different
  questions rather than two spellings of one. Do not re-decide any of it from a summary:
  `../docs/MCP_AGENTS_REFERENCE.md`, "What the create and update arms cover", "Why one kind has
  no constructor" and "Why deletion is refused".
- **Ten `Cadence/Shared/` files are in the Sources phase, and none of them earns its place for the
  obvious reason.** Each earns it by one rule a hand-rolled copy would re-break — a rename that
  would otherwise strand every card on a name no column has, T-509's case-insensitive scheme rule
  — never by the feature it arrived with. Adding another is still not casual: one more path by
  which an app-side edit breaks a target no scheme builds — and `CadenceListNoteFiling` cost a
  file **split** rather than a file ([[T-1122]]). **A file stops earning it, too, and then it
  goes**: `CadenceTrackingMutationSupport`, `GoalAssignmentRules` and `CadencePluralization` lost
  their last caller here when [[T-2077]] removed `create_goal`/`create_habit`, and [[T-3010]] took
  all three out of the phase while leaving them on disk for the app. Sweep when an arm is retired,
  not only when one is added. What each is for: `../docs/MCP_AGENTS_REFERENCE.md`, "Why ten shared
  files joined the Sources phase" and "Why the tracking helpers cost four files".
- **The MCP write path's equivalent of "name the failure on screen" is the thrown error the router
  renders as `isError`, plus an undo, and every arm now has both halves** (T-1121). One long-lived
  `ModelContext` per process means a refused `save()` used to leave the mutation *pending* for the
  next tool call's `save()` — a write the caller was told had failed, landing later from a call that
  never mentioned it. How `saveNotifyAndAudit` composes the two `CadencePendingChangePersistence`
  primitives, why that is not a `rollback()`, and why two field snapshots stay local to this file:
  `../docs/MCP_AGENTS_REFERENCE.md`, "Why the write path's undo is two composed primitives".
