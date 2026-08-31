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
                VStack(alignment: .leading, spacing: 16) {
                    titleSection
                    scheduleSection
                    taskSection
                    focusSection
                    deleteSection
                }
                .padding(18)
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
                Button("Delete Block", role: .destructive) {
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
    }

    // The one section here whose children are *not* separated by an `iOSEditorDivider`, so it is the
    // one that needs its own spacing: at the 0 default the title field and the summary row below it
    // sat flush against each other.
    private var titleSection: some View {
        iOSEditorSection(title: "Block", contentSpacing: 10) {
            TextField("Block title", text: $title)
                .textInputAutocapitalization(.words)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .background(Theme.surfaceElevated.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))

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
        iOSEditorSection(title: "Schedule") {
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
        iOSEditorSection(title: "Tasks") {
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
            title: "Delete Block",
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

    private static func timeDate(on date: Date, minute: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: max(0, minute), to: start) ?? start
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
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.35))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}
#endif
