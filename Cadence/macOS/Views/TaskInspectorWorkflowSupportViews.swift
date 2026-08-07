#if os(macOS)
import SwiftUI
import SwiftData

struct TaskInspectorRecurrenceControl: View {
    @Bindable var task: AppTask
    @Query private var allTasks: [AppTask]
    @Environment(\.modelContext) private var modelContext
    @State private var pendingRule: TaskRecurrenceRule?

    var body: some View {
        Menu {
            ForEach(TaskRecurrenceRule.allCases, id: \.self) { rule in
                Button {
                    selectRule(rule)
                } label: {
                    Label(rule.label, systemImage: rule.systemImage)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: task.recurrenceRule.systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(task.isRecurring ? Theme.blue : Theme.dim)
                Text(recurrenceLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(task.isRecurring ? Theme.text : Theme.dim)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .confirmationDialog(
            "Change repeating task?",
            isPresented: Binding(
                get: { pendingRule != nil },
                set: { if !$0 { pendingRule = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(TaskRecurrenceEditScope.thisTask.label) {
                applyPendingRule(scope: .thisTask)
            }
            Button(TaskRecurrenceEditScope.thisAndFuture.label) {
                applyPendingRule(scope: .thisAndFuture)
            }
            Button("Cancel", role: .cancel) {
                pendingRule = nil
            }
        } message: {
            Text("Choose whether this repeat change applies only here or to this task and future instances.")
        }
    }

    private var recurrenceLabel: String {
        task.recurrenceRule == .none ? "No repeat" : task.recurrenceRule.shortLabel
    }

    private func selectRule(_ rule: TaskRecurrenceRule) {
        guard task.recurrenceRule != rule else { return }
        if task.isRecurrenceSeriesMember {
            pendingRule = rule
        } else {
            TaskWorkflowService.applyRecurrenceRule(rule, to: task, allTasks: allTasks, scope: .thisTask)
            try? modelContext.save()
        }
    }

    private func applyPendingRule(scope: TaskRecurrenceEditScope) {
        guard let pendingRule else { return }
        TaskWorkflowService.applyRecurrenceRule(pendingRule, to: task, allTasks: allTasks, scope: scope)
        self.pendingRule = nil
        try? modelContext.save()
    }
}
#endif
