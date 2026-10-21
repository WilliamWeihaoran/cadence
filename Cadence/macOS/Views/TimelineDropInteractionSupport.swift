#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct TimelineDropDelegate: DropDelegate {
    let metrics: TimelineMetrics
    let allTasks: [AppTask]
    let onDropTaskAtMinute: (AppTask, Int) -> Void
    let onDropAllDayEventAtMinute: ((CalendarAllDayEventDropPayload, Int) -> Void)?

    @Binding var isTargeted: Bool
    @Binding var previewTaskID: UUID?
    @Binding var previewStartMin: Int?
    @Binding var activeDragTaskID: UUID?
    @Binding var selectedTaskID: UUID?
    @Binding var dragYOffset: CGFloat

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [UTType.text]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        if let taskID = activeDragTaskID,
           let task = allTasks.first(where: { $0.id == taskID }) {
            let taskTopY = metrics.yOffset(for: task.scheduledStartMin)
            dragYOffset = info.location.y - taskTopY
        } else {
            dragYOffset = 0
        }
        updatePreview(with: info)
        resolveTaskID(from: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isTargeted else { return DropProposal(operation: .cancel) }
        updatePreview(with: info)
        resolveTaskID(from: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        previewTaskID = nil
        previewStartMin = nil
        dragYOffset = 0
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let startMin = previewStartMin ?? metrics.snappedMinute(fromY: info.location.y - dragYOffset)

        previewTaskID = nil
        previewStartMin = nil
        activeDragTaskID = nil
        selectedTaskID = nil
        dragYOffset = 0

        guard let provider = info.itemProviders(for: [UTType.text]).first else {
            return false
        }

        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString else { return }
            let payloadString = payload as String
            if let eventPayload = CalendarEventDragPayload.allDayEventPayload(from: payloadString) {
                Task { @MainActor in
                    onDropAllDayEventAtMinute?(eventPayload, startMin)
                }
            } else if let uuid = taskID(from: payloadString) {
                Task { @MainActor in
                    guard let task = allTasks.first(where: { $0.id == uuid }) else { return }
                    onDropTaskAtMinute(task, startMin)
                }
            }
        }
        return true
    }

    private func updatePreview(with info: DropInfo) {
        previewStartMin = metrics.snappedMinute(fromY: info.location.y - dragYOffset)
    }

    private func resolveTaskID(from info: DropInfo) {
        guard previewTaskID == nil,
              let provider = info.itemProviders(for: [UTType.text]).first else { return }

        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString,
                  let uuid = taskID(from: payload as String) else { return }

            Task { @MainActor in
                guard isTargeted else { return }
                previewTaskID = uuid
            }
        }
    }

    nonisolated private func taskID(from payload: String) -> UUID? {
        TaskDragPayload.taskID(from: payload)
    }
}
#endif
