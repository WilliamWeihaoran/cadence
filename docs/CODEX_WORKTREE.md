# Codex Worktree Protocol

Codex writes code here, in its own worktree, on its own branch. The coordinator lands it.

This exists because **two writers in one checkout collide in two measured ways**, neither of which
announces itself:

- **[[T-1385]]** — `scripts/agent-commit.sh` stages **whole files**. When two writers edit one file,
  one commit silently carries the other's half-finished work: no refusal, no declined hunk, nothing
  in `git status` that looks wrong. It reddened CI on `d65d294`, where a commit swept in a sibling's
  in-progress block that contained a forward reference to a declaration still uncommitted.
- **[[T-975]]** — a commit lands through a private index and never writes the shared checkout, so
  the tree drifts behind HEAD. `[stale base]`, `[stale copy]` and `[never checked out]` ([[T-1394]])
  are three different repairs and picking the wrong one destroys work.

A separate worktree removes the first entirely — disjoint filesystems cannot interleave — and makes
the second Codex's own problem rather than a shared one.

## The flow

1. **Codex works in its worktree**, on a branch named `codex/<topic>`, based on `origin/main`.
2. **Codex commits with plain `git commit`.** It does *not* run `scripts/agent-commit.sh`: that
   script enforces ledger discipline that requires editing `docs/TODO.md`, which is the one file
   guaranteed to conflict.
3. **Codex never touches the ledger.** Instead it appends its ticket entries to
   `docs/CODEX_LEDGER_INBOX.md` — **append-only, newest last**. Appending merges cleanly; editing
   a 12,000-line file in place does not.
4. **The coordinator reviews** with `./scripts/codex-land.sh review codex/<topic>`, which refuses on
   lease violations, ledger edits, missing inbox entries and id clashes.
5. **The coordinator runs the tests and lands it** through `scripts/agent-commit.sh`, folding the
   inbox entries into `docs/TODO.md` in the same commit. Every guard the repository has then applies
   to Codex's work exactly as it applies to everyone's. **When the coordinator PRE-FILED a stub for
   the id and assigned the branch to it, the fold REPLACES THAT STUB'S BODY IN PLACE** — one id, one
   entry, no second entry, no deletion, no renumber ([[T-1458]], [[T-3003]], [[T-3004]]). Step 4's
   `CODEX-INBOX-ID-CLASH` on a pre-filed id is that case, not a blocker ([[T-1800]]).

The coordinator is the bottleneck on step 5 deliberately. It costs minutes, and it is what keeps
`FOREIGN-STAGED`, `REMOVES-HEAD-LINES`, `LEDGER-ID-UNFILED`, the closure reading and the foreign-hunk
notice applying to code that did not come through them.

## The lease

Codex may write **only** to paths matching the lease below, and never to a path another writer holds.
The coordinator updates this block when the assignment changes; `codex-land.sh lease` parses it, so
this file is the single source of truth and there is no second list to drift.

Patterns are shell globs matched against repository-relative paths. `docs/CODEX_LEDGER_INBOX.md` is
always allowed and never needs listing.

```lease
Cadence/iOS/iOSList*.swift
Cadence/Shared/CadenceTypography.swift
CadenceTests/CadenceTypographyScaleTests.swift
CadenceTests/CadenceCodex*.swift
Cadence/Shared/Components/CadenceChoicePicker.swift
Cadence/iOS/iOSChoicePicker.swift
Cadence/Shared/Components/CadenceTagChip.swift
Cadence/macOS/Views/SettingsAppearanceSection.swift
Cadence/CadenceApp.swift
Cadence/iOS/iOSTaskViews.swift
Cadence/iOS/iOSTaskRowActionViews.swift
Cadence/iOS/iOSTaskGroupSection.swift
Cadence/Shared/CadenceCapturePaletteSupport.swift
Cadence/iOS/iOSCaptureRadialMenu.swift
Cadence/iOS/iOSFocusView.swift
Cadence/Shared/CadenceFocusPlanningSupport.swift
CadenceWidgets/CadenceWidgetsBundle.swift
Cadence/iOS/iOSFloatingCreateTaskButton.swift
Cadence/Shared/Components/CadenceBoardMetadataChip.swift
CadenceTests/CadenceTagChipStyleTests.swift
Cadence/iOS/iOSMarkdownStylingSupport.swift
Cadence/iOS/iOSMarkdownEditor.swift
Cadence/iOS/iOSMarkdownTableGridRendering.swift
Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift
Cadence/macOS/Services/CadenceMCPRefreshCoordinator.swift
Cadence/macOS/Services/FocusManager.swift
Cadence/macOS/Services/QuickTaskPanelController.swift
Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift
Cadence/macOS/Views/TimelineDropInteractionSupport.swift
Cadence/Services/CadenceRemindersManager.swift
Cadence/Services/CadenceForkedOccurrenceRemover.swift
CadenceWidgets/FocusSessionWidget.swift
Cadence/Shared/CadenceFocusSessionSnapshot.swift
Cadence/Services/CadenceWidgetRefreshCenter.swift
Cadence/Services/CadenceTodayWidgetSupport.swift
Cadence/iOS/iOSCompactTabShell.swift
Cadence/iOS/iOSRootView.swift
Cadence/macOS/Views/CalendarEventPresentationSupport.swift
Cadence/iOS/iOSCalendarBoardView.swift
Cadence/iOS/iOSBoardCards.swift
Cadence/macOS/Views/GlobalSearchIndexSupport.swift
Cadence/macOS/Views/GlobalSearchSupportViews.swift
Cadence/macOS/Views/macOSRootCommandActionSupport.swift
Cadence/macOS/Views/EventNoteSupportViews.swift
Cadence/macOS/Views/NotesView.swift
Cadence/iOS/iOSTodayCompactViews.swift
Cadence/Shared/CadenceSavedLinkPersistence.swift
CadenceTests/CadenceSavedLinkPersistenceTests.swift
Cadence/macOS/Views/LinksView.swift
CadenceTests/CadenceInboxRemindersSurfaceTests.swift
CadenceTests/CadenceSharedConstantReuseSweepTests.swift
```

### LEASE WIDENED 2026-10-09 (third batch) — three paths so [[T-3085]]'s shared wording has somewhere to live

Codex asked for exactly the three paths the T-3085 instruction below already prescribes, which is the
right ask: that instruction says the sentence moves into `CadenceSavedLinkPersistence` and the pins go
in `CadenceSavedLinkPersistenceTests`, and neither is reachable from the leased mobile file. Granting
the presenter without them would strand the shared-wording half. Additive: three in, none out.

**`Cadence/Shared/CadenceSavedLinkPersistence.swift`** — for the confirmation title and sentence,
beside the existing `saveFailureNotice` / `deleteFailureNotice`. **Do not change what `delete(_:)`
does.** Its `modelContext.delete` + `commitDelete` and its `actionError` reporting stay exactly as
they are: the confirmation gates that call, it does not replace or wrap it.

**`CadenceTests/CadenceSavedLinkPersistenceTests.swift`** — for the pins. It already source-scans both
link surfaces (there is an `iOSListLinksPanel` scan around `:220-261`), so extend it rather than
starting a new suite.

**`Cadence/macOS/Views/LinksView.swift` — granted for ONE edit and nothing else.** Replace the literal
at `:82` with the shared helper. **The rendered string must be byte-identical before and after**:
today it is `"This will permanently delete \"\(link.title)\"."` under the title `"Delete Link?"`, and
macOS behaviour must not change by so much as a full stop — this grant exists so the two platforms
cannot drift on wording, not to retune the Mac's copy. Nothing else in that file moves: not the
hover-revealed trash, not `deleteLink(_:)`'s reachability from the confirm closure only, not the
card styling.

**Still out of scope, restated because this grant touches the Mac:** the link-row chrome. The owner
decided the deletion, not the styling, and mobile's plain rows are the Lists page's one deliberate
treatment. Delete-failure reporting is likewise unchanged on both platforms.


### INSTRUCTION 2026-10-09 — [[T-3085]] on a path Codex already holds: a saved link deletes with no confirmation on mobile

No new grant. `Cadence/iOS/iOSListSupportViews.swift` matches the standing
`Cadence/iOS/iOSList*.swift` glob, which is why agent `linkdelete` stopped rather than editing it —
and it stopped correctly: **both the swipe button and `delete(_:)` live inside that one file, so no
half of this change lands outside the fence.** The owner has decided it, so it comes to Codex.

**The defect, verified in source by two readers, not relayed.** macOS `LinksView.swift:80-83` presents
`Delete Link?` / *This will permanently delete "&lt;title&gt;".* and `deleteLink(_:)` is reachable only
from that confirm closure. Mobile `iOSListSupportViews.swift:692-696` calls `delete(link)` straight
out of a `.swipeActions` button, which goes through `CadenceSavedLinkPersistence.delete` —
`modelContext.delete` plus `commitDelete` — so **one gesture commits to the store and to CloudKit**.
`allowsFullSwipe: false` costs a flick a second tap but names nothing and cannot be answered "no".

**It is not undoable, checked rather than assumed.** No `holdUndo` on the saved-link path (its only
callers are `CadenceListDeleteHelpers.swift:127` and `CadenceTaskMutationSupport.swift:843`), no
toast, no Recently Deleted. Model-level undo is deliberately absent app-wide — [[T-367]] removed
`modelContext.undoManager` on purpose. The rollback inside `CadenceSavedLinkPersistence.delete` is
*failure* handling; a successful delete is final. And the direct swipe was never chosen deliberately:
the saved-link history ([[T-327]], [[T-507]], [[T-509]]) is entirely about whether a write lands or
is reported, never about whether it is confirmed.

**The design, recorded so it is not re-derived.** Follow `iOSNoteDeletionSupport.swift`'s shape: a
`View` extension over a `Binding<SavedLink?>`, the swipe sets the binding and nothing else, so exactly
one `CadenceSavedLinkPersistence.delete` call site survives behind exactly one presenter. Use
**`.alert("Delete Link?")` weight, not the full modal sheet** — a note or list delete earns the sheet
because it is a cascade with a summary; a saved link is one trivial object, and
`iOSTaskDetailSheet.swift:88` already establishes the light idiom. **It must name the link**, and the
sentence should move into `CadenceSavedLinkPersistence` beside `saveFailureNotice` /
`deleteFailureNotice` so the two platforms cannot drift on wording the way they drifted on the scheme
check in T-509. Keep `delete(_:)`'s existing `actionError` reporting — the confirmation gates it, it
does not replace it. Pins belong in `CadenceTests/CadenceSavedLinkPersistenceTests.swift`, which is
**not** leased and already source-scans both link surfaces.

**Explicitly NOT in scope: the card styling.** Codex's audit bullet welded a cosmetic difference to a
destructive one. Only the deletion half loses data. Mobile's links are plain `List` rows sharing the
Lists page's one deliberate `iOSListRowChrome()` treatment; carding them would make that panel the
only carded surface on the page. The owner decided the deletion, not the chrome.

**Worth folding in while you are there:** that panel uses raw `.swipeActions` rather than the shared
`iOSSwipeActionsModifier` / `iOSListRowSwipeActions` the same file's list rows adopted after the
"swipe did nothing on iPad" defect (`iOSListSupportViews.swift:49-55`). It is not discarded today
because the panel builds its own `List`, but a future re-host in a `ScrollView` would make the swipe
silently vanish.


### LEASE WIDENED 2026-10-09 — five wiring paths, so the approved parity fixes are not left inert

Codex asked for these by name to finish work already granted on 2026-10-08, and the ask is the right
one: four of the five exist because **a search hit that cannot be opened is half a fix**, which is
what that grant already told it. Granting the index without the destination would have shipped
exactly the inert result the grant warned against. Additive: five patterns in, none out.

**The ticket ids Codex asked for: [[T-3082]], [[T-3083]], [[T-3084]]** — filed in the same commit as
this grant, one per finding, each carrying the audit's file:line evidence and the conditions the
2026-10-08 grant attached. Codex should fold its inbox entries into those three ids and allocate no
new ones.

**Four paths for [[T-3084]], the Mac note-search fix.** `GlobalSearchSupportViews.swift` for the
ordinary-note destination and category; `macOSRootCommandActionSupport.swift` to resolve the selected
note; `EventNoteSupportViews.swift` for the kind-aware navigation request; `NotesView.swift` to select
requested ids in Daily, Weekly and Notepad. **`NotesView.swift` is the one to be careful in** — it is
the Mac's whole notes surface, and selecting a requested id must not disturb what it already does on
open. Granted for the selection path, not for a re-layout of that page.

