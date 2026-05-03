#if os(macOS)
import SwiftData
import SwiftUI

private enum GoalTimelineBarDragMode {
    case move
    case leading
    case trailing
}

struct GoalTimelineBarView: View {
    @Environment(\.modelContext) private var modelContext

    let goal: Goal
    let rangeStart: Date
    let dayWidth: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    @State private var activeDragMode: GoalTimelineBarDragMode?
    @State private var activeDeltaDays = 0

    private var goalRange: (start: Date, end: Date)? {
        guard let start = goal.startDateDate,
              let end = goal.endDateDate else {
            return nil
        }
        return (start, end)
    }

    private var displayedRange: (start: Date, end: Date)? {
        guard let goalRange else { return nil }
        guard let activeDragMode else { return goalRange }

        switch activeDragMode {
        case .move:
            return GoalTimelineDateMath.movedRange(
                start: goalRange.start,
                end: goalRange.end,
                dayDelta: activeDeltaDays
            )
        case .leading:
            return GoalTimelineDateMath.resizedRange(
                start: goalRange.start,
                end: goalRange.end,
                edge: .leading,
                dayDelta: activeDeltaDays
            )
        case .trailing:
            return GoalTimelineDateMath.resizedRange(
                start: goalRange.start,
                end: goalRange.end,
                edge: .trailing,
                dayDelta: activeDeltaDays
            )
        }
    }

    private var displayedFrame: GoalTimelineBarFrame? {
        guard let displayedRange else { return nil }
        return GoalTimelineDateMath.barFrame(
            start: displayedRange.start,
            end: displayedRange.end,
            rangeStart: rangeStart,
            dayWidth: dayWidth
        )
    }

    var body: some View {
        if let frame = displayedFrame {
            barContent
                .frame(width: max(40, frame.width), height: 28)
                .offset(x: frame.x)
                .onTapGesture(perform: onSelect)
                .onTapGesture(count: 2, perform: onEdit)
        }
    }

    private var barContent: some View {
        let color = Color(hex: goal.colorHex)

        return ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(goal.status == .done ? 0.10 : 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected ? color.opacity(0.95) : color.opacity(0.55), lineWidth: isSelected ? 1.5 : 1)
                )

            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(color, lineWidth: 1.5)
                    .background(Circle().fill(color.opacity(goal.status == .done ? 0.5 : 0.12)))
                    .frame(width: 15, height: 15)
                Text(goal.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)

            HStack(spacing: 0) {
                resizeHandle(edge: .leading)
                Spacer(minLength: 0)
                resizeHandle(edge: .trailing)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .gesture(dragGesture(mode: .move))
        .shadow(color: isSelected ? color.opacity(0.18) : Color.clear, radius: 8, y: 2)
    }

    private func resizeHandle(edge: GoalTimelineBarDragMode) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .gesture(dragGesture(mode: edge))
    }

    private func dragGesture(mode: GoalTimelineBarDragMode) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                activeDragMode = mode
                activeDeltaDays = GoalTimelineDateMath.dayDelta(
                    for: value.translation.width,
                    dayWidth: dayWidth
                )
            }
            .onEnded { value in
                let delta = GoalTimelineDateMath.dayDelta(
                    for: value.translation.width,
                    dayWidth: dayWidth
                )
                commit(mode: mode, deltaDays: delta)
                activeDragMode = nil
                activeDeltaDays = 0
            }
    }

    private func commit(mode: GoalTimelineBarDragMode, deltaDays: Int) {
        guard deltaDays != 0, let goalRange else { return }

        let newRange: (start: Date, end: Date)?
        switch mode {
        case .move:
            newRange = GoalTimelineDateMath.movedRange(
                start: goalRange.start,
                end: goalRange.end,
                dayDelta: deltaDays
            )
        case .leading:
            newRange = GoalTimelineDateMath.resizedRange(
                start: goalRange.start,
                end: goalRange.end,
                edge: .leading,
                dayDelta: deltaDays
            )
        case .trailing:
            newRange = GoalTimelineDateMath.resizedRange(
                start: goalRange.start,
                end: goalRange.end,
                edge: .trailing,
                dayDelta: deltaDays
            )
        }

        guard let newRange else { return }
        goal.startDate = DateFormatters.dateKey(from: newRange.start)
        goal.endDate = DateFormatters.dateKey(from: newRange.end)
        try? modelContext.save()
    }
}
#endif
