# RC Queue — owner-visible defects for the next RC

Written 2026-10-21 by agent `rcqueue` at `993cc30a` (Build 24). Read-only triage of the OPEN and
PARTIAL entries in `./scripts/ledger-view.sh brief`; no build or test was run. Point-in-time: the
ledger's own first line is the authority, and a dirty file named here can be clean within the hour.

"Polished" here means fewer visible defects the owner would hit, macOS first, then iOS/iPadOS.
Ranked by how likely the owner sees it in ordinary use, times how cheap it is to fix.

## Excluded on purpose

- Being worked: T-3171 (`t3171mac`), T-3170 (Codex `codex/block-removal-finish`), T-3288/T-3289
  (CI), T-3260 (Codex), T-3166/T-3315 (k1mac/k2mac).
- Dirty in the main checkout at triage time, compared file-by-file against `main`:
  `TimelineEventBlock.swift`, `TimelineMetricsSupport.swift`, `CadenceSavedLinkPersistence.swift`,
  and the tests `CadenceCalendarOverlapLayoutTests`, `CadencePendingChangePersistenceTests`,
  `CadenceTaskPresentationSupportTests`, `MarkdownImageDropAffordanceTests`.
  So T-3222 (notes excerpt cut mid-word) is excluded: its code is on main
  (`CadenceTaskPresentationSupport.swift:365-377` cuts on a word and adds an ellipsis) and its test
  file is dirty, so someone is on it.
- Internal cleanup, tooling, CI, docs residue and test-suite performance (about 60 entries).

## Fence note (applies to every "leased" blocker below)

`docs/CODEX_WORKTREE.md:3180` (2026-10-20, owner decision, T-3257) releases EVERY fenced path to
local agents. A ticket that says it stopped "at the fence" may no longer be blocked. Codex-held
paths are now only the T-3170 four (`:3211`) and the T-3260 two (`:3283`). Two old Codex worktrees
(`text-scale-finish`, `platform-parity-audit`) hold copies that differ from main for
`CadenceScheduleCaptureCard`, `CadenceSchedulePanel`, `CalendarPageSupportViews` and
`CadenceCalendarOverlapLayout`. T-3257 found no unlanded work on fenced paths. I did not redo that
check file by file.

## Ranked queue

1. **T-3269** — macOS. The Calendar page title wraps mid-word at a ~960pt window: `Cal/end/ar`,
   `Octobe/r 2026`.
   - Evidence: `Cadence/macOS/Views/CalendarPageSupportViews.swift:20-28`. The title and month
     `Text`s have no `lineLimit` or layout priority, and the file has no `lineLimit` anywhere.
   - Size S. Touches `CalendarPageSupportViews.swift` only. No sync. Needs a window capture of the
     fix.
2. **T-3233** — iOS and macOS (shared capture card). Choosing *Ends: On Date* defaults the end to
   the START day, so the series ends the day it begins. For events, T-3229 now writes that end to
   Apple Calendar as `EKRecurrenceEnd`.
   - Evidence: `Cadence/Shared/Components/CadenceScheduleCaptureCard.swift:743` seeds from
     `draft.startDateKey`. The other Ends controls seed
     `CadenceTaskRecurrenceEndPresentation.defaultEndDateKey()`.
   - Size S. Touches the capture card plus a pin test. No CloudKit, but it writes to EventKit, so
     mutation-test it. The fence that stopped it is released.
3. **T-3253 (a)** — macOS. Clicking the Due (or Do) chip on a note's inline task embed opens the
   panel with every row collapsed.
   - Evidence: `Cadence/Shared/Components/CadenceSchedulePanel.swift:138-139`.
     `isDoExpanded`/`isDueExpanded` are `@State private` and nothing outside can open them.
   - **The blocker is stale.** It named an uncommitted edit in `~/.codex/worktrees/9e4a`, and that
     file is now byte-identical to main (`cmp` 0). The title-focus modifier it held has landed.
   - Size S-M. Touches `CadenceSchedulePanel.swift` (one defaulted parameter) and
     `Cadence/macOS/Editor/MarkdownInlineTaskPanelSupport.swift`. No sync.
4. **T-3219** — macOS. A timed event that starts 24-33 minutes after an event with a two-line
   title covers that event's time row.
   - Evidence: `Cadence/Shared/CadenceCalendarOverlapLayout.swift:150` has
     `macEventTitleHeaderLineCount = 1`, while the block draws its title with `.lineLimit(2)`.
   - Size S (one constant plus a pin). The ticket asks for an owner nod. Its pin belongs in
     `CadenceCalendarOverlapLayoutTests`, which is dirty (T-3166), so do it after T-3166 lands.
     No sync.
5. **T-3249** — iOS/iPadOS inline task panel in notes, three rough edges:
   - (3) the floating `+` covers most of Save once the action row is scrolled above the keyboard.
     `iOSFloatingCreateTaskButton.swift` never refers to the inline panel.
   - (2) the hit area is tight. The card tap test uses only 4pt of slop
     (`Cadence/iOS/iOSMarkdownEditor.swift:1053`).
   - (1) the `[[` strip flashes "No matching tasks" after a save that renames the task.
   - Size S for (2) and (3), M for (1). No sync. The fence that stopped (3) is released.
