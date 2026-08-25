# Cadence — task list

The running record of work: open, in progress, done, cancelled. Started 2026-08-16.

**Format.** One line per item: `- [id] Title — note`. Ids are stable and never reused, so a
cancelled or done item can still be referenced later. Done items keep their commit sha, because the
commit message is where the *reasoning* lives; this file is only the index.

**Rule (set 2026-08-17).** *Every* request the user makes lands here the moment it is made, whether
or not work starts on it — under **In progress** if it is being worked now, otherwise under the
right Open section. An item moves to **Done** only when the code behind it is committed (or
otherwise verified), not when it is written.

**Target devices** (set 2026-08-16). Build and verify for these three only; anything that exists
solely to serve other hardware is dead weight and should be removed rather than maintained:

| Device | Points | Notes |
|---|---|---|
| iPhone 15 (base) | 393 × 852 | compact width, the only phone shape that matters |
| iPad Pro 11" | 834 × 1210 portrait · 1210 × 834 landscape | pane = window − 188pt sidebar → **646** portrait, **1022** landscape |
| MacBook Pro 14" | 1512 × 982 | the macOS surface |

Both iPad panes matter to Today's layout: 646pt portrait falls **below**
`CadenceTodayLayoutSupport.twoPaneMinimumWidth` (761), so portrait is one column and landscape is
two. The three-pane floor of 1022pt that this note used to cite is gone with the layout itself
(T-06).

---

## In progress

_Nothing in flight._

## Open — decided, not started

- [T-73] **Audit iPhone/iPad divergence and share what should be shared.** Standing rule added to
  `AGENTS.md` and `CLAUDE.md` 2026-08-17: the two differ in *layout* only, never in how a row, chip,
  header or picker looks or behaves. This item is the sweep to make the code match that — find the
  places where a phone view and an iPad view are near-copies and collapse them into one view
  parameterised by size class. Distinct from [T-32], which is macOS↔iOS *feature* parity; this is
  iPhone↔iPad *implementation* sharing. The Notes starting point is closed (`D-44`, one view for all
  three hosts) and so is the page-header family (`D-62`). What is left of the original list —
  `iPadTodayView` vs the compact Today, and the compact/regular branches inside the task row — is
  in flight now.

  **2026-08-24 mechanical re-sweep: both named remainder items are already closed, and nothing else
  in scope needs a code change.** Checked against HEAD (`9582956`), not the working tree, which had
  five other agents' uncommitted changes in it at the time. `iPadTodayView` does not near-copy the
  compact layout any more — both widths render through the one `iOSTodayTaskSections` (comment at
  `iPadTodayView.swift:258` records the second-copy defect `D-54`/`D-66` already fixed: 15pt vs 14pt
  group spacing, an 18-vs-14-padded empty state, and a `todayTasks`-derived branch duplicating the
  groups). The task row is one `iOSTaskRow` reading `CadenceTaskRowMetrics.metrics(isRegularWidth:)`
  for every figure (`iOSTaskViews.swift:5-9` records the deleted `iOSTaskRowDensity` axis this used
  to hide behind). Grepped every `horizontalSizeClass` site under `Cadence/iOS` and `Cadence/Shared`
  (38 files) rather than trusting impression: the rest are legitimate layout swaps already reached
  through shared factories (`CadencePageHeaderMetrics`, `iOSEditorSheetMetrics`,
  `CadenceRegularPaneLayout`, `iOSCalendarMetrics`) or `iOSFeatureSplitLayout`/`iOSFeatureRowLink`
  (list-pane-vs-push, one implementation parameterised by `pushes`), each with a code comment
  recording the drift it already closed. `iOSCalendarToolbar.toolbar` is the model worth naming: it
  used to be an `if horizontalSizeClass == .compact` beside a `ViewThatFits` fallback described in
  its own comment as "the phone's own two-row shape" — i.e., the phone's layout was already correct
  for the iPad and was being withheld from it. It is one `ViewThatFits`, chosen by whether the row
  fits, now.

  One drift found in passing, adjacent to but not itself iPhone/iPad divergence — a near-copy of two
  *iOS* note-editor sheets rather than of one sheet across two widths: `iOSEventNoteEditorSheet`'s
  header (hand-rolled 12pt uppercase caption, title fixed at 24pt on every width, 4pt block spacing)
  had drifted from `iOSLinkedNoteEditorSheet`'s near-identical header
  (`Cadence/iOS/iOSMarkdownReferenceSupport.swift`), which already uses the shared
  `SectionEyebrowLabel` (10pt, kerned) and ramps the title `isRegularWidth ? 24 : 22` with 8pt
  spacing — that sheet's own comment records converting "a fourth hand-rolled uppercase caption",
  and the event-note sheet was never swept into it. **Shipped in `af03fb1`**:
  `iOSEventNoteEditorSheet.swift`'s `header` now matches the linked-note sheet's spelling exactly;
  no visible change at regular width (title was already 24 there), compact width now reads 22pt to
  match. Not folded into a single shared header type in this pass — the two sheets' surrounding
  chrome (toolbar items, AI actions button, calendar sync) differ enough that extracting one would
  be a larger, unaudited change; a future pass can revisit if a third near-copy appears.

  Nothing else ticketed out of this sweep: no missing-capability divergence (a control present at
  one width and absent at the other) turned up anywhere the grep reached.


- [T-243] **The drop-a-task-on-a-task gesture landed on iOS's Board, not its timeline — because the
  iOS timeline has no drag-and-drop at all.** macOS's home for the gesture is `TimelineDayCanvas`,
  where every block by definition owns a slot, so the target is always eligible.
  `Cadence/iOS/iOSCalendarTimelineViews.swift` has **no** `.draggable` and **no** `.dropDestination`
  anywhere — `iOSTimelineTaskBlock` cannot be dragged — so [[T-190]]'s gesture went to the Calendar
  Board, whose drag mesh already works. Consequence: on the Board only *timed* cards offer it, and a
  do-dated-only card correctly declines, so the affordance is less discoverable than on the Mac.
  Adding DnD to the iOS timeline is the fix and it is **not** small: that view carries a
  `simultaneousGesture` pinch, and the file's own comment records that `.draggable` "delays the
  touches of everything under it" — the sidebar bug it was written about. Treat gesture-conflict
  testing on a real device as part of the work, not a follow-up.
  Two small things found in the same pass, neither worth its own ticket: `SchedulingActions.dayStartMin`
  has been dead since before [[T-190]] (declared, read by nothing), and the day bounds are now
  spelled twice on purpose — `TimelineDayRange` in `macOS/Views/TimelineMetrics.swift` and
  `CadenceTaskMutationSupport.bundleDayEndMin` / `bundleMinimumDuration` in `Shared/`, because
  `Shared/` does not compile the timeline. The second pair is pinned equal to the first by
  `theSharedBundleClampsMatchTheTimelineDayRange`; if `TimelineDayRange` ever moves to `Shared/`,
  delete the copy rather than the test.

- [T-237] **`git archive HEAD` over the whole tree runs at ~5 KB/s here; root cause unconfirmed.**
  Measured 2026-08-22 and worked around rather than fixed — `AGENTS.md` now prescribes
  `rsync` + `git show HEAD:<path>` restore instead. The workaround has a real ongoing cost: the
  restore step is manual, and an agent that skips it verifies another agent's in-flight code while
  believing it tested HEAD. That is worth removing, not just documenting.
  Evidence: one file (`git archive --format=tar HEAD -- AGENTS.md`) is instant; the whole tree
  sampled at 10s intervals gave 1259520 → 1310720 → 1372160 → 1484800 → 1525760 → 1576960 bytes,
  ~25 min for a 15 MB tree, and emits a **0-byte file** for the first minutes so it reads as a hang
  (two runs were killed at 2 and 3 minutes for that reason). The repo is healthy —
  `git rev-parse HEAD` is 0.018s.
  Prime suspect, **not confirmed**: a global `filter.lfs` with `required = true` while `git-lfs` is
  not installed (`git lfs version` → "not a git command"). Against that theory,
  `-c filter.lfs.process= -c filter.lfs.required=false` did not help, and the repo has no
  `.gitattributes`. Next steps: `git config --global --get-regexp '^filter\.'`, then try
  `GIT_TRACE=1 GIT_TRACE_PERFORMANCE=1 git archive HEAD > /dev/null` to see where the time goes, and
  test whether the slowness follows the global config into a scratch repo. Fixing it restores a
  one-command isolation step for every future agent.


- [T-278] **There is a fourth note-kind switch, and it is on the MCP boundary.** Found while
  closing [[T-239]], which named three and consolidated those three.
  `CadenceReadService.noteSubtitle` (`Cadence/Services/MCPReadOnly/CadenceReadService.swift:1213`)
  is a fourth switch over `NoteKind` reading "Daily note" / "Weekly note" / **"Permanent
  note"** / the container name / **"Meeting note"**. Both bolded strings are the retired vocabulary
  that `NoteReferencePanelSupport.noteKindLabel`'s own doc comment exists to warn about: the app
  calls those surfaces Notepad and Event Notes. A sixth literal `subtitle: "Meeting note"` sits at
  line 730 of the same file.

  **Not folded into T-239 on purpose.** These strings are MCP *response* content, and
  `CadenceMCPServer/AGENTS.md` says response DTOs change on purpose or not at all — an agent
  reading this surface may be matching on them. The stable keys are elsewhere and unaffected
  (`noteEntityType` returns `permanent_note` / `document` / `event_note`), so this is prose in a
  payload rather than schema, but it is still a decision rather than a cleanup. Either route both
  through `noteKindLabel` and note the response change, or record that the MCP surface keeps the
  raw-value vocabulary deliberately. Nothing persisted is involved either way.

- [T-221] **Edit tables in place — DONE on macOS, and the iOS half is the whole remainder.**
  Requested 2026-08-21, decided 2026-08-25 (shape 2, tables only; Tab / Shift-Tab / Return as
  spreadsheet keys), and the macOS half shipped the same day in `0b44973`. macOS renders a table as a real grid and edits it cell by
  cell: `Services/MarkdownTableEditSupport.swift` (the markdown decisions),
  `Services/MarkdownTableLayoutSupport.swift` (the rects), `macOS/Editor/MarkdownTableCanvasDrawing.swift`
  and `macOS/Editor/MarkdownTableInteractionSupport.swift` (the AppKit half). Fenced code, images,
  dividers and task embeds are untouched, as decided.

  **The two questions left open at decision time are settled.** A row or column is added and
  removed from the **table's own context menu** — a right-click on the cell you want to change,
  rather than hover chrome, which would be a second hit-testing surface over a canvas that already
  has one and would have to be discovered. The raw source is reachable **by command**, "Show Table
  Source" in that same menu, which un-renders that one table back to the banded per-row styling the
  editor has always drawn; it is never reached by caret position, since that is the behaviour the
  ticket exists to remove.

  **What the boundary spike measured**, on a real offscreen `CadenceTextView`
  (`CadenceTests/MarkdownTableHostedEditingTests.swift`), because three of the four worries turned
  out to rest on one design choice: **the markdown source never leaves the text storage.** Only its
  glyphs are collapsed and a grid is drawn over the space they were given.
  - *Selection* — a range from the prose above to the prose below still covers the table's own
    characters, and a caret arrowed at the table steps over it rather than into it.
  - *Copy/paste* — copying that range yields the pipes; pasting it into another note renders a
    table again. One measured surprise: on macOS 26 `NSTextView.writablePasteboardTypes` still
    advertises the **legacy** names (`NSStringPboardType`), so writing
    `NSPasteboard.PasteboardType.string` returns false without writing anything.
  - *Undo* — a committed cell is an ordinary text-view edit through
    `shouldChangeText` / `replaceCharacters` / `didChangeText`, so `Cmd+Z` restores the note byte
    for byte with nothing added to the existing pass-through route. A commit whose value did not
    change registers no edit at all, so tabbing across five cells does not cost five `Cmd+Z`.
  - *`MarkdownStyleSignature`* — **the fourth concern does not exist on macOS.** The signature has
    exactly one reader in the repo, `Cadence/iOS/iOSMarkdownEditor.swift`; macOS re-runs the whole
    styler from `textDidChange`, which `didChangeText()` posts.

  **One shared parser rule changed, and it is worth knowing.** `MarkdownTableParser` now
  distinguishes opening a table from continuing one: an all-blank row (`|  |  |`) continues a table
  and cannot start one. Return inserts exactly that row, and under the old shared predicate the
  table simply ended at it. The two-pipe count that keeps prose out (`Ship it | maybe`) is
  unchanged.

  **Still open, and it is the whole other platform.** `Cadence/iOS/` was deliberately out of scope
  and is untouched. `iOSMarkdownStylingBlockSupport` still draws a table as a canvas and
  un-renders it via `MarkdownStyleRanges.isRevealed` the moment the caret lands inside — so on
  iPhone and iPad, editing a table still means typing pipes, which is the complaint this ticket
  opened with. The shared halves are already there and platform-free (`MarkdownTableEditSupport`,
  `MarkdownTableLayoutSupport`); what iOS needs is a `UITextView` equivalent of the hosted cell,
  its own `.cadenceMarkdownTable` styling pass, and — unlike macOS — a **`MarkdownStyleSignature`
  entry**, because the gate that does not exist here does exist there and a committed cell that
  does not change the signature would silently not re-render.

  Two smaller gaps left on the macOS side, neither blocking:
  - Inline markdown **inside** a cell is not rendered — a cell reading `**Total**` draws its
    asterisks. The stylist computes the cell's attributes before hiding the run; carrying the
    attributed substring through to the draw pass would fix it.
  - Cells clip rather than wrap, which is what makes the reserved line height independent of the
    window width (and therefore correct across a resize with no restyle). A wrapping cell would
    need the reservation recomputed on resize, the way the image block's already is.

- [T-211] **On iOS, H5 (16pt) and H6 (15pt) render *below* the editor's body text.** Found by
  `d513e72` and recorded rather than fixed. The iOS body is
  `UIFont.preferredFont(forTextStyle: .body)` — 17pt by default and larger at accessibility sizes —
  so no fixed point size can stay above it. Fixing it means making the iOS ramp relative to
  `preferredFont(.body).pointSize` rather than absolute, which is a different change from unifying
  the ramps.

- [T-194] **Note export on iOS: markdown *and* PDF.** User's call — the fuller option, chosen
  knowing the cost. Unlike [[T-187]]–[[T-193]] this is the one gap that is genuinely AppKit-bound
  rather than guarded by accident: `NoteExportService` uses `NSSavePanel` and renders PDF through
  `NSTextStorage`/`NSTextView`, so the mechanism must be rebuilt, not un-guarded.
  Markdown is cheap: a `ShareLink` over the export string, and `ShareLink` appears nowhere under
  `Cadence/iOS` today. PDF is the real work and needs a UIKit renderer, which means **a second
  renderer that has to keep matching the macOS one** — so factor the shared decisions (page size,
  margins, how a task embed and an image asset render) out of `NoteExportService` first, or the two
  will drift the way the heading ramps did. Note `D-124` found the markdown *preview* and *editor*
  already disagreed about heading sizes on the same platform; a third renderer is a third chance at
  that.

- [T-168] **iOS Focus mode: widgets and a landscape timer.** Two halves.
  *(a)* A widget showing the running timer plus what is being worked on, and a second showing the
  task list — exact split is a design call, make a good one rather than shipping two widgets that
  say the same thing. Two constraints to design around, both real: **WidgetKit timelines cannot
  tick**, so a live count needs `Text(timerInterval:)` (the system animates it without waking the
  extension) or ActivityKit for a Live Activity on the lock screen and Dynamic Island — a timeline
  that reloads every second is not an option. And **`FocusManager` is `#if os(macOS)` only**
  (`macOS/Services/FocusManager.swift`); iOS focus lives in `iOSFocusView.swift` with no shared
  state object, so session state is in-memory and a widget process cannot see it. Persisting focus
  state to the app-group store is the prerequisite, not a detail. Existing widgets to match:
  `CalendarSnapshotWidget`, `HabitCheckInWidget`, `MilestoneMomentumWidget`, `TodayTasksWidget`.
  *(b)* iPhone **landscape** layout for the running timer and its tasks. The compact shell
  (`iOSCompactTabShell`) is built around a portrait tab bar; landscape focus wants the timer large
  and the chrome gone, which is a different shape rather than the same one rotated.

- [T-170] **Decide how far iPadOS and iPhone layout should converge.** Standing rule is that they
  are one *style* and differ only in *layout* — sidebar vs tab bar, two panes vs one. The open
  question is where that line actually falls now that Today, Tasks, Calendar and Notes have all
  been unified internally. Wants a decision recorded, not a sweep: which surfaces are genuinely
  shape-bound and which are iPad-only by accident.

- [T-171] **The blue `+` button: palette on stillness, drag on escape.** User's resolution of the
  gesture conflict, and it is better than the alternatives offered — **the palette *is* the
  local-drag target**:
  - Quick press then move → a drag immediately. The palette never appears.
  - Press and hold still (~350ms, with haptic) → the palette opens, a semicircle of segments around
    the button: task, calendar, note, and possibly a fourth.
  - Palette open, finger moving **within** its radius → slides between segments, the way a radial
    menu works. This is the "local dragging" case and it belongs to the palette.
  - Finger travelling **beyond** that radius → the palette gives up and it becomes a drag, so
    dropping onto a task list still works.
  **The technical caveat, recorded before anyone starts.** "Drag wins on escape" is probably not
  implementable with `.onDrag` / `UIDragInteraction`: you cannot hand a live touch to UIKit's drag
  machinery partway through a gesture you are already tracking, and the lift has to be recognised at
  the start. So this likely needs a custom drag — a `UIPanGestureRecognizer` plus a rendered preview
  — rather than the system drag the button uses today. `iOSMarkdownImageResizeGestureRecognizer` is
  the in-repo precedent for a recognizer that decides by direction inside the first few points of
  travel and fails cleanly so a sibling can take over.
  Two figures to settle by feel, not by argument: the hold duration (UIKit's own lift is 326–349ms
  measured here) and the escape radius, which must be larger than the palette's own reach or
  segment selection will convert to a drag mid-choice. macOS stays deliberately unspecified.



- [T-161] **Tests pin helpers, not wiring.** The T-149 verifier proved by mutation that reverting the
  `macOSRootCommandActionSupport` fix leaves all 1692 tests green, and the same holds for T-150 —
  nothing observes that `MarkdownEditorView` calls the shared functions. `D-113` closed this for the
  markdown indent formula by testing that the stylist *reads the shared metrics*, not merely that the
  numbers are right. Worth applying that pattern to the two search fixes, and treating it as the
  default shape for consolidation work: a test that passes when the call site is reverted has not
  pinned the consolidation.

  **Survey, 2026-08-25, against `6e1f1e0`.** Measured rather than estimated, because nobody had:
  **2,514 `@Test` functions, of which 154 read a `.swift` file as text**, spread over **32 of 189**
  test files. Of those 154, **73 assert nothing but that some text exists** and 81 also assert at
  least one value produced by a real call. So the source-scan population is ~6% of the suite — small
  — and it is concentrated where the risk is: iOS surfaces the macOS target cannot compile, plus a
  tail of macOS files where a value *was* available and nobody reached for it. The script is
  reproducible from the classification described here; it strips comments and masks string literals
  before matching, because `func select(` inside a needle literal otherwise reads as a declaration.

  **Partly shipped in `902b386`: three fixed, each with the blindness proved first** (pre-fix
  mutation → all green, post-fix same mutation → red, both at 0 compile errors). Six more
  whole-file needle counts, listed below, were recorded as remaining rather than fixed — this
  ticket stays open for those:
  - *macOS's settings rail was pinned one case at a time.* `SettingsCategoryGroup` was `private`, so
    `theSyncCategoryIsFiledInTheMacOSRail` and `theAboutCategoryIsFiledInTheRailAndRoutedToItsSection`
    each found `static let all: [SettingsCategoryGroup]` in the source text, sliced to the next
    `\n}`, and asked whether the slice contained `".sync"` / `".about"`. Deleting `.notifications`
    from the Connections group — Settings → Notifications unreachable on macOS — passed. The struct
    is `internal` now and `theRailFilesEverySharedCategoryExactlyOnce` states the general rule.
  - *Both edit sheets' wind-down was two whole-file counts.* `macOSStillWindsDownOnArchiveAndOnCompletion`
    asserted `cancelRemainingActiveTasks(` == 2 and `completeRemainingActiveTasks(` == 2 in
    `EditListSheet.swift`. **Swapping them** — archiving a list marks its leftovers *done*, completing
    one cancels them — leaves both counts at 2 and passed. The branch is a value now
    (`ListEditorLifecycleChoice.windDownOutcome`) over a new
    `TaskContainerLifecycleService.settleRemainingActiveTasks(…outcome:)`, and the surviving scan is
    scoped to `apply(_:)`'s brace-matched body instead of the file.
  - *T-240, closed in `902b386` — see Done.*

  **`cadenceFunctionBody(_:in:)` is now the one brace matcher in `CadenceTests`** — `cfa3b3b`'s
  `focusFunctionBody`, promoted to `internal` and renamed, read by `FocusPickerPlayControlTests`,
  `AppStoreReviewReadinessTests` and `CadenceListWindDownSurfaceTests`. Anything else scoping a scan
  to one function calls it rather than writing a second.

  **Deliberately left, and worth doing next** — all still whole-file needle counts, listed worst
  first. Each is the `cfa3b3b` shape: a call moving between two functions in the same file is
  invisible to them.
  - `CadenceTaskInspectorHostTests.theInspectorIsPresentedFromExactlyFivePlacesInTheWholeApp` and
    `theHostIsInstalledAboveBothShellsAndInsideTheOneSheetThatCarriesAPage`; the same pair in
    `CadenceBundleInspectorHostTests`. These are repo-wide counts, which is the *right* shape for
    "exactly N places in the whole app" — but the per-file half is unscoped.
  - `CadenceKanbanColumnLifecycleSurfaceTests.bothVisibleCompletionControlsSitInsideTheLifecycleGate`
    and `theKeyboardRouteAndTheConvergencePointBothRefuseDefault`.
  - `CadenceListDetailTabStripMarginTests.theResetIsTheStripsAloneAndTheHostCompensatesForNothing`.
  - `CadenceSharedBoardChromeTests.bothBoardsDrawTheSharedMetadataChip` (a `cardCornerRadius:` count
    over two whole view files).
  - `CadenceSharedTaskRowJobsTests.theRowsAnimatedPartsAreStillExtractedIntoTheirOwnSubViews` — an
    `@Environment(TaskCompletionAnimationManager.self)` count of 2 over `TasksPanelComponents.swift`,
    which cannot tell the two extracted sub-views from `MacTaskRow` growing one of its own.
  - `CadenceTodayRolloverSurfaceTests.theMacSpellingDelegatesToTheSharedMutation` and
    `CadenceTodayOverdueSummarySurfaceTests.theMacCardsHopTheNavigationManagerThroughTheSharedRequest`
    — both scan macOS files, and the first has a behavioural neighbour already
    (`TaskBundleTests` calls `SchedulingActions.rollOverTaskToToday` for real), so only the
    "no second body" half is at risk.

  **One piece of mutation evidence is still owed from `55d696b`:** forcing
  `CadenceTaskGroupHeadingMetrics.showsCapsule` to `true` was never watched to fail, because two
  test hosts deadlocked (T-117). The behavioural test exists; the proof does not.



- [T-123] **Tighten the repo, and converge the three platforms' UI.** Requested 2026-08-18. Scope
  decided with the user up front, because two readings of "unify the UI" are different projects:

  1. **Share the implementation now; decide feature parity after.** One set of tokens, components
     and presentation logic behind all three surfaces; each keeps its own *layout* (macOS sidebar +
     columns, iPad split, iPhone tabs). The user's stated goal is that the end product should be
     **more similar across all three than it is now, especially closing the macOS↔iOS/iPadOS gap** —
     so parity is a real target, just sequenced after the sharing sweep with numbers in hand.
     Distinct from [T-32], which stays not-started.
  2. **Best spelling wins, either way.** macOS may change visually where iOS has the better answer.
     This reverses the earlier "macOS is the reference" default and is only safe because macOS
     screenshot verification now works (`D-89`). Every macOS visual change must be seen, not argued.
  3. **MCP is in scope, refactored extra carefully** — and the first task there is to work out *why*
     `AGENTS.md` says not to touch it, since a rule with a forgotten reason is either load-bearing
     or dead. `CadenceReadService.swift` is now the largest file in the repo at 1,336 lines. After
     the refactor, the docs must say considerably more about that boundary than they do now.

  Proportions worth keeping in view: macOS 218 files / 51.9k lines, iOS 79 / 30.4k, **Shared only
  74 / 11.5k**, Services 53 / 12.7k, Models 24 / 2.6k. 82k lines of platform code against 11.5k
  shared is the number this item exists to move.

  Method: read-only audit agents first, findings triaged and recorded here, then implementation
  agents, each followed by an **independent verifier agent** that checks the work against the code
  rather than against the implementer's report.

  **Audit pass, 2026-08-24, against `af03fb1`.** Re-derived every count in this entry and in the
  guides rather than trusting them, per the method above.
  - **Item 3 (MCP) is done by inspection.** `CadenceMCPServer/AGENTS.md` already states the full
    boundary — why the old "do not touch" rule was wrong (`670e299`/`62dc384` broke the target
    silently, `0040f24` shipped a stale schema silently) and the procedure that replaced it. There
    is nothing left to refactor that the doc doesn't already explain; a future pass should cite a
    specific file before re-opening this rather than re-asking the general question.
  - **The proportions line is dated but the trend is real, not a reason to reset it.** At filing:
    macOS 218/51.9k, iOS 79/30.4k, Shared 74/11.5k. At `af03fb1`: macOS 216/51.2k (flat), iOS
    96/35.0k (+17 files), **Shared 106/19.0k (+32 files, +7.5k, +65%)**. Item 1's sharing sweep is
    visibly happening.
  - **Two file counts elsewhere had drifted**, caught by re-deriving instead of trusting them: iOS's
    `.swift` count read "93" in four places (root `AGENTS.md`, `CLAUDE.md` ×2, `Cadence/iOS/AGENTS.md`)
    against an actual `ls Cadence/iOS/*.swift | wc -l` of 96; `CadenceTests/` read "177" in two
    places (root `AGENTS.md`, `CLAUDE.md`) against an actual 186. Fixed in root `AGENTS.md` (both
    counts) in this pass. **Not fixed in `CLAUDE.md` or `Cadence/iOS/AGENTS.md`**: both files were
    mid-edit by other agents for unrelated work (the `CadenceFocusHandoff`/T-266 addition and the
    T-214/T-215 archive→wind-down rename) while this pass ran, so editing them risked colliding
    with in-flight work rather than being unsafe on its own terms — still open. Everything else
    checked out exactly and needed no correction: `Shared/Components/` 21 files (matches the named
    list), `macOS/Views/` 167, `Services/` 50, `Markdown*.swift` 27 (25 of them `*Support`),
    `SettingsCategory` 14 cases, `iOSSettingsCategory` 12 cases.
  - **One concrete near-copy found, filed separately as [T-275]** rather than fixed here: fixing it
    is a visible macOS change, and item 2 above requires those to be screenshotted rather than
    argued, which a read-only pass isn't positioned to do.
  - **Checked and clean, no action needed:** no `Color(hex: "#...")` literals outside `Theme.swift`,
    no bare `Color.white`/`.black`/`.gray`, priority/status colour fully routed through
    `Theme.priorityColor`/`statusColor`, `CadenceFeatureDestination` tints read from one source on
    both platforms (the `e181dea` fix holds), `GoalLinkTarget`'s one write path holds on macOS too
    (`.area`/`.project` shorthand at both `CreateGoalSheet` and `GoalAttachWorkSheet` call sites,
    not a bare `GoalListLink(` construction).
  - **Narrowed scope going forward:** item 3 is closed. Item 1 is the real remaining work, and the
    productive unit of audit is one hand-rolled UI pattern (a header, a label style, a literal
    list) at a time, grepped across both platform folders before calling it shared or
    platform-only — the method that found [T-275] and the two stale counts above.

