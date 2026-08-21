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


## Open — decided, not started

- [T-222] **`iOSListNotesPanel` and `CadenceListNoteSupport.firstOrCreateNote` are now dead.**
  `676ff3b` gave iOS a real notes column, so the one-note-per-list panel has zero construction sites
  and deleting it orphans its helper. Both sit outside the files that agent owned. Confirm with a
  declaration grep before removing — `AGENTS.md` warns that no-references is not by itself evidence
  something is safe to delete, though neither of these is a stored property so the usual hazard does
  not apply.

- [T-223] **Editing a list note's `# H1` on iOS does not sync back to `note.title`.** macOS does sync,
  which is why every iOS list-note row read "Untitled" while seeding `676ff3b`'s screenshots.
  Pre-existing and unrelated to folders. `CLAUDE.md` documents the intended behaviour — new notes
  start with the title as the first H1, and editing that H1 syncs back — so iOS is missing half of a
  documented feature.

- [T-224] **Two hosts still need the one-line `editingNote:` pass for the reference panel.**
  `0332255` shipped the panel but `iOSNotesView.swift` (2 sites) and the list-detail notes panel were
  locked to other agents mid-run. The test deliberately does **not** assert them at zero, so adding
  them will not read as a regression. Also: `iOSSearchView.swift:589` and
  `iOSMarkdownNoteReferenceRow` each carry their own note-kind switch — third and fourth spellings of
  one mapping, now that the shared label exists.

- [T-225] **An agent overwrote another agent's simulator app-group data.** During `0332255` a build was
  installed on an iPad another agent had booted between the device listing and the boot attempt,
  replacing its `Application Support/Cadence`. No repo damage, but it invalidated that agent's seeded
  state mid-run. Same family as [[T-179]] and [[T-204]]: the simulator fleet is shared and nothing in
  the brief tells an agent to check whether a device is already in use before installing to it.

- [T-221] **Edit tables and code blocks in place, instead of falling back to raw markdown.**
  Requested 2026-08-21. Today the editor renders a table, a fenced code block, a divider, an image and
  a task embed as **canvases**, and `MarkdownStyleRanges.isRevealed` swaps a block back to its raw
  markdown source when the caret lands inside it. So typing in a table means typing pipes. The user
  wants the rendered form to *stay* rendered and be edited directly — cell by cell for a table, and
  the equivalent for the other elements where it makes sense.
  **The user explicitly asked to be consulted while this is worked on**, so ask before choosing the
  interaction: at minimum, which elements are in scope (table certainly; fenced code with a language
  pill probably; image and task embed unclear), what Tab and Return do inside a table, how a row or
  column is added or removed, and whether the raw source should still be reachable on purpose.

  **Why this is bigger than it sounds, and the thing to establish first.** Both editors are a single
  `NSTextView` / `UITextView` over one attributed string, and a canvas is **drawn** — there is no
  view hosting a cell, confirmed by the absence of any `NSTextAttachment` / `UIView` / `NSView` in
  `iOSMarkdownStylingBlockSupport.swift`. Nothing is editable because nothing is a control. So the
  first question is not "how should cells behave" but **which of these three shapes the app takes**:
  1. Keep one text view and make the *source* edit feel structured — caret navigation that skips
     delimiters, Tab jumping cell to cell, alignment maintained as you type. Cheapest, and it is an
     extension of work already done (hidden markers already are skipped by caret traversal).
  2. Host real views for these blocks — text attachments or subviews with their own editing — inside
     the text view. Genuinely WYSIWYG, and the hard one: selection, undo, copy/paste, and the
     `MarkdownStyleSignature` render gate all have to cross the boundary.
  3. A separate structured editor for a block, opened from the canvas. Least ambitious, most
     predictable, and it sidesteps the text-view boundary entirely.

  Constraints that will shape the answer: markdown *decisions* belong in
  `Cadence/Services/Markdown*Support.swift` and the parsing already exists
  (`MarkdownTableParser.tableBlock` is shared by the editor and the preview since `7c964a6`);
  `MarkdownStyleSignature` is the gate in front of the whole render pass, so a block that becomes
  editable must still invalidate correctly or it silently stops updating; and undo must keep working —
  `Cmd+Z` currently passes through to `NSTextView`'s own stack when a text view is first responder,
  which a hosted sub-editor would break. `MarkdownRenderedBlockDeletionSupport` already exists for
  deleting a rendered block, so read it: it is evidence of how much special-casing a canvas already
  needs.

