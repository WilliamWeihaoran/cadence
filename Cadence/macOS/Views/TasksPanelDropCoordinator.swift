#if os(macOS)
import Foundation

struct TasksPanelDropCoordinator {
    let allTasks: [AppTask]
    let taskIDFromPayload: (String) -> UUID?
    let assignTask: (AppTask, String) -> Void
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

    func handleSectionDrop(payload: String, dropKey: String) -> Bool {
        guard let (_, droppedTask) = droppedTask(from: payload) else { return false }
        assignTask(droppedTask, dropKey)
        return true
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
            assignTask(droppedTask, dropKey)
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
