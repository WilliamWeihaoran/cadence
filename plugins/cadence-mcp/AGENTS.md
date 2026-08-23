# Cadence MCP Plugin Guide

This plugin wraps Cadence MCP workflows for coding agents: a launcher script and
`scripts/smoke-test.py`, which is the **only** thing that *runs* `CadenceMCPServer`'s router, tool
definitions and argument parsing. `CadenceTests/CadenceMCPToolContractTests.swift` scans those
files as text and pins the tool-name and write-gating contracts, but executes nothing.

It dispatched **21 of the router's 30 arms** until T-259 — five of the eight write tools
(`update_task`, `schedule_task`, `complete_task`, `reopen_task`, `cancel_task`) were run by
nothing at all. It now dispatches all 30, and, more to the point, **it checks that it does**: every
`tools/call` it sends is recorded in `DISPATCHED`, and the run fails if that set does not cover the
server's own `tools/list`. Adding a router arm and forgetting to exercise it is now a red smoke
test rather than a number nobody was counting. Keep that guard — a Swift test pins its presence
(`theSmokeTestStillChecksItDispatchesEveryAdvertisedTool`) precisely because deleting four lines of
Python breaks no build.

**Error paths assert the message, not just `isError`.** Half the new coverage is a not-found or
missing-argument case, and a deleted router arm answers `Unknown tool` while a renamed argument key
answers a different `Missing required argument` — both of them errors. A bare `isError` check is
green for all three, so `call_error` takes the expected text. Do not "simplify" it away.

What is still not covered: `list_task_bundles`, `list_goals`, `list_habits`, `list_links`,
`list_contexts` and `list_containers` are dispatched but return `[]`, because MCP has no tool that
creates a bundle, goal, habit, link, context or container, so a fresh fixture store cannot hold
one. `list_tasks`, `list_tags` and `list_notes` run against real rows and have their DTO shapes
checked. See T-269.

This file used to say the plugin "should not be touched during unrelated refactors". Read that as
scope, not as a ban: nothing here needs to change for a UI refactor, but the smoke test is what
you run to verify one that reached the MCP boundary, and a tool rename lands in its expectations
too. The boundary's rules live in `CadenceMCPServer/AGENTS.md`.

## Working Rules

- Keep scripts deterministic and safe to run repeatedly.
- Do not assume the macOS app is open unless the script explicitly checks/launches it.
- Preserve command-line output that other agents or smoke tests parse.
- Coordinate schema/response changes with `CadenceMCPServer/` and app model changes. The 30 tool
  names are a contract in three places — the definitions, the router's `case` arms, and this
  smoke test — and the first two can disagree while compiling.
- A new tool means a new dispatch here, not only a new name in `EXPECTED_TOOLS`. The coverage
  guard will say so.

## Verification

Run `scripts/smoke-test.py` after changing plugin behavior, and after any change to
`CadenceMCPServer/` or to the read/write services under `Cadence/Services/MCPReadOnly/`. It
verifies read-only mode and then drives a temp fixture store via `CADENCE_MCP_STORE_URL`, so it
never touches the app-group store.

`scripts/run-cadence-mcp.sh` defaults to the shared `.codex-build` so the installed plugin keeps
one warm build, but honours `CADENCE_MCP_DERIVED_DATA` — set it to a private path before verifying
a change, per the `-derivedDataPath` non-negotiable in the root `AGENTS.md`. Build that path
first: the launcher builds lazily, and a cold build outlasts the smoke test's 45-second
per-response timeout, surfacing as `timed out waiting for response 100`, which reads like a server
fault rather than an unfinished compile.
