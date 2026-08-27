# Writing an audit report Cadence can act on

Four external audits landed on 2026-08-26 and every finding in them was real. This is what made
them expensive to act on anyway, and what would make the next one cheaper. Written from the
receiving end, after verifying all four.

The audits are already good: file:line references, a "why it matters" per finding, a suggested fix,
suggested tests, a "looks solid" section, and a patch order. Keep all of that. Everything below is
addition, not replacement.

## 1. Answer "can this happen today?" — and show the check

The single most expensive gap. A bundle-delete finding correctly identified that a shared helper
does not clear `calendarEventID` while its sibling does. Its stated impact — "iOS can leave
unbundled tasks pointing at an old calendar event" — cannot occur: **nothing in the app writes that
field a non-empty value**, so a stale value can only come from an older build. One grep
(`grep -rn 'calendarEventID = ' Cadence --include='*.swift' | grep -v '= ""'`) settles it.

The inconsistency is still worth fixing. But a finding filed with an impact claim that cannot occur
sends someone hunting a live bug that is not live.

So for each finding, state one of:

- **Reachable today** — and the path a user or agent takes to reach it.
- **Reachable only from existing data** — the code that used to produce it is gone.
- **Not currently reachable** — a latent inconsistency worth fixing for consistency, not urgency.

## 2. Separate "the code is wrong" from "the code is right and nothing pins it"

These need different work and different urgency, and several findings blur them. "Copied subtasks
never set `parentTask`, and the test reads the parent's array so it cannot see the difference" is
really *two* findings: a possible defect, and a test that cannot detect it. Say which you mean.

The strongest recent example of the second kind: a fix's own wiring was correct, and deleting the
two lines that armed it left the whole feature inert **with the suite green**. No production code
needed to change — only the tests could not see it.

## 3. Give the 30-second confirming command

The best finding in these four audits was the date one, because its claim could be *run*:

```swift
let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
f.date(from: "2026-8-20")            // parses
"2026-8-20" < "2026-08-25"           // false — the whole bug, in one line
```

That took two minutes to confirm and went straight into the ticket as evidence. A finding I can
*execute* is worth several I have to reason about.

For each finding, include the grep, the snippet, or the test that distinguishes "real" from
"looks real". If there isn't one, say the finding is analytical.

## 4. Mark each claim measured or inferred

`P1/P2/P3` is severity, not confidence, and they are independent: a P3 you ran beats a P1 you
reasoned about. Tag each claim `measured` (you executed it) or `inferred` (you read it). Then I
verify the inferred ones and trust the measured ones, instead of re-checking everything.

## 5. Check `docs/TODO.md` before writing the finding up

Two findings in the fourth audit were already filed from the second and third. A grep for the
symbol name in `docs/TODO.md` costs nothing. If a ticket exists, say "extends T-NNN" and give only
the new part — that is genuinely useful, and much cheaper than a rediscovery I have to detect.

## 6. Reach for the sharpest available framing

The bundle finding was framed as macOS clearing a field that the shared helper does not. The real
shape is tighter: **two functions in the same file, twelve lines apart**, unbundling members in
near-identical loops, and only one clears it. An inconsistency visible in a single screen is much
easier to settle than a cross-platform one.

Before writing a finding as "platform A vs platform B" or "layer X vs layer Y", check whether both
halves are closer together than that.

## 7. Point at the existing correct pattern

The date audit named `AIActionService`, which already normalizes and already documents the exact
failure mode. That reframed the work from "write new code" to "spread a practice this codebase
already has" — which is a better ticket, an easier review, and an argument that the fix is right.

## 8. Keep the "looks solid" section, and make it specific

It is more valuable than it looks. "Task deletion fetches subtasks first, detaches relationships,
repairs recurrence links, and deletes empty bundles through one shared path" tells the next agent
where the good pattern lives. Vague reassurance ("looks fine") does not.

## 9. Say which tree you read

Audits run against the working tree, not `main`. One 2026-08-27 audit reported a ticket as already
fixed; it was reading three agents' uncommitted work, so it was correct about what it read and wrong
about the branch. Closing that ticket on its evidence would have credited work that had not landed.

The reverse is worse and has not happened yet: an audit reading a dirty tree will also *miss*
defects that in-flight work introduced but has not committed, and report the file as clean.

So state the commit (`git rev-parse --short HEAD`) and whether the tree was dirty
(`git status --porcelain | wc -l`). Two lines, and they tell the reader whether a "looks solid"
means the branch is solid or only somebody's scratch state was.

## What not to change

- Read-only, no build, no tests. That division is why this is cheap: discovery is read-a-lot,
  produce-a-little work, and it is the expensive half to do in-context.
- The patch order. It has been right every time.
- File:line references. Non-negotiable — they are what makes verification take minutes.
