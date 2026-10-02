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
  Use `./scripts/ledger-view.sh brief` / `show T-NNNN` for tickets and
  `./scripts/codex-inbox.sh show R<n>` for requests; never open either ledger whole.
- Treat stale prose as weaker than code and tests. If docs disagree with source, say so and follow
  the code.
- Keep new durable notes short. Put rare debugging narratives in `docs/TODO.md` or another linked
  reference, not here.
- When adding a new always-read rule, remove or link out something else.

## Rules And Verification

Use [AGENTS.md: Project Snapshot](AGENTS.md#project-snapshot) and
[Where Things Live](AGENTS.md#where-things-live) for targets and the directory map.
[Non-Negotiable Patterns](AGENTS.md#non-negotiable-patterns) owns the colour, date, relationship,
header, hover, shared-component and unrelated-change rules; they all still apply.

Follow [Build And Run Safety](AGENTS.md#build-and-run-safety) and
[Red-Run Triage](AGENTS.md#red-run-triage). Use `scripts/xcb.sh <id> build|test` with private
DerivedData, scope unit tests to `CadenceTests`, and hold the zero compiler-warning baseline.
macOS UI tests can run, but require an unlocked screen and the wrapper's test-host lock:
`scripts/xcb.sh <id> test -only-testing:CadenceUITests`, never bare `xcodebuild`.
Detailed incident history belongs in `docs/AGENTS_REFERENCE.md`, not startup context.

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