6. **T-3265** — iOS at large Dynamic Type. Timed blocks cascade at the wrong gap: titles collide,
   or blocks split that would have fit.
   - Evidence: `Cadence/iOS/iOSCalendarMetrics.swift:470` passes the static `iOSEventHeaderHeight`
     against a type-scaled `hourHeight`.
   - Size M. Touches `iOSCalendarMetrics.swift` and `CadenceCalendarOverlapLayout.swift`. No sync.
     Not seen on screen, so it is latent. The ticket calls it the owner's call.
7. **T-3109** — iOS. Reminders for a task completed from a widget may survive a return to the app.
   - The fix is on main (`Cadence/iOS/iOSRootView.swift:187` reads
     `CadenceForegroundNotificationSnapshot`). The entry says its tests' results are "still
     pending".
   - Size S: run the tests and close it. Touches the store read path, so mutation-test the
     throw-versus-empty branch.
8. **T-1461** — iOS/iPadOS widgets. The layout, routing and date fixes are in, but nobody has looked
   at a widget on a device.
   - Size S. Verification only, needs an attended simulator. SHIP-NOTE if nobody gets to it.
9. **T-3216** — iPad. The mobile-parity month fixture, outline jump and unlinked-mention action
   have never been run or seen. They rest on Codex's word.
   - Size S-M. Verification only (`CadenceIOSCalendarAndNoteParityUITests`, attended). No sync.
10. **Mac look session** — T-3160, T-3163, T-3167. Each is PARTIAL only because a macOS frame was
    never seen (rails, all-day month chips, rail clipping).
    - Blocked by T-3259: `run-macos-app.sh` refuses while the owner's Cadence runs. One session with
      the owner's app quit settles all three.
    - Size S. SHIP-NOTE them if that session does not happen before the RC.

## PARTIALs that should get a SHIP-NOTE (deliberately half-done, fine to ship)

- **T-3252** — the keyboard half is on main (`CadenceSchedulePanelTitleFocus`, 5 hits in
  `CadenceSchedulePanel.swift`). What is left is that the iPad draft editor disappears for the
  length of an edge-handle drag. That needs a different presentation, which is a design decision.
- **T-3169** — the iPad Today draft-block create landed. It is only "not yet seen on screen".
- **T-3046** — Mac reconciles notifications on activation. The sync-driven trigger was left out on
  purpose: a reconcile is a removal.
- **T-3147** — the phone capture-hold delay does not reproduce at 3,000 tasks in the simulator. The
  next step is a trace on the owner's phone, not code.

## Lease-blocked PARTIALs that are visible (lease-blocked, see leasesweep)

- T-3140: macOS Board day columns do not move on at midnight. Also waits on T-3170.
- T-3089: the Mac search cap row.
- T-3049: an iOS cold-launch deep link.
- T-3051: a calendar presentation DST edge.
- T-2054: the iOS list editor's Lists row.
- T-1400, T-1410, T-1411: text-scale halves.

## Owner decisions only (one line each)

- T-3125: two lists deliberately given the same name are fused at the next launch. Refuse the
  duplicate, narrow the merge, or say so in the UI? (`DataIntegrityRepairService.swift:358-359`)
- T-3213: a Block arriving from iCloud mid-session hides its tasks until relaunch
  (`CadenceScheduleSupport.swift:410-434`). Accept, or re-run the retirement mid-session?
- T-3146: reset-then-import can leave a daily note mangled under a `---` merge. Which rule should
  apply?
- T-3145: an overwrite import can lower a pre-ledger focus counter. Switch to `max`?
- T-3041: nothing outside Settings says a cold iCloud import is in flight. Add an indicator?
- T-1845: the Today inspector popover covers 10pt of the row's due chip on a wide window. Where
  should it go?
- T-2090: the compact Tasks page spends a whole row on List Order / Completed. Merge it into the
  header?
- T-3295: event plates are luminance-equalised, unlike Apple's, so yellow and blue weigh the same.
  Keep it?
- T-3232: the 10pt calendar glyph is now the loudest red on a block. Tone it down?
- T-3207: should an iOS timeline block drag sideways to another day?
- T-3084: should Mac search find list documents? This is extra scope.
- T-3030: what should a habit with an unreadable weekday list be due on?
- T-3102: the destructive half of Data Safety on a recovery launch.
- T-1840: should Delete Account & Data remove the recovery and legacy stores?
- T-1163: does Cadence follow the Mac's 24-Hour Time setting? Needs the owner to turn it on and look.
- T-3226: what syncs back after a staged restore? Test account only.

## Not verified

- Nothing was built, run or seen on screen. Every "present" claim is a source read at `993cc30a`.
- Dirty-file status came from `cmp` of the main checkout against `main`'s blobs, because this agent
  could not run `git status` there. Untracked files outside `Cadence/` and `CadenceTests/` were not
  checked.
- The old Codex worktree copies listed under the fence note were not diffed for unlanded hunks.
- T-3315 is not in this tree's ledger, so its files were inferred from the dirty list.
