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
        iOSCalendarBundleEditorSection(title: "Block") {
            TextField("Block title", text: $title)
                .textInputAutocapitalization(.words)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .background(Theme.surfaceElevated.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                Label(
                    CadenceScheduleSupport.timeRangeLabel(startMinute: startMinute, endMinute: endMinute),
                    systemImage: "clock.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.amber)

                Spacer(minLength: 0)

                Text("\(bundle.sortedTasks.count) task\(bundle.sortedTasks.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.surfaceElevated.opacity(0.68))
                    .clipShape(Capsule())
            }
        }
    }

    private var scheduleSection: some View {
        iOSCalendarBundleEditorSection(title: "Schedule") {
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .tint(Theme.blue)
                .onChange(of: date) { _, newDate in
                    startTime = Self.timeDate(on: newDate, minute: startMinute)
                }

            iOSCalendarBundleDivider()

            DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                .tint(Theme.blue)

            iOSCalendarBundleDivider()

            Stepper(value: $durationMinutes, in: 5...720, step: 5) {
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(durationLabel(durationMinutes))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var taskSection: some View {
        iOSCalendarBundleEditorSection(title: "Tasks") {
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
                        .foregroundStyle(Theme.dim)
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
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete Block", systemImage: "trash")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.bordered)
        .tint(Theme.red)
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

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private static func timeDate(on date: Date, minute: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: max(0, minute), to: start) ?? start
    }
}

private struct iOSCalendarBundleEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
        }
    }
}

private struct iOSCalendarBundleDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.borderSubtle.opacity(0.55))
            .frame(height: 1)
            .padding(.vertical, 9)
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
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.green : Theme.dim)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title.isEmpty ? "Untitled Task" : task.title)
                    .font(.system(size: 14, weight: .semibold))
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Theme.surfaceElevated.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.42), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: open)
    }
}
#endif
