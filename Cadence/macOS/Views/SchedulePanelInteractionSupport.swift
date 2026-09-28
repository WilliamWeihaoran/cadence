#if os(macOS)
import SwiftUI

/// What the Today timeline remembers between one scroll report and the next.
///
/// **A reference box held in `@State`, deliberately, and not two `@State` values (T-1498).** Writing
/// a `@State` *value* from a scroll report invalidates `SchedulePanel`, and this panel's body
/// re-derives the day's tasks with a full pass over every task in the store **and** performs one
/// uncached `EKEventStore.events(matching:)` fetch through
/// `SchedulePanelDataSupport.externalEventItems`. A guard that bought its saving by adding a render
/// per hour crossed would be paying in exactly the currency it collects in. Mutating a property of
/// a class held in `@State` invalidates nothing.
///
/// The shape is `CalendarPageView`'s, which already holds `CalendarEventDayCache` and
/// `CalendarTimelineScrollState` this way — and the second of those carries this repository's own
/// record of the same defect class, measured on the calendar page and fixed there.
final class SchedulePanelScrollPersistence {
    /// The last hour a scroll report actually adopted. `nil` until the first one.
    var lastReportedHour: Int?
    /// The debounced write in flight, so the next report can cancel it.
    var pendingPersistence: DispatchWorkItem?
}

enum SchedulePanelInteractionSupport {
    /// The hour a scroll report should persist, or `nil` when it should persist nothing.
    ///
    /// **This is the whole of T-1498's first half, and it is a count rather than a feeling.**
    /// `onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y }` runs its action whenever
    /// the transformed value changes, and a raw content offset changes on **every frame of a live
    /// scroll**. The gate above this line was `didRestoreScroll, !isRestoringScroll` and nothing
    /// else, so every one of those frames wrote `@AppStorage("scheduleRememberedScrollHour")`:
    /// **60 per fling where 7 were meant.**
    ///
    /// **It was not 60 renders, and the ledger says so with the number that refutes it** — a
    /// `UserDefaults` key does not notify when written the value it already holds (1 notification
    /// for 60 identical writes, against 60 for 60 distinct ones). The invalidations were already
    /// one per hour crossed; what collapses them to one per settled gesture is the debounce below,
    /// not this guard. Writes land at **1** per settled gesture rather than 60 for the same reason.
    /// The guard's own saving is narrower and worth naming honestly: 60 → 7 schedule-and-cancel
    /// cycles per fling.
    ///
    /// The same canvas is smooth on the calendar page because that host already refuses the
    /// report: `CalendarTimelineViewport` holds `guard visibleTimelineHour != clampedHour else
    /// { return }` before it touches anything. Passing `lastReportedHour: nil` here reproduces the
    /// old behaviour exactly — no memory, so every report is adopted — which is how the before and
    /// after numbers in `SchedulePanelScrollWorkRateTests` come out of one transcript through one
    /// code path rather than out of two descriptions of one.
    static func rememberedHourToPersist(
        yOffset: CGFloat,
        geoHeight: CGFloat,
        zoomLevel: Int,
        didRestoreScroll: Bool,
        isRestoringScroll: Bool,
        lastReportedHour: Int?
    ) -> Int? {
        guard didRestoreScroll, !isRestoringScroll else { return nil }
        let hour = SchedulePanelStateSupport.clampedRememberedHour(
            offsetY: yOffset,
            geoHeight: geoHeight,
            zoomLevel: zoomLevel
        )
        guard hour != lastReportedHour else { return nil }
        return hour
    }

    /// Adopt a scroll report, and schedule the remembered hour through the **same** debounce the
    /// calendar page's timeline uses — `CalendarPageStateSupport.schedulePersistence`, not a second
    /// spelling of it. The guard collapses a fling to one call per hour crossed; the debounce
    /// collapses those to one write per settled gesture.
    static func persistRememberedHour(
        yOffset: CGFloat,
        geoHeight: CGFloat,
        zoomLevel: Int,
        didRestoreScroll: Bool,
        isRestoringScroll: Bool,
        state: SchedulePanelScrollPersistence,
        persist: @escaping (Int) -> Void
    ) {
        guard let hour = rememberedHourToPersist(
            yOffset: yOffset,
            geoHeight: geoHeight,
            zoomLevel: zoomLevel,
            didRestoreScroll: didRestoreScroll,
            isRestoringScroll: isRestoringScroll,
            lastReportedHour: state.lastReportedHour
        ) else { return }

        state.lastReportedHour = hour
        CalendarPageStateSupport.schedulePersistence(
            value: hour,
            cancelPending: { state.pendingPersistence?.cancel() },
            storePending: { state.pendingPersistence = $0 },
            persist: persist
        )
    }

    static func focusTimeline(
        proxy: ScrollViewProxy,
        clearAppEditingFocus: () -> Void,
        setHighlighted: @escaping (Bool) -> Void
    ) {
        clearAppEditingFocus()
        let targetHour = SchedulePanelStateSupport.focusTargetHour()
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(targetHour, anchor: .top)
        }
        SchedulePanelStateSupport.highlightFocus { setHighlighted($0) }
    }
}
#endif
