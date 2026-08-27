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

## Where findings come from

This file is authoritative. Two other documents hold *findings*, not tracked work:

- [`refactor-phases-4-6.md`](refactor-phases-4-6.md) — 153 findings from a read-only audit at
  `249b475`, **two weeks stale**. A good hunting ground; verify each finding against current code
  before filing it, because several have been overtaken.
- [`TODO_DONE.md`](TODO_DONE.md) — everything shipped, with SHAs. **Search it before filing**;
  tickets have been re-reported here more than once.

## Open — decided, not started

- [T-375] **A completed task's deep link lands on All Tasks without opening the task, and the
  macOS destination→sidebar mapping has an unpinned `?? .today` fallback.** Residue from [[T-368]],
  filed rather than folded into it. (a) T-368 killed the lingering-arm bug — the dangerous half —
  but tapping a widget link for a task you finished elsewhere still does not *show* you that task;
  All Tasks keeps completed rows behind a collapsed toggle. Deciding to auto-expand or auto-select
  there is a product call, not a bug fix. (b) `macOSRootView` now maps a resolved destination
  through `SidebarStaticDestination.allCases.first { $0.feature == destination } ?? .today`. That
  is correct today — every destination `resolvedDestination` can return is in that table, and
  `allTasks` is a case — but nothing pins it, so a future resolver returning `.notes` or `.inbox`
  would silently route to Today with the suite green.

- [T-358] **Section state is one JSON blob, so two devices editing different sections clobber each
  other.** CloudKit audit (Codex, 2026-08-27); shape measured, cross-device outcome inferred.
  `Area.sectionConfigsRaw` (and Project's) holds the whole section array as one string, and ~20 call
  sites read the array, change one section, and write the array back. The iOS list editor snapshots
  configs on appear and writes the snapshot on save, so a Mac-side edit to a *different* section is
  overwritten with no per-section merge point. `TaskSectionConfig` already has a stable `uuid`; the
  identity exists and persistence throws it away. Fix: one merge helper that reloads by `uuid` before
  save and applies only changed fields. Keep `sectionNamesRaw` compatibility.

- [T-359] **Two devices can create two `HabitCompletion` rows for the same habit and the same day, and
  the count sums both.** Extends [[T-328]] — that ticket says the repair service cannot *see*
  `HabitCompletion`; this says what it would need to repair. Measured: four files construct
  `HabitCompletion(` with an insert-if-none-exists toggle —
  `CadenceFocusPlanningSupport`, `CadenceWidgetIntents`, `CadenceWidgetRefreshCenter`,
  `HabitsView`. Different UUIDs means both rows survive sync, and `completionCountsByDate()` adds
  them, so one real check-in can satisfy a `targetCount` or `.timesPerWeek` habit. Decide collapse
  semantics (`max` vs `sum`) before writing the repair.

- [T-360] **Duplicate-tag merge keeps the newer timestamp and throws away the newer colour — and the
  guard that was supposed to prevent that is unreachable.** Sharper than filed. `TagSupport.swift:273`
  copies `colorHex` only `if target.colorHex...isEmpty`, but `Tag.colorHex` defaults to `"#6b7a99"`
  and is never empty for an app-created tag, so the branch is **dead code**. Line 279 then sets
  `updatedAt = max(target, source)`. Net: the surviving tag **advertises the newer timestamp while
  carrying the older colour** — it lies about its own freshness, which is worse than losing the
  colour, because nothing downstream can detect the loss. Note the trap for whoever fixes it: the
  `desc` branch three lines above has the *identical* shape and **is** live, because `desc` really
  can be empty. Two branches that look the same, one works.

- [T-361] **Turning reminders off cancels nothing until a scene-phase sweep.** Notification audit;
  measured. `NotificationManager.reconcile` correctly calls `cancelAll()` when disabled — but
  **zero** `onChange(of: notificationsEnabled)` handlers exist on either platform, so the toggle
  writes `UserDefaults` and stops. Pending OS notifications survive until the app next backgrounds.
  A reminder can fire after the user just turned reminders off, which reads as the setting not
  working. Fix is small: react to the toggle on both platforms — cancel on false, reconcile on true.

- [T-362] **Eleven macOS/iOS surfaces change a task's date or time without reconciling
  notifications.** Extends [[T-343]] (iOS *status* paths); this is the *date/time* half. Measured
  source, inferred staleness. Move a task from 9am to 3pm and the 9am notification stays pending
  until a lifecycle checkpoint. The create sheets on both platforms and `iOSTaskDetailSheet.applyDates()`
  already do this correctly — copy them. Wrap save+reconcile app-side; do **not** push it into the
  shared helpers that widgets and MCP call without reviewing that boundary.

- [T-363] **An out-of-range `reminderMinuteOfDay` schedules a daily reminder at whatever time
  reconcile happened to run.** Measured by probe: `Calendar.date(bySettingHour:minute:second:of:)`
  returns `nil` for -15, 1440 and 1500, and `NotificationScheduling.swift:190` ends `?? now`. Not
  reachable from the picker; reachable from existing or imported data. `Habit.swift` already
  documents that the model does no range validation. Guard `0...1439` in the planner and return
  `nil`.

- [T-364] **Task-creation surfaces that report success still bypass the rollback API.** Undo audit;
  measured. `TaskCreationService` itself says success-reporting surfaces should prefer
  `createTask(from:into:)`, and `CreateTaskSheet`, `InlineTaskComposerView`, and four
  note/markdown embed paths do not — they insert, swallow or skip the save, then dismiss, clear the
  composer, or refresh the embed. `iOSCreateTaskSheet` is the pattern to copy: it catches, keeps the
  sheet open, and reconciles only after the commit lands. Related: [[T-321]], [[T-322]].

- [T-365] **Ordinary task deletes swallow the final save failure and return `true`.** Extends
  [[T-322]] with the highest-risk single site. `CadenceTaskMutationSupport` documents why ordinary
  deletes must commit immediately, then does `try? modelContext.save()`, cancels notifications, and
  reports success — so macOS and iOS row deletes cannot tell a failed delete from a real one, and
  no rollback runs. `CadencePendingChangePersistence.commitDelete` already rolls back on throw and
  is already tested. Route through it and let the failure be visible.

- [T-366] **The embed field popover calls `onChanged()` whether or not the write landed.** Measured.
  `TaskEmbedFieldEditorPopover` mutates the live task, swallows the save, then unconditionally tells
  the note editor to refresh its rendered task card — so the card repaints with values the store may
  not hold. Narrower [[T-322]] case. `AINoteActionSupport` shows the right shape: snapshot the
  fields, restore them on failure, rather than rolling back unrelated pending work.

- [T-367] **Global Cmd+Z on the model context is either a feature or a hazard, and nothing says
  which.** P3, source measured, runtime behaviour not measured. The macOS root installs an
  `UndoManager` on the shared `ModelContext` and routes non-text Cmd+Z/Cmd+Shift+Z into it, while
  destructive copy elsewhere tells the user "This cannot be undone." Editor undo is correctly scoped
  to the text view. **Decide:** if global model undo is real, pin what it may undo; if not, remove
  the root fallback. Do not leave it undecided — the current state means neither the code nor the
  copy can be trusted.

- [T-369] **The Calendar widget links to "the calendar", not to the date it was showing.** Measured.
  The widget snapshot has a `date`; the URL is bare `cadence://calendar` and the parser takes no
  payload, so the app lands on whatever date the calendar was parked on. `CalendarNavigationManager`
  already carries a concrete date and `CalendarPageInteractionSupport` already applies an external
  jump — the plumbing exists, the link just doesn't use it. Either add a date payload or make bare
  `cadence://calendar` explicitly jump to today; drifting to a remembered date is the one behaviour
  nobody asked for.

- [T-370] **Deep-link root application is correct and unpinned; the parser's URL shape is
  undecided.** Two P2/P3s. (a) `iOSRootView` correctly writes *both* the sidebar selection and the
  compact tab route, and `macOSRootView` sets selection — no test guards either; the compact route
  *table* is well pinned, the wiring that consumes it is not. Relates to [[T-334]]. (b) The parser
  switches on `url.host`, so singleton routes silently ignore extra path components and
  `cadence:///today` is rejected. Not reachable from app-owned widgets, which emit canonical URLs.
  Pick strict or lenient and pin it.

- [T-371] **Schedule and bundle ordering stop before they reach a total order.**
  `CadenceScheduleSupport` ends both its task comparators at bare `$0.order < $1.order` (lines 58,
  292) — and `TaskOrdering` documents that `order` is assigned **per container**, so any cross-list
  surface routinely compares equal values. Bundles sort on `startMin` alone with nothing preventing
  two bundles sharing a start. Reach: iPad Today, iOS calendar, macOS calendar and schedule panels.
  `TaskOrdering.fallbackPrecedes` is the fix and it lives in `Models/`, compiled into every target —
  there is no packaging reason this helper stopped short.

- [T-372] **MCP read APIs return order-only lists, so another agent sees nondeterministic order.**
  Measured. `listContainers(kind: nil)` sorts areas by `order` alone before concatenating, and areas
  in different contexts routinely share `order == 0`. This is worse than the UI equivalent: an agent
  reading Cadence twice sees rows move and cannot tell that from a real change, so it re-reads and
  spends tokens proving nothing happened. Shared total comparators for container refs, documents,
  and links, applied at the MCP boundary.

- [T-373] **The EventKit and Reminders comparators both tie on realistic duplicates.** EventKit's is
  named "total" but stops at start-date-then-title, and recurring or imported meetings routinely
  share both. Apple Reminders sorts on due date and title while `AppleReminderItem` already carries
  a stable `id` it never uses. Both fixes are one line: end on the identity the app already has.

- [T-374] **The most common defect shape in 21 audits is "a correct shared helper exists and call
  sites don't use it" — enforce it mechanically.** Synthesis, not a new defect. [[T-359]] (four
  open-coded habit toggles), [[T-362]] (eleven unreconciled date edits), [[T-364]] (creation paths
  bypassing `TaskCreationService`), [[T-365]], [[T-343]] all have that shape, and each was found by
  a human-scale read that will not repeat reliably. `CadenceCreateTaskCommitSurfaceTests` is already
  the right instrument. Extend that source-scan pattern to habit completion, task date/time
  mutation, and delete commit — **after** each shared wrapper exists, not before, or the test
  becomes a brittle census of scattered call sites.