- [T-217] **The bundle detail sheet has the same row-owned-sheet defect T-201 just fixed.**
  `iOSCalendarBoardBundleCard` (`iOSBoardCards.swift:~390`) and `iOSTimelineBundleBlock`
  (`iOSCalendarTimelineViews.swift:~925`) each present `iOSCalendarBundleDetailSheet` from a card
  inside a filtered `ForEach`, so editing a block's date or time moves the card between day columns
  and tears the panel down mid-edit. Same defect, **different sheet**, so it needs its own host rather
  than the task one. `D-141` pinned both at an exact count so it cannot drift unnoticed.
  `iOSTaskInspectorHost` is the pattern to copy, including its `isDeleted || modelContext == nil`
  finding.


- [T-220] **macOS's About carries only the build card; iOS's also carries Privacy Policy and Support.**
  Flagged by `D-140` rather than decided: macOS already offers both links under Settings → Data Safety,
  so matching the two screens means *moving* them rather than duplicating. Decide which screen owns
  those links on each platform.

- [T-212] **`finishRemainingActiveTasks` hand-rolls the cancel transition, and gets two things wrong.**
  `Cadence/macOS/Services/TaskWorkflowService.swift:~105-118`. Found by T-202 and left because another
  agent held the file. It sets `completedAt = nil` for `.cancelled`, so bulk "cancel remaining tasks
  in this section" still produces untimestamped cancellations that [[T-202]] just fixed everywhere
  else — **and** it bypasses `markCancelled` entirely, so it never spawns a recurring successor. Two
  bugs in the same three lines. Route it through the shared workflow rather than patching the
  timestamp.

- [T-213] **`normalizeCompletionState`'s `.done` branch bumps a completion timestamp.** It calls
  `markDone`, which sets `completedAt = now` unconditionally, and the iOS task sheet's save is its
  only caller — so opening and closing the sheet on a task finished last week rewrites its timestamp
  to today and pulls it into Today's Completed. Pre-existing and distinct from [[T-202]]; found while
  fixing the `.cancelled` branch beside it. A normalizer should not invent a timestamp the status
  merely permits.

- [T-214] **iOS list *completion* is still macOS-only, and the obvious shared substitute is wrong.**
  T-187 shipped deletion and deliberately not completion. `TaskContainerLifecycleService` lives in
  `TaskWorkflowService.swift` behind `#if os(macOS)` with nothing platform-specific in it — the
  fourth-instance shape again — so un-guarding it makes iOS completion a call site and nothing more.
  Do **not** reach for `applyStatusCompletion` instead: it routes through `markDone`, which **spawns
  the next recurrence occurrence**, which is correct for one task and wrong for bulk container
  completion that must not mint new work.

- [T-215] **macOS's archive cancels a list's remaining active tasks; iOS's archive only sets status.**
  An existing silent divergence found by T-187, in the same blocked file as [[T-212]] and [[T-214]].
  One line, but decide it deliberately: archiving *should* probably settle the work, and if so iOS is
  the wrong one — which also makes it [[T-212]]'s bug, since that is the path macOS uses.

- [T-216] **Docs need a pass for the `ListDeleteHelpers` move.** `Cadence/Services/` count 48 → 49;
  `AGENTS.md`'s `macOS/Services/` bullet now has **three** tombstones, not two; `CLAUDE.md`'s
  project-structure block, its "What's Built (iOS)" Settings line, and the `Shared/` inventory (two
  new files) are all stale. Deliberately not done by the agent that moved the file, because the docs
  agent held those files at the time.


