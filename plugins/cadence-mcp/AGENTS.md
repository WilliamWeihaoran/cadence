# Cadence MCP Plugin Guide

This plugin wraps Cadence MCP workflows for coding agents: a launcher script and
`scripts/smoke-test.py`, which is the **only** thing exercising `CadenceMCPServer`'s router,
tool definitions and argument parsing — none of that subtree has unit coverage.

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
never touches the app-group store. It does rebuild into the shared DerivedData with no private
path override — see the `-derivedDataPath` non-negotiable in the root `AGENTS.md` before running
it alongside a live app or another build.
