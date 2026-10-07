#if os(iOS)
import SwiftData
import SwiftUI

struct iOSCalendarBundleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var bundle: TaskBundle

    @State private var title: String
    @State private var date: Date
    @State private var startTime: Date
    @State private var durationMinutes: Int
    @State private var selectedTask: AppTask?
    @State private var showDeleteConfirmation = false
    /// T-322. `deleteBundle` used to end in `try? modelContext.save()` and the button below
    /// dismissed regardless, so a refused delete closed this sheet exactly as a successful one
    /// does. The alert is the shape `iOSTaskDeleteFailureAlert` already uses for the task delete
    /// this is the block-shaped sibling of.
    @State private var deleteFailed = false
    /// T-566, and the same shape as `deleteFailed` above for the same reason: `save()` used to end
    /// in a swallowed commit inside `updateBundle` and the button dismissed regardless, so a
    /// refused save closed this sheet exactly as a successful one does. The block's *delete* and
    /// the sibling *create* sheet (T-471) both already caught; this was the third exit.
    @State private var saveFailed = false

    private let calendar = Calendar.current

    init(bundle: TaskBundle) {
        self.bundle = bundle
        let bundleDate = DateFormatters.date(from: bundle.dateKey) ?? Date()
        _title = State(initialValue: bundle.title)
        _date = State(initialValue: bundleDate)
        _startTime = State(initialValue: Self.timeDate(on: bundleDate, minute: bundle.startMin))
        _durationMinutes = State(initialValue: max(5, bundle.durationMinutes))
    }

    private var dateKey: String {
        DateFormatters.dateKey(from: date)
    }

    /// The other direction, and it was already right ([[T-3051]]). Reading `.hour` and `.minute`
    /// out of a calendar *is* a wall-clock reading, so it needed no change — it is the half that
    /// made the seed's elapsed arithmetic visible as data loss rather than as a cosmetic offset.
    /// Together with `timeDate(on:minute:calendar:)` below it now round-trips to the identity, and
    /// its `(24 * 60) - 5` ceiling is the one that clamp mirrors.
    ///
    /// **What `save()` does with this is the whole reason the seed mattered**: it goes to
    /// `CadenceTaskMutationSupport.updateBundle(startMin:)`, which assigns `bundle.startMin` and
    /// commits. This is not a label.
    private var startMinute: Int {
        let components = calendar.dateComponents([.hour, .minute], from: startTime)
        return max(0, min((components.hour ?? 0) * 60 + (components.minute ?? 0), (24 * 60) - 5))
    }

    private var endMinute: Int {
        min((24 * 60), startMinute + max(5, durationMinutes))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // T-604: `.ruled` groups need a plate to be ruled *on*, and the figures are
                // `iOSEditorSheetMetrics`' rather than this sheet's own 16/18 — which happened to
                // match `groupSpacing` and the compact `gutter` exactly, so nothing moves and the
                // agreement stops being a coincidence. Same frame as
                // `iOSCalendarQuickCreateSheet` and `iOSCalendarEventEditSheet`, because all three
                // now draw the same "Schedule" group.
                VStack(alignment: .leading, spacing: iOSEditorSheetMetrics.groupSpacing) {
                    titleSection
                    scheduleSection
                    taskSection
                    focusSection
                    deleteSection
                }
                .padding(iOSEditorSheetMetrics.cardPadding)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
                .padding(iOSEditorSheetMetrics.gutter(isRegularWidth: false))
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Edit Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try save()
                        } catch {
                            saveFailed = true
                            return
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $selectedTask) { task in
                iOSTaskInspectorSheet(task: task) { selectedTask = nil }
            }
            .confirmationDialog("Delete this block?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button(TaskBundle.deleteConfirmationButtonTitle, role: .destructive) {
                    do {
                        try CadenceTaskMutationSupport.deleteBundle(bundle, modelContext: modelContext)
                    } catch {
                        deleteFailed = true
                        return
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The tasks stay scheduled for \(DateFormatters.relativeDate(from: bundle.dateKey)), but they will no longer be grouped in this block.")
            }
            // The promise it makes is earned by `commitDelete`'s rollback: the block and its
            // members are visible again, so nothing was removed.
            .alert(CadenceTaskMutationSupport.bundleDeleteFailureAlertTitle, isPresented: $deleteFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(CadenceTaskMutationSupport.bundleDeleteFailureNotice)
            }
            // "Nothing was changed" is earned by `updateBundle`'s undo: the block's own fields and
            // its members' scheduling are back where they were, so the sheet the user is still
            // looking at is showing the truth.
            .alert(CadenceTaskMutationSupport.bundleEditFailureAlertTitle, isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(CadencePendingChangePersistence.editFailureNotice)
            }
        }
        // [[T-642]]. `taskSection` grows a completion circle per member, and this sheet is
        // presented by `iOSBundleInspectorHost` from the same root and in the same modifier order
        // as the task sheet — so a refused tick here would raise the shell's alert and take this
        // sheet down with it. It says the sentence itself instead. **Not driven**: reaching this
        // surface needs a block to exist, which the seeded simulator store has none of; the two
        // alerts above are the fix for the same shape on this sheet's own Save and Delete.
        .cadenceSaysItsOwnTaskSettleFailure()
    }

    // The one section here whose children are *not* separated by an `iOSEditorDivider`, so it is the
    // one that needs its own spacing: at the 0 default the title field and the summary row below it
    // sat flush against each other.
    private var titleSection: some View {
        iOSEditorSection(title: TaskBundle.shortLabel, style: .ruled, contentSpacing: 10) {
            // No inset well (T-604). It was `Theme.surfaceElevated.opacity(0.65)`, which was
            // legible only because the group sat on a `.card` — on the sheet's own elevated plate
            // it is the plate, at 65%, on itself. The sibling sheets' subject field is bare 22pt
            // bold and reads from `iOSEditorSheetMetrics`, so this is now the third caller of one
            // decision rather than a fourth literal.
            TextField(TaskBundle.titleFieldPlaceholder, text: $title)
                .textInputAutocapitalization(.words)
                .font(.system(size: iOSEditorSheetMetrics.titleSize, weight: .bold))
                .foregroundStyle(Theme.text)

            HStack(spacing: 8) {
                Label(
                    CadenceScheduleSupport.timeRangeLabel(startMinute: startMinute, endMinute: endMinute),
                    systemImage: "clock.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.amber)

                Spacer(minLength: 0)

                iOSMetaChip(
                    label: "\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")",
                    color: Theme.dim,
                    systemImage: "checklist"
                )
            }
        }
    }

    private var scheduleSection: some View {
        iOSEditorSection(title: "Schedule", style: .ruled) {
            iOSEditorFieldRow(label: "Date", systemImage: "calendar", color: Theme.blue) {
                CadenceDatePicker(selection: dateBinding)
            }

            iOSEditorDivider()

            CadenceStartTimeFieldRow(minutes: startMinuteBinding)

            iOSEditorDivider()

            iOSEditorFieldRow(label: "Duration", systemImage: "timer", color: Theme.green) {
                EstimatePickerControl(value: $durationMinutes)
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { date },
            set: { newDate in
                date = newDate
                startTime = Self.timeDate(on: newDate, minute: startMinute)
            }
        )
    }

    private var startMinuteBinding: Binding<Int> {
        Binding(
            get: { startMinute },
            set: { minute in startTime = Self.timeDate(on: date, minute: minute) }
        )
    }

    private var taskSection: some View {
        iOSEditorSection(title: "Tasks", style: .ruled) {
            if bundle.sortedTasks.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                    Text("No tasks in this block")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Drop tasks onto the block from Calendar Board to group them here.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                VStack(spacing: 8) {
                    ForEach(bundle.sortedTasks) { task in
                        iOSCalendarBundleTaskRow(
                            task: task,
                            open: { selectedTask = task },
                            remove: { CadenceTaskMutationSupport.removeTaskFromBundle(task, modelContext: modelContext) }
                        )
                    }
                }
            }
        }
    }

    /// T-266: the block half of "start a session from somewhere other than the Focus screen".
    ///
    /// It lives here rather than on `iOSCalendarBoardBundleCard` and `iOSTimelineBundleBlock` —
    /// the two surfaces that correspond to macOS's `CalendarBoardItemSupportViews` and
    /// `TimelineBundleBlock` — because on iOS both of those *open this sheet*. macOS puts the ▶ on
    /// the block because a pointer can reveal a control without committing to it; a finger cannot,
    /// so a permanently visible play glyph on every block card is clutter on the one surface whose
    /// whole job is reading a day at a glance. One entry here is reachable from both.
    ///
    /// The session is started before the sheet is dismissed, not after: the request is a value in
    /// an inbox, so the shell can route underneath while this is still on screen, and there is no
    /// dismissal callback to hang the second half on.
    ///
    /// **T-276 decided the block case separately, and it did not come out the same way as the task
    /// case by analogy — it came out the same way because the picker already said so.** A block
    /// whose members are all settled is not "a settled task, ×N"; it is a container with nothing
    /// left in it, which is exactly what `TaskBundle.isCompleted` means, and
    /// `CadenceFocusPickItem.filtered` has refused to list such a block since before there was an
    /// entry point to gate. Offering it here contradicted the app's own stated position two taps
    /// away. The second clause of `canFocus(_ bundle:)` is the sharper one: an *empty* block is not
    /// `isCompleted`, and running the clock against it distributes its minutes across nothing at all
    /// — the only place in the app where measured time is silently discarded.
    @ViewBuilder
    private var focusSection: some View {
        if CadenceFocusSupport.canFocus(bundle) {
            iOSActionButton(
                title: "Focus This Block",
                systemImage: CadenceFeatureDestination.focus.systemImage,
                // The destination's own tint, beside the destination's own glyph. This was a literal
                // `Theme.amber` — a token `CadenceFeatureDestination.defaultColorHex` assigns to
                // Today and Habits, and the exact drift that property's doc comment was written
                // about. T-273 added the second Focus entry (`iOSTaskDetailSheet.focusSection`);
                // two buttons naming one screen in two colours is what made it worth one line to
                // settle.
                tint: CadenceFeatureDestination.focus.tint,
                fullWidth: true
            ) {
                CadenceFocusHandoffCenter.shared.request(.bundle(bundle.id))
                dismiss()
            }
        }
    }

    private var deleteSection: some View {
        iOSActionButton(
            title: TaskBundle.deleteConfirmationButtonTitle,
            systemImage: "trash",
            role: .destructive,
            fullWidth: true
        ) {
            showDeleteConfirmation = true
        }
    }

    private func save() throws {
        try CadenceTaskMutationSupport.updateBundle(
            bundle,
            title: title,
            dateKey: dateKey,
            startMin: startMinute,
            durationMinutes: durationMinutes,
            modelContext: modelContext
        )
    }

    /// Seeds `startTime` — and re-seeds it on every date change and picker edit — from a
    /// **minute-of-day**, which is a wall-clock reading and is therefore *set*, never added to
    /// midnight ([[T-3051]], the fifth site of the defect [[T-3048]] and [[T-3050]] fixed).
    ///
    /// **This sheet is a write path, not a preview, and that is why the line mattered.** The seed
    /// is read straight back out by `startMinute` above, which `save()` hands to
    /// `CadenceTaskMutationSupport.updateBundle(startMin:)` — so with the old
    /// `date(byAdding: .minute, value: minute, to: startOfDay)` spelling, *opening this sheet on a
    /// transition day and tapping Save moved the block an hour with no user edit at all*. Measured
    /// in `America/New_York` with `startMin = 540`: the elapsed form seeds 10:00 on 2026-03-08 and
    /// 08:00 on 2026-11-01, and `startMinute` then reads back 600 and 480 for a block stored at
    /// 540. The picker misbehaved in the same breath — `startMinuteBinding` sets through here and
    /// reads back through `startMinute`, so a user who picked 09:00 watched it snap elsewhere.
    ///
    /// It delegates to `CadenceCalendarEventTiming.startDate(day:startMin:calendar:)` rather than
    /// spelling the rule again: this call site holds the day as a `Date`, which is exactly the
    /// shape that overload was added for, and the repo reached five copies of one rule by letting
    /// each site write its own. That helper's doc comment owns the gap and ambiguity readings — a
    /// non-existent 02:30 resolves to 03:00, the first instant after the gap, and an ambiguous
    /// 01:30 takes the first (EDT) of its two occurrences.
    ///
    /// **Out of range diverges from the three write sites, and only because there is nothing here
    /// to refuse.** They return `nil` and abandon the write rather than mis-date a real calendar
    /// event; this is a non-failable `@State` seed inside a `View.init`, so the picker must be
    /// given *some* instant. The old code clamped the floor with `max(0, minute)` and had **no
    /// ceiling**, so a stored `startMin` of 1500 rolled the seed onto the *next calendar day* at
    /// 01:00 and `startMinute` read it back as 60. The clamp is now two-sided and at exactly the
    /// bound `startMinute` and `updateBundle` already impose — `(24 * 60) - 5` — which makes the
    /// round trip `startMin → timeDate → startMinute` the identity on the whole valid domain and a
    /// same-day 23:55 outside it. `?? dayStart` is therefore unreachable, and is the day's own
    /// midnight rather than any other day.
    private static func timeDate(on date: Date, minute: Int, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let clamped = min(max(0, minute), (24 * 60) - 5)
        return CadenceCalendarEventTiming.startDate(day: dayStart, startMin: clamped, calendar: calendar) ?? dayStart
    }
}

private struct iOSCalendarBundleTaskRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: AppTask
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext)
            } label: {
                iOSTaskCompletionCircle(glyph: .resolve(task: task))
                    .frame(width: 18, height: 18)
                    .frame(width: 30, height: 30)
                    .iOSExpandedHitArea()
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: CadenceBundleTaskRowMetrics.summarySpacing) {
                Text(TaskTitleSupport.displayTitle(task.title))
                    .font(.system(size: CadenceBundleTaskRowMetrics.titleSize, weight: CadenceBundleTaskRowMetrics.titleWeight))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .strikethrough(task.isDone, color: Theme.dim)
                    .lineLimit(CadenceBundleTaskRowMetrics.titleLineLimit)

                // Was priority and a raw `\(est)m`, and **no due date** — so a task three days
                // late inside a calendar block said nothing about it here while both macOS bundle
                // rows did. Priority is not what a bundle is ordered by; it was spending the only
                // secondary line on the one fact this row does not need.
                CadenceTaskDetailLineLabel(
                    parts: CadenceBundleTaskRowSupport.detailParts(for: task),
                    fontSize: CadenceBundleTaskRowMetrics.detailSize
                )
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    open()
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                Button {
                    remove()
                } label: {
                    Label("Remove from Block", systemImage: "rectangle.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Task actions")
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.rowSeparator)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}
#endif
