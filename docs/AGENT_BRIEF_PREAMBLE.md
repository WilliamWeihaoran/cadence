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

**Block inside one Bash call; never end your turn waiting.** Four agents have lost round-trips to this.

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

## Safety

Do not launch the app or touch `/Applications/Cadence.app`. Do not create simulators unless your brief
says so; if it does, claim through `scripts/simulator-claim.sh` and clean up in the same turn. Never
kill a process you did not start. Do not touch EventKit or raise a TCC prompt.

## Reporting

Bullets. Say which claims are **measured** and which are **reasoned**. Residue you do not fix goes into
`docs/TODO.md` as a ticket in your reserved id range, not just into your report. If your ticket turns
out to need a judgement call rather than applying a decision, **stop and say so** rather than guessing —
that has been the right move every time it has happened.
