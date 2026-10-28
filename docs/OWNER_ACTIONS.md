# Owner actions — the things no agent can do for you

Nine items. Every one is blocked on your hands, your devices, your Apple account or your
judgement, not on engineering effort. Agents have done the half that could be done and stopped
at the boundary; each section below says exactly where that boundary is and why.

**Read this way:** do items 1–3 first. Two of them take about two minutes each and unblock other
work; the third was the last thing standing between the project and a macOS TestFlight build,
and is done — build 25 went to internal TestFlight on both platforms on 2026-10-27.
Items 4–6 are short but need a second device or a spare moment during a run. Items 7–9 are
larger, and two of them are explicitly *not* needed for the internal release candidate.

After each item there is a **Tell me** line. That is what to paste back; the ticket closes on it.

| # | Item | Time | Ticket | Needed for the RC? |
|---|---|---|---|---|
| 1 | Unset the stale git hooks path | 2 min | T-4900 | No, but cheap |
| 2 | Calendar identifier check | 5 min | T-1117 | No — unblocks a parked decision |
| 3 | ~~Create a Mac Installer Distribution certificate~~ — done | — | T-7102 | Was yes; build 25 shipped |
| 4 | 24-hour time check | 2 min | T-1163 | No |
| 5 | Answer the automation prompt when it appears | seconds | T-2049 | No |
| 6 | Two-device archive comparison | 15 min | T-2053 | No |
| 7 | Backup-restore sync test on a test account | 30 min | T-3226 | No |
| 8 | App Store Connect privacy answers | 10 min | T-1424 | **No — public release only** |
| 9 | Logo artwork and a name | open | T-16 | No |

---

## 1. Unset the stale git hooks path — T-4900

**What is wrong.** This repository's git config points `core.hooksPath` at
`/Users/williamwei/Desktop/Projects/Cadence/.git/hooks`, a directory that stopped existing when
the project moved to `~/Developer/Cadence`. Re-verified today: the path still reads that way and
still does not exist.

**Why it does not matter yet, and why to fix it anyway.** No hooks are installed right now
(`.git/hooks` holds only `README.sample`), so the effect today is exactly nil. The reason to fix
it is that the failure is **silent**: the day anyone installs a pre-commit hook at `.git/hooks`
or arms the inert `.githooks/pre-commit`, it will never run, and nothing will say so.

**Why it is yours.** It is persistent repository configuration. No agent set it and no agent
should change it — it is the kind of setting that belongs to whoever owns the checkout.

**Do this:**

```bash
cd /Users/williamwei/Developer/Cadence && git config --unset core.hooksPath && git config --get core.hooksPath; echo "exit $? — 1 means it is unset, which is correct"
```

**Tell me:** the output. Exit 1 with no path printed is the result we want.

---

## 2. Calendar identifier check — T-1117

**The question.** When the same iCloud calendar appears on your Mac and on your iPhone, does
Apple give it the same internal identifier on both, or a different one? Apple's documentation
says the identifier is device-local, which makes "different" likely — but likely is not measured,
and a whole parked ticket sits downstream of the answer.

**Why it is yours.** Answering it means asking the calendar system on your Mac a question, which
raises a macOS permission prompt addressed to you. Agents are barred from triggering EventKit
permission or opening a real event store. That click is yours.

**You do not need a console. The app already displays the answer.**

1. On your **iPhone**, open **Cadence's own** Settings → Calendar — the app's settings, not
   iOS Settings. Find an **iCloud** calendar — *not* an
   "On My Mac" or "On My iPhone" one. A local calendar genuinely does not exist on the other
   device, which would give you a false answer. Use its link button and connect it to any area
   or project.
2. Wait about a minute for iCloud, then open Cadence on your **Mac**.
3. On the Mac, open that same area or project's edit sheet and look at the **Apple Calendar** row.

**Read the row. There are five things it can say and three of them are the answer:**

| The row says | What it means |
|---|---|
| **None** | The link has not synced yet. Wait, reopen, try again — this is not an answer |
| **The calendar's name** | **The identifiers match.** T-624's premise collapses and the ticket closes |
| **"Linked calendar is not on this device"** | **The identifiers differ.** T-624's premise holds |
| "…(hidden)" | Also a match — you have that calendar switched off inside Cadence |
| "Linked calendar is missing" | Should be unreachable here. If you see it, that is a new bug worth filing |

**Why this version of the test is trustworthy.** The sentence *"Linked calendar is not on this
device"* can only ever be drawn when a link **is** stored. So seeing it proves two things at
once: that the sync arrived, and that the identifier did not resolve. It cannot be confused with
"nothing synced".

