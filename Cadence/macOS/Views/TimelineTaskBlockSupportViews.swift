#if os(macOS)
import SwiftUI

struct TimelineDraggedTaskPreview: View {
    let task: AppTask
    let startMinute: Int
    let durationMinutes: Int
    let column: Int
    let totalColumns: Int
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle

    private var frame: TimelineBlockFrame {
        computeTimelineBlockFrame(
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            column: column,
            totalColumns: totalColumns,
            totalWidth: totalWidth,
            metrics: metrics,
            style: style
        )
    }

    private var timeRangeLabel: String {
        TimeFormatters.timeRange(startMin: startMinute, endMin: startMinute + max(durationMinutes, 5))
    }

    private var dragDurationLabel: String {
        guard durationMinutes > 0 else { return "" }
        if durationMinutes < 60 { return "\(durationMinutes)m" }
        if durationMinutes % 60 == 0 { return "\(durationMinutes / 60)h" }
        return String(format: "%.1fh", Double(durationMinutes) / 60.0)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(Theme.blue.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: style.cornerRadius)
                            .stroke(Theme.blue.opacity(0.55), lineWidth: 1)
                    )
                    .frame(width: frame.width, height: frame.height)

                timelineBlockBody(
                    task: task,
                    durationMinutes: durationMinutes,
                    timeRangeLabel: timeRangeLabel,
                    frame: frame,
                    style: style,
                    showSelection: true
                )
                .opacity(0.92)
            }

            if !dragDurationLabel.isEmpty {
                Text(dragDurationLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Theme.bg.opacity(0.94))
                            .overlay(
                                Capsule()
                                    .stroke(Theme.blue.opacity(0.45), lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .offset(x: -8, y: -10)
            }
        }
        .allowsHitTesting(false)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.centerX, y: frame.centerY)
    }
}

struct TimelineCurrentTimeOverlay: View {
    let date: Date
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    let showDot: Bool

    private var minutesFromMidnight: Int {
        let calendar = Calendar.current
        return calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())
    }

    private var yOffset: CGFloat {
        metrics.yOffset(for: minutesFromMidnight)
    }

    var body: some View {
        let calendar = Calendar.current
        let mins = minutesFromMidnight

        if calendar.isDateInToday(date),
           mins >= metrics.startHour * 60,
           mins <= metrics.endHour * 60 {
            ZStack(alignment: .topLeading) {
                if showDot {
                    Circle()
                        .fill(Theme.red)
                        .frame(width: 8, height: 8)
                        .offset(x: style.leadingInset - 4, y: yOffset - 4)
                }

                Rectangle()
                    .fill(Theme.red)
                    .frame(
                        width: max(0, totalWidth - style.leadingInset - style.trailingInset + (showDot ? 4 : 0)),
                        height: 1
                    )
                    .offset(x: showDot ? style.leadingInset - 4 : style.leadingInset, y: yOffset)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct DiagonalStripeOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 10
            let lineWidth: CGFloat = 3
            let totalLines = Int((size.width + size.height) / spacing) + 2
            for i in 0..<totalLines {
                let offset = CGFloat(i) * spacing
                var path = Path()
                path.move(to: CGPoint(x: offset - size.height, y: 0))
                path.addLine(to: CGPoint(x: offset, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
    }
}

@ViewBuilder
func timelineBlockBody(
    task: AppTask,
    durationMinutes: Int,
    timeRangeLabel: String,
    frame: TimelineBlockFrame,
    style: TimelineBlockStyle,
    showSelection: Bool,
    showHover: Bool = false,
    isPendingCompletion: Bool = false,
    completionProgress: Double = 0,
    onToggleDone: (() -> Void)? = nil
) -> some View {
    let taskColor = Color(hex: task.containerColor)
    let clampedProgress = min(max(completionProgress, 0), 1)
    let completedTransitionOpacity = max(0, (clampedProgress - 0.58) / 0.42)
    let greenOverlayOpacity = 0.28 * (1 - max(0, (clampedProgress - 0.8) / 0.2))
    HStack(alignment: .top, spacing: 0) {
        taskColor
            .opacity(task.isDone ? 0.4 : 1)
            .frame(width: 3)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: style.cornerRadius,
                bottomLeadingRadius: style.cornerRadius
            ))

        HStack(alignment: .top, spacing: 4) {
            if let onToggleDone {
                Button(action: onToggleDone) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : (isPendingCompletion ? "circle.inset.filled" : "circle"))
                        .font(.system(size: 12))
                        .foregroundStyle(task.isDone || isPendingCompletion ? Theme.green : Theme.dim)
                }
                .buttonStyle(.cadencePlain)
                .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                if frame.height >= 58 {
                    Text(timeRangeLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(taskColor.opacity(0.9))
                        .lineLimit(1)
                }
                if frame.height >= 38 {
                    Text(task.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                        .lineLimit(2)
                    let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: durationMinutes)
                    if label != "-/-" {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.dim)
                    }
                } else {
                    let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: durationMinutes)
                    HStack(spacing: 4) {
                        Text(task.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if label != "-/-" {
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)

        Spacer(minLength: 0)
    }
    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    .clipped()
    .background(
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius).fill(Theme.surfaceElevated)
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(taskColor.opacity(task.isDone ? 0.07 : 0.14))
            if isPendingCompletion {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(taskColor.opacity(0.06 + (0.06 * completedTransitionOpacity)))
            }
            if showHover {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(TimelineHoverVisuals.hoverFill(tint: taskColor, isHovered: showHover, opacity: 0.08))
            }
            if isPendingCompletion {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: style.cornerRadius)
                        .fill(Theme.green.opacity(greenOverlayOpacity))
                        .frame(
                            width: proxy.size.width * clampedProgress,
                            alignment: .leading
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    )
    .overlay {
        if task.isDone {
            DiagonalStripeOverlay()
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
        }
    }
    .overlay(
        RoundedRectangle(cornerRadius: style.cornerRadius)
            .stroke(
                TimelineHoverVisuals.borderColor(
                    tint: taskColor,
                    isSelected: showSelection,
                    isHovered: showHover,
                    selectedOpacity: 0.46,
                    hoverOpacity: 0.38
                ),
                lineWidth: showHover ? 1.2 : 1
            )
    )
    .shadow(
        color: TimelineHoverVisuals.shadowColor(isActive: showHover || showSelection),
        radius: TimelineHoverVisuals.shadowRadius(isActive: showHover || showSelection),
        x: 0,
        y: TimelineHoverVisuals.shadowY(isActive: showHover || showSelection)
    )
}

func timelineDragPreview(task: AppTask, style: TimelineBlockStyle) -> some View {
    Color.clear
        .frame(width: 1, height: 1)
}
#endif
