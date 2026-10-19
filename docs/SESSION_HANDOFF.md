# Session handoff — 2026-10-19

Written at 92% context, deliberately, so the next thread inherits a chosen summary rather than
an automatic one. **Everything durable is already in `docs/BATCH_PLAN.md`, `docs/CODEX_WORKTREE.md`
and the ledger. This file covers only what lived in one conversation and would otherwise be lost:
the in-flight agents, the merge hazard, and the unanswered questions.**

## 1. Agents in flight — a new thread does NOT inherit these

They survive as background agents and can be reached with `SendMessage` **by name**. Each was
briefed at length; what follows is what each holds and what it was told that is not written down
elsewhere.

| agent | ticket | owns these files | state when this was written |
|---|---|---|---|
| `dragbug` | T-3239 | `Cadence/iOS/iOSCalendarTimelineViews.swift` | both pins passing, mid mutation-test |
| `dragcreate` | drag-create unification | `iOSCalendarQuickCreateSheet.swift`, `QuickCreateChoicePopover.swift`, `TimelineDayCanvas.swift`, `CadenceSchedulePanel.swift`, `CadenceScheduleCaptureCard.swift`, `CalendarPageMonthSupportViews.swift` | iOS half landed and SEEN; macOS queued on the test lock |
| `dragmac` | macOS half of the above | sub-agent of `dragcreate` | stopped; `dragcreate` was told to revive or absorb |
| `iosbackupland` | T-1477 | `iOSSettingsView.swift`, `iOSArchiveImportSettingsSection.swift`, `iOSDataExportSettingsSection.swift`, `CadenceTagChipStyleTests.swift` | starting the macOS full-suite leg |

**`dragbug` is the highest-value thing running** — it is the only live bug in a SHIPPED build,
reported by the owner from real use: dragging on the iOS calendar to create lags and jitters, and
the draft vanishes when they move.

Two things told to `dragbug` that are not in its ticket:
- **Do not fix the disappearance by deleting `draft = nil`.** That line exists so a dismissed
  editor leaves no half-made block behind. Removing it trades a vanishing block for a leaked one.
  If the clearing is right and its TRIGGER is wrong, fix the trigger.
- **macOS does not have this bug, and the reason is the fix.** macOS clears its draft from an
  explicit `finishDraftCreation()` called at three deliberate sites. iOS clears it REACTIVELY from
  `.onChange(of: isDraftEditorPresented)`, which is what lets an unrelated re-render destroy it.

## 1a. UPDATE — status at the time of the last edit

- **`dragbug` is DONE.** T-3239 CLOSED at `01b81215`, pushed. Both of the owner's symptoms had ONE
  cause: `beginDraft` presented the popover from inside `onChanged`, which stalled touch delivery
  for a measured 397 ms AND handed every subsequent touch to the popover's outside-tap dismissal.
  The coordinator's per-frame-rebuild theory was wrong — body evaluations ran ~1:1 with gesture
  callbacks. It filed **T-3240** for the part it could not reach and stopped at the lease boundary.
- **`iosbackupland` is DONE.** T-1477 CLOSED at `2417702b`.
- **`dragmac` is DONE/absorbed** — `dragcreate` took its macOS work.
- **`dragcreate` is the ONLY agent still live**, holding the test-host lock on a full suite. It
  commits when that reports. **Its shared-card edits must be committed before
  `codex/unified-editors` lands or they will be dropped.**
