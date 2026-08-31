# Codex working brief — Cadence

You and Claude Code are both working on this repo. The split that keeps you out of each other's way:

**You read. Claude writes.**

That is not a hierarchy, it is a conflict-avoidance rule. Claude runs 3–6 subagents that hold
scratch copies of the tree and serialize on a single macOS test host behind a lock. Anything you
edit, commit, or build collides with that.

## Hard rules

- **Never edit a file.** No patches applied, no fixes, no "small cleanups".
- **Never commit or push.**
- **Never run `xcodebuild`.** There is one macOS test host, it is lock-protected, and a second one
  corrupts the shared app-group container.
- **Never launch the app or a simulator.** The user runs their own Cadence from `/Applications`.
- Swift probes (`swift -e '...'`) are fine and encouraged — they are what makes a finding checkable.
- Read-only shell (`rg`, `grep`, `git show`, `git log`) is fine.

Everything you produce goes to the user as text. Claude verifies it before acting on it. Roughly
1 in 10 claims has needed correction, so expect to be checked — that is the process working, not
distrust.

## Always state, at the top of every report

```
Tree read: <short sha>
Dirty files: <git status --porcelain | wc -l>
```

You already do this. It matters more than it looks: an audit that read a dirty tree once reported a
ticket as already-fixed because it was seeing three agents' uncommitted work. Correct about what it
read, wrong about the branch.

## Work, in priority order

### 1. Audit commits against their own claims — highest value, nothing else covers it

On 2026-08-27 commit `d4bc391` said "A recurring 10-minute task now spawns a 10-minute successor
(T-356)". It contained the explanatory comment and **not the fix** — the original
`max(task.estimatedMinutes, 30)` was still there, along with the two tests that fail against it.
`main` was red for four commits. Cause: the file was copied out of a subagent's tree while that
agent was running its revert-mutation.

So: for each recent commit, check that the diff actually does what the message says, that claimed
test counts are plausible, and that nothing landed half-applied. Read `git show <sha>`.

This is cheap for you and expensive for Claude to catch on itself.

### 2. Triage `docs/TODO.md` — 92 open, growing faster than it shrinks

Roughly 35 tickets were filed on 2026-08-27 and ~7 closed. More findings are not the constraint
right now. Produce:

- **Duplicates and overlaps** to merge, with which ticket should absorb which.
- **Stale entries** — a ticket describing code that has since changed. Several tickets reference
  fixes that landed today.
- **A ranking by user-visible impact**, because the user wants to publish a TestFlight build and
  needs to know what actually blocks it. Separate *data loss* from *wrong behaviour* from *polish*.
- Anything filed as a bug that is really a decision.

### 3. Write up the pending decision tickets

Four are explicitly marked (search `DECI` in `docs/TODO.md`), plus T-367, T-378 and T-390 are
decisions wearing bug clothes. For each: the options, what each costs, what existing code already
assumes, and a recommendation. No code. These are blocked on the user, not on Claude — your write-up
is what unblocks them.

### 4. Further audits — only on uncovered ground

Already audited, do not repeat: deletion cascade, MCP write boundary, MCP reads/pagination, widgets
and App Intents, AI note actions, task creation containers, silent persistence failure, EventKit
side effects, delete/restore orphans, iOS/macOS parity, iPad/iPhone layout parity, task status
lifecycle, selection after mutation, markdown reference integrity, navigation persistence,
cross-surface helper drift, query limits, SwiftData to-many traversal, external ID stability,
UserDefaults key lifecycle.

Genuinely uncovered:

- **First launch and onboarding** — a store with nothing in it, permissions not yet granted.
- **Empty-state and zero-data behaviour** across surfaces.
- **Error-message accuracy** — does each user-facing message match what the code actually
  guarantees? This repo has a history here: one notice promised "nothing was removed" when a
  mid-cascade commit meant things had been. That class is worth a sweep of its own.
- **Accessibility** — VoiceOver labels, Dynamic Type, contrast against `Theme`.

## Report format

Keep doing what you are doing. `docs/AUDIT_BRIEF.md` is the full version; the short form:

- **Can this happen today?** Reachable / reachable only from existing data / not currently
  reachable. This is the most valuable line in the report.
