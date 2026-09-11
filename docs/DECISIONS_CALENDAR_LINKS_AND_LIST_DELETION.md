# Four parked tickets: calendar links and list deletion

Companion to `docs/DECISIONS_PENDING.md`. Written 2026-09-06 against `main` at `4c091c1`, with
every number in it re-measured that day rather than inherited from the ledger.

`docs/TODO.md` entries **T-623**, **T-624**, **T-899** and **T-1043** have each been verified twice
and moved neither time. They are not stuck on work. They are stuck on four questions only you can
answer, and every previous write-up was addressed to an engineer. This one is not.

Each section says the same four things: **what you would notice**, **what fixing it costs**,
**what leaving it costs**, and **what I would do**. Where a claim was measured today it says so;
where it is inference it says that too.

---

## Status update, 2026-09-10 — three of the four are now closed

This memo was written on 2026-09-06 and every measurement in it still holds. Three of its four
questions have since been answered, and only one is still yours.

- **T-899 + T-1043 — done.** You were asked whether to merge them and schedule one session. They were
  merged and the session ran: one new test file,
  `CadenceTests/CadenceCalendarLinkProvenanceSweepTests.swift`. No model change, no database change,
  nothing a user sees — exactly the cost quoted below. The correction this memo warned about (the
  rule would have failed on four correct call sites) was needed; a second correction was found while
  writing it, in the opposite direction — the *unlink* allowance the rule proposed turned out to have
  no site behind it at all, so it was left out rather than shipped unexercised.
- **T-1084 — done, and it is the one line of copy this memo recommends for T-624 as well.** The
  archive-import preview now says, only when the file actually carries calendar links, that a
  calendar connection belongs to the device that made it. One conditional sentence, no new stored
  field, on both platforms.
- **T-624 — closed as a decision, and the question below is now T-1117.** Every part of it an
  engineer could act on has landed. **The five-minute experiment in the next section is still
  yours, and it is still the only thing that would change anything.** It was moved to its own ticket
  so it stays addressed to you rather than sitting under an entry that has now been re-verified four
  times without moving.
- **T-623 — unchanged.** Still parked, still recommended parked, and nothing in the work above
  touches it. The one thing still worth a decision from you is **T-752**'s sentence.

## Status update, 2026-09-11 — T-752's sentence is now one line, and the question is T-1118

**T-752 is closed and the sentence is unchanged.** No wording was picked for you. What was done is
the half that was not a decision: that sentence was the only one in the delete-confirmation family
typed inside a view body, on one platform, assembled from a noun at the call site — so it was also
the one nothing in the codebase could find. It now lives beside the others, as
`CadenceListDeletionKind.nothingElseFiledSentence`, with tests naming all three versions of it
verbatim.

**The question itself is now T-623's last open item and is filed as [[T-1118]]**, with the three
wordings and what each costs you. It is a two-line diff whichever you pick, and the recommendation
there is *leave it as it is* unless you have ever seen a stray row turn up in Inbox after deleting a
list. If you have, the scoped version — *"Nothing else **on this device** is filed under this
area"* — is the one that is never false.

One correction to what this memo said on 2026-09-06, found while doing the work. The memo quotes the
sentence and says it "can be false in exactly this scenario". Half of it can. *"Nothing else is filed
under this"* is the claim about your data and is the one at risk; *"no tasks, notes or saved links
will be lost"* is a claim about what the delete removes, and the delete genuinely removes nothing it
cannot see. That does not make it harmless — an orphaned list note is filtered out of every screen
that would show it, and unreachable is what most people mean by lost — but it is why T-1118 asks
about the whole sentence rather than proposing to drop a clause.

Where a section below says a ticket is open, read it as the reasoning that led to the decision above
rather than as the current state.

*One naming note before you search the ledger:* the id `T-1043` was accidentally handed out twice
(recorded in T-1072). The one this memo is about is the calendar-link ticket. The other one — text
sitting on top of an image in a note — was fixed and closed on 2026-09-05 and has nothing to do with
any of this.

---

## The one-page version