- [T-277] **The two weekday column headers are a fork nobody has compared.**
  Found while closing [[T-275]] and left alone deliberately. `CalendarPageMonthSupportViews`
  (macOS) draws `MON` at 10pt semibold, `isToday ? Theme.blue : Theme.dim`, `.kerning(0.5)`;
  `iOSCalendarTimelineViews` draws the same header at `iOSCalendarTimelineMetrics.weekdaySize`
  semibold in the same conditional tint with **no** kerning. One is a literal and one is a named
  metric, so a grep for a shared constant finds nothing wrong. This is not a section eyebrow — it
  is the date label above a day number — so `SectionEyebrowLabel` is the wrong answer; the right
  one is a shared weekday-header metric the way `CadenceBoardColumnHeaderMetrics` is shared, or a
  decision that the two differ on purpose.

- [T-122] **Flip `SWIFT_VERSION` to 6.0 — now an open question rather than a blocked one.** `D-95`
  cleared the last macOS error, so nothing in the app's source blocks it. What remains: 10
  Swift-6-mode *warnings* elsewhere in the app (byte-identical before and after T-105, none in
  editor files), and on iOS the toolchain bug in [T-115] — swift-frontend crashes in IRGen once the
  diagnostics are gone, which is not app code. So macOS could plausibly flip first; iOS cannot until
  the toolchain moves. `CadenceMCPServer` has been on 6.0 all along.


- [T-119] **Not reproduced — and the obvious fix breaks scrolling.** Reported by the drag sweep as a
  Week-view task block opening the Edit Task sheet after a 700ms press and 250pt of travel. Five
  gesture variants on HEAD — vertical both ways, horizontal, single-jump, diagonal — all scrolled the
  grid and opened nothing. That matches the construction: the block is a plain `Button`, which does
  not fire when released outside its bounds, and the grid's scroll views claim the pan first.
  The fix was built anyway and **regressed scrolling**: a `simultaneousGesture(DragGesture(minimumDistance: 0))`
  on scroll content claims the touch, so a plain swipe starting on a block stopped scrolling where
  HEAD scrolls. Reverted, helper and tests deleted.
  Most likely the original observation was the grid scrolling 1:1 under the finger — 250pt relative
  to the screen, none relative to the control. **Left open only as a warning**, not as work: it joins
  T-89 and T-14 as an observation whose mechanism was misattributed, and it should not be "fixed"
  without a fresh reproduction.
