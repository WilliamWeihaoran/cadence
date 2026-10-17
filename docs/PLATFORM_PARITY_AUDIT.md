# macOS / iOS platform parity audit

## Summary — 16 October 2026

**Source audit of 26 concrete differences; no product changes, builds, tests or app launches.** This is an inventory of the named surface pass, not certification of runtime parity or all 517 files. Both deliberate choices and unresolved gaps are counted. UNKNOWN means the implementation differs but no examined comment/ticket establishes why. No finding is classified DRIFT merely because it looks accidental.

Audit branch: `codex/platform-parity-audit`, created from fetched `origin/main` and rebased before inspection. Product base: `8c6d218e3848d2fcee270cc393c64d0ba5ae8952`; tree: `d2cdf0d8004a1556a15ef70d8701163f3f5cebbe`. The audit worktree began clean. The separate main checkout had unrelated work and was not edited. Source line references below are pinned to this base, not a later landing tree.

| KIND | Count |
|---|---:|
| DATA | 2 |
| INFORMATION | 12 |
| BEHAVIOUR | 5 |
| INTERACTION | 6 |
| COSMETIC | 1 |

| INTENT | Count |
|---|---:|
| IDIOM | 7 |
| DRIFT | 0 |
| LAG | 3 |
| BLOCKED | 2 |
| UNKNOWN | 14 |

**Five findings to address first, in order:**