**Tell me:** which of the five rows you saw, word for word.

---

## 3. ~~Create a Mac Installer Distribution certificate~~ — DONE, T-7102 CLOSED

**Resolved 2026-10-27. You are releasing both legs to internal TestFlight.** This section is kept
rather than deleted because the diagnosis in it was wrong in a way worth remembering.

**What this item used to say:** no Mac Installer Distribution certificate exists on this Mac, so
the macOS leg archives but cannot be packaged for TestFlight. The measurements behind that were
real — `productbuild --sign "3rd Party Mac Developer Installer: …"` genuinely failed, the same
command without `--sign` genuinely wrote an 11.2 MB `.pkg`, and the keychain genuinely held zero
installer certificates.

**Why it was wrong anyway.** Hand-rolled `productbuild` is the Mac App Store / Developer ID route.
It is not the route Xcode Organizer takes for an internal TestFlight upload — Organizer packages
and signs for internal distribution itself once it holds an App Store Connect session. The
certificate was never on your path. Re-measured at close: still **zero** installer certificates in
either `login.keychain-db` or `System.keychain`, and the upload works.

**What was actually blocking you.** Xcode 27.1 had no Apple Account signed in. Organizer stopped
with *"App Store Connect access for 'Haoran Wei' is required"* over an empty **No Accounts** table.
Confirmed on disk at the time: no account store under `~/Library/Developer/Xcode`, and
`security find-generic-password -s Xcode-Token` found nothing.

Signing certificates live in the login keychain and survive an Xcode major-version upgrade. The
**account** does not. This Mac had moved to Xcode 27.1 since the last successful uploads
(1.0 (9), 2026-06-01), which is why something that had never happened before happened now.

**If it recurs after a future Xcode upgrade:** Xcode → Settings → Accounts → **+**, sign in, retry
Distribute App. Nothing else is needed, and no certificate has to be created.

**The lesson, which is worth more than the item was.** A signing or packaging failure you reproduce
by hand proves only that your hand-rolled command fails. Before treating it as a release blocker,
check that the tool you will actually use takes the same path. The same shape caught us twice in
one day — see T-7500, where a build was verified against a tree it never compiled.

---

## 4. 24-hour time check — T-1163

**The question.** Does Cadence follow the system 24-hour time setting?

**Why it is yours.** It is a system preference on your Mac, and the check is "look at the app and
see". No agent can set a system preference on your machine, and no test can observe what you'd
see.

**Do this:**

1. System Settings → General → Date & Time → turn **24-Hour Time** on.
2. Relaunch Cadence.
3. Look at any surface with a clock time on it — the Calendar page, a task with a due time, the
   Today page.

**Tell me:** whether times read `14:30` or `2:30 PM`. If they read 24-hour, nothing is owed and
the ticket closes. If they still read 12-hour, that is a real bug and an agent will take it.

---

## 5. Answer the automation prompt when a UI run asks — T-2049

**What this is.** When a UI test run starts on this Mac, macOS may raise a per-session automation
permission prompt. It is addressed to you and it blocks the run until answered.

**Why it is yours.** It is a system security prompt. An agent clicking it would be defeating the
point of it.

**Do this:** nothing proactively. Next time you see a prompt asking whether an app may control
another app while a test run is going, answer it. Note that this is per-session — it can come
back after a reboot or a logout.

**Tell me:** that you answered it, and what it asked. There is a second half of this ticket about
a hung runner that unexpectedly recovered, which is still unexplained; if you ever see a run hang
and then free itself, that detail is worth having.

---

## 6. Two-device archive comparison — T-2053

**What is already done.** The signing-environment guard is landed and covered by 11 tests
(`CadenceSigningEnvironment` in `Cadence/Services/PersistenceController.swift:1196`, acted on at
`:610` — both re-read at HEAD on 2026-10-27; the file has shifted by one line since this was
written). It fails safe: anything it cannot read leaves CloudKit **on**. A distribution-signed
TestFlight build will sync to the Production CloudKit environment, which is what you want.

**What is left, and why it is yours.** Confirming the guard's behaviour across two real devices
signed into your own iCloud account. No agent can arrange two of your devices or use your iCloud
account.

**Do this:**

1. Install the build on two of your devices, both signed into your iCloud account.
2. On device A, export an archive from Settings.
3. On device B, export an archive from Settings.
4. Compare the two files — do they describe the same data?

**Tell me:** whether the two archives agree, and if they do not, where they diverge.

---

## 7. Backup-restore sync test on a test account — T-3226

**The question.** After you restore an older backup, what does iCloud sync do to the restored
store? Specifically: does the restored store resume syncing from the backup's own change tokens,
so that newer iCloud changes come back in — and do rows the cloud has since deleted get deleted
again?

