#if os(macOS)
import SwiftUI
import SwiftData

private let schedStartHour = 0
private let schedEndHour   = 24
private let timeLabelWidth: CGFloat = 36
private let timeLabelPad:   CGFloat = 6
private let blockInset:     CGFloat = timeLabelWidth + timeLabelPad  // 42

struct SchedulePanel: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [AppTask]

    @State private var zoomLevel: Int = 1   // 1, 2, 3

    private var hourHeight: CGFloat {
        switch zoomLevel {
        case 1: return 66   // ~9 hours visible
        case 2: return 102  // ~6 hours visible
        default: return 180 // ~3 hours visible
        }
    }

    private var todayKey: String { DateFormatters.todayKey() }

    private var scheduledTasks: [AppTask] {
        allTasks.filter {
            $0.scheduledDate == todayKey && $0.scheduledStartMin >= 0 && !$0.isCancelled
        }
    }

    var body: some View {
        let metrics = TimelineMetrics(
            startHour: schedStartHour,
            endHour: schedEndHour,
            hourHeight: hourHeight
        )

        VStack(alignment: .leading, spacing: 0) {
            // Header + zoom controls
            HStack(spacing: 0) {
                PanelHeader(eyebrow: "Schedule", title: "Timeline")
                Spacer()
                TimelineZoomControl(zoomLevel: $zoomLevel, range: 1...3)
                    .padding(.trailing, 12)
            }

            Divider().background(Theme.borderSubtle)

            GeometryReader { geo in
                let totalWidth = max(240, geo.size.width - 8)
                let canvasWidth = max(0, totalWidth - blockInset)

                ScrollViewReader { proxy in
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                ForEach(schedStartHour..<schedEndHour, id: \.self) { hour in
                                    ScheduleTimeRailRow(hour: hour, hourHeight: hourHeight)
                                        .id(hour)
                                }
                            }
                            .frame(width: blockInset)

                            TimelineDayCanvas(
                                date: Date(),
                                dateKey: todayKey,
                                tasks: scheduledTasks,
                                allTasks: allTasks,
                                metrics: metrics,
                                width: canvasWidth,
                                style: .schedule,
                                showCurrentTimeDot: true,
                                dropBehavior: .perHour,
                                onCreateTask: { title, startMin, endMin in
                                    SchedulingActions.createTask(title: title, dateKey: todayKey, startMin: startMin, endMin: endMin, in: modelContext)
                                },
                                onDropTaskAtMinute: { task, startMin in
                                    SchedulingActions.dropTask(task, to: todayKey, startMin: startMin)
                                }
                            )
                        }
                        .frame(width: totalWidth, alignment: .leading)
                        .padding(.trailing, 8)
                    }
                    .onAppear {
                        let currentHour = Calendar.current.component(.hour, from: Date())
                        let scrollHour = max(schedStartHour, currentHour - 1)
                        proxy.scrollTo(scrollHour, anchor: .top)
                    }
                }
            }
        }
        .background(Theme.bg)
    }
}

private struct ScheduleTimeRailRow: View {
    let hour: Int
    let hourHeight: CGFloat

    var body: some View {
        Text(hourLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.dim)
            .frame(width: timeLabelWidth, height: hourHeight, alignment: .topTrailing)
            .padding(.trailing, timeLabelPad)
            .offset(y: -6)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var hourLabel: String { "\(hour)" }
}

// MARK: - Quick Create Popover

struct QuickCreatePopover: View {
    @Binding var title: String
    let startMin: Int
    let endMin: Int
    let todayKey: String
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TimeFormatters.timeRange(startMin: startMin, endMin: endMin))
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)

            TextField("Task title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .focused($focused)
                .onSubmit { onCreate(title) }

            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                Spacer()
                Button("Create") { onCreate(title) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(Theme.surface)
        .onAppear { focused = true }
    }
}

// MARK: - Task Detail Popover (shared between SchedulePanel and CalendarPageView)