- [T-357] **`TaskCompletionAnimationManager` bypasses the shared status path when it has no context
  — and that is now the second bypass found in that one file.** From the same audit; **inferred, not
  measured**, and the entry keeps that: the manager's context is set on root appear and it is
  injected app-wide, so the contextless branch probably never runs in the shipping app. If it did,
  a recurring task completed through it would not spawn its successor.
  **Read it together with [[T-341]]**, which found the *same file* writing `task.status = .todo`
  directly at line 102 while calling the correct helper at line 41. Two independent audits, two
  different bypasses, one file. That is no longer a coincidence worth two tickets — whoever fixes
  T-341 should route **every** status write in that manager through the shared helper and pin that
  no direct `task.status =` assignment survives there.
  Hardening, not a production bug. Say so in the commit rather than inflating it.

- [T-353] **The widgets keep their own definition of Today, and it is narrower than the app's.**
  From the widget-parity audit (Codex, 2026-08-27); **premise verified**: `scheduledDate < todayKey`
  appears in `CadenceTaskQuerySupport` and **zero times** in `CadenceTodayWidgetSupport`. Extends
  [[T-305]].
  So an unfinished task planned for a past day with no due date is on the app's Today page and
  absent from the Today widget — and because the Calendar widget's "Next up" reuses the Today
  widget's picker, **one divergence produces two wrong widgets**. The Calendar widget can say
  nothing is urgent while Today has work on it.
  The widget rank has no past-do branch either, so this is a definition living in two places rather
  than a missed case. Fix by making the shared membership and rank callable from widget support —
  note the widget target compiles its own subset, so "call the shared helper" needs checking rather
  than assuming.

- [T-354] **`review launch plan !!!` becomes a high-priority task in the app and a literal title in
  the widget.** From the same audit, premise verified: `TaskCreationService` resolves the shortcut
  through `TaskTitleSupport.priorityShortcut`, and `CadenceWidgetIntents` references it **zero**
  times. Extends [[T-314]].
  Same words, two different tasks, depending only on where you typed them — and the widget keeps
  the `!!!` in the title, so the artefact is visible afterwards. The existing widget test covers
  simple titles only, which is why it survived.
  Prefer routing capture through `TaskCreationService` over calling the title helper directly:
  [[T-314]] is already about eliminating that open-coded copy, and every other creation rule it
  skips is the same bug waiting.

- [T-355] **DECIDE: the milestone widget mixes directions with their own milestones.** From the same
  audit; measured code, inferred product impact.
  The app's Goals surface is hierarchical — top-level goals are groups, milestones nest beneath. The
  widget prioritizes every active goal, parent or child, into one flat pool. Since a parent's
  contribution **already recurses through its sub-goals**, the widget can show a rollup and one of
  its own children side by side as peer "priority milestones", double-counting the child's progress
  in the reader's eye.
  Two coherent answers: mirror the app and prioritize top-level directions, letting their summaries
  carry the milestones; or be genuinely milestone-first, filter out top-level goals, and rename the
  copy away from "Active goals". **The current mixed pool is only defensible with a test saying it
  is deliberate**, and there is none.

  Note the audit also reported [[T-301]] as looking already fixed. It is being fixed **right now**
  in uncommitted work — the audit ran against the dirty tree and read an agent's in-flight change.
  Not stale on `main`; do not close it on that basis until that work lands.

- [T-351] **A list with an old remembered tab opens the global default instead of Tasks.** From the
  navigation-persistence audit (Codex, 2026-08-27); **premise verified.**
  `ListDetailView.restoreRememberedTab()` reads the per-list value through the *failable*
  `ListDetailPage(rawValue:)` and, when that returns nil, falls back to
  `resolved(defaultPageRawValue)` — the user's **global** default. The shared rule
  `ListDetailPage.resolved(_:)` exists precisely to map a stale raw value to the canonical page, and
  this path never calls it with the stale value.
  So a list still holding a removed tab name like `Planning` opens **Links** if that is the global
  default, rather than Tasks. And this is not hypothetical: `ListDetailPageTests` explicitly
  documents that per-list remembered tabs can contain old `Planning` values.
  One-line fix — resolve the remembered raw value itself rather than discarding it. Test with a
  stored `Planning`, a global default of `Links`, and an expected `Tasks`.

- [T-352] **DECIDE: should the root destination persist? A comment already says it does.** From the
  same audit; **premise verified** — `macOSRootView` holds the selection in `@State` with **zero**
  `SceneStorage` or `AppStorage`, and no restore path exists anywhere. iPad regular width is the
  same, while the *compact* tab and task subsection are persisted, so one platform has two
  different answers depending on width.
  **The defect worth acting on is not the missing feature — it is the comment.**
  `macOSRootSupportViews.swift` documents a parameter as non-nil for "an `.inbox` selection
  **restored at launch**", describing a mechanism that does not exist. That is the **third** such
  comment found this week: [[T-333]] has one claiming macOS reads a shared sorter it does not, and
  [[T-337]] carries one justifying an unseeded button by a drop path that no longer exists. A
  comment asserting a mechanism is worse than a missing mechanism, because it stops the next reader
  checking.
  So: decide the contract, and **fix the comment either way**. If root navigation should persist,
  start with stable destinations only — Today, Inbox, All Tasks, Habits, Goals, Calendar. **Do not
  persist area or project ids until [[T-345]] lands**, or launch will restore a selection pointing
  at a deleted list, which is that ticket's bug made permanent.

- [T-348] **A reference to a deleted note silently retargets to a different note with the same
  title.** From the markdown-reference audit (Codex, 2026-08-27); **premise verified at
  `NoteReferenceSupport.linkedNotes`**: the resolver tries `reference.noteID` in an `if let` chain,
  and when that fails it **falls through** to matching on `fallbackTitle`. `linkedTasks` and the
  backlink count do the same, and iOS's tap navigation duplicates the resolver.
  **The root is that the parsed type cannot tell a stale ID from no ID.** `[[note:<deleted-id>|Budget]]`
  and `[[Budget]]` reach the same code path, so a reference that named a *specific* note by id
  quietly starts pointing at whichever other note is called Budget. The user wrote a precise
  reference and gets an imprecise one back.
  It reaches MCP reads too, so an agent asking about a note is told about the wrong one.
  Fix by splitting the parsed reference: title-fallback only when the markdown had no valid id form.
  The existing tests pin the safe half — a stable id beats a stale title, and a title-only
  reference that resolves to nothing disappears. **Nothing pins that an explicit id must not
  retarget**, which is why this survived.

- [T-349] **A deleted embedded task stays interactive in an open editor.** From the same audit;
  **inferred from a repeated pattern**, not measured at runtime, and the entry should keep that
  distinction. Each editor caches newly embedded tasks in `recentEmbeddedTasks` to cover creation
  latency, and lookup falls back to that cache when the live query no longer has the task. Delete
  the task elsewhere and the card can still toggle, rename, open and hover against a cached object.
  Four surfaces repeat it: `NotePanel`, `NoteEditorPane`, `ListNotesSupportViews`, and iOS's
  editing surface.
  The fix shape matters: the cache should serve **creation latency only**, so a fallback hit should
  re-verify by fetching the id and drop the cached value when that misses. And the missing-card
  behaviour must stay — the markdown reference remains, the actions stop working. Test the helper,
  not the private SwiftUI methods.

- [T-350] **An image can be garbage-collected out of a note that still references it.** From the
  same audit, premise verified — `MarkdownImageAssetServiceTests` contains a fixture line
  `Inline ![ignored](cadence-image://…)` and asserts it **is** ignored.
  That is correct for **rendering**: an inline image stays paragraph text rather than becoming a
  block. The bug is that **asset lifecycle and export reuse the rendering predicate**, so
  `referencedIDs` counts only standalone references — and a list or note delete can collect an
  asset that a surviving note still shows inline. That is data loss, narrow but real.
  Reachable mainly by hand-editing an image into a sentence, since paste and photo insertion both
  create standalone blocks — so **low frequency, permanent consequence**.
  **Do not widen the shared predicate**, which would change what renders as a block. Split the API:
  standalone references for rendering and block deletion, all references for lifecycle and export.
  The inline-capable pattern already exists in `MarkdownStyleRangeSupport`.