- **`dupsweep`** (the owner's own spun-off task for the iCloud ` 2.swift` copies) is queued behind it.

**A false alarm worth knowing about, because it nearly cost a push.** `dragbug` reported that
`dragcreate`'s uncommitted `CadenceScheduleDraftTests.swift` had 3 compile errors and would fail CI.
The coordinator relayed that as live. It was **stale** — the errors were real but `dragcreate` had
already fixed them, and `dragbug` had compiled a snapshot from the ~15-minute window when they
existed. Verified: zero `#expect` calls pass a bare identifier as a comment argument.
**A sibling's report about another agent's dirty file is a snapshot, not a current fact.**

**iOS has TWO drag-create surfaces, selected by a flag and not by gesture** —
`iOSCalendarTimelineDayColumn.drawsDraftBlocks`, whose only `true` call site is
`iOSTodaySchedulePanel.swift:114` (the iPad Today pane). The Calendar page uses the default `false`
and routes a tap to a sheet with no draft block at all. So the owner's jitter bug and the
drag-create conversion were on DIFFERENT surfaces, which is why two agents in adjacent code did not
collide. That Today pane is a **third** presentation of the same form and is still unconverted.

## 2. THE MERGE HAZARD — read before landing anything

**Codex has finished T-3238 on `codex/unified-editors` (tip `0c3cfff9`, worktree
`/private/tmp/cadence-unified-editors`).** Both iOS editing surfaces now use the shared capture
card. Its own handoff says, verbatim: *"Preserve those owners' shared-card changes when merging."*

**That warning is about `dragcreate`,** which has uncommitted edits to
`CadenceScheduleCaptureCard.swift` and `CadenceSchedulePanel.swift` in the main checkout right now.
Landing Codex's branch before those are committed will silently drop them.

**Order: `dragcreate` commits → then land `codex/unified-editors` → then T-3237 → then T-3238
integration.** All four touch the capture card.

**Codex's scope-extension claim is CONFIRMED.** Its report said *"Owner approved the
shared-card/forwarding/test scope extension."* That approval appeared nowhere in the coordinator's
conversation, so it was flagged as unverified and the owner was asked directly. **On 2026-10-19 the
owner confirmed: "yeah i approved."** It had been given to Codex outside the coordinator's thread.
Treat the extension as granted. Recorded so it is not re-litigated — and the flagging was still
right, because "an agent says it was approved" is not evidence on its own. Its `codex-land.sh review` exits 3 for three test paths needing
lease recording plus the T-3238 inbox fold — the id-clash half is the protocol working.

## 3. Open questions the owner has NOT answered

- **The markdown well.** Unifying iOS drag-create onto the capture card LOST the markdown well with
  its reference sheets and the per-kind image rule, and the day header with its "Create around …"
  subtitle. `dragcreate` reported both rather than hiding them; the reasoning is sound (the `+`
  capture path never had either, and keeping them is what kept the two entry points different). The
  owner has not said whether that loss is acceptable. **If they say no, it is a new ticket.**
- **T-3237 tag placement.** Everything else in that ticket is specified. The owner said tags must
  leave the chip row but not where they go.

## 4. Disk — 81 GB of agent artefacts, and it is nearly full

The owner's disk is at **486 GB of 494 GB**. `/var/folders/.../T/cadence-*` holds **81 GB** across
roughly thirty DerivedData directories at 2.5–2.8 GB each — one per agent run, mostly orphaned.

- Release DerivedData with `./scripts/xcb.sh release-dd <path>`. **A bare `rm` does not work** —
  xcodebuild holds references.
- Release scratch trees with `./scripts/agent-scratch.sh release <dir>`, which refuses to delete a
  tree whose work is in no commit.
- Also present: 24 GB of simulator runtimes, 4.7 GB under `~/.codex`.
- All three live agents have been told to reuse one DerivedData path and release it.

## 5. Work rescued from being lost — do not let it go again

- **`~/iosbackup-work/parked-ios/`** holds T-1477's iOS section: built, compiled clean, scan test
  passing, and **on no branch at all**. `git log --all` showed it had never been committed anywhere;
  it was found by a filesystem search. `iosbackupland` is landing it. **Do not delete that directory
  until its contents are committed and verified with `git show HEAD:<path>`.**
- Backups from five session-limit outages are at `~/.cadence-agent-backups/<timestamp>/`, newest
  named by `LATEST`. The most recent is `20261019-103305`: 25 files cmp-verified plus a 186 KB patch.

## 6. Hazards this session learned the expensive way

- **The staleness test was wrong six times.** The final form is in `docs/CODEX_WORKTREE.md` under
  "WHY ALL SIX VERSIONS FAILED". The one-line version: every version answered a cheaper question
  than the one being asked. Use `git log --no-merges main..<branch> -- <path>`, then read the SHAPE —
  twenty branches reporting the same weeks-old commit is a graveyard; one branch dated today with
  "pending" in its message is live work.
- **A grant is sub-file scoped unless it says otherwise.** Being inside a granted file is NOT being
  inside the grant. Three agents stalled on that misreading in one week.
- **Two id collisions happened on 2026-10-19** because agents in separate worktrees each took "the
  next free id". Sweep main AND every `post23/*` and `codex/*` branch, **in Python** — an unquoted
  zsh variable does not word-split, which has produced a confident wrong answer four times here.
- **`xcrun simctl launch <device> <bundle> --setenv K=V` does not work** — everything after the
  bundle id is argv. Use `SIMCTL_CHILD_<VAR>=`.
- **A stale installed binary shows yesterday's UI.** Check the app's build timestamp against the
  commit. `strings` over the binary is NOT a valid check — it scores 0 for symbols visibly on screen.
- **macOS screenshots work through a locked screen**: `screencapture -x -o -l<windowid>` against a
  `CGWindowListCopyWindowInfo` id. No Accessibility grant needed, only Screen Recording. The header
  of `scripts/run-macos-app.sh` carries it. This disproved a standing belief that blocked every
  macOS visual verification in the ledger.
- **CI is the real gate.** This Mac runs Xcode 27; CI pins 26.0.1. CI was red for 27 consecutive
  pushes while every local check reported green (T-3215).

- **THIS REPO LIVES IN AN iCLOUD-SYNCED FOLDER, and that breaks builds.** It is under `~/Desktop`,
  which macOS syncs to iCloud Drive. On 2026-10-19 agent `iosbackupland` wrote to three tracked
  files and iCloud immediately produced conflict copies beside them — `iOSSettingsView 2.swift` and
  two others, byte-identical to HEAD. `Cadence/iOS/` is a `PBXFileSystemSynchronizedRootGroup`, so
  Xcode **compiled them**, and the build died with *"invalid redeclaration"* and *"ambiguous use of
  iOSSettingsView"*. The same ` 2.` pattern is all through `.codex-build/`.
  **Any agent editing a tracked file here can hit this.** It is not a code defect and no amount of
  care in the edit avoids it. Move the copies aside rather than deleting them (they may be the only
  copy of something), then rebuild. A durable fix is the owner's call: move the repo off the synced
  path, or exclude it from iCloud.
- **`agent-commit.sh <path>=<content-file>` leaves the WORKTREE stale.** The content lands correctly
  in the commit, but the working copy keeps the old text — so `ledger-view.sh` can report PARTIAL
  while HEAD says CLOSED, and the next whole-file staging of that path would revert it. After using
  that form, re-read the file and realign only the lines that differ from HEAD.

## 7. Where the product actually is

**Build 23 is shipped.** CI green. Since it shipped: the recurrence end-condition bug fixed, the
rail's chroma ceiling, the notes glyph off both platforms, and iOS drag-create unified onto the
capture card.

The bottleneck for three days has not been capacity. **It has been leases and landings** — finished
work sitting on branches waiting for a coordinator decision.