**What is already settled in code.** The in-process half is done (T-1477):
`StoreBackupManager.performPendingRestoreIfNeeded` runs in `PersistenceController`'s launch
preflight *before* `makeContainer()` opens the CloudKit-backed store, so a restore cannot race a
sync within the same process. That part is not in question.

**Why it is yours.** The after-half cannot be measured against a disposable store, and your own
2026-10-18 ruling forbids measuring it against a real one. It needs a test iCloud account and a
throwaway device store. That is yours to arrange.

**What hangs on the answer.** `CadenceStoreBackupPresentation.cloudKitNote`
(`Cadence/Shared/CadenceStoreBackupPresentation.swift:73`) currently says newer iCloud changes
"can sync back in" — stated as a possibility rather than a promise, precisely because nobody has
measured it. Your result either keeps that wording or tightens it to something definite.

**Do this:**

1. On a **test** iCloud account and a throwaway device store — not your real one — let some data
   sync.
2. Stage a restore of an older backup.
3. Watch what arrives afterwards: do newer edits from the cloud come back in? Do rows you
   restored, which the cloud had deleted, get deleted again?

**Tell me:** what came back and what vanished. The copy gets rewritten from your answer.

---

## 8. App Store Connect privacy answers — T-1424

**This is public-release work. It is NOT needed for the internal TestFlight RC** — TestFlight
internal testing does not depend on the nutrition label. Park it until you are going public.

**What is already done.** `Cadence/PrivacyInfo.xcprivacy` declares exactly one collected type,
`NSPrivacyCollectedDataTypeOtherUserContent`. The `Name`, `EmailAddress` and `UserID` rows were
removed because Apple's published test for "collected" is transmission off the device.

**Why it still needs you.** The manifest does **not** feed the product page. Xcode aggregates
manifests into a privacy *report*, and Apple's own instruction is to refer to that report when
you fill in App Store Connect by hand. There is no derivation and no upload validation for
`NSPrivacyCollectedDataTypes`. So until someone signs in and types it, the bundle says three
identity types are not collected while the public label may still say they are.

**Do this,** in one sitting, in App Store Connect:

- **Name** → not collected
- **Email Address** → not collected
- **User ID** → not collected
- **Other User Content** → leave as it stands

**Tell me:** that the three are answered. Your earlier instruction on this topic stands and I am
not raising it again beyond this entry.

---

## 9. Logo artwork and a name — T-16

**Two things block this and both are yours.**

**(1) The chosen artwork does not exist in the repository.** You picked concept A, the folded D,
from `design/icon-concepts-2026-09-20-dwell-d/`. But commit `1107671e` added only that
directory's `README.md` — the A/B/C sketches and the 120/80/40pt ladder it describes were never
committed, and no matching `.svg` exists anywhere under `design/`. Render QA is therefore
asset-blocked rather than undone, and Codex was right to refuse to redraw a look-alike in place
of approved geometry.

**Your choice:** supply the concept-A file, or approve a redraw of A from the README's
description as a new round — which would then need your re-approval.

**(2) No name survived the screen.** All eight candidates are conflicted: Dayfold, Daymark,
Dayleaf, Daylet, Denote, Diem, Docket, Dovetail. The first seven have direct or close
planner/note/task products; Dovetail sits in adjacent research software. The evidence with URLs
is in `docs/audits/2026-09-25/naming-screen.md#r56-all-eight-have-conflicts`.

**Not RC-blocking.** The shipped app icon set is complete at HEAD for both iOS and macOS, so the
archive does not depend on any of this.

**Tell me:** whether you are supplying artwork or want a redraw, and whether you want another
naming round.

---

## Before each upload: what a TestFlight build needs beyond item 3

**Build 25: DONE.** It went to internal TestFlight, macOS and iOS, on 2026-10-27. That date is
your word, recorded in `docs/SESSION_HANDOFF.md`; the upload happens in Organizer and nothing in
the tree records it. Everything below is restated for **the next upload**, which must carry a
`CURRENT_PROJECT_VERSION` **above 25**. Re-read 2026-10-28: the tree still reads 25 on the app and
widget targets, so the bump is the first step of that upload and has not been taken.

Not a tenth item and not a tenth ticket — there are still nine. Item 3 ends at "the certificate
exists", and the upload is the step after it. No document in this repository describes that step:
`docs/apple-release-readiness.md` and `docs/app-store-submission-packet.md` are written for the
public Mac App Store release and `docs/direct-distribution-runbook.md` for Developer ID, and an
internal TestFlight build is neither. This section is the gap, checked against HEAD on 2026-10-27.