- [T-117] **A project-file lock is a new disguise in the T-86 family — now confirmed twice.** Builds
  deadlock in `NSFileCoordinator` reading `Cadence.xcodeproj`, 20+ minutes at 0% CPU, with an empty
  derivedDataPath. A `sample` of a stalled process caught it in `_blockOnAccessClaim` on the project
  file, with a concurrent agent's `xcodebuild` holding it and the user's Xcode — open six days —
  also claiming it. **It produces no diagnostic at all**: the run simply sits at the "Command line
  invocation" line, which reads as a broken checkout. Distinct from DerivedData contention.
  Mitigations: quit Xcode when a batch of agents is running, and treat total silence as this rather
  than as a failure to be debugged.
  Related but *not* universal: one agent found a fresh private DerivedData could not start because
  package resolution is sandbox-blocked, and worked around it with
  `-clonedSourcePackagesDirPath` + `-disableAutomaticPackageResolution`. Recorded as situational
  rather than as a rule — my own fresh-DD runs this session resolved packages fine, so do not add
  those flags by default.

  **Re-checked 2026-08-24 under 14 concurrently-building agents: not reproduced, and the tell is now
  in `AGENTS.md`.** Live `ps` found no bare `xcodebuild` pinned at 0% CPU; every process that looked
  stalled at a glance was a `test-host-lock.sh acquire` wait (T-236's mutex, working as designed —
  `sleep 10` in a loop, not a hang) or a polling wrapper shell around one. The user's Xcode was not
  running at all, so one of the two confirmed claimants from the original report was simply absent
  tonight — consistent with the mitigation ("quit Xcode when a batch of agents is running") rather
  than with the mechanism having gone away. Two processes stranded the same night — an `xcodebuild
  test` at 3h14m against a suite that normally runs ~15 minutes, and a runner script at 4h30m — were
  both killed before anyone captured a `sample`, so neither can be attributed to this ticket by
  evidence; that would be a third confirmation resting on inference, which is exactly the shape T-119
  warns against. The runner script fits `58e20a4` ("agents stall by launching a background job and
  returning," the same night, four other agents confirmed) far better than it fits a project-file
  deadlock: a wrapper script outliving the agent that launched it, with no one left to read its
  `DONE` file, is that failure's signature, not this one's. Downgrading the open half of this ticket
  accordingly: the mechanism from the original two `sample` captures stands and the mitigation stays,
  but there is nothing further to *fix* here — this is a recognition guide, not open work. See
  `AGENTS.md`'s new bullet (after the T-236 test-host mutex entry) for the exact tell command.

- [T-115] **The iOS Swift 6 flip is blocked by a toolchain bug, not app code.** With `D-86`'s three
  errors fixed the iOS module is diagnostically clean, and swift-frontend then crashes in IRGen on a
  reabstraction thunk carrying an `(any Actor)?` parameter. Attributed, not assumed: pristine HEAD
  with those same errors removed a different way crashes identically with zero diagnostics, and
  pristine HEAD under Swift 5 builds clean. Xcode 26.6 / Swift 6.3.3. Recheck on a toolchain bump.

- [T-86] **Agents building into the shared DerivedData can crash a running Mac app.** On 2026-08-17
  the user hit "Cadence quit unexpectedly" — `EXC_BREAKPOINT` on the main thread, five seconds after
  launch. **Not app code:** the whole backtrace is `dyld` → `libSystem_initializer` →
  `_libsecinit_appsandbox`, i.e. App Sandbox setup failing *before `main()` runs*, and the app
  bundle had vanished from `Build/Products/Debug/` by the time it was inspected — a concurrent agent
  clean build wiped it under the running process. A fresh build into a private `derivedDataPath`
  launched and stayed up. Two agents had already reported `build.db is locked` from the same
  contention. **Mitigation:** every agent brief should require a private `-derivedDataPath`, which
  most already do ad hoc; worth making standing in `AGENTS.md`. Nothing to fix in the app.

  **Mitigation shipped 2026-08-18** — the rule is standing in `AGENTS.md`. Left open because the
  underlying contention still exists and this keeps producing *new* disguises: the same day it
  reported unresolvable swift-nio modules (`DequeModule`, `Atomics`) from a corrupt `SourcePackages`,
  which read as a broken package checkout and briefly made a correct agent report look wrong. The
  standing rule now says an unexplained build failure is a private-path re-run before it is a
  finding. Close this only if the contention itself is removed.

- [T-55] **Three things need a real phone, not a simulator** — written up as a checklist in
  `docs/device-checks.md` (keyboard dismissal, double-tap, and drag-to-create per [T-89]).
  Original note:
  1. **Can a phone still dismiss the keyboard in the Notes tab?** The Done bar was the dedicated
     affordance and it is gone. `keyboardDismissMode = .interactive` remains, so dragging the note
     down should carry the keyboard off — Apple Notes behaves this way — but it was never seen to
     happen: both simulators suppress the software keyboard while the Mac's hardware keyboard is
     attached, and that toggle lives in Simulator.app, which is off limits. The Notes tab is the
     exposed case because it hides its navigation bar; every sheet-hosted editor has its own
     Done/Cancel above the keyboard. If it sticks, the answer is a nav-bar Done or tap-outside, not
     the bar returning.
  2. **Double tap on plain text, and on a code block or table.** The `shouldBegin` gate makes the
     prose case true by construction, but neither case was observed: the simulator tooling has no
     double-tap action and two scripted taps fall outside UIKit's ~350ms window.

- [T-16] **Redesign the logo.** Currently the app mark in the sidebar header and the app icon.
- [T-17] **Expand the target device list.** Directly reverses [T-08]; anything deleted as
  "unnecessary for the three targets" would need reinstating, so [T-08] should be done in a way that
  is easy to read back out of git history. Backlogged.

  **Axis decided 2026-08-24, still backlogged.** The user's answer: *more iPhone and iPad sizes* —
  not a lower OS floor and not a new platform family. Both of those are explicitly out of scope, so
  do not touch `IPHONEOS_DEPLOYMENT_TARGET` / `MACOSX_DEPLOYMENT_TARGET` or add a
  `TARGETED_DEVICE_FAMILY` entry on the strength of this ticket. **The user will name the exact
  devices and OS versions when they want this done — do not start it before then.**
  Investigated 2026-08-24 without changes. `TARGETED_DEVICE_FAMILY = "1,2"` on every target already,
  so any iPhone or iPad can install today; nothing at the build level blocks it and **no
  `project.pbxproj` edit is needed for this axis**. T-08 removed no device-specific code — it deleted
  width clamps unreachable at the three targeted sizes (`inspectorMaxWidth` 430, two 540 inspector
  caps, a 760 task cap) and replaced them with proportion-pinning tests, so there is nothing to
  reinstate. The whole cost is layout auditing: the current breakpoints (Goals' inspector gate at
  901, Today's 761/841/900/928 bands, the Calendar Board's rails, the Settings templates card) were
  tuned and tested against three screen profiles only. D-155, b1239e0 and 8b73c78 each found a real
  defect at a width nobody had measured, so expect more of that shape rather than a settings flip.

- [T-18] **Chinese localisation.** Backlogged. Nothing is localised today: user-facing strings are
  hardcoded English at the call site, and `DateFormatters` uses fixed formats. Two known hazards
  already documented in this repo — `Calendar.current` is not Gregorian everywhere (a `yyyy-MM-dd`
  storage key becomes `2569-…` under a Buddhist calendar), and weekday symbol arrays are indexed by
  weekday number rather than by `firstWeekday`. Both bit us before; both get worse with a second
  locale.
  **Scoped 2026-08-24; no code changed.** Measured with
  `python3 count_strings.py` (comment-stripped regex over `Text(`/`Label(`/`Button(` &c., the
  `.navigationTitle`/`.help`/`.accessibilityLabel` modifiers, `return "…"` display copy, and
  labelled `title:`/`message:`/`subtitle:` arguments): **~2,000 hard-coded call sites, ~1,233 unique
  strings, ~4,660 English words** across `macOS` (848) / `iOS` (707) / `Shared` (271) /
  `Services` (188) / `Models` (68). Infrastructure is **zero** — no `.strings`, `.xcstrings` or
  `.lproj` anywhere, `knownRegions = (en, Base)`, zero `NSLocalizedString` / `String(localized:)` /
  `LocalizedStringKey`. 250 of the unique strings carry `\(…)` interpolation, and 57 do English
  pluralisation inline as `\(n == 1 ? "" : "s")` — those are the restructuring cost, not the
  translation cost. `CadenceTests` holds **342** `== "Capitalised copy"` assertions that pin English
  literals; they are the loudest thing a translation breaks.
  **Storage boundary (do not cross):** `DateFormatters.ymd`, every `dateKey`, `weekKey`, and
  `TaskSectionDefaults.defaultName = "Default"` are storage. The last one is the sharp edge — it is
  the default value of the persisted `AppTask.sectionName` *and* the subject of
  `TaskSectionConfig.isDefault`'s `caseInsensitiveCompare`, so it is a display string that is also a
  comparison key. Translating it silently orphans every existing task's column.
  Two latent defects found while scoping, both **already wrong today** and neither Chinese-specific:
  - `DateFormatters.longDate` / `shortDate` / `fullShortDate` / `dayOfWeek` / `monthAbbrev` are the
    only fixed-format formatters in the file that are **not** locale-pinned, while `monthYear`'s doc
    comment states pinning as the repo's rule. Verified against Foundation: on a `zh_Hans_CN` device
    `"EEEE, MMMM d"` already renders `星期一, 八月 24` and `"EEE"` renders `周一` — half-translated
    output beside English chrome, which is the exact outcome `monthYear` was pinned to prevent.
  - `MonthCalendarPanel` (`Shared/Components/CadenceDatePicker.swift`) hardcodes
    `["Su","Mo","Tu","We","Th","Fr","Sa"]` and derives its leading blanks from
    `component(.weekday,…) - 1`, i.e. Sunday-first unconditionally — it ignores `firstWeekday`. Its
    sibling `CadenceScheduleSupport.weekdaySymbols` rotates by `firstWeekday` over
    `calendar.shortWeekdaySymbols`, and its doc comment records that exact skew shipping in Germany
    and Saudi Arabia. So the two shared month grids already disagree in Monday-first regions, and on
    a Chinese device the iOS grid reads `周日 周一…` while the macOS picker reads `Su Mo…`.
  Not a hazard after all: the `Calendar.current`-is-not-Gregorian storage risk this ticket names is
  contained — `%04d-%02d-%02d` key derivation exists in exactly two files and both route through
  `DateFormatters.storageCalendar`, and `zh_Hans_CN` is Gregorian and Sunday-first anyway.
  Also out of scope by decision: `CadenceMCPServer` / `Services/MCPReadOnly` strings are a
  machine-facing protocol surface and must stay English.

  **The two date defects are fixed and pushed (`c09f67d`); the rest stays backlogged.** Six
  fixed-format formatters are now locale-pinned — `dayNumber` was the sixth, missed by the original
  count and the same class, since numerals follow the locale too. And both month grids read one
  function, `CadenceScheduleSupport.weekdaySymbols` / `leadingBlankCount`, with language pinned and
  **week start honoured from `firstWeekday`** — that is a real preference, not a language one.
  Three mutations killed at 0 compile errors each; 2480 passed / 0 failed.
  **This inverts when localisation actually happens**, and both doc comments say so: the pins come
  off and the fixed patterns must become `setLocalizedDateFormatFromTemplate` or `Date.FormatStyle`,
  because idiomatic zh is `8月24日` rather than a translated `MMMM d`.

- [T-274] **Importing a Cadence archive.** [[T-19]] shipped the export and deliberately stopped
  there: an unverified restore is worse than none, because it invites the user to trust it.
  `CadenceDataExportService.decode` already returns a `CadenceArchive`, and
  `CadenceDataExportSurfaceTests.theArchiveRoundTripsThroughJSON` proves encode → decode → equal, so
  the *parsing* half is done and tested. What is not decided, and what makes this a design ticket
  rather than a loop over twenty arrays:
  1. **CloudKit.** The store is `.private("iCloud.com.haoranwei.Cadence")`. An import is not a local
     write — every row inserted is uploaded to every other device, so "restore my backup" on one
     device is "push 4,000 rows at the others" from theirs. A restore has to state whether it
     targets the syncing store at all, or whether it goes through the `CADENCE_LOCAL_STORE_ONLY`
     path and asks the user to re-enable sync afterwards.
  2. **Identity.** Records carry their original `id`s. Re-inserting them means the merge policy
     decides which copy of a row wins, and nothing in the app currently reasons about that. The
     three plausible modes — replace the store, merge by id, import as copies with fresh ids — have
     different answers and only one of them can be the default.
  3. **Referential integrity.** Relationships are stored as id references, so an import is a
     two-pass rebuild: insert every row, then wire every reference. A reference to a row the archive
     does not contain (a hand-edited file, or an archive from a newer `formatVersion`) has to fail
     loudly rather than silently produce an orphan — `DataIntegrityRepairService` is the repair pass
     for stale relationships, not a substitute for validating input.
  4. **The legacy note models.** `DailyNote` / `WeeklyNote` / `PermNote` / `EventNote` / `Document`
     are exported because a pre-migration archive is the only copy of them. Importing one into a
     store where `NoteMigrationService` has already run would re-create rows that were already
     folded into `Note`, i.e. duplicate every note. The importer has to run the migration after the
     insert, or refuse those tables when the destination has already migrated.
  Do **not** ship this behind a confirmation and call it verified. The bar is a test that imports an
  archive into a container and asserts the graph came back — every foreign key resolved, counts
  equal, and a second import of the same file changing nothing.
- [T-20] **Settings UI for macOS**, and possibly iPad/iOS after. iOS Settings was rebuilt in
  `775833d` — category list plus value rows — and macOS has not caught up; it is the older
  twelve-category shell. Bringing macOS to the same vocabulary would also settle which of the two is
  the reference.

## Done


- [T-276] **iOS offered "Focus" on a settled task; macOS hid it — DONE, one predicate in `Shared/`.**
  `CadenceFocusSupport.canFocus(_ task:)` (`Shared/CadenceFocusPlanningSupport.swift`) and
  `canFocus(_ bundle:)` (`Shared/CadenceFocusBundleSupport.swift`) are now the app's only spelling of
  "can this be the subject of a focus session", and all five entry points read them:
  `MacTaskRow.focusButtonSlot`, `iOSTaskRowContextMenu.focusMenuItem`,
  `iOSTaskDetailSheet.focusSection`, `iOSCalendarBundleDetailSheet.focusSection`, and
  `TaskBundleDetailPopover.actionDeck`'s **Start Focus**.

  **Which side won, and why it is not "match macOS reflexively".** The predicate was already the
  app's stated position, in `Shared/`, on both platforms: `readyTasks` — the only thing either Focus
  picker lists tasks from — has always filtered by exactly `!isDone && !isCancelled`. iOS was
  diverging from *itself*, not merely from the Mac: the Focus screen refused to list a settled task
  while a menu two taps away handed one to it, and the handoff resolves, so the minutes really
  landed in `actualMinutes` and from there in `area.loggedMinutes` / `project.loggedMinutes`, which
  an hours-based `Goal` reads.

  **The bundle half was decided separately and did not fall out of the task half by analogy.** A
  block whose members are all settled is not "a settled task, ×N" — it is a container with nothing
  left in it, which is what `TaskBundle.isCompleted` already means and what
  `CadenceFocusPickItem.filtered` had excluded since before there was an entry point to gate. Both
  clauses are load-bearing and neither implies the other: `sortedTasks` filters cancelled members
  out, so an **empty** block and an all-cancelled block are both `isCompleted == false`, and running
  the clock against one distributes its minutes across nothing (`distributeMinutes` returns early on
  an empty array) — the only place in the app where measured time is silently discarded.
  `canFocus(_ bundle:)` is therefore `!sortedTasks.isEmpty && !isCompleted`, which is exactly
  `!activeTasks.isEmpty`, which is what the Mac's block inspector had hand-spelled as its
  `isDisabled` all along; that call site now reads the shared predicate instead of being a correct
  fifth copy.

  **Shape of the gate differs by surface, deliberately.** The three iOS entries and the Mac's hover ▶
  are *absent* on an ineligible subject — a menu is a list of things you can do, and the Mac already
  drew a `Color.clear` spacer. The Mac's block inspector stays *disabled* rather than absent: it is
  one of a pair of equal-width buttons and removing it would stretch "Complete" across the deck.

  Pinned by `FocusSubjectEligibilityTests` (the predicate, both halves, plus an assertion that both
  pickers offer exactly what it allows) and `FocusEntryGateCallSiteTests` (five brace-matched
  call-site scans) in `CadenceTests/FocusPickerPlayControlTests.swift`. Every one was mutation-tested
  and every mutation failed the test named for it.

- [T-225] **An agent overwrote another agent's simulator app-group data — DONE, `scripts/simulator-claim.sh`.**
  During `0332255` a build was installed on an iPad another agent had booted between the device
  listing and the boot attempt, replacing its `Application Support/Cadence`. No repo damage, but it
  invalidated that agent's seeded state mid-run. Same family as [[T-179]] and [[T-204]].

  **Two independent mechanisms make the collision possible, and the fix needed both.** Measured on
  the live fleet before writing anything: Cadence's store is *not* in the app's own data container.
  `CadenceStoreSupport.sharedStoreDirectoryURL` prefers the **app group**, which on a simulator is
  one device-wide directory —
  `.../Devices/<udid>/data/Containers/Shared/AppGroup/AF3C0EF3-…/Library/Application Support/Cadence/`,
  found holding a 491 KB `default.store` with a 3.1 MB `-wal` written two minutes earlier by a
  sibling. It survives reinstall and is shared by every install of the bundle id. So (1) `install`
  replaces the other agent's build, and (2) `launch` puts two writers on one SQLite file. A per-agent
  store id alone cannot fix (1); a lock alone leaves (2) live the moment the lock is wrong.

  **What was built.** `scripts/simulator-claim.sh`, the simulator's `test-host-lock.sh`:
  - `claim <id> [timeout]` — atomic `mkdir` per **device** under `$TMPDIR/CadenceSimClaims/<udid>.claim`,
    45-minute lease, `$PPID` + id + `since` recorded. Several booted devices means several agents
    proceed in parallel, each on its own; one device means the second agent **waits**. It never
    creates or clones a device: `boot` exists, boots a *stock* device only when the fleet is empty,
    under its own serialising lock, and requires `--apply`.
  - `install` / `launch` **refuse** without a claim (exit 3, message on stderr — the first draft
    printed it on stdout, where the caller's `u=$(require_claim …)` swallowed it whole).
  - `launch` passes `SIMCTL_CHILD_CADENCE_UI_TEST_STORE_ID=<id>` and
    `SIMCTL_CHILD_CADENCE_LOCAL_STORE_ONLY=1`, so `PersistenceController.resolvedStoreURL` redirects
    to `<data container>/tmp/CadenceUITestStores/<id>/default.store` and the shared app-group store is
    never opened. Same lever `run-macos-app.sh` pulls on the Mac; `simctl launch`'s own help documents
    the `SIMCTL_CHILD_` prefix.
  - Device-touching commands report and act only with `--apply`, as `agent-cleanup.sh` does.
    `claim`/`env`/`renew`/`release` touch nothing but `$TMPDIR`.
  - By construction there is **no** `create`, `erase`, `shutdown`, `delete` or `privacy` subcommand,
    and nothing anywhere kills a process by the name Cadence. `release` frees only a claim recording
    your own id, and leaves the device booted.
  - Reclaim is on the **lease**, not pid liveness — the `test-host-lock.sh` lesson, since an agent's
    acquiring shell is dead by the next command — and an expired lease is still refused while a live
    `simctl` names that udid.

  **Concurrency evidence** (fake `simctl` via `CADENCE_SIMCTL`, so the shared fleet was never
  touched; the fake resolves the store by the same rule `PersistenceController` does):
  - *Baseline, the failure itself.* Two agents, one device, no claim: the installed bundle ends as
    `buildB.app` and the single shared app-group `default.store` reads "written by build: …buildB.app".
    A's build and A's data are simply gone. Private stores created: 0.
  - *One device, two agents starting together.* Exactly one `UDID=…`; the other prints
    `TIMED OUT … Do not install anyway`. Its `install --apply` then exits **3** with the refusal, and
    its `release` does **not** free the winner's claim.
  - *Handoff.* Winner releases at t+3 s; the waiter acquires `after 5s`.
  - *Two devices, two agents.* Different udids, both installs succeed, and the two stores land at
    `…/000001/Data/tmp/CadenceUITestStores/agentB/` and `…/000002/…/agentA/`. App-group
    `default.store` files created: **0**.
  - *Defence in depth.* Two agents forced onto **one** device with the claim bypassed but the env
    kept: two private stores, app-group `default.store` count still **0**.
  - *Hammer.* 8 agents, 2 devices, launched together: exactly 2 winners, exactly 2 claim directories,
    distinct owners, no device claimed twice.
  - *Lease.* A short `CADENCE_SIM_LEASE` is floored at 2700 s unless `CADENCE_SIM_CLAIM_TESTING=1`
    (the guard `test-host-lock.sh` had to grow). With the flag: an expired claim is refused twice
    while a process whose command line names `simctl … <udid>` is alive, then reclaimed once it exits.
  - *Real fleet, real `simctl`.* `status` → `free  iPhone 17 Pro (7B642065-…)`; claim, `env`,
    `install` and `launch` **without** `--apply` (both printed `would run:`), release. The sibling's
    `default.store` / `-shm` / `-wal` kept byte-identical sizes and timestamps, and the booted count
    stayed 1.

  `agent-cleanup.sh` gained a claims section: it reclaims only claims naming a device that is **no
  longer booted** (verified: a live sibling's claim on the real booted device survived `--apply`,
  the dead one did not). An expired lease on a *booted* device is reported and left alone — deleting
  it from a `SubagentStop` hook would be this same ticket one step earlier.

  Rule recorded in `AGENTS.md` under the simulator bullet. **Deliberately not done:** no per-agent
  device clones (that is how the pool went 3.8 GB → 7.7 GB), no change to the app's Swift sources, and
  no wrapper around `mcp__Claude_Code_iOS_Simulator__build` / `control` — those are outside the repo,
  and an agent driving a device through them still holds the claim that keeps the *install* exclusive.


- [T-235] **What a widgets-scheme baseline measures: the same two targets the app scheme already
  builds.** Measured 2026-08-25 against `4f8546f` bytes (rsync'd tree, siblings' in-flight files
  restored to HEAD), two cold builds into separate private DerivedData paths.
  `-scheme CadenceWidgets` → **615** tasks `in target 'Cadence'` (534 `SwiftCompile`) and **115** in
  `CadenceWidgets` (56 `SwiftCompile`), producing `Cadence.app` with
  `Contents/PlugIns/CadenceWidgets.appex` embedded, 52 s. `-scheme Cadence` → the **same** per-target
  totals and a task-type histogram that `diff`s clean against it, 56 s. Both 0 warnings, 0 errors
  (`grep -c "warning:"`, `grep -c "error:"`, no path filter).
  Cause, from `project.pbxproj`: the `Cadence` target carries a `PBXTargetDependency` on
  `CadenceWidgets` plus an **Embed App Extensions** phase, so the extension is built either way; the
  widgets scheme merely also names `Cadence.app` in its `BuildActionEntries`. So the ticket's premise
  was right and understated — the widgets scheme is not a widget-only measurement, *and* the app
  scheme was never missing the widget target. For contrast, measured the same way:
  `-scheme CadenceMCPServer` builds `CadenceMCPServer` + 20 SPM targets (`MCP`, `NIOCore`, `Atomics`,
  `DequeModule`, …) and **neither** app target, 25 s — that one is a genuinely separate measurement.
  Sentence written into `AGENTS.md` beside the warning baseline: the baseline is three targets and
  **two** builds. Documentation only; no `.swift` touched, so no test run.

- [T-238] **Recognition procedure for an early test-host exit — written as a family, not a fourth
  note.** `AGENTS.md` gained one section, "Red Runs That Are Not Regressions", a four-row table
  discriminating T-117 (frozen log, 0.0% CPU), T-209 (macro-plugin `error:` storm), T-236
  (four-figure failure count, two host PIDs) and this one (a handful of `0.000 seconds` failures in
  suites the change cannot reach, one host PID). Each row is tell → cause → the command that
  confirms it. Detail stays in the existing `AGENTS.md` bullets and the evidence stays here; the
  table points at both rather than restating them.
  Two things measured 2026-08-25 so the row is applicable rather than plausible. **The
  `xcresulttool` invocation**: on Xcode 26.6 (build 17F113) `get object` and `formatDescription` are
  deprecated, and the working form is
  `xcrun xcresulttool get test-results summary --path <dd>/Logs/Test/Test-Cadence-*.xcresult`, whose
  JSON carries `result`, `statistics`, `topInsights` and `testFailures` — run against a live sibling
  run's bundle, which reported `"result" : "Passed"`, `"passedTests" : 2578`. **The host-PID tell**:
  `grep -oE "My Mac - Cadence \([0-9]+\)" <log> | sort -u` returns exactly one line on a healthy run
  (verified on a sibling's `mac-test.log`), so ≥2 is the T-236/T-238 signature and needs no counting
  of failures.
  Left undecided deliberately: whether agent runs should default to `-parallel-testing-enabled NO`.
  Measuring that costs the shared test host for two full suite runs, which is the resource three
  agents were queued on at the time; it is a scheduling decision, not a blocker for the rule.

- [T-209] **Closed as documented, and *not* closed by `scripts/test-host-lock.sh`.** The ticket's
  deliverable was always the `AGENTS.md` line, and it is now row two of "Red Runs That Are Not
  Regressions". The tempting close — "`1e6e7da` hardened the lock, so parallel runs are handled" —
  is wrong and worth recording as wrong: the lock serialises the macOS **test host**, whereas the
  macro-plugin failure (`external macro implementation type … could not be found`,
  `swift-plugin-server could not be loaded: Resource temporarily unavailable`) happens in the
  **compile** phase, which every plain `xcodebuild build` also runs and which nothing serialises.
  Three builds were run for T-235 above while a sibling held the test-host lock, entirely legitimately
  — that is the gap in one sentence.
  What the lock did remove is the *test-run-versus-test-run* instance of it (`e1c098a`, `1e6e7da`),
  which is why the signature is now most likely to appear during a build. `AGENTS.md` already carried
  half of this rule — `build.db is locked` / `unable to spawn swift-frontend` — filed under "check the
  log says which tree it built", where nobody looks when staring at 650 `error:` lines; that sentence
  now points at the table instead of duplicating it. The discriminator is
  `grep "error:" log | grep -Evc "macro\|plugin"` → `0` (verified on this machine's BSD grep against a
  synthetic log holding two plugin errors and one real one: it returns 1, i.e. it does find a real
  error when there is one).

- [T-15] `4f8546f` **Several dark palettes.** Shipped as decided: **accents only**, dark-only,
  three sets — **Cadence** (the values the app shipped with, and the standard one), **Ember**
  (warm) and **Glacier** (cool) — chosen in Settings → **Appearance** on both platforms through one
  shared `CadenceAccentPalettePicker`. The near-black neutrals, the marker pen, the `onColor*`
  family, the overlays, the shadows and the radius scale did not move and cannot: they are still
  `static let`. `preferredColorScheme` is still a hardcoded `.dark`; no light value was added
  anywhere.

  **The mechanism**, all of it in `Theme.swift` because `CadenceWidgets` takes its sources by
  explicit reference and a new file under `Shared/` would not compile for that target:
  `CadenceAccentPalette` (six hex strings, name, one-line description; `.standard` is the set every
  compile-time literal mirrors), `CadenceAccentResolution` (one palette resolved once into `Color`s
  **and** the three accent `NSColor` mirrors, so `Theme.blue` stays one property load), and the
  `@Observable` `CadenceAccentPaletteSelection`. The observation is the live-repaint mechanism, not
  decoration: every accent accessor funnels through `resolution`, so a view reading `Theme.blue`
  anywhere in its body registers a dependency and repaints on a switch. `.id(paletteID)` on the
  root was rejected — it repaints by discarding every `@State` in the app, including the Settings
  screen the user is standing on.

  **What made this wider than `Theme.swift`, and the thing to remember:** an accent read into a
  `static let` freezes on first access and then draws whichever palette happened to be active the
  first time that surface appeared — silently, no diagnostic, wrong colour only where nobody looked.
  Three declarations were in that shape and were converted to computed: `CadenceColorPalette`'s
  `areaDefault` / `projectDefault` / `colors` / `sectionColors` / `destinationTints`,
  `CadenceTodayPresentationSupport.completedSectionAccent`, and `MarkdownStylist`'s `blueColor` /
  `greenColor` / `redColor`. `destinationTints` mattered most: frozen, a destination's own
  `defaultColorHex` falls out of the menu that edits it, which is T-245 arriving by a different
  road. `CadenceAccentStorageSweepTests.noStoredDeclarationAnywhereInTheAppFreezesAnAccent` now
  sweeps all 512 files under `Cadence/` for both shapes — a direct read and an array literal — with
  no allowlist, and a self-check pins both needles.

  **Widgets: shipped, and it was cheap.** The selection goes to the app-group suite
  (`cadence.appearance.accentPaletteID`), which `CadenceWidgetRefreshCenter` already crosses, and
  selecting a palette forces a timeline reload. Proved by value rather than asserted in a comment:
  a probe written through the store's own suite is read back through a freshly constructed
  app-group `UserDefaults`.

  **User-owned `colorHex` is untouched.** A switch changes what a *new* list/tag/habit/section is
  seeded with and what the swatch menus offer; it rewrites nothing stored, and
  `CadenceColorPalette.offered(_:from:)` keeps a stored hue selectable after its palette stops
  offering it. Pinned by `aStoredColourSurvivesAPaletteSwitchAndStaysSelectable`.

  Two existing tests were restated rather than relaxed, and the reason is worth carrying: a `@Model`
  `colorHex` default is a compile-time literal in `Models/` (which `CadenceMCPServer` compiles and
  `Theme.swift` is not part of), so it can only ever mirror **one** palette. Those assertions now
  name `CadenceAccentPalette.standard` explicitly instead of reading whatever is active. Change the
  standard blue and they still fail.

  Left undone, deliberately: the AppKit markdown editor repaints on its next restyle rather than
  instantly, because it draws through `MarkdownStylist` and not through a SwiftUI body — its three
  accent colours are computed so that restyle is *correct*, which is the part that matters. If an
  instant repaint there is ever wanted, that is a notification the `NSViewRepresentable` observes,
  not a change to the palette mechanism.

- [T-258] `aa85e1b` **Cmd+K draws the Notes row in a different glyph than the sidebar does.** The last
  hand-typed per-destination fact in `GlobalSearchPageDefinition`. T-244 made the definition carry
  a `CadenceFeatureDestination` and derived the tint, the selection it opens and its Settings →
  Sidebar toggle from it; `icon` was left stored, and eight of the nine happen to equal
  `CadenceFeatureDestination.systemImage` already. The ninth does not: the palette says `doc.text`
  for Notes, the sidebar says `note.text`. Same defect class as T-244 one layer up — two lists
  answering one question about a destination, agreeing until one moved. The fix is one line
  (`icon: feature.systemImage`, deleting the stored field), deliberately not taken with T-244
  because it changes a glyph nobody asked about.
  (The `doc.text` on the **event-note** result rows in `GlobalSearchIndexSupport` is unrelated —
  those are note rows, not the Notes destination, and stays.)
  **Shipped.** The stored field is gone and `icon` is
  `feature.systemImage`, so the palette and the sidebar cannot disagree again; the nine `.init`
  entries lost their `icon:` argument. Notes was checked to be the **only** disagreement rather
  than assumed: the other eight stored glyphs were compared against `systemImage` one by one before
  the field was deleted, and all eight matched — which is exactly why deleting the field mattered
  more than editing one string, since eight silently-correct copies is the state this one was in
  before somebody moved the sidebar's glyph.
  `GlobalSearchCommandDefinition.icon` is deliberately **left stored**: five of its six do equal a
  destination glyph, but `.newTask` is `plus.circle.fill` against Tasks' `checklist`, because a
  command's glyph names a verb and not a page. Its `tintSource` exists for the tint alone and must
  not be reused as an identity. Pinned by
  `GlobalSearchDestinationTintTests.everyPageRowDrawsTheSidebarsGlyphForItsDestination`, which
  asserts on the row `pageResults` actually produces — not on the catalog and not by reading the
  source, so a stored `icon` reintroduced anywhere in that file still fails it. Mutation-checked:
  reverting the file turns that test red, exit 65 with 0 compile errors.

- [T-275] `aa85e1b` **`SectionEyebrowLabel` exists to stop exactly this, and nine call sites don't use it.**
  Found by a [[T-123]] grep sweep for the shape the component's own doc comment says it
  consolidates — `.font(.system(size: 10, weight: .semibold))` plus a dim tint plus
  `textCase(.uppercase)` — hand-rolled instead of the shared component. All nine are plain
  section/row eyebrows with nothing about them that would justify a bespoke spelling:
  - iOS: `iOSFeatureDetailViews.swift:340` ("Next", `.kerning(0.6)`), `iPadTodayScheduleViews.swift:463`
    ("Ready to Schedule", `.kerning(0.7)`).
  - macOS: `SchedulePanelShellViews.swift:32` ("Today", no kerning), `TaskBundlePickerSupportViews.swift:196`
    (`resultSectionLabel`, no kerning), `FocusPickerSupportViews.swift:24` ("Ready to focus", no
    kerning), `FocusSidebarSupportViews.swift:39` (`sidebarLabel`, no kerning),
    `FocusChromeSupportViews.swift:13` (`eyebrow` parameter, no kerning), `TasksPanel.swift:542`
    (`overdueSectionHeading`, size **11** not 10, `.kerning(0.8)` applied to the whole `HStack` —
    title and count both — not just the label), `ListNotesViewSupportViews.swift:73` (section
    title, tint `Theme.muted` — the only one of the nine that also disagrees on **colour**, not
    just kerning).
  `SectionEyebrowLabel` itself is `.kerning(0.8)`. Six of the nine specify no kerning at all (system
  default 0); the other three specify 0.6, 0.7, and 0.8 — one matches by coincidence, two don't.
  Same shape `e181dea` fixed for destination tints — independent hand-typed copies of one value
  drifting apart — for a label style instead of a colour. **Gratuitous, not deliberate**: nothing
  about any of the nine sites needs a size, weight, tint or kerning different from the shared
  label; several sit in files that use `SectionEyebrowLabel` correctly elsewhere for the identical
  visual role.
  **Shipped, and it was twenty, not nine.** Re-grepping with no path
  filter found the ticket's nine (three of which had moved: `TasksPanel.swift:542`'s heading is
  `CadenceTodayOverdueSummaryHeading` in `Shared/Components/CadenceTodayOverdueSummaryCards.swift`
  now) plus eleven more the original sweep's uppercase-only pattern missed — seven byte-identical to
  the shared spelling (`CreateGoalSheet.fieldLabel`, `ListEditorSupportViews`,
  `GlobalSearchOverlayShellViews`, `HabitsFormSupportViews.HabitFormLabel`,
  `NoteReferenceSupportViews.ReferenceSection`, `CadenceSettingsSharedViews`,
  `HabitProgressViews.HabitInfoCard`), one already-uppercase string
  (`ListDetailSupportViews`'s `"\(count) COMPLETED"`, found by kerning rather than by case), one
  with no kerning at all (`GoalsSupportViews.GoalSectionHeading`), and two at `.bold`
  (`SettingsTemplatesSection`, `Shared/Components/CommitmentSharedViews.CommitmentGroupHeader`).
  All twenty read `SectionEyebrowLabel` now.
  **No new parameter was needed.** `tint` already existed and took the one site that legitimately
  differs on colour (`ListNotesViewSupportViews`, `Theme.muted` — its header is a control, not an
  inert label). Three sites changed a measurement on purpose: the overdue summary heading drops
  from the app's only 11pt eyebrow to 10 and its count now reads `SectionEyebrowLabel.fontSize`
  (the rule `CadenceBoardColumnHeaderMetrics` and `CadenceTaskGroupHeadingMetrics.countSize`
  already state), and the two `.bold` labels become `.semibold` while their counts keep `.bold` —
  the split `CadenceTaskGroupHeading` already draws, since weight is what demotes a number from
  its label.
  **Two shapes deliberately not shared.** The 9pt sub-label tier (`TaskInspectorGroupLabel`,
  `SidebarComponents`' context header, `SettingsViewSupport`'s rail group,
  `TaskInspectorWorkflowSupportViews.sectionLabel`, `EstimatePickerControl`,
  `AIActionsSupportViews`, `CadenceCalendarPicker`, `ContainerPickerSupportViews`) is a second,
  internally consistent tier — most of it already routed through named metrics — and folding it
  into a 10pt component would be a size decision dressed as a refactor. And the calendar **weekday
  column header** (`CalendarPageMonthSupportViews`, mirrored by `iOSCalendarTimelineViews`) is a
  date label under a day number, tinted `isToday ? Theme.blue : Theme.dim` and kerned 0.5; the two
  weekday headers have to agree with **each other**, which is a different question, and pointing
  both at `SectionEyebrowLabel` would answer it by accident. Filed as [T-277].
  Pinned by `CadenceSectionEyebrowConvergenceTests` in `CadenceSharedBoardChromeTests.swift`. The
  load-bearing assertion is the **negative** one: a sweep of all 509 files under `Cadence/` for the
  hand-rolled *shape*, which cannot be satisfied by the shared spelling surviving somewhere
  unreachable — the failure mode that has twice let a source scan pass over a restored bug here.
  Measured 26 hits before, 1 (the allowlisted weekday header) after, and the allowlist entry has
  its own test so it cannot quietly go stale. Mutation-checked: re-forking one call site turns
  `noSurfaceHandRollsTheSharedEyebrow` and `theConvertedSitesCallTheSharedLabel` red, exit 65 with
  0 compile errors.
  **Not screenshotted.** [[T-123]] item 2 asks for macOS visual changes to be looked at rather than
  argued, and this touches sixteen macOS surfaces. Fifteen of the twenty conversions are provably
  pixel-identical (the modifier chain they replaced is the component's own), and the five that are
  not are listed above by name and figure. The three that shift a measurement — the overdue summary
  heading, `SettingsTemplatesSection`'s field label, `CommitmentGroupHeader` — are the ones worth a
  look before this is called finished, per [[T-123]] item 2's screenshot rule.

- [T-240] `902b386` **CLOSED.** `accountDeletionIsExplicitInSettingsAndReviewDocs`
  now brace-matches `deleteCadenceData()`'s body with `cadenceFunctionBody(_:in:)` instead of ending
  the range at the next `private struct SettingsPrivacyStatementSection`. Proved both ways: renaming
  that struct failed the test before the change and does not after it, and moving the
  `PrivacyDataResetService.deleteCadenceDataAndLocalArtifacts` call out of the function into a
  sibling in the same file — which the old range would have swallowed — fails it now. Original
  entry follows.

  **A test bounds a `#require`'d source range by searching for another file's declaration
  line.** `AppStoreReviewReadinessTests.accountDeletionIsExplicitInSettingsAndReviewDocs` locates the
  region it wants to assert over by finding a literal landmark in a *different* file. T-220 made the
  landmark less brittle (the struct name rather than a `"\n}\n\nprivate struct …"` sequence), but the
  shape remains: rename `SettingsPrivacyStatementSection` and the test fails as a `#require`
  precondition rather than as a readable assertion, so the message tells you nothing about what broke.
  That is the same "fails for a reason unrelated to its subject" family as T-233 and T-227. Worth
  replacing the source-range search with something that cannot silently stop matching — assert over
  the whole file, or have the view expose the fact under test as a value the test can read directly.

- [T-262] `45ad9f0` **Five more `@State` colour seeds still hand-type `#4a9eff` / `#6b7a99`.** Out of T-246's
  scope, which named three palettes and not these. Each is a pure substitution — the literal
  already equals the token it should read — which is precisely why they survive:
  `macOS/Sheets/CreateContextSheet.swift:11`, `macOS/Sheets/CreateGoalSheet.swift:24` and `:47`,
  `macOS/Views/HabitsFormSheets.swift:14` (all `#4a9eff` → `CadenceColorPalette.areaDefault`), and
  `macOS/Views/HabitsView.swift:63` (`#6b7a99` → `TaskSectionDefaults.defaultColorHex`, which is
  what that neutral is). Two adjacent things that are **not** the same finding and must not be
  swept in with them:
  - `Cadence/Models/*.swift`'s `colorHex` defaults (`Area`, `Context`, `Goal`, `Habit`, `Project`,
    `Tag`, `AppTask`) genuinely cannot read `Theme`: `CadenceMCPServer` compiles `Models/` and not
    `Theme.swift`. Same reason T-166 left `TaskSectionDefaults.defaultColorHex` alone. Leave them.
  - `Services/CadenceUITestSupport.swift` seeds fixtures with `#5AA2FF`, `#FFB84D` and `#4ECB71`.
    The first two are the *drifted* sidebar tints T-166 deleted — they now exist nowhere else in
    the app. Harmless as fixture data, but a UI test asserting on a colour would be asserting on a
    hue the product no longer has.

  **Shipped.** All five substituted; `Cadence/macOS/` now contains no
  colour literal at all, which is what the new `CadenceSeedColourSourceTests` pins — a per-file list
  only guards the sites this ticket happened to find, so the load-bearing assertion walks the whole
  216-file tree and needs no allowlist (`Theme.swift` and the swatch arrays both live under
  `Shared/`). Two departures from the ticket's own prescription, both deliberate:
  - The four `#4a9eff` seeds read **`Theme.blueHex`**, not `CadenceColorPalette.areaDefault`. That
    constant is documented as "`Area.colorHex`'s model default", and these seed a *Context*, a
    *Goal* and a *Habit*. Reading it would assert a relationship that does not exist and would drag
    three unrelated sheets along if the Area default ever moved off blue. `areaDefault` is itself
    `Theme.blueHex`, so the resolved value is identical either way.
  - `#6b7a99` gets **no new `Theme` token**. It reads the existing
    `TaskSectionDefaults.defaultColorHex`, whose home has to be `Models/` because `CadenceMCPServer`
    compiles `Models/` and not `Theme.swift`. A `Theme.neutralHex` beside it would be a second
    spelling of a hex the app already publishes — the drift T-166 deleted, not the fix for it. A
    test asserts `Theme` has not grown one.
  The models stay literals as the ticket says, and the enforcement a token read would have given
  them is now a test: `theSeedsMirrorModelDefaultsThatCannotReadTheToken` fails if `Theme.blueHex`
  moves without `Context`/`Goal`/`Habit`/`Area` following it.

- [T-253] `159af9f` **macOS Settings → Reminders never re-derives authorization after it first appears, and
  it is the surface most likely to be on screen when authorization changes.**
  `macOS/Views/SettingsRemindersSection.swift` has `.onAppear { refreshAuthorizationState() }` and
  nothing else, while macOS's Inbox (`TasksListView`) carries **both** `.onAppear` **and**
  `.onChange(of: scenePhase)`. The asymmetry matters on macOS specifically: revoking in System
  Settings does **not** terminate the app the way iOS does (measured — iOS kills Cadence on both
  grant and revoke, so its surfaces always re-read from a fresh process), so a user who follows this
  card's own **Open Reminders Settings** button, revokes, and comes back lands on a view that never
  disappeared and is still claiming "Apple Reminders connected" over a stale list. `iOSRemindersSettingsSection`
  has the same single hook; it is far less exposed for the termination reason above, but the two
  Settings sections should match the two Inboxes rather than each other. Not fixed here because
  macOS TCC cannot be driven without touching the host machine's real Reminders permission, so the
  fix would ship unverified — see the note in [[T-21]].

- [T-254] `159af9f` **macOS's Inbox reminders section is the only one of the four reminders surfaces that does
  not read `RemindersConnectionState`.** `InboxAppleRemindersSectionView`
  (`macOS/Views/InboxSupportViews.swift`) branches `if isAuthorized { rows } else {
  AppleRemindersAccessRow(isDenied:) }` and hand-writes its own copy — "Reminders access is off" /
  "Show Apple Reminders in Inbox", "Connect" / "Open Settings" — while Settings on both platforms and
  the iOS Inbox all read `state.accessTitle` / `accessMessage` / `accessAction`. Two consequences.
  The copy can drift, which is the standing no-near-copies rule. And the **branch order differs**:
  the shared resolver puts `isDenied` ahead of `isAuthorized` precisely so a live denial beats a
  stale authorized snapshot, and this view puts `isAuthorized` first, so in that window macOS's
  Inbox draws stale reminder rows with completion buttons that no longer write while macOS's
  Settings, one category away, says access is denied. Fold it onto `RemindersConnectionState` the
  way `iOSInboxRemindersSection` already is.

  **Partly shipped.** `2f018a4` fixed the two concrete symptoms this ticket named —
  `InboxAppleRemindersSectionView` now checks `isRestricted` ahead of `isDenied` (the
  branch-order bug) and borrows `RemindersConnectionState.restricted`'s copy (the drift bug) —
  but the structural ask is still undone: the view still carries three hand-derived booleans
  (`isAuthorized`/`isDenied`/`isRestricted`) rather than one `RemindersConnectionState` value,
  the way `iOSInboxRemindersSection` already does. Stays open for that half.

- [T-265] `159af9f` **`RemindersManager.requestAccess()` has a second exit that returns `false` without
  recording a denial — the same doorway [[T-21]] just closed, one branch over.** The
  `guard status == .notDetermined else { refreshAuthorizationState(); return false }` arm is taken
  by every status that is neither `.fullAccess` nor `.notDetermined`. For `.denied` and
  `.restricted` that is harmless, because `isDenied` already reads them from the cached status. For
  anything else it is the dead-button bug again: `resolve(status:)` folds unknown statuses through
  `default` into `.notDetermined`, so the card offers **Allow Access**, the tap takes this arm, and
  nothing changes. Today the only such value is `.writeOnly`, which EventKit does not return for
  reminders — so this is a latent hazard, not a live defect, and it is filed rather than fixed for
  that reason. The cheap version is to set `deniedInThisSession = true` on this arm too, since the
  arm already means "asking cannot help". Related: [[T-256]], which is the same shape for
  `.restricted` — an affordance offered in a state where it cannot work.

- [T-239] `b22a02a` **The note-kind switch is spelled three times, and the three disagree.** Split out of
  [[T-224]]. **Fixed** — corrected from a prior mis-citation of `902b386`, which never touched this
  file; the actual fix is `b22a02a`. `NoteReferencePanelSupport.noteKindDetail(_:)`
  in `Cadence/Services/NoteReferenceSupport.swift` is now the one detail spelling, built on top of
  the existing `noteKindLabel` so the two cannot disagree about the vocabulary, and the two
  full-width rows call it.

  **What each of the three said, because the disagreement is the finding.**
  - `NoteReferencePanelSupport.noteKindLabel` — "Daily note" / "Weekly note" / "Notepad" /
    "List note" / "Event note". Right vocabulary, no room for the detail. Unchanged, and still what
    the three *compact* callers take (the reference panel's pills, the `[[` completion choices,
    `iOSMarkdownReferenceSupport`'s editor sheet).
  - `iOSSearchView.noteSubtitle` — the detail form, and the better half of it: "Daily / <dateKey>",
    "Weekly / <weekKey>", "Event / <eventDateKey>", and a `.list` note's area/project name. But
    `.permanent` read **"Permanent note"** where the tab, `Note.displayTitle` and `noteKindLabel`
    all say "Notepad" — the same class of error as `.meeting.rawValue.capitalized` saying "Meeting",
    and with a functional edge the label version does not have: this string is one of the `fields`
    `CadenceSearchMatcher.matchScore` scores, so the notepad did not match the app's own word for
    it. Its `.list` branch was also `compactMap { $0 }.first`, which accepts a whitespace-only list
    name and renders a blank subtitle rather than falling through.
  - `iOSMarkdownNoteReferenceRow.subtitle` (`iOSMarkdownAccessoryViews.swift`) — **the live bug.**
    `.list` said "Linked note", which names the reference panel's own *Linked Notes* section rather
    than the note, and drops the container. And `.daily` / `.weekly` returned a **bare** `dateKey` /
    `weekKey`. `NoteMigrationService.dailyNote` creates every daily note with `title: dateKey` and
    every weekly one with `title: weekKey`, so `displayTitle` returns that same string — and the row
    draws `displayTitle` directly above `subtitle`. Every daily and weekly row in the markdown note
    picker printed one string twice, one line under the other, for every note of those kinds. Not an
    edge case: it is how those notes are constructed.

  **Resolution.** Search's spelling wins everywhere it disagreed with the row, except `.permanent`,
  where the label's "Notepad" wins over search's retired "Permanent note". One separator for all
  three dated kinds (`/`): the row spelled the event's `·` and search spelled it `/`, and two
  separators inside one list of results is a difference that means nothing. Persisted state is
  untouched — `NoteKind.meeting` keeps its raw value and nothing about `Note.kindRaw` changed.
  Pinned by `CadenceNoteReferencePanelSurfaceTests`: five value assertions on `noteKindDetail`, the
  duplication regression stated as `noteKindDetail(daily) != daily.displayTitle` rather than as a
  literal, the four fallbacks, and a call-site check scoped to the two function bodies with
  `cadenceFunctionBody` rather than counted over whole files.



- [T-273] **A task on the Calendar Board or the day timeline still cannot be focused on iOS.**
  Fallout scoped out of [[T-266]] rather than missed by it. `iOSBoardTaskCard` and
  `iOSTimelineTaskBlock` both open `iOSTaskDetailSheet`, and that sheet has no Focus action — so
  the *task* half of the handoff is reachable only from a row's long-press menu, while the *block*
  half is reachable from the block's own inspector. The fix is one `iOSActionButton` in
  `iOSTaskDetailSheet`, calling `CadenceFocusHandoffCenter.shared.request(.task(task.id))` and
  then `dismiss()`, exactly as `iOSCalendarBundleDetailSheet.focusSection` does. It was left out
  to keep T-266 to the smallest complete path, not because it is wrong: the inspector is presented
  by a host (`iOSTaskInspectorHost`), so the button has to dismiss *and* the shell has to route
  underneath, and that interaction deserves its own simulator pass rather than riding on another
  ticket's. `FocusHandoffCallSiteTests.bothAffordancesRequestAHandoff` pins the two that exist; a
  third belongs in the same test.
  **Built, verified, and shipped in `9980fe8`**, and built as the ticket describes rather than as a
  second mechanism: one `iOSActionButton` in `iOSTaskDetailSheet.focusSection`, `request(.task(…))`
  then `dismiss()`, no new type and no change to `CadenceFocusHandoff`. The card and the block gain
  nothing of their own — both open this sheet, which
  `CadenceTaskInspectorHostTests.noRowOrCardStillPresentsTheInspector` already pins, so one entry
  reaches both. A `contextMenu` on the two surfaces was rejected: it duplicates a menu at two call
  sites, and `iOSCalendarTimelineViews` carries the `simultaneousGesture` pinch a long-press
  competes with ([[T-243]]). A swipe was rejected for [[T-266]]'s reason, unchanged. The test is
  `everyAffordanceRequestsAHandoff` now — renamed rather than left saying "both" over three — beside
  three new ones pinning that the section is rendered, that the request precedes the dismissal, and
  that both Focus entries read `CadenceFeatureDestination.focus.tint`. That last one is a one-line
  fix riding along: `iOSCalendarBundleDetailSheet` shipped `tint: Theme.amber`, the token
  `defaultColorHex` gives Today and Habits, so two buttons named the same screen in two colours.
  One rough edge left deliberately: the bundle sheet presents this sheet for a member task, and
  `dismiss()` closes only the inner one, so Focus is routed *underneath* a block sheet that still
  needs its own Close. Papering over it means a third observer of `CadenceFocusHandoffCenter`,
  against the "shell routes, Focus screen adopts" division the whole design rests on.

- [T-266] **On iOS the Focus screen is the only way *into* a focus session — for blocks and for
  tasks alike.** [[T-242]] made a `TaskBundle` pickable and runnable in `iOSFocusView`, which was
  the ticket, but macOS reaches a session from three other places: the hover ▶ on `MacTaskRow`
  (`TasksPanelComponents`), `TimelineBundleBlock`, and the Calendar Board's bundle card
  (`CalendarBoardItemSupportViews`). All three go through `FocusManager.startFocus(...)`, whose
  `wantsNavToFocus` flag is what navigates the shell — and `FocusManager` is macOS-only, correctly
  (it is not AppKit-bound, but iOS's screen holds its clock in the already-shared
  `CadenceFocusTimerState`, so un-guarding the singleton would add a second timer authority with no
  reader, not a feature — see the T-242 note in `CLAUDE.md`).
  So this is **not** "lift a guard": giving iOS a "focus this" affordance on a task row or a block
  card needs an iOS-shaped way to say *start this session and take me to Focus*, i.e. a deep link
  or a `CadenceCompactTab` route carrying a `CadenceFocusTarget`, plus a decision about what
  happens to a session already running when a second one is started from elsewhere. Note the phone
  has no hover, so the macOS affordance does not transfer literally; the swipe action and the
  long-press menu on `iOSTaskRow` are the candidates. `iOSCalendarBundleDetailSheet` contains the
  string `Focus` zero times and is the obvious home for the block half.
  **Built, verified, and shipped in `a06ce1c`** (groundwork in `b653a6a`; hardened by a
  regression test in `cfa3b3b`). The route is a value in a one-slot inbox
  (`Shared/CadenceFocusHandoff.swift`: `CadenceFocusHandoff` + `CadenceFocusHandoffCenter`), the
  same shape as `CadenceDeepLinkManager` and for the same reason — the surface making the request
  cannot reach navigation state, and the Focus screen it hands to may not have been built yet.
  `FocusManager` was **not** un-guarded. Two affordances shipped, one per `CadenceFocusTarget`
  case: **Focus** in `iOSTaskRowContextMenu` (one entry, every iOS task surface, because
  `iOSTaskRow` is the row everywhere) and **Focus This Block** in `iOSCalendarBundleDetailSheet`
  (which is what both the board card and the timeline block open). The swipe tray was rejected —
  a swipe is for things you do without looking, and this one changes screens.
  Two session decisions, both in `Shared/` with tests: `timerState(startRequestFor:…)`, which
  unlike the play control's `afterPlayTapOn` **never pauses** (asking to focus the running subject
  would otherwise stop its clock), and `endSession(leaving:…)`, now called from `iOSFocusView`'s
  `.onDisappear`. That last one is a bug fix riding along: the screen's clock is `@State`, so
  leaving Focus threw the measured minutes away — pre-existing, but a route *into* Focus from a
  task row makes backing straight out of it routine. Deferred half is [[T-273]].

- [T-242] **Bundle focus is macOS-only.** `macOS/Views/FocusBundleTaskSupportViews.swift` lets the
  focus timer run a `TaskBundle` and step through its members; `Cadence/iOS/iOSFocusView.swift`
  contains the string `bundle` zero times. This was the one claim in [[T-190]] that was **true**,
  and it survived the ticket being closed because it is a separate feature rather than a guard to
  lift: `FocusManager` is macOS-only (`macOS/Services/`), so the picker, the member rows and the
  "which member am I on" state all have to be reached before iOS can focus a block. Start by
  checking what of `FocusManager` is actually AppKit-bound — [[T-190]] and the three tombstones in
  `macOS/Services/` are all cases where the answer was "nothing".

  **Shipped in `b653a6a`.**

- [T-268] **macOS offers "Mark Section Completed" on the Default kanban column, and the model
  throws the flag away while the settle still runs.** Found while doing [[T-247]].
  `Area.normalizedSectionConfigs` / `Project.normalizedSectionConfigs` force
  `isCompleted = false` and `isArchived = false` on the column named `Default`, on every read *and*
  every write — so the Default column can never be completed or archived, by design.
  `KanbanColumnSupportViews.swift:526` already gates the **Archive** item on `!section.isDefault`
  for exactly that reason; the **completion** button four lines above it is not gated. Tapping it on
  the Default column runs `KanbanSectionColumnView.saveSection`, which calls
  `TaskContainerLifecycleService.completeRemainingActiveTasks` — every open task in the column is
  marked done — and then the flag is normalized away, so the column stays visibly Active with its
  cards gone. Measured on iOS during T-247: the write is discarded and the status label does not
  move (that is why `iOSListEditorSheet.lifecycle(for:)` returns `nil` for a default column).
  Two candidate fixes, and they are not equivalent: gate the completion button the same way Archive
  is gated (cheapest, matches the invariant), or decide the Default column *should* be completable
  and relax the normalization — which would need a story for what "archived Default" means to
  `sectionNames`, since that getter filters archived columns out and every task with an empty
  `sectionName` resolves into Default.
  Pinned from the iOS side by `CadenceColumnWindDownSurfaceTests
  .theModelDiscardsALifecycleFlagWrittenOntoTheDefaultColumn`; nothing pins the macOS button.

  **Done — shipped in `43e269b`.** The **gate** was the route taken, not the relaxed normalization, and the
  reason is that Default is *synthesised* rather than created: `normalizedSectionConfigs` inserts
  it when it is absent, `AppTask.resolvedSectionName` sends every task with no section name into
  it, and `sectionNames` filters archived columns out — so a completed-or-archived Default would
  be an invisible bucket that still collects every new task in the list, and every task created
  into that list would land in a column marked done. There is no story for "archived Default"
  worth telling; refusing the flag is the story.
  The invariant is **named** now rather than re-spelled a fourth time:
  `TaskSectionConfig.supportsLifecycle` in `Models/AppTask.swift`, whose doc comment carries the
  reasoning above. All **three** macOS routes to a column's completion read it — the header glyph
  (`KanbanColumnHeader.headerControls`), the editor popover's item (which moved inside Archive's
  existing gate, taking the divider above it with it), and `Cmd+Return` over the hovered column,
  which now registers **no** `HoveredSectionManager` target for Default rather than a no-op one,
  because `triggerToggleComplete()` reports whether it handled the key and a registered no-op
  would swallow the keystroke. So does `toggleSectionCompletion`, the point all three converge on,
  which is what makes a *fourth* route refused by default. The popover's Default copy names
  completion now.
  Agrees with [[T-247]]'s iOS behaviour: `iOSListEditorSheet.lifecycle(for:)` returns `nil` for
  the same column for the same reason. Nothing about the wind-down itself changed — every
  non-default column still settles through `settleWithoutAdvancingSeries`, and
  `theMacColumnStillWindsDownEveryOtherColumn` fails if those calls are removed.
  New file: `CadenceTests/CadenceKanbanColumnLifecycleSurfaceTests.swift`.
  One thing found on the way, recorded because it outlives this ticket: a test that slept
  `animationDuration + 1.0` for `SectionCompletionAnimationManager`'s 2.5s sweep **failed under the
  suite's own parallel load** (exit 65, 0 compile errors, three expectations at
  `…SurfaceTests.swift:151-153`), and passed alone. It was replaced with a wall-clock-free
  equivalent: the *reopen* branch is synchronous and is asserted as behaviour, the *complete*
  branch is asserted as "the press enters the pending state" plus a source read of the two flags
  the sweep lands. Both 2.5s animation managers (`SectionCompletionAnimationManager`,
  `TaskCompletionAnimationManager`) still have no test that drives their delay, and
  `HoveredTaskManagerTests` sleeps 160ms against an 80ms debounce — a 2x margin, i.e. the same
  shape at a smaller scale. Do not add a sleep-and-assert test to this suite.


- [T-247] **Archiving a kanban column on iOS settles nothing, and it is a draft toggle rather than
  an action.** The sibling of [[T-215]], one level down. macOS's `KanbanSectionColumnView` calls
  `TaskContainerLifecycleService.cancelRemainingActiveTasks(in:area:project:)` when a column is
  archived and `completeRemainingActiveTasks` when it is completed; on iOS a column's `Completed`
  and `Archived` are two `Toggle`s on a `CadenceSectionDraft` inside `iOSSectionDraftRow`
  (`iOSListEditorViews.swift`), saved with every other edit in the sheet, and no task changes status.
  The service is cross-platform since [[T-215]] and its section overload is public and tested, so the
  mutation is available — what has to be *decided* is the interaction, which is why this is not a
  one-liner: a toggle flipped mid-edit and saved alongside a rename is a bad shape for an
  irreversible bulk cancellation, and there is nowhere in that sheet to state a count. Either the
  toggle becomes a confirmed action (the shape `iOSListWindDownSupport` uses for lists), or column
  archiving deliberately stays a flag on iOS and it is macOS's behaviour that changes.
  Do **not** reach for `markDone` / `markCancelled` / `applyStatusCompletion` here either — see
  [[T-213]] and [[T-214]]: the successor inherits `sectionName`, so a column wind-down routed
  through them refills the column it just archived.
  **Built, shipped in `bf529c6`.** Decided the first way: the toggle becomes a confirmed action.
  The reason is not taste — a draft flag is committed *after* `reassignTasks` has re-pointed
  `AppTask.sectionName` for every renamed or removed column, so any count stated at flip time is a
  promise about a different array, and the count has to be the settle's own
  (`remainingActiveTasks(in:area:project:)`). New `Cadence/iOS/iOSColumnWindDownSupport.swift`
  (target, `ModelContext.windDownColumn` / `reopenColumn`, the confirmation modifier) and
  `Cadence/iOS/iOSWindDownConfirmation.swift` (the sheet, now shared with the list archive via
  `iOSWindDownSubject`); `CadenceListArchiveSummary` generalised to
  `CadenceContainerWindDownSummary` with a `CadenceWindDownOutcome` rather than copied; covered by
  `CadenceColumnWindDownSurfaceTests`. Reversal (`reopenColumn`) stays a plain tap and stays in the
  editor, because `Area.sectionNames` filters archived columns out of the board and iOS has no
  "Show Archived" mode.

- [T-214] **iOS list *completion* is still macOS-only, and the obvious shared substitute is wrong.**
  T-187 shipped deletion and deliberately not completion. `TaskContainerLifecycleService` **no
  longer lives** in `TaskWorkflowService.swift` behind `#if os(macOS)`: [[T-215]] moved it to
  `Cadence/Services/CadenceTaskContainerLifecycleService.swift`, so the un-guard half of this ticket
  is done and what remains is genuinely only the call site — an iOS affordance that offers
  "Complete" and calls `completeRemainingActiveTasks`. Nothing on iOS offers it today, so this stays
  open.
  Do **not** reach for `applyStatusCompletion` instead: it routes through `markDone`, which **spawns
  the next recurrence occurrence**, which is correct for one task and wrong for bulk container
  completion that must not mint new work.

  **Built, shipped in `aff8de3`** (built on the archive plumbing in `635720c`). Extended [[T-215]]'s and [[T-247]]'s machinery rather than
  writing a second one: `iOSListArchiveSupport.swift` became `Cadence/iOS/iOSListWindDownSupport.swift`
  with an `iOSListWindDownAction` (`.archive` / `.complete`) beside the list — the shape
  `iOSColumnWindDownTarget` already had — `archiveList` became `windDownList`, and
  `CadenceContainerWindDownSummary.forArea` / `forProject` gained the required `outcome:` that
  `forColumn` already carried. Same sheet, same one decision point (`iOSListsView.requestWindDown`),
  covered by the renamed `CadenceTests/CadenceListWindDownSurfaceTests.swift`.

  Two judgements worth keeping, because both could plausibly have gone the other way:
  - **The conditional-confirmation rule does not get stricter for completion.**
    `requiresConfirmation` asks whether anything irreversible happens, not how large a claim the
    action makes; completing an empty list writes one `status` and settles nothing, and a sheet over
    a no-op is what teaches people to dismiss the one that matters.
  - **The copy does differ, in substance and not only in the verb.** A cancellation records that
    work was abandoned; a completion records that it *happened*, and
    `GoalContributionSummary.progress` reads `completedTasks / totalTasks` over `filter(\.isDone)`
    — so bulk completion can move a goal's bar where bulk cancellation cannot (a cancelled task
    stays in the denominator and out of the numerator). And the destination is asymmetrical on iOS:
    an archived list stays on the Lists page under "Archived", a completed one leaves it and is
    reopened from Settings › Lists. Both facts are in the completion sheet's explanation, because a
    confirmation that did not name the destination would make completion look like a deletion.
  Completion is a context-menu item on the iPhone list and the iPad pane and a swipe action on
  neither — the tray already carries Archive, and a two-action tray puts "this work is finished" one
  mis-flick from "file it away" on a control with no beat in which to read anything. It is also not
  `role: .destructive`.


