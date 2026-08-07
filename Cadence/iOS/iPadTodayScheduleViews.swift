#if os(iOS)
import SwiftData
import SwiftUI

struct iOSSchedulePanel: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]
    @State private var quickCreateStartMin: Int?
    @State private var quickCreateTitle = ""
    @State private var quickCreateError: String?

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var scheduledTasks: [AppTask] {
        CadenceScheduleSupport.scheduledTasks(on: todayKey, from: allTasks)
    }

    private var todayBundles: [TaskBundle] {
        CadenceScheduleSupport.bundles(on: todayKey, from: allBundles, includeCompleted: false)
    }

    private var untimedTodayTasks: [AppTask] {
        CadenceScheduleSupport.unscheduledTasksByDate(allTasks)[todayKey] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                iOSPanelHeader(eyebrow: "Schedule", title: "Timeline")
                Spacer()
            }
            .frame(height: iOSPanelHeaderHeight, alignment: .top)

            Divider().background(Theme.borderSubtle)

            if !untimedTodayTasks.isEmpty {
                iOSScheduleReadyStack(tasks: untimedTodayTasks)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                Divider().background(Theme.borderSubtle.opacity(0.72))
            }

            if let quickCreateStartMin {
                iOSScheduleQuickCreateBar(
                    startMin: quickCreateStartMin,
                    title: $quickCreateTitle,
                    errorMessage: quickCreateError,
                    create: createScheduledTask,
                    cancel: cancelQuickCreate
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(Theme.borderSubtle.opacity(0.72))
            }

            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(6..<23, id: \.self) { hour in
                            iOSScheduleHourRow(
                                hour: hour,
                                tasks: tasks(in: hour),
                                bundles: bundles(in: hour),
                                rowHeight: horizontalSizeClass == .regular ? 58 : 48,
                                selectedStartMin: quickCreateStartMin,
                                onSelectStart: selectQuickCreateStart
                            )
                        }
                    }
                    .padding(.trailing, horizontalSizeClass == .regular ? 12 : 8)
                }
                .scrollIndicators(.hidden)

                if scheduledTasks.isEmpty && todayBundles.isEmpty && untimedTodayTasks.isEmpty {
                    iOSScheduleEmptyHint()
                        .padding(.horizontal, 20)
                }
            }
        }
        .background(Theme.bg)
    }

    private func tasks(in hour: Int) -> [AppTask] {
        CadenceScheduleSupport.tasks(in: hour, from: scheduledTasks)
    }

    private func bundles(in hour: Int) -> [TaskBundle] {
        CadenceScheduleSupport.bundles(in: hour, from: todayBundles)
    }

    private func selectQuickCreateStart(_ startMin: Int) {
        quickCreateStartMin = startMin
        quickCreateError = nil
    }

    private func cancelQuickCreate() {
        quickCreateStartMin = nil
        quickCreateTitle = ""
        quickCreateError = nil
    }

    private func createScheduledTask() {
        guard let startMin = quickCreateStartMin else { return }
        let pendingTitle = quickCreateTitle
        do {
            guard (try CadenceTaskMutationSupport.insertScheduledTask(
                title: pendingTitle,
                allTasks: allTasks,
                modelContext: modelContext,
                scheduledDate: todayKey,
                scheduledStartMin: startMin,
                estimatedMinutes: 30
            )) != nil else {
                quickCreateError = "Add a title first."
                return
            }
            cancelQuickCreate()
        } catch {
            quickCreateTitle = pendingTitle
            quickCreateError = "Couldn't save this timed task."
        }
    }
}

private struct iOSScheduleQuickCreateBar: View {
    let startMin: Int
    @Binding var title: String
    let errorMessage: String?
    let create: () -> Void
    let cancel: () -> Void
    @FocusState private var isFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "clock.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(width: 28, height: 28)
                    .background(Theme.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create at \(TimeFormatters.timeString(from: startMin))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text("Adds a 30 minute task to Today.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 26, height: 26)
                        .background(Theme.surfaceElevated.opacity(0.38))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel timed task")
            }

            HStack(spacing: 7) {
                TextField("Timed task title...", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(create)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Theme.surface.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(0.52), lineWidth: 1)
                    }

                Button(action: create) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34)
                        .background(trimmedTitle.isEmpty ? Theme.surfaceElevated.opacity(0.42) : Theme.blue.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(trimmedTitle.isEmpty)
                .accessibilityLabel("Create timed task")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .cadenceCard(background: Theme.surfaceElevated.opacity(0.36), cornerRadius: Theme.radiusCard)
        .onAppear {
            isFocused = true
        }
    }
}

private struct iOSScheduleHourRow: View {
    let hour: Int
    let tasks: [AppTask]
    let bundles: [TaskBundle]
    let rowHeight: CGFloat
    let selectedStartMin: Int?
    let onSelectStart: (Int) -> Void

    private var hasItems: Bool {
        !tasks.isEmpty || !bundles.isEmpty
    }

    private var startMin: Int {
        hour * 60
    }

