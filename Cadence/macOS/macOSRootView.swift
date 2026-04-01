#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

enum SidebarItem: Hashable {
    case today
    case allTasks
    case inbox
    case area(UUID)
    case project(UUID)
    case goals
    case habits
    case notes
    case calendar
    case focus
    case settings
}

struct macOSRootView: View {
    @State private var selection: SidebarItem? = .today
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(ThemeManager.self) private var themeManager
    @Environment(FocusManager.self) private var focusManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskDatePickerManager.self) private var hoveredTaskDatePickerManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @State private var keyMonitor: Any? = nil
    @State private var showTimelineSidebar = false
    private let hoveredTaskManager = HoveredTaskManager.shared
    private let hoveredEditableManager = HoveredEditableManager.shared
    private let hoveredKanbanColumnManager = HoveredKanbanColumnManager.shared
    private let hoveredSectionManager = HoveredSectionManager.shared
    private let taskCompletionAnimationManager = TaskCompletionAnimationManager.shared

    var body: some View {
        let _ = themeManager.selectedTheme

        ZStack {
            HStack(spacing: 0) {
                if columnVisibility != .detailOnly {
                    SidebarView(selection: $selection)
                        .frame(width: 264)
                        .background(
                            LinearGradient(
                                colors: [Theme.surface.opacity(0.98), Theme.surfaceElevated.opacity(0.98)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Theme.borderSubtle.opacity(0.85))
                                .frame(width: 1)
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)

                if showTimelineSidebar {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Today Timeline")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showTimelineSidebar = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.dim)
                                    .frame(width: 20, height: 20)
                                    .background(Theme.surfaceElevated)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.cadencePlain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(Theme.surface)

                        Divider().background(Theme.borderSubtle)

                        SchedulePanel()
                            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
                    }
                    .frame(width: 360)
                    .background(Theme.surface)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.borderSubtle.opacity(0.85))
                            .frame(width: 1)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .preferredColorScheme(.dark)

            VStack {
                HStack {
                    Button(action: toggleSidebarVisibility) {
                        Image(systemName: columnVisibility == .detailOnly ? "sidebar.left" : "sidebar.leading")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 30, height: 30)
                            .background(Theme.surfaceElevated.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.borderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.cadencePlain)
                    .help(columnVisibility == .detailOnly ? "Show Sidebar (Cmd+S)" : "Hide Sidebar (Cmd+S)")

                    Spacer()
                }
                .padding(.leading, 10)
                .padding(.top, 10)

                Spacer()
            }
            .zIndex(5)

            TaskCreationLayerView()
            SuccessToastLayerView()
            DeleteConfirmationLayerView()
            DatePickerLayerView()
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            configureMainWindow()
            if modelContext.undoManager == nil {
                modelContext.undoManager = UndoManager()
            }
            installKeyMonitorIfNeeded()
            GlobalHotKeyManager.shared.registerIfNeeded()
            Task {
                await CalendarManager.shared.requestAccess()
                // requestAccess calls startObserving() on success, but call again for already-authorized case
                CalendarManager.shared.startObserving()
            }
        }
        .onDisappear {
            removeKeyMonitor()
            GlobalHotKeyManager.shared.unregister()
        }
        .onChange(of: calendarManager.storeVersion) {
            // Sync all tasks that have linked calendar events (handles moves + deletes from iCal)
            let descriptor = FetchDescriptor<AppTask>()
            let tasks = (try? modelContext.fetch(descriptor)) ?? []
            for task in tasks where !task.calendarEventID.isEmpty {
                calendarManager.syncTaskFromLinkedEvent(task)
            }
            try? modelContext.save()
        }
        .onChange(of: selection) { _, newValue in
            // Restore sidebar when leaving focus
            if newValue != .focus {
                withAnimation(.easeInOut(duration: 0.25)) {
                    columnVisibility = .all
                }
            }
        }
        .onChange(of: focusManager.isRunning) { _, isRunning in
            // Hide sidebar when timer starts while on focus tab
            if isRunning && selection == .focus {
                withAnimation(.easeInOut(duration: 0.25)) {
                    columnVisibility = .detailOnly
                }
            }
        }
        .onChange(of: focusManager.wantsNavToFocus) {
            if focusManager.wantsNavToFocus {
                selection = .focus
                withAnimation(.easeInOut(duration: 0.25)) {
                    columnVisibility = .detailOnly
                }
                focusManager.wantsNavToFocus = false
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .today, .none:
            TodayView()
        case .allTasks:
            AllTasksPageView()
        case .inbox:
            InboxView()
        case .area(let id):
            AreaDetailLoader(id: id)
        case .project(let id):
            ProjectDetailLoader(id: id)
        case .goals:
            GoalsView()
        case .habits:
            HabitsView()
        case .notes:
            NotesView()
        case .calendar:
            CalendarPageView()
        case .focus:
            FocusView()
        case .settings:
            SettingsView()
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if deleteConfirmationManager.request != nil {
                switch event.keyCode {
                case 36, 76: // Return / Enter
                    deleteConfirmationManager.confirm()
                    return nil
                case 53: // Escape
                    deleteConfirmationManager.cancel()
                    return nil
                default:
                    break
                }
            }

            if hoveredTaskDatePickerManager.request != nil {
                switch event.keyCode {
                case 36, 76: // Return / Enter
                    hoveredTaskDatePickerManager.confirm()
                    return nil
                case 53: // Escape
                    hoveredTaskDatePickerManager.cancel()
                    return nil
                default:
                    break
                }
            }

            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
                return event
            }

            switch event.keyCode {
            case 51: // Cmd+Delete — delete hovered event first, fall back to hovered task
                if hoveredEditableManager.triggerDelete() { return nil }
                guard let task = hoveredTaskManager.hoveredTask else { return event }
                deleteConfirmationManager.present(
                    title: "Delete Task?",
                    message: "This will permanently delete \"\(task.title.isEmpty ? "Untitled" : task.title)\"."
                ) {
                    modelContext.delete(task)
                    hoveredTaskManager.hoveredTask = nil
                }
                return nil
            case 14: // Cmd+E — open edit panel for hovered item
                if hoveredEditableManager.triggerEdit() { return nil }
                return event
            case 17: // Cmd+T / Cmd+Shift+T — mark do today or open do-date picker
                guard let task = hoveredTaskManager.hoveredTask else { return event }
                if event.modifierFlags.contains(.shift) {
                    hoveredTaskDatePickerManager.present(for: task, kind: .doDate)
                } else {
                    task.scheduledDate = DateFormatters.todayKey()
                }
                return nil
            case 2: // Cmd+D / Cmd+Shift+D — mark due today or open due-date picker
                guard let task = hoveredTaskManager.hoveredTask else { return event }
                if event.modifierFlags.contains(.shift) {
                    hoveredTaskDatePickerManager.present(for: task, kind: .dueDate)
                } else {
                    task.dueDate = DateFormatters.todayKey()
                }
                return nil
            case 35: // Cmd+P — cycle priority
                guard let task = hoveredTaskManager.hoveredTask, !event.modifierFlags.contains(.shift) else { return event }
                task.priority = task.priority.nextCycled
                return nil
            case 36, 76: // Cmd+Return / Cmd+Enter — toggle completion for hovered task
                if let task = hoveredTaskManager.hoveredTask {
                    taskCompletionAnimationManager.toggleCompletion(for: task)
                    return nil
                }
                if hoveredSectionManager.triggerToggleComplete() { return nil }
                return event
            case 45: // Cmd+N — create task in hovered kanban column
                if hoveredKanbanColumnManager.triggerCreateTask() { return nil }
                return event
            case 6: // Cmd+Z / Cmd+Shift+Z — undo / redo
                if event.modifierFlags.contains(.shift) {
                    modelContext.undoManager?.redo()
                } else {
                    modelContext.undoManager?.undo()
                }
                return nil
            case 42: // Cmd+\ — toggle timeline sidebar
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTimelineSidebar.toggle()
                }
                return nil
            case 1: // Cmd+S — toggle sidebar
                toggleSidebarVisibility()
                return nil
            case 24, 27: // Cmd+Shift+Plus / Cmd+Shift+Minus — nudge hovered do/due date by one day
                guard event.modifierFlags.contains(.shift),
                      let task = hoveredTaskManager.hoveredTask,
                      let dateKind = hoveredTaskManager.hoveredDateKind else { return event }
                let delta = event.keyCode == 27 ? -1 : 1
                let currentKey: String
                switch dateKind {
                case .doDate:
                    currentKey = task.scheduledDate
                case .dueDate:
                    currentKey = task.dueDate
                }
                let baseDate = DateFormatters.date(from: currentKey) ?? Date()
                let nudged = Calendar.current.date(byAdding: .day, value: delta, to: baseDate) ?? baseDate
                let nudgedKey = DateFormatters.dateKey(from: nudged)
                switch dateKind {
                case .doDate:
                    task.scheduledDate = nudgedKey
                case .dueDate:
                    task.dueDate = nudgedKey
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func configureMainWindow() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.contentViewController != nil }) else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbar = nil
            window.isMovableByWindowBackground = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    private func toggleSidebarVisibility() {
        withAnimation(.easeInOut(duration: 0.22)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}

private struct TaskCreationLayerView: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager

    var body: some View {
        if taskCreationManager.isPresented {
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearAppEditingFocus()
                        taskCreationManager.dismiss()
                    }

                CreateTaskSheet(seed: taskCreationManager.seed)
                    .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
                    .onTapGesture {
                        // Prevent outside tap handler from firing when clicking inside the panel.
                    }
            }
            .transition(.opacity)
            .zIndex(10)
        }
    }
}

private struct SuccessToastLayerView: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager

    var body: some View {
        if taskCreationManager.showSuccessToast {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.green)
                    Text("Task Created")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Theme.surfaceElevated.opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
                .padding(.bottom, 24)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .zIndex(30)
        }
    }
}