1. **PA-13 — failed iOS board drops report success.** Persistence refusal must not leave a moved-looking card and pending fields. Mac already has a tested transactional pattern; extend the contract to the actual mobile path.
2. **PA-26 — stale iOS state after external writes.** *(Landing correction: half of this is already fixed — see PA-26's LANDING NOTE. The notification arm landed in `7343bfe8`; only the UI-adoption arm survives, and it is the blocked [[T-1469]]. Read #2 as PA-14 in practice.)* A completed widget task that remains active in the app/reminder plan undermines trust across devices and entry points. Resolve the existing T-3109 ownership block rather than inventing a second refresh mechanism.
3. **PA-14 — Mac board date moves skip immediate notification reconciliation.** Persistence success alone is insufficient when the reminder still describes the previous schedule. Prove the successful mutation and notification side effect as one contract.
4. **PA-01 — Mac task rows omit note excerpts.** This is the owner-observed information gap and affects routine Today scanning. Preserve the notes glyph until the chosen replacement actually exposes the information. PA-02 is the closely related subtask follow-up.
5. **PA-19 — Mac search silently caps matches.** A search that appears complete but cannot reveal a matching item is more damaging than a different layout. Preserve bounded initial rendering while making the remainder reachable.

PA-20 (list-document search) is already a blocked scope decision in T-3084. The two note-discovery gaps PA-15/16 also warrant tickets. Deliberate truncation/space choices stay in this inventory for owner review, without cosmetic ticket spam.

**Evidence level:** code paths and comments were inspected; no new runtime failures were induced. “Tests cover” below means the inspected assertion contract exists, not that this audit ran it. Failure consequences and device behavior are explicitly identified as inferred where relevant. Reported absences name the specific host where a counterpart would belong. Search used raw source for symbols, literals and comments; no literal-absence claim uses `CadenceSourceScan.codeOnly`.

## Landing corrections — 2026-10-16 (coordinator `parityland`, the commit carrying this file)

**The audit's line references are pinned to `8c6d218e`. Main is 19 commits ahead of that base, and the
T-3170 Block/bundle retirement landed in between.** Every citation below that names a file changed since
the base was re-read at the landing HEAD; citations in files that did not change were left alone and
still stand. What changed is recorded in each finding under **LANDING NOTE**. Nothing was marked stale
on inference — each note says what was run and what it returned.

Files changed since the base (`git diff --name-only 8c6d218e..main`) that this audit cites:
`iOSCalendarBoardView.swift`, `iOSCalendarMonthViews.swift`, `iOSCalendarTimelineViews.swift`,
`iOSRootView.swift`, `iOSCompactTabShell.swift`, `CalendarPageMonthSupportViews.swift`,
`CalendarPageBoardSupportViews.swift`, `CalendarBoardDayColumnSupportViews.swift`,
`CalendarBoardDayDropCommitTests.swift`, `CadenceCalendarChipTreatmentTests.swift`.
The files behind PA-01/02/03/05/06, PA-15/16, PA-19/20 and PA-23's Focus halves are **unchanged**,
so those line numbers are the audit's own and were not re-derived.

| Finding | Disposition at landing |
|---|---|
| PA-04 | **Half superseded, half live.** The estimate half is overtaken by [[T-3196]]. The block-badge half **survives** — see its LANDING NOTE; an earlier reading of this landing called it stale and was wrong. |
| PA-11 | **Partly repaired.** Both platforms now call the one shared priority; only the capacity figure still differs. |
| PA-12 | Live. Its ticket is **T-1474**, re-allocated from the audit's T-1469. |
| PA-13 | **Live, and still the strongest finding here.** One stale citation dropped; the rest re-pinned and sharpened. |
| PA-26 | **Half repaired.** The notification half landed in `7343bfe8`; the UI-adoption half is [[T-1469]]. |
| PA-01, PA-10, PA-14, PA-19, PA-23 | Live; cross-links and re-pins only. |

**ID RE-ALLOCATION: the audit's T-1469 for PA-12 is now [[T-1474]].** T-1469 was free at `8c6d218e`
and was taken on main afterwards, by `8a597abf`, for the iOS fresh-context split out of [[T-3109]] —
a different subject entirely. `ledger-view.sh show T-1469` returns that entry; `show T-1474` returned
`LEDGER-VIEW-NO-SUCH-ID`, so T-1474 was free and PA-12 took it. The other six ids the audit proposed
(T-1467, T-1468, T-1470, T-1471, T-1472, T-1473) were each re-checked at landing and were still free.
There is a small irony worth recording rather than smoothing over: the ticket that took PA-12's id is
the same ticket PA-26's surviving half belongs to.

## Surface inventory

Each numbered entry is counted once. Direction names the platform with the extra capability/information, or `both-differ-from-each-other` for a divergent policy. A Mac-only refresh path does not imply Mac has more records in every runtime situation. Confirmation scenarios are **next-pass work, not checks performed**.

### Today, Inbox, task lists and task rows

#### PA-01 — Mac rows omit the notes preview

**KIND:** INFORMATION · **INTENT:** UNKNOWN · **DIRECTION:** iOS-only

The same task with nonempty notes shows a text excerpt on iOS. MacTaskRow shows the notes indicator but no excerpt. This is the motivating gap; the glyph is not redundant on Mac. Scope is the common row, including Today, rather than every card that can display a task.

- **Mac evidence:** Cadence/macOS/Views/TasksPanelComponents.swift:65 (complete row body through 195); :105 (indicator). Today reaches the interactive row at Cadence/macOS/Views/TasksPanelSectionViews.swift:171.
- **iOS evidence:** Cadence/iOS/iOSTaskViews.swift:256 (preview), :341 (plain-text extraction); Today caller Cadence/iOS/iOSTodayTaskSections.swift:433.
- **Intent evidence:** Cadence/Shared/CadenceTaskPresentationSupport.swift:61 acknowledges the absence but supplies no product decision to withhold note content. An explanation of unused metrics is not approval of the information gap.
- **Test coverage:** CadenceTaskRowIndicatorTests covers the glyph, not excerpt parity. TodayScopeParityTests covers membership/order, not row content. CadenceCodexFunctionalParityTests should gain paired content assertions; none of the seven requested suites currently detects this omission.
- **Confirm next:** Give one task a distinctive notes sentence and inspect its Today row on both platforms. Opening the inspector is the Mac workaround.
- **LANDING NOTE (2026-10-16): the owner is already on this, in [[T-3196]] rather than a new ticket — but has NOT yet decided it.** T-3196's revision asks for the row's glyphs to move beneath a notes preview and asks whether the notes glyph can then go. Its own measurement reaches the same conclusion this finding did, independently: *"The macOS row draws NO notes text at all — a grep for `task.notes` in `TasksPanelComponents.swift` returns nothing — so on macOS the glyph is the only signal that a task has notes."* It then puts three options to the owner: drop the glyph on iOS only, drop it everywhere and let macOS lose the signal, **or give the macOS row a notes preview too so both can drop it**. T-3196 records the answer as *"Not decided; nothing should be built on the notes glyph until it is."* So the third option is the one that would close PA-01, but it is an option on the table, **not a ruling**. [[T-1467]] should cross-reference T-3196 and wait on it rather than re-opening the question; whoever implements T-3196 closes PA-01 as a side effect if the owner picks that branch. The glyph stays until the replacement is real either way.

#### PA-02 — Inline subtask names and completion controls are absent from Mac rows

**KIND:** INFORMATION · **INTENT:** UNKNOWN · **DIRECTION:** iOS-only

iOS exposes listed subtasks and an overflow entry beneath an unsettled parent. Mac’s common row exposes the checklist indicator; subtask names and controls require its inspector. This is distinct from a note excerpt: it hides actionable child work.

- **Mac evidence:** Cadence/macOS/Views/TasksPanelComponents.swift:65 (no subtask list in body); Cadence/macOS/Views/SchedulePanelComponents.swift:105 (inspector counterpart).
- **iOS evidence:** Cadence/iOS/iOSTaskViews.swift:280 (subtask section), :298 (child row), :301 (overflow).
- **Intent evidence:** No comment or ticket examined establishes a decision to omit the inline Mac list.
- **Test coverage:** CadenceSharedTaskRowJobsTests and indicator tests cover shared row vocabulary, not matched subtask visibility. CadenceCodexFunctionalParityTests should check a parent with children on both surfaces; current suites cannot catch the missing renderer.
- **Confirm next:** Use an unsettled task with multiple named subtasks; compare row-level visibility and one-child completion without opening details.

#### PA-03 — Mac titles stop at one line; iOS titles can reveal more

**KIND:** INFORMATION · **INTENT:** IDIOM · **DIRECTION:** iOS-only

Mac’s row truncates a long title after one line. The normal iOS row allows two lines, and its wrapping form removes that limit. The full title remains accessible in the inspector.

- **Mac evidence:** Cadence/macOS/Views/TasksPanelComponents.swift:88.
- **iOS evidence:** Cadence/iOS/iOSTaskViews.swift:240 (title), :244 (line limit).
- **Intent evidence:** Cadence/Shared/CadenceTaskPresentationSupport.swift:50 explicitly names the single-HStack desktop exception and the growing iOS stack. This is a documented density choice, not inferred intent.
- **Test coverage:** CadenceSharedTaskRowJobsTests documents the desktop metrics exception; CadenceCodexTaskRowTypographyTests pins mobile title treatment. They cover the chosen contract, not actual truncation at every text size. Native layout checks are still required.
- **Confirm next:** Compare one long title in a narrow Mac Today pane, iPhone portrait, and iPad at larger text sizes.

#### PA-04 — Narrow Mac rows shed estimate and block-time metadata

**KIND:** INFORMATION · **INTENT:** IDIOM · **DIRECTION:** iOS-only

Mac progressively removes the block badge and then the estimate when the metadata strip does not fit; its due chip survives. iOS uses wrapping badges and keeps a positive estimate in one of two placements. The same row can therefore lose duration context only on the Mac.

- **Mac evidence:** Cadence/macOS/Views/TasksPanelComponents.swift:224 (policy), :243 (`metadataStrip`'s three `ViewThatFits` variants, was :242), :252 (conditional estimate), :262 and :396 (`taskBundleBadge`, the block badge).
- **iOS evidence:** Cadence/iOS/iOSTaskViews.swift:194 (normal estimate), :267 (wrapping estimate), :329 (wrapping badges).
- **LANDING NOTE (2026-10-16):** **the estimate half is SUPERSEDED; the block-badge half is NOT.**
  *Superseded:* [[T-3196]] is filed OPEN (decided by the owner, not started) and removes the estimate
  chip from the task row on **every** platform, putting the task's due date in that slot instead. It
  names the very lines this finding cites — `TasksPanelComponents.swift:252` and the `:224` trailing
  decoration. Re-ranking what the Mac strip sheds is therefore work against a policy the owner has
  already replaced; do not act on this half. [[T-3197]] is the Today empty-state card and is unrelated.
  *Still live:* an earlier reading of this landing held that the block badge had gone with the T-3170
  bundle retirement, on the strength of `rg -n 'blockBadge|bundleBadge' TasksPanelComponents.swift`
  returning nothing. **That grep is a false negative** — the symbol is `taskBundleBadge`, so the
  capital `B` defeats a case-sensitive `bundleBadge`. Re-run case-insensitively it matches, and the
  code is plainly there at HEAD: `metadataStrip` at :243 still sheds `showsBundle` first
  (`metadataRow(showsEstimate: true, showsBundle: true)` / `(true, false)` / `(false, false)`),
  `metadataRow` still draws `if showsBundle, let bundle = task.bundle` at :262, and
  `taskBundleBadge` is defined at :396 drawing `square.stack` plus the block's time range. The
  shedding-order half of PA-04 stands; only its estimate half is dead.
- **Intent evidence:** Mac comment at :224–241 explicitly ranks which metadata yields to preserve the title and due date (T-1432). This is an intentional desktop width tradeoff; no new bug ticket proposed.
- **Test coverage:** CadenceCodexTaskRowTypographyTests covers the two iOS estimate placements. Neither TodayScopeParityTests nor WorkHoursParityTests measures ViewThatFits choosing a variant. Native width/text-size verification is needed.
- **Confirm next:** Shrink the Mac pane around a task with estimate, due date and retained block membership; compare the same iOS row.

#### PA-05 — Secondary task actions use different entry points

**KIND:** INTERACTION · **INTENT:** UNKNOWN · **DIRECTION:** both-differ-from-each-other

Mac right-click opens the inspector, with additional hovered keyboard shortcuts. iOS long-press opens a context menu and swipe reveals actions. This is an affordance difference, not evidence that the underlying actions are unavailable.

- **Mac evidence:** Cadence/macOS/Views/TasksPanelComponents.swift:144 (tap), :146 (right-click), :203 (hovered edit registration).
- **iOS evidence:** Cadence/iOS/iOSTaskViews.swift:109 (context menu), :125 (custom swipe actions).
- **Intent evidence:** The mobile comment explains why custom swipe handling is necessary across List and ScrollView hosts. It does not establish a product decision that desktop right-click should skip a menu; classify that difference UNKNOWN.
- **Test coverage:** Current shared action/commit tests can verify outcomes but cannot detect a missing or surprising gesture. The seven parity suites do not exercise pointer/touch entry points. A paired UI scenario should cover discoverability.
- **Confirm next:** Right-click the Mac row; long-press and swipe the same iOS row. Compare available actions rather than expecting identical gestures.

#### PA-06 — Row spacing and completion targets intentionally differ

**KIND:** COSMETIC · **INTENT:** IDIOM · **DIRECTION:** both-differ-from-each-other

Desktop rows are denser; mobile rows allocate larger touch targets. The completion symbol’s point size on Mac and its surrounding touch frame on iOS are different measurements, so equating their constants would change the design rather than repair parity.

- **Mac evidence:** Cadence/macOS/Views/TasksPanelComponents.swift:65 (row composition and desktop metrics).
- **iOS evidence:** Cadence/iOS/iOSTaskViews.swift:240 (mobile typography); Cadence/Shared/CadenceTaskPresentationSupport.swift:54 (mobile target versus desktop glyph).
- **Intent evidence:** Cadence/Shared/CadenceTaskPresentationSupport.swift:4 explicitly explains pointer/finger density; :54 explains the two completion measurements.
- **Test coverage:** CadenceSharedTaskRowJobsTests covers metric consumption/exceptions; typography tests cover numeric ramps. Source tests cannot prove perceived equivalence, clipping or actual hit targets.
- **Confirm next:** Review matching screenshots and hit targets; do not file a ticket solely for differing point values.

### Task editor / inspector

#### PA-07 — iOS has a Save/Cancel draft; Mac’s inspector edits the live task

**KIND:** BEHAVIOUR · **INTENT:** LAG · **DIRECTION:** both-differ-from-each-other

iOS buffers title, priority, schedule, container and estimate in a draft until Save. Mac binds the title and container directly to the model. Closing the Mac inspector is not the same operation as cancelling the iOS draft. On iOS, tags, subtasks and status remain immediate record actions; Cancel is not a universal undo.

- **Mac evidence:** Cadence/macOS/Views/SchedulePanelPopoverSupportViews.swift:107 (title binding); Cadence/macOS/Views/SchedulePanelComponents.swift:36 (container binding).
- **iOS evidence:** Cadence/iOS/iOSTaskDetailSheet.swift:5 (contract), :230 (Save/Cancel), :244 (immediate record sections), :340 (save).
- **Intent evidence:** T-3171 records incremental shared-panel adoption. The iOS task inspector has adopted it; the Mac task inspector remains the earlier form. This is a documented migration gap, not a claim that all Mac edits currently fail persistence.
- **Test coverage:** CadenceTaskEditorPanelAdoptionTests and CadenceScheduleDraftTaskEditingTests in CadenceTests/CadenceScheduleDraftTests.swift cover the new draft. CadenceEditorSaveCommitSurfaceTests covers refusal/undo paths, not identical editor transaction boundaries. A paired edit/cancel contract needs an explicit product decision.
- **Confirm next:** Change title and schedule, then Cancel on iOS versus close on Mac; separately add a tag on iOS and Cancel to demonstrate the documented immediate-action exception.

### Calendar day/week timeline

#### PA-08 — Existing task blocks support direct move/resize on Mac; iOS routes time edits through the inspector

**KIND:** INTERACTION · **INTENT:** UNKNOWN · **DIRECTION:** macOS-only

Mac task blocks provide drag payloads and start/end resize handles. The current iOS block is a button opening task details, with no reschedule drop target. This applies to existing task blocks; iOS draft creation has its own drag gesture.

- **Mac evidence:** Cadence/macOS/Views/TimelineTaskBlock.swift:104 (drag), :115 (resize overlays), :121 (drop-through rescheduling).
- **iOS evidence:** Cadence/iOS/iOSCalendarTimelineViews.swift:1469 (explicit no-drag/no-drop contract), :1478 (inspector action).
- **Intent evidence:** T-3170’s retirement comment explains removal of bundle-forming drag. It does not establish that lack of mobile rescheduling/resize is the desired permanent interaction. UNKNOWN rather than assuming a phone cannot support it.
- **Test coverage:** WorkHoursParityTests covers time geometry and clipping, not gestures. Current seven suites cannot catch an absent resize affordance. A native day/week move-and-resize scenario should cover Mac, touch iPad and pointer iPad separately.
- **Confirm next:** Attempt to move and resize an existing task in day and week views, then verify the iOS inspector can express the same stored time.

#### PA-09 — Canvas creation uses different gesture grids

**KIND:** INTERACTION · **INTENT:** IDIOM · **DIRECTION:** both-differ-from-each-other

Mac pointer creation snaps on a five-minute grid. iOS canvas placement/draft-edge movement uses fifteen minutes. This is a canvas input difference: current shared panel rollers use the finer pointer grid, so it would be wrong to say all iOS time editing is limited to quarter hours.

- **Mac evidence:** Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift:26 (pointer drag and snapped minutes).
- **iOS evidence:** Cadence/iOS/iOSCalendarTimelineViews.swift:1037 (press/drag creation), :1051 (touch-grid edge); shared constants Cadence/Shared/CadenceScheduleSupport.swift:47.
- **Intent evidence:** Cadence/Shared/CadenceScheduleSupport.swift:26 documents pointer precision versus touch targeting (T-1293), including the iPad-trackpad limitation at :43. Its older “iOS never drags” prose predates current draft dragging; the constants and callers, not that stale sentence, establish current behavior. Cadence/Shared/CadenceScheduleDraft.swift:485 defines rollerGridMinutes separately.
- **Test coverage:** WorkHoursParityTests should cover numeric grid contracts alongside scheduling tests; it cannot validate touch precision. Existing source/geometry checks are not proof of interaction parity.
- **Confirm next:** Create around a five-minute boundary by Mac drag and iOS press/drag; compare stored starts and panel roller adjustment.

### Calendar month grid

#### PA-10 — iOS event chips omit the event time

**KIND:** INFORMATION · **INTENT:** UNKNOWN · **DIRECTION:** macOS-only

Mac month event chips can show a formatted time alongside the title. iOS month chips pass only title, icon and color; a clock icon distinguishes timed events but does not say when they occur.

- **Mac evidence:** Cadence/macOS/Views/CalendarPageMonthSupportViews.swift:244 (`chipTimeLabel`, was :242), :436 (`MonthEventChip` in the month-cell renderer, was :433); `MonthEventChip` itself at :229.
- **iOS evidence:** Cadence/iOS/iOSCalendarMonthViews.swift:411, :418, :426 (the three `iOSCalendarMiniChip` call sites, was :417), :545 (mini-chip type, unmoved). No time field/label counterpart in this renderer.
- **LANDING NOTE (2026-10-16):** re-pinned; both files changed since the base but the finding is unaffected. `iOSCalendarMiniChip` still takes `title`, `icon`, `color` and `isEvent` and has no time parameter, so the gap is structural rather than a call site forgetting to pass one.
- **Intent evidence:** No examined comment or ticket establishes that mobile month cells should withhold event times.
- **Test coverage:** CalendarAllDayAndDoneTaskParityTests checks inclusion/order, not the information in a chip. CadenceCalendarChipTreatmentTests checks treatment. CadenceCodexFunctionalParityTests should assert timed-event information in both month renderers; current suites cannot catch this gap.
- **Confirm next:** Place a timed event and an all-day event with similar titles on one date. Compare visible time information without opening either.

#### PA-11 — The number of visible month chips is height-derived on Mac and fixed on iOS

**KIND:** INFORMATION · **INTENT:** IDIOM · **DIRECTION:** both-differ-from-each-other

Mac derives capacity from the cell height; iOS allocates five slots. Both use shared priority ordering and expose overflow, so this is different information density rather than lost records.

- **Mac evidence:** Cadence/macOS/Views/CalendarPageMonthSupportViews.swift:401 (`CadenceCalendarMonthCellPriority.split`, was :390), :405 (`capacity: layout.visible`); Cadence/macOS/Views/CalendarPageMonthGridSupport.swift:190 (layout).
- **iOS evidence:** Cadence/iOS/iOSCalendarMonthViews.swift:315 (`chipCapacity = 5`, was :312), :322 (the same shared `split`, was :321), :432 (overflow).
- **LANDING NOTE (2026-10-16): partly repaired since the base, and the surviving difference is narrower than written.** Both month cells now call the **same** `CadenceCalendarMonthCellPriority.split(bundles:events:tasks:capacity:)`; the Mac comment at :400 says so outright — *"both platforms now ask the same function"* — and the iOS comment at :317 records that the shared call replaced three hardcoded per-kind caps *"that macOS had drifted the other way from."* What still differs is **only the `capacity:` argument**: `layout.visible` on Mac, the fixed `5` on iOS. Ordering is no longer a divergence. The IDIOM classification is if anything better supported now, and the finding stays uncounted as a defect.
- **Intent evidence:** The iOS comment at :312 explicitly explains that minHeight supplies no fixed row budget to divide. The rendering choice is documented.
- **Test coverage:** CalendarAllDayAndDoneTaskParityTests covers shared prioritization, not actual available height or clipping. Native month-layout tests should cover small windows, iPhone and iPad; no defect ticket for the numeric difference alone.
- **Confirm next:** Fill a day with more than five items and resize the Mac month grid; confirm overflow remains discoverable on both.

### Calendar all-day lane

#### PA-12 — Mac puts untimed tasks before all-day events; iOS gives events the limited slots first

**KIND:** INFORMATION · **INTENT:** UNKNOWN · **DIRECTION:** both-differ-from-each-other

Mac’s fixed-height all-day band scrolls through tasks first and then events. iOS’s header gives its two preview rows to events before untimed tasks and shows +N more behind a day-opening button. Crowding can hide appointments first on Mac and tasks first on iOS.

- **Mac evidence:** Cadence/macOS/Views/CalendarPageMonthSupportViews.swift:531 (`allDayBannerContent`, the scrolling band, was :527), :534 (`ForEach(unscheduledTasks)` — tasks first, was :530), :537 (`ForEach(allDayEventItems)` — events second, was :533).
- **iOS evidence:** Cadence/iOS/iOSCalendarTimelineViews.swift:720 (the `split` property, was :711), :721 (`CadenceCalendarAllDayBandPriority.split`), :759 (`allDayEvents.prefix(split.events)` — events first, was :751), :772 (`unscheduledTasks.prefix(split.tasks)` — tasks second, was :760).
- **LANDING NOTE (2026-10-16): live, re-pinned, and the shared helper can now be named.** The opposing order is intact at HEAD and the contrast is cleaner than the audit could state it: iOS routes the band through **`CadenceCalendarAllDayBandPriority`**, declared in `Cadence/Shared/CadenceCalendarMonthCellPriority.swift`, whose comment at `iOSCalendarTimelineViews.swift:697` describes it as giving events *"slots ahead of the unscheduled tasks ... (the month cell's events-before-tasks rule)"*. `rg -n 'CadenceCalendarAllDayBandPriority' --type swift -l` returns three files: the Shared declaration, the iOS band, and `CalendarAllDayAndDoneTaskParityTests`. **The Mac band is not among them** — it hardcodes tasks-then-events in a `VStack` with no priority type and no cap at all. So this is not merely two orders; it is a shared decision helper with exactly one product consumer, which is the same shape as PA-13. **This finding's ticket is [[T-1474]], not T-1469 — see the landing corrections above.**
- **Intent evidence:** The mobile priority is explicit, but no examined comment justifies the opposing desktop ordering. This entry concerns priority/access to hidden items, not identical row heights.
- **Test coverage:** CalendarAllDayAndDoneTaskParityTests:121 covers the mobile event-first split and :149 its renderer. It does not assert Mac band ordering or exercise scrolling. Extend it with the paired capacity/order policy; native overflow access remains unchecked.
- **Confirm next:** Use at least three untimed tasks and two all-day events on one day; check which facts are initially hidden and how each platform reveals them.

### Calendar board

#### PA-13 — iOS day drops can claim success after a failed save

**KIND:** DATA · **INTENT:** LAG · **DIRECTION:** both-differ-from-each-other

The iOS day-column callback returns Void; handleDrop returns true after calling it. The shared task helper mutates date, estimate and bundle-membership fields and swallows the save failure. Mac returns applied/refused, restores affected fields and sibling state on refusal, and presents a failure notice. A refused mobile save can leave pending in-memory changes available to a later unrelated save; no actual data loss was induced in this audit.

- **Mac evidence:** Cadence/macOS/Views/CalendarPageBoardSupportViews.swift:226 (`CalendarPageBoardDropSupport.schedule`, the transaction), :243 (`CadenceTaskFieldEditCommit.commit`), :634 (`handleDayColumnDrop`, was :664), :643 (sets `dropFailureNotice`), :644 (`return outcome == .applied`); Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift:22 (`let onDropTaskOnDay: (AppTask) -> Bool`, was :217), :204 (`handleDrop`), :208 (`return onDropTaskOnDay(task)` — forwards the answer).
- **iOS evidence:** Cadence/iOS/iOSCalendarBoardView.swift:256 (`let onDropTaskOnDay: (AppTask) -> Void`, was :243), :115 (the closure), :227 (`schedule`, which calls `CadenceTaskDateEditing.moveTaskToDate`), :462 (`handleDrop`), :466 (calls the callback), :467 (`return true`, unconditional — was cited as :551, which is past the end of a 485-line file); Cadence/Shared/CadenceTaskDateEditing.swift:117 (the Void wrapper), :122 (delegates), :123 (reconciles); Cadence/Shared/CadenceTaskMutationSupport.swift:270 (mutations, bare `try? modelContext.save()` at :278).
- **LANDING NOTE (2026-10-16): live — this remains the top finding, and one citation was dropped as stale.** *Dropped:* `iOSCalendarBoardView.swift:252 (swallowed bundle move)`. `rg -n 'bundle|Bundle' Cadence/iOS/iOSCalendarBoardView.swift` returns **nothing** at HEAD; T-3170 retired the Block card and the file's own comment at :458 now reads *"No nested drop target to arbitrate any more ([[T-3170]])... Neither card exists."* There is no second swallowed bundle move in the board view. **But the clause about bundle fields was NOT dropped, because the shared helper still does it:** `CadenceTaskMutationSupport.moveTaskToDate` at :270 still filters the task out of `task.bundle?.tasks` (:271), nils `task.bundle` (:272) and zeroes `bundleOrder` (:273) before the bare `try? modelContext.save()` at :278. That is a **relationship write** under a swallowed save — the *existence* half of the `try? save()` rule in AGENTS.md, not merely an in-place field edit — so the helper breaks the rule on its own terms, independent of the caller. *Confirmed at HEAD:* the two platforms declare **identically-named callbacks with different return types** — Mac `(AppTask) -> Bool` forwarded at `:208`, iOS `(AppTask) -> Void` followed by a hardcoded `return true` at `:467`. The Mac side proves the shape is reachable: `handleDayColumnDrop` maps `.refused` onto `dropFailureNotice` and returns `outcome == .applied`. The iOS side cannot refuse because nothing in its chain returns a value to refuse with. **Nothing here was taken on the audit's word; every line above was read at the landing HEAD.**
- **Intent evidence:** T-1980 and the Mac helper comment at :211 record the repair to precisely this cross-frame false-success shape. The iOS callbacks still have the earlier shape: LAG. The iOS comment claiming that nothing reports success is contradicted by its caller.
- **Test coverage:** CalendarBoardDayDropCommitTests:123 and :531 cover Mac rollback and result forwarding. CadenceEditorSaveCommitSurfaceTests covers shared commit contracts but not this mobile callback chain. Port refusal injection plus second-context checks to the mobile-used helper, and assert caller answer propagation; current Mac-only coverage cannot catch it.
- **Confirm next:** In a disposable test store, inject a throwing commit for task and bundle day drops; assert false/refused, unchanged persisted and in-memory fields, and a visible notice. Do not test by damaging the owner’s store.

### Calendar board / notification scheduling

#### PA-14 — Successful Mac board date moves skip the immediate notification reconcile used by iOS

**KIND:** BEHAVIOUR · **INTENT:** UNKNOWN · **DIRECTION:** iOS-only

iOS task-day movement calls CadenceTaskDateEditing, which requests reconciliation immediately. Mac day movement applies fields inside CadenceTaskFieldEditCommit; its successful path returns without running the reconciler. The Mac scene-phase checkpoint eventually reconciles, but a frontmost board edit has no equivalent immediate call. OS delivery impact is inferred, not measured.

- **Mac evidence:** Cadence/macOS/Views/CalendarPageBoardSupportViews.swift:243 (commit), :253 (`CalendarBoardPlannerSupport.apply`, direct apply); Cadence/Shared/CadenceTaskFieldEditCommit.swift:262 (`return true`, the successful return, with no reconcile between it and the commit — was :255, which is now the `commitEdit` call itself); Cadence/macOS/macOSRootView.swift:355 (later scene checkpoint, was :340).
- **iOS evidence:** Cadence/iOS/iOSCalendarBoardView.swift:227 (`schedule`, was :244) calls Cadence/Shared/CadenceTaskDateEditing.swift:117, whose :123 requests reconciliation (was :124).
- **LANDING NOTE (2026-10-16):** live, re-pinned. `CadenceTaskDateEditing`'s header states the split this finding depends on — *"shared helper mutates, app-side wrapper reconciles"* — and every function in it is *"one line plus one reconcile."* The Mac board bypasses that wrapper for `CalendarBoardPlannerSupport.apply` inside `CadenceTaskFieldEditCommit`, which is why its success path reaches no reconciler. The asymmetry is in the caller, not in the shared code.
- **Intent evidence:** T-362 already inventories missing date/time reconciliation; T-1980’s ledger description explicitly leaves the success-path reconcile outstanding. Neither establishes a desired platform difference, so UNKNOWN. Do not label a broad historical ticket closed/open solely from this subcase.
- **Test coverage:** CalendarBoardDayDropCommitTests covers persistence/refusal. CadenceEditorSaveCommitSurfaceTests:683 covers refused date edits, not a paired successful board-notification contract. Add an injected-reconciler assertion and notification-plan check; device permission/delivery still requires runtime verification.
- **Confirm next:** After a successful board day move, count reconciler calls and compare the requested notification plan before any scene transition. Verify delivery separately with authorized notifications.

### Notes and markdown editor

#### PA-15 — Only the Mac note editor exposes a heading outline

**KIND:** INFORMATION · **INTENT:** UNKNOWN · **DIRECTION:** macOS-only

Mac derives an outline and offers a heading jump list when headings exist. No outline renderer or action was found in the reviewed iOS note host, header, editing surface or format toolbar. Headings still render on iOS; the missing information is the document overview/jump list.

- **Mac evidence:** Cadence/macOS/Views/NoteEditorPane.swift:229 (button), :439 (parser); Cadence/macOS/Views/NoteEditorAccessoryViews.swift:29 (jump list).
- **iOS evidence:** No counterpart in Cadence/iOS/iOSNotesView.swift:775 (editor host), Cadence/iOS/iOSNoteEditorSheetHeader.swift:29, or Cadence/iOS/iOSMarkdownEditingSurface.swift:147 (toolbar/editor composition through :244). An outline action would live in that host/header or toolbar.
- **Intent evidence:** Mac accessory comments explain moving the outline out of a permanent panel, not omitting it on iOS. No explicit platform decision found.
- **Test coverage:** CadenceOutlineParserRegexTests tests parsing, not feature reachability. CadenceCodexFunctionalParityTests should cover a reachable outline on both platforms if parity is adopted. None of the seven requested suites currently detects the missing mobile control.
- **Confirm next:** Open a long note with multiple heading levels and attempt to list/jump to a named heading on each platform.

#### PA-16 — Only the Mac note editor surfaces unlinked mentions

**KIND:** INFORMATION · **INTENT:** UNKNOWN · **DIRECTION:** macOS-only

Mac resolves loose title mentions and offers a footer action to turn one into a link. iOS shows actual linked notes/tasks/backlinks, but no unlinked-mention footer/action was found in the checked editing surface. Existing backlinks are not a substitute for discovering unlinked references.

- **Mac evidence:** Cadence/macOS/Views/NoteEditorPane.swift:316 (footer), :434 (resolver), :686 (link action); Cadence/macOS/Views/NoteEditorAccessoryViews.swift:192.
- **iOS evidence:** No counterpart in Cadence/iOS/iOSMarkdownEditingSurface.swift:147 (full composition through :244) or Cadence/iOS/iOSNotesView.swift:775 (host). Discovery/link action would belong beside the existing reference panel at :157.
- **Intent evidence:** No examined ticket/comment states that unlinked-mention discovery is deliberately Mac-only.
- **Test coverage:** NoteReferenceSupportTests and CadenceNoteReferencePanelSurfaceTests cover actual reference resolution. They do not require an unlinked-mention affordance on iOS. CadenceCodexFunctionalParityTests should cover the missing surface; current seven suites cannot detect it.
- **Confirm next:** Create a note whose plain body mentions another note’s title without link syntax; compare discovery and conversion to a link.

#### PA-17 — iOS hides reference information while the editor has focus

**KIND:** INFORMATION · **INTENT:** IDIOM · **DIRECTION:** macOS-only

Linked-note/task/backlink strips remain above the Mac editor while typing. iOS hides its reference panel while focused to preserve editing room. References have not disappeared from the note; they return when focus leaves.

- **Mac evidence:** Cadence/macOS/Views/NoteEditorPane.swift:255 (content-only visibility gate).
- **iOS evidence:** Cadence/iOS/iOSMarkdownEditingSurface.swift:151 (rationale), :156 (focus gate).
- **Intent evidence:** The iOS comment explicitly prioritizes typing affordances over navigation strips when the keyboard occupies the screen. This is a documented space tradeoff.
- **Test coverage:** CadenceNoteReferencePanelSurfaceTests covers shared contents and the mobile panel. Rendering under keyboard/focus changes is not proven by the seven requested suites; native focus/keyboard scenarios should verify the deliberate policy.
- **Confirm next:** Open a note with backlinks, focus its body, then dismiss the keyboard; compare information visibility and restored panel access.

#### PA-18 — Embedded task fields open different editing surfaces

**KIND:** INTERACTION · **INTENT:** UNKNOWN · **DIRECTION:** both-differ-from-each-other

Mac embedded-task edits can open a field-specific popover. The iOS editing surface opens the full task inspector for an embedded task. Completion/subtask toggles exist separately on iOS, so this is not a claim that embedded tasks are read-only there.

- **Mac evidence:** Cadence/macOS/Views/NoteEditorPane.swift:294 (TaskEmbedFieldEditorPopover and initial field).
- **iOS evidence:** Cadence/iOS/iOSMarkdownEditingSurface.swift:115 (full inspector sheet), :225 (completion), :228 (subtask toggle), :232 (open task).
- **Intent evidence:** No examined comment establishes whether mobile field-specific editing is intentionally omitted or pending.
- **Test coverage:** CadenceEditorSaveCommitSurfaceTests covers refused edits and embedded refresh ordering, not matching presentation scope. Existing unit/source suites cannot validate gesture-to-field focus; a native embedded-task editing scenario is needed.
- **Confirm next:** Edit a due date or estimate from an embedded task on both platforms; verify stored outcome and the number of navigation steps.

### Search

#### PA-19 — Mac search silently discards results beyond its caps; iOS offers continuation

**KIND:** INFORMATION · **INTENT:** UNKNOWN · **DIRECTION:** iOS-only

Mac builds already-truncated arrays: matching tasks stop at 14, events at 12, and ordinary notes at 12 (smaller idle caps). No continuation is wired in the checked global-search presentation. iOS caps the visible prefix but keeps the full result array and offers expansion. A matching record below the Mac cutoff is inaccessible through that query even though iOS can reveal it.

- **Mac evidence:** Cadence/macOS/Views/GlobalSearchIndexSupport.swift:186 (tasks), :220 (events), :313 (notes); Cadence/macOS/Views/GlobalSearchView.swift:47 passes those sections to the presentation; Cadence/macOS/Views/GlobalSearchOverlayShellViews.swift:23 renders only the supplied results, with no continuation.
- **iOS evidence:** Cadence/iOS/iOSSearchView.swift:511 (visible cap), :519 (prefix), :535 (continuation).
- **Intent evidence:** No examined comment/ticket justifies silent omission on Mac. The mobile comments explicitly distinguish a bounded list from a silent cutoff; that alone does not prove historical cause on Mac.
- **Test coverage:** CadenceSearchResultCapTests:77 guards mobile use only. CadenceCodexFunctionalParityTests:129 actually pins the Mac note cap/ranking, so green tests would preserve this gap. Extend tests to require a count/continuation or explicit narrowing affordance before changing the cap.
- **Confirm next:** Create more than 14 uniquely identifiable tasks matching one phrase and more than 12 notes; compare the ability to reach the last match without changing the query.
- **LANDING NOTE (2026-10-16): the owner has already ruled on the shape of the fix, so do not re-litigate it on [[T-1473]].** The decision, relayed by the owner through the landing coordinator: **show the remaining match count, and give the list a "show all" affordance.** That settles the two questions this finding deliberately left open — whether to raise the caps (no; bounded initial rendering stays) and whether a count alone is enough (no; the remainder must be reachable). It is recorded on T-1473 so the ticket carries it. **Provenance, stated plainly:** this decision reached the landing from the owner via the coordinator's instruction and is **not** in `docs/TODO.md` at the time of writing — searching the ledger for a "show all" or search-cap ruling returns nothing relevant. T-1473, filed by this landing, is its first written home. If an implementer finds it conflicts with a later owner instruction, the owner's later word wins.

#### PA-20 — Mac global search excludes list documents

**KIND:** INFORMATION · **INTENT:** BLOCKED · **DIRECTION:** iOS-only

Mac’s ordinary note search excludes .list documents; iOS searches nonblank notes without that kind exclusion. Mac Daily, Weekly, Notepad and Event Notes support is present and is not reopened here.

- **Mac evidence:** Cadence/macOS/Views/GlobalSearchIndexSupport.swift:295 (candidate gate), :303 (.list rejected).
- **iOS evidence:** Cadence/iOS/iOSSearchView.swift:213 (all nonblank note candidates), :225 (content matching).
- **Intent evidence:** T-3084 explicitly leaves list-document routing awaiting an additional-scope decision. BLOCKED is recorded, not inferred from absence.
- **Test coverage:** CadenceCodexFunctionalParityTests:107 covers the four supported global note kinds but excludes list documents from its contract. Extend it with list-document discovery and correct list routing once scope is resolved. Current coverage cannot flag the intentionally unfinished fifth kind.
- **Confirm next:** Search a unique phrase appearing only in a list document; verify iOS discovery and the absent Mac result, then verify intended destination before implementing.

#### PA-21 — Completed tasks are searchable by default on Mac but opt-in on iOS

**KIND:** BEHAVIOUR · **INTENT:** UNKNOWN · **DIRECTION:** both-differ-from-each-other

Mac global task search includes completed tasks. iOS defaults its include-completed setting to false and offers a toggle. Identical queries can therefore return different sets before the user changes scope.

- **Mac evidence:** Cadence/macOS/Views/GlobalSearchIndexSupport.swift:161 (includingCompleted: true).
- **iOS evidence:** Cadence/iOS/iOSSearchView.swift:29 (false default), :57 (filter), :313 (control).
- **Intent evidence:** No examined comment/ticket establishes different default search scopes as a product decision. Not automatically a bug: an owner decision is needed before aligning it.
- **Test coverage:** Shared search/filter tests can verify either polarity but do not assert a cross-platform default. CadenceCodexFunctionalParityTests should cover the chosen default contract and visible scope indication; no bug ticket proposed without that decision.
- **Confirm next:** Complete one otherwise uniquely searchable task; compare a fresh search before and after enabling completed results on iOS.

### Settings / archive import and export

#### PA-22 — Only Mac Settings exposes local backup creation and staged restore

**KIND:** BEHAVIOUR · **INTENT:** UNKNOWN · **DIRECTION:** macOS-only

Mac Settings offers local backup creation, cleanup and staged restore. iOS provides archive import/export and reset but no counterpart to the local backup list/restore controls. Archive import is available on both and is not equivalent to selecting a store backup.

- **Mac evidence:** Cadence/macOS/Views/SettingsDataSafetySection.swift:354 (create), :367 (cleanup), :388 (stage restore).
- **iOS evidence:** Cadence/iOS/iOSArchiveImportSettingsSection.swift:9 explicitly states no backup list/staged restore; Cadence/iOS/iOSSettingsView.swift:286 (data-safety section). Missing controls would live here.
- **Intent evidence:** The iOS import comment acknowledges the limitation but gives no decision or plan for equivalent local recovery controls. UNKNOWN, not a claim of missing automatic backup execution.
- **Test coverage:** CadenceArchiveImportSurfaceTests and CadenceArchiveImportEntryPointTests cover import. They cannot assert recovery controls that are absent. A product recovery-policy decision and disposable-store runtime restore checks are needed; no generic “iOS restore broken” ticket filed.
- **Confirm next:** Compare Settings recovery actions. Never stage a restore of the owner’s live store merely to verify this inventory.

### Focus

#### PA-23 — Leaving Focus has different session lifetime semantics

**KIND:** BEHAVIOUR · **INTENT:** LAG · **DIRECTION:** both-differ-from-each-other

Mac’s app-owned FocusManager keeps its wall-clock session running when the Focus view goes away. iOS ends/banks its view-owned session on a genuine pop or sidebar change. Switching compact tabs is explicitly different: visited tabs stay alive, so that switch does not necessarily end the session. Wider/narrower shell changes remain an important mobile risk.

- **Mac evidence:** Cadence/macOS/Views/FocusView.swift:14 (navigation-independent clock), :35 (resume display); Cadence/macOS/Services/FocusManager.swift:151 (explicit end-session action).
- **iOS evidence:** Cadence/iOS/iOSFocusView.swift:108 (lifetime contract), :119 (endSession on disappear); Cadence/iOS/iOSCompactTabShell.swift:45 (the kept-alive comment, unmoved despite the file changing), :71 (`visitedTabs`, the state behind it).
- **LANDING NOTE (2026-10-16):** `iOSCompactTabShell.swift` changed since the base, so its citation was re-checked: the comment at :45 still reads *"The tabs are kept alive once visited"* and `@State private var visitedTabs` backs it at :71. `iOSFocusView.swift` and the two Mac files did not change, so their line numbers are the audit's own. Finding unaffected.
- **Intent evidence:** T-168 explicitly records that shared session persistence across mobile shell swaps remains unwritten. Mac T-1103 already moved timing ownership out of the view. LAG; the historical project-membership stop is evidence of unfinished work, not proof the present fence still blocks every solution.
- **Test coverage:** CrossPlatformParityTests:217 and :231 cover time roll-up, not ownership/lifetime. CadenceFocusSessionAndBlockCommitTests covers commits. Current suites cannot catch navigation teardown or size-class state loss; native navigation and shell-swap scenarios are required.
- **Confirm next:** Start a session, visit Notes and return on Mac, iPad sidebar and iPhone compact tabs; then resize an iPad shell. Verify elapsed and logged minutes without assuming every navigation path tears down the view.

### Capture and create flows

#### PA-24 — Mac can open quick capture while another application is active

**KIND:** INTERACTION · **INTENT:** UNKNOWN · **DIRECTION:** macOS-only

Mac’s global shortcut chooses an in-app composer when Cadence is active and a separate quick panel otherwise. The reviewed iOS capture buttons live inside the app. This does not claim iOS has no Siri/App Intent capture; those are separate entry points.

- **Mac evidence:** Cadence/macOS/Services/GlobalHotkeyManager.swift:105 (active/inactive routing), :123 (external panel); Cadence/macOS/Services/QuickTaskPanelController.swift:38 (composer).
- **iOS evidence:** No global-hotkey panel counterpart in Cadence/iOS/iOSCompactTabShell.swift:75 (capture state) or Cadence/iOS/iOSCaptureRadialMenu.swift:349 (gesture). An in-app capture host is the mobile counterpart, not an OS-global panel.
- **Intent evidence:** The branch proves the affordance but the examined comments do not explicitly designate it as a deliberate permanent platform exclusion. UNKNOWN avoids treating OS conventions as a product decision.
- **Test coverage:** CadenceCapturePaletteTests covers palette routing; CadenceEditorSaveCommitSurfaceTests covers create commit boundaries. Neither catches an external-app shortcut. Native foreground/global-shortcut checks are required.
- **Confirm next:** With a different Mac app frontmost, invoke Control-Space and create in a disposable fixture. On iOS test in-app tap/hold capture separately from Siri intent capture.

### Navigation chrome

#### PA-25 — Compact iOS preserves a stack per tab; desktop uses sidebar selection

**KIND:** INTERACTION · **INTENT:** IDIOM · **DIRECTION:** both-differ-from-each-other

Compact iOS presents Tasks, Calendar, Notes and More around a central capture control, preserving each visited tab’s navigation stack. Mac exposes sidebar navigation. Regular-width iOS uses its sidebar and bridges selection when width changes. This is a documented navigation model, not a missing-screen count.

- **Mac evidence:** Cadence/macOS/Views/SidebarView.swift:1 (sidebar); Cadence/macOS/Views/macOSRootShellViews.swift:38 (shell renders sidebar).
- **iOS evidence:** Cadence/iOS/iOSCompactTabShell.swift:11 (four paths), :37 (tab/capture design), :45 (preservation); Cadence/iOS/iOSRootView.swift:168 (width bridge).
- **Intent evidence:** The mobile shell comment at :37 explains replacing the home-grid with persistent tabs and independent history. The width-bridge comment at iOSRootView.swift:168 explains continuity across layout changes.
- **Test coverage:** CadenceCompactShellSupportTests covers routing models; CrossPlatformParityTests does not exercise stack preservation. Native size-class, back-navigation and pending-editor tests remain necessary.
- **Confirm next:** Navigate into a list, switch tabs and back, then resize an iPad to regular width. Compare destination continuity rather than insisting on identical chrome.

### Widgets / external writes / notification scheduling / MCP

#### PA-26 — iOS does not adopt external writes through the fresh-context path used by Mac

**KIND:** DATA · **INTENT:** BLOCKED · **DIRECTION:** macOS-only

Mac can replace the active context after external-write notification and then reconcile from it. iOS’s scene callback reconciles from the root’s existing @Query objects without that replacement/adoption path. A widget completion or capture can therefore leave mobile UI and reminder state stale. This is a local cross-process adoption gap, not proof of a CloudKit transport failure or universal lost writes.

- **Mac evidence:** Cadence/macOS/macOSRootView.swift:265 (`activeModelContext = CadenceModelContextRefresh.replacement(for:)`, was :263), :50 (the doc explaining the wholesale replacement); Cadence/macOS/Views/macOSRootDataRefreshSupport.swift:35.
- **iOS evidence:** Cadence/iOS/iOSRootView.swift:181 (scene checkpoint, was :184), :186–:195 (**new since the base**: a fresh `CadenceForegroundNotificationSnapshot(container:)` read, then reconcile), :200–:202 (the comment stating the UI context is deliberately not replaced), :203 (the leaving-active reconcile off the existing `@Query`). No replacement-context counterpart in this root.
- **LANDING NOTE (2026-10-16): HALF REPAIRED since the base — the remainder belongs to [[T-1469]].** `7343bfe8` landed the notification half of [[T-3109]] on iOS: on `.active`, `iOSRootView` now builds a **fresh** `CadenceForegroundNotificationSnapshot` from the container and reconciles from that, instead of reading the root's possibly-stale `@Query`. So the *"a widget completion can leave the reminder plan stale"* arm of PA-26 is **fixed**, and the audit's evidence for it no longer describes HEAD. **The UI-adoption arm is untouched and is now documented as deliberate-for-now in the source itself**, at `iOSRootView.swift:200–202`: *"This fixes notification input only; it deliberately does not replace the UI context."* That remaining arm is exactly T-1469, which is BLOCKED pending a state-preserving design — its entry measures 18 iOS files holding SwiftData objects in `@State` that a context swap would strand. **PA-26 should therefore no longer be read as one finding:** its notification half is closed, and what is left is a known blocked ticket rather than an unfiled gap. The T-3109 addendum filed by this landing says so rather than repeating the audit's base-pinned claim. One consequence for the summary above: PA-26 ranked #2 overstates what is still open.
- **Intent evidence:** T-3109 explicitly records OPEN/BLOCKED ON THE CODEX LEASE and names the root/app entry points and rejected workarounds. This audit adds evidence, not a duplicate ticket or an attempted workaround.
- **Test coverage:** CadenceEventKitPlatformParityTests concerns EventKit, not SwiftData cross-process adoption. CrossPlatformParityTests widget date checks do not cover stale registered objects. A two-context test and native extension-to-app scenario should cover fresh reads, held inspectors and notification plans. Current seven suites cannot catch the whole lifecycle.
- **Confirm next:** Using an isolated store, hold a task in app context A, complete it through context B/intent, foreground the app, and inspect UI plus pending reminder plan. Repeat capture and deletion without restarting the app.

## Checked areas without an additional confirmed difference

These are bounded conclusions about the named paths, not assertions that entire directories are equivalent. A common helper is evidence of shared decisions, not proof of equal rendering or integration.

| Surface | Paired source inspected / traced | Conclusion within this pass |
|---|---|---|
| Today membership | `Cadence/macOS/Views/TasksPanel.swift:164`; `Cadence/iOS/iOSTodayTaskSections.swift:433`; `CadenceTests/TodayScopeParityTests.swift:43` | Past-do inclusion, due/do de-duplication, rank and widget scope have explicit shared tests. No new membership divergence established. Row information differences are PA-01–06. |
| Inbox / All Tasks | `Cadence/macOS/Views/TasksListView.swift:87`, `:179`; `Cadence/iOS/iOSInboxView.swift:1`; `Cadence/iOS/iOSInboxRemindersSection.swift:19` | The scoped collection and Reminders strip use shared policy. Do not repeat the obsolete claim that iOS has no Inbox Reminders. This does not certify every grouping/reorder permutation. |
| Day/week geometry | `Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift:26`; `Cadence/iOS/iOSCalendarTimelineViews.swift:1006`; `CadenceTests/WorkHoursParityTests.swift:16` | Shared work-hour metrics have coverage. PA-08/09 concern input, which that math suite does not prove. |
| Month inclusion | `Cadence/macOS/Views/CalendarPageMonthSupportViews.swift:390`; `Cadence/iOS/iOSCalendarMonthViews.swift:321` | Both consult shared month priority. The earlier month event/task-order fork is repaired; PA-10/11 remain. |
| Note export | `Cadence/iOS/iOSNoteExportMenu.swift:67`; `Cadence/iOS/iOSNoteExportService.swift:39`; `CadenceTests/NoteExportSurfaceTests.swift:1` | Mobile Markdown/PDF export exists. Common export-content support is present; native PDF rendering/font/image equivalence was not measured. |
| Settings navigation layout | `Cadence/iOS/iOSSettingsView.swift:210`; `Cadence/iOS/iOSSidebarLayoutSettingsSection.swift:1`; `Cadence/macOS/Views/SettingsView.swift:178` | iOS now exposes the synced sidebar layout. Do not refile the earlier Mac-only control gap. The Settings switch was inventoried; individual settings’ effects were not all executed. |
| Archive import | `Cadence/macOS/Views/SettingsArchiveImportCard.swift:22`; `Cadence/iOS/iOSArchiveImportSettingsSection.swift:22` | Both use `CadenceArchiveImportFlow` and shared presentation. No new merge-mode/preview difference established. Local-store backup controls remain PA-22. |
| Archive export | `Cadence/macOS/Views/SettingsDataSafetySection.swift:337`; `Cadence/iOS/iOSDataExportSettingsSection.swift:112` | Both call `PersistenceController.exportArchiveForDataSafety`. No “Mac can export, iOS cannot” finding. File-provider completion and reopened-store validity were not exercised. |
| EventKit | `Cadence/macOS/Services/CalendarManager.swift:342`, `:352`, `:425`, `:492`; `Cadence/iOS/iOSCalendarManager.swift:97`, `:130`, `:217` | Mac splits timed/all-day fetch methods; mobile returns the day’s events and its surfaces split them. Search windows agree at 60 past / 365 future days. Typed write failures and rollback have specific suite coverage. Separate method shapes alone are not findings. Cross-device event identifiers remain a device check, not a proved mismatch. |
| Reminders | `Cadence/macOS/Services/RemindersManager.swift:1`; `Cadence/Services/CadenceRemindersManager.swift:1`; `Cadence/macOS/Views/InboxSupportViews.swift:23`; `Cadence/iOS/iOSInboxRemindersSection.swift:27` | Mac’s former manager file is a tombstone pointing to the shared manager. Both Inbox rows use shared connection/completion outcomes. No new data-policy difference established; provider permissions/read-only accounts need runtime checks. |
| Notifications | `Cadence/macOS/macOSRootView.swift:340`; `Cadence/iOS/iOSRootView.swift:184`; `Cadence/Services/NotificationManager.swift:127` | Both scene directions reconcile and both use the shared manager. Specific caller gaps are PA-14 and PA-26; do not infer that the whole scheduling implementation is platform-forked. |
| Widgets | `CadenceWidgets/CadenceWidgetsBundle.swift:11`; `CadenceWidgets/TodayTasksWidget.swift:176`; `CadenceWidgets/TodayTasksWidgetView.swift:431`; `CadenceWidgets/CalendarSnapshotWidget.swift:117` | Two kinds are currently registered, Today and Calendar, with the same declared family lists. Today uses `CompleteTaskIntent`. Retired Habit/Goal kinds are not counted as missing iOS features. Host-supported families, live taps, links and refresh latency require devices. The shared source does not erase PA-26’s app-side adoption gap. |
| MCP boundary | `CadenceMCPServer/main.swift:6`, `:25`, `:48`; `CadenceMCPServer/AGENTS.md:24`; `plugins/cadence-mcp/scripts/run-cadence-mcp.sh:4`; `Cadence/macOS/macOSRootView.swift:263`; `Cadence/iOS/iOSRootView.swift:184` | A local command-line server opens the store under an explicit write gate, publishes external-write notices and uses stdio. There is no matching iOS in-app server host in the inspected mobile root. That deployment boundary is recorded here, not padded into a “different frameworks” finding. User-visible adoption is PA-26. Every MCP tool’s business semantics was not re-audited. |

## Shared helpers: one platform’s consumer does not prove the other platform’s surface

This is a **selected, per-file consumer inventory**, not a declaration that all 186 Shared files have been exhaustively audited. Each row names the actual callers inspected. Shared code may also have widget/MCP/test consumers, so “one-sided” here means the compared app surface, not that the file has exactly one reference anywhere.

| Shared file / symbol | Mac consumer | iOS consumer or missing counterpart | Result |
|---|---|---|---|
| `Cadence/Shared/CadenceTaskPresentationSupport.swift:43`, preview/secondary-line metrics | `Cadence/macOS/Views/TasksPanelComponents.swift:65` takes desktop spacing/type metrics, not preview fields | `Cadence/iOS/iOSTaskViews.swift:256`, `:341` consume the preview | Shared metrics mask the one-sided renderer: PA-01. The explicit one-line exception is PA-03, not assumed drift. |
| `Cadence/Shared/CadenceTaskFieldEditCommit.swift:239` | `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift:243` uses the rollback/outcome helper | `Cadence/iOS/iOSCalendarBoardView.swift:244` instead calls the void date wrapper | Shared transactional machinery exists but does not protect this mobile drop: PA-13. |
| `Cadence/Shared/CadenceTaskDateEditing.swift:117` | Mac board uses direct planner apply at `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift:253` | Mobile board uses wrapper at `Cadence/iOS/iOSCalendarBoardView.swift:244` | The wrapper’s immediate reconcile is one-sided for this action: PA-14. Other Mac callers may use the wrapper. |
| `Cadence/Shared/CadenceScheduleDraft.swift:485` | Shared panel rollers use the pointer grid; Mac timeline creation uses its pointer metrics | `Cadence/iOS/iOSCalendarTimelineViews.swift:1051` still uses touch-grid draft edges | Same Shared file does not imply identical gesture resolution. PA-09; do not conflate rollers with drag grids. |
| `Cadence/Shared/Components/CadenceSchedulePanel.swift:1` | Mac task inspector remains in `Cadence/macOS/Views/SchedulePanelComponents.swift:72` | `Cadence/iOS/iOSTaskDetailSheet.swift:205` hosts the panel | One-sided **task-inspector** adoption, PA-07; not a claim that no Mac surface uses the panel. |

Also checked one-sided *service* consumers rather than mislabelling them Shared: Mac’s outline/unlinked-mention resolvers (PA-15/16), the search-cap continuation helper (PA-19), and model-context replacement (PA-26). Their missing counterpart is named in each finding. Unexamined Shared consumers are explicitly part of the next-pass scope below.

## What the seven existing parity suites actually establish

No suite was executed in this audit. These are inspected contracts, not green-run claims.

| Suite | Existing assertion boundary | What this pass shows it cannot currently establish |
|---|---|---|
| `CadenceTests/CrossPlatformParityTests.swift:21` | Date storage/formatting/widget keys, shared metadata, archive/roll-up logic and selected editor source contracts; focus roll-up at :217 and :231 | Screen-level information inventory; navigation lifetime; pointer/touch behavior; external-context adoption. |
| `CadenceTests/TodayScopeParityTests.swift:43` | Today inclusion, past-do, rank, de-duplication and widget membership/badges | Notes excerpts, subtask rows, truncation, metadata shedding and gestures (PA-01–06). |
| `CadenceTests/WorkHoursParityTests.swift:16` | Work-hour geometry, clipping, out-of-range inputs and weekend behavior | A reachable drag/resize control, precise touch targeting, native layout/scrolling (PA-08/09). |
| `CadenceTests/CalendarAllDayAndDoneTaskParityTests.swift:61` | Month inclusion, mobile all-day split at :121, mobile rendering call at :149, settled timeline inclusion at :196 | Month time labels, Mac all-day priority, actual cell capacity/overflow access (PA-10–12). |
| `CadenceTests/CadenceEventKitPlatformParityTests.swift:39` | Shared store-change effects, observers, typed write refusals, event-note commits and identifier/link handling | Real account permissions, calendar-ID portability across devices, OS delivery, SwiftData external-writer adoption (PA-26). |
| `CadenceTests/CadenceCodexFunctionalParityTests.swift:6` | Selected deadline labels, note tabs, board event-editor wiring, settled-card treatment and the four supported Mac global note kinds; rank-before-cap at :129 | Whole-surface parity. It expressly leaves list-document search out and tests a cap that currently hides the remaining results (PA-19/20). |
| `CadenceTests/CadenceEditorSaveCommitSurfaceTests.swift:36` | Commit/undo helpers, failure messages, snapshots, selected editor call sites; date failure reconciliation at :683 and source contracts at :840 | Every callback chain or native success signal. The mobile board’s Void callback + unconditional true lives across frames (PA-13). It also does not make draft and live-binding editors equivalent (PA-07). |

**Testing recommendation:** agree on the information and transaction contract per surface before adding more source-token checks. Paired fixtures should include notes, subtasks, completed/cancelled tasks, many search hits, crowded all-day/month cells and a refused save. Runtime checks should target the gaps source tests cannot observe. For future literal source guards, use raw source or `strippingComments`; `codeOnly` blanks quoted strings as well as comments.

## What I could not check and why

- **Native UI and gesture behavior:** this was a read-only source pass following the audit brief, with no application launches, builds or tests. No current screen-lock or simulator failure is claimed. Mac hover/right-click, iPhone touch, iPad trackpad, keyboard, Dynamic Type, VoiceOver, focus dismissal and safe-area behavior remain unmeasured. PA-03–06, PA-08–12 and PA-17/18 need screenshots or interaction checks on the named surface, not broad assertions about a platform.
- **Store/refusal behavior on mobile:** PA-13’s mutation and accepted-result chain is visible in source. A real refusal was not injected. Its second-context durability, later-save contamination and on-screen failure response need an isolated fixture; the owner’s store must not be used to manufacture failures. Retained bundle handling is still reachable in the Board at this base while T-3170 retirement is incomplete; recheck that reachability before fixing legacy paths.
- **CloudKit and cross-process state:** no iCloud account, production store, sync logs, export archive or live MCP write was opened. PA-26 is the recorded local adoption defect. It does not identify the cause of every historical device-count discrepancy. Test external writes, CloudKit imports, retained inspectors and pending edits independently.
- **Notifications/EventKit/Reminders:** no permission prompt, delivered alert, recurring EventKit edit, provider account or cross-device calendar identifier was exercised. PA-14 establishes caller timing, not an observed stale alert. T-1117’s cross-device identifier uncertainty remains a device experiment; it is not counted as a new parity defect.
- **Focus lifetime and sleep:** the source establishes genuine navigation teardown versus retained tabs (PA-23). Mac also pauses/resumes on system sleep (`Cadence/macOS/Services/FocusManager.swift:215`), whereas the examined iOS Focus view has no analogous scene hook. Mobile suspension/lock semantics were not confirmed, so a sleep-policy difference is a follow-up hypothesis, not a counted finding. Process termination, restoration and failed bank-at-exit need native tests.
- **Notes/editor depth:** the pass traced outline, mention discovery, reference visibility, task-embed editing and export availability. It did not exhaustively compare slash-command lists, IME input, undo/redo, every table/image interaction, clipboard formats, Markdown render geometry, PDF pagination or export accessibility. Those require focused editor fixtures; no claim that the two editors otherwise match is made.
- **Settings and archive recovery:** category routing, import/export entry points and local backup affordances were checked. Individual AI/account/preferences effects, every setting’s synchronization policy, file-provider failure, crash recovery, destructive reset and actual backup restore were not run. Their absence from the findings is not evidence of parity.
- **Widgets and MCP:** inspected shipped widget registration, family declarations and completion action, plus the native MCP entry point/write fence. No live WidgetKit timeline/intent or plugin was run. Family availability on each OS, deep-link routing, stale snapshots and all MCP read/write tools remain separate test scopes.
- **Exhaustiveness boundary:** all requested surface categories were visited, but not every screen state, caller, shared declaration or the full 517-file product corpus. The base contains 222 macOS, 109 iOS and 186 Shared Swift files. As requested, these were not all read wholesale. The Shared table is selected, not a complete orphan/one-sided-consumer census. Additional surfaces such as every list Kanban variant and every quick-create seed require another pass. No zero-findings claim applies to unexamined files.
- **Fence / handoff:** the existing write lease includes the inbox but not this new report path. The owner explicitly requested this document and the two-file-only audit. No product fence was bypassed or altered. The final `codex-land.sh review` result is reported at handoff; a lease objection to the report is not evidence that product inspection was blocked. The audit uses the requested plain commit and never opens/edits `docs/TODO.md`; ticket checks used `ledger-view.sh`.

## Reproduce and land

At the pinned base, inspect any cited span with `nl -ba <named-file> | sed -n '<start>,<end>p'`. **At the landing HEAD, use the re-pinned numbers in each LANDING NOTE instead.** To reproduce the strongest source comparison, read `iOSCalendarBoardView.swift:256` and `:462`–`:467`, then `CadenceTaskMutationSupport.swift:270`–`:278`, against `CalendarBoardDayColumnSupportViews.swift:22` and `:208` and `CalendarPageBoardSupportViews.swift:226` and `:634`–`:644`. For external adoption, compare `macOSRootView.swift:265` with `iOSRootView.swift:181`–`:203`. These are read-only confirmations; the per-entry runtime scenarios are not substitutes for test results.

Ledger disposition is appended in `docs/CODEX_LEDGER_INBOX.md`: new entries only for unresolved ticket-worthy information/persistence gaps, plus evidence addenda to existing T-362, T-3084, T-3109 and T-168. No cosmetic or documented-density tickets. Rebase/landing against a newer tree must re-resolve line references and check whether shared-panel adoption or bundle retirement has already removed a finding. No product fix or test addition belongs in this audit commit.

### Landing review result

**Superseded by the landing — kept for the record.** What follows is Codex's own pre-landing review on
the audit branch. The state after landing is in the **Landing corrections** section at the top of this
file and in the commit that carried it: the lease objection was resolved by adding
`docs/PLATFORM_PARITY_AUDIT.md` to the fenced ```lease block in `docs/CODEX_WORKTREE.md` (commit
`38224bd8`, grant recorded **before** this report landed), and the four id clashes were resolved by
folding each addendum into its existing ledger entry in place, with no second entries and no
renumbering. The branch's own review keeps refusing until those same changes exist on `codex/*`, which
they never will — the branch is not rewritten. Read its exit code as a property of the branch, not of
the landed tree.

`./scripts/codex-land.sh review codex/platform-parity-audit` ran after the audit commit and exited **3**. It reported exactly two changed documents, neither already in main, and these refusals:

- `CODEX-LEASE-VIOLATION`: the owner-requested `docs/PLATFORM_PARITY_AUDIT.md` is absent from the standing lease. The report is present under the owner's explicit instruction; the lease was not edited.
- `CODEX-INBOX-ID-CLASH`: T-168, T-362, T-3084 and T-3109 are existing-ticket evidence addenda. Fold each into its existing formal entry at landing; do not allocate replacement IDs or create duplicate tickets.

No TODO-edit or missing-inbox refusal fired. The review noted **11 commits behind local main**; the branch was correctly based/rebased on fetched `origin/main`, whose pinned base is above. The coordinator must reconcile newer local-main work and recheck finding currency before landing. This is a saved audit branch, not a merged or review-green change.

Document verification passed: 26 unique sequential finding IDs; KIND/INTENT totals agree with all entries; 125 explicit source references resolve to existing files and valid line numbers; the inbox preserves its entire original prefix; `git diff --check` is clean; only the two requested documents changed. These checks validate the document, not app behavior.