    private var isSelectedForCreate: Bool {
        selectedStartMin == startMin
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(hourLabel)
                .font(.system(size: rowHeight > 50 ? 11 : 10, weight: .medium))
                .foregroundStyle(isSelectedForCreate ? Theme.blue : Theme.dim.opacity(hour % 3 == 0 ? 0.9 : 0.45))
                .frame(width: rowHeight > 50 ? 50 : 42, alignment: .trailing)
                .padding(.trailing, rowHeight > 50 ? 9 : 7)
                .padding(.top, -6)

            VStack(alignment: .leading, spacing: 5) {
                Rectangle()
                    .fill(isSelectedForCreate ? Theme.blue.opacity(0.58) : Theme.borderSubtle.opacity(hour % 3 == 0 ? 0.55 : 0.25))
                    .frame(height: 1)

                if hasItems {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(bundles) { bundle in
                            iOSScheduleBlock(
                                title: bundle.displayTitle,
                                subtitle: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                                tint: Theme.purple
                            )
                        }

                        ForEach(tasks) { task in
                            iOSScheduleTaskBlock(task: task)
                        }
                    }
                    .padding(.top, 5)
                } else {
                    Button {
                        onSelectStart(startMin)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSelectedForCreate ? "plus.circle.fill" : "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text(isSelectedForCreate ? "Creating here" : "Add")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(isSelectedForCreate ? Theme.blue : Theme.dim.opacity(0.58))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(isSelectedForCreate ? Theme.blue.opacity(0.12) : Theme.surfaceElevated.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create timed task at \(hourLabel)")
                    .padding(.top, 5)
                }
            }
        }
        .frame(minHeight: rowHeight, alignment: .top)
        .padding(.leading, 4)
    }

    private var hourLabel: String {
        TimeFormatters.timeString(from: hour * 60)
    }
}

private struct iOSScheduleBlock: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(tint.opacity(0.9))
                .frame(width: 3)
        }
        .cadenceCard(background: tint.opacity(0.18), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
    }
}

private struct iOSScheduleTaskBlock: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @State private var showDetail = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                showDetail = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title.isEmpty ? "Untitled Task" : task.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text(timeRangeLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                clearTime()
            } label: {
                Image(systemName: "arrow.uturn.left.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.92))
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Move \(task.title.isEmpty ? "task" : task.title) back to ready to schedule")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(tint.opacity(0.9))
                .frame(width: 3)
        }
        .cadenceCard(background: tint.opacity(0.18), cornerRadius: Theme.radiusCard, shadowRadius: 8, shadowY: 3)
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }

    private var tint: Color {
        Color(hex: task.containerColor)
    }

    private var timeRangeLabel: String {
        TimeFormatters.timeRange(
            startMin: task.scheduledStartMin,
            endMin: task.scheduledEndMin
        )
    }

    private func clearTime() {
        CadenceTaskMutationSupport.clearScheduledTime(task, modelContext: modelContext)
    }
}

private struct iOSScheduleReadyStack: View {
    let tasks: [AppTask]

    private var visibleTasks: [AppTask] {
        Array(tasks.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.amber)

                Text("Ready to Schedule")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.7)

                Spacer(minLength: 0)

                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.amber.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 7) {
                ForEach(visibleTasks) { task in
                    iOSScheduleReadyTaskRow(task: task)
                }
            }

            if tasks.count > visibleTasks.count {
                Text("+\(tasks.count - visibleTasks.count) more in Today")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 1)
            }
        }
    }
}

private struct iOSScheduleReadyTaskRow: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                iOSTaskCompletionCircle(isDone: false, tint: rowTint)
                    .frame(width: 13, height: 13)
                    .padding(.top, 3)

                Button {
                    showDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title.isEmpty ? "Untitled Task" : task.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)

                        Text(task.estimatedMinutes > 0 ? estimateLabel : "No estimate")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    showDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.dim.opacity(0.85))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open task details")
            }

            HStack(spacing: 5) {
                ForEach(iOSReadyScheduleSlot.defaults) { slot in
                    Button {
                        schedule(at: slot.startMin)
                    } label: {
                        Text(slot.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.blue)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Theme.blue.opacity(0.11))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schedule \(task.title.isEmpty ? "task" : task.title) at \(slot.accessibilityTime)")
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.35))
                .frame(height: 1)
        }
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
    }

    private func schedule(at startMin: Int) {
        CadenceTaskMutationSupport.setScheduledDate(DateFormatters.todayKey(), for: task, modelContext: modelContext)
        CadenceTaskMutationSupport.setScheduledTime(startMin, for: task, modelContext: modelContext)
    }

    private var rowTint: Color {
        switch task.priority {
        case .high:
            return Theme.red
        case .medium:
            return Theme.amber
        case .low:
            return Theme.blue
        case .none:
            return Theme.dim.opacity(0.76)
        }
    }

    private var estimateLabel: String {
        "\(CadenceTaskPresentationSupport.estimateLabel(for: task)) estimate"
    }
}

private struct iOSReadyScheduleSlot: Identifiable {
    let title: String
    let startMin: Int

    var id: Int { startMin }

    var accessibilityTime: String {
        TimeFormatters.timeString(from: startMin)
    }

    static let defaults = [
        iOSReadyScheduleSlot(title: "9 AM", startMin: 9 * 60),
        iOSReadyScheduleSlot(title: "1 PM", startMin: 13 * 60),
        iOSReadyScheduleSlot(title: "4 PM", startMin: 16 * 60)
    ]
}

private struct iOSScheduleEmptyHint: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.dim)

            Text("No timed blocks")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("Scheduled tasks and bundles appear here.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .cadenceCard(background: Theme.surface.opacity(0.72), cornerRadius: Theme.radiusCard)
    }
}
#endif