| Ticket | What you would notice today | Fix costs | Leaving costs | Recommend |
|---|---|---|---|---|
| **T-623** | Occasionally, after deleting a list, some of its tasks turn up in Inbox | 13 models, 29 new hidden fields, ~260 code changes, and a multi-release rollout | Recoverable stray rows plus wasted space. Nothing is ever lost | **Leave parked.** Nothing about parking it forecloses the fix |
| **T-624** | Either nothing at all, or one quiet sentence on your second device. **Which one is unknown** | Two new fields on two synced models, permanently carried beside the old one | Nothing, or one dead-end feature per device pair | **Run the 5-minute test below first.** Do not decide before you know |
| **T-899** | Nothing. It is a guard against a future mistake | One test file. No model, no database, no user-visible change | Nothing, until someone adds a new calendar screen | **Merge into one ticket with T-1043 and do it.** Not release-blocking |
| **T-1043** | Nothing. Same shape, other direction | Same test file | Same | **Merge into T-899.** And see the correction below — its rule would fail today |

**If you only do one thing:** run the T-624 experiment. It takes five minutes, needs no engineer,
and it either closes T-624 outright or converts it from an unknown into a known, bounded cost.

---

## The constraint behind all four

On **2026-09-05 the app's iCloud database schema was promoted to Production**
(`docs/apple-release-readiness.md`). In plain terms: the shape of the data Apple stores for you is
now frozen in one direction. You can **add** new kinds of record and new optional fields forever.
You can never **remove** a field, and never change what type a field is.

`linkedCalendarID` — the field that holds which Apple calendar a list is connected to — is a text
field in that frozen schema. So every possible fix to T-624 can only ever be *another field
alongside it*. Replacing it with something better-designed is off the table permanently. That is
not a new restriction imposed by parking these tickets; it happened the day the schema shipped, and
it would be equally true if all four were fixed tomorrow.

The same rule cuts the other way for T-623: its fix needs a **new** record type and **new** optional
fields, and both of those stay legal indefinitely. **Parking T-623 does not cost you the option.**

---

## T-624 — a calendar link may not mean anything on your other device

### The experiment, and why it is yours

Everything below turns on one fact nobody has established: **when the same iCloud calendar appears
on your Mac and on your iPhone, does Apple give it the same internal identifier on both, or a
different one?** Apple's documentation says the identifier is local to a device, which makes
"different" likely — but likely is not measured, and the whole ticket is downstream of it.

Two agent passes could not settle this, for a reason that is worth stating plainly: answering it
means asking the calendar system on your own Mac a question, which raises a macOS permission prompt
addressed to you. That is your click, not an agent's.

**But you do not need a console or an engineer. The app already displays the answer.** Measured
today against source, here is the whole procedure:

1. On your **iPhone**, open Settings → Calendar. Find an **iCloud** calendar (not an "On My Mac" or
   "On My iPhone" one — a local calendar genuinely does not exist on the other device, which would
   give you a false answer). Use its link button and connect it to some area or project.
2. Give iCloud a minute, and open Cadence on your **Mac**.
3. On the Mac, open that same area or project's edit sheet and look at the **Apple Calendar** row.

Read the row. There are only five things it can say, and three of them are the answer:

| The row says | What it means |
|---|---|
| **None** | The link has not synced over yet. Wait, reopen, try again |
| **the calendar's name** | **The identifiers match. T-624 is moot — close it.** |
| **"Linked calendar is not on this device"** | **The identifiers differ. T-624's premise holds.** |
| "…(hidden)" | Matches, and you have that calendar switched off in Cadence. Also a match |
| "Linked calendar is missing" | Should be unreachable here; if you see it, that is a new bug worth filing |

The middle row is self-verifying, which is why this version of the test is better than checking
Settings on the Mac: the sentence *"Linked calendar is not on this device"* can only ever appear
when a link **is** stored — so seeing it proves both that the sync arrived and that the identifier
did not resolve.

### What you would notice, if the identifiers do differ

- On the device that **did not** make the link, that list's Apple Calendar row reads *"Linked
  calendar is not on this device"*, and offers no repair.
- On that device, Settings → Calendar shows that calendar as *"Not connected to any area or
  project"*, even though it is connected on the other one.
- Meeting notes filed against that calendar appear under the list on the device that made the link,
  and not on the other one.

**Nothing is lost, nothing is corrupted, and nothing pesters you.** The two genuinely bad behaviours
— each device announcing the other's good link as *broken*, and each "repair" silently destroying
the other device's link — were already removed, in two changes on 2026-09-01 and 2026-09-04. What is
left is a feature that quietly only works on one device.

