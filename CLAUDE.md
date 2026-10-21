# Cadence Claude Guide

Keep this file small. Claude Code loads `CLAUDE.md` as startup context, so this file is a routing
layer, not the full product history. The long former guide lives at `docs/CLAUDE_REFERENCE.md`;
read only the section you need.

## First Reads

1. Read `docs/AGENT_BRIEF.md` first. It is the single source for the rules you work under: build
   and test, mutation, the Codex lease, the commit gate, safety, and how to report.
2. Then `docs/SESSION_HANDOFF.md` for today's state — what landed, what is open, which reds are
   not yours. It is point-in-time; where it and the brief disagree, the brief wins.
3. Then `AGENTS.md`, the directory map and the non-negotiable repo patterns.
4. Before editing inside a scoped subtree, read that subtree's nearest `AGENTS.md`.
5. Do not bulk-read the repo. Search for symbols/files with `rg`, then open only the relevant
   files and local guide sections.
6. For unfamiliar work, skim `docs/CONTEXT_INDEX.md` before opening long references.

## Context Budget Rules

- Prefer targeted source search over loading inventories, TODO history, or full feature lists.
  For a ticket ask `./scripts/ledger-view.sh head T-NNNN` first — the entry's first line and state,
  with the addenda counted rather than printed — and `show T-NNNN` only when you need the history;
  `brief` for the open list, `./scripts/codex-inbox.sh show R<n>` for requests. Never open either
  ledger whole.
- Treat stale prose as weaker than code and tests. If docs disagree with source, say so and follow
  the code.
- Keep new durable notes short. Put rare debugging narratives in `docs/TODO.md` or another linked
  reference, not here.
- When adding a new always-read rule, remove or link out something else.

## Rules And Verification

Nothing is restated here. [docs/AGENT_BRIEF.md](docs/AGENT_BRIEF.md) owns build, test, mutation,
lease, commit-gate, safety and reporting; [AGENTS.md](AGENTS.md) owns the directory map, the
[non-negotiable patterns](AGENTS.md#non-negotiable-patterns), [build and run
safety](AGENTS.md#build-and-run-safety) and [red-run triage](AGENTS.md#red-run-triage). Detailed
incident history belongs in `docs/AGENTS_REFERENCE.md`, not startup context.

## When To Read The Long Reference

Use `docs/CLAUDE_REFERENCE.md` only for details that are not in the scoped guides or obvious from
source, and open it by **section name** rather than loading it: `docs/CONTEXT_INDEX.md` routes a
change type to the section that answers it. Prefer the matching scoped `AGENTS.md` first; it is
usually closer to the current code than the long reference.

Additional archived agent references:

- `docs/CONTEXT_INDEX.md` - small routing map by change type.
- `docs/AGENTS_REFERENCE.md` - detailed root runbook and red-run history.
- `docs/SHARED_AGENTS_REFERENCE.md` - detailed Shared guide.
- `docs/IOS_AGENTS_REFERENCE.md` - detailed iOS guide.
- `docs/audits/README.md` - index of the 47 dated audit files; says which are still cited.