**One path for [[T-3077]], the Completed chip.** `iOSTodayCompactViews.swift`, **for exactly one
edit**: passing `showsCompletedControl: false` from `iOSCompactTodayView.optionsBar`. The flag itself
goes in `iOSTaskViews.swift`, which Codex already holds. Do not change anything else in that file —
agent `todaytrim` landed the owner's Today header changes there in `69b9d60b` and the ledger entry
explains each one. In particular do **not** restore `eyebrowDetail:` and do **not** flip
`CadenceTaskSurfaceOptions.options(for: .today).showsCompletedToggle`, which macOS reads.

**Still NOT granted, and these are now owner-DECIDED rather than undecided** — Codex should not start
them until they are filed with paths: Focus checkmark semantics (**the owner chose mobile's immediate
complete; the Mac moves to match**), list-detail memory (**the owner chose the Mac's per-container
behaviour; mobile moves to match**), Saved Links deletion (**the owner chose the Mac's confirmation;
mobile's direct swipe-delete goes**), and the Notes label vocabulary (**Mac's naming wins**). The
month-cell priority policy and the search-truncation difference are still open questions.


### LEASE WIDENED 2026-10-08 — three paths for Codex's own parity audit, plus one instruction on a path it already holds

Codex delivered a read-only iOS/macOS parity audit against `c3d5dbdc` and asked for exact lease paths
before implementing. The owner triaged it and chose: **Codex takes all three of its high-value
functional findings.** Additive: three patterns in, none out.

**Verified before granting**, because the audit's own caveat says concurrent sidebar and Today edits
appeared during it and to recheck against current main: all three paths exist on HEAD, none was
already in the fence, and none is held by an agent in flight (`listrowheight` and `listsdoor` hold
`iOSRootSidebar.swift` and `CadenceSidebarMetrics.swift`; `todaytrim`, `sidebarspacing` and `daysnap`
have landed).

**(1) `Cadence/iOS/iOSCalendarBoardView.swift` — mobile Calendar Board event cards are inert.** Mac
cards open `CalendarEventEditPopover` (`CalendarBoardItemSupportViews.swift:186`); mobile renders a
display-only card with no activation callback (`:479`). Reuse the existing mobile event
inspector/editor route rather than building a second one, and carry read-only-calendar behaviour
across — an event on a subscribed calendar must refuse the same way it refuses on the Mac. Check the
caller as well as the card: a card that gains a callback nobody wires is not a fix.

**(2) `Cadence/iOS/iOSBoardCards.swift` — cancelled cards still look active.** The glyph recognises
cancellation but title contrast, strike-through and background attenuation check only `isDone`
(`:323`). Mac dims cancelled titles (`KanbanCardView.swift:552`) and ordinary mobile task rows
already use the shared settled-state decision — **use that same shared decision, do not add a third
spelling of "settled".** This is not the completed-section membership issue, which is already fixed;
do not re-open that.

**(3) `Cadence/macOS/Views/GlobalSearchIndexSupport.swift` — Mac search omits daily, weekly and
notepad notes.** Mac filters note candidates to `kind == .meeting` (`:259`); mobile searches every
non-blank kind (`iOSSearchView.swift:195`). **This is the one the owner cares about most**: their Mac
archive holds 97 notes including 16 legacy daily notes and 9 documents, and today none of those is
findable from the Mac. Extend the note candidates **and** the destination resolution — a hit that
cannot be opened is half a fix — preserving task-embed title resolution, tags, ranking and identity.
`iOSSearchView.swift` is **reference only and is NOT granted**: read it to match behaviour, do not
edit it.

**(4) [[T-3077]] — `Cadence/iOS/iOSTaskViews.swift`, which Codex ALREADY holds.** No new grant; this
is an instruction on an existing one. Agent `todaytrim` landed the owner's Today changes in
`69b9d60b` but could not remove the "Completed N" chip, because it is drawn unconditionally inside
`iOSTaskViewOptionsBar` (`:651-665`) in that leased file. The fix it identified, which Codex should
take: add `var showsCompletedControl = true` beside `spreads`, wrap the trailing `Button` in it, and
pass `false` from `iOSCompactTodayView.optionsBar` **only**. Do **not** flip
`CadenceTaskSurfaceOptions.options(for: .today).showsCompletedToggle` — macOS's `TasksPanel` reads
it and the owner scoped this change to the phone. Today already reads correctly either way, because
the chip and the new chevron write the same state; this removes the second control, not a bug.

**Deliberately NOT granted, because the owner has not decided them**: the Focus checkmark semantics
(Mac logs adjustable time, mobile completes immediately), list-detail per-container memory, and the
month-cell priority policy. All three are product decisions the audit itself flagged as such. The
visual batch — Kanban card geometry, list-detail gutters, markdown rhythm — is also not granted:
several of those divergences are deliberate and the audit says so.


### LEASE NARROWED 2026-10-07 — `CalendarManager.swift` comes OUT, so [[T-3032]] can be fixed

**Exactly one pattern struck: `Cadence/macOS/Services/CalendarManager.swift`. 39 -> 38.** Asserted as
a set difference rather than a line count, and rebuilt from `git show HEAD:docs/CODEX_WORKTREE.md`
rather than from a copy read earlier in the session — the discipline `4ccaf39d` adopted after an
agent nearly revoked a live grant from a stale base.

**Why it is safe to take back.** The file was granted for [[T-122]]'s annotation-only pass. That pass
has LANDED (`bc082946`), and Codex's own report says the warning it carries —
`CalendarManager.swift:110` — is one of seven actor-bound observer/KVO callbacks that **cannot be
honestly cleared within the annotation-only restriction**. So there is no further T-122 work in this
file that the current grant permits: clearing that warning needs a new owner decision about where a
callback runs, not a new lease. Revoking a grant nobody can act on is the opposite of revoking a live
one.

**Why it has to come out at all.** [[T-3032]]: `CalendarManager.isAuthorized` is a plain `var` with
no `private(set)` (`:24`), and it is the **only** guard on all six EventKit writes.
`CadenceRemindersManager` spells the same flag `private(set)` (`:39`) — the asymmetry is in the tree,
not in anyone's opinion. Four tests set `CalendarManager.shared.isAuthorized = true` on the real
singleton holding a real `EKEventStore`, and they are safe today only by accident: they hand EventKit
events from a throwaway store, which it refuses. The call they happen not to make would write to the
owner's real default calendar.

**This does not re-open T-122's eight-file grant**, which stands; only this one path moves. If Codex
needs it back for a decided callback change, the coordinator re-grants it the same way it granted it.


### LEASE WIDENED 2026-10-07 (second batch) — one path for [[T-122]], and the widget-membership sequence for [[T-168]]

Codex landed `codex/leased-followup-batch` for review and came back with exactly two asks. Both are
answered here. Additive: one pattern in, none out, 38 -> 39.

**[[T-122]] — `Cadence/macOS/Views/CalendarEventPresentationSupport.swift:285-305`, granted.** This is
the LAST of the Swift 6 warnings that can be cleared inside the annotation-only rule. It is
`CalendarEventDragPayload`, a pure string codec: `static func string(for:)` and
`allDayEventPayload(from:)` on an enum with two private `let`s and no stored state. The grant is for
an annotation, not a rewrite — **the decode must stay synchronous**, which is the same constraint the
first grant put on `TimelineDropInteractionSupport`: a drag decoder that gains a hop stops answering
in the callback that asked it.

**The other seven warnings are CORRECTLY not fixed, and that is the grant working rather than
failing.** Codex reports them as actor-bound observer and KVO callbacks that cannot be honestly
cleared within the annotation-only restriction. The first grant said in as many words that a warning
which cannot be cleared that way gets **reported in the inbox entry instead of cleared**, because the
report is worth more than the silence. It did that. Nobody should read eight-minus-one as incomplete
work; `SWIFT_VERSION` stays 5 and the ticket's standing *investigate and report, do not flip* is
intact.

**[[T-168]] — the project-membership STOP was the right call, and here is the sequence.** The grant
said to stop rather than edit `Cadence.xcodeproj/project.pbxproj` if widget-target membership needed
a hunk, and Codex stopped, made no edit and claimed no workaround. The reason the stop exists is
[[T-117]]: that file must not be written while the owner has Xcode open, and whether the coordinator
or the owner lands it is decided at the time, not in advance.

**The coordinator adds the membership, not Codex, and it is a known four-line shape.** `7d5bad39`
did exactly this for `CadenceTaskBundleMutationSupport.swift` — a `PBXFileReference`, a
`PBXBuildFile`, a group-children line and a Sources-phase line, with `pgrep -x Xcode` re-checked
immediately before the write and the file backed up by `cp` first. `Cadence/Shared/` is a
`PBXFileSystemSynchronizedRootGroup` so the app target picks a new file up by itself; the widget
extension is a second target and does not, which is the whole of the problem Codex hit.

**So the order is: Codex writes `CadenceFocusSessionSnapshot.swift` and the widget against it and
says so; the coordinator then lands the membership in the same pass that integrates the branch.** Do
not build the widget first and discover the membership last — a snapshot type the extension cannot
see compiles fine in the app and fails only in the target nobody builds by default. **No T-168 lease
path is retired by any of this**: nothing of half (a) is claimed, no session persistence exists, and
the chrome toggle is unwritten.


### LEASE WIDENED 2026-10-07 — six paths for [[T-168]], because the owner answered its three questions

The grant above withheld T-168 on the grounds that it was three product decisions and a new surface
rather than a set of dependencies. The owner has now made all three, so this publishes them together
with the paths they imply. Additive: six patterns in, none out, 32 -> 38.

**(1) The widget: yes, ONE read-only current-session widget.** Codex's own design is the one taken —
the live timer plus the subject, drawn with `Text(timerInterval:)` so the system animates the count
without waking the extension, because a WidgetKit timeline cannot tick and a reload-every-second
timeline is not an option. **No second widget and no task-list widget**: two widgets that say the
same thing was the outcome the entry told us to avoid. `CadenceWidgets/FocusSessionWidget.swift` is
new; `CadenceWidgetRefreshCenter.swift` and `CadenceTodayWidgetSupport.swift` are granted for the
registration and `instrumentedKinds` only, not for a rewrite of what the existing widgets do.

**(2) The chrome: hide the tab bar in landscape Focus, AND a tap on empty space toggles it back.**
This is the owner's refinement on the question as asked, and it is the binding half of the grant:
hiding alone is not what was asked for. In landscape Focus the four-tab bar is hidden so the timer
goes full-bleed, and a tap on empty space — not on the timer, not on the transport controls, not on
the task picker — toggles it back into view, and toggles it away again. So the bar is **recoverable
without rotating**, which is what makes hiding it safe: a hidden bar that can only be restored by
rotating the phone would strand someone in Focus. Granted: `Cadence/iOS/iOSCompactTabShell.swift`.
Every tab draws through that shell, so the hiding must be expressible as something Focus asks for
and the other three tabs cannot accidentally inherit; portrait Focus and all of iPad are unchanged.

**(3) Rotation: a running session must survive it.** `iOSRootView` replaces the compact shell with
the regular one at a size-class change, which today throws away an in-progress session, and the
owner's answer is that it must not. Focus session state moves above the shell so the swap cannot
take it. Granted: `Cadence/iOS/iOSRootView.swift`. This is the same persistence (1) needs — a widget
process cannot see in-memory state in `iOSFocusView` either — so do them as one piece of work and
not twice.

**The persistence itself is `Cadence/Shared/CadenceFocusSessionSnapshot.swift`, new, and it is the
prerequisite rather than a detail.** iOS focus state lives in `iOSFocusView`'s own
`CadenceFocusTimerState` with no shared state object, and `FocusManager` is `#if os(macOS)` only
(T-242) — do **not** make it cross-platform, that would be a second timer authority with nothing
incrementing its `elapsed`. The snapshot is a small app-group value — subject, start instant,
running/paused, and nothing more — written by the app and read by the extension. It goes in
`Shared/`, not `Services/`, for a mechanical reason: the `Cadence/` tree is a
`PBXFileSystemSynchronizedRootGroup` so a new file there self-registers, while `Cadence/Services/`
holds explicit `PBXFileReference`s and a new file there needs a project edit. `CadenceFocusHandoff`
is NOT this type and must not be made into it — it is an in-memory message carrying a
`CadenceFocusTarget` and a token, with deliberately zero macOS readers.

**Two hard stops.** There is **no `cadence://focus` route** — the owner chose the widget without one,
so tapping it opens the app and nothing registers a new deep link. And if making the snapshot
readable from the widget target turns out to need a membership edit in
`Cadence.xcodeproj/project.pbxproj`, **STOP and report instead of editing it**: that file must not be
touched while the owner has Xcode open ([[T-117]]), and whether the coordinator or the owner lands
that hunk is a decision made at the time, not in advance.