**Already handled — these need nothing from you, and are listed so you do not go looking.**

- **Export compliance is answered in the bundle.** `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption =
  NO` is set on both of the app target's configurations, so App Store Connect will not ask you the
  encryption question once per build.
- **The app and its widget extension agree on everything an upload compares.** Read per target
  rather than grepped: `MARKETING_VERSION` 1.0, `CURRENT_PROJECT_VERSION` 25, both deployment
  targets 26.1, device family `1,2`, team `SM6Y3D2D55`, app group `group.com.haoranwei.Cadence`,
  iCloud container `iCloud.com.haoranwei.Cadence`, and bundle ids `com.haoranwei.Cadence` and
  `com.haoranwei.Cadence.CadenceWidgets`. A mismatch here is the classic rejection and there was
  not one for build 25. (The test bundles still read 24 and the MCP server reads 1; none of the
  three ships.) **When the number is bumped for the next upload, bump the app and the widget
  together** — four `CURRENT_PROJECT_VERSION` lines, two configurations each — or this check fails.
- **Build 25 is now the highest uploaded build**, so 25 itself would be rejected as a duplicate.
  The next upload needs 26 or higher.
- **Both binaries carry a privacy manifest**, app and widget, each declaring the UserDefaults and
  file-timestamp reasons.
- **Internal TestFlight needs no Beta App Review, no nutrition label and no test information.**
  That is why item 8 is marked "public release only" — it is, and nothing about the internal RC
  changes it.
- **No new CloudKit schema obligation.** This is the one that would have been expensive to miss:
  a TestFlight build talks to the **Production** CloudKit environment, and a record type or field
  that exists only in Development can abort mirroring for the whole store. The readiness document
  carries that rule with a measurement dated 2026-10-20 and says in terms "redo it, do not re-read
  it". It was redone at HEAD on 2026-10-27, against the 2026-10-02 deploy you verified in the
  Console: 24 `@Model` types, byte-identical `CadenceSchema.swift`, and not one stored property
  added in between. **Nothing was owed for build 25.** For the next upload this is a measurement
  to redo against that build's HEAD, not a standing answer: a stored property added since
  2026-10-27 changes it.

**What cannot be checked from here at all.** No agent has, or may seek, App Store Connect access,
so these are yours and nothing in the repository can confirm or deny them. They are listed in the
order Organizer will hit them. Items 1, 2 and 4 were one-time setup and build 25 reaching
TestFlight on both platforms is the evidence they are done; 3 and 5 recur every upload.

1. ~~**An App Store Connect app record must exist for `com.haoranwei.Cadence`.**~~ Done — build 25
   was accepted into it.
2. ~~**That record must have the macOS platform enabled.**~~ Done — the Mac leg of build 25 is in
   TestFlight. It stays relevant only if the record is ever recreated.
3. **The build number must exceed the highest build already uploaded for version 1.0** — 25 as of
   2026-10-27, so the next upload needs `CURRENT_PROJECT_VERSION` 26 or higher. (If
   `MARKETING_VERSION` moves past 1.0, this compares against that version's builds instead.)
4. ~~**Internal testers must be added.**~~ Done for build 25 — it was installed and tested from
   TestFlight (T-7550 was reported from it). New testers still need a role on the team first.
5. **The upload itself**, through Xcode Organizer, every time. Agents are barred from it, and
   `scripts/xcb.sh export-archive` refuses `destination: upload` and the `app-store` /
   `app-store-connect` / `validation` methods before it reaches `xcodebuild` — re-read at HEAD on
   2026-10-27 and still intact. That refusal is correct; it is not something to work around.

**One repository-side thing to do in the same sitting as the archive, because it takes a second.**
Every file under `Cadence/` or `CadenceWidgets/` that is not a known source type is copied into
the shipped bundle as a resource, with nothing in the project file to notice — that is how 19 KB
of macOS source shipped inside the iOS app (T-7101). The `.gitignore` rule added afterwards stops
such a file reaching git but **not** the bundle, and it also means `git status` no longer shows
one. The tree is clean as of 2026-10-27; a test to keep it that way is filed as T-7277. Until it
lands, run this immediately before you archive and expect no output:

```bash
cd /Users/williamwei/Developer/Cadence && find Cadence CadenceWidgets -type f \( -name '*.orig' -o -name '*.rej' -o -name '*.bak' -o -name '*.swp' \)
```

---

## What is deliberately not on this list

- **Chinese localisation (T-18)** — parked. v1 ships English only.
- **Anything an agent can do.** If an item here turns out to be doable without your hands, it
  leaves this file and becomes a normal ticket.