- [T-208] **Today's Completed section lists cancelled tasks but the header's "N done" does not count
  them.** Introduced deliberately by `9d11135` and documented at `CadenceTaskQuerySharedSupport.swift`
  — a cancellation is not an accomplishment — but it is a *visible* inconsistency: the section can
  show three rows above a count of two. Decide whether the count should say something else
  ("3 settled"), the section should label its cancelled rows, or the mismatch is fine.

- [T-209] **Parallel `xcodebuild` runs in *separate* private DerivedData paths still contend, and it
  looks exactly like a real failure.** The verifier's first test run exited **65** with hundreds of
  `external macro implementation type 'SwiftDataMacros.PersistentModelMacro' could not be found …
  swift-plugin-server could not be loaded: Resource temporarily unavailable`. Serial re-run: exit 0.
  Two other agents hit the same thing today (one saw 650 `error:` lines, clean on retry).
  `AGENTS.md` warns about *shared* DerivedData; it says nothing about concurrent invocations in
  private paths. Add it, because the failure mode is a plausible-looking compile error that a careless
  agent would report as a regression.


- [T-211] **On iOS, H5 (16pt) and H6 (15pt) render *below* the editor's body text.** Found by
  `d513e72` and recorded rather than fixed. The iOS body is
  `UIFont.preferredFont(forTextStyle: .body)` — 17pt by default and larger at accessibility sizes —
  so no fixed point size can stay above it. Fixing it means making the iOS ramp relative to
  `preferredFont(.body).pointSize` rather than absolute, which is a different change from unifying
  the ramps.

- [T-204] **Agents leak simulators and MCP servers, and it is measurably starving the machine.**
  Found on 2026-08-21 at the user's prompting. **Ten** simulators were booted at once, each running
  Cadence, two of them for over a day and one for nine hours — 54 `SimMetalHost`/`MTLCompilerService`
  processes between them. Alongside that, **11** `CadenceMCPServer` processes, the oldest 18 hours,
  one holding 4 open handles on the live SwiftData store. Shutting down eight simulators and three
  stale servers took the load average from **60.6 to 27.3**.
  This is not cosmetic: two agents died to a 600s watchdog stall on 2026-08-20, and the diagnosis at
  the time was "five concurrent builds saturate the machine". Leaked simulators were the other half
  of that, and nobody was counting them.
  Two things to fix. **(a)** Agents boot a device, use it, then boot another without shutting the
  first down — the brief already forbids the host Simulator app and `control action=detach` (T-179),
  but says nothing about *shutting down what you booted*. Add that to `AGENTS.md`'s verification
  rules, next to the scratchpad-cleanup rule it parallels exactly. **(b)** The `CadenceMCPServer`
  instances are spawned by `ChatGPT.app`'s codex app-server, not by this repo's agents, so they are
  outside our control — but [[T-124]] recorded 32 of them once already, so the count is worth checking
  whenever the machine feels slow. A `pgrep -c CadenceMCPServer` in the pre-verification checklist
  would cost nothing.


- [T-190] **Task bundles can be viewed, edited and deleted on iOS but never created.** `TaskBundle(`
  is constructed only at `macOS/Services/SchedulingService.swift:32` and `:125`, inside
  `#if os(macOS)`, in a file with no AppKit. iOS reads bundles across nine files and has a detail
  sheet with a `@Bindable bundle` plus `deleteBundle`. Also no bundle focus on iOS. Needs a create
  affordance the iOS calendar does not currently have, so this is more than un-guarding.


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

