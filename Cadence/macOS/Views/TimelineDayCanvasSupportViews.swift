#if os(macOS)
import SwiftUI

/// The hour rules and half-hour ticks behind the canvas.
///
/// Purely decorative: this used to be the same `VStack` of hour rows that *also* carried the
/// drag-to-create gesture, which meant the gesture's canvas Y was reconstructed from a row index
/// (`(hour - startHour) * hourHeight + localY`). Adding a divider or any spacing here would have
/// silently pushed every drag-to-create a little further off the further down the day you went.
/// Now the rows draw and nothing else, and the gesture reads the canvas coordinate space directly.
///
/// **The ladder has a rung now ([[T-1129]]).** Every third hour is drawn heavier than the two
/// between it, the way both iOS timed surfaces have drawn since [[T-596]] — the repository owner's
/// answer to [[T-619]]'s open question, chosen over leaving the Mac flat and over taking the rung
/// off iOS. The cadence and the two weights come from `CadenceCalendarHourLadderMetrics`, one read
/// for both platforms, because copying a `% 3` across without the weights it selects between is
/// precisely what produced the drift that ticket exists to end.
///
/// **Three lines, in order.** `ruleOpacity` × `hourRuleWidth` gives 0.437 ink on a rung and 0.190
/// on an ordinary hour; the half-hour tick is 0.142 and appears only at `showHalfHourMarks`. The
/// ordering is the point — a tick heavier than the hour it bisects would turn the grid into
/// 30-minute rows — and `CalendarVisualStyle.halfHourTickOpacity` records how the tick was
/// re-derived to keep it.
struct TimelineHourGridLines: View {
    let metrics: TimelineMetrics
    let showHalfHourMarks: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(metrics.startHour..<metrics.endHour, id: \.self) { hour in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.hourHeight)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(
                                Theme.borderSubtle.opacity(
                                    CadenceCalendarHourLadderMetrics.ruleOpacity(hour: hour)
                                )
                            )
                            .frame(height: CalendarVisualStyle.hourRuleWidth)
                    }
                    .overlay(alignment: .top) {
                        if showHalfHourMarks {
                            Rectangle()
                                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.halfHourTickOpacity))
                                .frame(height: CalendarVisualStyle.halfHourTickWidth)
                                .offset(y: metrics.hourHeight / 2)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

#endif