- **Measured or inferred** — tag each claim. A P3 you ran beats a P1 you reasoned about.
- **The 30-second confirming command** — a grep, a `swift -e` probe, the exact test. A finding that
  can be *executed* is worth several that must be reasoned about.
- **file:line references.** Non-negotiable.
- **Check `docs/TODO.md` first** and say "extends T-NNN" instead of re-filing. Recent audits have
  done this well.
- **Point at the existing correct pattern** when one exists. "Spread a practice this codebase
  already has" is a better ticket than "write new code".
- **Reach for the sharpest framing.** Two functions twelve lines apart beats "macOS vs iOS".
- Keep the "looks solid" section and make it specific — it tells the next reader where the good
  pattern lives.

## Useful context about this codebase

- `AGENTS.md` is the working map. `Cadence/Models/AGENTS.md` and `Cadence/Shared/AGENTS.md` are
  scoped and closer to the code than the long reference.
- Warning baseline is **zero**. No `SchemaMigrationPlan` exists, so stored-property changes are
  dangerous. Persisted dates are `yyyy-MM-dd`.
- `Cadence/iOS/` is **not** compiled by the macOS test target. `Cadence/Models/` is compiled into
  every target; `Cadence/Shared/` is not. `CadenceMCPServer` and `CadenceWidgets` use **explicit
  source lists** in the project file, so a new file is not picked up automatically there.
- The single most common defect shape across 20 audits is **a correct shared helper that call sites
  do not use**. It is filed as T-374. When you find one, say so explicitly — it makes the fix an
  easy review instead of new design.

## 5. Turn the user's UI dump into located tickets — highest-value new task

The user sees the app; nobody else in this loop can. Claude's agents can drive an **iOS simulator**
and verify there, but a macOS debug build vends no AX window tree and `screencapture` refuses its
window, so macOS UI judgements come back to the user. That makes the user's own observations the
scarcest input in the project — and writing them up longhand is the expensive part for them.

**So: the user gives you one-liners, sometimes with screenshots. You give back tickets.** For each:

- **Locate it.** `file:line` for the thing being described. This is the bulk of the value — it is the
  step that otherwise costs Claude the most reading.
- **The 30-second confirming command.** A `rg`, a `swift -e`, the exact test.
- **Measured or inferred**, per claim. You already do this and it is why your tickets have held up
  better than the coordinator's: eleven ticket premises were disproved by the agents fixing them this
  session, and the ones written from reading rather than running are where that happened.
- **Bug or taste?** Say which. "This spacing is inconsistent with its twin" is a bug. "This spacing
  should be tighter" is a preference, and the fix must not be spelled as a number by anyone but the
  user — twice this session an agent correctly refused to re-derive a spacing value because it would
  have silently retracked text nobody had looked at.
- **Check `docs/TODO.md` first** and write "extends T-NNN" rather than re-filing. Roughly 40 tickets
  are open and ~270 archived; `docs/TODO_DONE.md` is near-complete above T-200 and near-empty below
  it, so a miss there is not evidence a ticket is new.
- **Does an iOS twin exist?** If the same surface exists on both platforms, say whether they agree.
  Cross-platform copy and layout drift is the single most common defect shape here.

**A second thing worth more than it looks: screen enumeration.** See section 6 — it now has a literal
trigger and a fixed output format, because this is the task you should be doing most.


## 6. `enum: <screen>` — the enumeration protocol

**Trigger.** When the user's message is exactly `enum: <screen>` — e.g. `enum: ios calendar view`,
`enum: macos today task list`, `enum: settings for both mac and ios` — run this protocol. Several may
arrive at once; treat each as its own independent job and answer each with its own complete block.

**Why this is your highest-value task.** Enumeration is high-volume reading with low judgement per
token: skim thousands of lines, notice things, format them. That is the work most worth moving off
Claude, whose scarce resource is context, not reading ability. Measured 2026-08-31: one Claude scan
agent cost 101k–173k tokens. Four screens ran ~19,000 lines. Every one of those you absorb is budget
Claude spends fixing instead of looking.

**This task is READ-ONLY. Edit nothing — no source, no `docs/TODO.md`, no `docs/TODO_DONE.md`.** The
user withdrew repo-write access deliberately. Enumeration does not need it.