private struct DeleteConfirmationLayerView: View {
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager

    var body: some View {
        if let deleteRequest = deleteConfirmationManager.request {
            DeleteConfirmationOverlay(
                title: deleteRequest.title,
                message: deleteRequest.message,
                confirmLabel: deleteRequest.confirmLabel,
                onConfirm: { deleteConfirmationManager.confirm() },
                onCancel: { deleteConfirmationManager.cancel() }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .zIndex(20)
        }
    }
}

private struct DatePickerLayerView: View {
    @Environment(HoveredTaskDatePickerManager.self) private var hoveredTaskDatePickerManager

    var body: some View {
        if let request = hoveredTaskDatePickerManager.request {
            HoveredTaskDatePickerOverlay(
                request: request,
                onUpdateDate: { hoveredTaskDatePickerManager.request?.selectedDate = $0 },
                onConfirm: { hoveredTaskDatePickerManager.confirm() },
                onClear: { hoveredTaskDatePickerManager.clearDate() },
                onCancel: { hoveredTaskDatePickerManager.cancel() }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .zIndex(21)
        }
    }
}

private struct HoveredTaskDatePickerOverlay: View {
    let request: HoveredTaskDatePickerManager.Request
    let onUpdateDate: (Date) -> Void
    let onConfirm: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    @State private var pickerViewMonth: Date

