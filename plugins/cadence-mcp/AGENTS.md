# Cadence MCP Plugin Guide

This plugin wraps Cadence MCP workflows for coding agents. It is separate from the main app UI and should not be touched during unrelated refactors.

## Working Rules

- Keep scripts deterministic and safe to run repeatedly.
- Do not assume the macOS app is open unless the script explicitly checks/launches it.
- Preserve command-line output that other agents or smoke tests parse.
- Coordinate schema/response changes with `CadenceMCPServer/` and app model changes.

## Verification

Run the plugin smoke test script after changing plugin behavior.
