# Paused work — 2026-08-28 — **RETIRED, the pause ended**

**Nothing here is waiting. Do not resume anything from this file.** It was the snapshot taken when
the owner paused a ten-agent run on 2026-08-28, so that the trees on disk could be picked up again.
They were: every batch it lists landed in the 2026-08-28/29 five-batch run, archived in
`docs/TODO_DONE.md` under *"Closed 2026-08-28/29 — the five-batch run"*.

Checked 2026-10-20 before retiring it:

- **All ten `/private/tmp/cadence-*` trees are gone.** There is nothing left to stage.
- **Every ticket the ten trees held is closed** — T-321, T-333, T-338, T-341, T-342, T-343, T-344,
  T-349, T-351, T-354, T-355, T-357, T-363, T-366, T-369, T-373, T-377, T-378, T-385, T-386, T-387,
  T-389, T-390, T-392, T-393, T-394 — as are T-399 and T-400, the two ids it allocated and wrote
  down. Read any of them with `./scripts/ledger-view.sh show T-NNNN`.
- **`main` is nowhere near `859e270`** and the "next free id" below `401` is off by thousands.

Nothing links to this file; it is kept as the record of a pause that ended, not as a queue.

## The two things worth carrying out of it

Both are about how a many-agent run goes wrong. Only one of them is written anywhere an agent
actually reads, so they are kept here rather than dropped:

- **Two agents allocated the same ticket id.** This one *is* in `docs/AGENT_BRIEF.md`,
  "Committing", with the sweep that catches it — across every local *and* remote ref, not just the filesystem. It is
  restated here only so this file is not a dead end.
- **An agent tree is a snapshot and HEAD moves.** Copying a tree wholesale reverts landed work; it
  happened four times in one day. Take each agent's own files, or ask for a patch. The handoff
  carries the neighbouring warning — that a sibling's report about a dirty file is a snapshot, not
  a current fact — but **not this one**, which is why it is spelled out here.

## The one thing in it that never landed

The note it deferred was never written. It belongs in `Cadence/Shared/AGENTS.md`, beside the
existing non-vacuity guidance, and it is this: **a non-vacuity anchor has to be a file where the
needle can actually appear.** A type calls its own members *unqualified*, so anchoring a qualified
needle inside the declaring type reads zero for a reason that is not absence — the scan is vacuous
and green, which is the exact failure the anchor exists to prevent.

That file is another session's to edit, so this is recorded here rather than fixed, and a ticket
carries it.