- [T-345] **The macOS sidebar can stay selected on a list that no longer exists.** From the
  selection-after-mutation audit (Codex, 2026-08-27); premise verified — `iOSListViews` has
  `effectiveSelectedRoute` and retargets when the active route disappears, and the macOS root has
  **no** selection normalizer at all.
  Delete an area or project from its edit sheet or Settings and the root `selection` can stay
  pointing at the deleted id. The detail loaders then render **nothing** — not an explanation, not
  an empty state, just blank content — which reads as the app having lost the page rather than the
  list having been deleted.
  Two halves worth fixing together: normalize the selection, **and** give the loaders an explicit
  missing-list state. Either alone leaves a blank pane reachable.

- [T-346] **macOS Goals keeps a deleted goal selected whenever the search box is empty.** From the
  same audit, premise verified at `GoalsView.swift:106`:
  `visibleGoals.contains(where: { $0.id == selectedGoalID }) || trimmedQuery.isEmpty`.
  **That condition conflates two different questions** — "does this goal still exist?" and "is it
  hidden by the current search?" — and answers both with "assume it is fine when search is empty".
  Empty search is exactly the state in which a *deleted* goal is most likely still selected, so the
  guard is weakest precisely where it is needed.
  Fix by separating them: missing from `allGoals` should **always** retarget; hidden by search may
  keep the current product behaviour. Both correct patterns already exist — iOS clears the selected
  goal before deleting, and macOS Habits retargets when its selection leaves the visible set.

- [T-347] **Six local iOS sheets present a detail view without the deleted-model guard.** From the
  same audit; measured in source, runtime impact inferred.
  The root task and bundle hosts route through `CadenceDetailPanelPresentation.resolveHeldSubject`,
  which closes a sheet when the held model is genuinely deleted. Four task sheets and two bundle
  sheets present the detail view directly and skip it, so an external deletion while the sheet is
  open leaves it holding a dead model.
  **Preserve the distinction the shared rule already makes**, which is the subtle part: leaving the
  page's query must *not* close the sheet; only actual deletion should. That difference is why the
  guard exists rather than a simple existence check.
  The audit's fourth step is the one that keeps this closed: a source scan so a direct detail sheet
  cannot bypass the guard again. Note the shape that has failed here repeatedly — scope it to a
  function body and count call sites, do not `range(of:)` for the first match.

  **These three reverse the direction of a pattern worth not over-fitting.** Five findings this week
  had iOS lagging a model macOS already grew ([[T-323]], [[T-324]], [[T-325]], [[T-339]]). Here
  macOS lags iOS twice over — iOS normalizes both the list route and the goal selection, macOS
  neither. The drift is not one-directional, and a sweep that only ports macOS to iOS would miss
  half of it.

- [T-341] **Restoring a cancelled task on macOS leaves its completion timestamp behind.** From the
  status-lifecycle audit (Codex, 2026-08-27); **premise verified, and the framing is tighter than
  reported.** `TaskCompletionAnimationManager` calls `TaskWorkflowService.markTodo(task)` at line
  **41** — the correct path, which clears `completedAt` — and then at line **102**, in the same
  file, the cancelled branch assigns `task.status = .todo` directly. So restoring a cancelled task
  leaves a non-nil `completedAt` on an open task, violating the lifecycle invariant, and skips the
  reconcile the wrapper performs.
  Not two files disagreeing across a platform boundary: **one file disagreeing with itself, sixty
  lines apart.** The existing test asserts the status and not the timestamp, which is why it
  survived. Smallest live invariant bug on this list — fix it first, and extend the test to assert
  `completedAt == nil`.

- [T-342] **A frozen macOS surface drops tasks that became done, but keeps ones that became
  cancelled.** From the same audit, premise verified: `TaskSurfaceFreezeModels` filters
  `{ !$0.isDone }` in two places and never considers `isCancelled`. So a task cancelled while a
  surface is frozen stays visible in an active frozen group until the freeze releases.
  **The app already has the right predicate** — `CadenceTaskQuerySupport.isFinishedTask` defines
  finished as done *or* cancelled, and the logbook and history already use it. The freeze filter
  simply predates or ignores it. Existing tests pin the done case and not the cancelled one, which
  is the same shape as [[T-341]]: half a rule tested, so half a rule implemented.

- [T-343] **Six iOS paths change a task's status without reconciling its notifications.** From the
  same audit; **measured in source, runtime impact inferred.** The row actions, task views, board
  cards, markdown surface, bundle sheet and focus view all complete or reopen through the pure
  shared helper without the app-side reconcile that macOS's `TaskWorkflowService` performs.
  **This is a latency bug, not a correctness one**, and the entry should say so: `iOSRootView`
  reconciles on scene-phase changes — widened to *every* change in `75e36c4` — so a stale
  notification survives only until the next lifecycle checkpoint. Related to [[T-306]] and
  [[T-312]], which fixed the same gap for the out-of-process writers.
  The audit's own constraint is the important half: **do not push the reconcile into the shared
  helper**, because widgets and MCP use the same mutation paths and must not schedule app-side
  notifications. An iOS-side wrapper, or explicit call sites.

- [T-344] **DECISION NEEDED: what does the completion circle mean on a cancelled task?** From the
  same audit, and filed as a question because the behaviour may be deliberate.
  The shared toggle treats any non-done task as "mark done", cancelled included. The iOS detail
  sheet's comments say that is intended — the circle owns done/todo, the cancel button owns
  cancelled/restore. But the row's swipe label shows **"Done"** on a cancelled task rather than
  "Restore", so the two surfaces describe the same gesture differently.
  Either is defensible; the current state is that nothing pins which. Decide, then pin it with one
  test or one comment — the audit's own recommendation, and the right one.

- [T-340] **Two more places a task keeps a context its owner no longer has.** Found while closing
  [[T-292]] and [[T-293]], and deliberately not folded in.
  1. Editing an **area's** context re-points tasks filed directly in that area, but not tasks in
     *projects* under it whose own `context` is `nil`. Those projects' `resolvedContext` changes and
     their tasks are never walked — the same defect one level down.
  2. `DataIntegrityRepairService.mergeProject` re-points tasks moved *from* the source project, but
     tasks already in the **target** keep their old `task.context` even though the merge may have
     changed the target's area.
  Both are the T-292 rule applied at call shapes nobody walked. The rule itself already exists —
  `Project.resolvedContext` — so this is finding the remaining walks, not deciding anything new.
  Note why they cannot simply reuse `assignContainer`: that also rewrites `sectionName` and `order`,
  and re-ordering every task in a list because its owner changed is the T-175 bug.

- [T-339] **iOS has three failure vocabularies for EventKit; macOS has one.** Recommended by the
  agent that closed [[T-323]] and [[T-325]], which deliberately did **not** do it.
  macOS models a calendar write failure once, as `CalendarWriteFailure` with a `title` and a
  `message`, and renders it through one shared alert. iOS has accumulated three answers to the same
  question: a `Bool` return, the shared notice strings [[T-324]] introduced in
  `CadenceCalendarEventEditingSupport`, and now an outcome enum for the note commit. Each was the
  right local call; together they are the divergence.
  Porting the macOS model means changing every `Bool` write on `iOSCalendarManager` and every call
  site in both event sheets — well past the two tickets that surfaced it, which is why it was
  correctly refused there. It is its own ticket.
  This is the fifth finding where **iOS lags a model macOS already grew** (see [[T-323]], [[T-324]],
  [[T-325]]). At five, the pattern is the work: port the model once rather than patch the sixth.

- [T-338] **macOS adds a subtask by writing one side of the relationship; iOS writes both.** Found
  while closing [[T-296]], which fixed the same asymmetry on the *delete* side.
  `TaskDetailPopover.addSubtask` (`SchedulePanelComponents.swift:148-157`) sets
  `subtask.parentTask = task` and never appends to `task.subtasks`; the iOS `addSubtask` writes
  both. It is why `deleteSubtask` had to take the parent explicitly rather than trusting
  `subtask.parentTask` — a back-reference that may be the only side written.
  The rule T-296 established is the fix: **write both sides explicitly, never depend on
  back-population timing.** T-296 measured why that matters on the delete side — between the delete
  and the next flush, the parent's array still holds the deleted row, and that window is exactly
  when a SwiftUI list re-renders. Whether the create side has an equivalent window is unmeasured.