- [T-195] **Today's rollover banner and sections-due-today are macOS-only.** The four Today group
  kinds *are* shared (`CadenceTodayTaskGroupKind`, read by both platforms since `d330f5e`). What is
  not: `TasksPanelRolloverNoticeSectionView`, the `todayRolloverNoticeDismissedDate` preference, and
  `TodayOverdueSectionSummary`. The roll action's slot-clearing semantics — move `scheduledDate`,
  reset `scheduledStartMin`, drop the linked event — would need lifting into `Shared/` first.


- [T-198] **Six stale counts across the guides, and one refuted shared-component claim.** From the
  T-32 audit, re-verify each before editing: `Cadence/iOS/` said 79 in three places (actual 82 at the
  time); `Cadence/Services/` said 43 (actual 45 top-level, 54 with `AI/` and `MCPReadOnly/`);
  `Markdown*Support` said 22 (actual 25); `CadenceTests/` said "~140" (actual 158); `macOS/Views/`
  said ~168 in one guide and ~165 in another. Separately, both root guides list "`KanbanCard`,
  `BoardColumnHeader` and `KanbanColumnScroll` are now shared" — **there is no `BoardColumnHeader`**
  (the type is `CadenceBoardColumnHeader`), and `KanbanCard` and `KanbanColumnScroll` are macOS-only.
  The claim is true across the three *macOS* boards and false as a cross-platform statement;
  `iOS/iOSListSupportViews.swift:424` compounds it by naming all three as the vocabulary the iOS
  board is written in, when two cannot be referenced from that file.

- [T-199] **Four smaller refuted doc claims.** `CLAUDE.md` lists `HabitInsights` as a non-`@Model`
  helper *type* in `Models/`; there is no such type — `Models/HabitInsights.swift` is an
  `extension Habit`. `CLAUDE.md` understates iOS Settings (it has **13** categories, not the seven
  listed) and implies macOS ⊃ iOS, when the relation is two-way: iOS lacks `sidebar` and `account`,
  **macOS lacks `sync`, `coverage` and `about`**. `CLAUDE.md`'s `Shared/` map implies the T-120
  calendar files serve both platforms, but `CadenceCalendarDayBadge`,
  `CadenceCalendarDateTitleFormat`/`Support`, `CadenceCalendarZoom`, `CadenceCalendarTimelineWindow`
  and `CadenceLazyScrollAnchor` have **zero** readers under `Cadence/macOS`. And the recurrence-scope
  "APPLY TO" row replacing a `confirmationDialog` is macOS-only — iOS still raises the dialog at
  `iOSTaskDetailSheet.swift:113`.


- [T-15] **Several dark palettes — decided, and the colours are not the hard part.** User's call, and
  it narrows what was an open-ended ask: **stay dark-only**, offer alternate near-black palettes
  (cooler/warmer neutrals, or a different accent set). Explicitly **not** light mode — that was the
  option costed as largest and it was declined, so nothing needs a light value and no call site has to
  change its reasoning.
  What this reverses, and does not: the seven-theme `ThemeManager` is already gone and the user did
  **not** ask for it back. There is currently exactly one palette and no picker; `Theme.swift`'s own
  comment records the removal, and `preferredColorScheme` is a hardcoded `.dark`.
  **The mechanism is the work.** `Theme` is a `nonisolated struct` exposing **67 `static let`**
  constants, which cannot vary at runtime, and 243 files read them directly as `Theme.bg` and friends.
  Making the palette selectable means those become computed properties over an active palette value —
  a mechanical but wide change, and the one place a mistake shows up as the wrong colour somewhere
  nobody looked. Two consequences to plan for rather than discover:
  - **19 `Theme.ns*` AppKit mirrors** exist so the markdown editor can draw in sRGB `NSColor`. They
    must resolve from the same active palette or the editor keeps drawing the old one.
  - **`Theme.swift` is compiled into `CadenceWidgets`** (4 references in `project.pbxproj`). A widget
    is a separate process, so the selected palette has to reach it through the app group, the way
    `CadenceWidgetRefreshCenter` already does — otherwise widgets stay on the default palette.
  Also delete the stale **"Theme"** row in Settings → Coverage (`iOSMobileCapability.all`,
  `iOS/iOSSettingsComponents.swift:149`), which advertises a picker to the user that does not exist —
  either before this ships or as part of it.

