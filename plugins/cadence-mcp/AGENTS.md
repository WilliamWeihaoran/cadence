# Cadence MCP Plugin Guide

This plugin wraps Cadence MCP workflows for coding agents: a launcher script and
`scripts/smoke-test.py`, which is the **only** thing that *runs* `CadenceMCPServer`'s router, tool
definitions and argument parsing. `CadenceTests/CadenceMCPToolContractTests.swift` scans those
files as text and pins the tool-name and write-gating contracts, but executes nothing — and the
smoke test itself dispatches only 21 of the router's 30 arms, so five of the eight write tools
(`update_task`, `schedule_task`, `complete_task`, `reopen_task`, `cancel_task`) are run by nothing
at all.

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