- [T-337] **The `+` inherits context from what you drop it on, and from nothing else.** The user's
  rule, 2026-08-26, and it supersedes [[T-336]] and reverses part of [[T-282]]:
  - **Tap the button** → no context. Just a task.
  - **Hold, then choose a palette segment** → no context either. Task / Event / Note, unseeded.
  - **Drag it onto an existing list, group, section or grouped display** → it inherits *that*
    target's context.
  The principle is worth stating because it decides the edge cases: **context comes from where you
  drop it, not from where you started.** A button standing on the Today page is not a statement
  about what you are creating; dropping onto a list is.

  **What already exists**, so this is smaller than it sounds: `CadenceCaptureDropHitTest` and
  `seed(forTarget:)` are built and shipped — dropping onto a row already seeds from that row, on
  both placements, through one hit-test.

  **What changes:**
  1. **The iPad's corner `+` must stop passing `baseSeed` on a tap.** It currently seeds the page —
     Today seeds today's date, a list detail seeds its list. Under this rule that is wrong, and
     `iOSCaptureRadialMenu.swift:295` documents the *opposite* reasoning ("a page's corner `+` is
     already standing somewhere"), so that comment has to go with it. This also makes the two
     placements behave identically, which retires the last real difference between them.
  2. **Extend drop targets from rows to groups.** The hit test collects candidate frames; a section
     header, a kanban column and a list group need to register as candidates and resolve to the
     right seed. Decide what a *group* seeds — a section header should presumably seed its section
     name and its container, not just the container.
  3. **Decide what an empty group seeds**, since a group with no rows still has an identity, and it
     is the case most likely to be missed.

  Pin it by value: the seed a drop produces for a row, a section, a column and an empty group are
  four assertions, and the two no-context paths are two more. Note the existing test asserting the
  tab bar's button carries no `baseSeed` becomes the rule for *both* placements rather than the
  difference between them.

- [T-334] **Resizing an iPad window can land you on the wrong screen.** From the iPad/iPhone layout
  audit (Codex, 2026-08-26); **premise verified — there are zero `onChange(of: horizontalSizeClass)`
  handlers in `iOSRootView`.** The root keeps the sidebar's `selection` and the compact shell's
  `selectedTabRaw` / `tasksSectionRaw` as separate stores, picks a shell from the size class, and
  never bridges between them. A regular sidebar tap writes only `selection`; a compact tab tap
  writes only `selectedTab`. So Calendar on iPad can narrow into a stale Tasks, and compact Calendar
  can widen back into a stale Today — reachable through Split View and Stage Manager resizing,
  which is ordinary iPad use.
  **The correct pattern is already in the same file**: deep links and the Focus handoff both write
  *both* shells. So this is not a missing mechanism — it is user navigation not using the one that
  exists. Fix with a projection between compact route and sidebar item, applied on selection or on
  the size-class transition, and pin it for plain navigation rather than only for deep links.
  Measured in source; the live effect is inferred, since neither the auditor nor I drove a resize.

- [T-335] **Settings forgets which category you were in when the window resizes.** From the same
  audit, premise verified — `iOSSettingsView` holds `selectedCategory` for the rail and
  `drilledCategory` for the phone layout, ten references between them, and **zero** size-class
  bridges. Compact taps write one, the regular layout reads the other, so widening from Templates
  can land on Navigation and narrowing from Calendar can drop back to the category list.
  **The app already solves exactly this elsewhere**, and the audit named it: Calendar stores the
  user's Month detail choice separately and lets width decide only *placement*. That is the rule —
  **the category is user state, compact-versus-regular is presentation** — and it generalises past
  this ticket, including to [[T-334]].

- [T-336] **DECISION NEEDED: should the iPhone `+` inherit the page you are on?** From the same
  **ANSWERED 2026-08-26 by the user, and superseded by [[T-337]].** The question was whether the
  iPhone `+` should inherit the page. The answer is **neither button should** — context comes from
  the *drop target*, not from the page you happen to be standing on. That resolves this ticket and
  reverses the iPad's current page-seed at the same time. Keep this entry only as the record of how
  the question was framed; the work is T-337.
  audit, and filed as a question rather than a defect because **the current behaviour is deliberate
  and test-pinned**, which the audit established rather than assumed.
  The iPad's page-corner `+` passes a seed — Today seeds today's date, a list detail seeds that
  list. The iPhone's centre `+` is deliberately unscoped, and `CadenceCapturePaletteTests` asserts
  it carries no `baseSeed`.
  So this is only a ticket if the wanted behaviour is: tapping `+` from iPhone Today or a list
  should inherit that context. Note it sits beside the rule the user set for [[T-282]] — placement
  may differ across widths, capability may not — and a seed is arguably capability rather than
  placement. **Ask the user before touching it**, and if the answer is "leave it", record that here
  and close, because the test currently pins the opposite of what a reader might assume.

- [T-332] **macOS trims whitespace, iOS trims whitespace and newlines.** From the same audit;
  measured in source, the user path inferred — it depends on whether paste can introduce a newline,
  which neither of us drove. Several macOS forms trim `.whitespaces` only or save the raw name;
  the iOS siblings use `.whitespacesAndNewlines`. Verified the difference is real:
  `"Name\n"` trims to `"Name\n"` and `"Name"` respectively.
  Route both through one shared normalizer rather than fixing four call sites, since the next form
  will otherwise pick whichever it copies from.

- [T-333] **The macOS sidebar keeps a private copy of list ordering that iOS routes through the
  shared one.** From the same audit, premise verified — including that `iOSRootSidebar`'s own
  comment claims macOS reads the shared sorter, which it does not. Ordinary data behaves; legacy,
  imported or CloudKit data with duplicate same-kind order or name can drift, because the shared
  sorter ends in an id tie-break and the macOS copy does not.
  Either route macOS through `CadenceSidebarLists`, or **pin the fork deliberately with a test and
  fix the comment that says otherwise**. A comment asserting a sharing that does not exist is worse
  than the fork: it is what stops the next reader from checking.

- [T-328] **`DataIntegrityRepairService` cannot see four of the models that can be orphaned.**
  From the same audit, premise verified by counting fetches: it fetches `Context`, `Area`,
  `Project` and the rest, and fetches `Subtask`, `TaskBundle`, `HabitCompletion` and
  `MarkdownImageAsset` **zero** times. The shared delete helpers prevent most of those orphans at
  source, so this is not a live bug — but if one exists already, from legacy data, a CloudKit
  oddity, a failed restore ([[T-326]]) or a delete that bypassed the helpers ([[T-296]]), repair
  will not clean it up.
  The decision is which thing this service is: either document it as duplicate-container-and-note
  repair and stop implying more, or give it a real orphan sweep for targetless subtasks, empty
  bundles, unowned habit completions and unreferenced image assets. **Do not leave it named like a
  general repair while covering half the schema** — the name is what makes the gap invisible.

- [T-321] **Structural editors close without knowing whether the change persisted.** From the same
  audit; premise verified. The iOS context editor, the iOS list editor and macOS's `EditListSheet`
  all mutate, `try? modelContext.save()`, and dismiss. These objects drive task grouping, context
  scoping and list visibility, and the list editor also reassigns tasks first — so a swallowed
  failure can leave the reassignment half-applied with the editor closed over it. The audit's
  lower-priority sibling belongs here: iOS event-note creation opens the note editor after a
  swallowed save.

- [T-322] **Decide the rule for `try? save()`, then sweep — there are 133 of them.** Measured, not
  estimated: `try? modelContext.save()` / `try? context.save()` appears **133 times** across
  `Cadence/`. [[T-319]], [[T-320]] and [[T-321]] are four of them; [[T-291]], [[T-298]], [[T-307]]
  and [[T-315]] are the same shape found by four earlier audits in unrelated code.
  **This is a convention, not a set of bugs, and it should not be fixed with a sed.** Many of the
  133 are probably fine — a save whose failure the user cannot act on, or a transient object. What
  is missing is a rule saying which is which, so the next one is written correctly instead of
  found by the ninth audit.
  Proposed shape, to be decided: a save is allowed to swallow its error only when nothing visible
  depends on it. Any save whose failure would let the UI **dismiss, navigate, or report success**
  must throw and be handled. Then triage the 133 against that rule rather than converting them all.
  Write the rule into `AGENTS.md` when it is decided — a rule an agent reads before writing the
  134th is worth more than fixing the first 133.

- [T-313] **The milestone widget recomputes every goal summary two or three times per timeline.**
  From the same audit. The snapshot fetches all goals, computes contribution and habit summaries to
  prioritize them, then recomputes them for the visible ones and again for the overdue rollup. Goal
  contribution walks recurse through sub-goals, linked lists, tasks and habits, so on a large store
  this can approach WidgetKit's execution budget — and a widget that misses that budget renders
  nothing at all. Carry the decorated summaries from the prioritization pass into rendering.

- [T-314] **Widget intents re-implement task capture and habit toggling.** From the same audit.
  `CaptureTaskIntent` creates tasks inline and `ToggleHabitCompletionIntent` duplicates the toggle,
  rather than going through the shared mutation helpers. Small today, and exactly the drift this
  repo keeps paying for as defaults, recurrence and habit semantics evolve — the same argument as
  [[T-296]] and [[T-292]], where one strict shared path exists beside looser open-coded copies.
  An App Intent-safe mutation service owning capture, complete and habit toggle would also give
  [[T-311]] and [[T-312]] one place to put the preflight and the reconcile marker.

- [T-309] **Read-write MCP startup runs migration and repair more than once.** From the same audit.
  `main.swift` builds a write container and then constructs read and write services that each do
  further setup against the same context. Mostly overhead — but it widens the window in which a
  **second process mutates the store before any tool call has been made**, and it is only safe
  while every one of those operations stays perfectly idempotent, which nothing currently enforces.
  Centralize the startup work, or let the service initializers skip what the container factory
  already did.

- [T-305] **Today should group by list, not by date intent — on both platforms.** Reported by the
  user 2026-08-26. Today currently groups into `CadenceTodayTaskGroupKind`: Overdue, Past Do, Due
  Today, Planned Today. The user's decision, three parts:
  1. **Drop "Planned Today" as a heading.** It restates the page — this is the Today view, so
     everything in it is today. Same objection as the standing rule that a page header does not
     describe the page you are already on; this is that rule applied one level down.
  2. **Group the day's work by list instead**, the way the rest of the app groups tasks. The
     `PAST DUE LISTS` block at the top is list-shaped already, so the page stops mixing two
     different grouping axes.
  3. **Keep Overdue at the top, and have a rolled-over task fall into its list's group** rather
     than into a second date-shaped bucket. That is what makes the roll-over feel like it did
     something: the task leaves the red section and joins its list.
  Apply the same change to iOS, whose Today sections were unified onto the shared support in
  `2dcc948` and `c6f7d61`.
  Worth reading before designing: `CadenceTodayLayoutSupport` records that the split between
  Overdue and Planned Today is deliberate and not width-driven, so this reverses a decision rather
  than filling a gap — say so in the commit. `CadenceTaskPlanningSupport.CadenceTodayTaskGroupKind`
  is the shared enum both platforms read, so the grouping decision has one home; the risk is the
  **sort** inside each group and the rollover banner's interaction, not the enum.
  Not decided, and worth asking the user once there is something to look at: what happens to a task
  with no list — its own group, or the bottom of the page.

- [T-300] **The drag-and-drop date seed has the same lenient-parse bug.** From the same audit,
  premise verified verbatim: `CadenceTaskDropSupport.dateValue` does
  `guard DateFormatters.date(from: value) != nil` and then `return value`. Same class as [[T-299]],
  lower risk because drop keys are internally generated and therefore already fixed-width in
  practice — but the helper accepts arbitrary strings and can seed a composer with a
  non-canonical key. One-line fix: return `DateFormatters.dateKey(from: parsed)`.

- [T-301] **Widget date labels bypass the app's English-pinned formatters.** From the same audit.
  `CadenceTodayWidgetSupport` builds its weekday, day-number and due-day labels with
  `date.formatted(...)`, which is locale-sensitive, while `DateFormatters` deliberately pins the
  app's display formats to `en_US_POSIX`. On a non-English host a widget can render localized
  month and weekday text beside English app chrome, on the same home screen.
  The widget target compiles its own subset, so the fix is nonisolated widget-safe helpers
  mirroring `shortDate` / `dayOfWeek` / `dayNumber` rather than a cross-target import.
  Related to the localisation work already done under [[T-18]], which pinned exactly these
  formatters for exactly this reason and did not reach the widget target.

- [T-302] **`CadenceCalendarDateMemory` accepts a calendar and then ignores it.** From the same
  audit. `storageKey(for:calendar:)` snaps to `calendar.startOfDay` and then calls
  `DateFormatters.dateKey(from:)` — the default-timezone spelling — rather than the calendar-aware
  overload. Every current call site passes `Calendar.current`, so this is not a shipping bug today;
  it is an API promising something it does not keep, with tests covering only the current-calendar
  case. Either honour the parameter on both the write and the parse, or remove it.

- [T-303] **The backup timestamp formatter lives outside the formatter layer.** From the same
  audit. `PersistenceController` declares its own `DateFormatter` while `DateFormatters` states
  that every one should live there. It is POSIX-pinned and works, so this is rule drift rather
  than a defect — but the rule exists so an agent can find every date format in one file, and this
  one is invisible to that search. Move it to `DateFormatters.backupFolderTimestamp`.

- [T-295] **`deleteBundle` leaves `calendarEventID` set; its sibling twelve lines above clears it.**
  From the second external audit (Codex, 2026-08-26); **premise verified, and the evidence is
  stronger than the report's.** The audit said macOS clears the field elsewhere while the shared
  helper does not. In fact `CadenceTaskMutationSupport.deleteBundleIfFullySettled` and
  `deleteBundle` sit in the **same file, twelve lines apart**, unbundling members in near-identical
  loops — and only the first sets `member.calendarEventID = ""`. That is a much easier
  inconsistency to argue about than a cross-platform one.
  **Read the "Calendar / Events" note in `CLAUDE.md` before assigning this any urgency.** Nothing in
  the app writes that field a non-empty value — measured again here, every assignment is `""` and
  the only non-empty reads are the exporter's. So a stale value can only come from a build that
  shipped before that changed, or from CloudKit. The fix is one line and makes the two loops agree;
  the *impact* claim in the audit ("iOS can leave tasks pointing at an old calendar event") is only
  true of pre-existing data, and a ticket that overstates it will get someone chasing a live bug
  that is not live.

- [T-298] **A failed fetch makes the note-delete summary understate the damage.** From the same
  audit, premise verified at `CadenceNoteActionSupport.swift:130-131`: both the note fetch and the
  image-asset fetch are `(try? …) ?? []`, so a store read failure reads as "nothing will be
  affected" in the confirmation the user is about to accept. The actual cleanup in
  `CadenceListDeleteHelpers` is more conservative, so this is a misleading-summary risk rather than
  data loss — but it is misleading in the one direction that matters, telling the user a delete is
  smaller than it is. Surface an unknown-impact state instead of collapsing a failure to zero.
  Same shape as [[T-291]]: a failure treated as an ordinary empty result.

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

  **Second pass, 2026-08-26 against `36be8ba`: four of the six done, each proved by mutation**
  (apply → red on exactly the intended test, restore → green; 0 compile errors on every run, and
  for each one the *old* whole-file needle was grepped in the mutated file and found still present,
  which is the blindness proof stated mechanically rather than by re-running a deleted assertion).
  - *The two inspector-host suites.* The repo-wide dictionaries are kept — they are the right shape
    for "exactly N places in the whole app" — and the per-file half is now placement.
    `theHostDrawsThePanelOnlyInTheStayBranchOfTheSharedRule` (and its bundle twin) pin the panel to
    the `.stay` arm of `CadenceDetailPanelPresentation.resolveHeldSubject`; **swapping the `.stay`
    and `.close` arms** leaves `iOSTaskDetailSheet(` at one occurrence in one file, every old
    assertion green, and every row in the app opening nothing.
    `theRootAppliesTheHostAboveBothShellsRatherThanInsideOne` (and its bundle twin) slice
    `iOSRootView`'s `Group` and require the host, the bundle host and the startup banner to be
    applied *to* it, not inside it; **moving `.iOSTaskInspectorHost()` into the
    `horizontalSizeClass == .regular` branch** — iPad keeps the inspector, the iPhone's four tabs
    get dead taps — keeps the file count at exactly 1.
    `theNestedHostSitsOnTheSheetThatCarriesAWholePageOfRows` scopes the nested host to
    `iOSTodayOverdueListSheet`'s **`var body`**, and the reason is a measured one: the first draft
    scoped it to the *struct* and survived a mutation that moved the modifier onto a second computed
    property in the same struct. Struct-level was not enough; `var body` is.
  - *`CadenceTodayOverdueSummarySurfaceTests.theMacCardsHopTheNavigationManagerThroughTheSharedRequest`
    is behavioural now.* macOS's half is compiled by this target and nobody had reached for it: the
    test drives `TasksPanelSupport.openOverdueListSummary` / `openOverdueSectionSummary` against
    `ListNavigationManager.shared` and reads the request it is left holding. Two mutations that the
    old scan could not see: **swapping the `.area` and `.project` arms** of the private
    `open(_:listNavigationManager:)`, and **dropping `sectionName:`** from both hops so the board
    lands on whatever column it last showed. The one whole-file assertion kept is the *absence*
    (`if let projectID = summary.projectID`), which is the claim a scan states better than a call.
  - *`CadenceTodayRolloverSurfaceTests.theMacSpellingDelegatesToTheSharedMutation` is scoped and
    stated as an equality.* `cadenceFunctionBody` slices `SchedulingActions.rollOverTaskToToday` and
    the whole trimmed body must equal the one delegating call, so **any** added statement fails —
    proved with `task.scheduledStartMin = -1` appended under the delegation, which the old
    `contains(…)` cannot see.
  - *`55d696b`'s owed evidence is paid.* Forcing `CadenceTaskGroupHeadingMetrics.showsCapsule` to
    `true` fails `CadenceInboxRemindersSurfaceTests.onlyAnUnknownCountSuppressesTheCapsule`, exit 65
    at 0 compile errors. The behavioural test was load-bearing all along.

  **Still open, and the list is shorter than it was for one reason worth reading.**
  - `CadenceKanbanColumnLifecycleSurfaceTests.bothVisibleCompletionControlsSitInsideTheLifecycleGate`
    and `theKeyboardRouteAndTheConvergencePointBothRefuseDefault`. Both already assert *structure*
    with brace-adjacent regexes; what is unscoped is the pair of
    `section.supportsLifecycle` == 2 counts beside them. Not attempted here.
  - `CadenceListDetailTabStripMarginTests.theResetIsTheStripsAloneAndTheHostCompensatesForNothing`.
    Not attempted. Note while you are in the file: it declares a **second** declaration slicer
    (`declaration(named:in:)`, which slices to the next `\nstruct` rather than brace-matching), and
    `CadencePageHeaderMetricsTests` / `CadenceTodayUnificationTests` declare a **third** between
    them (`declarationBody(of:in:)`, twice, byte-identical). Three private near-copies of the thing
    `cadenceFunctionBody(_:in:)` was promoted to be.
  - `CadenceSharedBoardChromeTests.bothBoardsDrawTheSharedMetadataChip`. Not attempted.
  - `CadenceSharedTaskRowJobsTests.theRowsAnimatedPartsAreStillExtractedIntoTheirOwnSubViews` was
    **rewritten but is the one place a mutation did not survive on its own merits**, and that is the
    finding rather than the fix. It now asks each declaration for its own count —
    `TaskCompletionButton` 1, `TaskRowBackground` 1, `MacTaskRow` 0, `MacTaskRowEstimateChip` 0 —
    over `cadenceFunctionBody`, with the whole-file 2 kept as a no-fifth-reader guard. The mutation
    (the row observes the manager and hands it down to `TaskRowBackground` as a `let`) does turn it
    red, but it turns `CadenceTodayUnificationTests.theTaskRowStillDoesNotObserveTheCompletionAnimationManager`
    red too — that test has scoped `MacTaskRow` and `MacTaskRowEstimateChip` to their declaration
    bodies all along, so the bullet's stated gap ("cannot tell the two extracted sub-views from
    `MacTaskRow` growing one of its own") was already closed by a neighbour nobody had checked.
    The residue the new assertion adds — *both* observations in one sub-view and none in the other —
    could not be mutated into existence in code that compiles, because a view that uses `manager`
    has to obtain it and the only non-observing route needs a holder that is itself forbidden from
    observing. Recorded as unprovable rather than claimed as proved.




- [T-122] **Flip `SWIFT_VERSION` to 6.0 — now an open question rather than a blocked one.** `D-95`
  **DECIDED 2026-08-26: investigate and report, do not flip.** The user's call. Measure each target's
  error and warning count under Swift 6 and re-test whether the blocker is still real against the
  current toolchain, then bring a recommendation. A flip that adds concurrency warnings destroys the
  zero-warning baseline, which has caught real regressions repeatedly — that baseline is worth more
  than the language mode.
  cleared the last macOS error, so nothing in the app's source blocks it. What remains: 10
  Swift-6-mode *warnings* elsewhere in the app (byte-identical before and after T-105, none in
  editor files), and on iOS the toolchain bug in [T-115] — swift-frontend crashes in IRGen once the
  diagnostics are gone, which is not app code. So macOS could plausibly flip first; iOS cannot until
  the toolchain moves. `CadenceMCPServer` has been on 6.0 all along.

  **MEASURED 2026-08-26 against `36be8ba` and re-confirmed on `ea77271`, Xcode 26.6 / Swift 6.3.3.
  Recommendation: do not flip anything yet — flip nothing before the two items in "what a flip
  needs" below are done, and never flip iOS while [T-115] stands.** Every number below is one
  `xcodebuild` run into a private `-derivedDataPath` over an `rsync`-isolated tree, exit status read
  on the xcodebuild line, diagnostics counted from the log with **no path filter** and attributed to
  a target by the `(in target 'X' from project 'Cadence')` line above them.

  | Target | Swift 5 today | Swift 6 (`SWIFT_VERSION=6.0` override) |
  |---|---|---|
  | `Cadence` (macOS) | 0 errors, 0 warnings | **0 errors, 10 warnings** |
  | `Cadence` (iOS Simulator) | 0 errors, 0 warnings | 0 errors, 1 warning — **but swift-frontend crashes, no build** ([T-115]) |
  | `CadenceWidgets` | 0 errors, 0 warnings | **0 errors, 0 warnings** |
  | `CadenceMCPServer` | already 6.0: 0 errors, 0 warnings | already 6.0 |
  | `CadenceTests` | 0 errors, 0 warnings | **611 errors** |
  | `CadenceUITests` | 0 errors, 0 warnings | 0 errors, 5 warnings |

  Notes on how those were obtained, because two of them are not what a single run reports.
  - A Swift 6 build of the app **stops at `EmitSwiftModule` on two errors in one file** —
    `Cadence/Services/CadenceDataExportService.swift:228`, `nonisolated static let
    recordCountsByEntityName: [String: KeyPath<CadenceArchive, Int>]`, because `KeyPath` is not
    `Sendable`. That file postdates `D-95`, so **the app's Swift-6 error count is not a fixed
    quantity that T-105 drove to zero — it regressed to 2 the moment ordinary new code was written
    under Swift 5.** Nothing else in the app module errors: with that one declaration changed to
    `nonisolated(unsafe)` **in the scratch copy only**, the whole macOS app module compiles.
  - The per-target error counts were then taken with `SWIFT_COMPILATION_MODE=wholemodule`, because
    the default batch mode surfaces **one failing batch at a time** — the first Swift 6 run of
    `CadenceTests` reported 18 errors in one file and stopped, and the module actually holds 611.
    Any future count of this debt must be taken whole-module or it is a lower bound.
  - The 10 macOS app warnings are the same 10 this ticket has always claimed, and they are in five
    files: `Services/CadenceRemindersManager.swift` (1 — the only cross-platform one, and the iOS
    build's single warning), `macOS/Views/TimelineDropInteractionSupport.swift` (3),
    `macOS/Services/QuickTaskPanelController.swift` (3), `macOS/Services/CalendarManager.swift` (1),
    `macOS/Services/CadenceMCPRefreshCoordinator.swift` (1),
    `macOS/Views/CalendarBoardDayColumnSupportViews.swift` (1). All are ordinary main-actor
    isolation, none is in `macOS/Editor/`.

  **`CadenceTests`' 611 errors are one build setting, not 611 problems.** The app target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; `CadenceTests` and `CadenceUITests` do not. So under
  Swift 6 every `@Test` function is nonisolated by default and every call into the app's
  main-actor-by-default API is an error — 365 of the 611 are literally "call to main actor-isolated
  static method 'X' in a synchronous nonisolated context". Adding
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` to the test target takes `CadenceTests` from **611
  errors to 0**, measured. It also takes `CadenceUITests` from 0 to **11**, all of the form
  "main actor-isolated instance method 'setUpWithError()' has different actor isolation from
  nonisolated overridden declaration" — `XCTestCase` overrides, a handful of `nonisolated` keywords.
  That asymmetry is the whole shape of the problem: the two test targets want opposite defaults.

  **What a flip needs, in order.** (1) Fix `CadenceDataExportService`'s key-path table — and note
  `nonisolated(unsafe)` was only a probe, not a proposal. (2) Clear the 10 app warnings; they are
  real isolation questions in scheduling, panel and EventKit callbacks, not cosmetics, and the
  zero-warning baseline is worth more than the language mode. (3) Set the test targets' actor
  isolation deliberately and re-measure — and consider that making every `@Test` main-actor is a
  behavioural change to the suite, not just a compile fix. (4) iOS stays on 5.0 until [T-115]'s
  compiler crash clears, whatever macOS does.

  **A partial flip is available and is the recommendation *when* the above is done, not now.**
  `SWIFT_VERSION` is per-target, `CadenceMCPServer` has been 6.0 beside 5.0 targets all along
  without splitting anything, and `CadenceWidgets` compiles under Swift 6 today with 0 errors and 0
  warnings. So "two dialects" is already the status quo and costs nothing new. What a macOS-only
  flip *would* split is the app target itself — one module built two ways per platform — which is
  the one combination worth refusing: `Cadence/Shared/` and `Cadence/Services/` compile into both,
  so an isolation fix accepted by the macOS flip would still have to satisfy the iOS Swift 5 build,
  and a regression introduced on the iOS side would be invisible until [T-115] cleared. Flip
  `CadenceWidgets` and (after step 3) `CadenceTests` if a partial flip is wanted early; leave the
  app target alone until both platforms can move together.


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
  **DECIDED 2026-08-26: investigate and report, do not flip.** The user's call. Measure each target's
  error and warning count under Swift 6 and re-test whether the blocker is still real against the
  current toolchain, then bring a recommendation. A flip that adds concurrency warnings destroys the
  zero-warning baseline, which has caught real regressions repeatedly — that baseline is worth more
  than the language mode.
  errors fixed the iOS module is diagnostically clean, and swift-frontend then crashes in IRGen on a
  reabstraction thunk carrying an `(any Actor)?` parameter. Attributed, not assumed: pristine HEAD
  with those same errors removed a different way crashes identically with zero diagnostics, and
  pristine HEAD under Swift 5 builds clean. Xcode 26.6 / Swift 6.3.3. Recheck on a toolchain bump.

  **STILL REAL — reproduced 2026-08-26 on the installed toolchain (Xcode 26.6, Apple Swift version
  6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)), twice, in two compilation modes.** This was worth
  re-testing rather than inheriting: the toolchain had not moved, and it has not. Recipe:
  `-scheme Cadence -destination 'generic/platform=iOS Simulator' SWIFT_VERSION=6.0 build` over an
  isolated tree, with `CadenceDataExportService`'s key-path table made `nonisolated(unsafe)` in the
  scratch copy so the module gets past `EmitSwiftModule` (see [T-122]). The iOS module is then
  **diagnostically clean — 0 errors, 1 warning** — and swift-frontend aborts anyway:

  ```
  4.	While evaluating request IRGenRequest(IR Generation for file ".../Cadence/iOS/iOSCalendarView.swift")
  5.	While emitting IR SIL function "@$s7Cadence0A19CalendarMonthDetailOScA_pSgIeAghyg_ACIeAghn_TR".
  ```

  which `swift-demangle` reads as `reabstraction thunk helper from @escaping @isolated(any)
  @callee_guaranteed @Sendable (@unowned Cadence.CadenceCalendarMonthDetail, @guaranteed
  Swift.Actor?) -> () to @escaping @isolated(any) @callee_guaranteed @Sendable (@in_guaranteed
  Cadence.CadenceCalendarMonthDetail) -> ()` — the `(any Actor)?` reabstraction thunk this ticket
  named. Two details the earlier write-up did not have:

  - **It is not one unlucky type.** Under `SWIFT_COMPILATION_MODE=wholemodule` the same abort fires
    on a *different* thunk, `@$sSSScA_pSgIeAghgg_SSIeAghn_TR` (the `String` one). Whatever is wrong
    is general to `@isolated(any)` thunk emission for this module, not to `CadenceCalendarMonthDetail`,
    so "find the one call site and rephrase it" is unlikely to be a workaround.
  - **The stack names the failure**, and it is an assertion, not a segfault:
    `IRGenSILFunction::visitFullApplySite` → `SyncCallEmission::setArgs` →
    `llvm::SmallVectorBase<unsigned int>::grow_pod` → `report_at_maximum_capacity` →
    `llvm::report_fatal_error` → `abort`. An LLVM `SmallVector` exceeding its maximum capacity while
    setting call arguments. Worth quoting verbatim in any bug report filed against the toolchain.

  Control confirmed in the same session: the identical tree on Swift 5 builds the iOS target to
  `** BUILD SUCCEEDED **`, exit 0, 0 errors, 0 warnings — so this is the language mode, not the
  sources. macOS emits IR for the same shared modules with no trouble, so it is iOS-only.
  Recheck on the next toolchain bump; there is nothing to fix in Cadence.

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
- [T-280] **The iOS half of T-279 is fixed by construction and unverified on a device.**
  `iOSMarkdownTextView.canPerformAction` now returns `true` for `paste:` when
  `UIPasteboard.general.hasImages`, mirroring the macOS `readablePasteboardTypes` widening. The
  macOS half was measured before *and* after against a real clipboard holding a real PNG; the iOS
  half has only an iOS **build**. `Cadence/iOS/` is inside `#if os(iOS)` and invisible to the
  macOS-built `CadenceTests`, so there is no unit-test route to it. The predicate to check on a
  simulator is one value: with an image on the pasteboard and the caret in a note, **Paste** appears
  in the edit menu and inserts the picture. Do not close this by reading the diff — a correct
  `paste(_:)` override that was never dispatched is exactly how the macOS bug survived.

- [T-281] **Two iOS note-editor sheet headers are one header, written twice.** From the [[T-73]]
  split. `iOSEventNoteEditorSheet.header` (`Cadence/iOS/iOSEventNoteEditorSheet.swift`) and
  `iOSLinkedNoteEditorSheet.header` (`Cadence/iOS/iOSMarkdownReferenceSupport.swift`) are now
  **line-for-line identical**: `SectionEyebrowLabel(text:)`, a title at `isRegularWidth ? 24 : 22`
  bold with `lineLimit(2)`, `frame(maxWidth: .infinity, alignment: .leading)`,
  `frame(maxHeight: isRegularWidth ? .infinity : nil, alignment: .topLeading)`,
  `padding(.horizontal, isRegularWidth ? 20 : 18)`, `padding(.vertical, isRegularWidth ? 20 : 14)`,
  `background(Theme.surface)`. `af03fb1` made them identical rather than shared and deferred the
  extraction to "a future pass … if a third near-copy appears" — but the reason it recorded is
  about the two sheets' *surrounding chrome* (toolbar items, AI actions button, calendar sync),
  which is not the thing that would be extracted. Two identical bodies is exactly the state the
  event-note header was already in once, before its 12pt caption / fixed-24pt title / 4pt spacing
  drifted away from the linked-note sheet's.
  Done: one `iOSNoteEditorSheetHeader(eyebrow:title:)` view, both sheets calling it, neither file
  spelling the ramp again, and a source-scanning test that fails if either re-declares the block.

- [T-282] **The iPad's corner `+` carries the same palette, pointing the only way it can.**
  **VERIFIED 2026-08-26 — keep open. The value half is strongly pinned; the device run still has not
  happened.** Four mutations caught, including unifying the corner arc and weakening the drag arm,
  and the old system-drag path is gone with zero live references. Placement is pinned as
  *deliberately different* in both directions.
  Still outstanding, and it is the one thing the ticket was left open for: **nobody has driven an
  iPad.** The verifier was blocked all session — both booted simulators were held by live agents,
  and the claim script correctly refuses to reclaim a device with live operations on it.
  One specific risk only a device answers: `iOSCaptureRadialMenuOverlay`'s own comment says it sits
  at the **shell's** level so a palette is not clipped by a 46pt bar row — but on iPad the host is
  applied to the page's content, not the shell. The arc opens up-and-left so it probably clears.
  "Probably clears" is what a simulator run is for.
  From the [[T-73]] / [[T-170]] split, and the one genuine "control present at one width and absent
  at the other" that audit found. [[T-171]] had shipped the hold-for-palette gesture on
  `iOSCaptureRadialMenuButton`, whose **only** caller was `iOSCompactTabShell` — so holding the
  centre `+` on iPhone offered `CadenceCaptureAction`'s three segments (Task / Event / Note) and a
  drag onto a drop target, while the iPad's corner `+` (`iOSFloatingCreateTaskButton` →
  `iOSCircularAddButton` + `.iOSNewTaskDragSource`) tapped straight into `iOSCreateTaskSheet` and
  could capture nothing but a task. **Confirmed against the source before any of it was rebuilt.**
  The corner button now renders that same `iOSCaptureRadialMenuButton`.
  **What stayed different, deliberately, is the arc — and only the arc.** A button 50pt from the
  trailing edge cannot draw a semicircle: two of its three segments would be off the display. So
  `CadenceCapturePalettePlacement` gives `.bottomTrailing` a quadrant opening up and to the left,
  and a wider `layoutRadius` because three tiles packed into 90° instead of 180° would otherwise
  overlap — the tile width is published now so that claim is a test rather than a taste. The hold
  delay, the drag slop, the dead zone and the margins the outer and escape rings keep past the tiles
  are all the *same value*, asserted field by field.
  **The three outcomes do coexist on that button, and the reason is the reason T-171 gives.** The
  iPad's `+` carried a system `.onDrag`, and `UIDragInteraction`'s lift *is* a ~350ms long press —
  the same window the palette wants — so the two could never have shared a touch. It carries
  `CadenceCapturePressResolver`'s one `DragGesture` instead, exactly as the phone's does. Verified
  on a booted iPad simulator: press-and-move drags, press-and-hold opens the palette, and moving
  inside the radius slides between segments.
  **Two things went with it rather than being left beside it.** The system drag lost its last
  source, so `iOSNewTaskDragSource`, the drop target's `.onDrop`, `CadenceTaskDropPayload`,
  `CadenceTaskDropCoordinator` and `UTType.cadenceNewTaskDrag` are deleted — a sourceless second
  path into the same insertion ghost is how a comment ends up claiming "two mechanisms, on purpose"
  about one. And the three composers a finished press can ask for moved out of `iOSCompactRootShell`
  into `.iOSCaptureHost(_:)`, which both placements apply, because copying that routing to the iPad
  is the near-copy this repo keeps paying for.
  `iOSCircularAddButton`'s doc comment claimed the two buttons were "the same action in deliberately
  different *places*" while they were not. It now says which parts are shared (the face, the gesture,
  the composers, the feel) and which the placement chooses (the diameter, the corner inset, the arc)
  — and the `Button` wrapper of that name is gone, the name having moved down to the circle it
  always described.