Existing widgets to match are **`CalendarSnapshotWidget` and `TodayTasksWidget`** — the two named in
T-168's original text that no longer exist, `HabitCheckInWidget` and `MilestoneMomentumWidget`, went
with the Habits/Goals retirement, and a design that matches them matches nothing.


### LEASE WIDENED 2026-10-07 — fifteen paths for [[T-3011]], [[T-1411]], [[T-1400]] and [[T-122]]

The owner granted these after Codex named each one in its batch report and the landing note above
recorded that none of them was granted by the landing. Each path was checked to exist on HEAD and to
be absent from the fence before being added, so this grant adds fifteen patterns and retires none;
the ten paths of the first 2026-10-07 grant and the four standing globs are untouched.

**Why this is a grant and not a widening by the writer.** `codex-land.sh review` refuses
`CODEX-LEASE-VIOLATION` on a path outside the fence, and the tool's own printed remedy is for the
coordinator to widen main's lease deliberately rather than for the branch to carry the widening
hunk. Codex edited none of these files before asking, which is why there is a branch to grant for
rather than one to refuse.

**[[T-3011]] — `Cadence/iOS/iOSFloatingCreateTaskButton.swift`, to wire the lifetime owner that
already landed built-and-unwired.** Replace the `@State UUID` at the drop-target modifier with the
`CadenceNewTaskDropRegistrationLifetime` that `makeRegistrationLifetime()` builds, and call
`activate()` where the registration is published — a lifetime that is never activated must stay
inert, because a discarded `@State` initial value enqueuing a `destroy` is the bug the reference
type exists to avoid. **Conditional:** [[T-3008]]'s guarantee is the thing this must not reopen, so
`CadenceNewTaskDropRegistrationTests` stays green unmodified, and the entry's own third requirement
stands — land a measurement that this bounds something, not only the wiring. `retire(_:)`'s doc
comment stops saying the cost is still paid only once production owns a lifetime.

**[[T-1411]] — `Cadence/Shared/Components/CadenceBoardMetadataChip.swift` and
`CadenceTests/CadenceTagChipStyleTests.swift`.** The patch order is the one the entry already
records and it is not negotiable, because declaring a root over an unconverted chip is the
scattering [[T-1364]]'s brief forbids: convert the chip first (environment fonts, additive glyph
growth, wrap rather than shrink-to-fit, fixed metrics unchanged), then extend the existing caller
inventory to the undeclared Calendar and macOS consumers, then declare both Lists roots, then add
exactly those two to `CadenceTypographyConversionSweepTests`. The chip is drawn on macOS too, so the
macOS rendering must be unchanged at the default text size.

**[[T-1400]] — the four iOS markdown files.** `monoFont`, the table geometry and the restyle-on-change
invalidator, scaled through `UIFontMetrics`. **Do not convert `iOSMarkdownStyler.baseFont`** — it is
`.preferredFont(forTextStyle: .body)` and has followed the reader's text size all along, which is the
finding that corrected the audit's headline; moving it to the Cadence ramp would be a regression
dressed as the fix. Table geometry derives from the same fonts rather than from a second constant,
and a restyle preserves selection and caret. The Mac half of this ticket is **not** granted: it waits
on [[T-1399]], and `Cadence/macOS/Editor/` is not in this fence.

**[[T-122]] — the eight Swift 6 files, under a condition that is the whole point of the grant.**
The owner's standing decision on this ticket is *investigate and report, do not flip*, and this grant
does not change it: `SWIFT_VERSION` stays 5 and no target flips. What is granted is clearing the one
error and the thirteen warnings the 2026-10-07 re-measure found, as preparation that is **inert under
Swift 5**. A fix qualifies only if it is a type- or annotation-level change — a `Sendable`
conformance, a `@Sendable` closure annotation, an isolation annotation that states the isolation the
code already has at runtime. A fix that moves work to a different actor or defers it does not
qualify, however quiet it makes the compiler: **no blanket `Task {}` hops and no
`nonisolated(unsafe)`**, because `FocusManager`'s observers bank synchronously before sleep and the
drag decoders in `TimelineDropInteractionSupport` must stay synchronous. Where a warning cannot be
cleared that way, Codex reports it in the inbox entry instead of clearing it — that report is worth
more than the silence. The zero-warning Swift 5 baseline must be re-measured as still zero before and
after, and the entry's own caution stands: the error may hide further debt behind it.

**[[T-168]] is NOT granted by this, and the omission is deliberate.** Half (a) wants a new widget
surface (`CadenceWidgets/FocusSessionWidget.swift`, `Cadence/Services/CadenceWidgetRefreshCenter.swift`,
`Cadence/Services/CadenceTodayWidgetSupport.swift`) and a `cadence://focus` route; the rest of half
(b) wants `iOSCompactTabShell` to let Focus hide the tab bar and `iOSRootView` to promise State
survives a size-class shell swap. Those are three product decisions and a new surface, not
dependencies — they go to the owner, and the paths stay outside the fence until they come back
answered.


### LANDED PARTIAL 2026-10-07 — `codex/typography-lifecycle-batch`, and NOTHING is retired

Agent `codexland3` landed the branch (tip `980d4b75`) in the commit carrying this note. Every one of
its ten paths was unchanged on main since the merge base `12858406`, checked blob by blob, so the
take was whole-file with no three-way merge. **No lease path is retired, deliberately:** each grant
says to retire its paths when its work lands, and none of the three code tickets did. [[T-2054]]
(the Area/Project chooser) needed no grant — `iOSListEditorViews.swift` is the standing
`iOSList*.swift` glob. [[T-168]] landed landscape content only, so its three paths stay. [[T-3011]]
landed built-but-unwired, and the Dynamic Type cluster's eight paths carry rechecks rather than
conversions, so the ten paths of the first 2026-10-07 grant stay too.

**Changed at landing, and only this:** the `retire(_:)` doc comment in
`CadenceCapturePaletteSupport.swift` keeps saying the memory cost is *still paid*, because the
branch's rewrite read as though a lifetime owner already existed and none does in production.

**Codex's requested dependencies are NOT granted by this landing** — `iOSFloatingCreateTaskButton.swift`
for T-3011's wiring, the compact-shell and root-view decisions and the three widget files for T-168,
`CadenceBoardMetadataChip.swift` / `CadenceTagChipStyleTests.swift` for [[T-1411]], four iOS editor
files for [[T-1400]], and eight Swift 6 files for [[T-122]]. Each is recorded in its ledger entry and
needs the owner's grant here before Codex edits it.

### LEASE RETIRED 2026-10-06 — the three T-3005 Kanban paths are out, because the work landed

`codex/kanban-rendering` landed at tip `05de6408` in the same commit that folded [[T-3005]]'s
pre-filed stub in place. `Cadence/macOS/Views/KanbanSupportViews.swift`,
`KanbanColumnSupportViews.swift` and `KanbanListColumnView.swift` are struck from the lease above.
**Exactly three patterns out, and the four standing globs are untouched** — asserted as a SET
equality, not a line count: what remains is exactly `Cadence/iOS/iOSList*.swift`,
`Cadence/Shared/CadenceTypography.swift`, `CadenceTests/CadenceTypographyScaleTests.swift` and
`CadenceTests/CadenceCodex*.swift`. That last one is Codex's reserved namespace and is where this
branch's `CadenceCodexKanbanRenderingTests.swift` landed, so it must survive its own landing.

**Rebuilt from `git show HEAD:docs/CODEX_WORKTREE.md`, never from a copy read earlier in the
session** — the discipline `4ccaf39d` adopted after an agent nearly revoked a live grant from a
stale base. The branch itself never touched this file (`git diff c3b659f5 05de6408` lists five
paths and this is not one), so nothing retired here was taken from a writer holding its own lease:
a writer that can edit the fence can widen it, and that hunk would have been declined had it
existed.

The `CODEX-INBOX-ID-CLASH` that `codex-land.sh review` exits 3 on was answered by replacing the
pre-filed T-3005 stub's body, not by allocating a second id — the same fold as [[T-3004]].

### LEASE RETIRED 2026-10-06 — the one T-3004 path is out, because the work landed

The heartbeat coordinator landed `codex/task-list-virtualization` (tip `1b187f9e`) and closed
[[T-3004]] in the same commit. `Cadence/macOS/Views/TasksListView.swift` is struck from the lease
above; the four standing globs are untouched. The `CODEX-INBOX-ID-CLASH` that review printed on
T-3004 was the pre-filed stub, whose body was replaced in place, not a blocker.

### LEASE RETIRED 2026-10-05 — the twenty-one T-3003 paths are out, because the work landed

`52a6b408` integrated `codex/data-safety-audit-fixes` and `d17fac9a` closed [[T-3003]] on top of it.
The eighteen production paths and the three narrowly granted guard files are struck; **the four
standing globs above are untouched**, `CadenceTests/CadenceCodex*.swift` among them — it is Codex's
reserved namespace and it is where this very branch's `CadenceCodexBackupAuditTests.swift`,
`CadenceCodexEventNoteResolutionTests.swift` and `CadenceCodexWidgetReopenTests.swift` landed, so
dropping it would strand three files that are now on main.

Asserted as a **set equality**, not a line count: the patterns remaining are exactly
`Cadence/iOS/iOSList*.swift`, `Cadence/Shared/CadenceTypography.swift`,
`CadenceTests/CadenceTypographyScaleTests.swift` and `CadenceTests/CadenceCodex*.swift`.

**Rebuilt from `git show HEAD:docs/CODEX_WORKTREE.md`, never from a copy read earlier in the
session** — a previous agent nearly revoked a live grant that way, and a lease file is exactly the
document where a stale base silently re-grants or silently revokes. The branch itself never touched
this file, so nothing here was taken from a writer holding its own lease: a writer that can edit the
fence can widen its own lease, and that hunk would have been declined had it existed.

The three conditional grants were checked as honoured before retirement, not after:
`markTodo` gained the zero-pin on its old spelling rather than only moving to `commitMarkTodo`;
the popover `SaveSurface` moved to `finishCommittedEdit()` **together with** the coverage pinning
both committing callers and the finisher's single `onChanged()`; and exactly four stale exemptions
were deleted with the detector, the "Exemptions rot" guard and an EMPTY `reportExemptions` intact.

### LEASE RETIRED 2026-10-05 — the nineteen T-1466 paths are out, because the work landed

`df2e8a5a` closed the tracking-UI retirement on top of `3c80981c`, which integrated it.

**CORRECTION, written by the same agent that got it wrong.** The commit message of `b11c3ec6`, which
made this edit, claimed `codex-land.sh review codex/tracking-ui-retirement` would report all
twenty-two files as landed and refuse a single path. That was asserted from the pre-retirement run
and NOT re-run afterwards, and it is wrong in both halves. What `review` actually reports once the
nineteen are retired is: **20 of 22 files already in main, 2 still only on the branch**, and
**`CODEX-LEASE-VIOLATION` on 20 paths**, because `review` refuses a path that is outside the lease
whether or not it has landed — so retiring a grant necessarily brings the violation back. That is the
normal steady state after every retirement, not a regression; the same is true of `36ef5e04`/`4ccaf39d`
and `189f7249`. The two files that are correctly **not** byte-identical in main are the two the
coordinator deliberately resolved differently: `CadenceTests/CadenceRealTreeSweepManifest.txt`, which
is generated and was re-derived against the integrated tree instead of taken, and
`docs/CODEX_LEDGER_INBOX.md`, where main's copy is the UNION of both sides and so is deliberately a
superset of the branch's. The `CODEX-INBOX-ID-CLASH` on T-1466 is the consequence of the id having
been filed in `0030f487` before the code, exactly as T-1465's was in `b802afc5`; it is not a blocker.
The correction is recorded here rather than left in a commit message no one re-reads, because this
file's whole value is that a later reader can believe it.

Retired in the same session that granted them, as the grant below said it would be, and because this
file's own warning is the thing [[T-2069]] and [[T-2058]] are about: *a lease granting paths nobody
is working on is a lease that will eventually be believed.*

**Nothing else was touched, and this was rebuilt on HEAD to make sure of it.** The fence was
regenerated from `git show HEAD:docs/CODEX_WORKTREE.md` rather than from the copy read at the start
of the session — the same discipline `4ccaf39d` adopted after nearly revoking a live grant that way.
The four standing globs are unchanged, `CadenceTests/CadenceCodex*.swift` among them, and **all
nineteen [[T-3003]] paths stay**: that grant (`220b0b91`, `c4eedfcb`) is for Codex's four audit
findings and is still live. 42 patterns in, 23 out, and the 23 are exactly the 4 standing globs plus
T-3003's 19.

### LEASE WIDENED 2026-10-05 — nineteen paths for [[T-1466]], the tracking-UI retirement

