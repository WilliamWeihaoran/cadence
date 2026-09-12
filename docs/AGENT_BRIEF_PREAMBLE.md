# Standing rules for a Cadence subagent

Your brief points here instead of repeating this. Read it once. It is deliberately short.

## Read narrowly — this is the expensive one

**Cache is billed on your whole context, every tool round.** A file you open at round 5 is re-read on
every round after it. `docs/TODO.md` is ~90k tokens; opened once by an agent that runs 300 rounds, it
costs ~26M cached tokens. That single habit outweighs everything else on this page.

So: **extract, do not open.** `sed -n '120,150p'`, `rg -n` with a tight pattern, or a `python3` slice.
Open a whole file only when you are editing it. Never read `docs/TODO.md` or `docs/TODO_DONE.md` whole
— your brief carries your ticket, and you touch the ledger only to write your own line.

## Loop less

**The scratchpad is shared by every agent in the batch. Namespace your files.** Put everything under
`<scratchpad>/<your-agent-id>/` and prefix log and plan names with your id. An agent using generic
names — `plan.txt`, `mut.log`, `tree` — has already collided with a sibling mid-mutation-run and had
to terminate a runner to recover. Same for build ids: `xcb.sh <your-id>`, never a shared word. **This
paragraph did not stop it**: on 2026-09-11 a sibling's `git archive` landed on top of one agent's
tree at `.../scratchpad/tree`, and that agent's whole first build-and-test round then measured HEAD
instead of its own edits — a wrong answer, not a crash. So the name is no longer yours to pick:
`./scripts/agent-scratch.sh new <your-agent-id>` mints the tree, does the `git archive HEAD | tar -x`,
and refuses the generic words outright.

**Build in a `git archive HEAD` tree, not the working tree, whenever siblings are in flight.** The
shared checkout routinely will not compile because another agent is mid-edit in a file you do not
own. Two agents this batch hit 48 and 2 compile errors that were not theirs. Copy your own files over
an archive of HEAD and build that.

**Block inside one Bash call; never end your turn waiting.** Ending a turn does not pause you — it
**stops** you, until a human notices and sends a message. There is no notification that resumes you.
Seven agents have now stalled this way, several while explaining that they were being considerate of
a sibling's in-flight work. Waiting politely and dying are the same thing here.

    for i in $(seq 1 30); do pgrep -f '<runner>' >/dev/null || break; /bin/sleep 20; done; cat <log>

with the Bash `timeout` raised (up to 600000 ms). Batch your runs — failing-first, green and mutations
in one script — rather than one call per step.

## Verifying

- **Failing-first before the fix**, red for the right reason. For a deletion, prove absence with a scan
  that would fire if a caller existed, not an empty `rg`.
- **Mutations: `scripts/mutate.sh`. Never hand-roll a runner** — five distinct ways a hand-rolled one
  lied are why it exists. A surviving mutation is a finding, not an embarrassment.
- **Never assert a numeric floor over a population the repo is shrinking.** Exact counts, each
  occurrence named. Mutate weakened assertions in pairs.
- **Pin call sites, not values.** A test that a constant exists stays green when a new site retypes it.

## Building

- `./scripts/xcb.sh <id> test -scheme Cadence -destination 'platform=macOS' -only-testing:CadenceTests/<Suite>`
  — never a bare `xcodebuild`. `-only-testing:` takes a **suite** name; a name matching nothing runs zero
  tests and reports success.
- The lock is at `${TMPDIR}cadence-macos-test-host.lock`, **not in the repo**. `xcb.sh test` takes it
  itself — do not wrap it in an outer `acquire`. It is a FIFO, so waiting longest is served.
- Warning baseline is **zero**, from a run that recompiled your files.
- Touching `Cadence/iOS/` needs `-destination 'generic/platform=iOS Simulator'`. Touching
  `Cadence/Shared/` or `Models/` needs `CadenceWidgets` and `CadenceMCPServer` too — the app scheme
  cannot see when the MCP target breaks.
- **Scan a `git archive HEAD` tree, not the working tree.** Siblings are editing; a scan over
  half-written Swift crashed a test host. A trap in a scan helper kills the host and emits no `error:`.

## Committing

`./scripts/agent-commit.sh <id> -m <msg> <path>[=<content-file>]...` — never a bare `git commit`. It
commits through a private index, leaves the shared one clean, and refuses a foreign staged path, a lost
declined hunk, and a ledger edit that drops ticket ids.

**Build every path on HEAD, not on the worktree copy you happened to open.** Siblings land while you
work, so read `git show HEAD:<path>` into a file, apply your change to *that*, and pass it as
`<path>=<content-file>`. Your ledger line belongs in the **same commit as the code it closes**, built
the same way. `--removes <n>` is not a formality: read every line the refusal lists, satisfy yourself
that each one is yours to remove, and only then say the number. **Never `--commits-stale`** — it is the
one override here that discards a sibling's landed work.

**DELETE NOTHING UNTIL `git log` SHOWS YOUR COMMIT AT HEAD.** Not "unless it was refused" — the
condition is not about the commit path at all, it is *is this work in HEAD yet*. This paragraph used
to open *"a refused commit means your files are the only copy"*, and on 2026-09-11, with that wording
in place, an agent finished T-752, T-919 and T-1085, deleted its tree **before its commit landed**,
and every line was lost; a second agent rebuilt all three from nothing. The refusal-shaped rule did
not cover the refusal-free way to do it. Three batches now, counting the two T-1094 was filed over.

So do not answer it from memory:

    ./scripts/agent-scratch.sh release <your tree>

refuses while anything in there is in neither the sha it was minted from nor HEAD, and names the
files. `check` asks without deleting. A refusal — `REMOVES-HEAD-LINES`, `HEAD-MOVED`,
`WORKTREE-BEHIND-HEAD`, a user-gated flag — says *this commit was not taken*, not *this work was no
good*. **Cleanup applies to what you committed and to nothing else.** If anything you produced is not
in `git log`, leave those files where they are, do not clean their directory, and end your report with
their **absolute paths** and the exact refusal text — so the next agent commits your work instead of
rebuilding it.

## Safety

Do not launch the app or touch `/Applications/Cadence.app`. Do not create simulators unless your brief
says so; if it does, claim through `scripts/simulator-claim.sh` and clean up in the same turn. Never
kill a process you did not start. Do not touch EventKit or raise a TCC prompt.

## Reporting

Bullets. Say which claims are **measured** and which are **reasoned**. Residue you do not fix goes into
`docs/TODO.md` as a ticket in your reserved id range, not just into your report. If your ticket turns
out to need a judgement call rather than applying a decision, **stop and say so** rather than guessing —
that has been the right move every time it has happened.
