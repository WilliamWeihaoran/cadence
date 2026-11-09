import Foundation

/// **[[T-6995]] — the eyebrow over a list's Completed tab.**
///
/// The Mac tab used to hand-roll its row, and this enum answered that row's title, glyph, VoiceOver
/// status and due line. Since [[T-12791]] the row is `TaskListDisplayRow`, which answers all four
/// itself (`TaskTitleSupport`, `CadenceTaskCompletionGlyph`, the completion control's label, the
/// due chip), so only the count is left here.
///
/// **[[T-14292]]: shared, so both platforms' Completed tab heads its rows with it.** It sat in the
/// `#if os(macOS)` list-detail file, and iOS's `iOSListCompletedPanel` drew the same rows with no
/// count over them -- drift, with no pointer or screen reason behind it ([[T-8201]]).
enum ListLogRowPresentation {
    /// The eyebrow over the rows. It counted cancelled tasks as "completed"; it now names both
    /// when both are there.
    static func countLabel(for tasks: [AppTask]) -> String {
        let cancelled = tasks.filter(\.isCancelled).count
        let completed = tasks.count - cancelled
        switch (completed, cancelled) {
        case (_, 0): return "\(completed) completed"
        case (0, _): return "\(cancelled) canceled"
        default: return "\(completed) completed, \(cancelled) canceled"
        }
    }
}
