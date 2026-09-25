# Cadence Context Index

Use this as a routing map before opening long guides. Prefer `rg` and nearby scoped guides over
loading broad histories.

## By Change Type

- SwiftData model, relationship, schema, migration, export, reset:
  `AGENTS.md`, `Cadence/Models/AGENTS.md`, `Cadence/Services/AGENTS.md`, then
  `CadenceMCPServer/AGENTS.md` if shared model/service code crosses the MCP boundary.
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
- Product/feature history:
  Search `docs/CLAUDE_REFERENCE.md` by section name.

## Common Searches

- Type declaration: `rg -n "struct TypeName|enum TypeName|class TypeName|extension TypeName"`
- SwiftData relationship rule: `rg -n "relationship|\\[.*\\]\\?" Cadence/Models Cadence/Services`
- Hardcoded colour sweep: `rg -n "Color\\(|\\.white|\\.black|\\.gray" Cadence CadenceWidgets`
- Date formatter sweep: `rg -n "DateFormatter\\(|dateFormat\\s*=" Cadence`
- Page-header usage: `rg -n "DesktopPageHeader\\(|iOSPageHeader\\(" Cadence`
- MCP boundary hits: `rg -n "CadenceMCP|CadenceReadService|CadenceWriteService|calendarEventID"`

## Verification Defaults

- Formatting: `git diff --check`
- macOS build: use the private `-derivedDataPath` command in `AGENTS.md`.
- Unit tests: scope to `CadenceTests`; for macOS tests, use `scripts/test-host-lock.sh`.
- MCP changes: build the `CadenceMCPServer` scheme separately and grep the log for warnings.

## The Ledger, Without Reading 1.4 MB

`docs/TODO.md` is authoritative and enormous. Do not `rg` it for a ticket id — that prints whole
multi-kilobyte entries. Ask `scripts/ledger-view.sh` instead (T-1331), which derives everything it
prints from the two ledgers at the moment you ask:

- `./scripts/ledger-view.sh` — every active entry with its status, source location, one-line next
  action and, for a parked item, why it is parked (~90 lines).
- `./scripts/ledger-view.sh show T-1325` — the exact entry block for one id, from both ledgers.
- `./scripts/ledger-view.sh counts` — the census, beside the naive lexical count it corrects.

Its closure reading is the narrow one `agent-commit.sh` already uses (a bold run opening the
entry's own first line), so an entry that merely quotes the token stays open — the [[T-1335]] trap.