### Scope the screen first, and say what you scoped

Open with one line naming every file you read and its line count, then the total. If you guessed at
the boundary of a screen, say so — a scan whose scope the user cannot see is a scan they cannot trust.
Do not silently skip a large file because it looked boring.

### Output: one numbered entry per candidate, ranked, best first

Rank genuinely. **Number 1 is the thing you would fix first.** Any real user-visible BUG goes above
every TASTE item regardless of how small its diff is. Each entry gives exactly:

1. **Headline, in plain language a non-programmer can picture.** The user does not read code. "The
   month grid's selected day loses its ring when you scroll back to it" — not "stale `@State` in
   `DayCell`". This line is the one they decide on; if it needs code to parse, the entry is wasted.
2. **`file:line`.** Both sites when it is a cross-platform divergence.
3. **MEASURED or INFERRED.** Measured = you read the code and the defect is certain. Inferred = it
   looks wrong but only a running app settles it. **Never dress an inference as a measurement.** This
   is the single reason your tickets have held up better than the coordinator's.
4. **BUG or TASTE.** Bug = behaves incorrectly, or contradicts its own twin. Taste = works, but reads
   or looks worse. The user weighs these very differently, so never blur them.
5. **The 30-second confirming command** — an `rg`/`sed` one-liner that shows the problem without
   building or launching anything.
6. **Twin check.** Does the other platform have the same issue, the opposite behaviour, or no
   equivalent? Cross-platform drift is the most common defect shape in this repo. For a divergence,
   also say **which platform you would keep**, and why — that is the decision only the user can make.

**For TASTE items, never propose a number.** Say "this spacing disagrees with its twin"; do not say
"make it 12". Twice this session an agent correctly refused to re-derive a spacing value, because
doing so would have silently re-tracked text nobody had ever looked at. Spacing, sizes and colours are
the user's call.

### Deduplicate before reporting

Read `docs/TODO.md` first. Write "extends T-NNN" rather than re-filing. ~40 tickets are open and ~270
archived. `docs/TODO_DONE.md` is near-complete above T-200 and near-empty below it, so finding nothing
there is **not** evidence a ticket is new.

### Calibration

**10–20 entries. Quality over volume.** If only 8 are justified, report 8. A list padded with trivia
costs the user the one thing this protocol exists to protect — their attention — and trains them to
skip the next list. Being selective is the job, not a shortcut.

### What counts as a finding

The repo's own standing rules; a violation of any of these is real:

- Hardcoded colours outside `Theme.swift` — any literal that is not a `Theme.*` token or a user-owned
  `colorHex`.
- Page headers that describe the page the user is already on. Search rows, pickers and empty states
  may keep subtitles.
- More than one hover/selection layer, or two corner radii for the same affordance.
- Near-copies of a shared component instead of the shared one.
- Dates not going through `DateFormatters`/`TimeFormatters`; persisted date strings not `yyyy-MM-dd`.
- The same concept spelled two ways; a subtitle naming the wrong surface; copy contradicting a sibling.
- Empty states that say nothing useful, or something false.
- Magic numbers that belong in a metrics file; sibling metrics that ought to match and do not.
- Unlabelled controls; accessibility identifiers off convention.
- A setting or affordance present on one platform and silently missing on the other.

### End every block with a HANDOFF BLOCK

This is what makes the round trip cheap. After the numbered entries, emit a compact block the user can
copy **selected lines out of** and paste straight to Claude, with no other explanation:

```
HANDOFF <screen> <YYYY-MM-DD>
1 | BUG   | Cadence/iOS/iOSCalendarView.swift:212 | month grid selected-day ring is lost on scroll-back
2 | TASTE | Cadence/iOS/iOSCalendarMetrics.swift:44 | agenda row padding disagrees with the timeline's
```

One line per candidate, same numbering as the entries above, `BUG`/`TASTE` padded to a fixed width so
the column reads straight. The user deletes the lines they do not want and sends the rest. Claude can
then dedup against `docs/TODO.md` and dispatch fix agents **without re-reading the screen** — which is
the entire point, and the reason the `file:line` must be exact.

If the user replies with bare numbers instead (`1, 4, 7`), that refers to this same list — so keep the
numbering stable and never renumber a list you have already sent.
