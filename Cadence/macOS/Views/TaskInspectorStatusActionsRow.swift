#if os(macOS)
import SwiftUI
import SwiftData

/// The inspector's Start/Stop and Cancel/Restore pair ([[T-5015]] (a)).
///
/// The same `CadenceTaskInspectorSupport.StatusAction` set the iOS inspector renders in
/// `iOSTaskStatusActionsSection`, with its copy and glyphs, so the two platforms cannot drift on
/// what a status control offers. Before this the only macOS writer of `.inProgress` was the
/// note-embed status popover: a Mac user who never embedded a task could not start one, nor take an
/// iOS-started task back out of In Progress except by completing it.
///
/// Completion stays with "Mark done" in `TaskDetailActionsSection` directly above; each action here
/// owns its one status and is its own undo back to `.todo`, as on iOS. A file of its own rather
/// than more buttons in that row, which already carries a flexible primary and two icon buttons.
struct TaskInspectorStatusActionsRow: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext

    private static let controlHeight: CGFloat = 32
    private static let cornerRadius: CGFloat = Theme.radiusControlCompact

    /// Set when the status change was refused and put back, named where the button is — the
    /// inspector's convention for its own settle (T-628).
    @State private var failureNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(CadenceTaskInspectorSupport.StatusAction.allCases, id: \.self) { action in
                    actionButton(action)
                }
            }
            if let failureNotice {
                CadenceInlineFailureNotice(text: failureNotice)
            }
        }
    }

    private func actionButton(_ action: CadenceTaskInspectorSupport.StatusAction) -> some View {
        let isActive = action.isActive(task.status)
        let tint = isActive ? Theme.statusColor(action.status) : Theme.dim
        return Button {
            do {
                try Self.apply(action, to: task, in: modelContext)
                failureNotice = nil
            } catch {
                failureNotice = CadencePendingChangePersistence.editFailureNotice
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: action.systemImage(for: task.status))
                    .font(.system(size: 12, weight: .semibold))
                Text(action.title(for: task.status))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: Self.controlHeight)
            .background(isActive ? tint.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(isActive ? Color.clear : Theme.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
    }

    /// One tap: the action's target from the current status, committed, then the notification
    /// reconcile every other macOS status writer runs. A refused commit has already been put back
    /// by the shared mutation, so it throws without reconciling.
    static func apply(
        _ action: CadenceTaskInspectorSupport.StatusAction,
        to task: AppTask,
        in context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try CadenceTaskMutationSupport.setStatus(
            action.target(from: task.status),
            for: task,
            modelContext: context,
            commit: commit
        )
        HabitNotificationReconcileSupport.scheduleReconcile(in: context)
    }
}
#endif
