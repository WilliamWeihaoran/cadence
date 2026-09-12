import Foundation
import SwiftUI

/// The arithmetic and the figures behind the now-line, apart from the drawing.
///
/// Split out so the parts that can be wrong are reachable from `CadenceTests`, which builds on
/// macOS and therefore compiles none of `Cadence/iOS/`. The view below is the only drawing; every
/// decision it makes — which minute, whether this column is even today, how wide the rule is and
/// where it starts — is one of these functions.
nonisolated enum CadenceTimelineNowLineSupport {

    /// **How often the line moves, and the answer is macOS's existing 15 seconds ([[T-1131]]).**
    ///
    /// Stated once here rather than typed at each of the three call sites, because the cost is
    /// per-surface and a phone pays it too: a `TimelineView(.periodic)` schedule is a real timer,
    /// and the iOS grid draws one per visible day column. 15s is what the Mac has always paid, so
    /// adopting it adds a platform rather than a cadence. Nothing is gained by going tighter — at
    /// `iOSCalendarTimelineMetrics.hourHeight`'s resting 58pt an hour, one minute is 0.97pt, so a
    /// 15-second tick already moves the rule by roughly a quarter of a point and a 1-second one
    /// would redraw sixty times to move it the same pixel.
    ///
    /// SwiftUI suspends a `TimelineView` schedule while its view is off-screen or the app is not
    /// foreground, so the windowed day columns that are scrolled away stop ticking on their own;
    /// that is a property of the schedule, not something the call sites arrange.
    static let tickInterval: TimeInterval = 15

    /// The dot at the rule's leading end, on the surfaces that draw one.
    static let dotDiameter: CGFloat = 8

    /// The rule itself. 1pt, which is a hairline on the Mac and two device pixels at 2x — the
    /// weight macOS shipped, kept rather than re-decided, because this is the one mark on a timed
    /// grid that is allowed to be louder than the grid.
    static let lineThickness: CGFloat = 1

    /// Minutes since midnight, carrying the seconds as a fraction, in `calendar`'s zone.
    ///
    /// Fractional rather than whole minutes because the line is drawn at a sub-point precision the
    /// tick interval can resolve: truncating to the minute would make the rule jump 0.97pt every
    /// sixty seconds and sit still in between, which reads as a glitch rather than as a clock.
    ///
    /// The calendar is the caller's ([[T-1115]]): a zone read the caller never stated is how a
    /// suite ends up passing on the author's longitude.
    static func fractionalMinuteOfDay(at date: Date, calendar: Calendar = .current) -> CGFloat {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        return CGFloat(hour * 60 + minute) + CGFloat(second) / 60
    }

    /// Does the rule belong on this canvas at all?
    ///
    /// Two independent conditions, and both matter. `day` must be the same day as `now` — the Mac's
    /// canvas is one column and iOS's is a window of them, so on iOS this is what keeps a single
    /// red rule on today's column instead of one on every day of the week. And the minute must be
    /// inside the hours the canvas draws, which is what stops a rule being drawn off the end of a
    /// canvas whose `startHour` is not midnight.
    static func isVisible(
        day: Date,
        now: Date,
        startHour: Int,
        endHour: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard calendar.isDate(day, inSameDayAs: now) else { return false }
        let minute = fractionalMinuteOfDay(at: now, calendar: calendar)
        return minute >= CGFloat(startHour * 60) && minute <= CGFloat(endHour * 60)
    }

    /// Where the rule starts, horizontally. With a dot it backs up by the dot's radius so the rule
    /// leaves the dot's centre rather than its right edge.
    static func lineOriginX(leadingInset: CGFloat, showDot: Bool) -> CGFloat {
        showDot ? leadingInset - dotDiameter / 2 : leadingInset
    }

    /// How wide the rule is, given the canvas it crosses. Floored at zero so a canvas narrower
    /// than its own insets — a column mid-pinch, or a pane being dragged closed — cannot ask for a
    /// negative frame.
    static func lineWidth(
        totalWidth: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        showDot: Bool
    ) -> CGFloat {
        max(0, totalWidth - leadingInset - trailingInset + (showDot ? dotDiameter / 2 : 0))
    }
}