- [T-283] **Three `iPad*` names for views that render on every device.** From the [[T-73]] /
  [[T-170]] split — a naming defect, not a layout one, and the kind that makes the next agent write
  the second copy. `iPadInboxView` is the Inbox at every width and **its own doc comment says so**
  ("the name is now simply wrong: this is the Inbox on every device"); `iPadTodayView` is Today at
  every width and picks its layout from `CadenceTodayLayoutSupport.layout(...)` inside;
  `iPadTodayCompactViews.swift` declares `iOSCompactTodayView` / `iOSCompactTodayEmptyState` /
  `iOSCompactSampleDataCard` and `iPadTodayScheduleViews.swift` declares `iOSSchedulePanel` — two
  files whose names claim a device none of their types is limited to.
  **Not in scope, and deliberately so:** `iPadTodayTaskHeader`, `iPadTodayInspectorSwitcher` and
  `iPadTodaySidePanel` really are two-pane-only, which only regular width reaches.
  Done: `iOSInboxView` and `iOSTodayView` (with their ~20 call sites and the four test files that
  name them), `iOSTodayCompactViews.swift` and `iOSTodaySchedulePanel.swift`, and no `iPad`-prefixed
  symbol left that a compact width can reach.

- [T-284] **Six spellings of one uppercase eyebrow label, at four kernings.** From the [[T-123]]
  **VERIFIED 2026-08-26 — keep open, narrowly. Well pinned; needs one look.** The tier folded in as
  `SectionEyebrowLabel.Size`, with kerning derived as `fontSize * kerningRatio`. The previous
  audit's judgement was half-kept on purpose: sizes preserved, kernings converged. The 19
  standard-tier sites are bit-identical (`10 * 0.08 == 0.8` exactly).
  **The unlooked-at change is letterspacing at 8 labels, all still 9pt** — six tightened kernings
  converge on 0.72 (one from 0.45, a 60% increase) and two labels that had *no* tracking now have
  it. Three mutations caught, including a negative sweep against a re-hand-rolled spelling.
  This is the cheapest of the four to close: one screenshot pass over those 8 sites.
  split, and exactly the "one hand-rolled UI pattern (a header, a label style, a literal list) at a
  time" unit that entry narrowed itself to. `SectionEyebrowLabel` is the app's one eyebrow — 10pt
  semibold, kerning 0.8, and `fontSize` is published because things drawn beside it have to agree —
  and macOS reads it in 19 files. Beside it, at 9pt semibold `Theme.dim`, sit:
  `macOS/CadenceCalendarPicker.swift:84` (0.6), `macOS/Views/ContainerPickerSupportViews.swift:115`
  (0.6), `macOS/Views/AIActionsSupportViews.swift:443` (`NoteActionSubsectionLabel`, 0.7),
  `macOS/Views/TaskInspectorWorkflowSupportViews.swift:483` (0.45, with a comment computing
  "~0.05em at 9pt"), `macOS/Views/GoalAttachWorkSheet.swift:85` (no kerning at all), plus
  `TaskInspectorFieldRowMetrics.groupLabelKerning` (0.54) and — in a **shared** component —
  `Shared/Components/EstimatePickerControl.swift:139` (0.54). iOS has one too:
  `iOSContainerChoicePopover.groupLabel` in `iOS/iOSChoicePicker.swift:66`, 9pt, no kerning.
  Two constants re-type the shared numbers rather than reading them:
  `SidebarMetrics.contextHeaderFontSize`/`contextHeaderKerning` are literally `10` and `0.8`.
  There may be a real second tier here — a popover eyebrow can legitimately be smaller than a page
  eyebrow — but four kernings is not a tier, it is drift.
  Done: one named spelling for the 9pt tier (a `SectionEyebrowLabel` size parameter or a
  `CadenceEyebrowMetrics` pair), every call site above reading it, `SidebarMetrics`' two constants
  deriving from `SectionEyebrowLabel.fontSize`, and a source scan that fails on a new inline
  `.font(.system(size: 9, weight: .semibold))` over an `.uppercased()` `Text`.

