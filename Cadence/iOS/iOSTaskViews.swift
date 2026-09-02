#if os(iOS)
import SwiftData
import SwiftUI

// `iOSTaskRowDensity` is gone. It was a second size axis, chosen per call site, that a phone could
// set two ways in two tabs of one tab bar — and did: Today was `.compact` while Inbox and All Tasks
// were `.regular`, which on a phone meant one-line titles here and two-line titles there and almost
// nothing else. The row's measurements are `CadenceTaskRowMetrics` now, read from
// `horizontalSizeClass` and from nothing else; that file carries the full accounting.

struct iOSTaskRow: View {
    @Bindable var task: AppTask
    /// Off for surfaces that are already scoped to one list, where naming it on every row is
    /// noise — the same knob, and the same reason, as `KanbanCard.showsContainerChip` on macOS.
    var showsContainer: Bool = true
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    // No `@Query` here on purpose. A list can have twenty of these rows alive at once, and a
    // task/area/project query per row meant twenty live fetches plus twenty observation
    // registrations re-firing on any write — for data only the context menu and the recurrence
    // dialog ever read. The queries now live in the context-menu *content* (only instantiated
    // when the menu is presented), the same trick `KanbanContainerMetaButton` documents.
    //
    // T-201: **the row does not present the inspector.** It used to carry `@State showDetail` and a
    // `.sheet(isPresented:)`, which tied the panel's lifetime to this row's — and this row lives
    // inside a filtered `ForEach`, so cancelling, restoring or completing a task from inside the
    // panel removed the row and closed the panel with it. The host is above the page
    // (`iOSTaskInspectorHost`); all the row does is ask.
    @Environment(\.iOSTaskInspector) private var taskInspector
    @State private var showDeleteConfirmation = false
    /// T-365. The delete can fail, so the row needs somewhere to say so. It is a flag rather than
    /// a `String?` because there is exactly one sentence for this and it lives on the mutation
    /// helper — the row reads it, it does not word it.
    @State private var deleteFailed = false
    /// One flag for both of this row's move affordances — the list chip's popover and the context
    /// menu — because both dismiss themselves on the tap and neither can report a refusal itself
    /// (T-702). See `iOSTaskMoveFailureAlertModifier`.
    @State private var moveFailed = false
    @State private var pendingRecurrenceRule: TaskRecurrenceRule?

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var metrics: CadenceTaskRowMetrics {
        .metrics(isRegularWidth: isRegularWidth)
    }

    /// T-147. "Over, however it ended" — the shared `CadenceTaskCompletionState.isSettled`, which
    /// is also what tints the circle beside this title, so the ring and the title cannot disagree
    /// about whether a task is finished.
    ///
    /// It was `task.isDone` alone, so a **cancelled** task drew full-contrast and un-struck: the
    /// glyph said `xmark.circle.fill` in `Theme.dim` while the title beside it read exactly like
    /// live work. `MacTaskRow` has spelled this `isDone || isCancelled` all along. The difference
    /// mattered nowhere until the completed queries started admitting cancelled tasks, at which
    /// point a Completed section would have shown one row struck through and the next one not.
    private var isSettled: Bool {
        CadenceTaskCompletionState.resolve(task: task).isSettled
    }