Written by the coordinator (agent `codex1466`) while landing `codex/tracking-ui-retirement`, which
is [[T-1466]] — the third and last Codex landing of the day. `codex-land.sh review` REFUSES
`CODEX-LEASE-VIOLATION` on **twenty** paths; the owner authorized this grant explicitly, and the
tool's own printed remedy is for the coordinator to widen main's lease deliberately rather than for
the branch to widen its own. Nineteen of the twenty are granted here. The twentieth is withheld on
purpose and is named below.

**The four live controls.** `Cadence/iOS/iOSTaskDetailSheet.swift` and
`iOSTaskDetailSheetSections.swift` hold the task inspector's unconditional Milestone row, its
`Goal` fetch, its picker state and the `task.goal` binding; `iOSTaskRowActionViews.swift` holds the
task row's Goal chip, its picker and the committing assignment path, and `iOSTaskViews.swift` is
the row call site that passes them through. iPhone and iPad share these same four files, which is
why no iPad-specific path appears.

**The drawn copy.** `Cadence/Shared/CadenceSettingsSectionCopy.swift`,
`Cadence/iOS/iOSDataResetSettingsSection.swift` and
`Cadence/macOS/Views/SettingsDataSafetySection.swift` carry the notification descriptions and the
reset / delete warnings; `Cadence/Shared/CadenceListDeletionSummary.swift` carries the deletion
counts, `CadenceDataExportPresentation.swift` the backup description, and
`CadenceArchiveImportPresentation.swift` the import preview that groups the retained tracking rows
under one **Retained legacy records** line. These are granted for *wording and grouping only* — the
warnings must keep disclosing that legacy records are retained, and the insert/match totals must
stay exact. `Cadence/Services/MarkdownNoteSupport.swift` is granted for the built-in Project Brief
template's default headings (Objective/Deliverables) ONLY; it must not rewrite a saved note or a
customized template.

**`README.md`** stops advertising the three as current features.

**Seven test files** are granted because they are the exact-count and source guards this removal
re-points rather than relaxes: `CadenceArchiveImportEntryPointTests`,
`CadenceChoicePickerDismissalTests`, `CadenceEmptyTitleFallbackSweepTests`,
`CadenceIconOnlyButtonAccessibilityTests`, `CadenceListDeletionSurfaceTests`,
`CadencePresentedTypographyBoundaryTests` and `CadenceSettingsSectionCopyTests`. The two Codex's own
broad run left red — the accessibility census (five chips to four) and the presented-workflow census
(fifteen popovers to fourteen) — are in this set; a census that moves because a control was removed
is re-pointed, and the coordinator checks the positive controls survive rather than taking the
re-point on trust. Codex's new tests need no grant: they land in `CadenceTests/CadenceCodex*.swift`,
the standing namespace.

**THE TWENTIETH PATH IS DELIBERATELY NOT GRANTED.** `CadenceTests/CadenceRealTreeSweepManifest.txt`
is generated, not authored. The coordinator re-derives it with
`./scripts/real-tree-sweep-manifest.sh --write` *after* integrating, so the three new sweep
registrations are proved by the generator against the real tree rather than trusted from a branch
that is eight commits behind main — and main's own copy has moved twice since the merge base, in
`189f7249` and `36ef5e04`. `review` will keep reporting a violation on this one path and that report
is correct. This is the third branch running it is withheld.

**`docs/CODEX_WORKTREE.md` needed no decline this time.** Unlike `codex/sidebar-drawer` and
`codex/continuous-quote-rail`, this branch does **not** add itself to the lease block — Codex states
outright that it does not widen its own lease, and the diff confirms the file is untouched. The
protocol held without the coordinator having to enforce it.

**NOTHING WAS DROPPED, and this was rebuilt on HEAD to make sure.** The four standing globs survive
— `Cadence/iOS/iOSList*.swift`, `Cadence/Shared/CadenceTypography.swift`,
`CadenceTests/CadenceTypographyScaleTests.swift` and `CadenceTests/CadenceCodex*.swift`, dropping
the last of which would make `codex-land.sh` refuse Codex's next branch for doing what it was asked
— and **all nineteen [[T-3003]] paths stay**, the grant `220b0b91`/`c4eedfcb` published while these
landings were in flight. 23 patterns in, 42 out. These nineteen retire in a follow-through commit
the moment the work lands, in this session, because *a lease granting paths nobody is working on is
a lease that will eventually be believed.*

### LEASE RETIRED 2026-10-05 — the four T-1465 editor paths are out, because the work landed

`36ef5e04` landed the continuous quote rail. `codex-land.sh review codex/continuous-quote-rail` now
reports the four editor sources as already in main, and the two paths it still refuses are the two
the coordinator deliberately resolved differently rather than taking from the branch:
`CadenceTests/CadenceRealTreeSweepManifest.txt`, which is generated and was re-derived after
integrating rather than taken, and this file, whose lease self-grant was declined for the second
branch running. The `CODEX-INBOX-ID-CLASH` on T-1465 that it also prints is the consequence of the
id having been filed in `b802afc5` before the code, not a blocker.

Retired immediately rather than left standing, because the grant below said it would be, and
because this file's own warning is the thing [[T-2069]] and [[T-2058]] are about: *a lease granting
paths nobody is working on is a lease that will eventually be believed.*

**Nothing else was touched.** The four standing globs are unchanged, `CadenceTests/CadenceCodex*.swift`
among them, and **all nineteen [[T-3003]] paths stay** — that grant landed in `220b0b91`/`c4eedfcb`
*while this landing was in flight*, so this retirement was rebuilt on HEAD rather than written from
the copy that was read before it, which would have silently revoked a live lease.

### LEASE WIDENED 2026-10-05 — four editor paths for [[T-1465]], the continuous quote rail

Written by the coordinator (agent `codexquote`) while landing `codex/continuous-quote-rail`, which
is [[T-1465]]. The owner authorized the quote-rail fix and the editor files it needs, and then
asked for the macOS check that found the second defect; Codex asked for the minimum rather than
assuming it, and the request with its scope and verification plan is `docs/CODEX_LEDGER_INBOX.md`'s
T-1465 entry.

**The four paths and why each one.** `Cadence/iOS/iOSMarkdownStylingLineSupport.swift` is where the
mobile styler hides the `>` prefix and tags the paragraph, so it is where a per-paragraph tag
becomes a run that spans its terminator; `Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift` held the
18pt-per-paragraph bitmap that could not follow wrapped text, and is where the range/geometry layer
grouping same-depth runs lands; `Cadence/iOS/iOSMarkdownBlockCanvasRendering.swift` is the drawing
pass that must stroke a vector rail instead of stamping one bitmap per paragraph.
`Cadence/macOS/Editor/MarkdownEditorLayoutManager.swift` is granted **for quote gutter positioning
and full-block range recovery on partial redraw only** — it measured the hidden `>` glyphs as the
block's leading edge and put the rail outside AppKit's text-container clip. Regression tests need no
new grant: they land in `CadenceTests/CadenceCodex*.swift`, Codex's standing reserved namespace.

**`docs/CODEX_WORKTREE.md` is deliberately NOT granted, for the second branch running.** Codex's
branch again adds this file to its own lease block; that hunk is declined again and this record is
written by the coordinator in `main` instead, exactly as the T-1463/T-1464 grant above was. A writer
that holds its own lease file can widen its own lease, and this block's whole value is that one
party decides it. `codex-land.sh review codex/continuous-quote-rail` will keep reporting
`CODEX-LEASE-VIOLATION` on this one path, and that report is correct.

**`CadenceTests/CadenceRealTreeSweepManifest.txt` is NOT granted either**, for a different reason:
it is generated, not authored, and the coordinator regenerates it with
`real-tree-sweep-manifest.sh` *after* integration. The T-1463 grant above kept it outside for the
same reason and the landing was unaffected. Codex's branch carries a manifest line; the coordinator
re-derives it rather than taking it, so the registration is proved by the generator rather than
trusted from the branch.

**Nothing was dropped to make room.** The four standing globs are unchanged, and
`CadenceTests/CadenceCodex*.swift` in particular stays — it is where
`CadenceCodexQuoteRailTests.swift` lands with this very branch, and dropping it would make
`codex-land.sh` refuse Codex's next branch for doing exactly what it was asked to do.

**Retire these four when the assignment lands**, by the rule this file keeps rather than cites: *a
lease granting paths nobody is working on is a lease that will eventually be believed.*

### LEASE RETIRED 2026-10-05 — the seven T-1463 paths are out, because the work landed

`189f7249` landed the sidebar drawer. `codex-land.sh review codex/sidebar-drawer` now answers **8 of
10 files already in main, identical**, and the two it still reports as `NOT in main` are the two the
coordinator deliberately resolved differently rather than taking from the branch:
`CadenceTests/CadenceDesktopSplitLayoutTests.swift`, which was three-way merged so main's [[T-2079]]
hunk survives alongside Codex's width fixtures and is therefore *not* byte-identical to either side,
and this file, whose lease self-grant was declined. The two `CODEX-INBOX-ID-CLASH` refusals it also
prints are the shape this file already documents: an id clash on a branch in this state is a
consequence of the work having landed, not a blocker.

Retired immediately rather than left standing, because the grant below said it would be and because
this file's own warning is the thing [[T-2069]] and [[T-2058]] are about: *a lease granting paths
nobody is working on is a lease that will eventually be believed.* The four standing globs are
untouched, `CadenceTests/CadenceCodex*.swift` among them.

### LEASE WIDENED 2026-10-05 — seven paths for [[T-1463]]/[[T-1464]], the sidebar drawer

Written by the coordinator (agent `codexsidebar`) while landing `codex/sidebar-drawer`, which is
[[T-1464]] implementing [[T-1463]]. The owner granted the T-1463 dependencies directly; Codex asked
for the minimum rather than assuming it, which is the behaviour this file exists to produce, and the
request with its scope and verification plan is `docs/CODEX_LEDGER_INBOX.md`'s T-1463 entry.

**The seven paths and why each one.** `Cadence/macOS/Views/macOSRootShellViews.swift` is where the
Mac default width and the one-time `mainSidebarWidth.reset320.v1` migration live;
`Cadence/Shared/CadenceRootShellLayout.swift` is where the iPad 264pt navigation width and the
865pt docked floor are decided; `Cadence/iOS/iOSRootSidebar.swift` is the drawer itself.
`CadenceTests/CadenceRootShellLayoutTests.swift` and
`CadenceTests/CadenceDesktopSplitLayoutTests.swift` carry the literal pane expectations that a width
change necessarily re-points. `Cadence/Shared/CadenceRegularPaneLayout.swift` is granted **for its
width-rule register comment only**, and `CadenceTests/CadencePaneWidthRuleHomesTests.swift` **for the
per-file declaration inventory only** — the narrow pair Codex itself asked be conditional on the
model gaining a named drawer decision, which it did.

**`docs/CODEX_WORKTREE.md` is deliberately NOT granted.** Codex's branch adds itself to the lease
block; that hunk is declined and this record is written by the coordinator in `main` instead. A
writer that holds its own lease file can widen its own lease, and this block's whole value is that
one party decides it. `codex-land.sh review codex/sidebar-drawer` will therefore keep reporting
`CODEX-LEASE-VIOLATION` on this one path, and that report is correct: the protocol edit arrives
here, through the coordinator, which is what the owner's authorization asked for.

**Nothing was dropped to make room.** The four standing globs are unchanged, and
`CadenceTests/CadenceCodex*.swift` in particular stays — it is Codex's reserved namespace, it is
where `CadenceCodexSidebarDrawerTests.swift` lands with this very branch, and dropping it would make
`codex-land.sh` refuse Codex's next branch for doing exactly what it was asked to do (the rule
[[T-2061]] and [[T-2080]] each had to be read back out of this file).

**Retire these seven when the assignment lands**, by the rule this file keeps rather than cites: *a
lease granting paths nobody is working on is a lease that will eventually be believed.* Primary
ledger, `Cadence.xcodeproj/project.pbxproj`, the compact iPhone shell and the real-tree sweep
manifest remain outside it; the manifest is regenerated by the coordinator after integration.

### LEASE RETRACTED 2026-10-04 — the 16 T-1458 paths are back, because the work landed

`7bdb0c32` landed Codex's T-1458 work: the prepared-query search, the single-pass goal
next-action, the chunk-bounded MCP audit reader and the four widget follow-ups. `codex-land.sh
review codex/search-widget-followups` now answers **`CODEX-BRANCH-ALREADY-LANDED` — all 20 files
already in main, 20 identical, 0 where main moved past**, which is the terminal state a spent
branch is supposed to reach.

