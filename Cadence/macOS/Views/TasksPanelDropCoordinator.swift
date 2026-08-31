#if os(macOS)
import Foundation

struct TasksPanelDropCoordinator {
    let allTasks: [AppTask]
    let taskIDFromPayload: (String) -> UUID?
    /// Answers whether the key resolved to anything. See `handleSectionDrop`.
    let assignTask: (AppTask, String) -> Bool
    let reorderTask: (UUID, UUID, [AppTask]) -> Void

    func sectionDropHandler(for dropKey: String?) -> ((String) -> Bool)? {
        guard let dropKey else { return nil }
        return { payload in
            handleSectionDrop(payload: payload, dropKey: dropKey)
        }
    }

    func taskDropHandler(scopeTasks: [AppTask], dropKey: String? = nil) -> (String, AppTask) -> Bool {
        { payload, targetTask in
            handleTaskDrop(payload: payload, targetTask: targetTask, scopeTasks: scopeTasks, dropKey: dropKey)
        }
    }

    /// **A drop that applied nothing reports `false`.** This returned `true` unconditionally, so
    /// every Today list header lit up, accepted the row and left it where it was — for as long as
    /// the compound key went unparsed, which is exactly as long as nothing could tell the two
    /// outcomes apart (T-591). A rejected drop springs the row back and says so; a silent accept
    /// says the move happened.
    func handleSectionDrop(payload: String, dropKey: String) -> Bool {
        guard let (_, droppedTask) = droppedTask(from: payload) else { return false }
        return assignTask(droppedTask, dropKey)
    }

    func handleTaskDrop(
        payload: String,
        targetTask: AppTask,
        scopeTasks: [AppTask],
        dropKey: String? = nil
    ) -> Bool {
        guard let (droppedID, droppedTask) = droppedTask(from: payload),
              droppedID != targetTask.id else { return false }
        if let dropKey {
            // Ignored deliberately, unlike `handleSectionDrop`: the reorder below runs either way,
            // so a row drop whose key resolved to nothing still moved the row and is not the
            // silent accept T-591 was about.
            _ = assignTask(droppedTask, dropKey)
        }
        reorderTask(droppedID, targetTask.id, scopeTasks)
        return true
    }

    private func droppedTask(from payload: String) -> (UUID, AppTask)? {
        guard let droppedID = taskIDFromPayload(payload),
              let droppedTask = allTasks.first(where: { $0.id == droppedID }) else {
            return nil
        }
        return (droppedID, droppedTask)
    }
}
#endif