### What it would cost to fix properly

Making a link actually portable means storing the calendar's *title* and *account* next to its
identifier, so the second device can find the same calendar by description. That is:

- Two new stored fields on two synced models (`Area` and `Project`).
- Both **added beside** `linkedCalendarID`, never replacing it, because of the frozen schema above.
  You carry the old field forever regardless.
- Retiring a test that currently exists specifically to stop anyone doing this
  (`CadenceEventKitPlatformParityTests.aListsCalendarLinkStoresTheIdentifierAndNoCompanionMetadata`,
  measured present today). The repo armed itself against this branch on purpose, in T-390 — matching
  calendars by name without a conflict screen was judged worse than a link you can see is dead.
- A conflict screen for the case where the title matches two calendars, or none.

So: not enormous, but not small, and it is permanent surface area on your synced data.

### What it costs to leave

If the identifiers match, **zero, forever** — the code path that would produce the quiet sentence is
unreachable, and every screen behaves exactly as it did before either fix landed.

If they differ, the cost is one sentence and one one-device feature, per user with two devices. It
does **not** get worse with real users or real data: no data is at risk, and there is no accumulating
damage. It gets *broader* — more shipped device pairs, more people seeing it — but not deeper.

### Recommendation

**Run the experiment before deciding anything.** Then:

- **If they match:** close T-624 as moot. This also downgrades T-899 and T-1043 from "guards a real
  distinction" to "guards an unreachable code path" — still worth having, less urgent.
- **If they differ:** leave the portable-link work parked for now anyway, and instead consider one
  line of copy. The honest version of this feature is *"a calendar link belongs to the device that
  made it"*, and saying that costs a sentence rather than two permanent database fields. Revisit the
  real fix only if you find yourself linking lists to calendars on both devices in practice.

---

## T-623 — deleting a list can leave a few of its things behind

### What you would notice

When you delete an area, project, or context, the app deletes everything filed under it *that this
device currently has a copy of*. If another device added something to that list and this device has
not downloaded it yet — or if this device's first iCloud download has not finished — that item is not
in the list yet, so it is not deleted. It arrives afterwards with nowhere to belong.

Concretely, what you would see:

- **A task or two showing up in Inbox** some time after you deleted the list they were in.
- **An area showing up in the unfiled group** after you deleted the context it was in.
- **Nothing else.** Measured: the other five kinds of leftover row (goal links, habit completions,
  saved links, list notes, focus session logs) are already filtered out at every single place the app
  reads them, so none of them can produce a wrong count, a blank row, or a ghost entry. They sit in
  the database taking up space and are invisible.

You need two devices for this, or one device that is still doing its first sync, and you need a
delete to land in the window between the other device's write and this device's download.

**Nothing is ever lost.** The bias runs the other way: this leaks rows rather than destroying them,
and everything it leaks is somewhere you can see and delete yourself.

There is one honest wrinkle: on iPhone, the delete confirmation for an empty list says *"Nothing else
is filed under this — no tasks, notes or saved links will be lost."* That sentence can be false in
exactly this scenario. It is filed separately as **T-752**, and it is also a wording decision that is
yours. It is the only part of T-623 with words on a screen attached.

### What it would cost to fix

The durable fix — a hidden marker on every deleted list plus a background sweeper that catches
late-arriving orphans — was costed and re-costed:

- **13** of the app's 21 data types are reachable by a list delete (measured today: 21 types in the
  schema).
- **29** new hidden fields across those 13, plus one new record type.
- **~260** places in the app where an owner is assigned would each need to keep a hidden copy in
  step, plus **~470** more in the test suite. (Re-measured today with a deliberately loose pattern,
  so treat these as ceilings; the original tighter count was 215 and 425. The number has not gone
  down.)
- **It repairs nothing that has already happened.** The rows at risk are precisely the ones with no
  owner recorded, so there is nothing to copy the hidden marker *from*.
- **It only starts working once every one of your devices is on a build that has it.** That is a
  multi-release rollout, not a change with a day count.

The database mechanics are the cheap part and stay legal forever — a new record type and new optional
fields are exactly what a frozen Production schema still permits. The expense is entirely in the
~260 call sites and the rollout.