So the sixteen production paths granted on 2026-10-04 are retracted and free for any writer.
Retracted rather than left standing because this file's own warning applies: *a lease granting
paths nobody is working on is a lease that will eventually be believed*, and [[T-2069]] is the
precedent — four separate agents were blocked or forced to edit through a fence that was
protecting branches with nothing in them.

**What stays open does NOT need these paths.** [[T-1461]]'s native widget visual checks are device
work, not source edits. [[T-1458]]'s file-extraction half is still deferred and still needs an
owner decision about `project.pbxproj` target registration, not a lease. [[T-1462]], the midnight
habit-intent race, names `Cadence/Services/CadenceWidgetIntents.swift` — a path that was **never in
this grant** and is unchanged by the landing, so it would be a fresh request if Codex picks it up.

The four patterns above are untouched and still live: `iOSList*.swift` and the typography trio
remain [[T-1411]]'s standing assignment, and `CadenceTests/CadenceCodex*.swift` is a namespace
rather than a file -- dropping it would make `codex-land.sh` refuse Codex's next branch for doing
exactly what it was asked.


### LEASE GRANTED 2026-10-04 — 16 paths for T-1458, on `codex/search-widget-followups`

Codex requested the minimum production lease for the owner's search / goal-summary / MCP
audit-log / widget follow-ups, and asked that these be reserved from other writers. The ticket,
with the patch order and the verification plan, is `docs/CODEX_LEDGER_INBOX.md:227`; the worktree
is `/Users/williamwei/.codex/worktrees/9e4a/Cadence`, read at `24c671c4` with 0 dirty files.

**These are additive to the four patterns above, not a reversal of the narrowing.** The narrowing
retired the iOS task-UI fence because every branch behind it was spent ([[T-2069]]); this grant
covers a different subtree that a live branch is actually working on. None of the sixteen was held
by another writer when it was published, and none is in any running agent's scope.

**The file-extraction half is NOT granted and is deferred by agreement.** The owner's sixth
optimization recommendation would split `PersistenceController.swift`'s `StoreBackupManager`
boundary and declarations preceding `CadenceWriteService`. New files must be registered as build
inputs in `Cadence.xcodeproj/project.pbxproj` — which MCP explicitly compiles (`project.pbxproj:690`)
— and that file is not edited while the owner has Xcode open ([[T-117]]). Target registration is an
owner decision, not a lease question. Codex deferred it; the coordinator confirms the deferral.

### LEASE NARROWED 2026-10-04 — 35 patterns to 4, because every Codex branch is spent

**Measured, not read off the branch names.** `./scripts/codex-land.sh review` was run against all
seven `codex/*` branches in this repository on 2026-10-04 at `24c671c4`. **Not one of them has a
single code file that is not already in `main`:**

| branch | `review` verdict | exit |
| --- | --- | --- |
| `codex/archive-typography-20261002` | `CODEX-ONLY-THE-INBOX-IS-UNLANDED` — 30 of 31 files already in main | 3 |
| `codex/calendar-day-drop-commit` | `CODEX-ONLY-THE-INBOX-IS-UNLANDED` — 6 of 7 files already in main | 3 |
| `codex/archive-large-text-20261002` | `CODEX-BRANCH-ALREADY-LANDED` — all 18 files | 5 |
| `codex/context-budget` | `CODEX-BRANCH-ALREADY-LANDED` — all 4 files | 5 |
| `codex/save-report-closure-detector` | `CODEX-BRANCH-ALREADY-LANDED` — all 3 files | 5 |
| `codex/task-page-large-text` | `CODEX-REVIEW-VACUOUS` — 0 commits over main | 4 |
| `codex/task-page-typography-finish` | `CODEX-REVIEW-VACUOUS` — 0 commits over main | 4 |

The Codex worktree at `~/.codex/worktrees/9e4a/Cadence` was read at the same time: `git status` is
**empty**, so no path in this fence was mid-edit. Nothing was reset, deleted or force-pushed; the
branches are left exactly as Codex left them, and the two that still carry unlanded
`docs/CODEX_LEDGER_INBOX.md` entries carry ids the ledger already has formal entries for, which is
the T-1800 shape and not pending work.

**This is the rule in this file being kept rather than cited:** *a lease granting paths nobody is
working on is a lease that will eventually be believed.* It had been believed. [[T-2058]] designed
the three row indicator glyphs and wrote **no code**, on the stated evidence that
`codex/archive-typography-20261002` was "3 commits ahead of `main` and UNLANDED". The commit count
is three; the content is zero. `git log main..<branch>` answers a different question from
`codex-land.sh review`, and only the second one is the lease's question.

**What came back, and why.** Twenty-six paths whose assignment is closed in the inbox
([[T-1440]], [[T-1442]], [[T-1450]], [[T-1454]], [[T-1457]]) and whose branches `review` calls
spent — every converted iOS page surface, every shared component T-1442 closed, the three
context-budget paths, and the guards written for that closed work. Four of them were named by
T-2058 as the thing blocking it: `Cadence/iOS/iOSTaskViews.swift`,
`CadenceTests/CadenceTodayUnificationTests.swift`, `CadenceTests/CadenceSharedTaskRowJobsTests.swift`
and `CadenceTests/CadenceTagChipStyleTests.swift`.

**What stayed, and why — this is the conservative half.** [[T-1411]] is still **PARTIAL** and is
still Codex's standing first assignment under R66; [[T-1453]] says Lists is the one task page not
yet declared. So `Cadence/iOS/iOSList*.swift` stays, and with it the two files any further
conversion must edit: `Cadence/Shared/CadenceTypography.swift`, which is where the roles and the
scaling environment are decided, and `CadenceTests/CadenceTypographyScaleTests.swift`, which carries
the "exactly N declared roots" sweep that this file's own *one converter at a time* rule is about.
`CadenceTests/CadenceCodex*.swift` stays because it is Codex's reserved **namespace**, not a file:
a new conversion writes a new guard there, and dropping the glob would make `codex-land.sh` refuse
Codex's next branch with `CODEX-LEASE-VIOLATION` for doing exactly what it was asked to do.

**One edit was made inside that namespace at the same time, deliberately and under the permission
[[T-2061]] names.** `CadenceTests/CadenceCodexTaskSummaryTypographyTests.swift:74` required
`.cadenceFont(` in `CadenceTaskGroupHeading`, and [[T-2056]] deleted the count capsule that was that
file's only call of it. That is the *re-point, never weaken* case below, T-2061 asked the
coordinator to land it rather than route it to Codex, and `main` had been red on it for a day. The
check is not deleted: the heading keeps every other assertion in the loop and gains the stronger
`SectionEyebrowLabel` source read. **If Codex is mid-edit on that file when it reads this, say so
and the coordinator rebases it — the worktree was clean when this was written.**

**A SECOND edit was made inside that namespace on 2026-10-05, under the same permission and the
same rule ([[T-2080]]).** `CadenceTests/CadenceCodexWidgetFollowupTests.swift:70`'s
`codexWidgetProvidersAndViewsShareFamilyBudgets` walked five widget sources, and [[T-2078]]
(`7b686a76`) deleted two of them — `CadenceWidgets/HabitCheckInWidget.swift` and
`CadenceWidgets/MilestoneMomentumWidget.swift` — when the owner retired Habits and Goals.
`CadenceScanInstrument.sweep` *reads* every path it is handed, so this did not fail an assertion:
it threw `NSCocoaErrorDomain 260` and `main` was red on a missing file. `cutwidgets` saw it, named
it in T-2078's closure and correctly did **not** touch it, because this namespace is Codex's lease.
The coordinator landed it instead, exactly as T-2061 asked for the first one.

**Re-pointed, never weakened, and the index was the trap.** `atLeast:` moved 5 -> 3, re-derived
from the three survivors (`TodayTasksWidget.swift`, `TodayTasksWidgetView.swift`,
`CalendarSnapshotWidget.swift`) rather than relaxed to a floor — a floor would let a *second* widget
stop sharing the family budget unnoticed, which is the whole thing this guard is for. The witness
was `including: paths[2]`, i.e. the habit widget; deleting the two dead entries without re-deriving
it would have silently re-pointed the non-vacuity claim at `CalendarSnapshotWidget.swift` while
still reading like the old check. The witness is now a **named constant**, not an index, so the next
edit to that list cannot repeat it. The habit and milestone assertion blocks lost their subject and
are gone, but not silently: a doc comment on the test names each dead assertion, which widget it
died with, and where its surviving equivalent is asserted — and the one claim that had **no**
surviving assertion at all, the view-side "the family budget reaches the drawn content" half, is
added as a new `TodayTasksWidgetView` block. That file was in the sweep list all along and was never
actually read; the re-point closed that gap rather than just shrinking the array. Mutation-tested:
replacing `widgetFamily.cadenceLayout.todayTaskLimit` with the literal `8` in
`TodayTasksWidgetView.swift:88` compiled and turned the test red; restored from a `cp` backup, green.

**`CadenceWidgetFamilyLayout.habitLimit` / `.habitColumns` / `.milestoneGoalLimit` were NOT
deleted.** After T-2078 their only readers in the tree are the model assertions in
`codexWidgetFamilyBudgetsMatchTheSelectedContent`, one test above — i.e. they are dead to
production. Retiring them is an owner decision about the kept schema, not a side effect of fixing a
red run, and it is recorded in T-2080 rather than done here. **If Codex is mid-edit on
`CadenceCodexWidgetFollowupTests.swift` when it reads this, say so and the coordinator rebases it —
the worktree held no uncommitted change to that file when this was written.**

### The context-budget grant (2026-10-02), and the two things it does not permit

**LEASE ENDED 2026-10-04: [[T-1454]] landed on `main` and `codex/context-budget` reviews as
`CODEX-BRANCH-ALREADY-LANDED` (all four files). `CLAUDE.md`, `scripts/codex-inbox.sh` and
`docs/CODEX_REQUESTS.md` are out of the `lease` block above.** The section below is kept as the
record of what was asked, and its two boundaries still describe what those files are for.

`CLAUDE.md`, `scripts/codex-inbox.sh` and `docs/CODEX_REQUESTS.md` are leased to Codex for the
context-budget work Codex itself scoped. Measured at `74c1d186`: the request document is **306 KB**
with no per-request lookup, and `CLAUDE.md` repeats directory maps, build commands and incident
history that `AGENTS.md` already owns.

Two boundaries, both load-bearing:

**`scripts/codex-inbox.sh` has a selftest and it is a landing gate.** It currently offers
`report | fold R<n> | selftest`. Add `show R<n>`; do not change what `fold` or the id-clash check
mean. The selftest must be green and must gain a case for the new subcommand — a lookup that
silently returns the wrong request is worse than no lookup. `codex-inbox.sh` is `#!/bin/bash`;
`codex-land.sh` is `#!/bin/sh`; do not assume either from the extension.

**`CLAUDE.md` is startup context for every agent, so trimming it is in charter but rewriting it is
not.** Its own rule says: when adding an always-read rule, remove or link out something else. Move
duplicated material to `docs/CLAUDE_REFERENCE.md` or the scoped `AGENTS.md` and leave a link. Do not
remove a safety rule, and do not remove the first-reads ordering. If a line looks redundant but you
cannot find where it is covered, keep it and say so.

**Archiving acted-on requests is permitted only if ids and acknowledgement tracking survive byte for
byte.** The whole point of the inbox is that an id resolves to exactly one entry; an archive that
loses that is a regression, not a saving. Measure the before and after sizes and state both.

**Not granted, and not to be inferred:** `docs/TODO.md`, `AGENTS.md`, `scripts/xcb.sh`,
`scripts/agent-commit.sh`, `scripts/codex-land.sh`, `.github/`. The largest saving in this area —
never reading the 2.4 MB ledger, using `./scripts/ledger-view.sh show`/`brief` instead — is a
coordinator habit that has already been fixed in the agent brief, not a change to any file here.

### T-1980 was leased to Codex (2026-10-02), and it is a FINISH, not a start

**LEASE ENDED 2026-10-02: T-1980 landed on `main`, and its six paths are out of the `lease` block
above.** The section below is kept as the record of what was asked.

Six macOS paths are leased for [[T-1980]] only. This is the first time Codex has held anything under
`Cadence/macOS/Views/`, and the grant is narrow and temporary: it ends when T-1980 lands.

**The implementation already exists and is ~80% done.** Agent `boarddrops` built it and ran out of
budget mid-verification. The work is a patch, not a blank page, and the instruction is **finish and
verify it, do not redesign it**. If Codex believes a design decision is wrong, it says so and stops
rather than rewriting — the decisions were measured, and two of them were measured *against* the
obvious alternative.