    var body: some View {
        rowContent
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(minHeight: 44)
            // One layer, one radius: the divider is the row's only chrome, at the same weight
            // `MacTaskRow` draws its bottom hairline.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.22))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openDetail()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens task details")
            .contextMenu {
                iOSTaskRowContextMenu(
                    task: task,
                    openDetail: openDetail,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    moveFailed: $moveFailed,
                    pendingRecurrenceRule: $pendingRecurrenceRule
                )
            }
            // Not `.swipeActions`: that is a `List`-row modifier, and eight of this row's
            // eighteen call sites render it inside a `ScrollView`/`LazyVStack`, where SwiftUI
            // discards it without a word. The same row swiped on Today's iPad column and not on
            // iPhone Today. This container works in either host, so all eighteen behave alike —
            // including the `List`-hosted ones, which were switched over too rather than left on
            // a second, near-identical mechanism.
            .iOSSwipeActions(
                leading: iOSTaskRowSwipeActions.leading(task: task, modelContext: modelContext),
                trailing: iOSTaskRowSwipeActions.trailing(
                    task: task,
                    modelContext: modelContext,
                    requestDelete: { showDeleteConfirmation = true }
                )
            )
            // The destination half of drag-to-create. A row is the drop target because it is the
            // only thing on an iOS task surface that reliably knows its group: grouping here is by
            // section, by date or by list, and a row inside such a group carries that group's
            // defining attribute by construction. `CadenceTaskDropSupport.dropKey(for:)` documents
            // what it hands over and what it withholds; it is called at drop time so the seed
            // reflects the row as it is then, not as it last rendered.
            //
            // **The row itself takes no highlight.** It is being *read* for its placement, not
            // acted on, and a selection-style fill said the opposite. What opens instead is a ghost
            // row underneath it — see `iOSNewTaskDropTargetModifier` for why the gap is always
            // below and never split by hover position.
            //
            // Applied **after** the tap, context menu and swipe container on purpose: those belong
            // to the row, and wrapping them in the ghost's `VStack` would quietly hand the ghost a
            // tap target and a swipe container of its own.
            .iOSNewTaskDropTarget(
                horizontalInset: metrics.horizontalPadding,
                listName: { task.containerName }
            ) {
                CadenceTaskDropSupport.dropKey(for: task)
            }
            .iOSTaskRowRecurrenceScopeDialog(
                task: task,
                pendingRecurrenceRule: $pendingRecurrenceRule
            )
            .alert("Delete Task?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive, action: deleteTask)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the task and its subtasks.")
            }
            // The other half of that confirmation, and the same modifier `iOSTaskDetailSheet`
            // applies — see `iOSTaskDeleteFailureAlert` for why the two are one call rather than
            // two copies that a test asserts are equal. The promise it makes: the rollback put the
            // task back, so nothing was removed.
            .iOSTaskDeleteFailureAlert(isPresented: $deleteFailed)
            // The move's equivalent, and the same argument: the list chip's popover and the
            // context menu both close themselves on the tap, so a refused move had nowhere to be
            // reported and the row simply stayed where it was (T-702).
            .iOSTaskMoveFailureAlert(isPresented: $moveFailed)
            .onAppear(perform: handlePendingDeepLink)
            .onChange(of: deepLinkManager.pendingTaskID) { _, _ in
                handlePendingDeepLink()
            }
    }

    /// Completion circle, the task, and the estimate — in that order, with nothing at the trailing
    /// edge but the estimate.
    ///
    /// There is **no disclosure chevron**. It said nothing the row's own tappability does not, and
    /// it occupied the one piece of the row a finger reaches for last. The estimate took its place:
    /// an estimate is a property of the task like its priority, and it has no business in the middle
    /// of the date chips.
    private var rowContent: some View {
        HStack(alignment: .top, spacing: metrics.contentSpacing) {
            completionButton
            taskSummary

            if task.estimatedMinutes > 0 {
                iOSTaskRowEstimateChip(task: task)
            }
        }
    }

    /// The circle carries priority and nothing else, exactly as `MacTaskRow`'s does — and once a
    /// task is done every priority converges on `Theme.doneFill`. It used to fall back to the
    /// *container* colour for an unprioritised task, so one glyph meant two different things.
    ///
    /// `iOSExpandedHitArea` gives the glyph a 44pt touch target without letting it take 44pt of
    /// layout, which would shove the title across the row.
    private var completionButton: some View {
        // **The name is keyed on what a tap does, not on the state (T-611).** It was
        // `isFinishedTask ? "Mark task todo" : "Complete task"` — two strings this file spelled for
        // itself, where macOS's identical control reads
        // `CadenceTaskCompletionState.accessibilityActionLabel`. Reading the shared answer off the
        // glyph's own state also closes the wording gap: a settled task now says "Reopen task" on
        // both platforms, and the five branches stay in one place, which matters because on macOS
        // the mid-fill states genuinely change what a second tap does.
        let glyph = CadenceTaskCompletionGlyph.resolve(task: task)
        return Button {
            toggleCompletion()
        } label: {
            iOSTaskCompletionCircle(
                glyph: glyph,
                diameter: CadenceTaskRowMetrics.completionCircleDiameter
            )
            .frame(width: metrics.completionGlyphSize, height: metrics.completionGlyphSize)
            .iOSExpandedHitArea((44 - metrics.completionGlyphSize) / 2)
        }
        .buttonStyle(.iosPressable)
        .accessibilityLabel(glyph.state.accessibilityActionLabel)
    }

    private var taskSummary: some View {
        VStack(alignment: .leading, spacing: metrics.summarySpacing) {
            // `CadenceTaskRowMetrics.titleLineLimit`, not a per-width or per-host number. Today used
            // to truncate to one line while the next tab along wrapped to two, and it is the day's
            // planning screen that could least afford to hide half a title.
            Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                .font(.system(size: metrics.titleFontSize, weight: .medium))
                .foregroundStyle(isSettled ? Theme.dim : Theme.text)
                .strikethrough(isSettled, color: Theme.dim)
                .lineLimit(CadenceTaskRowMetrics.titleLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let secondaryLine {
                Text(secondaryLine)
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(Theme.dim.opacity(isSettled ? 0.58 : 0.82))
                    .lineLimit(metrics.secondaryLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            taskBadges

            // Both widths carry the same *elements*; only spacing and type scale change. Tags used
            // to be dropped at compact width, which meant an iPhone's Today row and an iPad's
            // Today row disagreed about what a task has on it rather than about how much room it
            // gets to say it.
            tagScroller

            subtaskRows
        }
    }

    /// The unfinished subtasks, as rows beneath the task, capped with a "+N more" line.
    ///
    /// This replaces a `0/3` chip that named a count of things to do without naming one of them, so
    /// a checklist was only readable by opening the task. The cap exists because uncapped was tried
    /// and measured: see `CadenceTaskPresentationSupport.rowSubtaskLimit`. The overflow line opens
    /// the inspector rather than toggling anything — it is "see the rest", not a fourth checkbox.
    ///
    /// Nothing is listed under a finished task: a completed row's leftover checklist items are not
    /// work any more, and the Completed sections these rows appear in would otherwise fill with
    /// tappable items belonging to tasks that are over. That guard was spelled here, and is now in
    /// `listedSubtasks(for:)` with the cap — the board cards that gained a subtask list under T-173
    /// need it for the same reason and must not each remember it.
    @ViewBuilder
    private var subtaskRows: some View {
        let subtasks = CadenceTaskPresentationSupport.listedSubtasks(for: task)
        if !subtasks.isEmpty {
            VStack(spacing: 0) {
                ForEach(subtasks) { subtask in
                    iOSTaskRowSubtaskRow(subtask: subtask)
                }

                if let hidden = CadenceTaskPresentationSupport.unlistedSubtaskCount(for: task) {
                    Button(action: openDetail) {
                        Text(CadenceTaskSurfaceOptions.moreLabel(hidden: hidden))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .frame(minHeight: 30)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.iosPressable)
                    .accessibilityLabel("Show \(hidden) more subtasks")
                }
            }
        }
    }

    /// Wraps rather than scrolls. This was a horizontal `ScrollView`, which could not work here:
    /// nested inside the page's vertical scroll and under the row's own tap gesture — and now its
    /// swipe gesture too — the outer gestures always won, so the strip never scrolled and every
    /// chip past the right edge was unreachable rather than merely off-screen. Wrapping is
    /// affordable because the colour pass left a typical row carrying two to four chips; a fully
    /// annotated task costs one extra line, which is cheaper than hiding what it says.
    ///
    /// `lineSpacing` is **derived, not chosen**. Every chip in here expands its hit area by
    /// `iOSTaskAttributeChipSize.row.hitInset` on each edge to reach 44pt without taking 44pt of
    /// layout, and those expanded regions are invisible: with a decorative 3-4pt line gap, a chip on
    /// the second line overlapped the chip above it and — being drawn later — answered taps aimed at
    /// it. Twice the inset is the smallest gap at which every chip owns its own target.
    private var taskBadges: some View {
        CadenceWrappingHStack(
            spacing: metrics.badgeSpacing,
            lineSpacing: iOSTaskAttributeChipSize.row.hitInset * 2
        ) {
            taskBadgeContent
        }
    }

    /// Notes preview only. The container used to be glued onto the front of this string
    /// (`"Errands - buy milk"`), which read as prose and left the list a task belongs to
    /// unclickable and indistinguishable from its notes. It is a chip now, like macOS's.
    private var secondaryLine: String? {
        let preview = CadenceTaskPresentationSupport.plainPreviewText(
            from: task.notes,
            limit: metrics.notesPreviewLimit
        )
        return preview.isEmpty ? nil : preview
    }

    /// Row metadata. **Colour is reserved for the exceptional**: every item is `Theme.dim`, icon
    /// and text alike, so a red thing in a row means something is actually wrong. Only three
    /// things earn a hue — an overdue deadline, a do date already in the past, and a task that is
    /// actively In Progress. Everything else (the list, the goal, the repeat marker, a do date that
    /// is merely *today*) is ordinary and reads as chrome, and that stays true now the chips are
    /// controls: a plate says "tappable", not "urgent".
    ///
    /// Before this, a task with four attributes rendered four tinted icons — amber sun, purple
    /// repeat, green checklist, the goal's own colour — and a genuinely late deadline had to
    /// compete with a recurrence glyph. On the Today screen every row carried the amber sun, which
    /// is the definition of a colour that says nothing.
    ///
    /// Priority is deliberately absent: it is the completion circle's job here exactly as it is on
    /// macOS, and a chip repeating it was a second affordance for one field.
    ///
    /// **Every chip opens the picker for the field it names** — the list chip the list picker, a date
    /// chip its month grid, and so on. They used to be read-only labels, so changing the list a task
    /// was in from a list *of* tasks meant opening the row and coming back. Tapping anywhere that is
    /// not a chip still opens the task inspector.
    ///
    /// Two chips were dropped rather than wired up. The **subtask tally** is now a set of rows under
    /// the task, and the **notes** chip only ever appeared when the secondary line did not — which no
    /// width does — so in a strip that is now entirely controls it would have read as one more
    /// control that did nothing.
    @ViewBuilder
    private var taskBadgeContent: some View {
        if showsListContextChip {
            iOSTaskRowContainerChip(task: task, moveFailed: $moveFailed)
        }

        // **Read-only, and deliberately not a chip.** The four-option status picker this used to
        // open is deleted (T-74): `todo` and `done` are what the completion circle already does,
        // `cancelled` has its own control, and a picker offering all four was a third affordance
        // for a field with two. What remains is a *reader* — rows written by an earlier build (and
        // the sample data) still hold `.inprogress`, and they must keep saying so.
        //
        // So it renders as a bare `iOSTaskMetaLabel` rather than a plated chip: in this strip a
        // plate now means "tappable", and a plate that opened nothing would be exactly the dead
        // control the plates exist to rule out. Starting and stopping work stays in the task
        // inspector, where `iOSTaskStatusActionsSection`'s Start/Stop button owns the value.
        if task.status == .inProgress {
            iOSTaskMetaLabel(
                systemImage: task.status.systemImage,
                text: task.status.label,
                tint: Theme.blue
            )
        }

        // The day, never the slot: "9:30 – 10 AM" is gone from this row. See
        // `CadenceTaskPresentationSupport.scheduledDayLabel(for:)` — and note the cost, which was
        // accepted deliberately: on a phone there is no timeline beside the list, so the day's plan
        // now reads only on the Today timeline pane and in the task inspector.
        if datePlan.drawsDoDateChip {
            iOSTaskRowDateChip(
                task: task,
                field: .doDate,
                title: CadenceTaskPresentationSupport.scheduledDayLabel(for: task),
                tint: isOverdo ? Theme.red : Theme.dim
            )
        }

        if datePlan.drawsDueDateChip, let dueUrgency {
            iOSTaskRowDateChip(
                task: task,
                field: .dueDate,
                title: CadenceTaskPresentationSupport.dueDateLabel(for: task),
                tint: dueUrgency == .overdue ? Theme.red : Theme.dim
            )
        }

        if task.recurrenceRule != .none {
            iOSTaskRowRepeatChip(task: task, pendingRecurrenceRule: $pendingRecurrenceRule)
        }

        if let goal = task.goal {
            iOSTaskRowGoalChip(task: task, goal: goal)
        }
    }

    /// Every row that names its list gets the chip — **including an Inbox task**, which reads
    /// `Inbox`.
    ///
    /// It used to be hidden when `containerName` was empty, which was right for a read-only label:
    /// a chip saying "Inbox" told you nothing the absence of one did not. Now the chip *is* the list
    /// picker, and hiding it left the tasks most in need of filing — the ones in the Inbox — as the
    /// only ones that could not be filed from the row. Same reasoning as macOS's
    /// `ContainerPickerBadge`, which shows the real name `Inbox` rather than reading as unset.
    ///
    /// `showsContainer` is still honoured: on a surface already scoped to one list, naming it on
    /// every row is noise, and there is nothing to choose.
    private var showsListContextChip: Bool {
        showsContainer
    }

    /// Same semantics as `KanbanCardComputedSupport.isOverdo`, which macOS's row and card both
    /// read: a finished task is never late, and the comparison goes through
    /// `DateFormatters.dayOffset` rather than a string compare so both platforms answer alike.
    /// That helper is behind `#if os(macOS)`; the two should be folded into one shared classifier.
    ///
    /// There is no `isDoToday` companion any more. "Do today" was drawn amber, but on the Today
    /// screen that is every row — a colour that fires on the common case cannot mark an
    /// exceptional one.
    private var isOverdo: Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate) ?? 0) < 0
    }

    /// Tags keep the user's own colour — a tag colour is identity they chose, not decoration — so
    /// the strip is capped at three. `CadenceTagChip` spends that colour on the dot, the fill tint
    /// and the border and keeps the label on a `Theme` token, which is what lets three of them sit
    /// in a row without being the loudest thing on screen, and what leaves the label free to say
    /// **archived** — a fact this row could not show at all while the chip was a coloured capsule.
    @ViewBuilder
    private var tagScroller: some View {
        if !task.sortedTags.isEmpty {
            // Wraps, for the same reason `taskBadges` does: a horizontal `ScrollView` in a row this
            // gesture-heavy cannot be scrolled, so a long tag name pushed its neighbours somewhere
            // no touch could reach them.
            CadenceWrappingHStack(spacing: 6, lineSpacing: 4) {
                ForEach(task.sortedTags.prefix(visibleTagLimit)) { tag in
                    CadenceTagChip(tag: tag, size: .compact)
                }

                if task.sortedTags.count > visibleTagLimit {
                    CadenceTagOverflowBadge(count: task.sortedTags.count - visibleTagLimit, size: .compact)
                }
            }
        }
    }

    /// Which date chips this row draws — **`CadenceTaskPresentationSupport.rowDatePlan`'s answer,
    /// not this row's** (T-304). The sun and the flag were each drawn from their own check on their
    /// own field, so a task do-dated and due on the same day said that day twice, once per chip.
    /// When the two name one day the flag survives and the sun folds into it; the do date is still
    /// set from this row's context menu (`Do Date`) and from the task detail sheet.
    ///
    /// macOS reads the same answer from the same function. Which chip wins is a fact about a task,
    /// not about a platform.
    private var datePlan: CadenceTaskRowDatePlan {
        CadenceTaskPresentationSupport.rowDatePlan(for: task)
    }

    /// `CadenceDueUrgency` rather than an inline `dueDate < todayKey`: the inline spelling had no
    /// `isDone` guard, so a task completed after its deadline kept rendering a red flag badge
    /// telling the user a settled deadline was still urgent. macOS reads the same classifier.
    ///
    /// It says how loudly the deadline reads, once `datePlan` has said there is a chip at all: the
    /// plan decides *whether*, this decides *how*. `evaluate` returns `nil` only for an empty key,
    /// so the two agree on the one case they overlap.
    private var dueUrgency: CadenceDueUrgency? {
        CadenceDueUrgency.evaluate(dueDateKey: task.dueDate, isDone: task.isDone)
    }

    /// `CadenceTaskPresentationSupport.rowTagLimit`, not a local 3. macOS's row capped at 2, and a
    /// figure that lives in one row's `private var` is a figure the other row cannot read.
    private var visibleTagLimit: Int { CadenceTaskPresentationSupport.rowTagLimit }

    private func toggleCompletion() {
        CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext)
    }

    /// Attempt, then decide — the shape `iOSNoteDeleteConfirmationSheet.confirm()` uses. The
    /// delete returns `false` when its commit was refused and rolled back, and a row that ignored
    /// that reported a deletion the store never took.
    private func deleteTask() {
        deleteFailed = !CadenceTaskMutationSupport.delete(task, modelContext: modelContext)
    }

    private func openDetail() {
        taskInspector(task)
    }

    private func handlePendingDeepLink() {
        guard deepLinkManager.pendingTaskID == task.id else { return }
        openDetail()
        deepLinkManager.clearPendingTask(task.id)
    }
}

