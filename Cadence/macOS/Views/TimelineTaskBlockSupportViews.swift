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
        return CadenceTaskPresentationSupport.estimateLabel(minutes: durationMinutes)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(Theme.blue.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: style.cornerRadius)
                            .strokeBorder(Theme.blue.opacity(0.55), lineWidth: 1)
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
                                    .strokeBorder(Theme.blue.opacity(0.45), lineWidth: 1)
                            )
                    )
                    .shadow(color: Theme.chipShadow, radius: 8, y: 3)
                    .offset(x: -8, y: -10)
            }
        }
        .allowsHitTesting(false)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.centerX, y: frame.centerY)
    }
}

/// The Mac's adapter onto the app's one now-line.
///
/// **The drawing moved to `CadenceTimelineNowLine` in `Shared/Components/` ([[T-1131]]).** It is
/// byte-for-byte the same mark — same `Theme.red`, same 1pt rule, same 8pt dot, same 15-second
/// tick — but iOS's two timed surfaces had nothing of the kind, and the repo rule is one shared
/// component over near-copies. What stays here is the only macOS-shaped part: `TimelineMetrics` and
/// `TimelineBlockStyle` are macOS types, so something has to read the start/end hours and the two
/// insets off them and hand over `metrics.yOffset(forFractionalMinute:)` as the canvas's own
/// minute-to-Y. Passing that function rather than an hour height is what keeps the red line on the
/// same expression as every block beside it — the drift `yOffset(forFractionalMinute:)`'s own doc
/// comment exists to record.
///
/// `TimelineDayCanvas` is unchanged; this type keeps its name and its five parameters.
struct TimelineCurrentTimeOverlay: View {
    let date: Date
    let totalWidth: CGFloat
    let metrics: TimelineMetrics
    let style: TimelineBlockStyle
    let showDot: Bool

    var body: some View {
        CadenceTimelineNowLine(
            day: date,
            totalWidth: totalWidth,
            startHour: metrics.startHour,
            endHour: metrics.endHour,
            leadingInset: style.leadingInset,
            trailingInset: style.trailingInset,
            showDot: showDot,
            yOffset: { metrics.yOffset(forFractionalMinute: $0) }
        )
    }
}

// `DiagonalStripeOverlay` lives in `Cadence/Shared/CadenceCalendarTaskDoneStyle.swift` since
// [[T-8241]], so the iOS timed block draws the same stripes.