**What is already proven:** M1, the headline mutation — both drops restored to the swallowing form
with the `commit:` seam kept — produced **31 issues across 6 tests**, linked and re-signed. The
macOS build is clean at 696 compile tasks, 0 warnings.

**What is missing, and it is the whole job:** M2 (`calendarEventID` dropped from `restore(to:)`,
expected to redden **only** the block-move calendar-link assertions) and M3
(`CadenceTaskBundleSlotSnapshot` dropping `startMin`/`durationMinutes`, expected to redden **only**
the clamp test). These are *attribution* mutations: each must redden exactly one group and leave the
rest green. That is the evidence that proved [[T-1952]] and caught that copying [[T-1580]]'s shape
unaltered would have made it worse. Also missing: a full `-only-testing:CadenceTests` run over final
bytes, and an **iOS build**, which is owed because `Cadence/Shared/CadenceTaskFieldEditCommit.swift`
is touched.

**Two design decisions not to undo.** `CadenceTaskMutationSupport.updateBundle` was deliberately not
reused: it writes `title`, clamps against its own literals, and does not clear members' calendar
links, so reusing it would have changed what the drop does while fixing what it reports. And
`CalendarBoardDayColumn.handleDrop` returned `true` unconditionally because both callbacks were
`Void`; they answer `Bool` now, and the one surviving `return true` is the hit-test deferral to a
bundle card, which is correct.

**`CadenceSaveCommitRule.reportExemptions` is empty (`[:]`) and stays empty.** Fix defects; never
widen or add an exemption.

### `CadenceSaveCommitDisciplineTests.swift` is leased for T-1990 only (2026-10-02)

**LEASE ENDED 2026-10-03: the direct-only detector ([[T-1457]]) landed on `main` from
`codex/save-report-closure-detector`, and this path is out of the `lease` block above.** [[T-1990]]
stays PARTIAL for the stored-callback transport sites; a later grant for them is a new lease.
The section below is kept as the record of what was asked.

Codex asked for this rather than assuming it, which is the behaviour the lease exists to produce.
[[T-1990]] is a change to the **detector**, and `CadenceSaveCommitRule` and its file-private parser
live inside that test file — 118 references — so the ticket is unreachable without it. Granted for
T-1990 only; it ends when T-1990 lands.

**Reserved from other writers while that lease is live.** It was clean and unheld when granted: no
in-flight agent had it, and the only uncommitted paths were `palettecopy`'s four. A coordinator
assigning work that touches this file must check the lease first rather than discovering the clash
at `agent-commit.sh`.

**`reportExemptions` is EMPTY (`[:]`) and stays empty.** [[T-1952]] emptied it by fixing the defect
and [[T-1980]] kept it empty. A detector that makes 47 sites fail and is then made tolerable by
re-populating that list would undo both. If the new rule needs an escape hatch, that is a finding to
file, not a list to refill.

**The trap, which Codex identified itself when filing the ticket:** a structural "a `Void`
declaration may not swallow" rule names **47 of 51** sites in one change, and most are the in-place
field edits the rule deliberately allows. The landable rule is the narrow one — a swallowing
declaration whose only caller is a closure argument whose parameter type returns `Bool`, the
`.dropDestination` shape where the `true` the UI reads is built one frame up in another file.

## The coordinator's side

A lease is a **two-sided** promise and the first draft of this file only wrote one side. Codex's
first assignment reported the gap before writing a line: the lease named paths, but nothing stopped
the coordinator from handing one of those same paths to a subagent an hour later, which is the
collision the worktree was built to remove, re-entering through the coordinator's own door.

So, while a lease is in force:

- **The coordinator does not assign a leased path to a subagent**, and does not edit one itself
  except to land Codex's branch. If something on a leased path needs fixing first, the lease comes
  back before the fix goes out.
- **The coordinator publishes the protocol before assigning work.** Codex branches from
  `origin/main`; a file that exists only in the shared checkout's working tree is a file Codex
  cannot read, cannot run, and is right to refuse to proceed without.
- **Shared test files count as leased paths.** `CadenceTypographyScaleTests` carries the "exactly N
  declared roots" sweep, so *every* typography conversion edits it. Two converters means two writers
  in that one file, which is [[T-1385]] exactly. One converter at a time, and right now that is
  Codex.
- **The coordinator narrows the lease when the assignment ends**, rather than letting it accumulate.
  A lease granting paths nobody is working on is a lease that will eventually be believed.

### The four paths T-1451 asked for, and the two embedded surfaces

**LEASE ENDED 2026-10-04: all four are out of the `lease` block above**, along with
`CadenceTests/CadenceSharedTaskRowJobsTests.swift` and `CadenceTests/CadenceTodayUnificationTests.swift`
— `codex/archive-typography-20261002` reviews with every one of its code files already in `main`.
The section below is kept as the record of what was asked. Its *re-point, never delete or loosen*
direction still binds whoever edits those guards next; it is a property of the guards, not of the
lease.

Three of the four are granted above. The fourth was already granted and Codex could not see it:
`CadenceTests/CadenceSharedTaskRowJobsTests.swift` and `CadenceTests/CadenceTodayUnificationTests.swift`
entered the lease **after** `codex/task-page-typography-finish` branched from `4e6f4feb`, so the
branch's own copy of this file does not list them. Re-point `:675`'s three-read count as T-1451
proposes — the narrow permission in the section above applies to it word for word: re-point, never
delete, loosen or route around, and do not add production reads whose only purpose is to satisfy the
old count. Read the lease from `origin/main`, not from the branch, when in doubt.

`Cadence/Shared/Components/CadenceBoardColumnHeader.swift` is the one grant here that is **not**
iOS-only: `Cadence/macOS/Views/KanbanColumnSupportViews.swift` and the two Calendar views draw it
too. The constraint is the one T-1451 proposed itself — prepare it with fixed-mode preservation and
an explicit caller inventory, and do not opt the macOS or Calendar callers in. There are open
scrolling-performance tickets against the macOS Kanban board; if one of them needs this file, the
lease comes back before that fix goes out, the same way [[T-1492]] took `CadenceDatePicker.swift`.

**Both embedded surfaces: the proposal in T-1451 is accepted.** Today `.timeline` and Lists
`.documents` get explicitly fixed Cadence chrome on the embedding, matching Today's agreed Notes
boundary, and the Calendar and Notes conversions behind them stay separate work. No new lease is
needed for it: `iOSTodayView.swift`, `iOSTodaySchedulePanel.swift`, `iOSListDetailView.swift` and
`iOSListNotesView.swift` all already match `iOSToday*.swift` and `iOSList*.swift`.

`Cadence/Shared/Components/CadenceDatePicker.swift` does **not** return, and the commit that removed
it said it would. It is already a declared scaled root in the inventory at
`CadenceTests/CadenceTypographyScaleTests.swift:422`, and T-1451's own remaining patch order does not
name it, so returning it would grant a path nobody is working on — which this file's own rule says is
the kind of lease that eventually gets believed. It comes back the moment an assignment needs it; say
so rather than working around it.

### The two files loaned for T-1702 have come back — and they came back

The promise this section carried while the loan was in force, kept word for word because it is the
one being discharged:

**They return when T-1702 lands.** [[T-1492]] made the same promise about `CadenceDatePicker.swift`
and I did not keep it; [[T-1800]] records why that was defensible and it is still a promise I broke.

**T-1702 landed as `3d1f5c33` on 2026-09-30, and both files are back in the lease as of 2026-10-01.**
That is this promise kept on its own terms. [[T-1492]]'s is still outstanding and is still recorded
as outstanding in the section above; nothing here discharges it.

What changed under the loan, so Codex is not surprised by the bytes: `iOSFeatureComponents.swift`
gained `CadencePageHeaderEyebrow.ladder(eyebrow:compactEyebrow:detail:)`, three **named** rungs fed to
a `ViewThatFits` on the header line. Two things about that are load-bearing and must not be undone by
a typography pass. First, the budget is not the pane and not the column — it is **what the two chips
on the same row leave behind**, which is why the fix is a ladder and not a width rule in the layout
support. Second, **an `if` inside a `ViewThatFits` builder produces an empty candidate that fits every
width and draws nothing**, and `ViewThatFits` renders its *final* candidate whether it fits or not —
so the rungs are unconditional and ordered deliberately. Re-spelling either property is a change to
the ladder, not to a font.

`iPadTodaySupportViews.swift` is unchanged in substance.

**Open against these two files, and yours now:** [[T-1880]] — `iPadTodayTaskHeader` reads `Date()`
twice for one header, because `iOSTodayView.todayTaskColumn` passes an eyebrow built from one `Date()`
and the header takes another. It was left unfixed precisely because the file was leased. It is a real
two-reads-one-render defect, not a tidy-up: the two reads can straddle midnight.

## Do not edit `Cadence.xcodeproj/project.pbxproj`

`Cadence/` and `CadenceTests/` are `PBXFileSystemSynchronizedRootGroup`s, so a new file under either
is picked up by the app and test targets **with no project-file edit at all**. The explicit entries
still in that file exist only for sources that must also compile into a *second* target — the widget
and the MCP server, which is why `Cadence/Models/*` appears there by hand.

Nothing in the typography work needs a second target. If Codex ever believes a new file does, that
is the moment to stop and say so, because `project.pbxproj` is the single highest-collision file in
the repository and a merge there is not reviewable.

### A leased guard may be re-pointed, never weakened

**`CadenceTests/CadenceSharedBoardChromeTests.swift` left the `lease` block on 2026-10-04**, and
this rule did not leave with it. It is why the two [[T-2061]] re-points landed as re-points: a guard
whose subject moved is pointed at where the subject went, never deleted, loosened, or routed around,
and the assertions bracketing it that stop it going vacuous stay.

`CadenceTests/CadenceSharedBoardChromeTests.swift` is leased because converting
`CadenceTodayOverdueSummaryCards.swift` invalidates a source-substring assertion in it
(`:671`, `size: SectionEyebrowLabel.fontSize`), and the converter is the only party who knows what
the call becomes. A guard edited at landing by someone reading a diff is a guard being rubber-stamped.

The permission is narrow and it is a direction, not a budget. Re-point the assertion at the new
call. Do **not** delete it, loosen it to a weaker predicate, or route around it — and keep the two
assertions bracketing it, which are what stop it going vacuous: the non-vacuity check that the file
is still the heading's file, and the negative control that an 11pt eyebrow tier has not come back.
Note also that the three checks above them (`SectionEyebrowLabel.fontSize == 10` and the two
`countSize ==` identities) are **model** assertions, not source reads, and a conversion should leave
them alone.

### A new test that reads the real product tree is not green until the manifest is regenerated

`CadenceTests/CadenceRealTreeSweepManifest.txt` is the exact list of every `@Test` that sweeps the
real product tree, and two suites compare the committed file against a fresh derivation:
`CadenceTestTargetHygieneTests.theRealTreeSweepManifestIsExactlyWhatTheScanFinds` and
`CadenceGuardScriptSelftestTests.theCheapPrecheckStillAnswersWhatTheAuthoritativeScanAnswers`. A new
sweep that is not listed fails both, and neither is reachable from a scoped run of the suites a
ticket touches — which is how `codexChipAndInspectorReadTheOneLineHeightRatio` arrived at landing
with a cold green, a 193-test run and a named known red, and still reddened the full suite.

**Codex does not regenerate the manifest and the file is not leased.** Every writer in the repository
adds sweeps, the file is derived rather than typed, and a branch that regenerates it conflicts with a
main that also did. Instead: **say in the inbox entry that the ticket adds a real-tree sweep, and
name the tests.** The coordinator runs `scripts/real-tree-sweep-manifest.sh <id> --write` at landing,
where it is one derivation against one tree.

So those two suites being red on the branch is expected when a sweep was added, and is not something
to chase. Every *other* red still is.

## What Codex must not do

- **Never edit `docs/TODO.md` or `docs/TODO_DONE.md`.** Use the inbox.
- **Never force-push, rebase a shared branch, or rewrite history.**
- **Never push to `main`.** Only `codex/<topic>` branches.
- **Never run `scripts/agent-commit.sh --commits-stale`,** or "repair a stale base".
- **Never touch a path outside the lease**, even to fix something obviously broken — say so instead.
- **Never point a test at `~/Library/Containers/com.haoranwei.Cadence/Data/`**, the real app group,
  or the owner's iCloud container.
- **Never kill a process merely named `Cadence`** — the owner runs `/Applications/Cadence.app` and
  an Xcode debug build. Terminate only pids Codex launched.
- **Never erase, boot or shut down a simulator it did not create.**

## What Codex must do

- Build and test through `./scripts/xcb.sh <id> …` with `-scheme` and `-destination`, never a bare
  `xcodebuild`. `-only-testing:` takes `CadenceTests/<SuiteName>` — a **filename runs zero tests and
  exits 0**, and so does a nonexistent suite. Verify names against `./scripts/test-suite-index.sh`.
