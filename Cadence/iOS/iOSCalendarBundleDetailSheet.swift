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
    @State private var showStartTimePicker = false

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
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $selectedTask) { task in
                iOSTaskDetailSheet(task: task)
            }
            .confirmationDialog("Delete this block?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Block", role: .destructive) {
                    CadenceTaskMutationSupport.deleteBundle(bundle, modelContext: modelContext)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The tasks stay scheduled for \(DateFormatters.relativeDate(from: bundle.dateKey)), but they will no longer be grouped in this block.")
            }
        }
    }

    private var titleSection: some View {
        iOSEditorSection(title: "Block") {
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

            iOSEditorFieldRow(label: "Start", systemImage: "clock.fill", color: Theme.blue) {
                iOSChoiceValueButton(title: TimeFormatters.timeString(from: startMinuteBinding.wrappedValue), color: Theme.text) {
                    showStartTimePicker = true
                }
                .popover(isPresented: $showStartTimePicker) {
                    iOSChoicePopoverList(
                        rows: stride(from: 0, to: 1440, by: 15).map { minute in
                            iOSChoiceRow(value: minute, title: TimeFormatters.timeString(from: minute), color: Theme.blue)
                        },
                        selection: startMinuteBinding,
                        isPresented: $showStartTimePicker
                    )
                }
            }

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

    private func save() {
        CadenceTaskMutationSupport.updateBundle(
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
                CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
            } label: {
                iOSTaskCompletionCircle(isDone: task.isDone, tint: Theme.priorityColor(task.priority))
                    .frame(width: 18, height: 18)
                    .frame(width: 30, height: 30)
                    .iOSExpandedHitArea()
            }
            .buttonStyle(.iosPressable)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title.isEmpty ? "Untitled Task" : task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .strikethrough(task.isDone, color: Theme.dim)
                    .lineLimit(2)

                HStack(spacing: 7) {
                    Label(task.priority.label, systemImage: "flag.fill")
                        .foregroundStyle(Theme.priorityColor(task.priority))
                    if task.estimatedMinutes > 0 {
                        Label("\(task.estimatedMinutes)m", systemImage: "clock")
                            .foregroundStyle(Theme.dim)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
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
