# Codex Ledger Inbox

**Append-only. Newest last. Never edit an existing entry, and never edit `docs/TODO.md`.**

Codex writes its ticket entries here; the coordinator folds them into `docs/TODO.md` when landing
the branch, in the same commit as the code. Appending merges cleanly; editing a 12,000-line ledger
in place is the conflict this file exists to avoid ([[T-1385]]).

Write an entry in the ledger's own shape — the id, a bold one-line headline, then the measurement.
A closure is written **as** a closure (`**CLOSED <date> (codex) — …`), never described as one, because
every reading in this repository anchors on that run and a quoted token is not one ([[T-1335]]).

**Reserved id range for Codex: T-1440 .. T-1469.** Do not use an id outside it. The coordinator
widens the range here when it runs low.

The protocol, the lease and the refusals are in `docs/CODEX_WORKTREE.md`; the coordinator checks a
branch with `./scripts/codex-land.sh review codex/<topic>`.

---
