#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct TimelineCreateRow: View {
    let hour: Int
    let metrics: TimelineMetrics
    let blockedFrames: [TimelineBlockFrame]
    let showHalfHourMark: Bool
    @Binding var activeDragTaskID: UUID?
    let onTapBackground: () -> Void
    let onDragChanged: (Int, Int) -> Void
    let onDragEnded: (Int, Int) -> Void

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.hourHeight)
            .overlay(alignment: .top) {
                Divider().background(Theme.borderSubtle.opacity(0.5))
            }
            .overlay(alignment: .top) {
                if showHalfHourMark {
                    Rectangle()
                        .fill(Theme.borderSubtle.opacity(0.18))
                        .frame(height: 0.5)
                        .offset(y: metrics.hourHeight / 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTapBackground)
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        guard activeDragTaskID == nil else { return }
                        let startPoint = absolutePoint(for: value.startLocation)
                        guard !isInsideBlockedBlock(point: startPoint) else { return }
                        onDragChanged(
                            absoluteMinute(forLocalY: value.startLocation.y),
                            absoluteMinute(forLocalY: value.location.y)
                        )
                    }
                    .onEnded { value in
                        guard activeDragTaskID == nil else { return }
                        let startPoint = absolutePoint(for: value.startLocation)
                        guard !isInsideBlockedBlock(point: startPoint) else { return }
                        onDragEnded(
                            absoluteMinute(forLocalY: value.startLocation.y),
                            absoluteMinute(forLocalY: value.location.y)
                        )
                    }
            )
    }

    private func absoluteY(forLocalY y: CGFloat) -> CGFloat {
        CGFloat(hour - metrics.startHour) * metrics.hourHeight + y
    }

    private func absolutePoint(for localPoint: CGPoint) -> CGPoint {
        CGPoint(x: localPoint.x, y: absoluteY(forLocalY: localPoint.y))
    }

    private func absoluteMinute(forLocalY y: CGFloat) -> Int {
        metrics.snappedMinute(fromY: absoluteY(forLocalY: y))
    }

    private func isInsideBlockedBlock(point: CGPoint) -> Bool {
        blockedFrames.contains { frame in
            point.x >= frame.x &&
            point.x <= frame.x + frame.width &&
            point.y >= frame.y &&
            point.y <= frame.y + frame.height
        }
    }
}

struct TimelineDropDelegate: DropDelegate {
    let metrics: TimelineMetrics
    let allTasks: [AppTask]
    let onDropTaskAtMinute: (AppTask, Int) -> Void
    let onDropAllDayEventAtMinute: ((String, Int) -> Void)?

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
        activeDragTaskID = nil
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
            if payloadString.hasPrefix("allDayEvent:") {
                let eventID = String(payloadString.dropFirst(12))
                guard !eventID.isEmpty else { return }
                Task { @MainActor in
                    onDropAllDayEventAtMinute?(eventID, startMin)
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

    private func taskID(from payload: String) -> UUID? {
        if payload.hasPrefix("listTask:") {
            return UUID(uuidString: String(payload.dropFirst(9)))
        }
        return UUID(uuidString: payload)
    }
}
#endif