- [T-285] **macOS re-spells `CadenceEmptyStateCopy`, and hand-rolls `EmptyStateView` for the
  Inbox.** From the [[T-123]] split. `Shared/CadenceEmptyStateCopy.swift` exists because three pairs
  of screens said the same thing in different words; it has **eight iOS references and zero macOS
  ones**. So the Inbox reads "Inbox is clear / Capture tasks here before scheduling or filing them."
  on iOS and "Inbox is empty / Unsorted tasks and Apple Reminders appear here.\nCreate something to
  get started." on macOS, and All Tasks reads "No active tasks / Tasks you create on iPhone, iPad,
  or Mac will collect here." against "No tasks yet / Create a task to get started"
  (`macOS/Views/TasksListView.swift:299`). Worse, `InboxEmptyStateView`
  (`macOS/Views/InboxSupportViews.swift:294`) is a hand-rolled second `EmptyStateView`: its own
  72pt `Theme.blue.opacity(0.08)` circle, its own 30pt light glyph, its own 16/13pt type ramp —
  while `EmptyStateView` is the shared component macOS already uses in eleven other files.
  **Not in scope:** `FocusPickerSupportViews.emptyState` is a searching-vs-empty popover state, a
  different job from a page's empty state.
  Done: `InboxEmptyStateView` deleted in favour of `EmptyStateView`, macOS's Inbox and All Tasks
  empty states reading `CadenceEmptyStateCopy`, and the copy decided once per screen rather than
  once per platform.