/// One piece of row metadata: an icon and its text, sharing **one** colour. No fill, because a
/// strip of filled capsules turns every attribute into an alert.
///
/// The icon and the text used to be tinted separately — icon for "which field this is", text for
/// "how urgent it is" — which meant a merely-scheduled task still drew an amber sun next to grey
/// words. An item is either ordinary, and entirely `Theme.dim`, or exceptional, and entirely the
/// colour that says so.
struct iOSTaskMetaLabel: View {
    let systemImage: String
    let text: String
    /// Icon *and* text. Neutral unless this item is one of the few that has earned a colour.
    var tint: Color = Theme.dim

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}

// `iOSTaskContainerChip` — the row's read-only list pill — is gone. The row's list chip is
// `iOSTaskRowContainerChip`, which is the shared `iOSTaskAttributeChip` plus the list picker, so a
// list can be changed from the row it is named on. The pill it replaced was a near-copy of that
// component's plate with its own paddings and no action.

struct iOSTaskListRow: View {
    @Bindable var task: AppTask
    var opacity: Double = 1
    var showsContainer: Bool = true

    var body: some View {
        iOSTaskRow(task: task, showsContainer: showsContainer)
            .opacity(opacity)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// Delegates to the shared `SectionEyebrowLabel` rather than re-spelling its size/weight/kerning —
/// this was a byte-for-byte copy of it with a tint, which is what the shared component's `tint`
/// parameter is for.
struct iOSTaskSectionHeader: View {
    /// The inset between a group's rows and the eyebrow of the next group. Exposed because
    /// `iOSTaskGroupHeader` draws the shared `CadenceTaskGroupHeading` and has to apply this
    /// itself — it is the *host's* spacing, not the heading's, which is why the shared component
    /// does not carry it.
    static let topPadding: CGFloat = 6

    let title: String
    let color: Color

    var body: some View {
        SectionEyebrowLabel(text: title, tint: color)
            .padding(.top, Self.topPadding)
    }
}

struct iOSTaskViewOptionsBar: View {
    @Binding var sortMode: CadenceTaskSortMode
    @Binding var showCompleted: Bool
    var completedCount: Int
    /// True on a band of its own, where the bar spans the pane and the two chips go to opposite
    /// ends. False when it is a *guest* on someone else's row — iPad Today puts it on the trailing
    /// edge of its page header — where an internal `Spacer` would fight the host's own for the
    /// leftover width and leave the sort chip floating in the middle of the row.
    var spreads = true
    @State private var showSortPicker = false

    /// **One size, at every width.** These two were 13pt/12pt-padded on a regular width and
    /// 12pt/10pt on a compact one, which is a chip that looks different on a phone than on a tablet
    /// for no stated reason — and this bar is a *guest* on iPad Today's header, so the same control
    /// changed size depending on which of two screens you had it open on. The app's chip vocabulary
    /// is already width-invariant: `iOSTaskAttributeChipSize` is 11pt in a row and 13pt in a strip
    /// on both. 13 is the size that matches `.standard`, which is what these are — a chip you tap,
    /// on a row of its own — and the phone is the harder touch target of the two, not the easier.
    private static let fontSize: CGFloat = 13
    private static let horizontalPadding: CGFloat = 12

    /// Both controls are the same neutral chip on the same radius, sized to a 44pt touch target.
    /// They used to be two different treatments for two peer controls — a blue-washed capsule
    /// beside a grey one — which read as one being an action and the other a state.
    var body: some View {
        HStack(spacing: 10) {
            Button {
                showSortPicker = true
            } label: {
                Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: Self.fontSize, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, Self.horizontalPadding)
                    .frame(minHeight: 44)
                    .background(Theme.surfaceElevated.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .buttonStyle(.iosPressable)
            .popover(isPresented: $showSortPicker) {
                iOSChoicePopoverList(
                    rows: CadenceTaskSortMode.allCases.map { mode in
                        iOSChoiceRow(value: mode, title: mode.title, color: Theme.blue)
                    },
                    selection: $sortMode,
                    isPresented: $showSortPicker
                )
            }

            if spreads {
                Spacer()
            }

            Button {
                showCompleted.toggle()
            } label: {
                Text(completedCount > 0 ? "Completed \(completedCount)" : "Completed")
                    .font(.system(size: Self.fontSize, weight: .semibold))
                    .foregroundStyle(showCompleted ? Theme.text : Theme.dim)
                    .padding(.horizontal, Self.horizontalPadding)
                    .frame(minHeight: 44)
                    .background(showCompleted ? Theme.surfaceElevated.opacity(0.72) : Theme.surfaceElevated.opacity(0.36))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            }
            .buttonStyle(.iosPressable)
            .disabled(completedCount == 0)
            .opacity(completedCount == 0 ? 0.45 : 1)
        }
        .tint(Theme.blue)
    }
}

/// Name only. See `iOSPageHeader`, which this is the `.pane`-role spelling of.
///
/// The name survives because "panel header" is what the header of a chooser column is, and because
/// its remaining callers — Focus's task-picker pane and `iOSFeatureListPane` — are exactly that.
/// It used to set its eyebrow at 9pt on compact width while every other header set 10; nobody
/// chose that, and it is gone with the rest of the second spelling.
struct iOSPanelHeader: View {
    let eyebrow: String
    let title: String
    var count: Int? = nil
    /// Set on a pushed compact screen whose navigation bar is hidden, so the back control sits on
    /// this row instead of on one of its own above it. See `iOSHidesCompactNavigationBar()`.
    var onBack: (() -> Void)? = nil

    var body: some View {
        iOSPageHeader(role: .pane, eyebrow: eyebrow, title: title, count: count, onBack: onBack)
    }
}

/// Thin wrapper over the shared `EmptyStateView`, which is what macOS's empty states render.
/// This used to be a second, slightly-different empty state (flat glyph, no medallion, its own
/// type ramp) sitting beside the shared one in the same app. The signature is kept so the two
/// dozen call sites across the iOS surface do not have to change.
///
/// Empty states are one of the three places that deliberately *keep* a subtitle — it says
/// something the screen does not.
struct iOSEmptyPanel: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        EmptyStateView(message: title, subtitle: subtitle, icon: systemImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 24)
    }
}
#endif