A simpler-sounding alternative, marking rows deleted instead of really deleting them, is worse: 246
list queries and 79 fetches in the app (re-measured today; the ledger's figures were 243 and 70)
would each have to learn to filter it out.

There is also no cheap middle option. "Warn the user that the delete might not be complete" needs the
app to know that its copy is incomplete, and it has no way to know that — measured again today, the
five things you would grep for to find such a signal return **zero** hits in the entire codebase.
And the obvious "wait for sync before deleting" gate fixes the rarer half of the problem: the common
case is a *peer* writing after your last sync, at which point your own sync is complete and no
"sync finished" signal can help.

### What it costs to leave

Stray recoverable rows in Inbox, and some wasted space in your iCloud storage. Both bounded, both
visible, both fixable by hand.

**Does it get more expensive after shipping?** Slightly, and in one specific way: the rollout clock
for the eventual fix starts at the first *shipped* build, so every month of shipping without it
lengthens the tail before the sweeper could safely run. It does **not** get more expensive in the
sense that matters — no data becomes unrecoverable, and the fix does not become illegal. That last
part is worth repeating: adding a new record type and new optional fields to a deployed Production
schema stays permitted indefinitely.

### Recommendation

**Leave it parked, and stop re-verifying it.** Three passes have now reached the same answer from
three directions. Re-open it only if the data model is being reworked for some other reason and this
can ride along.

The one thing worth doing separately is deciding **T-752**: whether that iPhone sentence should say
something weaker. That is a sentence, not a project.

---

## T-899 and T-1043 — two halves of one missing safety net

These two are the same ticket seen from two sides, and T-1043's own text already says the fix is one
file. Treat them as one decision.

### What you would notice

**Nothing, today.** Both are guards against a mistake nobody has made yet. Measured at HEAD today:

- **T-899 (the reading side).** Exactly **two** screens in the app read a stored calendar link, and
  both are correct and both are already pinned by name in the test suite. A *third* one, added later,
  would silently get the old broken behaviour back — announcing the other device's good link as dead,
  with a repair button beside it that overwrites it. That is exactly the behaviour removed in T-624,
  re-entering through an easy-to-forget default.
- **T-1043 (the writing side).** Every screen that *makes* a link has to also record locally that it
  made it, or the app can never later report that link as broken on the device that made it. Five
  files write one today, and every one is correct — for four unrelated local reasons, with no rule
  tying them together. A new screen that forgot would produce a link that works and can never be
  reported broken. Quiet in the worst way.

### What it would cost to fix

**One test file.** No model change, no database change, nothing added to the frozen schema, nothing a
user ever sees. It reads the app's own source code as text and requires each calendar-link site to
declare which case it is. One session of agent work.

### What it costs to leave

Flat and zero — right up until someone adds a calendar screen, at which point it is a silent
regression of a bug that took two rounds to fix.

**Is that hypothetical? Measured: no.** T-1043 was filed on 2026-09-05 describing three writer paths
in four files. On **2026-09-06 — the next day** — the archive importer landed and added a fifth file
with two more link writes. The population this guard exists to police grew within 24 hours of someone
writing down that it was stable, and it grew in a shape the proposed rule did not anticipate. That is
the argument for the guard, made by events rather than by prediction.

### A correction you should know before commissioning this

**T-1043's proposed rule would fail on today's code, and the failures would all be correct code.**
Measured today: 18 statements write a list's calendar link, and **four of them** satisfy none of the
three conditions T-1043 lists — two in the undo-a-list-edit path, two in the new archive importer.
Both of those are *restoring a value that was already stored*, not making a new link, and both are
deliberately right to record nothing.

So the rule needs a fourth allowance for restore paths. Whoever writes the sweep needs that in the
brief, or they will spend a session discovering it and may "fix" two correct call sites.

### Recommendation

**Fold T-1043 into T-899 as one ticket and schedule it as a single session.** It is not
release-blocking — nothing a shipped user can see depends on it. But do it **before iOS gets a
calendar row in its list editor** (measured today: iOS has none, which is the only reason there is
not already a third reading site). That change is precisely what this guard exists to catch, and it
is a natural next feature.

---

## What each of these needs from you, in one line

- **T-623** — say "stay parked" once, so it stops being re-verified. The sentence that was T-752's
  is now **T-1118**, which states the three options; picking one is a two-line diff.
- **T-624** — run the five-minute experiment above and report which of the three sentences you saw.
- **T-899 + T-1043** — say whether to merge them and schedule one session, or leave both open.
