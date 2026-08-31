# Cadence Claude Guide

Keep this file small. Claude Code loads `CLAUDE.md` as startup context, so this file is a routing
layer, not the full product history. The long former guide lives at `docs/CLAUDE_REFERENCE.md`;
read only the section you need.

## First Reads

1. Read `AGENTS.md` first. It is the authoritative working map for build commands, warning
   baseline, red-run triage, and non-negotiable repo rules.
2. Before editing inside a scoped subtree, read that subtree's nearest `AGENTS.md`.
3. Do not bulk-read the repo. Search for symbols/files with `rg`, then open only the relevant
   files and local guide sections.
4. For unfamiliar work, skim `docs/CONTEXT_INDEX.md` before opening long references.

## Context Budget Rules

- Prefer targeted source search over loading inventories, TODO history, or full feature lists.
- Treat stale prose as weaker than code and tests. If docs disagree with source, say so and follow
  the code.
- Keep new durable notes short. Put rare debugging narratives in `docs/TODO.md` or another linked
  reference, not here.
- When adding a new always-read rule, remove or link out something else.

## Project Shape

Cadence is a native SwiftUI productivity app with:

- macOS as the primary product surface.
- A large, real iOS/iPadOS surface, not a stub.
- Shared SwiftData models, CloudKit sync, widgets, EventKit calendar/reminder integration, notes,
  markdown support, local notifications, data export/reset, and an MCP server/plugin boundary.

Main paths:

- `Cadence/Models/` - SwiftData models. Read `Cadence/Models/AGENTS.md` before model/schema edits.
- `Cadence/Services/` - shared services, migrations, markdown logic, notifications, MCP read/write.
- `Cadence/Shared/` - theme tokens, shared UI/components, date/time utilities, cross-platform helpers.
- `Cadence/macOS/` - primary desktop app surface.
- `Cadence/iOS/` - adaptive iPhone/iPad app surface.
- `CadenceWidgets/` - widget extension; `Cadence` scheme already builds it.
- `CadenceMCPServer/` and `plugins/cadence-mcp/` - separate MCP boundary.
- `CadenceTests/` - unit tests. Use scoped test runs only.

## Non-Negotiables

- No hardcoded colours outside `Theme.swift` and user-owned `colorHex` values. Use `Theme.*`.
- Persisted date strings are `yyyy-MM-dd`. Use `DateFormatters` / `TimeFormatters`.
- SwiftData/CloudKit to-many relationships are optional arrays (`[Type]?`); read with `?? []`, append
  by assigning a new array.
- Page headers do not describe the page the user is already on. Search rows, pickers, and empty
  states may keep subtitles.
- Use one hover/selection layer at one radius.
- Prefer shared components over near-copies.
- Do not revert unrelated user or agent changes.

## Build And Test

Run from repo root with private DerivedData:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-build-$$ build
```

Tests must be scoped to `CadenceTests`:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test \
  -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-test-$$ -only-testing:CadenceTests
```

Unscoped tests pull in `CadenceUITests`. That target could not run until 2026-08-31, when the
one-time macOS automation grant was given; it runs now, but flakes on app activation unless
launched through `scripts/xcb.sh`, which takes the test-host lock. The expected warning
baseline is zero; any new warning is a regression.

## When To Read The Long Reference

Use `docs/CLAUDE_REFERENCE.md` only for details that are not in the scoped guides or obvious from
source. Useful old section names:

- `Data Models`
- `Design System`
- `Task lists: sort, group, and row UI`
- `Today view task scope`
- `Task Creation`
- `Notes / Markdown`
- `Task Inspector`
- `Calendar / Events`
- `Task Bundles`
- `Apple Reminders`
- `Account, Privacy, and Data Safety`
- `MCP Surface`
- `Notifications`

Prefer reading the matching scoped `AGENTS.md` first; it is usually closer to the current code than
the long reference.

Additional archived agent references:

- `docs/CONTEXT_INDEX.md` - small routing map by change type.
- `docs/AGENTS_REFERENCE.md` - detailed root runbook and red-run history.
- `docs/SHARED_AGENTS_REFERENCE.md` - detailed Shared guide.
- `docs/IOS_AGENTS_REFERENCE.md` - detailed iOS guide.