- Read the real `XCODEBUILD_EXIT=` line from the result block, never `$?` after a pipe, and check
  `swift compile tasks:` is non-vacuous — a warm run printing `VACUOUS-COUNT` carries no evidence.
- Hold the warning baseline at **zero**.
- Write one inbox entry per ticket it closes or files, in the ledger's own shape: the id, a bold
  one-line headline, and the measurement. A closure is written **as** a closure
  (`**CLOSED <date> (codex) — …`), not described as one ([[T-1335]]).
- Use only ids from the range the coordinator reserved for it, recorded at the top of the inbox.

### LEASE WIDENED 2026-10-05 — eighteen paths for [[T-3003]], Codex's four audit findings

Granted by the coordinator at the owner's explicit instruction, relayed in chat: *"please grant it
permission"*. Codex asked for this batch **before** making any production edit, which is the order
this protocol wants and the opposite of the T-1458 case where the work was blocked at handoff.

**Scope, as Codex stated it: the four audit findings only — no schema, project-file or manifest
edits.** The coordinator has NOT seen the four findings; no inbox entry existed for them when this
grant was written, so the scope recorded here is Codex's own words and not an independent reading
of it. Codex files the T-3003 inbox entry naming the four findings; if that entry turns out to need
a path outside this list, ask rather than widen.

**Checked before granting, not assumed.** The eighteen paths were diffed against both landings in
flight: zero overlap with `codex/tracking-ui-retirement` ([[T-1466]], queued), and no overlap with
the live edit set of `codex/continuous-quote-rail` ([[T-1465]], mid-landing). `CadenceCodex*` tests
and `docs/CODEX_LEDGER_INBOX.md` were already allowed and are not re-listed.

**This block is wide — eighteen production paths including `PersistenceController.swift`,
both `CalendarManager`s and `TaskWorkflowService.swift` — so it is a reservation against a
coordinator agent touching them, not only a permission for Codex.** Three of them were edited today
(`CadenceWidgetRefreshCenter.swift`, `CadenceTodayWidgetSupport.swift`,
`TaskWorkflowService.swift`) by the habits/goals retirement, so a branch based before `b802afc5`
will need a merge-base check at landing rather than a take-theirs.

**Retire it when T-3003 lands**, in the same session that lands it, as [[T-1464]]'s seven paths were
retired by `387ebca1` and the four quote paths are owed the same.

### LEASE WIDENED 2026-10-05 — one test file for [[T-3003]], and ONE assertion inside it

Granted at the owner's instruction, relayed in chat. `Cadence/macOS/Services/TaskCompletionAnimationManager.swift`
was already in the T-3003 block; this is its test half, and without it the widget fix cannot land
the reopen it needs.

**The single permitted edit.** `CadenceTests/CadenceTaskStatusLifecycleSurfaceTests.swift:759`
currently reads `expectOccurrences(of: "TaskWorkflowService.markTodo(task)", at: [path: 1])`.
It may become the committed spelling, `TaskWorkflowService.commitMarkTodo(task, in: $0)`, at 1.
**Nothing else in that test may move**: the surrounding transition counts, the direct-assignment
negatives, the funnel counts (`private func write(`, `write(.restored, to: task)` and its pair) and
the non-vacuity controls at the end all stay exactly as they are.

**One condition the request did not state, and it is required.** Two lines above, `markDone` and
`markCancelled` have already made this exact move, and each left its UNCOMMITTED spelling pinned at
zero — `expectOccurrences(of: "TaskWorkflowService.markDone(", at: [path: 0])` — so the old call
cannot come back beside the new one. `markTodo` must gain the same zero-pin
(`"TaskWorkflowService.markTodo("` at 0) in the same edit. Re-pointing the 1 without adding the 0
would leave `markTodo` the only one of the three transitions whose uncommitted spelling is
unguarded, which is a weakening wearing the shape of a re-point.

**Retire this path with the other eighteen** when T-3003 lands.

### LEASE WIDENED 2026-10-05 — a second test file for [[T-3003]], and ONE entry inside it

Granted at the owner's instruction. `Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift` was
already in the T-3003 block; this is its test half, the same shape as the
`CadenceTaskStatusLifecycleSurfaceTests.swift` grant above.

**The single permitted edit.** In `CadenceTests/CadenceEditorSaveCommitSurfaceTests.swift`, the one
`SaveSurface` entry whose `path` is `Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift` and
whose `function` is `commit` may change its `successSpellings` from `["onChanged()"]` to
`["finishCommittedEdit()"]`. **Nothing else moves**: that entry keeps its commit-before-report
ordering check and its one-refresh count, and every other editor entry, every failure and
dismissal control, and the surrounding inventory stay exactly as they are.

**The condition this grant rests on.** Moving the pinned spelling to `finishCommittedEdit()` puts
the ordering guarantee behind an indirection: the entry would then prove the popover calls the
finisher, not that the user is told once after the commit lands. Codex states its new coverage pins
both committing callers and the finisher's single `onChanged()`. **The re-point is granted only
with that coverage in the same change** — without it this is a weakening wearing the shape of a
re-point, which is the same trap the lifecycle grant above names.

**Retire this path with the rest of T-3003's** when the ticket lands.

### LEASE WIDENED 2026-10-05 — the save-commit discipline suite for [[T-3003]], FOUR exemption entries only

Granted at the owner's instruction. All four production files this touches were already in the
T-3003 block; these are the exemptions that named them.

**The four permitted removals, verified present before granting.**
`CadenceSaveCommitRule.existenceExemptions` — `toggleEmbeddedTask` under
`Cadence/macOS/Views/ListNotesSupportViews.swift` (`:1896`), `NoteEditorPane.swift` (`:1897`) and
`NotePanel.swift` (`:1898`); and `CadenceSaveCommitRule.commitReachExemptions` — `setStatus` under
`Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift` (`:2096`).

**Everything else holds.** The detector itself, every other exemption entry, the six `allowed:`
call sites, and — named because it is what makes this safe — the **"Exemptions rot" guard at
`:1748`**, which is the thing that would fail if one of these four were still needed. That guard is
the evidence for a removal here; weakening or re-pointing it would remove the only check that an
exemption deletion is honest. `reportExemptions` stays **EMPTY**.

**Removing a stale exemption is strengthening, not weakening** — it is the opposite of the trap the
two grants above name. An exemption is a hole in the detector; closing four of them means four more
call sites are now policed. That is why this one carries no further condition.

**Retire this path with the rest of T-3003's** when the ticket lands.

### LEASE WIDENED 2026-10-06 — one path for [[T-3004]], macOS task-row virtualization

Granted at the owner's instruction. **One production path**, because Codex checked and said so:
`TasksListSectionView.swift` **does not exist**. `TasksListSectionView` is declared inside
`Cadence/macOS/Views/TasksListView.swift` at `:506`, and the Completed section is in the same file,
so the whole of [[T-3004]]'s production surface is that one file. Verified here before granting —
the earlier performance report cited a `TasksListSectionView.swift:530` that is not a real path.

**What the ticket is.** `TasksListView.swift:270` opens a `LazyVStack`, but `TasksListSectionView`
draws an **eager** `VStack` at `:526` with `ForEach(section.tasks)` at `:559`, and a second eager
`VStack` at `:588`. An eager stack inside a lazy one defeats the lazy one: every row body in every
expanded section is built whether or not it is on screen. The owner's Unscheduled group holds 88
tasks.

**This is corroborated, not just profiled.** [[T-2057]] measured the same shape on iOS: an eager
row stack cost **4,005 row bodies and ~11s of main thread** for one tap where a `LazyVStack` cost
**9**. That measurement is why item 1 of the performance report proceeds without waiting for the
owner's trackpad baseline, while items 2-5 wait for it.

**Regression tests go in `CadenceTests/CadenceCodex*.swift`**, already a standing glob, and the
handoff in `docs/CODEX_LEDGER_INBOX.md`, always allowed. Neither is re-listed.

**Kanban sorting is deliberately NOT in scope** — Codex asked to leave it out because it needs a
separate production path and is not free. Agreed; it was already the item its own report called a
cleanup rather than the explanation.

**What must survive, and a lazy stack is exactly what threatens it:** collapse state, drag and
drop, frozen ordering, and deep-link behaviour. A lazy stack changes *when* row bodies are built,
so anything relying on an off-screen row having been constructed fails silently rather than loudly.

**Retire this path when T-3004 lands.**

### LEASE WIDENED 2026-10-06 — three Kanban paths for [[T-3005]], one batched rendering branch

Granted at the owner's instruction. Codex asked for exactly these three and asked for the ticket id
to be assigned by the coordinator; both are here. [[T-3004]] landed as `db37c9c6` and needs no
further action.

**Scope, as Codex proposed it:** bound the mounting of horizontally offscreen list columns, bound
the mounting of vertically offscreen cards, and derive the natural/frozen display ordering once per
list-column render instead of reaching through four separate paths.

**THE SHARED-CONSUMER HAZARD, AND IT IS WIDER THAN THE REQUEST SAYS.** Codex flagged that
`KanbanColumnScroll` serves list columns, section columns, Calendar Board day columns and Calendar
Board rails. Measured here before granting, it has **six** consumers, and only two are inside this
grant:

- `Cadence/macOS/Views/KanbanColumnSupportViews.swift` — **granted**
- `Cadence/macOS/Views/KanbanListColumnView.swift` — **granted**
- `Cadence/macOS/Views/KanbanSectionColumnView.swift` — **NOT granted**
- `Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift` — **NOT granted**
- `Cadence/macOS/Views/CalendarBoardRailSupportViews.swift` — **NOT granted**
- `Cadence/iOS/iOSListSupportViews.swift` — already covered by the standing `Cadence/iOS/iOSList*.swift` glob

So a change to `KanbanColumnScroll` itself reaches **four** surfaces this branch may not edit, one
of them on iOS and one of them the Calendar Board. If the work requires touching any ungranted
consumer, that is a new request, not a widening — stop and ask. The behaviours Codex named must
survive on **every** consumer, not only Kanban: empty-space drops, minimum-height geometry,
composer placement, stable IDs, hover cleanup, frozen ordering, and the drop path's unfrozen custom
ordering unchanged.

**THE BASELINE QUESTION, ANSWERED: the owner's known-revision fullscreen physical-trackpad capture
does NOT exist and is not being produced.** The owner was asked for it and chose to move on. Codex
correctly refused to treat [[T-3004]]'s result as proof for Kanban, and asked for explicit
authorization instead.

**Authorized: a counted-mounting / comparator experiment before production changes.** Count what is
mounted, compare bounded against eager, and report the counts. That is the same evidence class that
carried [[T-2057]] — 4,005 row bodies against 9 — and it is measurement rather than a frame-rate
claim. **No trackpad-FPS improvement may be claimed from hosted row counts or accessibility
paging**, which is Codex's own stated limit and is adopted here as a condition of the grant.

**Out of scope, deliberately:** calendar snapping, header payload work, persistence debouncing, and
the undiagnosed sidebar scrolling. Those remain blocked on the baseline that does not exist.

**Retire these three paths when T-3005 lands.**

### LEASE WIDENED 2026-10-07 — the Dynamic Type cluster and [[T-3011]], ten paths

Granted at the owner's instruction, who asked for Codex to be given more work and the lease to go
with it. **No new ticket ids** — every id below already has a formal ledger entry, so Codex writes
its inbox entries under them and the coordinator folds each in at landing.

**The Dynamic Type cluster: [[T-1364]], [[T-1398]], [[T-1399]], [[T-1400]], [[T-1410]], [[T-1411]],
[[T-1414]].** This batch is Codex's for a structural reason rather than a scheduling one — the two
files the whole cluster turns on, `Cadence/Shared/CadenceTypography.swift` and
`CadenceTests/CadenceTypographyScaleTests.swift`, are already standing globs in this lease, so no
coordinator agent can touch the work at all. The eight new paths are the conversion targets the
tickets name:

- `Cadence/Shared/Components/CadenceChoicePicker.swift` and `Cadence/iOS/iOSChoicePicker.swift` —
  [[T-1410]]'s panels. Two of four are converted end to end and two stay pinned **deliberately**:
  [[T-1364]]'s rule is *convert a panel completely or leave it pinned*, and the two answers
  differing is that ticket's finding, not an inconsistency to tidy away.
- `Cadence/Shared/Components/CadenceTagChip.swift` — [[T-1414]]'s second line-height ratio.
  `CadenceTypeScale.lineHeightRatio` is 1.2 and `CadenceTagChipStyle.chipHeight(hasRemoveControl:)`
  uses its own 1.25; T-1364 states the ratio once precisely so every height computed from a font
  size reads one number.
