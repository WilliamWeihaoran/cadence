# Cadence Context Index

Use this as a routing map before opening long guides. Prefer `rg` and nearby scoped guides over
loading broad histories.

## By Change Type

- SwiftData model, relationship, schema, migration, export, reset:
  `AGENTS.md`, `Cadence/Models/AGENTS.md`, `Cadence/Services/AGENTS.md`, then
  `CadenceMCPServer/AGENTS.md` if shared model/service code crosses the MCP boundary. For the
  measurement, the incident and the argument behind a model rule, open the named section of
  `docs/MODELS_AGENTS_REFERENCE.md` rather than re-deriving it.
- Shared service behaviour (deletion cascades, wind-down, export/import, push, tags, markdown
  assets): `Cadence/Services/AGENTS.md` for the rule, then the named section of
  `docs/SERVICES_AGENTS_REFERENCE.md` for the measurement, the incident and the argument.
- Shared UI/component/theme/date logic:
  `AGENTS.md`, `Cadence/Shared/AGENTS.md`, then search `docs/SHARED_AGENTS_REFERENCE.md`.
- macOS feature view or shell:
  `AGENTS.md`, `Cadence/macOS/AGENTS.md`, plus `Cadence/macOS/Views/AGENTS.md` or
  `Cadence/macOS/Services/AGENTS.md` as appropriate.
- macOS markdown editor bridge:
  `AGENTS.md`, `Cadence/macOS/Editor/AGENTS.md`; markdown parsing/mutation usually lives in
  `Cadence/Services/Markdown*Support.swift`.
- iOS/iPadOS UI:
  `AGENTS.md`, `Cadence/iOS/AGENTS.md`, then search `docs/IOS_AGENTS_REFERENCE.md` for host/shell
  details.
- MCP server/plugin:
  `AGENTS.md`, `CadenceMCPServer/AGENTS.md`, `plugins/cadence-mcp/AGENTS.md`, then search
  `docs/MCP_AGENTS_REFERENCE.md` for the boundary history the scoped guide routes out to.
- Build/test/debugging weirdness:
  `AGENTS.md` first; search `docs/AGENTS_REFERENCE.md` only for the detailed incident history.
- Verifying as a subagent (scratch trees, the test-host lock, mutation runs, committing out of the
  shared checkout): `docs/SUBAGENT_RUNBOOK.md` is the mandatory section and the whole of it; open
  the one named section of `docs/SUBAGENT_RUNBOOK_REFERENCE.md` its routing table sends you to.
- Product/feature history:
  Search `docs/CLAUDE_REFERENCE.md` by section name.
- A September 2026 audit, or whether one is still load-bearing:
  `docs/audits/README.md` — one row per report, with its headline finding, whether anything still
  cites it, and who. Audits are dated record and are never edited; read the index before the
  report, and never open `docs/audits/2026-09-25/queue-inventory.json` (1.2 MB) or
  `docs/audits/2026-09-20/request-queue/source-candidates.tsv` (968 KB) whole.

## Common Searches

- Type declaration: `rg -n "struct TypeName|enum TypeName|class TypeName|extension TypeName"`
- SwiftData relationship rule: `rg -n "relationship|\\[.*\\]\\?" Cadence/Models Cadence/Services`
- Hardcoded colour sweep: `rg -n "Color\\(|\\.white|\\.black|\\.gray" Cadence CadenceWidgets`
- Date formatter sweep: `rg -n "DateFormatter\\(|dateFormat\\s*=" Cadence`
- Page-header usage: `rg -n "DesktopPageHeader\\(|iOSPageHeader\\(" Cadence`
- MCP boundary hits: `rg -n "CadenceMCP|CadenceReadService|CadenceWriteService|calendarEventID"`
- Whether an unmerged local branch still holds work, or whether one is safe to lose:
  `docs/BRANCH_AUDIT.md` — a verdict per branch (SPENT / LIVE / SUPERSEDED) with the evidence, and
  the test that answers it. "Commits ahead of `main`" does not mean unlanded work here: landing
  rebuilds the hunks rather than merging, so a landed branch stays ahead forever.

## Verification Defaults

- Formatting: `git diff --check`
- Build and test: `scripts/xcb.sh <id> build|test`, never a bare `xcodebuild`. It supplies the
  private `-derivedDataPath` and takes the test-host lock. Rules: `docs/AGENT_BRIEF.md`.
- Unit tests: scope to `CadenceTests/<SuiteName>` — a SUITE, not a filename.
- MCP changes: build the `CadenceMCPServer` scheme separately and grep the log for warnings.
- CI red where local was green, or anything about to be pushed to `main`: `docs/CI_PARITY.md` —
  the measured differences (Xcode 26.0.1/UTC/3 cores there, 27.1 here), the pre-push checks that
  cover the jobs no local run makes, and what cannot be checked on this Mac at all.

## The Ledger, Without Reading It

`docs/TODO.md` is authoritative and enormous — a single entry reaches tens of kilobytes. Do not
`rg` it for a ticket id; that prints whole entries. Ask `scripts/ledger-view.sh` instead (T-1331),
which derives everything it prints from the two ledgers at the moment you ask:

- `./scripts/ledger-view.sh head T-1325` — **start here.** The entry's first line and state, with
  the addenda counted rather than printed. On the largest ticket that is ~5k tokens, not ~20k.
- `./scripts/ledger-view.sh show T-1325` — the whole entry block for one id, from both ledgers,
  once you are working on it and need the history.
- `./scripts/ledger-view.sh brief` — every active entry, one line each; with no subcommand at all,
  the same list wrapped onto two lines per entry.
- `./scripts/ledger-view.sh counts` — the census, beside the naive lexical count it corrects.
- `./scripts/ledger-view.sh untriaged` — active entries carrying no RC-TRIAGE verdict ([[T-7296]]).

Its closure reading is the narrow one `agent-commit.sh` already uses (a bold run opening the
entry's own first line), so an entry that merely quotes the token stays open — the [[T-1335]] trap.
