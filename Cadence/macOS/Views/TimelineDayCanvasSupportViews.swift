#if os(macOS)
import SwiftUI

/// The hour rules and half-hour ticks behind the canvas.
///
/// Purely decorative: this used to be the same `VStack` of hour rows that *also* carried the
/// drag-to-create gesture, which meant the gesture's canvas Y was reconstructed from a row index
/// (`(hour - startHour) * hourHeight + localY`). Adding a divider or any spacing here would have
/// silently pushed every drag-to-create a little further off the further down the day you went.
/// Now the rows draw and nothing else, and the gesture reads the canvas coordinate space directly.
struct TimelineHourGridLines: View {
    let metrics: TimelineMetrics
    let showHalfHourMarks: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(metrics.startHour..<metrics.endHour, id: \.self) { _ in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.hourHeight)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.majorGridOpacity))
                            .frame(height: CalendarVisualStyle.majorGridLineWidth)
                    }
                    .overlay(alignment: .top) {
                        if showHalfHourMarks {
                            Rectangle()
                                .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.minorGridOpacity))
                                .frame(height: CalendarVisualStyle.minorGridLineWidth)
                                .offset(y: metrics.hourHeight / 2)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

#endif
