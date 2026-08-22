# Cadence MCP Server Guide

This is the canonical description of the MCP boundary. The other guides that mention it
(`../AGENTS.md`, `../CLAUDE.md`, `../Cadence/Services/AGENTS.md`,
`../plugins/cadence-mcp/AGENTS.md`) state the procedure in one line and point here.

## The rule is a procedure, not a prohibition

This file used to say: *"Do not edit it during normal app UI/model refactors unless the task
explicitly asks for MCP work."* Four other guides carried a variant. That rule was wrong, and
being wrong in five places is what made it ignorable.

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

What replaces it: **when model or shared-service code changes, review this boundary deliberately.**
Build it on its own scheme into a private `-derivedDataPath`, grep the log for warnings, and change
response DTOs on purpose or not at all. Do not redesign the tool surface as a side effect of a UI
refactor — that part of the old rule was right, it was just spelled as a ban on reading the folder.

## Why app→MCP coupling is silent

`CadenceMCPServer` is a command-line tool target with an **explicit** Sources build phase: it
compiles a hand-picked subset of app source directly, not a framework. Currently that is most of
`Cadence/Models/`, all of `Cadence/Services/MCPReadOnly/`, and a short list of shared services —
`CadenceSchema`, `CadenceStoreSupport`, `NoteMigrationService`, `DataIntegrityRepairService`,
`TagSupport`, `NoteReferenceSupport`, `MarkdownMetadataSupport`,
`Shared/CadenceTaskRecurrenceWorkflowSupport`, `Shared/DateFormatters` — plus this folder's four
files. **Adding a file to `Models/` does not add it here.** A new type that an existing compiled
file references is a link error in this target and nothing at all in the app.

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
  no confirmation step and no undo stack: `createTask`, `updateTask`, `scheduleTask`,
  `completeTask`, `reopenTask`, `cancelTask`, `bulkCancelTasks` and `appendCoreNote` write and
  save. `mcp-audit.log` beside the store is the only record, and
  `CadenceMCPRefreshCoordinator` (macOS Services) watches a `.cadence-mcp-refresh` marker file so
  the app reloads after an external write. Treat a write-path change as a data-safety change.
- Opening the read-write container also runs `NoteMigrationService`, `TagSupport` seeding/sync and
  `DataIntegrityRepairService` against live data. A migration bug reaches users through this door
  as much as through app launch.
- **Nothing under `CadenceMCPServer/` is unit-*executed*.** `CadenceTests` covers the app-side half
  (`CadenceReadServiceTests`, `CadenceWriteServiceTests`, `CadenceSearchMatcherTests`); the router,
  the tool definitions and the argument parsing are *run* only by
  `plugins/cadence-mcp/scripts/smoke-test.py`. None of those three files is in the app target's
  Sources phase, so `CadenceTests` cannot reference a symbol in them and cannot call one.
  `CadenceMCPToolContractTests` is therefore a **source scan**, not an execution: it pins the
  three-way name contract below and the write gate, and nothing else. Do not read it as
  behavioural coverage of the router.
- **The 30 tool names are a contract in three places at once**: `CadenceMCPToolDefinitions.swift`
  (the advertised schema), `CadenceMCPToolRouter.swift` (30 `case` arms), and the smoke test's
  expectations. Renaming or adding one means all three, and the definitions/router pair will
  compile perfectly while disagreeing. `CadenceTests/CadenceMCPToolContractTests.swift` is the
  guard: it fails when those three sets diverge, and separately when
  `CadenceMCPToolDefinitions.writeToolNames`, the router arms that call `requireWriteService`, and
  the smoke test's `WRITE_TOOLS` stop naming the same eight tools. That second assertion is the
  data-safety one — a mutating arm missing from `writeToolNames` is **advertised and executable in
  the default read-only mode**, which is not a typo-class failure.

## Verification

Build **this** scheme. The old advice here was "build the app target if shared model code changed",
which is exactly backwards — the `Cadence` scheme staying green is the thing that hides the break.

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Cadence.xcodeproj -scheme CadenceMCPServer -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-mcp-$$ build 2>&1 | tee /tmp/mcp-build-$$.log
```

Then **grep the log**, with no path filter. Exit 0 says nothing about warnings: this target sat at
two warnings under a zero baseline precisely because a check read its exit status and never read
its output, and a later isolation regression surfaced only under synthesized-macro paths that a
`grep "/Cadence/"` would have missed. The private `-derivedDataPath` is not optional — see the
non-negotiable in `../AGENTS.md` for what the shared one does to a running app.

Run `plugins/cadence-mcp/scripts/smoke-test.py` after any router, tool-definition or
argument-parsing change. It verifies read-only mode and then drives a temp fixture store via
`CADENCE_MCP_STORE_URL`, so it never touches the app-group store — `resolvedStoreURL()` prefers
that override over `CadenceStoreSupport.primaryStoreURL()`, and `auditLogURL()` and
`refreshMarkerURL()` are both derived from it, so the entire write path lands in the temp
directory. That is the whole safety argument: check it in
`Cadence/Services/MCPReadOnly/CadenceModelContainerFactory.swift` rather than trusting this line.

Set `CADENCE_MCP_DERIVED_DATA` when you run it, or the launcher rebuilds into the shared
`.codex-build` the installed plugin and Codex are using. Point it at a path you have **already**
built into: the launcher builds lazily on first launch, that build outlasts the smoke test's
45-second per-response timeout, and the failure reads `timed out waiting for response 100` rather
than naming a build.

## Working Rules

- Keep MCP behavior read-oriented unless the requested change clearly adds write capability.
- Prefer stable response schemas over exposing raw SwiftData models. If a model change forces a DTO
  change, make it deliberately and update the smoke test's expectations in the same commit.
- Avoid coupling MCP server code to macOS-only UI concepts.
- Do not add app source to this target's Sources phase casually; every file added is another path
  by which a UI-side edit can break a target the app scheme does not build.