- [T-147] **A cancelled task is unreachable on iOS — decided: show them in Completed.** Every list
  query filters cancelled out (`CadenceTaskQuerySupport` ×6, `CadenceCalendarPlanningSupport`,
  `iOSSearchView` ×2, the note `[[task:` picker) and the inspector auto-dismisses on Cancel, so on iOS
  cancelling is deleting without saying so. **User's call: cancelled tasks appear in Completed**,
  visually distinct — strikethrough, not the green done treatment. macOS already renders a cancelled
  row distinctly, so the row work exists; what is missing is letting them through the queries. Check
  every one of the filter sites rather than the two obvious ones.


- [T-183] **Audit the remaining fixed-width columns for missing floors.** `T-177` and Today's own
  `twoPaneMinimumWidth` are the same defect twice: a fixed `.frame(width:)` beside a flexing pane,
  with nothing asserting the flexing side stays usable. Worth one sweep for other fixed column widths
  — `CadenceRegularSplitLayout.listPaneWidth`, the calendar rails, the settings rail — asking in each
  case what the other side gets at the narrowest host that reaches it.


- [T-179] **`control action=detach` ignores the `udid` argument and closes every simulator panel.**
  An agent detaching its own device closed three other agents' panels (iPhone 17e, iPhone 17 Pro Max,
  iPad Air 11-inch). No device or app state was altered and they can re-attach, but under parallel
  agents this is a cross-agent side effect worth knowing: either pass no `udid` and expect it to be
  global, or do not detach at all when others may be attached.


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