- [T-286] **Seven macOS Settings sections are still outside the shared row vocabulary.** From the
  [[T-123]] split — currently recorded **only inside the Done entry for [[T-20]]**, which is where
  remaining work goes to be forgotten. T-20 moved the settings vocabulary into
  `Shared/Components/CadenceFieldRows.swift` + `CadenceChoicePicker.swift` and converted Navigation,
  Calendar → Work Hours, AI and About completely; Account, Data Safety, Contexts, Lists and Sidebar
  took the hairline only. Untouched, and confirmed at `36be8ba` — zero references to
  `CadenceFieldSection` / `CadenceFieldRow` / `CadenceSettingsField` in any of them:
  `SettingsTagsSection.swift` (493 lines, and still carrying its own two spellings of the inset
  well), `SettingsTemplatesSection.swift` (323), `SettingsSupportViews.swift` (427),
  `SettingsRemindersSection.swift` (151), `SettingsSyncSection.swift` (85),
  `SettingsNotificationsSection.swift` (78), `SettingsAppearanceSection.swift` (24).
  They are *clean* — no `Picker(.menu)`, no `Divider().background(...)`, both swept by tests — just
  not in the vocabulary, so a settings row is still two heights and two spellings depending on which
  category you opened.
  Done: those seven built on `CadenceFieldSection` / `CadenceFieldRow` / `CadenceSettingsField` at
  `CadenceSettingsRowMetrics.rowHeight`, `SettingsTagsSection`'s two private inset wells deleted,
  and `SettingsSharedVocabularyTests` extended to name them so the next one cannot regress.