- [T-241] ~~**Bulk container settle skips the notification reconcile, so a completed list keeps its
  nudges.**~~ **Fixed — shipped in `bf529c6`.** `TaskContainerLifecycleService.settle` now reconciles after the batch, so
  completing or archiving an area, a project or a kanban column clears its tasks' pending
  "starting now" / "due today" notifications immediately instead of waiting for the next
  `scenePhase` checkpoint. iOS gets it too — the entry points are the shared ones.
  **The deliverable was the seam, not the call.** `scheduleReconcile` spawns an unstructured `Task`
  that fetches the whole store twice and calls into the `@MainActor` `NotificationManager`
  singleton, so an unconditional call would have left eighteen existing wind-down tests doing async
  store work after their bodies returned. The six entry points now take
  `reconciler: CadenceWindDownReconciler? = nil`; `nil` resolves to `.default`, which is `.live` in
  the app and `.inert` inside a test host (`NotificationManager.isTestEnvironment` — the reusable
  spelling; `PersistenceController.isRunningTests` is `private`). A test that wants to prove the
  wiring injects its own recorder, which is what makes "remove the reconcile call" a red test rather
  than a silent regression — `ContainerWindDownReconcileTests` in
  `CadenceTests/NotificationSchedulingTests.swift`.
  Rejected: a global `onDidSettle` hook the app wires at launch (correctness would depend on remote
  wiring, which *is* this bug; and a mutable static is a race under parallel tests), and an
  explicit closure at every call site (the next surface that forgets it reintroduces the bug).
  Also rejected: making `scheduleReconcile` itself inert under test — it works and changes nothing
  today, but with the call inert there is nothing behavioural left to assert, so the wiring would be
  pinned only by a source-text scan.
  Note the `in context:` parameters T-212 deliberately left unused are **used now**, on all six
  entry points: the context is what the reconciler is handed. `settle` also skips the reconcile when
  the batch settled nothing, because an unchanged store diffs to a no-op.
  One thing the original ticket got wrong and is worth keeping: it said adding the call would make
  the tests "touch the real notification centre". It would not have — `NotificationManager` guards
  every method on `isTestEnvironment` and its `center` is `lazy`, so `UNUserNotificationCenter.current()`
  is never evaluated under XCTest. The real cost was the stray async work, not a live centre.


- [T-259] **The MCP smoke test runs 21 of the router's 30 arms, and five of the eight write tools
  are run by nothing at all.** Found while doing [[T-126]]. `plugins/cadence-mcp/scripts/smoke-test.py`
  is the only thing that *executes* `CadenceMCPServer/`, and it never dispatches `get_task_bundle`,
  `list_containers`, `get_container_summary`, `get_goal`, `update_task`, `schedule_task`,
  `complete_task`, `reopen_task` or `cancel_task`. The five write tools are the ones that matter:
  each has its own argument wiring — `schedule_task` is the only place `minuteOfDay`,
  `durationMinutes` and `clearScheduledDate` are read together — and a rename or a reordered
  `CadenceScheduleTaskOptions` initialiser would compile, advertise, and fail only in the user's
  editor. `CadenceMCPToolContractTests` (added under T-126) closes the *name* half and explicitly
  not this half: it is a source scan and executes nothing.
  Two smaller shapes of the same gap, worth folding in: the four `list_*` arms the smoke test does
  call run against a **fresh empty fixture store** and return `[]`, so no list DTO's shape is ever
  observed; and the natural-language parsing in `CadenceMCPArgumentParsing.swift` is sampled at one
  point per helper — `tomorrow` but never `today`/`yesterday`/`in 3 days`/`+2 days`/`2 days ago`,
  `1h` and `three hours` but never `30m`/`1.5h`/`two and a half hours`, `4 PM` but never `4:30 pm`
  and never a rejected `13 pm`.
  Note the constraint before proposing "just add unit tests": `CadenceMCPArgumentParsing` extends
  `Dictionary where Value == MCP.Value`, and the `MCP` package product is linked into the
  `CadenceMCPServer` target only. Reaching it from `CadenceTests` means adding that package
  dependency to the test target in `project.pbxproj` — a real decision, not a formality — and it
  would compile those files under the app's Swift 5 / `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  settings rather than the server's Swift 6 without it, i.e. under settings that cannot reproduce
  the failure mode `CadenceMCPServer/AGENTS.md` exists to warn about. Extending the smoke test is
  the cheaper and more honest route.
  **Done — shipped in `88a88d9`.** The smoke test was the route taken, and the reasoning held up: it runs the
  real binary built by the real scheme, so it is the only thing that can catch a Swift-6 argument
  regression at all. All 30 arms are now dispatched, the five write tools run a full create →
  update → schedule → complete → reopen → cancel lifecycle, the date/duration/time parsers are
  exercised on every branch including their rejections, and the error paths assert the message
  rather than `isError` — a deleted arm answers "Unknown tool", which is also an error. The guard
  that matters most is not the new coverage but the fact that it is now *checked*: every
  `tools/call` is recorded and compared against the server's own `tools/list`, so the next arm
  added is a red run rather than a silent 31st. The list-DTO half is only partly closed — see
  [[T-269]].

- [T-260] **Two argument-parsing helpers in the MCP server have zero call sites.** Found while doing
  [[T-126]]. `Dictionary.int(_:)` and `Dictionary.stringArray(_:)` in
  `CadenceMCPServer/CadenceMCPArgumentParsing.swift` are never called by the router, by
  `main.swift`, or by the tool definitions — `strictInt` and `flexibleStringArray` replaced them
  (12 and 8 router call sites respectively) and the originals were left behind. Grep with a leading
  dot and read the hits: `.int(` also matches `MCP.Value.int(...)`, which the definitions file uses
  three times to build JSON-schema payloads, so a naive scan reports `int` as live.
  This is dead code in the one folder with no unit coverage and no execution path, which is the
  combination that makes it worth removing rather than leaving: the next agent to touch argument
  parsing sees two plausible entry points whose semantics differ from the two that are actually
  wired up — `int` returns `nil` on a bad value where `strictInt` throws, and `stringArray`
  silently drops non-strings where `flexibleStringArray` throws. Picking the wrong one turns a tool
  error into a silently ignored argument. Delete both, or wire them and say why.
  **Done — shipped in `88a88d9`.** Both deleted. `parseIntegerString` stays — `strictInt` calls it. The
  general form is pinned by `everyArgumentParsingHelperIsCalledByTheRouter`, which requires every
  non-private helper in that extension to have an `arguments.<name>(` call site in the router. The
  needle carries the receiver deliberately, for exactly the reason this ticket had to warn about:
  a scan for `.int(` matches `MCP.Value.int(...)` in the tool definitions and reports the dead
  helper as live.

- [T-269] **Six of the MCP `list_*` tools are dispatched against an empty store, so their DTO
  shapes are still unobserved.** Split out of [[T-259]], which closed the other half. The smoke
  test now checks `list_tasks`, `list_tags` and `list_notes` against real rows — key set, and the
  optionals named separately because Swift's synthesized `Codable` uses `encodeIfPresent`, so a nil
  optional is an *absent* key rather than a null. The other six — `list_task_bundles`,
  `list_goals`, `list_habits`, `list_links`, `list_contexts`, `list_containers` — return `[]`
  every run, so a renamed or dropped field in `CadenceGoalSummary`, `CadenceHabitSummary`,
  `CadenceContainerRef`, `CadenceContextRef`, `CadenceSavedLinkSummary` or
  `CadenceTaskBundleSummary` reaches a user's editor with nothing red anywhere.
  The reason is structural, not an oversight: MCP has **no write tool** that creates a bundle, a
  goal, a habit, a link, a context or a container — `create_task` and `append_core_note` are the
  only constructors on the surface — so a fresh fixture store cannot be made to hold one through
  the protocol. Two routes, and they are not equally good:
  (a) seed the fixture store out-of-band before the smoke test starts, which means a second
  process opening the same SwiftData store the server is about to open, and a fixture that has to
  be kept in step with `CadenceSchema` by hand;
  (b) assert the DTO shapes as a **source scan** in `CadenceMCPToolContractTests` — read the
  `nonisolated struct Cadence*Summary: Codable` declarations in `CadenceReadDTOs.swift` and pin
  their stored-property lists. That executes nothing, which is the standing weakness of everything
  in that file, but it is honest about what it is and it catches the rename, which is the failure
  actually worth catching. Prefer (b) unless the fixture is wanted for something else too.

  **Shipped in `88a88d9`** — route (b) from the ticket: `CadenceMCPToolContractTests
  .listToolDTOsDeclareTheirEstablishedStoredProperties` pins all six DTOs' stored-property
  lists by source scan. Route (a) — observing the six `list_*` tools against a seeded store —
  was not taken; the ticket said to prefer (b) unless the fixture was wanted elsewhere too, so
  this satisfies it as written.

