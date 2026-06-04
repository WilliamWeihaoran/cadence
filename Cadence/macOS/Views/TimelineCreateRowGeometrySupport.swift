#if os(macOS)
import CoreGraphics

enum TimelineCreateRowGeometrySupport {
    static func absoluteY(hour: Int, metrics: TimelineMetrics, localY: CGFloat) -> CGFloat {
        CGFloat(hour - metrics.startHour) * metrics.hourHeight + localY
    }

    static func absolutePoint(hour: Int, metrics: TimelineMetrics, localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: localPoint.x,
            y: absoluteY(hour: hour, metrics: metrics, localY: localPoint.y)
        )
    }

    static func absoluteMinute(hour: Int, metrics: TimelineMetrics, localY: CGFloat) -> Int {
        metrics.snappedMinute(fromY: absoluteY(hour: hour, metrics: metrics, localY: localY))
    }

    static func isInsideBlockedBlock(point: CGPoint, blockedFrames: [TimelineBlockFrame]) -> Bool {
        blockedFrames.contains { frame in
            point.x >= frame.x &&
            point.x <= frame.x + frame.width &&
            point.y >= frame.y &&
            point.y <= frame.y + frame.height
        }
    }
}
#endif
