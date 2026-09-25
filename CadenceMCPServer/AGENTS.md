# Cadence MCP Server Guide

This is the canonical description of the MCP boundary. The other guides that mention it
(`../AGENTS.md`, `../CLAUDE.md`, `../docs/CLAUDE_REFERENCE.md`, `../Cadence/Services/AGENTS.md`,
`../plugins/cadence-mcp/AGENTS.md`) state the procedure in one line and point here.
The measured detail behind several rules below — commit archaeology, the T-259/T-409/T-415
histories, the build-log forensics — lives in `../docs/MCP_AGENTS_REFERENCE.md`. Read the section a
pointer names; do not load it by default.

## The rule is a procedure, not a prohibition

This file used to say *"do not edit it during normal app UI/model refactors unless the task
explicitly asks for MCP work,"* and four other guides carried a variant. It was written by
anticipation rather than by incident, and roughly half the commits touching these paths are not MCP
work and *had* to reach in — so it cannot mean what it says. Obeying it produces either **a broken
target** or **a silently stale response schema**, and the second is worse because nothing goes red.
Both have happened; the commits are in the reference, under "Why the prohibition was wrong".

What replaces it: **when model or shared-service code changes, review this boundary deliberately.**
Build it on its own scheme into a private `-derivedDataPath`, grep the log for warnings, and change
response DTOs on purpose or not at all. Do not redesign the tool surface as a side effect of a UI
refactor — that part of the old rule was right, it was just spelled as a ban on reading the folder.

## Why app→MCP coupling is silent

`CadenceMCPServer` is a command-line tool target with an **explicit** Sources build phase: it
compiles a hand-picked subset of app source directly, not a framework. Currently that is most of
`Cadence/Models/`, all of `Cadence/Services/MCPReadOnly/`, and a short list of shared services —
`CadenceSchema`, `CadenceStoreSupport`, `NoteMigrationService`, `DataIntegrityRepairService`,
`TagSupport`, `NoteReferenceSupport`, `MarkdownMetadataSupport`, `CadenceHabitCompletionStore`,
`CadenceSearchMatcher`, `Shared/CadenceTaskRecurrenceWorkflowSupport`, `Shared/DateFormatters`,
`Shared/CadencePendingChangePersistence`, `Shared/CadenceSectionConfigMerge`,
`Shared/CadenceSectionEditingSupport`, `Shared/CadenceDefaults`,
`Shared/CadenceSavedLinkPersistence` — plus this folder's four files.
**Adding a file to `Models/` does not add it here.** A new type that an existing compiled file
references is a link error in this target and nothing at all in the app.

It is also the only target on `SWIFT_VERSION = 6.0` with `SWIFT_STRICT_CONCURRENCY = targeted` and
**without** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The app and the widgets default their
value types to the main actor; this target does not, and it is on Swift 6, where the isolation
mismatch is an error rather than a warning. That asymmetry is the whole reason a `nonisolated`
enum in `Models/` is load-bearing (see `Cadence/Models/AGENTS.md`) and the reason a change that
compiles in a view is not evidence it compiles here.

## What crosses the boundary, and what it can do

`Cadence/Services/MCPReadOnly/` is compiled into **both** the app and this target.
`CadenceReadService` / `CadenceWriteService` are the app-side half; `CadenceMCPToolDefinitions`,
`CadenceMCPToolRouter` and `CadenceMCPArgumentParsing` are the wire half.

- **The write path mutates the real store, from a second process, with no UI and no undo.**
  `CadenceModelContainerFactory.makeReadWriteContainer()` opens the app-group store
  (`group.com.haoranwei.Cadence`, `Library/Application Support/Cadence/default.store`) with
  `allowsSave: true` — the same file the running app has open. It is gated on the
  `CADENCE_MCP_ENABLE_WRITES` environment flag and defaults to read-only, but when enabled there is
  no confirmation step: `createContext`, `updateContext`, `createContainer`, `updateContainer`,
  `updateContainerColumns`, `createTask`, `updateTask`, `scheduleTask`, `completeTask`,
  `reopenTask`, `cancelTask`, `bulkCancelTasks`, `appendCoreNote`, `createSavedLink`, `createGoal`
  and `createHabit` — **sixteen arms** — write and save. *No undo stack* is no longer true of any
  of them (T-1121): every arm goes through `saveNotifyAndAudit(_:inserted:undo:)`, which un-inserts
  what the call added and restores what it changed in place before the caller is told. The one
  residue went with it (T-1181): the core-note accessors take a `commit:` and `append_core_note`
  defers their insert into its own `inserted:` list. `mcp-audit.log` beside the store is
  `.cadence-mcp-refresh` marker file so the app reloads after an external write. Treat a write-path
  change as a data-safety change.
