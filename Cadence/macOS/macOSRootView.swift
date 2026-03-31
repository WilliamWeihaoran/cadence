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
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(HoveredKanbanColumnManager.self) private var hoveredKanbanColumnManager
    @Environment(HoveredSectionManager.self) private var hoveredSectionManager
    @Environment(HoveredTaskDatePickerManager.self) private var hoveredTaskDatePickerManager
    @Environment(TaskCompletionAnimationManager.self) private var taskCompletionAnimationManager
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(\.modelContext) private var modelContext
    @Query private var allTasks: [AppTask]
    @State private var keyMonitor: Any? = nil

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
            }
            .preferredColorScheme(.dark)

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
            for task in allTasks where !task.calendarEventID.isEmpty {
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
                    switch hoveredTaskManager.hoveredSource {
                    case .timeline:
                        task.status = task.isDone ? .todo : .done
                    case .list, .kanban, .none:
                        taskCompletionAnimationManager.toggleCompletion(for: task)
                    }
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
}

private struct HoveredTaskDatePickerOverlay: View {
    let request: HoveredTaskDatePickerManager.Request
    let onUpdateDate: (Date) -> Void
    let onConfirm: () -> Void
    let onClear: () -> Void
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

                        CadenceDatePicker(selection: Binding(
                            get: { request.selectedDate },
                            set: onUpdateDate
                        ))
                    }
                }
                .padding(20)

                Divider().background(Theme.borderSubtle)

                HStack(spacing: 10) {
                    Button("Clear", action: onClear)
                        .buttonStyle(.cadencePlain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

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

                    Button("Apply", action: onConfirm)
                        .buttonStyle(.cadencePlain)
                        .keyboardShortcut(.defaultAction)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(request.kind == .doDate ? Theme.blue : Theme.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        case byDoDate = "By Do Date"
        case kanban = "Kanban"
    }

    @State private var mode: AllTasksViewMode = .byDoDate
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
                HStack(spacing: 2) {
                    ForEach(AllTasksViewMode.allCases, id: \.self) { viewMode in
                        Button {
                            mode = viewMode
                        } label: {
                            Text(viewMode.rawValue)
                                .font(.system(size: 11, weight: mode == viewMode ? .semibold : .regular))
                                .foregroundStyle(mode == viewMode ? Theme.blue : Theme.dim)
                                .frame(minWidth: 86, minHeight: 30)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .contentShape(RoundedRectangle(cornerRadius: 5))
                                .background(mode == viewMode ? Theme.blue.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.cadencePlain)
                    }
                }
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            Group {
                switch mode {
                case .byDoDate:
                    TasksPanel(mode: .byDoDate, showsHeader: false)
                case .kanban:
                    TaskListsKanbanView()
                }
            }
        }
        .background(Theme.bg)
    }
}

#endif