    init(
        request: HoveredTaskDatePickerManager.Request,
        onUpdateDate: @escaping (Date) -> Void,
        onConfirm: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onUpdateDate = onUpdateDate
        self.onConfirm = onConfirm
        self.onClear = onClear
        self.onCancel = onCancel
        var comps = Calendar.current.dateComponents([.year, .month], from: request.selectedDate)
        comps.day = 1
        _pickerViewMonth = State(initialValue: Calendar.current.date(from: comps) ?? request.selectedDate)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill((request.kind == .doDate ? Theme.blue : Theme.amber).opacity(0.16))
                                .frame(width: 40, height: 40)
                            Image(systemName: request.kind == .doDate ? "calendar" : "calendar.badge.exclamationmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(request.kind == .doDate ? Theme.blue : Theme.amber)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.kind.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Text(request.task.title.isEmpty ? "Untitled task" : request.task.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.kind == .doDate ? "Choose when you want to do this task." : "Choose when this task is due.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)

                        MonthCalendarPanel(
                            selection: Binding(
                                get: { request.selectedDate },
                                set: { newDate in
                                    onUpdateDate(newDate)
                                    var comps = Calendar.current.dateComponents([.year, .month], from: newDate)
                                    comps.day = 1
                                    pickerViewMonth = Calendar.current.date(from: comps) ?? newDate
                                }
                            ),
                            viewMonth: $pickerViewMonth,
                            isOpen: Binding(
                                get: { true },
                                set: { _ in }
                            ),
                            inlineStyle: true
                        )
                    }
                }
                .padding(20)