@ViewBuilder
func timelineBlockBody(
    task: AppTask,
    todayKey: String = DateFormatters.todayKey(),
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
    let dueUrgency = CadenceDueUrgency.evaluate(dueDateKey: task.dueDate, isDone: task.isDone, todayKey: todayKey)
    let dueLabel = CadenceFocusSupport.dueLabel(forDueDateKey: task.dueDate, todayKey: todayKey)
    let clampedProgress = min(max(completionProgress, 0), 1)
    let pendingOverlayOpacity = 1 - max(0, (clampedProgress - 0.86) / 0.14)
    // **T-3160: the task block wears the solved plate the event block used to wear** — a fill
    // solved to a luminance target in the list's hue, `Theme.onColor`-family content, and **no
    // leading colour rail**. The rail moved to the event side with the rest of Apple Calendar's
    // look; what stays here is every affordance, not the paint: the completion circle, the due
    // marker, the resize handles and the diagonal done-stripes are all untouched below.
    //
    // Both ink tiers are resolved once, against the same state the fill is, because the two have
    // to move together — the state ladder brightens the plate, and a label that did not rise with
    // it would quietly drop under AA on hover.
    let primaryInk = CadenceCalendarEventStyle.platePrimaryLabelColor
    let secondaryInk = CadenceCalendarEventStyle.plateSecondaryLabelColor(
        isSelected: showSelection,
        isActive: showHover
    )
    // A finished task drops one tier instead of going grey. `Theme.dim` measures 1.99 / 1.70 /
    // 1.48:1 against the three plate stops — it was a body-text colour chosen for a near-black
    // surface and this surface is no longer near-black. The diagonal stripes and the filled
    // completion glyph are what still say "done".
    let titleInk = task.isDone ? secondaryInk : primaryInk
    // **The due-urgency hue had to go, and it was measured before it went.**
    //
    // `CadenceDueUrgency.tint` is `Theme.red` / `Theme.amber` / `Theme.dim`, and against this
    // plate's rest / hover / selected stops every accent the app ships lands between **1.63:1 and
    // 4.61:1** — `Theme.red`, the overdue tint, is the worst at 1.72–2.84:1. Only one of the
    // eighteen (Glacier's amber, at rest) clears 4.5:1, and most miss even the 3:1 non-text bar,
    // so a tinted deadline here would be an AA failure on the one line the user is meant to act
    // on. Dark ink is no escape either: black reads 2.96:1 on the rest plate. A fill solved to
    // Y = 0.098–0.150 admits white-family ink and nothing else, which is exactly why
    // `platePrimaryLabelColor` is unconditionally `Theme.onColor`.
    //
    // So urgency moves from the hue to the **tier**, which this label can afford because
    // `CadenceFocusSupport.dueLabel` already says the word: "Overdue Aug 14", "Due today", "Due
    // tomorrow". **The honest cost, stated rather than hidden:** at rest the urgent line is
    // `Theme.onColor` over a non-urgent `Theme.onColorSecondary`, ~13 L* apart and plainly
    // different ink; on hover and selection the secondary tier *has* to rise to white to stay
    // above 4.5:1 on the brighter plate, so the two converge and only the wording separates them
    // there. Buying the distinction back would mean either a hue that fails AA or a fourth white
    // tier under it, which is the same failure wearing a different name.
    let dueInk = (dueUrgency == .overdue || dueUrgency == .dueToday) ? primaryInk : secondaryInk
    HStack(alignment: .top, spacing: 0) {
        HStack(alignment: .top, spacing: 4) {
            if let onToggleDone {
                // Two states before: a cancelled task scheduled onto the timeline drew the same
                // plain circle as an open one. `CadenceTaskCompletionGlyph` is the same decision
                // the task row and the kanban card make.
                let glyph = CadenceTaskCompletionGlyph.resolve(
                    task: task,
                    isPendingCompletion: isPendingCompletion
                )
                Button(action: onToggleDone) {
                    TaskCompletionProgressGlyph(
                        icon: glyph.symbolName,
                        color: glyph.tint,
                        progress: isPendingCompletion ? clampedProgress : nil,
                        size: 13,
                        lineWidth: 1.6
                    )
                }
                .buttonStyle(.cadencePlain)
                .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                if frame.height >= 58 {
                    Text(timeRangeLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }
                if frame.height >= 38 {
                    Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(titleInk)
                        .lineLimit(2)
                    let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: durationMinutes)
                    if label != "-/-" || dueLabel != nil {
                        HStack(spacing: 5) {
                            if label != "-/-" {
                                // The block is hard-clipped to a fixed frame, so a wrapped label would
                                // lose its second line and silently report a shorter duration.
                                Text(label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(secondaryInk)
                                    .lineLimit(1)
                            }
                            if let dueLabel {
                                Text(dueLabel)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(dueInk)
                                    .lineLimit(1)
                                    .layoutPriority(1)
                            }
                        }
                    }
                } else {
                    // The shortest block that still draws text gets one clipped line for title,
                    // duration, and deadline. A due date is a commitment and an estimate is not, so
                    // the duration label is what yields when there is a deadline to print, and the
                    // deadline outranks the title for width so the title truncates first.
                    let label = TimeFormatters.durationLabel(actual: task.actualMinutes, estimated: durationMinutes)
                    HStack(spacing: 4) {
                        Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(titleInk)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let dueLabel {
                            Text(dueLabel)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(dueInk)
                                .lineLimit(1)
                                .layoutPriority(1)
                        } else if label != "-/-" {
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundStyle(secondaryInk)
                                .lineLimit(1)
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
    // Hover and selection are carried by the plate's own luminance ladder, not by a wash stacked
    // on top of it — the same lever the event block already uses, and the reason the white hover
    // wash that used to sit here is gone. A wash lifts the block by draining the hue it exists to
    // show, and it would also break the ink solve: `plateSecondaryLabelColor` is computed against
    // `plateLuminance`, not against whatever a wash happened to composite to.
    .background(
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(
                    CadenceCalendarEventStyle.plateFill(
                        for: taskColor,
                        isSelected: showSelection,
                        isActive: showHover
                    )
                )
            if isPendingCompletion {
                // The second, list-coloured wash that used to ride on top of the fill here
                // (`taskColor.opacity(0.06 + 0.06 * completedTransitionOpacity)`) is gone rather
                // than re-tinted. It warmed a neutral surface toward the list colour as the
                // completion ran; over a plate that is already solved in that colour it would
                // composite to very nearly nothing, so keeping it would have been a line of code
                // pretending to animate. The animation itself is untouched —
                // `TaskCompletionPendingOverlay` is the sweeping glow, the progress capsule and
                // the rim, and the glyph still fills on its own ring.
                TaskCompletionPendingOverlay(
                    progress: clampedProgress,
                    tint: Theme.green,
                    cornerRadius: style.cornerRadius
                )
                .opacity(pendingOverlayOpacity)
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
            .strokeBorder(
                // The hairline is the calendar-style "lit rim of the same hue": the raw list
                // colour over the solved plate, at the plate treatment's own opacities rather
                // than the two this block used while it sat on a neutral surface. A 0.46 rim of
                // the list colour over a near-black surface reads as an edge; over a plate of
                // that same colour it is barely there.
                TimelineHoverVisuals.borderColor(
                    tint: taskColor,
                    isSelected: showSelection,
                    isHovered: showHover,
                    selectedOpacity: CadenceCalendarEventStyle.chipBorderOpacity(isActive: true),
                    hoverOpacity: CadenceCalendarEventStyle.chipBorderOpacity(),
                    idleOpacity: 0.12
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
#endif