- Opening the read-write container also runs `NoteMigrationService`, `TagSupport` seeding/sync and
  `DataIntegrityRepairService` against live data. A migration bug reaches users through this door
  as much as through app launch.
- **Nothing under `CadenceMCPServer/` is unit-*executed*.** `CadenceTests` covers the app-side half
  (`CadenceReadServiceTests`, `CadenceWriteServiceTests`, `CadenceSearchMatcherTests`); the router,
  the tool definitions and the argument parsing are *run* only by
  `plugins/cadence-mcp/scripts/smoke-test.py`, because none of those three files is in the app
  target's Sources phase and `CadenceTests` therefore cannot even reference a symbol in them.
  `CadenceMCPToolContractTests` is a **source scan**, not an execution: it pins the three-way name
  contract below, the write gate, that every non-private helper in `CadenceMCPArgumentParsing` has
  a router call site, and that the smoke test still checks its own dispatch coverage. Do not read
  it as behavioural coverage of the router.
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

Build **this** scheme. The old advice here was "build the app target if shared model code changed",
which is exactly backwards — the `Cadence` scheme staying green is the thing that hides the break.
`CadenceTests/CadenceTargetSourceMembershipTests.swift` catches the commonest shape of it from
inside the app scheme (T-409) by reading this target's Sources phase, but it sees types, not free
functions or extension members: it narrows the window rather than closing it.

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
- **Read-write startup prepares the store exactly once** (T-309). The four-step sequence — note
  migration, tag seeding, tag sync, integrity repair — lives in `CadenceMCPStorePreparation.prepare`
  and is run by `makeReadWriteContainer()`. `main.swift` then passes `performsMigrations: false` and
  `preparesStore: false`, because the services default to preparing and used to re-run the sequence
  twice more over the same context, against a live store, before any tool call. Do not guard inside
  `prepare` instead: the flag is readable at the call site, which is where the mistake was.
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
  **`create_link`, `create_goal` and `create_habit` are the constructors outside the
  context/list/task triangle; nothing creates a tag, a list note or a task bundle, and those three
  are *refused with a measurement* rather than undecided ([[T-1122]]).** All three refusals share
  one shape — no eligible owner this target can compile — and are in the reference, "Why three
  kinds have no constructor". Do not re-decide any of them from a summary.
  **Nothing deletes anything, and that is settled, not deferred.** Two measured reasons, either
  sufficient — the cascade is unreachable from this target, and `deleteContext` walks *local*
  relationship arrays so it could not honestly report what it removed — written out on
  `CadenceUpdateContextOptions` and in `../docs/MCP_AGENTS_REFERENCE.md`, "Why deletion is refused".
  Archiving is offered instead: reversible from the same tool, destroys nothing, and it is
  `update_container_columns`' own argument about column removal one size up.
- **Eight `Cadence/Shared/` files have joined the Sources phase, and never for the obvious reason.**
  Three came with `update_container_columns` and not for the one T-1095 predicted — the merge's
  `base`/`edited`/`current` is *not* what earns them; `applySectionNameChanges` is (without it a
  rename strands every card on a name no column has), plus `mutateSectionConfigs`' T-915 guard and
  `CadencePendingChangePersistence`. The fourth came with `create_link`, and not for the
  persistence half it is named after — `saveNotifyAndAudit` owns the commit here — but for
  `CadenceSavedLinkURL.normalized`, T-509's case-insensitive scheme rule, which a third hand-rolled
  copy would re-break. The last four came with `create_goal`/`create_habit`; why that is four files
  rather than one is in the reference, "Why the tracking helpers cost four files". Full reasoning
  in T-1095's and T-1122's ledger entries. Adding a file here is
- **The MCP write path's equivalent of "name the failure on screen" is the thrown error the router
  renders as `isError`, plus an undo.** The first half it always had; the second it did not.
  `CadenceWriteService` holds one long-lived `ModelContext`, so a refused `save()` left the
  mutation *pending* for the next tool call's `save()` to commit — a write the caller was told had
  failed, landing later from a call that never mentioned it. **Every arm now has both halves**
  (T-1121). `saveNotifyAndAudit(_:inserted:undo:)` *composes* the two
  `CadencePendingChangePersistence` primitives rather than re-spelling either: `commitInsert`
  deletes the rows this call added and rethrows, `commitEdit` then runs the field restore and
  rethrows. Nesting them is what gives `completeTask` — a status change **and** a spawned successor
  — one undo covering both. Neither is a `rollback()`: one long-lived context per process means a
  rollback discards whatever else is pending. Two field snapshots stay local to this file rather
  than being reused from `Cadence/Shared/`; both reasons are on the local types and in the
  reference.