- [T-169] **iPhone "More" tab: make it a grouped list, not a flat one.** User's call.
  `iOSMoreTabView` is currently the six destinations that did not fit the four-slot tab bar — Focus,
  Goals, Habits, Lists, Search, Settings — in one flat list, which describes the tab bar's overflow
  rather than a design. Group it the way the Settings screen already groups its categories: work
  (Goals, Habits, Focus), organisation (Lists), then Search and Settings. `CadenceMobileSettingsLayout
  .groups` is the precedent and its doc explains the reasoning ("three groups, not twelve loose
  rows"); reuse the shape, not the contents.
  The failure mode to avoid is named in the ticket's history: this replaced `iOSCompactHomeView`, a
  grid of eight tiles standing in for navigation the app did not have, so do **not** turn it back
  into a dashboard.

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

- [T-166] **`defaultColorHex` is eleven hand-typed hex literals feeding `Color(hex:)`.** Exactly the
  pattern `AGENTS.md` bans outside `Theme.swift` and genuinely user-owned `colorHex`. These are
  app-defined defaults, so they are a standing exception that predates the rule. Adding a
  `Theme.redHex` for one of the eleven would make the exception *less* consistent — it wants one
  pass over all of them or none.


- [T-161] **Tests pin helpers, not wiring.** The T-149 verifier proved by mutation that reverting the
  `macOSRootCommandActionSupport` fix leaves all 1692 tests green, and the same holds for T-150 —
  nothing observes that `MarkdownEditorView` calls the shared functions. `D-113` closed this for the
  markdown indent formula by testing that the stylist *reads the shared metrics*, not merely that the
  numbers are right. Worth applying that pattern to the two search fixes, and treating it as the
  default shape for consolidation work: a test that passes when the call site is reverted has not
  pinned the consolidation.


- [T-126] **The MCP smoke test can be run from here, and is data-safe** — it verifies read-only mode
  then drives a temp fixture store via `CADENCE_MCP_STORE_URL`, never the app-group store. SPM
  checkouts are already resolved locally, so no network is needed. One gap worth closing before
  relying on it: it rebuilds into the shared `.codex-build` with no private-path override, so
  verifying an MCP change disturbs the same DerivedData the live processes and Codex use.

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

- [T-115] **The iOS Swift 6 flip is blocked by a toolchain bug, not app code.** With `D-86`'s three
  errors fixed the iOS module is diagnostically clean, and swift-frontend then crashes in IRGen on a
  reabstraction thunk carrying an `(any Actor)?` parameter. Attributed, not assumed: pristine HEAD
  with those same errors removed a different way crashes identically with zero diagnostics, and
  pristine HEAD under Swift 5 builds clean. Xcode 26.6 / Swift 6.3.3. Recheck on a toolchain bump.

- [T-73] **Audit iPhone/iPad divergence and share what should be shared.** Standing rule added to
  `AGENTS.md` and `CLAUDE.md` 2026-08-17: the two differ in *layout* only, never in how a row, chip,
  header or picker looks or behaves. This item is the sweep to make the code match that — find the
  places where a phone view and an iPad view are near-copies and collapse them into one view
  parameterised by size class. Distinct from [T-32], which is macOS↔iOS *feature* parity; this is
  iPhone↔iPad *implementation* sharing. The Notes starting point is closed (`D-44`, one view for all
  three hosts) and so is the page-header family (`D-62`). What is left of the original list —
  `iPadTodayView` vs the compact Today, and the compact/regular branches inside the task row — is
  in flight now.


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
- [T-18] **Chinese localisation.** Backlogged. Nothing is localised today: user-facing strings are
  hardcoded English at the call site, and `DateFormatters` uses fixed formats. Two known hazards
  already documented in this repo — `Calendar.current` is not Gregorian everywhere (a `yyyy-MM-dd`
  storage key becomes `2569-…` under a Buddhist calendar), and weekday symbol arrays are indexed by
  weekday number rather than by `firstWeekday`. Both bit us before; both get worse with a second
  locale.
- [T-19] **Data safety, backup and controls.** `PrivacyDataResetService` (wipes every model),
  `StoreBackupManager`, and `DataIntegrityRepairService` exist; Settings → Data Safety is the
  surface. Worth reviewing as a whole: what a reset actually removes, whether backups are
  restorable, and whether the controls say plainly what they do. Note the standing rule that every
  new `@Model` must be added to the reset path or a wipe leaves orphans.
- [T-20] **Settings UI for macOS**, and possibly iPad/iOS after. iOS Settings was rebuilt in
  `775833d` — category list plus value rows — and macOS has not caught up; it is the older
  twelve-category shell. Bringing macOS to the same vocabulary would also settle which of the two is
  the reference.
- [T-21] **Verify the Apple Reminders integration end to end.** `RemindersManager` is macOS-only,
  separately authorised from Calendar, surfaced at Settings → Reminders. The app must keep working
  when access is denied — that path is the one most likely to be untested.
- [T-22] **Audit against Apple's App Review guidelines** before publishing. `docs/app-review-notes.md`
  and `docs/privacy.html` are the existing submission material and are the place to start. Likely
  areas: what the privacy manifest declares versus what is actually collected, Sign in with Apple
  being entitlement-gated and optional, the AI feature requiring a user-supplied key, and EventKit
  usage strings matching real behaviour.

## Done

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
  unspellable-wrong and an idempotent attach, because a duplicate link double-counts a list's tasks.
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

- [X-01] **Home screen redesign** — three rounds of mocks (quiet grid, today-first, informative
  cards) were all rejected before the real problem surfaced: there was no tab bar, so Home was
  standing in for navigation the app did not have. Superseded by [D-07].
- [X-02] **Keyboard-accessory verification above a raised software keyboard** — the accessory is
  confirmed to render and work, but `ConnectHardwareKeyboard` is a Simulator.app preference and the
  simulators run headless, so the raised-keyboard geometry cannot be checked without opening
  Simulator.app. Not worth the intrusion.
