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
                HStack(spacing: 4) {
                    Button { if zoomLevel > 1 { zoomLevel -= 1 } } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(zoomLevel > 1 ? Theme.dim : Theme.dim.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    Text("\(zoomLevel)×")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 22)
                    Button { if zoomLevel < 3 { zoomLevel += 1 } } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(zoomLevel < 3 ? Theme.dim : Theme.dim.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
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
                                    let task = AppTask(title: title)
                                    task.scheduledDate = todayKey
                                    task.scheduledStartMin = startMin
                                    task.estimatedMinutes = max(5, endMin - startMin)
                                    modelContext.insert(task)
                                },
                                onDropTaskAtMinute: { task, startMin in
                                    task.scheduledDate = todayKey
                                    task.scheduledStartMin = startMin
                                    if task.estimatedMinutes <= 0 {
                                        task.estimatedMinutes = 60
                                    }
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Area.order)    private var areas:    [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var showDatePicker = false
    @State private var dueDatePickerDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            TextField("Task title", text: $task.title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider().background(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 10) {
                // Time
                if task.scheduledStartMin >= 0 {
                    Label(TimeFormatters.timeRange(startMin: task.scheduledStartMin, endMin: task.scheduledStartMin + max(task.estimatedMinutes, 5)), systemImage: "clock")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }

                // Priority
                HStack(spacing: 8) {
                    Label("Priority", systemImage: "flag").font(.system(size: 11)).foregroundStyle(Theme.dim).frame(width: 70, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach([("none","—"),("low","Low"),("medium","Med"),("high","High")], id: \.0) { p, l in
                            Button { task.priority = p } label: {
                                Text(l).font(.system(size: 10, weight: task.priority == p ? .semibold : .regular))
                                    .foregroundStyle(task.priority == p ? Theme.text : Theme.dim)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(task.priority == p ? Theme.borderSubtle : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }.buttonStyle(.plain)
                        }
                    }
                }

                // Due date
                HStack(spacing: 8) {
                    Label("Due", systemImage: "calendar").font(.system(size: 11)).foregroundStyle(Theme.dim).frame(width: 70, alignment: .leading)
                    Button {
                        dueDatePickerDate = task.dueDate.isEmpty ? Date() : (DateFormatters.date(from: task.dueDate) ?? Date())
                        showDatePicker.toggle()
                    } label: {
                        Text(task.dueDate.isEmpty ? "Set date" : task.dueDate)
                            .font(.system(size: 11)).foregroundStyle(task.dueDate.isEmpty ? Theme.dim : Theme.muted)
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
                        }.padding(8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Theme.borderSubtle)

            // Actions
            HStack(spacing: 8) {
                Button {
                    task.status = task.isDone ? "todo" : "done"
                } label: {
                    Label(task.isDone ? "Unmark done" : "Mark done",
                          systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.green)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    task.scheduledStartMin = -1
                    task.scheduledDate = ""
                } label: {
                    Label("Unschedule", systemImage: "calendar.badge.minus")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
        .background(Theme.surface)
        .onAppear {
            dueDatePickerDate = task.dueDate.isEmpty ? Date() : (DateFormatters.date(from: task.dueDate) ?? Date())
        }
    }

}
#endif