struct TaskDetailPopover: View {
    @Bindable var task: AppTask
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var showDatePicker = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var notesDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: task.containerColor).opacity(0.22))
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: task.scheduledStartMin >= 0 ? "calendar.badge.clock" : "checklist")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: task.containerColor))
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Task title", text: $task.title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.text)

                        Text(scheduleDescriptor)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                    }

                    Spacer()

                    if task.priority != .none {
                        priorityPill(task.priority, selected: false)
                    }
                }

                infoCard {
                    detailRow("Time", icon: "clock") {
                        Text(task.scheduledStartMin >= 0 ? timeRange : "Not time-blocked")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(task.scheduledStartMin >= 0 ? Theme.text : Theme.dim)
                    }

                    detailRow("Due", icon: "calendar.badge.exclamationmark") {
                        Button {
                            dueDatePickerDate = task.dueDate.isEmpty ? Date() : (DateFormatters.date(from: task.dueDate) ?? Date())
                            showDatePicker.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Text(task.dueDate.isEmpty ? "Set due date" : DateFormatters.fullShortDate.string(from: DateFormatters.date(from: task.dueDate) ?? dueDatePickerDate))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(task.dueDate.isEmpty ? Theme.dim : Theme.text)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showDatePicker) {
                            VStack(spacing: 4) {
                                CadenceDatePicker(selection: $dueDatePickerDate)
                                    .onChange(of: dueDatePickerDate) {
                                        task.dueDate = DateFormatters.dateKey(from: dueDatePickerDate)
                                    }
                                if !task.dueDate.isEmpty {
                                    Button("Clear") { task.dueDate = ""; showDatePicker = false }
                                        .font(.system(size: 11)).foregroundStyle(Theme.red).buttonStyle(.plain)
                                }
                            }
                            .padding(8)
                        }
                    }

                    detailRow("List", icon: "tray.full") {
                        ContainerPickerBadge(task: task, areas: areas, projects: projects)
                    }
                }

                infoCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Priority")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)

                        HStack(spacing: 8) {
                            ForEach(TaskPriority.allCases, id: \.self) { priority in
                                Button {
                                    task.priority = priority
                                } label: {
                                    priorityPill(priority, selected: task.priority == priority)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                infoCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Notes")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)

                        TextEditor(text: Binding(
                            get: { task.notes },
                            set: { task.notes = $0 }
                        ))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 88)
                        .padding(8)
                        .background(Theme.surfaceElevated.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        task.status = task.isDone ? .todo : .done
                    } label: {
                        Label(task.isDone ? "Unmark Done" : "Mark Done",
                              systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(task.isDone ? Theme.dim : Theme.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    if task.scheduledStartMin >= 0 {
                        Button {
                            task.scheduledStartMin = -1
                            task.scheduledDate = ""
                        } label: {
                            Label("Unschedule", systemImage: "calendar.badge.minus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onAppear {
            dueDatePickerDate = task.dueDate.isEmpty ? Date() : (DateFormatters.date(from: task.dueDate) ?? Date())
            notesDraft = task.notes
        }
    }

    private var timeRange: String {
        TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledStartMin + max(task.estimatedMinutes, 5))
    }

    private var scheduleDescriptor: String {
        if task.scheduledStartMin >= 0 {
            return "Scheduled • \(timeRange)"
        }
        if !task.dueDate.isEmpty {
            return "Due \(DateFormatters.shortDateString(from: task.dueDate))"
        }
        return "Inbox task"
    }

    @ViewBuilder
    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .background(Theme.surface.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detailRow<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 88, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func priorityPill(_ priority: TaskPriority, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.priorityColor(priority))
                .frame(width: 7, height: 7)
            Text(priority.label)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
        }
        .foregroundStyle(selected ? Theme.text : Theme.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? Theme.surfaceElevated : Theme.surface.opacity(0.6))
        .clipShape(Capsule())
    }
}
#endif
