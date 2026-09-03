# Codex requests — open asks from the coordinator

**What this file is.** A queue of *read-only* work the coordinating agent wants done but should not
spend its own tokens on: reconnaissance, premise re-verification, sizing, and diagnosis. Codex reads
this, does the work, and writes its answer **back into this file** under the request it answered.

**Why it exists.** Measured 2026-09-03: the coordinator's own context is ~61% of session spend, and
the single most repeated expense is *reading source to find out whether a ticket is still true*.
Agents have corrected a ticket's premise roughly ten times in this run. Every one of those corrections
was a read that could have happened here instead, once, before a brief was written.

## Rules

- **Read-only.** Do not change product code, tests, or `docs/TODO.md`. If a request implies a fix,
  answer the question and say what the fix would be; do not make it.
- **Measured beats reasoned, and say which.** Every claim gets a `MEASURED` or `REASONED` tag and, if
  measured, the command or the file:line that measured it. A count with no command behind it is worth
  nothing here.
- **A disproved premise is the most valuable answer you can give.** If a request rests on something
  false, say so first and stop — do not answer the question it should have asked.
- **Do not trust the ticket text.** Most of these entries quote a ticket. The point of the request is
  usually that the quote may be stale.
- Answer under the request, prefixed `ANSWER <date>:`. Leave the request text intact.

---

## R1 — Diagnose T-739: literal arithmetic disagrees with variable arithmetic in `CadenceTests`

**Priority: highest.** This one is small, weird, and undermines an assertion style used across the
suite.

`#expect(x == 0.5 * 1.6)` **fails** while `#expect(x == retired * 1.6)` **passes**, for the same
numbers, in `CadenceTests`. A standalone `swiftc -Onone` binary prints **one identical bit pattern**
for every spelling. Found while landing T-496; deliberately not guessed at.

Answer: what is actually different — constant folding at a wider precision, `CGFloat`/`Double`
bridging, the `#expect` macro's expansion changing the inferred type, or something else? Then: **how
many assertions in `CadenceTests` compare against an inline `literal * literal`?** That set is the
blast radius, and nobody has counted it.

## R2 — Re-verify the premises of the tickets scheduled for batches M, N and O

Ten tickets have had a premise corrected by the agent working them, mid-task, at full Opus cost. These
are the next ones up. For each, say whether the quoted claim still holds at current HEAD, with the
command that shows it.

- **T-689** — "the Goals screen says *No goals yet* when every goal is completed". Still true after
  `c1b0c9b`?
- **T-690** — "a paused or cancelled project reaches **no** Settings lifecycle section on either
  platform". Count the sections; name the file:line for each platform.
- **T-691** — "`missingLinks` passes a raw list name, so an untitled list's row is a blank line".
  Still true after T-624's evidence gate landed (`892b866`)?
- **T-693** — "`CalendarEventPresentationSupport.swift:73` and `:198` display `?? ""` where iOS shows a
  fallback". Verify both line numbers and that the three other `?? ""` sites in that file really are
  search haystacks.
- **T-657** — "the detector cannot see a report handed *sideways* one frame down". How many live sites
  does that spelling actually have? T-648's three macOS copies were the only known ones and they are
  now fixed, so this may have **no population left** — which changes whether it is worth building.
- **T-664** — "the vocabulary has no spelling for *the surface filled itself in*; measured, exactly one
  live site". Is it still one?
- **T-672 / T-673 / T-674** — the icon-only-button ledger says 31 sites in 24 files, split 10/8/10 plus
  3 iOS. That was measured before batches H through L. Re-count all three.

## R3 — Size T-616's siblings before anyone sweeps them

T-754 says **41 more sites** spell `Theme.radiusControl` (10) as a bare `cornerRadius: 10`. Verify the
count, and answer the question the T-616 decision turned on: are those 41 **one origin copied**, or
independent choices? The tell is scatter — 55 sites at exactly 7 with no 6s or 8s nearby was the
evidence that made a token descriptive rather than a new design decision. Does the same hold at 10?

## R4 — Triage the ~20 unscheduled tickets

These are open and deliberately not in any batch, most because they need the user or look blocked:
T-16, T-17, T-18, T-55, T-115, T-122, T-168, T-274, T-447, T-481, T-491, T-511, T-531, T-551, T-554,
T-562, T-584, T-624, T-626, T-661.

For each: is it **still live**, **already overtaken by work that landed**, or **genuinely blocked and
on what**? Several were narrowed weeks ago and the code has moved a lot since. An entry that is
already dead is worth more to find than a new finding.

## R5 — Audit the last three batches against their own commit messages

The standing highest-value Codex task from `docs/CODEX_BRIEF.md` §1, pointed at what just landed:
batches **J, K and L** (`db1e9c6` through `67abf37`). Do the commits do what their messages claim?
Two specific things to check, because both are load-bearing and neither has an outside reader:

- **`db1e9c6` (T-621)** claims the focus-ledger reconcile is "a pure function of the counter and the
  rows" and therefore idempotent with no run-once flag. Is it? And does
  `max(counter, min(previousMinutes) + Σminutes)` really only ever raise?
- **`fba681a` (T-713)** claims intermediate names never touch a card, and that T-358's frozen snapshot
  still holds. Both are assertions about a rename's commit point; verify them against the code rather
  than the tests.

## R6 — Standing: what should be here that is not?

If you notice a class of question this coordinator keeps paying to answer with its own reads, add a
request for it. The three that have recurred so far are *"is this ticket's count still right"*,
*"how big is this change really"*, and *"is this instrument measuring what it claims"*.