- [T-248] **Settings → Templates draws a 16pt editor on the target iPad in portrait — [[T-177]]'s
  defect, one level down, in a card rather than a page.** The split is gated on
  `horizontalSizeClass == .regular` alone (`iOSSettingsTemplateAndListSections.swift:29`), with no
  width input and no floor, and the list beside it is a fixed `.frame(width: 260)` (line 32) while
  the editor is `maxWidth: .infinity`. The chain that eats the pane, every term of it read from the
  code: `paneWidth − 248` (`iOSSettingsRail`, `iOSSettingsComponents.swift:259`) `− 1` (divider,
  `iOSSettingsView.swift:113`) `− 56` (`settingsDetailScroll`'s `.padding(.horizontal, 28)`) `− 32`
  (`iOSSettingsCard`'s `.padding(16)`) `− 260 − 1 − 32` (two `iOSEditorSheetMetrics.groupSpacing`)
  = **`paneWidth − 630`**.
  Measured rather than derived: an `NSHostingView` reproduction of that exact modifier chain reports
  the editor at **16.0pt at a 646pt pane**, 146.0 at 776, 204.0 at 834, 392.0 at 1022, 580.0 at 1210,
  and **0.0 at 570**. 646 is the iPad Pro 11" in portrait with the shell sidebar out (834 − 188) —
  the default configuration of the primary target device, no multitasking involved, and the width
  `CadenceRegularPaneLayoutTests`' own file comment already names as the narrowest normal pane.
  The one-column form already exists and ships on iPhone (`templatePicker` chips above
  `templateEditor`), so the work is a gate, not a new layout.
  **Not taken in T-183 because the fix is a seventh width-derived pane decision.** The register at
  the top of `CadenceRegularPaneLayout.swift` and `CadencePaneWidthRuleHomesTests` require it to
  join one of the four registered files, be named in the register prose, and move two hard-coded
  expectations (`registeredHomes`, and the literal 16 in
  `theInventoryIsStillSixteenDeclarationsAcrossFiveFiles`) — correct, but not something to land
  inside an audit. The floor should not be invented either: `CadenceNotesListMetrics
  .minimumEditorWidth` (= `CadenceTodayLayoutSupport.inspectorPaneMinWidth`, 320) is the figure the
  notes editor already borrows for the same kind of content, which puts the card's two-column floor
  at `260 + 1 + 320 + 32` = 613 of *card* width, i.e. 950 of pane — landscape only on the target
  iPad, which is the right answer rather than a convenient one.

  **Shipped in `b1239e0`.**

- [T-249] **macOS Settings → Templates has the same missing floor, and no compact form to fall back
  to.** `SettingsTemplatesSection.swift:29` is a fixed `.frame(width: 230)` beside a
  `maxWidth: .infinity` editor, inside a `SettingsCard` (`.padding(14)`) inside the detail column
  beside a 248pt rail (`SettingsRailMetrics.columnWidth`), so the editor is **`paneWidth − 596`**.
  Same `NSHostingView` reproduction: 0.0 at a 570pt pane, 100.0 at 696, 144.0 at 740, 364.0 at 960,
  604.0 at 1200. The pane is the window less the sidebar, which is 220–390 wide and defaults to 264
  (`macOSRootShellViews.swift:12/15/16`) against a 960pt window floor (`CadenceApp.swift:57`) — so
  696 is the ordinary minimum and 570 the worst case.
  Less urgent than [[T-248]]: the MacBook Pro 14" target is 1512 wide, which leaves 1248 of pane and
  a 652pt editor. Recorded because it is the same defect and because the macOS side has **no**
  one-column branch at all, so closing it means writing one rather than gating to one that exists.

  **Shipped in `b1239e0`** (same commit as [[T-248]]).

- [T-250] **Three macOS pages declare more `HSplitView` minimum width than the window's own floor can
  pay, and `HSplitView` does not report that upward, so the window lets you reach it.** Measured, not
  reasoned: an `NSHostingView` of each split returns `sizeThatFits(width: 1).width == 1.0`, i.e. a
  child `minWidth` inside an `HSplitView` propagates nothing, and `fittingSize.width` for the whole
  shell stays exactly **960** whichever page is mounted. What happens instead is that the
  `NSSplitView` lays out at the sum of its minimums and overflows **leading-aligned** from the detail
  pane's origin, so the overflow leaves by the trailing edge of the window.
  The sums: Today `449 + 300 + 343` + 2 dividers = **1094** (`TodayView.swift:8/12/16`); Goals
  `560 + 340` = **901** (`GoalsView.swift:129/139`); Focus `520 + 320` = **841**
  (`FocusView.swift:78/86`). The pane available is the window less the sidebar: **570** at the 390pt
  sidebar maximum, **696** at the 264pt default, 740 at the 220pt minimum, 960 with the sidebar
  hidden by `Cmd+O`. Measured visible widths at a 960pt window, Today's three panes, sidebar at
  220 / 264 (the stored default) / 390: `449, 290, 0` — `449, 246, 0` — `449, 120, 0`. **The Schedule
  pane is entirely off the right edge in all three**, and at the widest sidebar the task column keeps
  120 of its 300. The MacBook Pro 14" target at its full 1512 is fine (`449, 454, 343`), so this is
  reachable by narrowing the window rather than on sight — which is exactly why nothing has caught it.
  The 960 floor's own comment derives it from the list-detail Kanban tab bar (~950pt), which is a
  different page — nothing ever checked it against these three. A related figure inside the same
  overflow: `GoalTimelineView.leftRailWidth` is a fixed 300 inside the 560pt Goals pane, so the Gantt
  canvas is 260 of 560 when that pane is at its own minimum.
  Not fixed because which side gives is a product decision, and both directions have a cost: raising
  the floor to 1314 puts it past a 1280-wide display, and lowering the pane minimums or gating a pane
  away (the `CadenceTodayLayoutSupport` answer) changes what the page *is* at that width.

  **Decided: the pages gained a narrow fallback and the window floor did not move.** The floor was
  weighed and rejected on measurement, not taste — the pane is `window − sidebar` and the sidebar is
  independently 220–390 and hideable, so paying for Today's 1094 costs **1358** at the stored 264pt
  sidebar and **1484** at the 390pt maximum, which is wider than a 13" MacBook Air's whole 1470pt
  screen. A single window minimum cannot express a rule whose input is `window − sidebar`, and any
  floor short of 1484 leaves the bug live for anyone who has widened their sidebar. It would also tax
  every page that already fits, and it would not stop the next raised pane minimum from re-opening
  the same silent overflow.
  The rule joined the register in the house file as `CadenceDesktopSplitLayout`
  (`Cadence/Shared/CadenceRegularPaneLayout.swift`), the three views read its constants back rather
  than re-typing their frames, and `CadenceDesktopSplitLayoutTests` sweeps every width asserting that
  whatever is drawn fits. Today drops the **notepad** first (measured: `tasks + schedule` is 644 and
  fits the ordinary 696pt pane, `notes + tasks` is 750 and does not — and the tasks/timeline pair is
  the one with a drag payload between them), Goals drops its **inspector** (its list column holds the
  page header, search, filter and the only New Goal button, so 560 is not the side that can yield),
  Focus drops its **sidebar** on all three of its splits. Verified and **shipped in `8b73c78`**.

- [T-251] **The macOS Calendar Board's two rails are 496pt of fixed width with nothing underneath the
  day columns.** `CalendarPageBoardSupportViews.swift:60-66` is `HStack(spacing: 0) { rail;
  dayColumns; rail }` with each rail at `calendarBoardRailWidth` = 248
  (`KanbanBoardSupport.swift:17`) and `dayColumns` a horizontal `ScrollView` at
  `.frame(maxWidth: .infinity)`. A horizontal scroller has no minimum width, so the rails are the
  only thing the `HStack` has to satisfy — measured, the board reports **496** as its minimum and the
  columns get `paneWidth − 496`: **74.0pt at a 570 pane, 200.0 at 696, 244.0 at 740**, 464.0 at 960,
  against a `calendarBoardDayColumnWidth` of **306** plus 22pt of padding each side.
  So at the default sidebar and the minimum window the Board shows two thirds of one day column
  between two inboxes holding 71% of the surface. Nothing clips and the columns scroll, which is why
  this is a floor question rather than a [[T-250]]-shaped break — but it is the fixed-rail pair
  [[T-183]] was asked to look at and the register does not cover it.

  **Decided: the rails collapse, they are not dropped, and the gate is `CadenceCalendarBoardLayout`
  (the ninth registered expression).** The floor is a sum of the board's own parts —
  `expandedRailWidth * 2 + oneDayColumnMinimumWidth` = **846pt of pane** — and below it each rail
  renders as a 60pt identity strip (dot, count, rotated name) that *keeps its drop destination*, so
  the one behaviour the pair has — dragging a card out of a day column onto Unscheduled — survives
  at every width. Tapping a strip expands that rail in place; one at a time, so the fixed side never
  costs more than one column plus one strip. Measured with an `NSHostingView` reproduction of the
  exact modifier chain (it reproduces the before figures above to the tenth of a point): day columns
  go **74.0 → 450.0 at a 570 pane, 200.0 → 576.0 at 696, 244.0 → 620.0 at 740**, and are unchanged
  at 846 (350.0), 960 (464.0) and 1248 (752.0) — so no Mac that already fits sees any difference.
  *Dropping* the rails, the `CadenceCalendarPaneLayout` answer, was checked against this surface and
  rejected on measurement rather than taste: the day columns are floored at today **because** the
  Overdue rail exists (`plannerWindowStart(notBefore:)`), and `tasksByBoardDate` keys strictly on the
  do date, so do-dateless work has no day column anywhere. Neither rail restates anything on screen;
  both are the only route to their pile on this surface. The Timeline's "unscheduled tasks" chips
  are a different population (`!scheduledDate.isEmpty` — a day with no start minute) and are not a
  second route. Compression alone was rejected because it cannot reach: 570pt of pane leaves 220 for
  two rails once one day column is paid for, i.e. 110 each. Un-pinning the rails into the day
  scroller was rejected because the drag needs both on screen and un-pinned they never are below
  816. Raising the window floor was rejected for [[T-250]]'s reason, unchanged.
  The four board metrics moved from `macOS/Views/KanbanBoardSupport.swift` into the house file,
  because the floor has to be a *sum* of them and that file is behind `#if os(macOS)`.
  **Cost, stated rather than glossed:** below 846 reading either pile takes one click, and while a
  rail is expanded there the day region is squeezed again — a user-chosen, one-click-reversible
  state, not something the app does unasked. Verified and **shipped in `850af8a`**.

- [T-252] **`CadenceRegularSplitLayout` is the one registered width rule with no "two panes is worse
  than one" fallback, and it shows on the target iPad.** Today gates to `.compact` at 761, Notes to
  `.oneColumn` at 601, Calendar drops its inspector under 681; `listPaneWidth` only clamps the
  *proportion* (`min(preferred, (paneWidth − 1) / 2)`), so there is no width at which Goals, Habits,
  Focus or Lists stop splitting. At the 646pt portrait pane that is a **300pt chooser beside a 345pt
  detail**, on the same device and orientation where Today is one column and Calendar has no
  inspector — three registered rules answering the same width three different ways.
  `CadenceRegularPaneLayoutTests.theNarrowestRegularPaneGivesTheMajorityToTheDetail` pins 300/345
  today, so this is a decision to revisit rather than a regression, and it is not taken here because
  none of those four details states a floor to derive a gate from. Inventing one is precisely the
  failure mode [[T-183]] exists to avoid.

  **Decided with [[T-250]], one rule for both.** The floor is derived from this type's *own* parts
  rather than from a detail that cannot supply one: `listPaneMinWidth / listPaneFraction` = **750pt**
  is the width below which the chooser's floor is bigger than the share it asks for, so every point
  the pane loses after that comes out of the detail. That answers the ticket's objection without
  inventing a number. 646 is now one column, alongside Today (761) and Calendar (681); 834, 1022 and
  1210 still split, and `listPaneWidth` is unchanged at every width where anything asks it.
  The gate lives in `iOSFeatureSplitLayout`, the one place all four surfaces go through, and the
  fallback is each surface's own one-column form with rows that push — not a dropped chooser, which
  would strand the detail ([[T-248]]'s reasoning). Verified and **shipped in `8b73c78`**.

- [T-272] **Goals' *timeline* mode has never had an Attach List route, at any width.**
  Found while doing [[T-271]] and separate from it: `GoalTimelineView` was handed only `onEditGoal`
  (`GoalsView.content(groups:)`), so the roadmap presentation offered Edit at every width and Attach
  List at none. This is not [[T-250]] fallout — the timeline layout never had an inspector to lose —
  which is why it was left out of T-271 rather than folded into it.
  **Fixed, shipped in `850af8a`, and it composes with [[T-271]] rather than adding a
  second route** — verified, not assumed: `GoalInspectorSheet` and its
  `.sheet(isPresented: $showGoalDetail)` hang off `GoalsView.body`, which wraps *both* presentations,
  so the presenter was already installed over the timeline and only the mission branch ever spent it.
  What was missing was the row action. `onEditGoal` became `onOpenGoal`, wired to the same
  `select(_:showsInspector:)` the mission cards call with a literal `false`, because the Gantt has no
  column to select into at any width — one flag, one gate, no second `showGoalDetail = true` for the
  two answers to disagree over. Edit did not move: it is a button inside `GoalInspectorView`, so the
  double-click now reaches a superset of what it did, with Attach List and `GoalLinkedListRow`'s
  per-list detach beside it. `GoalTimelineGroupRow` gained the route too, not just the milestone rail
  row and the bar: `timelineBody` skips the bar unless the goal has **both** dates, so hanging it on
  the bar would have left an undated *direction* — the shape a linked list is most likely to hang off
  — as the one goal on the page with no way to attach one. That is T-271's own argument about its two
  card kinds. No `GoalListLink` write was added anywhere; the sheet reaches `AttachWorkSheet` and
  `ModelContext.detachGoalListLink` exactly as the mission inspector does. Pinned by
  `CadenceGoalTimelineRouteTests` (5 tests, four mutations each failing only their own).

- [T-183] **Audit the remaining fixed-width columns for missing floors.** `T-177` and Today's own
  `twoPaneMinimumWidth` are the same defect twice: a fixed `.frame(width:)` beside a flexing pane,
  with nothing asserting the flexing side stays usable. Worth one sweep for other fixed column widths
  — `CadenceRegularSplitLayout.listPaneWidth`, the calendar rails, the settings rail — asking in each
  case what the other side gets at the narrowest host that reaches it.
  **Swept 2026-08-22; findings are [[T-248]] through [[T-252]] and nothing was changed here.** Every
  three-digit `.frame(width:)` and every `frame(minWidth:)` in `Cadence/` was classified as *has a
  floor*, *no floor but cannot be squeezed* (popovers, sheets, drag previews and overlay panels, which
  are the large majority), or *no floor and starves its neighbour*. Four of the last kind: the two
  Settings → Templates cards ([[T-248]], [[T-249]]), three macOS `HSplitView` pages against a 960pt
  window floor ([[T-250]]), and the Calendar Board's rail pair ([[T-251]]); [[T-252]] is the
  consistency question the sweep raised about the register itself. Two things worth carrying whatever
  is done next: **an `HSplitView` propagates none of its children's `minWidth` upward**, so a page's
  pane minimums never reach the window and the window happily gets narrower than the page
  (`sizeThatFits(width: 1).width == 1.0`, measured) — and the three registered surfaces that *do*
  state a floor were all correct at every reachable width, so the rule works where it has been
  applied and the gap is only where it has not.

  **All five findings shipped**: [[T-248]] and [[T-249]] in `b1239e0`, [[T-250]] and [[T-252]]
  in `8b73c78`, [[T-251]] in `850af8a`. This audit's job is done.


- [T-255] ~~**A reminder completion that fails leaves the row looking completed, on both
  platforms.**~~ **Fixed — shipped in `121e07f`.** Confirmed exactly as written, on both rows and on all four exits.
  `completeReminder(id:)` now returns `AppleReminderCompletionOutcome` — the three refusals come
  from the shared `AppleReminderCompletionOutcome.refusal(isAuthorized:reminderResolves:
  allowsContentModifications:)` rather than a `guard` chain a test cannot reach — and both rows turn
  it into `AppleReminderCompletionResolution` (`Shared/CadenceRemindersPresentationSupport.swift`).
  **The tick may not assert an outcome EventKit did not confirm**, so everything but `.completed`
  reverts; the tick still *leads* the write, because it has to land before the reload removes the
  row. A modal alert was rejected: a revoked grant or a sync conflict refuses every visible row at
  once, so it is a queue of sheets over a list. A bare silent revert was rejected too — it reads as
  a misclick — so the three outcomes nothing else on screen explains carry a short inline sentence
  on the row, and `.notAuthorized` is silent because the section is already replacing every row
  with its access card. Two outcomes also reconcile the manager: `.notAuthorized` re-derives
  authorization, `.reminderUnavailable` refetches. Pinned by six tests in
  `CadenceInboxRemindersSurfaceTests`, three of them mutation-checked.
  Original report follows.

  **A reminder completion that fails leaves the row looking completed, on both platforms.**
  `AppleReminderTaskRow.complete()` (macOS) and `iOSInboxReminderRow.complete()` (iOS) are the same
  optimistic sequence: set `isCompleting = true`, animate to struck-through at 0.65 opacity, then
  call `onComplete` 220ms later. `RemindersManager.completeReminder(id:)` has three silent exits —
  not authorized, the identifier no longer resolves, the calendar refuses content modifications —
  and a fourth on a `store.save` throw, which calls `reload()`. None of them tells the row, and
  `isCompleting` is local `@State` that is never reset, so the row stays visibly ticked while
  Apple Reminders still has the item open. The row needs the write's answer back, or the tick has to
  follow the write rather than lead it.

- [T-256] **`.restricted` is presented as a denial the user can undo, and it is not.**
  `RemindersConnectionState.resolve(status:)` folds `.restricted` into `.denied`, so the card reads
  "Reminders access denied" and offers "Allow Cadence from Settings, Privacy & Security, Reminders."
  Under a device restriction — Screen Time, MDM, a managed profile — that pane will not let them,
  and the button sends them somewhere that cannot help. The pure mapping is already tested for the
  state; what is missing is a fourth *presentation* that says the restriction is not theirs to lift.
  Low frequency, but it is the same class of mistake as the dead **Allow Access** button [[T-21]]
  fixed: an affordance offered in a state where it cannot work.

  **Shipped in `2f018a4`**: `RemindersConnectionState` gained a distinct `.restricted` case
  with its own title/message, and `accessAction` returns `nil` for it rather than the dead
  "Allow Access from Settings" button.

- [T-264] **Both Inboxes head the Apple Reminders group with a count of `0` in every state where the
  count is meaningless.** `iOSInboxRemindersSection` passes `count: remindersManager.reminders.count`
  to `iOSTaskGroupHeader`, and `InboxAppleRemindersSectionView` passes
  `regularCount: reminders.count` to `TaskListGroupHeader`; neither heading suppresses a zero, so
  not-determined, denied and restricted all render **APPLE REMINDERS 0** directly above a card that
  says Cadence cannot see the reminders at all. Screenshotted on the iOS 26 simulator in both the
  not-determined and denied states. It is the softer half of the "renders *no reminders* when the
  truth is *not authorized*" failure — the *copy* is clean everywhere ("No open reminders" is
  reachable only inside `.connected` on all four surfaces, verified state by state under [[T-21]]),
  and it is only the capsule that still asserts a quantity nobody measured. Fix is a decision, not a
  line: either the count is `nil`-able and the heading drops the capsule, or the section passes the
  count only when `state.isConnected`. Do it in the shared `CadenceTaskGroupHeading` /
  `TaskListGroupHeader` vocabulary rather than twice.

  **Shipped in `2f018a4`**: both Inboxes now pass `nil` instead of `0` when the state is not
  `.connected` (`iOSInboxRemindersSection.swift`, `InboxSupportViews.swift`), so the capsule is
  suppressed rather than asserting a count nobody measured.

- [T-195] **Sections-due-today is still macOS-only — the rollover banner half is done.** This
  ticket named two unrelated features and only one of them has shipped.
  **Closed:** the rollover banner. `TasksPanelRolloverNoticeSectionView` is
  `Shared/Components/CadenceTodayRolloverBanner.swift` (two container styles, `.panelBand` for the
  Mac's task column and `.card` for iOS), the decision is `Shared/CadenceTodayRolloverSupport.swift`
  (the over-do predicate, the visibility test, the withhold-while-showing filter, the batch roll),
  and the slot-clearing mutation is `CadenceTaskMutationSupport.rollOverTaskToToday` —
  `SchedulingActions.rollOverTaskToToday` delegates to it and must not grow a second body. macOS was
  rewired to all three rather than left beside them; `CadenceTodayRolloverSurfaceTests` recomputes
  `TasksPanelDerivedState`'s two changed values with the old inline expressions and asserts they are
  identical. **One `UserDefaults` key on purpose** — `todayRolloverNoticeDismissedDate` — because
  dismissing is a statement about the day, not the device.
  **Also closed: sections-due-today, shipped in `2dcc948`.** `CadenceTodayOverdueListSummary` /
  `CadenceTodayOverdueSectionSummary` moved to `Shared/CadenceTodayOverdueSummarySupport.swift`,
  and iOS renders them through `iOSTodayOverdueSummaries` (`Cadence/iOS/iOSTodayTaskSections.swift`,
  wired into `iPadTodayView.swift` / `iPadTodayCompactViews.swift`). The stale `Cadence/iOS/AGENTS.md`
  line this note flagged (claiming this half was untouched) is fixed too, in `91a7053`.



- [T-229] **iOS's Today → Completed admits what `CLAUDE.md` says it cannot, proven at runtime.**
  `completedTodayTasks` returns true for `scheduledDate == todayKey || dueDate == todayKey` *before*
  consulting `completedAt`. So a task **completed in January** with a do date of today appears there,
  and a pre-`f15db8b` cancelled task with a nil timestamp appears if its due date is today. Two
  consequences: `CLAUDE.md`'s "only shows tasks whose `completedAt` is **today**" is true of macOS and
  false of iOS; and `markCancelled`'s promise that legacy nil-stamp rows stay out holds only where the
  dates do not happen to be today. Overlaps [[T-208]].

  **Confirmed at HEAD, and shipped in `cd734a3`.** Every clause of the
  ticket held. The two date grounds are **original iOS code that no recorded decision ever chose**:
  `9d11135` (T-147) rewrote the *status* half of that same `filter` and left them untouched, and
  they have no macOS counterpart — `TasksPanelDerivedState` in `.todayOverview` has only
  `completedAt`. The deciding evidence for direction is that `CadenceTodayPresentationSupport`'s own
  doc comment justified unifying the two headings on the claim that both sat "over the same
  predicate — `completedAt` inside today, on both". That claim was false when written, so the app
  already said in three places (the heading, that comment, `CLAUDE.md`) what only one platform did.
  Fix: `CadenceTaskQuerySupport.completedTodayTasks` is settled-inside-today and nothing else, and
  **macOS calls it** rather than keeping a second spelling — its precomputed day range moved into
  the shared function, so the refactor costs nothing per task. Nothing became unreachable: every
  settled transition stamps `completedAt`, and `completedTasks` / `completedInboxTasks` / the
  `.byDoDate` logbook test no date. Pinned by six new tests in
  `CadenceCancelledTaskReachabilityTests` including a two-platform equality over one universe, a
  midnight-boundary case, the `· N done` summary line, and a verbatim-legacy comparison for macOS's
  `doneTasks` in **both** modes.




- [T-147] **A cancelled task is unreachable on iOS — decided: show them in Completed.** Every list
  query filters cancelled out (`CadenceTaskQuerySupport` ×6, `CadenceCalendarPlanningSupport`,
  `iOSSearchView` ×2, the note `[[task:` picker) and the inspector auto-dismisses on Cancel, so on iOS
  cancelling is deleting without saying so. **User's call: cancelled tasks appear in Completed**,
  visually distinct — strikethrough, not the green done treatment. macOS already renders a cancelled
  row distinctly, so the row work exists; what is missing is letting them through the queries. Check
  every one of the filter sites rather than the two obvious ones.

  **Shipped in `9d11135`.** Unified `isFinishedTask`/`isOpenTask` predicates in
  `Shared/CadenceTaskQuerySupport.swift` let cancelled tasks reach Completed with strikethrough
  on iOS, across every filter site the ticket named.


- [T-19] **Data safety, backup and controls.** `PrivacyDataResetService` (wipes every model),
  `StoreBackupManager`, and `DataIntegrityRepairService` exist; Settings → Data Safety is the
  surface. Worth reviewing as a whole: what a reset actually removes, whether backups are
  restorable, and whether the controls say plainly what they do. Note the standing rule that every
  new `@Model` must be added to the reset path or a wipe leaves orphans.

  **Narrowed and part-shipped — the export half shipped in `055ecc4`.** The review found the deletion half done
  and the *keeping* half missing. `StoreBackupManager` does snapshot the store at every launch and
  does restore — but every copy it writes lives in the app's own container beside the store it is
  protecting, `deleteCadenceDataAndLocalArtifacts` deletes all of them, and the file is an opaque
  SwiftData/CoreData store readable only by a build with this exact schema. iOS had **no** control
  over any of it — no create, no list, no restore, no route off the device — so the only
  data-safety action a phone offered was the irreversible one. Two copy defects on macOS's Backups
  card, both of the kind this ticket names: it said backups are taken "before migration work" (they
  are taken at every launch) and never said where they live.
  Shipped: `Cadence/Services/CadenceDataExportService.swift` — one JSON archive covering **every**
  entity in `CadenceSchema`, relationships as id references, image bytes included, pretty-printed
  with sorted keys and ISO-8601 dates so two exports diff; `Shared/CadenceDataExportPresentation.swift`
  (the `FileDocument` and the copy both platforms read); a `.fileExporter` card in Settings → Data
  Safety on **both** platforms, above the delete control; the corrected backup copy. Coverage is
  `CadenceDataExportSurfaceTests`, driven off `CadenceSchema` in the same two steps as
  `CadencePrivacyDataResetSurfaceTests` — a model added to the schema and not to the export is a red
  test, not a quietly incomplete backup.
  Deferred to [[T-274]]: reading an archive back in. The archive decodes as a *value* and that round
  trip is pinned, but nothing applies one to a live store, and the card says so in as many words.
- [T-22] **Audit against Apple's App Review guidelines** before publishing. `docs/app-review-notes.md`
  and `docs/privacy.html` are the existing submission material and are the place to start. Likely
  areas: what the privacy manifest declares versus what is actually collected, Sign in with Apple
  being entitlement-gated and optional, the AI feature requiring a user-supplied key, and EventKit
  usage strings matching real behaviour.

  **Audited 2026-08-24, shipped in `2a5c646`.** Went claim by claim against the code rather than against the
  docs themselves. Two findings, both fixed:
  1. **The Calendar usage string oversold what it withheld.** `NSCalendarsFullAccessUsageDescription`
     (both in `Cadence.xcodeproj/project.pbxproj`'s build settings and the literal
     `Cadence/Info.plist`), `docs/app-review-notes.md`, `docs/privacy.html`, and
     `docs/apple-release-readiness.md` all said Cadence creates/updates/deletes "**scheduled task**
     events" — language that reads as the still-unbuilt task-to-event attachment this file already
     tracks under "What's Not Built Yet" (`AppTask.calendarEventID` has readers, no writer:
     `SchedulingService.swift` only ever assigns it `""`). What the code actually does is broader and
     unrelated to tasks: `CalendarManager.createStandaloneEvent` (macOS, its own doc comment reads
     "direct iCal event, not linked to a task") backs the timeline's and month view's drag-to-create
     flow, `iOSCalendarManager.createEvent` is its iOS counterpart, and `TimelineEventBlock` can
     update or delete *any* event shown on the timeline, Cadence-created or not. Reworded all five
     sites to "create, update, or delete calendar events" plus one sentence stating the writes are
     independent of Cadence tasks, rather than inventing a task-linking claim that isn't there either.
  2. **`docs/support.html`** — listed as a reviewer-facing doc by name in `apple-release-readiness.md`
     — had the same shape of platform gap the push-notification and account-deletion falsehoods did:
     its Calendar-access check named only "macOS System Settings" (Calendar is EventKit on both
     platforms) and its account-deletion bullet said "open Settings, Account" unqualified, which does
     not exist on iOS/iPadOS (`iOSSettingsCategory` has 12 cases, no `.account`). Split both bullets
     by platform and scoped the backup/restore bullet to macOS, since iOS's Data Safety section has no
     backup-browsing or restore UI (`StoreBackupManager.listBackups`/`scheduleRestore` have zero iOS
     call sites outside a doc comment).

  Everything else checked out against the code as written and needed no change: the single
  multiplatform target and single entitlements file (`SDKROOT = auto`, one `PBXNativeTarget`, one
  `CODE_SIGN_ENTITLEMENTS` for both platform configs); the push-notifications section's claim that
  registration happens "at launch on macOS" (`registerForRemoteNotifications` has exactly one call
  site, `CadenceAppDelegate`, inside `#if os(macOS)` — iOS never registers, so the doc's own scoping
  is correct rather than aspirational); local notifications' single `AppStorage` toggle and
  single request site in Settings on both platforms; `AppleAccountManager` being
  `#if os(macOS)`-only with no `.account` case on iOS; the AI key living in Keychain
  (`KeychainCredentialStore`) and `AIProvider` exposing exactly the two actions the docs name;
  Reminders staying in-memory (`[AppleReminderItem]`, not a `@Model`) with `completeReminder` as the
  only EventKit write, gated on `allowsContentModifications`; the account/data deletion sweep
  (`PrivacyDataResetService.deleteCadenceDataAndLocalArtifacts`) running identically on both
  platforms with macOS's confirmation dialog and iOS's typed-`DELETE` sheet both gating the same
  function; no StoreKit, ads, or third-party SDKs anywhere in the tree; and the privacy manifest's
  declared API reasons (`CA92.1`, `C617.1`) matching actual `UserDefaults`/file-timestamp call sites
  with no undeclared boot-time or disk-space API usage found.

- [T-236] **A private `-derivedDataPath` does not isolate a macOS *test* run from another agent's.**
  Measured 2026-08-22. `xcodebuild test -scheme Cadence -destination platform=macOS
  -only-testing:CadenceTests` came back `** TEST FAILED **`, exit 65, **0 compile errors**, with
  **1438 failures and 757 passes** — on bytes that had passed 2194/2194 minutes earlier, and that
  passed 2194/2194 again immediately afterwards. Nothing about the sources changed. What changed is
  that `ps aux | grep "[x]codebuild test"` showed a second agent's run against the live repo, and the
  log showed the test host relaunching under a second PID (`My Mac - Cadence (13229)` then `(13416)`).
  The cause is that the test host is `Cadence.app`, whose app-group container lives at
  `~/Library/Containers/com.haoranwei.Cadence/Data/` — one path, shared by every run on the machine
  regardless of where DerivedData points. The private `-derivedDataPath` isolates the *build*
  products and nothing about the host's store.
  **The tell**, because this is misattributed by default exactly like the shared-DerivedData family
  already in `AGENTS.md`: 0 compile errors, a four-figure failure count, most failures reporting
  `0.000 seconds`, and two host PIDs in one run. It exits 65 like a real regression and like a
  mutation that failed to build, and no line of output says another test host is running.
  **The rule to write down:** check `ps aux | grep "[x]codebuild test"` before starting a macOS test
  run and wait the other one out. There is no flag that buys isolation here.
  A one-line summary of the rule went into `AGENTS.md` beside the private-`-derivedDataPath`
  non-negotiable; the evidence lives here rather than in both places.

  **The rule shipped**: the one-line tell went into `AGENTS.md` beside the private-
  `-derivedDataPath` non-negotiable, in `e1c098a`. Nothing else was open here — the underlying
  contention is environmental, not app code, and the deliverable was always the write-up.



- [T-245] `b613fb1` **The sidebar tint editor offers `Theme`'s six accents, not the list palette.**
  `CadenceColorPalette.destinationTints` is the menu; `ColorGrid` gained a `palette:` parameter
  rather than being forked. This is the one swatch menu that may be built from `Theme` — a
  destination tint is app chrome, not user-owned data — and no accent was added to make it fit.
  Pinned by `CadenceDestinationTintPaletteTests`, including the relation a value list cannot state:
  every `CadenceFeatureDestination.defaultColorHex` must be offered by the menu that edits it.
  **This file lagged the code by two days.** The entry sat under "Open — decided, not started"
  while the fix, its five mutations and its call-site test were all committed, which is the exact
  failure `CLAUDE.md` records against the iOS reminders section: *trust the test, not the task
  list*. Grep the tests for a ticket id before picking it up.

- [T-261] `b613fb1` **One swatch menu for a kanban section's colour, on both platforms.** Closed by
  the same commit as [[T-245]] and stale here for the same two days. macOS's eight won on contents,
  not seniority: iOS's nine were borrowed from `TagSupport.colorOptions`, whose own doc comment says
  tags are deliberately separate, and three of the eight it lent are the pre-T-166 drifted
  near-copies of `Theme`'s amber, blue and purple. Both editors name
  `CadenceColorPalette.offeredSectionColors(for:)` now, pinned by
  `CadenceSectionPaletteConvergenceTests`.

- [T-271] **macOS Goals in mission mode has no route to Edit or Attach List below 901pt of pane.**
  Fallout from [[T-250]]. `GoalInspectorView`'s header carries the only Edit and Attach List buttons
  the mission layout has — and `GoalLinkedListRow`'s per-list detach the only one anywhere — and
  below `CadenceDesktopSplitLayout.goalsSplitMinimumWidth` the inspector is not drawn. It was
  already unusable rather than usable there: measured, the column was handed 340 and showed
  179 / 135 / **9** points of it at the 960pt window floor with the sidebar at 220 / 264 / 390.
  **Shipped in `850af8a`.** The pane decision stands — it is a real drop — but the
  inspector stopped being *only* a pane: below the gate a card **opens** `GoalInspectorSheet`
  instead of selecting into a column that is not there, which is `iOSFeatureRowLink`'s own rule
  ("at regular width the row selects … on the phone the row pushes") spelled for a page with no
  navigation stack. Same `GoalInspectorView`, same closures, no second inspector; Edit and Attach
  List are presented from inside the sheet so nothing has to dismiss-and-re-raise in one update.
  Width borrowed as `goalInspectorPaneMinWidth`, so it is the column restored rather than a second
  opinion. Rejected: a `contextMenu` on the cards (hidden-only route, leaves detach out, and needs
  duplicating onto `GoalDirectionHeaderCard`), a header menu acting on the selection (a page header
  growing per-item commands), an in-place disclosure (scroll inside scroll, relayout on every
  selection), and raising the window floor (measured impossible in [[T-250]] — 1484pt against a 13"
  Air's 1470pt screen). Pinned by
  `CadenceDesktopSplitLayoutTests.goalsKeepsARouteToItsInspectorAtTheWidthsThatDropTheColumn`.

- [D-171] `353bf16` `50429a6` `b6f9ea8` `e6e05a4` `62df126` `263833d` `9714f18` Agents leak
  simulators and MCP servers, and it was measurably starving the machine (T-204). Re-verified
  2026-08-24 rather than re-diagnosed: both halves of the original finding are addressed, by a
  different mechanism than either proposed fix.
  **(a) Simulators.** The ticket asked for a rule that agents shut down what they booted.
  `AGENTS.md`'s simulator bullet instead forecloses the leak at its source: share one existing
  **stock** device, boot it only if none is booted, and never `erase`/`shutdown`/`delete` it — so
  there is no per-agent device to remember to close. `scripts/agent-cleanup.sh` (dry-run by default,
  `--apply` to reclaim) additionally targets devices an agent *did* create by name pattern
  (`Cadence-*-Agent`, `*-Agent[-iPad]`, `agent-t[0-9]+`), and a `SubagentStop` hook now runs it with
  `--apply` after every subagent exits (`.claude/settings.json`), so cleanup no longer depends on
  any agent remembering. Measured live with 14 agents concurrently building/testing: 1 booted
  simulator (the shared stock device), load average 16, 148 GB free — against the ticket's original
  10 booted simulators and a 60.6 load average.
  **(b) `CadenceMCPServer`.** The ticket asked only for a `pgrep -c` in a pre-verification checklist.
  `agent-cleanup.sh` does more: it unconditionally reclaims every exact-match `CadenceMCPServer`
  process (`pgrep -x`, immune to the self-match trap below) whenever the hook runs. Verified live:
  `pgrep -x CadenceMCPServer` reads 0 right now; the 39 hits from an unanchored `pgrep -fl
  CadenceMCPServer` are other agents' own build-script command lines naming the scheme, not leaked
  processes — the same self-match shape as [[T-270]].
  Nothing further to build here; re-open only if a live leak is measured against the current scripts.

- [D-170] `9714f18` The T-236 "belt and braces" guard agents kept writing beside the test-host mutex
  deadlocked the mutex (T-270). Verified by reproducing the exact failure in isolation and then
  disproving it against the fix: a `zsh -c` wait-loop shell whose own command line contains the
  literal `xcodebuild test` is matched by `pgrep -f 'xcodebuild test'` (the deadlock — every waiting
  agent counts every other waiting agent as a running host) and is **not** matched by the anchored
  `pgrep -f '^/Applications/.*/xcodebuild test'` the fix uses. Both `scripts/test-host-lock.sh`'s
  `status` output and `AGENTS.md`'s guidance now use the anchored form; no unanchored spelling of
  the pattern remains in either. Closed.

- [D-169] `e6e05a4` The test-host mutex did not exclude (T-263) — filed independently by the T-21 agent
  and already fixed by the time it reported. Both diagnoses agree and were reached separately, which
  is worth more than either alone: `acquire` recorded the PID of its own short-lived process, so every
  later caller found the lock "stale" within seconds and took it. Measured by that agent as a lock
  stolen inside 90s and **three** concurrent macOS test runs — the fix for T-236 reproducing T-236.
  Now records `$PPID` (the caller's shell, alive for the run) and refuses a release from a foreign id
  while the owner lives.

- [D-168] `3392fd3` Refusing the reminders prompt says "denied" (T-21).
  EventKit keeps reporting `.notDetermined` after a refusal, so both iOS surfaces offered an Allow
  Access button the OS will never answer again. Fixed with an observable `deniedInThisSession` behind
  a shared rule. The state map is otherwise clean — "no reminders" copy is reachable only inside
  `.connected`, so the classic misleading default is absent.
  **Keep the test lesson:** the predecessor's scan asserted a symbol name that also appears in the
  manager's *doc comment*, so deleting the real call left the suite green. Mutation caught it; the
  repair uses `strippingComments` plus a guard that the stripper ran.

- [D-167] `c82e120` The section palette gets an address, not new `Theme` accents (T-246). No resolved
  hue changed — 31 values compared programmatically, 0 differences. The ticket's count was off by one
  (`#4ecb71` was already a token) and the agent's own value test caught its own miscount. Mapping the
  eight kanban colours onto `Theme` was rejected as *structurally* impossible: six accents cannot
  supply eight distinct swatches, and two of them collapse onto amber. Keep the distinction it drew —
  a swatch **menu** is the "user-owned `colorHex`" clause of the no-hardcoded-colour rule, not the
  `Theme.*` clause. Found a real defect in passing: the macOS grid compared case-sensitively with no
  keep-the-stored-value rule, so a section wearing an unoffered hue showed nothing selected and the
  next tap silently replaced it.

- [D-166] `635720c` Archiving a list on iOS settles its remaining work, behind a confirmation
  (T-215). Sixth `#if os(macOS)` around code importing nothing platform-specific. The ticket said
  "one line"; it is not, because **archive is advertised as reversible and the cancellation is not**,
  and on iOS archive is a row *swipe* — the literal one-liner would have made one flick irreversibly
  cancel N tasks. The confirmation is conditional, so an empty list is still one flick, and it counts
  the settle's own array rather than a re-derived one. Does **not** close T-214: it resolves that
  ticket's premise, but iOS still offers no Complete action for a list.

- [D-165] `e181dea` Cmd+K asks the sidebar what colour a destination is (T-244). The ticket
  undercounted twice: three rows disagreed, not two (Settings was grey against the sidebar's blue),
  and there were **seventeen** dead literal fallbacks, not eight — and those fallbacks were the
  *pre-T-166 drifted* values, a frozen snapshot of a sidebar that had since moved twice. Fixed the
  same defect on iOS Search, which read `destination.tint`: right hue, but a default is not an
  override, so it silently disagreed for any retinted row.

- [D-164] `69b0237` A write tool missing from `writeToolNames` is advertised in read-only mode
  (T-126). The smoke test is data-safe — `CADENCE_MCP_STORE_URL` is honoured before the real store
  and the audit log and refresh marker derive from the same resolved URL — verified by 46 store files
  being byte-identical across a run. The finding is coverage: 30 router arms, 21 dispatched, and five
  of eight write tools never exercised. Filed T-259, T-260.

- [D-163] Three doc-accuracy tickets closed, and two of the three had largely been overtaken
  (T-198, T-199, T-216). Every claim re-derived against `HEAD` rather than trusted.
  **T-216 was entirely obsolete**: `Cadence/Services/` already reads 49 in all three guides, the
  `macOS/Services/` bullet already says **three** tombstones, and `CLAUDE.md`'s structure block,
  iOS Lists line and `Shared/` inventory (`CadenceListDeletionSummary.swift`) were all current.
  **T-198's six counts were all already fixed** — and four had gone stale *again* in the other
  direction, which is the finding: `Cadence/iOS/` 90 → **93** in six places and `CadenceTests/`
  171 → **177**. Counts were taken from `git ls-files` at `HEAD`, not the worktree: with eight
  agents live the worktree read 94 / 180 / 50 / 21 for iOS / tests / Services /
  `Shared/Components` from untracked files whose authors had not landed yet — and three of those
  four moved *while this entry was being written*. Counting the worktree would have made every
  figure wrong the moment those commits landed. `Cadence/Services/AGENTS.md` is currently the one
  guide reading 50, bumped by the agent adding
  `Cadence/Services/CadenceTaskContainerLifecycleService.swift`; the root guides stay at 49 until
  that file is committed, and whoever lands it owns bringing them along.
  Still stale and fixed from T-198: **there is no `BoardColumnHeader`.** Three guides spelled the
  header that way in five places (`AGENTS.md`, `CLAUDE.md` x3, `macOS/Views/AGENTS.md`); the type is
  `CadenceBoardColumnHeader`, it lives in `Shared/Components/`, and iOS's list kanban, Calendar
  Board and month agenda all render it — while `KanbanCard` and `KanbanColumnScroll` really are
  macOS-only. The bullet had been landing as "a cross-platform trio", which is two-thirds wrong in
  the direction that invites a fork. T-198's third sub-claim (`iOSListSupportViews.swift:424`) was
  already repaired — that comment now says "the vocabulary the three *macOS* boards share".
  From T-199: `HabitInsights` is **not a type** (`Models/HabitInsights.swift` is a bare
  `extension Habit`) — corrected in `CLAUDE.md` and `Models/AGENTS.md`. The three T-120 calendar
  files `CadenceCalendarDayBadge` / `CadenceCalendarDateTitleSupport` /
  `CadenceCalendarTimedGridSupport` (and `CadenceLazyScrollAnchor`) have **zero** readers under
  `Cadence/macOS` and are now labelled iOS-only-in-practice, with the general point stated once:
  living in `Shared/` says what a file may import, not that both platforms read it.
  T-199's settings claim was **wrong about the code**: it said macOS lacks `sync`, `coverage` and
  `about`, but `592b967` added `.sync`, `940c4da` added `.about` and deleted `.coverage` outright,
  so macOS offers all **14** `CadenceSettingsCategoryKind`s and the relation really is one-way.
  iOS has **12**, not the 13 the ticket claimed; `CLAUDE.md`'s iOS Settings line listed nine and
  silently dropped `sync` and `ai`, and now enumerates all twelve.
  T-199's recurrence claim was right but understated. The inline "APPLY TO" row is not just
  macOS-vs-iOS — it is **one surface**, the macOS task inspector. The `confirmationDialog` it
  "replaced" is still live in three places including macOS's own `TaskEmbedFieldEditorPopover`.
  Also corrected there: the type is `CadenceTaskRecurrenceEditScope`; no unprefixed
  `TaskRecurrenceEditScope` exists.
  Two stale claims found outside all three tickets and fixed in passing, both in
  `Models/AGENTS.md`: it called `ModelEnums.swift` "the eleven data enums" while listing and
  holding **ten**, and it still carried the refuted "a duplicate `GoalListLink` double-counts that
  list's tasks" rationale that `CLAUDE.md` already records as false (`contributingTasks` ends in
  `dedupe(...)`). Docs only; no source changed.

- [D-162] The iPhone More tab was already grouped, and nothing pinned the grouping (T-169). The
  ticket's premise — "`iOSMoreTabView` is currently the six destinations … in one flat list" — was
  false against `HEAD`: `CadenceFeatureDestination.compactMoreSections` has held three
  `CadenceFeatureSection`s (Progress: Focus, Goals, Habits │ Organize: Lists │ Workspace: Search,
  Settings) for some time, the view draws an eyebrow per section, and that is exactly the grouping
  the ticket prescribed. No design change was made or needed.
  What was missing is the reason the ticket could have been "done" twice: **every existing test
  flattened the sections before looking at them.** `everyDestinationIsEitherATabRootOrReachableFromMore`
  opens `compactMoreSections.flatMap(\.destinations)`, so it passes identically against one section
  holding all six rows — the flat list the ticket was filed about was, and had always been, one
  refactor away with the whole suite green. Now pinned in `CadenceCompactTabTests`: the three groups
  as literals (kinds, eyebrow titles, membership, order), the exactly-once/non-empty/unique-`id`
  invariants, no tab root smuggled into a group, and — because `Cadence/iOS/` is invisible to the
  macOS-built target and a correct value read by a flattening view is T-161 exactly — a source scan
  of the nested `ForEach` + `SectionEyebrowLabel` structure, with a non-vacuity guard.
  Worth keeping: the ticket was written from `CLAUDE.md`'s account of the More tab rather than from
  the file, and the file had moved on. Read the code before believing a ticket's "currently".

- [D-161] `223e46a` Drop a task on a task on iOS and the two become a block (T-190). The ticket's
  central claim was false — there was a third `TaskBundle(` constructor in `Shared/`, in a file with
  no `#if` at all, and iOS's quick-create Block segment had been calling it all along. The one real
  gap was the *gesture*, behind `#if os(macOS)` in a file importing no AppKit — the fifth instance of
  that shape. Unifying surfaced two divergences between the two copies (one cleared
  `calendarEventID`, one clamped the start minute) and both were resolved toward the careful version.
  Verified by dragging one card onto another on an iPhone 17 Pro: 30 + 25 minutes of estimates became
  a 9:30–10:25 block, which is arithmetic rather than a screenshot's word.

- [D-160] `8b743d0` Two ambers, one Today row (T-166). Not eleven literals but ten, and the real
  finding was that three of five hues had **drifted** from the `Theme` families they copied — with the
  drift on screen, since Cmd+K derives its tints from `Theme` while the sidebar used the literals.
  Deliberately a change of appearance: seven defaults move to the `Theme` value, no stored user tint
  is touched. The pure refactor was rejected because it would have added a second amber, blue and
  purple to a palette whose own comment forbids exactly that.
  Keep the test shape: the mutation that matters replaces a token with **its own current value** as a
  literal, which every value assertion passes and only the source-scanning relation catches.

- [D-159] `aa33ae6` Archiving a list timestamps the cancellations it produces (T-212), and still
  spawns nothing. Half the ticket was right — bulk cancel hand-wrote `completedAt = nil`, so archived
  work reached no Today section on macOS. The other half prescribed routing bulk settle through
  `markDone`/`markCancelled`, which would have inserted fresh **open** recurrence occurrences into
  the very column just archived, since `makeNextRecurringTask` copies `area`, `project` and
  `sectionName`. Not implemented, and a test now implements it as written and fails, so the wrong fix
  is pinned against rather than just avoided. New shared `settleWithoutAdvancingSeries` carries the
  decision. `TaskContainerLifecycleService` had zero coverage before this.

- [D-158] `4fe809f` Privacy Policy and Support belong to About on both platforms (T-220). The old
  doc comment justified the split with "iOS files them under About because iOS's Data Safety screen
  does not carry them" — a description of an accident, not a defence: that screen had no delete route
  at the time. Neither link is a data-safety control, and a help link one tab-stop from an
  irreversible delete button is the misread `.about`'s group-of-one exists to avoid.
  `CadenceAppReferenceLink` is now the one source for URLs *and* titles, glyphs and fallback copy —
  the URLs were already shared, which is exactly why the hand-typed titles had drifted
  ("Notepad"/"Permanent note"). `SettingsReviewLinksSection` renamed to
  `SettingsPrivacyStatementSection`, because a struct named for links it no longer has is how the
  page-header `subtitle` parameter survived three deletions.

- [D-157] `13dd01c` Notes reached from the Notes page or a list can say what points at them (T-224).
  Three sites presented the editor over a real `Note` and passed it nothing, so
  `refreshReferenceContents` wrote empty contents and the panel rendered `EmptyView` — the same note
  showed its backlinks from Search and not from the Notes page. The test states a **relation** (every
  editor in a note-editing host carries an `editingNote:`) rather than a count, since a count is
  satisfied by the wrong pane and goes stale when a pane is added.

- [D-156] `64df379` A normalizer was calling a transition, so renaming old work re-finished it
  (T-213). `normalizeCompletionState`'s `.done` branch called `markDone`, which stamps
  `completedAt = now` **and** spawns the next recurrence — so editing any of seven fields on a task
  finished last week pulled it into Today's Completed, and on a done recurring task minted a new
  occurrence every save. The ticket described the trigger wrongly (open/close does not save) and
  missed the spawn entirely. Fixed to `case .done, .cancelled: break`, which is what the function's
  own doc comment already claimed while the branch below contradicted it. Clearing the timestamp
  would have been the wrong fix and a test asserts the opposite polarity to prevent it.

- [D-155] `23210b9` The 100pt band under every iPad list tab was the floating `+`'s clearance,
  inherited. Reported as a Notes-tab bug, then corrected to "it's in all tabs" — which was the
  diagnosis: `iOSListDetailPagePicker` sits above `pageBody`, so one defect appears on five tabs.
  `.iOSFloatingCreateTaskButton(seed:)` sets `.contentMargins(.bottom, scrollClearance, …)` for the
  page's own list, `contentMargins` is inherited through the environment, and a `.bottom` margin on a
  **horizontal** scroll view grows its *cross* axis — so a 44pt tab row became 144pt. Reset on the
  strip, matching the two markdown accessory strips (D-104), so the next host is fixed too. Hairline
  230pt → 130pt.

- [D-154] `6c915fd` The bundle panel dismissed itself for the same reason the task inspector did
  (T-217). T-201 fixed four surfaces where a row owned the `.sheet`; `iOSCalendarBoardBundleCard` and
  `iOSTimelineBundleBlock` had it for `TaskBundle` and were missed **because the shared helper was
  named for tasks**. So the fix is mostly a rename — `CadenceTaskInspectorPresentation` →
  `CadenceDetailPanelPresentation`, `task` → `subject` — plus `iOSBundleInspectorHost` applied once in
  `iOSRootView`. `iOSCalendarDayInspector` and `iOSCalendarMonthAgendaList` deliberately keep their
  own `.sheet(item:)`: not being inside a filtered `ForEach` over what they present, they cannot show
  the defect. Worth remembering as a naming lesson, not just a bug fix.

- [D-153] `e79225a` Editing a note's `# H1` syncs back to `note.title` on iOS too (T-223). macOS did
  it inline in `NoteEditorPane`, so iOS had nothing to call; now `MarkdownNoteTitleSync` in
  `Services/MarkdownNoteSupport.swift` and both platforms call it. `iOSNoteDetailSheet` also stopped
  writing `note.content` directly and goes through `CadenceCoreNoteSupport.update`.

- [D-152] `e79225a` A test named for writes was banning reads, and blocking a real improvement
  (T-233). `onlyTheSharedFilingHelperWritesAFolderPath` banned `.folderPath` reads as well as
  assignments, so *displaying* a note's folder failed a test about *writing* it — the fourth instance
  of T-227's shape (a name narrower than the assertion it guards). Split to
  `\.folderPath\s*\+?=(?!=)`; the negative lookahead is what keeps `==` legal. With reads allowed,
  `CadenceNoteDeletionSummary` gained the `folder` field, so a confirmation for one of several
  "Untitled" notes can say which one.

- [D-151] `9d3e0d6` The near-copy calls the shared predicate rather than the predicate being deleted
  (T-234). The ticket said `CadenceNoteFolderPath.isRoot` was dead with zero production readers, and
  it was — because `CadenceNoteFolderGroup.isRoot` re-spells it as `folderPath.isEmpty` a few lines
  below. A dead-code pass found a shared predicate unused while a duplicate of it shipped; deleting
  the shared one would have been the wrong half of that observation. Two test readers also existed, so
  "delete it" would have taken assertions with it.

- [D-148] `605a793` `f611bd2` The widgets scheme was never shared, and it was building the whole app
  (T-231, T-230, T-232). Only `Cadence` and `CadenceMCPServer` were in `xcshareddata/xcschemes`;
  xcodebuild reported `CadenceWidgets` and wrote nothing to disk, so **every "baseline holds on all
  three schemes" claim made today rested on in-memory autocreation**. Worse, the autocreated scheme's
  build action contained the widget *and the host app* — established properly, by capturing
  `-showBuildSettings` before and after and noticing the first attempt did not match. So a
  widgets-scheme run was compiling the whole application; the shared scheme reproduces that
  deliberately, byte-identical on both destinations.
  T-230: macOS gated New Folder's Create on the **raw** string while iOS gates on the normalized one,
  so `"//"` filed the note at the root — a New Folder that makes no folder. T-232 removed five dead
  things on a *specific* safety argument: the `calendarEventID` hazard is about **stored SwiftData
  properties**, and none of these was one.
  The agent **declined** to `git rm --cached` the tracked per-user plist, because a staged deletion in
  a shared index is what another agent's `git add` sweeps up. That was right; `f611bd2` did it as its
  own immediate commit instead.

- [D-149] `028b081` Six source-scan assertions — three could fail on correct code, three could not
  fail (T-227, T-228). The technique that caught real regressions all day produced every defective
  assertion in the batch.
  The sharpest fix made a defect *visible*: `CadenceWriteServiceTests` could not see the **re-stamp**
  half of the cancel guard, because the DTO formats `completedAt` at second precision. The mutation
  now fails and prints both values as **equal** — `2026-08-21 11:35:40 +0000` twice. Under the old
  form both DTO-string *and* both audit assertions passed.
  The agent also found the same trap **one size down**, unreported: the positive-form literal
  `"tasks.filter { $0.isDone }"` is contained in `"…}.count"`. Each fix proven in the direction that
  matters — legitimate-edit-stays-green for kind one, mutate-what-you-pin for kind two — nine probes,
  every red at exit 65 with **0** compile errors, each failure message pulled from the `.xcresult` to
  confirm the intended assertion fired. Two of those mutations live inside `#if os(iOS)` and compile
  to nothing on macOS, which is the argument for those pins existing at all.
  Durable output: a new `Shared/AGENTS.md` section on how these go wrong, pointed at from one line in
  the root guide rather than restated.

- [D-150] `4e6080e` iOS can delete a note, and the image sweep moved inside the delete (T-226).
  The two macOS delete sites **agreed**, and neither was the right one — they were two spellings of one
  operation, the shape that eventually drifts. Both ran
  `deleteUnreferencedMarkdownImageAssets`, the forgettable step, so it is inside the shared
  `deleteNote` now; macOS was not leaking assets, but a third caller would have been the one to.
  Copy Note Link shipped only where macOS has it, and delete on the Notes tab follows macOS's rule —
  Notepad rows only, because dated and event notes are manufactured from their date so deleting one
  is a no-op behind a dialog. The confirmation states what survives as well as what goes, and the
  image count is the set the sweep will actually collect rather than the note's image references,
  which is larger and would over-promise.

- [D-146] `7a0c3e1` The reason given for idempotent attach was false, in five places. Found by an
  independent verifier attacking my own claims, and it is the **same mistake `D-139` caught and
  reverted two batches earlier** — then repeated by me and written into the guides. A duplicate
  `GoalListLink` cannot double-count the percentage: `contributingTasks` ends in `dedupe(...)`,
  filtering by task `id`. Proven the only way that counts — removing `attachList`'s early return left
  the test named for that symptom **passing**.
  Renaming the test was not enough, and my first pass stopped there: the body still asserted
  `totalTasks`, which the dedupe protects either way. It now asserts `linkedListCount` and the link
  count, and is confirmed to fail under the mutation at 0 compile errors. Also fixed an ordering
  assertion that compared a value to itself, and untracked a committed `default.profraw`.

- [D-147] Independent verification of the composed HEAD. All five runs exit 0 with **0 compiler
  warnings** and 2175 tests; the MCP smoke test passes 20/20 against an isolated fixture store. Ten
  mutations, each with its compile-error count, including a **calibration mutation** (a deliberate
  typo) to demonstrate that exit 65 alone cannot distinguish a caught mutation from a build failure —
  the trap I fell into earlier. Two source-scan tests were shown to genuinely observe iOS-only code
  the macOS test target cannot compile. All six attacked claims held except the `GoalListLink`
  rationale ([[D-146]]).

- [D-143] `de32a59` Three batches of doc debt, plus a fix that never reached the scoped guide
  (T-218, T-219). The finding that outlives the ticket: `1d81864` corrected two false
  `calendarEventID` claims in `CLAUDE.md` and **never reached `Cadence/Models/AGENTS.md`**, which
  carried the same two — and the precedence rule says the scoped guide is *closer to the code*, so the
  fix corrected the less authoritative copy and left the more authoritative one wrong. Three more were
  stale the same way, including a tombstone `CLAUDE.md` said "could be deleted" that `6f71a70` had
  already deleted.
  Counts were written against **HEAD, not the worktree**, deliberately: two agents were mid-flight
  adding files, and a count that is one *low* reads as "add one when you add one" while one that is
  too *high* reads as a complete inventory — the `CompactTagStrip` failure mode exactly.
  T-219 was verified rather than assumed and really was a swap: every figure agreed, differing only
  in `ForEach` identity spelling with identical semantics. The agent also caught five errors in its
  own drafts before reporting.

- [D-144] `0332255` A note can say what points at it on iOS (T-192). The resolver was already shared,
  unguarded and platform-independent, and `Cadence/iOS` called it **zero** times — it only ever
  *followed* a reference. So the panel is a call site, not new logic, built from the existing
  suggestion strip, which is also why the toolbar `contentMargins` fix survives: the panel reuses the
  strip that carries it. Ambiguity inherited verbatim rather than re-decided — id beats title, a
  title-only reference takes the first case-insensitive match, an unresolvable one is absent because
  macOS draws no broken chip either. **The third substring trap of the day**, caught in the act: an
  absence assertion on `".white"` fires on `".whitespacesAndNewlines"`.

- [D-145] `676ff3b` Note folders reach iOS, and the tab was showing one note not a flat list (T-193).
  The premise understated it in a way that changed the work: iOS's list Notes tab showed **exactly one
  note per list**, so folders were invisible because the notes were. The convention was read off all
  four macOS call sites, and nesting is **representable but deliberately not a tree** — every surface
  groups on the whole normalized string, so `Planning` and `Planning/Research` are siblings.
  Two findings worth keeping: one macOS context-menu site wrote `folderPath` **unnormalized**, safe
  only because its own menu values happened to be normalized; and `DataIntegrityRepairService`
  assigns **raw**, which is why paths must be normalized on *read* as well as write — pinned by a test
  that writes the property directly on the model, bypassing the writer.
  No pane added: a folder is a heading inside the existing column, so the notes split's floor is
  borrowed rather than duplicated.

- [D-140] `940c4da` The parity manifest is gone; macOS now offers every settings category
  (T-197, T-196, and T-210 with it). Coverage deleted whole — section, type, status enum, row view,
  iOS case and the shared `.coverage` kind — because leaving a case routing somewhere empty is how
  `subtitle` survived three deletions. It could not have been persisted (both surfaces hold selection
  in `@State`; no AppStorage key, deep link or palette command), and a test pins that
  `rawValue: "coverage"` is now nil. T-196's two gaps were **rendering-only**, verified first.
  Side effect: with `.sync` in and `.coverage` out, macOS offers **every** shared category, so the
  parity relation is one-way — iOS lacks `sidebar` and `account`, macOS lacks nothing. That closed
  [[T-210]] as a set-equality assertion instead of a `desktopOnly` analogue.

- [D-141] `4562d4e` The task inspector outlives the row that opened it (T-201). Four presenters
  converted, one host in `iOSRootView` over an environment action so no call site can hold the
  selection. The other four were left because converting them would have been **wrong** — three
  present from inside a sheet, where a host above is already presenting and a second request silently
  does nothing.
  **The measured finding that changed the fix:** guarding on `isDeleted` alone is insufficient and the
  agent's own test killed its first draft. Between `delete` and `save`, `isDeleted` is true with
  `modelContext` set; **after the save `isDeleted` reads false again** while `modelContext` goes nil
  and the property snapshot stays readable — a stale panel looks alive. Rule is
  `isDeleted || modelContext == nil`, both phases pinned, and the doc states the honest bound: neither
  signal is observable, so a CloudKit delete closes on the next re-render, not instantly.
  Proven with a pre-fix binary built alongside, Start control re-run on both.

- [D-142] `23eb847` A goal's progress counted linked lists iOS could neither see nor change (T-191).
  No shared path existed to reuse — macOS spelled `insert(GoalListLink(...))` inline in **four**
  places — so one now exists, with a target type that makes the model's exactly-one-of invariant
  unspellable-wrong and an idempotent attach. **The reason first recorded here was false** and is
  corrected in `D-146`: a duplicate cannot move the percentage, because `contributingTasks` dedupes
  by task `id`.
  The explanation ships with the section, since the complaint was explanatory; for an hours goal it
  says progress tracks logged hours, because there the lists move the count and not the bar.
  Two self-caught errors worth keeping: its first scan used a substring count and
  `toggleGoalListLink(` *contains* `GoalListLink(`, so it accused its own four rewired call sites —
  the same trap that bit another agent today. And the iPad caught "2 contributing tasks" truncating
  to "2 contributing t…".

- [D-136] `6f71a70` Two leftovers gone; the duplicate edit scope had **two** bridges (T-200).
  The second lived in `TaskInspectorWorkflowSupportViews`, unmentioned by the ticket. Safe to collapse
  because it is a *type*, not a stored property — nothing persists its raw value — which is the exact
  distinction that makes `Goal.dependsOnGoalIDsJSON` unsafe to remove. Renamed rather than
  typealiased, so both platforms' recurrence code reads identically.

- [D-137] `1d81864` The review notes denied push; the privacy policy never mentioned Reminders
  (T-205, T-206, T-207). Root cause of the push falsehood recorded: `CLAUDE.md`'s Notifications
  section documented only *local* notifications, so nothing in the working map contradicted it. The
  new test rejects denial phrasings rather than pinning wording. "Never creates or deletes reminders"
  was verified, not assumed — no `EKReminder(` exists repo-wide.
  Three counts were wrong in instructive ways: `CadenceTests` is **167** so the ticket's own 164 was
  already stale; `Cadence/AGENTS.md` said iOS was **79**, the worst of five figures and in a guide the
  root file says to read first; `Editor/AGENTS.md` said ~21 markdown support files while its own glob
  returns 27 and only 25 end in `Support.swift` — number and pattern never matched.
  And the `calendarEventID` enumeration was worse than "one missing": **two of four credited files
  were wrong**. `TaskDeleteHelpers` never mentions the field; `DataIntegrityRepairService`'s mention
  is on `Note` inside note-merging. Verified both independently. `InboxView` was also named in four
  places and has not existed since `7e5459c`.

- [D-138] `c84732e` Deleting a list reaches iOS, and it enumerates what it will take (T-187).
  The helper was **not** purely un-guardable: all three cascades call `deleteTasks(withIDs:)`, which
  is genuinely macOS-only (it tears down the focus, hover, completion-animation and subtask-entry
  managers). One seam remains by necessity and a test fails if a second appears.
  Confirmation is a modal sheet, and *more* informative than macOS rather than merely as ceremonious
  — it shows real counts where macOS's categorical sentence cannot. No typed phrase, deliberately: a
  list delete is scoped and now shows its scope, unlike the total, unreportable privacy reset.

- [D-139] `f15db8b` A cancellation is timestamped, and two other things were undoing it (T-202).
  macOS was **strictly worse** than iOS, not equivalent: `TasksPanelDerivedState` has no date
  fallback at all, so *every* cancelled task was excluded there. And `normalizeCompletionState`
  cleared the timestamp on the iOS sheet's save — the very surface the report came from — so Cancel
  stamped it and closing the sheet wiped it. Two MCP idempotency guards would also have broken
  silently, re-stamping and duplicating audit entries on re-cancel.
  **The best thing in it is an edit that was reverted.** An `isDone` guard added to the goal Momentum
  count looked obviously right and its mutation *survived*, because `contributingTasks` already
  filters cancelled work upstream. A guard that compiles, reads plausibly and cannot be killed is
  worse than none.

- [D-132] `d513e72` One heading ramp per platform; the tile corner was never size-relative
  (T-180, T-178). The same note showed an H1 at 28pt editing and 25pt in preview, and preview's
  `default:` swallowed levels **5 and 6**. iOS took the editor's ramp because it was the only one of
  the two already complete at six levels — adopting preview's meant *inventing* the H5/H6 the ticket
  exists to supply. macOS stayed separate on a better argument than "tiers": a ramp only means
  something against the body under it, and 14pt fixed `NSFont` vs a 17pt-and-growing Dynamic Type
  body makes macOS's *larger* ramp the *steeper* one.
  T-178's renders **overturned the premise**: `min(12, size * 0.28)` saturates at 42.86pt so it only
  ever evaluated 8.96 and 12 — both within 2pt of the token, and at 32/34pt the token reads rounder.
  The visible work was the *curve*, not the radius; `.continuous` is what makes the token safe at 56pt.

- [D-133] `29bb223` Six expressions of the pane-width rule, left in five files (T-182). My own debt,
  and my count was short by two — `CadenceCalendarWeekGridLayout` (already in the house file) and all
  of `CadenceRootShellLayout`, whose doc cites the rule without being counted as holding it.
  Left separate because **co-location was never what prevented this**: three of the six already
  cross-reference each other by name across file boundaries and a fourth copy still got written.
  Comment-only diff over five files. The guard test asserts *placement* and *that each floor is
  spelled as a sum*, because the existing numeric pins cannot fail when a sixth floor appears in a
  new file — which is what happened at `d0adfdc` with the suite green.

- [D-134] `592b967` A recurring task made on iPhone repeated forever; macOS could not see iCloud
  (T-188, T-189). Both were shared-logic-with-a-missing-surface. The subtlety: selecting an end mode
  must **seed** its value, because `effectiveRecurrenceEndMode` degrades an empty date or zero count
  back to `.never`, so without the seed the picker looks like it refused the tap. macOS needed no new
  category — `.sync` already existed and macOS never offered it. `CKContainer` is now called in
  exactly one file app-wide, verified independently.

- [D-135] Independent verification of HEAD. All five runs exit 0 with **0 compiler warnings**
  (`Cadence` macOS + iOS, `CadenceWidgets`, `CadenceMCPServer`, `CadenceTests`), and all six claims
  attacked held — including two mutations at exit 65 with **0 compile errors**. The composition risk
  I was worried about did not materialise: ~15 changes each verified as HEAD-plus-its-own-files do
  compose. Two document falsehoods found ([[T-205]], [[T-206]]) and several stale counts ([[T-207]]).
  **The verifier itself got one thing wrong** — it reported the Inbox reminders strip as macOS-only;
  it is at `iOSTaskCollectionPage.swift:94`, shipped in `d330f5e`. Verify the verifier too.

- [D-131] `1136558` The Board's Completed split was right only by accident (T-203). Both day columns
  spelled it `!$0.isDone` / `$0.isDone`, so a cancelled task — not `isDone` — would have landed in
  the **active** half; it never arrived only because `tasksByBoardDate` drops it upstream. Both now
  read `isFinishedTask`. The policy is unchanged and finally documented where the guard lives.
  **A no-op today by design**, which is why it needed a source scan: the T-147 pinning test passes
  unchanged *and also passed under the mutation*. macOS could only be captured partially and the agent
  said so — `ImageRenderer` cannot draw a card stack inside a `ScrollView` — but the column header
  counts 1 with the fix and 2 with the mutation, which is the bug and its absence.

- [D-130] T-32's feature-consistency scan is done; its findings are now T-187 through T-200.
  13 findings, 11 of them accidental gaps, and **10 of those sit on logic that is already shared** —
  the platform guard is the only thing in the way. Two are reverse-direction (macOS missing what iOS
  has), which the "iOS is not guaranteed parity" framing in `CLAUDE.md` structurally hides. Eight
  things it checked turned out deliberate or already closed, including both gaps T-32's own entry
  named as prerequisites, and it confirmed the interaction-modality table in `Shared/AGENTS.md`
  reproduces exactly while the older figures do not.
  **Recorded late, and that is the lesson.** The scan finished hours before this entry; three
  findings became tickets because the user happened to be asked about them, and the other ten lived
  only in a finished agent's transcript and one chat message. An audit that is not written down is an
  audit that has to be run twice.

- [D-127] `7b48808` The privacy policy promised iOS a deletion it could not reach (T-184).
  `PrivacyDataResetService` was 45 lines behind `#if os(macOS)` with **zero** AppKit — the
  `RemindersManager` shape a third time, and this one made a submission-facing document false.
  The confirmation matches macOS's *bar*, not its mechanism: the literal iOS translation of a
  window-modal dialog is a bottom action sheet, which is one thumb-reachable tap and strictly weaker,
  so the destructive control never appears on the settings screen at all and sits behind a typed
  `DELETE`. The schema was already fully covered — 20 entities, 20 deletions — but **nothing was
  checking**, so the check is the gain: a two-link chain off `CadenceSchema.entities` that fails if a
  model is added without a deletion. Two further doc falsehoods fixed: the review notes claimed a
  macOS-only target for an app that builds `iphoneos`, and the Apple-identity paragraph omitted that
  Sign in with Apple is macOS-only.

- [D-128] `2bf503b` AI actions reach iOS, and `normalizedDate` could hide a task (T-185).
  The service needed only its guard removed — nothing moved, so none of the `.stringsdata` trouble.
  **The bug:** `normalizedDate` validated by parsing and returned the string *as typed*, and
  `DateFormatters.ymd` is lenient about single-digit months, so `"2026-8-20"` reached
  `TaskCreationDraft.dueDateKey` verbatim. Every date comparison in Cadence is a string comparison
  against canonical `yyyy-MM-dd`, so that task was due on a day no "due today" check, group heading
  or sort key could see. `applyTaskDrafts` now has exactly one caller in the app, inside a gate that
  guards on validity itself, so losing a `.disabled()` cannot write. Unexercised without a key and
  said so: the HTTP round trip, `testConnection`, and the error alerts.

- [D-129] `f1e3dc8` iOS banked focus time on switch instead of discarding it (T-186). Both entry
  points were wrong — the row tap and the play button — and fixing one would have left the bug half
  present. No new arithmetic; the roll-up was already shared and correct. Two deliberate
  consequences documented at the call sites: re-selecting the focused task no longer zeroes its
  clock, and both paths read `selectedTask?.id` because with nothing picked the session runs against
  `readyTasks.first`. iOS has no bundle focus at all, pinned by a test so a future bundle path fails
  until it commits too. Demonstrated on device: 02:46 → `3m/30m`, then 01:55 → `5m/30m`, with the
  hours-mode goal reading FOCUS 5m.

- [D-126] `fdd04a8` A heading holding only a carriage return went 30pt bold and lost its marker
  (T-181). macOS re-derived the visible-content test locally, trimming `.whitespaces` where the
  shared function trims `.whitespacesAndNewlines`. Reachable, not academic: lines come from
  `components(separatedBy: "\n")`, so on a CRLF note `"# \r"` read as *having* content — marker
  hidden, line set 30pt bold, a tall blank row with nothing left to click the caret into, and
  `NSTextView` does not normalise line endings on paste. This is [[T-121]]'s payoff rather than a
  separate fix: the duplicate was invisible while the logic sat inside `#if os(iOS)`.
  Two process notes. The agent stalled after writing and never reported, so the work was verified
  from scratch rather than accepted. And my first mutation left an orphan paren and failed to
  *compile* — which reads as a passing mutation test if you only check the exit code. Repaired to 0
  compile errors before trusting it.

- [D-125] `d0adfdc` The notes split asks how wide it is, not what size class it is in (T-177).
  A 320pt inspector pane minus a fixed 280pt list and a 1pt divider left **39pt** of editor. The floor
  is a sum (`regularColumnWidth + divider + minimumEditorWidth` = 601) so raising the list column
  moves it automatically. The 320pt editor minimum was **borrowed** from `inspectorPaneMinWidth`,
  already documented as "the least the notes/timeline inspector will accept before its own content
  starts clipping"; the rejected alternative was the phone anchor at 375, which floors at 656 and
  would have converted an 11" iPad's *tight* 365pt editor into a fallback. A floor names where two
  columns is worse than one, not where it is ideal.
  `inspectorPaneFloor` was deliberately **not** raised: that would push Today's two-pane minimum to
  1042 and cost a 13" iPad in portrait its task column — the page's subject — to fix the pane's other
  tenant, when Timeline is verifiably fine at 320.

- [D-124] `7c964a6` The markdown styling layer split, and 14% of it was logic tests could not see
  (T-121). ~150 of 1,067 lines were decisions about what a string means, now in `Services/` with 40
  tests: the hidden-marker arithmetic for image refs, `[label](url)` links and `[[wiki]]` refs (pure
  inline math nothing could observe, and when wrong it swallows a line's first character), and
  `MarkdownStyleSignature`, the gate in front of the whole rendering pass. Two duplicates closed —
  the table-grouping walk existed **three** times, two of them the same walk down to the delimiter
  filter, and the unanchored image-reference regex was written out verbatim twice. Relocation proven
  inert rather than asserted: 0 of 3,125,760 pixels differ between pre- and post-change builds of the
  same probe note.

- [D-121] `dd66f51` The settle test waits for a gate it opens (T-176). Injected sleep rather than a
  longer interval, because an interval only moves the threshold. Both wall-clock waits gone; the two
  tests run in 0.015s against 0.412s alone and 43s under load. `awaitScheduledWrite` awaits the last
  *scheduled* task rather than the pending one, because `flush` nils pending and "the write you
  cancelled must not land later" still needs a handle to await.

- [D-122] `c94edb5` One habit tile, one border (T-157). Settled not by taste but by finding
  `HabitIconTile` is a single shared view whose body is an `#if os(macOS)` choosing between the two
  tiles at 32/56pt macOS against 34/52pt iOS — same tile, same card, within 4pt, bordered on iPad and
  not on Mac, under a doc comment saying it exists so a habit reads the same on both. A fork, not two
  contexts. The three `iOSIconTile` border opt-outs are tiles inside another plate, not a size
  threshold. Mutation is the lesson: reverting either tile's body fails the **call-site** test while
  the constant-only test still passes.

- [D-123] T-148 and T-155 verified, no code needed. T-148: the strip-level `contentMargins` reset
  holds on **both** hosts — Today's Notes pane and the area/project Notes tab — and the precondition
  is real (both apply `.iOSFloatingCreateTaskButton`, which sets the bottom clearance the strip was
  inheriting). Proven by mutation: removing the reset moved both toolbars ~51pt up, into the tab
  strip, exactly as `D-104` describes. T-155: the macOS startup banner renders, verified offscreen
  with `ImageRenderer` across all three `CadenceStartupIssueKind` cases plus collapsed pills, with no
  build launched and no CGEvents. The `maxWidth: nil` subtlety **holds** — expanded measures 656pt
  for all three, collapsed 181/210/189pt, so the pill hugs its content and `contentShape` is not a
  620pt invisible band. Also observed rather than inferred: the store outranks the account
  (`.recoveryStore` + `.available` → `notSyncing`).

- [D-120] `7f4efb3` macOS's task row reads the shared metrics, and the platform counts were wrong
  (T-175). `CadenceTaskRowMetrics` had five iOS readers and zero macOS ones; macOS is now a third
  `.desktop` tier. `verticalPadding` stays split at 8 desktop / 9 compact / 12 regular — tighter than
  **both** touch tiers rather than a point on the ramp. `completionGlyphSize` is deliberately not
  read by macOS because it is not the same measurement: iOS's is a layout box around a 16pt disc
  hit-expanded to 44pt, macOS's would be an SF Symbol point size that is also its frame.
  **The correction that outlives the ticket:** the platform-difference counts quoted throughout this
  repo's briefs are inflated 2–6×. Re-measured independently: `.onHover` 56/0 not 94/0,
  `.swipeActions` 0/9 not 0/57, `.draggable` 15/7 not 157/33. The conclusion holds; the magnitudes
  do not. They came from an audit whose notes file was deleted, and `Shared/AGENTS.md` now carries
  the command that produces them rather than only the output. Re-measure before quoting.

- [D-119] Six entries reconciled as already done, found while picking the next batch of work.
  `T-163` iOS Inbox reminders — `iOSInboxRemindersSection.swift` shipped in `d330f5e`, and with it
  `T-167`, since the shipped usage string promising reminders "in Inbox and mark them complete" now
  describes a surface that exists on both platforms. `T-165` Calendar/Focus sharing one red — closed
  by `830f476`, which gave Focus `Theme.teal` rather than taking Calendar's red back. `T-136` the
  prefix-hidden forks — closed by `7e5459c` and recorded in `D-116`, but the entry was never removed.
  `T-124` 32 orphaned `CadenceMCPServer` processes — one remains, which is the expected number.
  `T-142` `Goal.dependsOnGoalIDsJSON` — the ticket asked for "the same documented treatment or a
  decision to migrate it out"; `CLAUDE.md` now carries the full warning, so it has the former.
  Worth noting the failure mode rather than just the fix: I closed `T-164` by script and left
  `T-136` in the same commit, so a list whose job is routing work was pointing four agents at
  finished tickets.

- [D-118] `3c8de23` Board cards stop repeating their column, gain tags, stop listing every subtask
  (T-173, T-174). Both were recorded as design calls; both had a defect behind them.
  The do-chip suppression is spelled as an **equality** — omit the day the surface already states —
  not as "day columns omit do dates", because the chip's red is the card's only per-card over-do cue
  and a rule keyed on column *kind* would keep hiding it silently if the bucketing ever widened.
  `dayAlreadyStatedBySurface` defaults to `nil`, so forgetting to pass it shows the chip.
  Tags: reaching them deleted a near-copy the codebase had already asked to have removed —
  `CompactTagStrip` was inside `#if os(macOS)`, so `CadenceNotesListSupport` carried a private
  `NoteRowTagStrip` that was it line for line, with a comment naming this exact move.
  Subtasks: the answer was neither "give iOS the rows" nor "give both a count". `rowSubtaskLimit = 3`
  already existed and was already *measured* (uncapped made one row ~290pt and cut iPhone Today from
  ~5 visible tasks to 2.5; the `0/3` spelling was removed for naming a count of things to do without
  naming any of them). macOS's card was listing **every** subtask including completed ones,
  unbounded — that was the real defect, and macOS is the side that changed.

- [D-117] `cdf0896` Two task-row jobs unified, two proved misfiled, three rows were lying (T-172).
  Bundle rows: `BundleTaskPopoverRow` rendered `max(estimatedMinutes, 5)m` — an invented estimate
  in raw minutes, using the exact floor `AppTask.timelineDurationMinutes` documents as rejected —
  and `iOSCalendarBundleTaskRow` spent its one secondary line on priority, so an overdue task in a
  timeline block said nothing about being overdue. `FocusBundleTaskRow` drew the completion glyph in
  the completion colour for an action that adds to the *time log*, beside two rows where that glyph
  means completion. Board cards: iOS had silently dropped the do date, so one task read "planned for
  today" on a Mac and undated on an iPad.
  **My own inventory was wrong in three places** and the corrections are the durable part:
  `TaskNoteListRow`/`iOSMarkdownTaskReferenceRow` are a navigation row and an insertion-picker row —
  same silhouette, different jobs; `FocusSidebarTaskRow`/`iOSScheduleReadyTaskRow` pick a task and
  pick a *time* respectively; and `iOSTaskListRow` is not a third primary row, it is six lines
  wrapping `iOSTaskRow`. Two spellings, not three. Nothing on the exclusion list was misfiled.

- [D-116] `7e5459c` Six parallel workstreams landed as one commit (T-136, T-164, plus the
  Reminders, image, month-grid and notes-list requests). Committed whole because that is the unit
  verified: 86 files, several carrying two agents' edits, so per-agent commits would have been
  intermediate states nobody built. macOS + iOS green, 1817 tests, 0 compiler warnings.
  T-136's re-derived inventory was **worse** than recorded — 41 exact pairs and 79 near pairs
  against ~30/~50 — and two of the forks documented their own duplication in a doc comment and
  shipped anyway. Deliberately **no** surface axis on the shared board chrome: a board column is
  fixed-width on every device, so unlike the page header it earns no third `.desktop` tier. The
  Reminders work turned up a second bug only a screenshot could find: `requestAccess` discarded the
  grant and re-read a per-process cached authorization status, so connecting appeared to fail until
  relaunch. The image squash was a height cap applied without touching width — a 600x1200 image drew
  at aspect 1.503 instead of 2.000.

- [D-115] `c970c5c` A failed calendar save left the edit on screen, and tag order was a coin flip
  (T-159, T-160). `EKEvent` is a reference type held by the timeline, and a failed save emits no
  `EKEventStoreChanged`, so without `reset()` iOS showed an event that was not in the store
  indefinitely; macOS had done this since `CalendarManager.save`. `deleteEvent` deliberately left
  alone — `store.remove` mutates nothing in memory. The reset is **not** unit-observable (the file
  is inside `#if os(iOS)`, the manager is a private-init singleton owning its `EKEventStore`, and
  forcing the throw needs real authorization) and no test pretending otherwise was written.
  `TagSupport` now has one comparator ending on `id`; both callers sorted `Array(dictionary.values)`
  under a partial order, so which eight tags the `#` picker offered could differ per launch, and a
  tie inside `tagsBySlug` decided which duplicate became canonical. Tests pin call sites, not
  `precedes`; reverting `uniqueBySlug`'s call site alone fails one, reproduced independently.

- [D-114] `8bcbb24` Four doc claims that stopped being true, including one about committing
  (T-151, T-156, T-158, T-162). The page-header rule named three macOS headers as peers; all three
  — plus `PanelHeader`, a fourth neither doc listed — are name-only wrappers over
  `DesktopPageHeader`, which is why one subtitle and three glyph ratios each had to be deleted three
  or four times. `Shared/Components` read 12 across three commits that each added one; it is 15.
  The commit rule was rewritten into its two independent halves after `--only` was followed and
  still broke HEAD, and the isolation rule now names a directory rather than a filename. The
  three-tier `.desktop` reasoning turned out to already be a good doc comment in
  `CadencePageHeaderMetrics`; it needed a pointer from a guide, not a third restatement.

- [D-113] `a1872fe` A forgotten `??` would have written to a context nobody reads (T-128, T-130).
  Two neighbours that looked identical were left alone with reasons — one wants the inherited
  environment context, one wants a new private context. Rendering proved unchanged by byte-identical
  before/after captures rather than asserted.

- [D-112] `a33335c` Alphabetical order under a cap is a filter by first letter (T-149, T-150).
  My hypothesis that macOS's wider list justified alphabetical was refuted: both macOS consumers
  truncate, so an empty `[[` could only ever offer titles beginning with "A". Independently verified;
  the verifier's finding — that the new tests pin the helpers and not the wiring — is recorded.

- [D-111] `e635442` The sync banner covered the back chevron it was telling you about (T-154).


- [D-110] `3dd09ca` An archived tag looked live on iPhone, and the width cap was not a cap (T-138).
  Ten chip spellings become one; iOS gains the width cap, remove button and archived dimming. The
  rect beat the capsule structurally, not by taste: a capsule spends both colour channels on identity
  and leaves none for state, which is why iOS never grew archived rendering. Also fixed a latent bug
  on both platforms — `frame(maxWidth:)` is flexible *upward*, so the cap was never a cap.


- [D-109] `3238e71` The calendar wrote to disk twice per column and dropped a frame doing it (T-152).
  The reported "header glitch" was a rendering artefact of a storage problem — two `UserDefaults`
  writes per column crossed, ~8ms each, on a surface where only the header band has enough contrast
  for a dropped frame to be visible. iPad 32.7→16.8ms, iPhone 24.3→17.8ms. My stated hypothesis (the
  `Int` reduction in `onScrollGeometryChange`) was wrong: it is correct and load-bearing.

- [D-108] `5aa11dc` macOS Today shouted its column titles at page volume (T-135, T-137). First
  sanctioned macOS visual change. macOS is a **third tier** (`.desktop`), not an alias for
  `.regular` — a Mac window is wider than an iPad but sets type smaller, so folding them would have
  put a 30pt title over 13pt rows.


- [D-107] `49c1797` iOS could stop syncing and say nothing, while Settings showed a green tick
  (T-153). The worse half was Settings *contradicting* the store: a green iCloud tick shown from
  account status alone while the store had fallen back to local-only. `CadenceSyncHealth` is now one
  answer and the store outranks the account.


- [D-104] `41b25f8` A wire format bypassed by the surfaces it protects, and a toolbar drawn 50pt
  too high (T-127, T-129, T-145/T-146). The verifier refuted the first justification for the new
  strict decode — `TasksPanel` is prefixed; the bare-UUID sources are the kanban card and month
  chip — and the wrong claim had been copied out of `CLAUDE.md`'s stale drag-prefix table. T-129 was
  five sites, not the six briefed.

- [D-105] `6ac3b49` Cmd+K could not find an all-day event, and a cancelled task looked open
  (T-132, T-133, T-134). The all-day filter also blocked *opening* such an event, since resolution
  goes through the same function. macOS was not clean on the glyph either — a cancelled *scheduled*
  task drew a plain open circle. The matcher move required editing `CadenceMCPServer`'s explicit
  Sources phase; that scheme was built deliberately and is clean.

- [D-106] The documentation correction pass (T-125, T-131, T-139, T-140, T-141, T-143, T-144).
  Corrections are written in the style the two exemplary guides use — naming the previous wrong
  description and why it was wrong — rather than silently replacing it, because agents have already
  acted on some of these. The `~` "list, then section" flow and its invented `NSWindow`/`@FocusState`
  rationale are gone; the private `-derivedDataPath` rule now appears in four guides instead of one;
  the MCP rule is a procedure with its mechanism attached instead of an unexplained prohibition.


Newest first. The commit message carries the reasoning; this is the index.

- [D-95] `810603d` The last macOS Swift 6 error, and the 1,996-line file it lived in (T-105 +
  refactor). Whole-module probe 1 error → 0. Two of the three visual questions that blocked this for
  a day turned out to rest on false premises, and the offscreen renders said so — the caret is
  composited above everything the view draws and cannot be occluded by any hook choice here.

- [D-94] `4fe3411` An empty kanban column could not be a drop target, whatever identity it carried
  (T-118). Wiring the identities alone would not have fixed the documented motivating example —
  `sectionGroups` discarded empty sections before the show-when-empty rule could run. `.priority`
  deliberately left unwired: no iOS surface groups by priority, so constructing it would be
  speculation.

- [D-93] `025c081` The inspector's notes well had no border, and a fill that never rendered (T-112,
  T-113). Density is now a rule owned by `iOSEditorSection` rather than a number each sheet picks.
  EventKit granted on two simulators, clearing a standing verification blind spot.

- [D-92] `24f6774` 1,314 lines and six unrelated jobs in one file (T-120). Byte-identical moves,
  independently checked by reassembly; no test file needed editing.

- [D-91] `39ca491` A group header accepted a dropped `+` only on its words (T-116). The first drag
  fixes in this app ever made with a drop observed firing. Also established that **six of the drag
  paths believed to exist on iOS do not exist at all** — no task-list reordering, no timeline drop or
  drag-to-create, no all-day chip drag, no kanban card drag, no board rails. Those are macOS
  features, so "unverified" was concealing "absent" rather than "broken".

- [D-90] `8772628` Tests stranded a UserDefaults plist on every run — 4,629 of them (T-114).
  Bounded at 11 files total, verified by a third independent run showing delta 0.

- [D-89] **T-89 and T-14 were both false, and both had been shaping decisions for days.**
  *Drag-and-drop can be driven on the iOS simulator.* `UIDragInteraction`'s lift recognizer needs
  the touch stationary ~350ms before any movement — measured, `itemsForBeginning` fires at 326–349ms
  — so a `swipe`, or any path that moves immediately, never lifts. 300ms fails too. The working
  recipe is in `AGENTS.md`, proven end-to-end on real Cadence: a Calendar Board card dragged between
  day columns, with the SwiftData change surviving a relaunch.
  *The "tab bar swallows taps" folklore is also wrong.* A touch beginning within 4pt of an edge is
  synthesised as the OS home gesture; an incomplete one leaves the window ~35pt short, so
  bottom-anchored controls move up and taps aimed from an old screenshot miss. Nothing is swallowed.
  Almost certainly caused by aiming with screenshot **pixels** where the API takes **points**.
  *macOS UI can be screenshot- and event-verified.* All four preflights return true; I confirmed
  this independently. T-14's symptom is real but misdiagnosed — `count of windows` on an app with no
  window returns 0 and indexing errors `-1719`, which reads like a permission denial.
  **One real constraint survives:** posting CGEvents drives the user's *physical* cursor, so a
  scripted macOS drag fights them for it. Screenshots and reads are safe any time.

- [D-88] **Every "verified by inference" caveat in this repo's history predates the recipe above.**
  Recorded separately because it is the expensive part: two limitations nobody had retested were
  used to justify not verifying whole features, and one of them ([T-14]) also blocked [T-105].

- [D-87] `2ff8d39` The calendar's day header reserved less space than its contents need (T-73
  calendar slice). 33 branches → 5 reads; one of them was arithmetic that was simply wrong.

- [D-86] `813fe0d` The iOS layout manager's overrides now agree with their superclass (T-109).

- [D-85] **T-13 closed as won't-fix, and its headline figure was wrong.** `xcodebuild` creates one
  directory per launched test process inside the app's sandbox container, hands it to that process
  as `LLVM_PROFILE_FILE`, then deletes the profile file and not the directory. Caught in the act:
  the PID in the directory name resolved to a live `xcodebuild test` 5 times out of 5, and the test
  host's captured environment names that exact directory. The container is the only place a
  sandboxed test host may write, which is why this happens here and not on the simulators.
  **The "97 MB" was wrong** — empty directories occupy no data blocks on APFS. All 2,109 of them
  cost ~0 bytes; the 6 MB measured is 5 stray `.profraw` files. The real cost is directory entries.
  Ruled out with evidence: SwiftData (the UI-test runner container shows the same pattern and links
  no Cadence code), CloudKit (tests run `cloudKitDatabase: .none` and still leak; the simulators do
  run CloudKit and leak nothing), the sandbox machinery (907 containers on the machine, only the
  three dev-built Cadence ones do this), and app code. Nothing in the repo can prevent it short of
  dropping the app test host.

- [D-84] `2b0b1f7` Four sheets drew one markdown well four different ways (T-111). One height, 340,
  from the two surfaces that never ramped. Unifying the box surfaced a real rendering bug: a
  `.stroke` on a clipped path had half its border cut away, at 0.68 alpha, in two sheets.

- [D-83] `2a15f27` Section headers respond to the first click again (T-107). Decided by the user:
  two clicks should be two toggles. The gesture cost ~352ms on *every* click to smooth over an
  accidental double-click that nobody performs on purpose.

- [D-82] `11d8891` A note in one list drew another list's task as if it were deleted (T-95 part 3).
  User chose the wider reading: any task is embeddable from anywhere. One array fed three things, so
  it also fixed reference resolution and click-to-open.

- [D-81] `0b2f976` The MCP scheme had two warnings sitting under a baseline that never looked at it
  (T-110). The baseline now covers all three schemes, verified rather than assumed.

- [D-80] `92ad0af` The notification reconcile carried a ModelContext across actors (T-105 item 2).
  With it fixed, the editor override is the only remaining macOS Swift 6 blocker.

- [D-79] `b346fe3` Two more types the nonisolated pass missed, and the workaround one forced (T-106).

- [D-78] `fd669d8` Wiring that read as live and was not — iOS (T-104).

- [D-77] `a679f94` The editor's Swift 6 blocker is one error, and the fix is not landable yet
  (T-105). The refactor was **built and proven to compile**; it is not landed because three residual
  questions are visual only and macOS UI cannot be checked from the agent shell. See [T-108].

- [D-76] `fcf0a6e` 173 lines that read as wiring and were not — macOS (T-104).

- [D-75] `1dc7d33` Cmd+N did nothing over a Calendar Board column, and a double-click mystery
  (T-102). The third item was suspected dead and turned out to be neither hypothesis — measured, not
  reasoned about.

- [D-74] `7c6e259` A short timeline block was 6pt of tap target and 16pt of resize strip (T-101).
  Also fixed an unconditional EventKit write on a plain click, which raised an unprompted "Change
  recurring event?" dialog.

- [D-73] `234a794` Three of the four Swift 6 errors go; the fourth is a refactor (T-96).

- [D-72] `7091a6a` All Tasks and Inbox were one page rendered through two containers (T-98, T-99).

- [D-71] `c9d2d78`+`7091a6a` **A commit broke HEAD for iOS.** `git add <paths>` stages *on top of*
  whatever is already in the index, so another agent's staged deletion of two view files rode into
  an unrelated commit while their callers were still uncommitted. iOS did not build between the two
  commits. Third occurrence of this sweep; now a standing rule in `AGENTS.md` (`git commit --only`).
  Worth recording that verification could not have caught it: isolating a change with
  `git archive HEAD` reproduces HEAD's tree, not its index.

- [D-70] `d8965a8` Cmd+Return deleted one task and completed another (T-103, from the T-97 audit).

- [D-69] The audit for controls that look wired and do nothing (T-97). No code; it produced T-101,
  T-102, T-103 and T-104, and a *cleared* list — deep links, notification reconcile paths, all 36
  `@AppStorage` keys, every documented keyboard chord — so the next agent does not re-chase them.

- [D-68] `f35ace2` A sheet's width is its own, not the screen's (T-100).

- [D-67] `c9d2d78` Note rows named tasks by whatever they were called last time (T-95 parts 1, 2).

- [D-66] `9b08364` The phone was not told how much of its day was already timed (T-73 remainder).

- [D-65] `646ff9e` The task is the record; the embedded title is a cache (T-92).

- [D-64] `dfae0d3` `isCustomDoDate` outlived its only caller (T-93).

- [D-63] `62dc384` The MCP server target compiled a file it never used (T-94).

- [D-62] `c5a4ea5` Six page headers had drifted into six title sizes (T-73 group B remainder).

- [D-61] `f94361a` 215 value types were main-actor isolated, including ones widgets use (T-87).

- [D-60] `b554824` Month's date picker opened on a layout constant (T-90, T-91; T-11 closed as
  already fixed).

- [D-59] `49a273e` macOS rewrites an embed's reference when its inspector closes (T-88).

- [D-58] `3097749` The creation sheet is a grid of value tiles, measured to fit (T-85).

- [D-57] `69bf02d` A group header takes a dropped + only when it can say where it lands (T-39).

- [D-56] `fcb2168` Renaming a task never updated the note that embeds it (T-84).

- [D-55] `7d39af2` 1195 test warnings were hiding five real ones (T-82).

- [D-54] `7f21fab` One board card, one timeline block, and two more ungated scroll reports (T-73
  group B, T-80).
- [D-53] `661a602` A task row is one row, and the Inbox stops naming itself (T-78, T-77).
- [D-52] `2a30319` Three near-copies collapse into the components they were copies of (T-73 group B).
- [D-51] `457ca47` The estimate picker was still three, and CLAUDE.md still said two — two false
  claims in `3ecfeaf` caught by a read-only verifier.

- [D-50] `0e8db6c` The creation sheet puts its fields in the page, not on the floor (T-49). Height
  risk only partly closed — the Tags row sits ~53pt below the fold with a keyboard up; awaiting the
  user's call on whether to retreat further.
- [D-49] `11883bb` One date-jump title, and the scroll gate stops being copied (T-59, T-70).
- [D-48] `3ecfeaf` One estimate picker, and macOS loses its status list too (T-75, T-76).

- [D-47] `29735a6` A task-embed card was tappable only along its leading 8 points (T-57, T-43).
- [D-46] `b8b329e` iPhone and iPad stop disagreeing about seven things (T-73 visible half).
- [D-45] `0f7b756` The task row stops pointing at itself and starts being editable (T-68, T-74).
- [D-44] `a240a74` Notes is one view for all three hosts (T-73 largest, T-56, T-58, T-54).

- [D-43] `ecfc9a3` Month scrolls, every surface names one date, and nothing steps by button
  (T-61…T-65, T-69, T-71, T-72).

- [D-42] `8f2fd9f` Settings and Focus share one row of glyphs at the sidebar's foot (T-66).
- [D-41] `ae3ac48` Checklist circles sat on the baseline, which reads as floating (T-67).

- [D-40] `cf785a8` The calendar scrolls instead of stepping, and its headers stay put (T-50).

- [D-39] `7d93f7f` Drop visionOS from the build settings (T-53).

- [D-38] `4f00e55` Three line-numbering conventions were feeding each other's indexes (T-48, T-41).

- [D-37] `64218d1` The note editor loses two bars and stops eating double taps (T-47, T-51, T-42).

- [D-36] `88c05d1` Today's two panes asked for one point more than the pane had (T-52, T-08).

- [D-35] `a911d5a` The drop preview stops highlighting a task nothing happens to (T-46).

- [D-34] `68d78ec` Month's agenda opened past the end of its own content; Board's counts strip and
  Month Day's missing add control (T-34, T-35, T-36).
- [D-33] `aca2787` A task embed named itself "Untitled Task" and then argued with the note (T-26);
  plus the macOS twin of the frontmatter/divider bug.

- [D-32] `a43b8fd` A checkbox you typed was never a checkbox, and tagged notes grew two
  rules (T-37, T-38).

- [D-31] `47328af` Drag the + onto a task and the new one lands where that one lives (T-05).

- [D-30] `4c63084` The MCP surface called eight kept weeks "8 day streak" (T-12).

- [D-29] `a4bdaa5` Nothing that renders a block rendered on iOS — tables, code blocks and
  dividers were all invisible (T-33).

- [D-28] `2929867` Daily and Weekly notes could only ever be today's — the header title became the
  date and the control that changes it (T-31); tabs renamed Daily/Weekly; template menu moved into
  the editor's format row.
- [D-27] `6609bf7` A past-due line measured its colour and its words against different days —
  `relativeDate` ignored the injected `todayKey` and read the system clock.
- [D-26] `42de745` Board has no inspector, and no surface repeats the day it is showing (T-28).
- [D-25] `bea12c7` iPad Today: Focus/Mac picker deleted (T-06), composer stays where you tapped
  (T-24), free slots derived rather than hardcoded (T-25), sort row merged into the header (T-30).
- [D-24] `8d1bbab` The iPad sidebar shows its lists, and folds out of the way (T-07, T-27).
- [D-23] `40e2381` The Notes header's second row held one button; it holds nothing now (T-29).

- [D-22] `545f429` Week could not show a week — seven columns at every real pane width.
- [D-21] `8a316c4` Month stopped changing mechanism on rotation; Lists eyebrow says its shape.
- [D-20] `71fbd1f` macOS sidebar: one nav block, colour bar instead of icons, Inbox restored.
- [D-19] `f2a1227` Today panel said "late" four times; now once.
- [D-18] `c9fb369` Notes has one live editable mode; code blocks stay editable.
- [D-17] `5a3cd63` Timeline shows 24 hours; three range spellings collapsed to one.
- [D-16] `cce1a4d` Sidebar pushed off-screen by a pane three levels down; capture bars deleted.
- [D-15] `8b5b0d8` iPad pane layouts: Calendar mode picker rendered as "…" at 632pt; day inspector
  took 54% of an 11" pane leaving 2 of 7 days; Goals/Habits/Focus split every pane exactly in half.
- [D-14] `e792fe8` Workspace drawer → lists picker; Planning deleted from iOS list detail; iOS and
  macOS list-detail page enums consolidated into `Shared/`.
- [D-13] `779bf68` Two-pane layout had no minimum width — an 11" iPad split 632pt into 312/320 and
  clipped its own capture field. Floor now derived from the panes.
- [D-12] `17f9f7a` iPad Today caught up with the phone; note templates stopped being silently
  discarded when the editor held focus.
- [D-11] `6277539` iOS task comparator was a partial order — list sequence depended on whatever row
  order SwiftData returned.
- [D-10] `717d330` Segmented picker hid two of its four options; widget printed "8d" for weeks.
- [D-09] `68c860e` Month became a grid over a live agenda; Week stopped opening at 6 AM.
- [D-08] `38af360` Thirteen bugs from a read-only audit, each confirmed before fixing.
- [D-07] `94f4540` Tab bar shell replaced the Home grid; iOS gained a real task-creation sheet.
- [D-06] `775833d` Settings became a category list with value rows; notes header stopped repeating
  its own tab name.
- [D-05] `f3b68ed` Six Focus play buttons that only changed the selection; goal detail's inert rows.
- [D-04] `ecaf80f` Calendar Board opened seven months in the past and persisted the bad anchor.
- [D-03] `5a14dda` Task inspector stopped showing five chips for fields it already let you edit.
- [D-02] `ec1912f` Task row: colour reserved for the exceptional; swipe actions that worked outside
  a `List`; a metadata strip that could not scroll.
- [D-01] `74f59ee` Seven keyboard toolbars, five of which never rendered — and the `/` slash menu
  they were hiding.

## Cancelled

- [X-03] **[T-83] Remove the nav arrows from Month and Board** — filed and decided on a false
  premise, then found already delivered. `cf785a8` scoped the removal to the timed grids; `ecfc9a3`
  superseded it two hours later and removed the cluster from **all four** surfaces, saying so in its
  own message. My summary to the user reported the earlier scoping as the shipped state, so the user
  was asked to decide something already done. Nothing was changed. The lesson is cheap and worth
  keeping: **report the shipped state from the code, not from the decision you remember briefing.**

- [X-08] **[T-208] CLOSED, FALSE PREMISE — Today's Completed section cannot show three rows above a
  count of two, and neither can the surfaces it was re-scoped onto.** The ticket said the section
  lists cancelled tasks while the header's "N done" does not count them. Re-derived from the code at
  `902b386`, independently of the note `CLAUDE.md` already carried.

  **The two numbers a user reads at that section are both `.count` over the array the rows are
  drawn from, so rows and count are the same number by construction.**
  - macOS: `TasksPanel.completedSection(derived:)` hands `TasksPanelCompletedSectionView` its
    `tasks: derived.doneTasks`, and that view heads itself with
    `TasksPanelIntentSectionHeader(count: tasks.count)` — the same array it `ForEach`es. The
    column-header `· N done` is `CadenceTodaySummary.completedCount`, built by
    `CadenceTodayPresentationSupport.summary(completedTasks: derived.doneTasks)` as
    `completedTasks.count` — the same array again.
  - iOS: `iOSTodayTaskSections.groupStack` passes
    `CadenceTaskSurfaceOptions.completedRows(from: completedTasks)` to `iOSTaskGroupSection`, whose
    capsule is `count: tasks.count` over that same (row-capped) array.
  - `derived.doneTasks` in `.todayOverview` is `CadenceTaskQuerySupport.completedTodayTasks`, whose
    predicate is `isFinishedTask` — done **or** cancelled — so a cancelled task is in the rows *and*
    in both counts. Three rows show a count of three.

  **`completedTaskCount` — the `isDone`-only rule the ticket is really about — is not read by that
  section at all.** `CadenceTaskQuerySupport.completedTaskCount` has three call sites: the iOS
  Settings **Completed** metric tile (`iOSSettingsView.completedTaskCount` →
  `iOSLocalDataSettingsSection`) and the past-due kanban-column summary built in
  `CadenceTodayOverdueSummarySupport.summaries(...)`. (`TasksListView` declares a private
  `completedTaskCount` of its own for All Tasks / Inbox; it counts `isDone || isCancelled`, matching
  its own `completedTasks` array exactly. Three MCP DTO fields share the name over an inline
  `filter(\.isDone).count`.)

  **Neither of those is defective either, which is why this closes rather than being re-scoped.**
  The overdue column card (`CadenceTodayOverdueSectionCard`) draws "N open" from `openTaskCount`
  and "N done" from `completedTaskCount`, and a cancelled task is in neither — but the card states
  no total, and both labels are literally true of the numbers under them. The Settings tiles are
  the same shape: independent "Active tasks" and "Completed" tiles, no sum, both accurate. An
  omission with no claim attached is not the visible inconsistency the ticket was filed on.

  One correction to the note `CLAUDE.md` carried, which said the two overdue summary cards are
  macOS's: `CadenceTodayOverdueSummaryCards.swift` is in `Shared/Components/` and
  `CadenceTodayOverdueSectionCard` is rendered by `TasksPanel.overdueSectionsSection` **and** by
  `iOSTodayTaskSections`. If anyone ever does decide cancelled work should be visible on that card,
  it is one change for both platforms, not a macOS one.

- [X-01] **Home screen redesign** — three rounds of mocks (quiet grid, today-first, informative
  cards) were all rejected before the real problem surfaced: there was no tab bar, so Home was
  standing in for navigation the app did not have. Superseded by [D-07].
- [X-02] **Keyboard-accessory verification above a raised software keyboard** — the accessory is
  confirmed to render and work, but `ConnectHardwareKeyboard` is a Simulator.app preference and the
  simulators run headless, so the raised-keyboard geometry cannot be checked without opening
  Simulator.app. Not worth the intrusion.

- [X-04] **The kanban header's `overdueCount > 0` guard is not a coverage gap** — a mutation batch
  reported it as "genuinely unpinned": deleting the `> 0` from `ListDetailSupportViews.swift:176`
  passes the whole suite, and no test names the view's own display rule. Both halves are true and
  the conclusion does not follow. `TasksPanelSupport.overdueCount(in:)` returns
  `count > 0 ? count : nil`, so **zero never reaches the view** — every call site into the header
  either goes through that producer or passes `nil` outright. The mutation is behaviourally inert,
  which is why it survived. The invariant it leans on *is* tested, at
  `TaskOverdueSupportTests.swift:120` (`overdueCount(in: [doneLate]) == nil`). Leave the guard.
  Recorded so the next agent neither "fixes" it nor re-files it — and as a reminder that a
  surviving mutation means *the tests cannot see this change*, which is a hole only when the
  change is one a user could ever observe.

- [X-05] **[T-267] CLOSED, NOT A BUG — the iOS month date picker never killed the app. `tccd` did.**
  The ticket read as the highest-priority open crash and the premise was false, so the correction
  matters more than the closure. Re-verified against `b1239e0` on the shared `iPhone 17 Pro`
  (`7B642065-…`, iOS 26.5), clean Debug build, **seven** day-cell taps across all three entry
  points — `iOSTaskComposerDateTile` (Do and Due), `iOSTaskRowDateChip` on a live Today row, and
  the task inspector's `CadenceDatePicker` — covering today's cell, a future cell, a **past** cell,
  and a cell in a **different month** (the one that really moves `viewMonth` and re-derives all 49
  months). Every tap set the date and left the app running. `MonthCalendarPanel`'s day `Button` is
  **not** the defect; do not "fix" the `selection` / `syncViewMonthToSelection()` / `isOpen = false`
  sequence on the strength of this ticket, and do not touch it lightly at all — it is
  `Shared/Components/`, macOS reads it from six call sites including the `Cmd+Shift+T`/`Cmd+Shift+D`
  hovered-date overlay.
  **What actually happened.** Every disappearance-to-Home in this simulator's log — ten of them
  across 2026-08-22, including the four consecutive ones at 12:50:44 / 12:53:17 / 12:55:02 /
  12:55:37 that are this ticket's "reproduced four times" — is the same line:
  `tccd: Terminating com.haoranwei.Cadence[<pid>] because access to the kTCCServiceReminders
  service changed`, followed by `launchd_sim: … exited with exit reason (namespace: 11 code: 0x0)
  - OS_REASON_TCC`. Each one is preceded by milliseconds with
  `tccd REQUEST: sender_pid=81487, function=TCCAccessSetInternal` (or `TCCAccessResetInternal`) —
  pid 81487 is **CoreSimulatorBridge**, i.e. a host-side `xcrun simctl privacy <udid>
  grant|revoke|reset reminders com.haoranwei.Cadence`. Changing a TCC grant for a *running* app is
  specified to kill it; nothing in Cadence can cause it. The msgIDs form one ascending series
  (`81487.2 … .16`) across the whole day, which is what an unrelated agent's repeated
  `simctl privacy` calls on a **shared** device look like from inside the app.
  **Demonstrated, not inferred.** With the picker open and no tap on the grid,
  `xcrun simctl privacy … grant reminders com.haoranwei.Cadence` from the host reproduced the exact
  reported symptom — app gone, Home screen, sheet state lost — and logged `msgID=81487.16` with the
  identical two lines. `auth_value` in the device's `TCC.db` was `2` before and `2` after, so the
  demonstration changed no state on the shared device.
  **The two "supporting" observations were both true and both misleading.** Nothing in
  `~/Library/Logs/DiagnosticReports` and no exception, because `OS_REASON_TCC` is not a crash and
  writes no report — the same reason the ticket's `SIGKILL`-shaped reading felt right. And the
  quick pills worked "every time" because they were not tapped during the seconds a `simctl
  privacy` call happened to land.
  **The lesson is the shared simulator, not the picker.** The root `AGENTS.md` simulator bullet now
  carries it: on a device several agents share, an app vanishing to the Home screen is an *external
  termination* until the log says otherwise, and
  `log show --predicate 'process == "tccd" OR process == "launchd_sim"'` settles it in one command.

- [X-06] **[T-179] CLOSED, EXTERNAL CONSTRAINT — `control action=detach` ignores the `udid` argument and
  closes every simulator panel.** Re-verified 2026-08-24: this is a bug in the iOS Simulator control
  tool itself (the `mcp__Claude_Code_iOS_Simulator__control` action), not in anything under this
  repo, so there is no code here that can fix it. An agent detaching its own device once closed
  three other agents' panels (iPhone 17e, iPhone 17 Pro Max, iPad Air 11-inch); no device or app
  state was altered and every closed panel could just re-`attach`, so the blast radius is annoyance,
  not data loss. The one mitigation available from this side of the boundary is documentation, and
  it is now in place: `AGENTS.md`'s simulator bullet states `detach` as global regardless of `udid`
  and tells agents to only call it when they have reason to believe no one else is attached. Closing
  rather than leaving open because there is nothing left to *build* — reopen only if the tool itself
  changes or a repo-side workaround (e.g. an attach-tracking convention) is actually designed.


- [X-07] **[T-257]** ~~**`HEAD` does not build from a clean clone.**~~ **Withdrawn — the premise is false, and
  following the instruction breaks the build.** `TaskContainerLifecycleService` *is* declared at
  `HEAD`, in the committed `Cadence/macOS/Services/TaskWorkflowService.swift:58`; the untracked
  `Cadence/Services/CadenceTaskContainerLifecycleService.swift` is another agent's uncommitted
  **move** of that type — which is why `Cadence/macOS/Services/TaskWorkflowService.swift` shows as
  modified in the same `git status` the ticket was written from. So the committed call sites in
  `EditListSheet.swift` and `CadenceCancelledTaskReachabilityTests.swift` resolve fine, and a clean
  clone builds. What does *not* build is `HEAD` plus that one untracked file, which is exactly the
  isolation [[T-21]] was told to construct: measured on 2026-08-22, three errors — `invalid
  redeclaration of 'TaskContainerLifecycleService'` and two `has no member 'remainingActiveTasks'`
  against `HEAD`'s smaller version of the type. Dropping the file instead gave macOS TEST SUCCEEDED
  and an iOS BUILD SUCCEEDED. Do **not** `git add` it — that would commit half of somebody else's
  in-flight refactor. The general rule stands and is the one worth keeping: the project uses Xcode
  **file-system-synchronized groups** (6 `PBXFileSystemSynchronizedRootGroup` entries in
  `project.pbxproj`), so any `.swift` file under `Cadence/` is compiled by directory membership with
  no `project.pbxproj` change to show for it. An untracked file therefore silently joins every
  build, and restoring `HEAD` means **deleting** it, not keeping it.