- [T-287] **The `~` list-search panel is implemented twice on macOS.** From the [[T-123]] split.
  `CLAUDE.md` already records this as "a standing violation of the 'one shared component over
  near-copies' rule, recorded here so it is not mistaken for a deliberate split" — and it has never
  been a ticket, so it has stayed standing. `macOS/Views/QuickCreateChoicePopover.swift` carries
  `tildeFlatContainers` (288), `selectTildeContainer` (318), `selectTildeContainerItem` (324),
  `clampTildeHighlight` (416) and its own `TildeContainerItem`; `macOS/Views/TaskTitleEntryField.swift`
  carries the same five under the same names plus `TaskTitleTildeContainerItem`. They share
  `TildeContainerPickerRow` and nothing else — including the silent `normalizeSelectedSection()`
  that both must perform after a container change, which is the half most likely to be fixed in one
  copy only.
  Done: one panel — the container list, the highlight arithmetic, the selection and the section
  normalisation — read by both the title field and the drag-create popover, one item type, and a
  test that fails if either file re-declares `tildeFlatContainers`.

- [T-288] **Four whole-file `#if os(macOS)` components sit in `Shared/Components/`.** From the
  [[T-123]] split. That folder is the inventory `CLAUDE.md` tells an agent to read *before* writing
  a new shared view, so a macOS-only file in it reads as available and is not — the T-173
  `CompactTagStrip` failure mode with the platform fence supplying the misdirection.
  `CadenceScrollElasticity.swift` (49 lines) is genuinely AppKit (`NSViewRepresentable`,
  `NSScrollView.Elasticity`) and simply lives in the wrong folder. The other three import
  **`SwiftUI` and nothing else** — `CadenceButtons.swift` (237), `CadenceContextPicker.swift` (293),
  `CommitmentSharedViews.swift` (224) — i.e. 754 lines behind a guard that nothing in them needs,
  which is the same shape as `PrivacyDataResetService`, `ListDeleteHelpers`, `RemindersManager` and
  `CadenceFocusBundleSupport` before each was lifted. `CadenceContextPicker` is the one with a live
  counterpart to converge on: `CadenceContextPickerButton` has two macOS readers (`CreateGoalSheet`,
  `HabitsFormSupportViews`) while iOS spells the same "pick a context" control twice more, in
  `iOSListEditorViews.swift:124` and `iOSTrackingEditorSheets.swift:167`/`:385`.
  Done: no whole-file `#if os(macOS)` under `Shared/Components/` — the AppKit one moved to
  `Cadence/macOS/`, and each of the other three either unfenced with its iOS counterpart routed
  onto it, or moved to `macOS/Views/` with the reason recorded. A test asserting the folder holds
  no whole-file platform fence is what keeps it settled.

## Done

Moved to [`TODO_DONE.md`](TODO_DONE.md) on 2026-08-26 — 220 entries, with their reasoning and shipping SHAs intact.
The working list was ~82k tokens and two thirds of it was finished work. **Search the archive
before filing**: this list has had the same ticket re-reported more than once.

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
