#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTaskRowTrailingSwipeActions: View {
    let task: AppTask
    @Binding var showDeleteConfirmation: Bool
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            CadenceTaskMutationSupport.toggleCompletion(task, modelContext: modelContext)
        } label: {
            Label(task.isDone ? "Todo" : "Done",
                  systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
        }
        .tint(task.isDone ? Theme.blue : Theme.green)

        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

struct iOSTaskRowLeadingSwipeActions: View {
    let task: AppTask
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            CadenceTaskMutationSupport.scheduleToday(task, modelContext: modelContext)
        } label: {
            Label("Today", systemImage: "sun.max.fill")
        }
        .tint(Theme.amber)

        Button {
            CadenceTaskMutationSupport.scheduleTomorrow(task, modelContext: modelContext)
        } label: {
            Label("Tomorrow", systemImage: "calendar")
        }
        .tint(Theme.blue)

        Button {
            CadenceTaskMutationSupport.dueToday(task, modelContext: modelContext)
        } label: {
            Label("Due", systemImage: "flag.fill")
        }
        .tint(Theme.red)

        if !task.scheduledDate.isEmpty {
            Button {
                CadenceTaskMutationSupport.clearScheduledDate(task, modelContext: modelContext)
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .tint(Theme.dim)
        }
    }
}

struct iOSTaskRowContextMenu: View {
    let task: AppTask
    let allTasks: [AppTask]
    let activeAreas: [Area]
    let activeProjects: [Project]
    @Binding var showDetail: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var pendingRecurrenceRule: TaskRecurrenceRule?
    @Environment(\.modelContext) private var modelContext

    private var availableSectionNames: [String] {
        let rawNames = task.area?.sectionNames ?? task.project?.sectionNames ?? []
        let names = rawNames.isEmpty ? [TaskSectionDefaults.defaultName] : rawNames
        if names.contains(where: { $0.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame }) {
            return names
        }
        return names + [task.resolvedSectionName]
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            Label("Edit", systemImage: "square.and.pencil")
        }

        statusMenu
        priorityMenu
        recurrenceMenu
        doDateMenu
        dueDateMenu
        sectionMenu
        moveToListMenu