- `Cadence/macOS/Views/SettingsAppearanceSection.swift` and `Cadence/CadenceApp.swift` — [[T-1399]],
  which was **EVALUATED and deliberately not built**: the costing found the plan wanting. Re-cost it
  before implementing rather than treating the ticket as a backlog item.
- `Cadence/iOS/iOSTaskViews.swift`, `iOSTaskRowActionViews.swift`, `iOSTaskGroupSection.swift` —
  [[T-1411]], whose constraint is the sentence to read first: **a task row is not a conversion unit,
  the page is.**

[[T-1400]] (the two markdown editors) is in the batch but its paths are **NOT granted yet** — the
macOS side is seven `Cadence/macOS/Editor/*.swift` files and the iOS side several more, and a
blanket grant there would be wider than anything measured. Ask for the specific files once the plan
names them.

**[[T-3011]] — `Cadence/Shared/CadenceCapturePaletteSupport.swift`,
`Cadence/iOS/iOSCaptureRadialMenu.swift`.** [[T-3008]] landed `ee9aad1d` today: `onDisappear` now
clears **liveness only**, because the logged pop order showed frames are republished *before*
`onDisappear` fires, so an `onAppear` re-publish would be undone by the event it exists to survive.
The deliberate cost is T-3011: a genuinely destroyed target keeps its frame for the life of the
process. **Every eviction rule considered reintroduced T-3008 somewhere** — a count bound evicts an
index's entries behind a long scroll in a pushed detail; a time bound evicts them behind a
backgrounded app. The ticket names the shape that is probably right: a reference-type `@State` whose
`deinit` unregisters, which is a destruction signal SwiftUI can actually give. **Do not weaken
T-3008's guarantee to satisfy T-3011** — `CadenceNewTaskDropRegistrationTests` replays the measured
pop order and is the control.

**Retire all ten when the work lands.** Ask before touching any path not listed; a path outside the
grant is a new request, not a widening.

### LEASE WIDENED 2026-10-07 (second grant) — [[T-168]]'s iOS Focus mode, three paths

Granted at the owner's instruction, alongside two assignments that need **no new paths at all**.

**[[T-2054]] needs nothing granted — its one remaining path is already leased.** The ticket is
PARTIAL on exactly one sentence: `iOSListEditorMode.newProject` has a single call site, so the drop
that opens `.newArea` cannot replace the Lists row without deleting the only way to make a
**project** on iPad. The remedy is the Area/Project toggle in `Cadence/iOS/iOSListEditorViews.swift`,
which matches the standing `Cadence/iOS/iOSList*.swift` glob. Agent `dropinherit` stopped there
rather than edit a leased file, which is why this is Codex's to finish. The three layers below it
are already **driven, not argued** — a real drag made a task whose stored container is the dropped
list, verified in SQLite.

**[[T-122]] needs nothing granted YET, and that is deliberate.** Rechecked 2026-08-30: *do not
flip*, and the reason is measured on both platforms — a macOS Swift 6 build costs **10 warnings
across 6 files** against a zero-warning baseline, so it fails on its own merits before iOS is even
considered. The useful work is to **name those 6 files and clear the 10 warnings**, which turns a
blocked flip into a decidable one. Measure first and request the six paths by name; a blanket grant
over whatever Swift 6 complains about would be wider than anything measured.

**[[T-168]] — iOS Focus mode: widgets and a landscape timer.** The entry is two words long ("Two
halves"), so the scoping is Codex's and should be stated in the inbox entry before implementation.
Granted:
- `Cadence/iOS/iOSFocusView.swift` — the landscape timer half.
- `Cadence/Shared/CadenceFocusPlanningSupport.swift` — the shared planning surface both halves read.
- `CadenceWidgets/CadenceWidgetsBundle.swift` — a widget is only registered by appearing in the
  bundle body; that file **is** the registration.

**New files under `CadenceWidgets/` need no project edit** — it is a
`PBXFileSystemSynchronizedRootGroup` and self-registers, confirmed by [[T-2078]] and
[[T-2083]]. Do **not** add files to `Cadence/Services/` for widget use: those are explicit
`PBXFileReference`s and would need a `project.pbxproj` edit, which [[T-117]] forbids while the
owner's Xcode is open.

**What the widget half must not repeat.** [[T-2078]] retired two widgets and the thing that would
have survived deleting the views was the **AppIntent**, not the view — an intent is extracted into
AppIntents metadata from the *compiled target*, so it keeps appearing in Shortcuts with no app
surface behind it. If a Focus widget ships an intent, it owns that intent's whole lifecycle.
Also: `CadenceWidgetGenerationLedger.instrumentedKinds` keeps retired kinds on purpose, because it
is the list `clearStoredState` sweeps — adding a kind means adding it there too.

**Retire these three when T-168 lands.** T-2054's and T-122's retirements belong to their own
grants. Ask before touching any path not listed.


## T-3031 — the Reminders launch gate needs its own exit, and the guard that forbids one

**`CadenceTests/CadenceInboxRemindersSurfaceTests.swift` — GRANTED, narrowly, for
`requestAccessAnswersFalseOnlyThroughItsOneRefusal` at `:515-533` and nothing else in the file.**

Codex found this before writing a line of it, and the finding is correct at source. The test pins
`requestAccess()` to **zero** bare `return false` and **exactly two** `refuse(recordingDenial:)`
calls. T-3031's disarmed exit has to answer `false`, so it reddens the first check as a bare return
and the second check as a third refusal. There is no third way to write it. The guard is doing its
job; it was written before a non-denial exit existed.

**The exit is not a denial and must not be recorded as one.** `refuse(recordingDenial:)` is the
*bookkeeping* path — it exists because a user said no at the TCC prompt. A process that is disarmed
by `CadenceEventKitLaunchGate.isDisarmedForThisProcess` never reached TCC and the user never
answered. Routing it through `refuse` would write a denial the user did not make, and that denial
outlives the process in the surface state. So the shape is a **third, separately named exit**, not a
third refusal and not a `recordingDenial: false` argument.

**On "I won't hide the exit in another helper to evade the guard" — right instinct, and the grant
asks for the opposite of hiding.** The comment above the test says the bookkeeping "cannot be
skipped by adding one [bare return]", and a helper whose only purpose is to launder a bare return
out of the scanned body is exactly that evasion. A helper that is *named for what it does* and
*separately pinned by count* is not: it converts an unnamed hole into a counted, named exit that a
fourth one cannot slip past. The test must be able to tell the two apart by reading the source, which
is the whole premise of this suite.

**What the edit must preserve.** Both existing authorization-refusal checks stay, with their
numbers unchanged — bare `return false` stays at **0**, `refuse(recordingDenial:` stays at **2** —
and both non-vacuity controls stay: the `RemindersAccessRequestPlan.forStatus(` requirement and the
`!body.contains("status == .notDetermined")` guard against a hand-written pre-prompt exit. The new
assertions are additive: the disarmed exit appears **exactly once**, by name, and its own body
records no denial and opens no `EKEventStore`. Update the doc comment above the test so it describes
three exits and says which one is not a refusal — a stale comment over a changed count is how the
next reader gets this wrong.

**Not granted, and not needed:** `Cadence/Services/CadenceEventKitLaunchGate.swift`. The gate side
is already complete — `isDisarmedForThisProcess` is at `:60-62` and the file's own doc already names
`RemindersManager` as the uncovered surface. Anything added there would be dead code.

**Everything else in `CadenceInboxRemindersSurfaceTests.swift` is out of scope.** The
`RemindersConnectionState.resolve` tests above `:515` and every other suite in the file are untouched
by this grant.

### T-3031, second guard in the same file — `theManagerReadsRestrictedLiveWithNoSessionFold` at `:316-330`

**GRANTED, additively, on top of the `:515-533` grant above. The file's scope is now those two
tests and nothing else in it.**

Codex measured this one on a compiling run rather than predicting it, and it is real. The assertion
at `:323` is a regular expression whose `\{\s*EKEventStore` requires `isRestricted`'s getter body to
**open immediately** with the live read. A disarm guard ahead of that read is not a different
spelling of the same shape — it is a different shape, and the regex correctly stops matching. The
guard was written when the only thing that could precede the read was nothing.

**What the edit must preserve, and why each piece is load-bearing:**

- **The live comparison itself stays byte-identical.** `EKEventStore.authorizationStatus(for: .reminder) == .restricted` is the whole point of the test: a restriction is device policy, and the manager must read it live rather than cache it. The grant moves what may come *before* that expression, never the expression.
- **The non-vacuity control stays.** `#expect(source.contains("var isRestricted: Bool"))` at `:321` is what stops the regex assertion passing because the property was deleted. Keep it.
- **`deniedInThisSession` is PROHIBITED in this getter, explicitly.** This is the sharpest part of Codex's request and it is right. The doc comment's argument is that `.restricted` has nothing for a session record to have an opinion about — unlike `isDenied`, which deliberately folds one in. A disarm guard is a new early-exit in a getter that previously had none, and the next reader's obvious move is to fold session state into it. Pin the absence now, while the reason is still written down directly above.
- **The disarm exit answers `false`, not `true`.** A disarmed process is not restricted; it simply never asked. Returning `true` would make the UI assert a device policy that may not exist.

**And the flags must stay coherent with each other under disarm.** `theManagerFoldsAllThreeFlagsIntoTheOneConnectionState` at `:338-348` is **NOT granted and must stay green unedited**: it pins `connectionState` to resolve from all three of `isAuthorized` / `isDenied` / `isRestricted`. If disarm drives all three to `false`, the fold must still land on the state that honestly describes a process that never reached TCC — not on anything that reads as authorized. If making that true requires touching the fold or the resolver, **stop and ask**; that is a product-behaviour question about what a disarmed launch shows the user, and it is not inside this grant.

**Update the doc comment above the test.** It currently says the manager "exposes the live status
directly, with no session fold". After the change that is true of the *comparison* but no longer of
the *getter*, which now has a gate in front of it. Say so, and say that the gate is a process-level
disarm and not a session record — same reason as the `:515-533` grant: a stale comment over a changed
shape is how the next reader gets this wrong.

**Still not granted:** `Cadence/Services/CadenceEventKitLaunchGate.swift` (complete already), and
every other suite and test in `CadenceInboxRemindersSurfaceTests.swift` — including the
`RemindersConnectionState.resolve` tests and the task-group-header tests above `:313`, which share
the file and have nothing to do with T-3031.

### T-3086 Mac half — one more test path, because the sweep that proves the reuse is scoped to iOS

**`CadenceTests/CadenceSharedConstantReuseSweepTests.swift` — GRANTED, narrowly, for
`CadenceNotesTabVocabularyReuseTests.theNotesTabPhrasesAreTypedOnceAndOnlyInTheSharedVocabulary`
and nothing else in the file.**

The shared type landed at `db2f214d` (`CadenceNotesTabVocabulary`, in
`Cadence/Shared/CadenceNotePlanningSupport.swift:57`). The reuse test that proves the four phrases
are typed once currently walks `Cadence/iOS` only, because when it was written the Mac was still on
the far side of the fence. Routing `NotesView.swift` through the shared type without widening that
walk would land the Mac half with **no guard against it drifting straight back** — the walk would
keep passing while `NotesView.swift` re-typed all four phrases by hand. Widen the root set to
include `Cadence/macOS`.

**The rest of the file is out of scope.** It hosts the general shared-constant sweep, whose harvest
reads `static let` / `func` / `var` declarations; these three readings are *instance* properties, so
that sweep walks past them and `CadenceNotesTabVocabularyReuseTests` exists beside it rather than
inside it. Do not fold one into the other and do not change the general sweep's harvest — that is a
much wider blast radius than this ticket, and the agent that landed the mobile half deliberately
left it alone.

**Keep the non-vacuity control.** A walk that is widened to a second root must still prove it read
that root — a scanned-file floor, or an assertion that the Mac's own file was seen. A sweep that
silently finds zero files in `Cadence/macOS` passes for the wrong reason and is worse than not
widening it.

**No rendered Mac string may change.** The vocabulary was built from the Mac's own words — tab strip
and column headings alike — so this is a de-duplication, not a copy change. `NotesPage.title` →
`label`, the four `NotesListHeader(title:)` calls → `columnTitle`.

**Do not reach for `usesFullLabels(isRegularWidth:headerWidth:)` on the Mac.** It exists for the
mobile fork, where Today's Notes inspector is regular width but bottoms out at 320pt. The Mac has
the room and uses `label` unconditionally.

**`NoteKind.meeting`'s raw value is persisted in `Note.kindRaw` and the shared type does not touch
it.** Keep it that way: the display vocabulary must not reach the persisted one.
