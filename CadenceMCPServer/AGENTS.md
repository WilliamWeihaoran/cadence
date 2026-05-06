# Cadence MCP Server Guide

This subtree is an integration boundary for the Cadence MCP server. Do not edit it during normal app UI/model refactors unless the task explicitly asks for MCP work.

## Working Rules

- Keep MCP behavior read-oriented unless the requested change clearly adds write capability.
- Treat app model shape changes as compatibility-sensitive. If models change, update serializers/responses deliberately.
- Prefer stable response schemas over exposing raw SwiftData models.
- Avoid coupling MCP server code to macOS-only UI concepts.

## Verification

Use existing MCP smoke tests/scripts when changing this subtree, and also build the app target if shared model code changed.