                Divider().background(Theme.borderSubtle)

                HStack(spacing: 10) {
                    Button(action: onClear) {
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.red)
                            .frame(minWidth: 74, minHeight: 36)
                            .contentShape(Rectangle())
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.cadencePlain)

                    Spacer()

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .frame(minWidth: 96, minHeight: 36)
                            .contentShape(Rectangle())
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.cadencePlain)
                        .keyboardShortcut(.cancelAction)

                    Button(action: onConfirm) {
                        Text("Apply")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 96, minHeight: 36)
                            .contentShape(Rectangle())
                            .background(request.kind == .doDate ? Theme.blue : Theme.amber)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.cadencePlain)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(20)
            }
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.borderSubtle))
            )
            .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 14)
        }
    }
}

private struct DeleteConfirmationOverlay: View {
    let title: String
    let message: String
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.red.opacity(0.14))
                                .frame(width: 40, height: 40)
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.red)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)

                Divider().background(Theme.borderSubtle)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.cadencePlain)
                        .keyboardShortcut(.cancelAction)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button(confirmLabel, action: onConfirm)
                        .buttonStyle(.cadencePlain)
                        .keyboardShortcut(.defaultAction)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Theme.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(20)
            }
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.32), radius: 28, x: 0, y: 16)
        }
    }
}

private struct AllTasksPageView: View {
    private enum AllTasksViewMode: String, CaseIterable {
        case list = "List"
        case kanban = "Kanban"
    }

    @AppStorage("allTasksViewMode") private var modeRaw: String = AllTasksViewMode.list.rawValue
    @AppStorage("allTasksSortField") private var sortField: TaskSortField = .date
    @AppStorage("allTasksSortDirection") private var sortDirection: TaskSortDirection = .ascending
    @AppStorage("allTasksGroupingMode") private var groupingMode: TaskGroupingMode = .byDate

    private var mode: AllTasksViewMode { AllTasksViewMode(rawValue: modeRaw) ?? .list }
    @Environment(TaskCreationManager.self) private var taskCreationManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("All Tasks")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Browse everything by do date or by list, then open the full task creator from here.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Button {
                    taskCreationManager.present()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("New Task")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minWidth: 140, minHeight: 44)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
                HStack(spacing: 4) {
                    ForEach(AllTasksViewMode.allCases, id: \.self) { viewMode in
                        allTasksTabButton(viewMode)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            HStack(spacing: 10) {
                EnumFilterPickerBadge(title: "Sort", selection: $sortField)
                EnumFilterPickerBadge(title: "Order", selection: $sortDirection)
                if mode == .list {
                    EnumFilterPickerBadge(title: "Group", selection: $groupingMode)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            Group {
                switch mode {
                case .list:
                    TasksPanel(
                        mode: .byDoDate,
                        showsHeader: false,
                        sortField: sortField,
                        sortDirection: sortDirection,
                        groupingMode: groupingMode
                    )
                case .kanban:
                    TaskListsKanbanView(
                        sortField: sortField,
                        sortDirection: sortDirection,
                        groupingMode: .byList
                    )
                }
            }
        }
        .background(Theme.bg)
    }

    private func allTasksTabButton(_ tab: AllTasksViewMode) -> some View {
        Button {
            modeRaw = tab.rawValue
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab == .list ? "list.bullet" : "square.grid.3x2")
                    .font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: mode == tab ? .semibold : .regular))
            }
            .foregroundStyle(mode == tab ? Theme.blue : Theme.dim)
            .frame(minWidth: 82, minHeight: 34)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(mode == tab ? Theme.blue.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                if mode == tab {
                    Rectangle().fill(Theme.blue).frame(height: 2)
                }
            }
        }
        .buttonStyle(.cadencePlain)
    }
}

private struct EnumFilterPickerBadge<T: CaseIterable & RawRepresentable & Identifiable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    @State private var showPicker = false

    var body: some View {
        Button { showPicker.toggle() } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(selection.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(T.allCases), id: \.id) { value in
                    Button {
                        selection = value
                        showPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(value.rawValue).font(.system(size: 13)).foregroundStyle(Theme.text)
                            Spacer()
                            if selection.id == value.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background(selection.id == value.id ? Theme.blue.opacity(0.08) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.cadencePlain)
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 170)
            .background(Theme.surfaceElevated)
        }
    }
}

#endif