/// **The one now-line in the app: a `Theme.red` rule across a timed canvas at the current minute.**
///
/// macOS has drawn one since long before [[T-1131]]; iOS drew nothing of the kind on either of its
/// timed surfaces, which was the largest of [[T-619]]'s three divergences and the one most likely
/// to read as missing rather than as different. The repo rule is one shared component over
/// near-copies, so rather than porting the Mac's overlay this is the Mac's overlay, moved here and
/// parameterised; `TimelineCurrentTimeOverlay` is now a four-line adapter from `TimelineMetrics`
/// and `TimelineBlockStyle` onto it, and nothing about what the Mac draws changed.
///
/// **The geometry arrives as a closure, not as an hour height.** Every canvas in the app maps a
/// minute to a Y with the same expression, and `TimelineMetrics.yOffset(forFractionalMinute:)`
/// carries a warning about exactly that: the current-time line and the work-hours band both used
/// to hold their own copy, so a top inset or a non-linear zoom would have moved every block and
/// left those two behind. Taking `hourHeight` here and multiplying it out would re-create that
/// copy in shared code — three times over, since iOS's grid has a `1×`–`3×` pinch that is already
/// folded into the `hourHeight` its columns lay blocks out with. Each caller therefore hands over
/// *its own* minute-to-Y function, which is the same thing
/// `CalendarWorkHoursPreferences.highlightFrame(…yOffset:)` already asks of these callers.
///
/// The dot is the split macOS already had, kept because iOS needs the identical one: the Mac draws
/// it on the Schedule panel and not on the Calendar page, and iOS wants it on Today's timeline and
/// not on the windowed Calendar grid, where one dot per visible column would be a row of them.
struct CadenceTimelineNowLine: View {
    /// The day this canvas draws. The rule appears only when it is the day it actually is.
    let day: Date
    /// The canvas's full width; the rule spans it less the insets.
    let totalWidth: CGFloat
    let startHour: Int
    let endHour: Int
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let showDot: Bool
    /// Fractional minute-of-day → Y in this canvas's own coordinate space. See the note above on
    /// why this is a closure.
    let yOffset: (CGFloat) -> CGFloat

    var body: some View {
        TimelineView(.periodic(from: Date(), by: CadenceTimelineNowLineSupport.tickInterval)) { context in
            let calendar = Calendar.current

            if CadenceTimelineNowLineSupport.isVisible(
                day: day,
                now: context.date,
                startHour: startHour,
                endHour: endHour,
                calendar: calendar
            ) {
                let y = yOffset(
                    CadenceTimelineNowLineSupport.fractionalMinuteOfDay(at: context.date, calendar: calendar)
                )
                let dot = CadenceTimelineNowLineSupport.dotDiameter

                ZStack(alignment: .topLeading) {
                    if showDot {
                        Circle()
                            .fill(Theme.red)
                            .frame(width: dot, height: dot)
                            .offset(x: leadingInset - dot / 2, y: y - dot / 2)
                    }

                    Rectangle()
                        .fill(Theme.red)
                        .frame(
                            width: CadenceTimelineNowLineSupport.lineWidth(
                                totalWidth: totalWidth,
                                leadingInset: leadingInset,
                                trailingInset: trailingInset,
                                showDot: showDot
                            ),
                            height: CadenceTimelineNowLineSupport.lineThickness
                        )
                        .offset(
                            x: CadenceTimelineNowLineSupport.lineOriginX(
                                leadingInset: leadingInset,
                                showDot: showDot
                            ),
                            y: y
                        )
                }
                // The rule sits over the drag-to-create surface on all three canvases, and a filled
                // `Shape` is hit-testable across its whole path — the same trap `dayWash` on iOS's
                // day column records falling into, where a 0.025-opacity wash swallowed every tap
                // on today's column.
                .allowsHitTesting(false)
            }
        }
    }
}