        Button {
            _ = try? CadenceTaskMutationSupport.duplicate(task, allTasks: allTasks, modelContext: modelContext)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete Task", systemImage: "trash")
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button {
                    CadenceTaskMutationSupport.setStatus(status, for: task, modelContext: modelContext)
                } label: {
                    Label(status.label, systemImage: status.systemImage)
                }
            }
        } label: {
            Label(task.status.label, systemImage: task.status.systemImage)
        }
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button {
                    CadenceTaskMutationSupport.setPriority(priority, for: task, modelContext: modelContext)
                } label: {
                    Label(priority.label, systemImage: priority == task.priority ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            Label("Priority: \(task.priority.label)", systemImage: "flag.fill")
        }
    }

    private var recurrenceMenu: some View {
        Menu {
            ForEach(TaskRecurrenceRule.allCases, id: \.self) { recurrence in
                Button {
                    selectRecurrenceRule(recurrence)
                } label: {
                    Label(
                        recurrence.label,
                        systemImage: recurrence == task.recurrenceRule ? "checkmark.circle.fill" : recurrence.systemImage
                    )
                }
            }
        } label: {
            Label(task.recurrenceRule == .none ? "Repeat" : "Repeat: \(task.recurrenceRule.shortLabel)", systemImage: "repeat")
        }
    }

    private var doDateMenu: some View {
        Menu {
            Button {
                CadenceTaskMutationSupport.scheduleToday(task, modelContext: modelContext)
            } label: {
                Label("Today", systemImage: "sun.max.fill")
            }

            Button {
                CadenceTaskMutationSupport.scheduleTomorrow(task, modelContext: modelContext)
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }

            Button {
                CadenceTaskMutationSupport.scheduleNextWeek(task, modelContext: modelContext)
            } label: {
                Label("Next Week", systemImage: "calendar.badge.clock")
            }

            if !task.scheduledDate.isEmpty {
                Button {
                    CadenceTaskMutationSupport.clearScheduledDate(task, modelContext: modelContext)
                } label: {
                    Label("Clear Do Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Do Date", systemImage: "sun.max.fill")
        }
    }

    private var dueDateMenu: some View {
        Menu {
            Button {
                CadenceTaskMutationSupport.dueToday(task, modelContext: modelContext)
            } label: {
                Label("Today", systemImage: "flag.fill")
            }

            Button {
                CadenceTaskMutationSupport.dueTomorrow(task, modelContext: modelContext)
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }

            Button {
                CadenceTaskMutationSupport.dueNextWeek(task, modelContext: modelContext)
            } label: {
                Label("Next Week", systemImage: "calendar.badge.clock")
            }

            if !task.dueDate.isEmpty {
                Button {
                    CadenceTaskMutationSupport.clearDueDate(task, modelContext: modelContext)
                } label: {
                    Label("Clear Due Date", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Due Date", systemImage: "flag.fill")
        }
    }

    @ViewBuilder
    private var sectionMenu: some View {
        let names = availableSectionNames
        if names.count > 1 {
            Menu {
                ForEach(names, id: \.self) { section in
                    Button {
                        CadenceTaskMutationSupport.moveToSection(section, task: task, modelContext: modelContext)
                    } label: {
                        Label(section, systemImage: section.caseInsensitiveCompare(task.resolvedSectionName) == .orderedSame ? "checkmark.circle.fill" : "rectangle.split.3x1")
                    }
                }
            } label: {
                Label("Move Section", systemImage: "rectangle.split.3x1.fill")
            }
        }
    }

    private var moveToListMenu: some View {
        Menu {
            Button {
                moveToContainer(area: nil, project: nil)
            } label: {
                Label("Inbox", systemImage: task.area == nil && task.project == nil ? "checkmark.circle.fill" : "tray.fill")
            }

            if !activeAreas.isEmpty {
                Divider()

                ForEach(activeAreas) { area in
                    Button {
                        moveToContainer(area: area, project: nil)
                    } label: {
                        Label(area.name.isEmpty ? "Untitled Area" : area.name, systemImage: task.area?.id == area.id && task.project == nil ? "checkmark.circle.fill" : area.icon)
                    }
                }
            }

            if !activeProjects.isEmpty {
                Divider()

                ForEach(activeProjects) { project in
                    Button {
                        moveToContainer(area: nil, project: project)
                    } label: {
                        Label(project.name.isEmpty ? "Untitled Project" : project.name, systemImage: task.project?.id == project.id ? "checkmark.circle.fill" : project.icon)
                    }
                }
            }
        } label: {
            Label("Move to List", systemImage: "folder.fill")
        }
    }

    private func selectRecurrenceRule(_ rule: TaskRecurrenceRule) {
        guard task.recurrenceRule != rule else { return }
        if task.isRecurrenceSeriesMember {
            pendingRecurrenceRule = rule
        } else {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                rule,
                to: task,
                allTasks: allTasks,
                scope: .thisTask
            )
            try? modelContext.save()
        }
    }

    private func moveToContainer(area: Area?, project: Project?) {
        CadenceTaskMutationSupport.moveToContainer(
            task,
            area: area,
            project: project,
            sectionName: task.resolvedSectionName,
            allTasks: allTasks,
            modelContext: modelContext
        )
    }
}

struct iOSTaskRowRecurrenceScopeDialogModifier: ViewModifier {
    let task: AppTask
    let allTasks: [AppTask]
    @Binding var pendingRecurrenceRule: TaskRecurrenceRule?
    @Environment(\.modelContext) private var modelContext

    private var isPresented: Binding<Bool> {
        Binding(
            get: { pendingRecurrenceRule != nil },
            set: { presented in
                if !presented {
                    pendingRecurrenceRule = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Change repeating task?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button(CadenceTaskRecurrenceEditScope.thisTask.label) {
                applyPendingRecurrenceRule(scope: .thisTask)
            }
            Button(CadenceTaskRecurrenceEditScope.thisAndFuture.label) {
                applyPendingRecurrenceRule(scope: .thisAndFuture)
            }
            Button("Cancel", role: .cancel) {
                pendingRecurrenceRule = nil
            }
        } message: {
            Text("Choose whether this repeat change applies only here or to this task and future instances.")
        }
    }

    private func applyPendingRecurrenceRule(scope: CadenceTaskRecurrenceEditScope) {
        guard let pendingRecurrenceRule else { return }
        CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
            pendingRecurrenceRule,
            to: task,
            allTasks: allTasks,
            scope: scope
        )
        self.pendingRecurrenceRule = nil
        try? modelContext.save()
    }
}

extension View {
    func iOSTaskRowRecurrenceScopeDialog(
        task: AppTask,
        allTasks: [AppTask],
        pendingRecurrenceRule: Binding<TaskRecurrenceRule?>
    ) -> some View {
        modifier(iOSTaskRowRecurrenceScopeDialogModifier(
            task: task,
            allTasks: allTasks,
            pendingRecurrenceRule: pendingRecurrenceRule
        ))
    }
}
#endif
