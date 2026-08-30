import Foundation

/// What Today's iOS timeline says when the day has nothing timed on it.
///
/// **iOS-only, and filed where that is true (T-520).** This was
/// `CadenceTodayPresentationSupport.emptyScheduleHint`: a `Cadence/Shared/` constant ending "…tap
/// an hour to schedule one" with exactly one reader, `iOSSchedulePanel`. macOS's `SchedulePanel`
/// draws no empty state at all, so the sentence was never shared — it was correct only because the
/// one Mac surface that could have picked it up had not yet. Copy naming a touch gesture belongs in
/// the tree whose readers have fingers, which is also what makes
/// `CadenceEmptyStateAuditTests.noMacReachableCopyAsksForATouchGesture` able to sweep `Shared/`.
///
/// Deliberately **outside** `#if os(iOS)`, like `iOSCalendarMetrics`, `iOSTaskCollectionMetrics`,
/// `iOSTaskInspectorMetrics` and `iOSEditorSheetMetrics`: the rest of `Cadence/iOS/` is invisible to
/// the macOS-built test target, and the words are worth pinning by value rather than by reading
/// source. Nothing in this file draws.
nonisolated enum iOSSchedulePanelCopy {
    /// The schedule pane's whole empty state: one line, and the one line teaches the gesture.
    ///
    /// It was a floating card — glyph, heading, explanation — laid over the middle of the hour
    /// grid in a `ZStack`, covering two hours of rows. See `iOSSchedulePanel`.
    static let emptyScheduleHint = "No timed blocks yet — tap an hour to schedule one."
}
