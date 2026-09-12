#if os(macOS)
import SwiftUI

/// One rung of the Schedule panel's hour rail.
///
/// **The label is `TimeFormatters`', not this view's ([[T-1130]]).** See `CalTimeRailLabel`, the
/// other half of the same divergence: both macOS rails spelled a bare 24-hour integer while both
/// iOS rails asked the shared formatter, and since [[T-1135]] that formatter follows the system's
/// *24-Hour Time* setting — so all four rails now say `1 PM` or `13:00` together.
///
/// This is the narrower of the two Mac rails, so it is the one the width question is really about:
/// `timeLabelWidth` is a 36pt box against the calendar rail's 44. Measured at 10pt medium, this
/// row's own size and weight, the widest 12-hour label is `10 AM` at 30.44pt and the widest 24-hour
/// one `04:00` at 29.81pt — both inside 36 with room to spare, and the 24-hour face narrower, so
/// neither clock face needs `timeLabelWidth` or `timeLabelPad` moved. `blockInset` is derived from
/// the pair, so changing either would have shifted every block on the panel.
/// `theMacHourRailsFitTheWidestLabelOnEitherClockFace` holds those figures.
struct ScheduleTimeRailRow: View {
    let hour: Int
    let hourHeight: CGFloat

    var body: some View {
        Text(hourLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.dim)
            .frame(width: timeLabelWidth, height: hourHeight, alignment: .topTrailing)
            .padding(.trailing, timeLabelPad)
            .offset(y: -6)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var hourLabel: String { TimeFormatters.timeString(from: hour * 60) }
}
#endif
