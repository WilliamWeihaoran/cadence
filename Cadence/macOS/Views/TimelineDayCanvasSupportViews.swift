#if os(macOS)
import SwiftUI

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
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.majorGridOpacity))
                    .frame(height: CalendarVisualStyle.majorGridLineWidth)
            }
            .overlay(alignment: .top) {
                if showHalfHourMark {
                    Rectangle()
                        .fill(Theme.borderSubtle.opacity(CalendarVisualStyle.minorGridOpacity))
                        .frame(height: CalendarVisualStyle.minorGridLineWidth)
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
            .suppressWindowBackgroundDrag()
    }

    private func absoluteY(forLocalY y: CGFloat) -> CGFloat {
        TimelineCreateRowGeometrySupport.absoluteY(
            hour: hour,
            metrics: metrics,
            localY: y
        )
    }

    private func absolutePoint(for localPoint: CGPoint) -> CGPoint {
        TimelineCreateRowGeometrySupport.absolutePoint(
            hour: hour,
            metrics: metrics,
            localPoint: localPoint
        )
    }

    private func absoluteMinute(forLocalY y: CGFloat) -> Int {
        TimelineCreateRowGeometrySupport.absoluteMinute(
            hour: hour,
            metrics: metrics,
            localY: y
        )
    }

    private func isInsideBlockedBlock(point: CGPoint) -> Bool {
        TimelineCreateRowGeometrySupport.isInsideBlockedBlock(
            point: point,
            blockedFrames: blockedFrames
        )
    }
}

#endif
