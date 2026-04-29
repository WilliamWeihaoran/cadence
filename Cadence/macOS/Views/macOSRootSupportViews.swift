#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct RootSidebarToggleButton: View {
    let isSidebarHidden: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSidebarHidden ? "sidebar.left" : "sidebar.leading")
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
        .help(isSidebarHidden ? "Show Sidebar (Cmd+O)" : "Hide Sidebar (Cmd+O)")
    }
}

struct RootTimelineSidebarPane: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Today Timeline")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Spacer()
                Button(action: onClose) {
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
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.borderSubtle.opacity(0.85))
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

struct TaskCreationLayerView: View {
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
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(0.95), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.42), radius: 34, x: 0, y: 18)
                    .shadow(color: Theme.blue.opacity(0.08), radius: 18, x: 0, y: 0)
                    .onTapGesture {
                        // Prevent outside tap handler from firing when clicking inside the panel.
                    }
            }
            .transition(.opacity)
            .zIndex(10)
        }
    }
}

struct SuccessToastLayerView: View {
    @Environment(TaskCreationManager.self) private var taskCreationManager

    var body: some View {
        if taskCreationManager.showSuccessToast {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.green)
                    Text("Task Created")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(Theme.surfaceElevated.opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
                .padding(.bottom, 36)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .zIndex(30)
        }
    }
}

struct DeleteConfirmationLayerView: View {
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

struct DatePickerLayerView: View {
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

struct GlobalSearchLayerView: View {
    @Environment(GlobalSearchManager.self) private var globalSearchManager
    let onSelect: (GlobalSearchResult) -> Void

    var body: some View {
        if globalSearchManager.isPresented {
            GlobalSearchOverlay(
                onSelect: onSelect,
                onDismiss: { globalSearchManager.dismiss() }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .zIndex(40)
        }
    }
}

struct HoveredTaskDatePickerOverlay: View {
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
                    CadenceActionButton(
                        title: "Clear",
                        role: .destructive,
                        size: .regular,
                        minWidth: 74
                    ) {
                        onClear()
                    }

                    Spacer()

                    CadenceActionButton(
                        title: "Cancel",
                        role: .secondary,
                        size: .regular,
                        tint: Theme.dim,
                        minWidth: 96,
                        shortcut: .cancelAction
                    ) {
                        onCancel()
                    }

                    CadenceActionButton(
                        title: "Apply",
                        role: .primary,
                        size: .regular,
                        tint: request.kind == .doDate ? Theme.blue : Theme.amber,
                        minWidth: 96,
                        shortcut: .defaultAction
                    ) {
                        onConfirm()
                    }
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

struct DeleteConfirmationOverlay: View {
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
                    CadenceActionButton(
                        title: "Cancel",
                        role: .secondary,
                        size: .regular,
                        tint: Theme.dim,
                        minWidth: 96,
                        shortcut: .cancelAction
                    ) {
                        onCancel()
                    }

                    CadenceActionButton(
                        title: confirmLabel,
                        role: .primary,
                        size: .regular,
                        tint: Theme.red,
                        minWidth: 96,
                        shortcut: .defaultAction
                    ) {
                        onConfirm()
                    }
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

struct AllTasksPageView: View {
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
                    AllTasksListView(
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

struct EnumFilterPickerBadge<T: CaseIterable & RawRepresentable & Identifiable>: View where T.RawValue == String {
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
