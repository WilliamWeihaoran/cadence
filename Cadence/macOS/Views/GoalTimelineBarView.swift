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
    let onOpen: () -> Void

    private var goalRange: (start: Date, end: Date)? {
        guard let start = goal.startDateDate,
              let end = goal.endDateDate else {
            return nil
        }
        return (start, end)
    }

    /// Where the bar is drawn. **The goal's own dates, and only those, since [[T-2079]].**
    ///
    /// This used to be a live drag preview: `activeDragMode` and `activeDeltaDays` were set by the
    /// bar's own `DragGesture` and ran `goalRange` through `GoalTimelineDateMath` so the bar
    /// followed the pointer before the drop wrote the dates. The gesture is gone with the write it
    /// committed, so nothing could ever set those two again and the switch was unreachable in every
    /// arm — a `@State` that is only ever read is invisible to the compiler, which is why it is
    /// removed by hand here rather than by a build error.
    private var displayedRange: (start: Date, end: Date)? { goalRange }

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
                // Higher count first — see `GoalTimelineGoalRailRow`. Reversed, the single-tap
                // recognizer swallows the event and double-click-to-open never fires.
                .onTapGesture(count: 2, perform: onOpen)
                .onTapGesture(perform: onSelect)
        }
    }

    private var barContent: some View {
        let color = Color(hex: goal.colorHex)

        return ZStack {
            RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
                .fill(color.opacity(goal.status == .done ? 0.10 : 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusControlCompact)
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
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControlCompact))
        .shadow(color: isSelected ? color.opacity(0.18) : Color.clear, radius: 8, y: 2)
    }

    /// The resize handles, **inert since [[T-2079]]**.
    ///
    /// They are the only part of this bar that is not purely drawn: dragging one, or dragging the
    /// bar itself, wrote `goal.startDate` and `goal.endDate` directly and committed with a bare
    /// `try? modelContext.save()`. That made the roadmap a goal **editor** — the one in the app
    /// that never went through the retired `saveGoal`, which is exactly why
    /// emptying that helper did not produce a compile error here and why the write survived the
    /// first sweep of this ticket. It was found by a field-write sweep afterwards.
    ///
    /// The handles keep their 10pt reservation because the bar's layout is measured against it;
    /// they draw nothing and now do nothing.
    private func resizeHandle(edge: GoalTimelineBarDragMode) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
    }

    // **The drag gesture and its `commit` were deleted by [[T-2079]].** `commit` ended in
    // `goal.startDate = …`, `goal.endDate = …` and a bare `try? modelContext.save()` — a direct
    // `Goal` write, open-coded rather than routed through the shared save helper, which is what
    // made it invisible to the compiler when that helper was emptied. `GoalTimelineDateMath` is
    // NOT removed: `movedRange`, `resizedRange` and `dayDelta` are pure arithmetic with their own
    // tests, and the bar still reads them to draw its own position.
}
#endif
