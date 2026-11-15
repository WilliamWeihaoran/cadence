import SwiftUI

/// **How an organizer-cancelled event is drawn, on every surface but the timed grid** ([[T-18014]],
/// under [[T-8201]]).
///
/// [[T-18007]] decided the rule (`CadenceCalendarEventVisibility.isCancelled`) and drew it on the
/// timed blocks only: the title struck through, the whole block dimmed to `cancelledOpacity`, and
/// "canceled" spoken. The all-day and month chips, the Board cards and both platforms' Search rows
/// went on drawing the same event as an ordinary one. These two modifiers are that treatment, so
/// each surface reads the one predicate and spells nothing of its own.
///
/// The spoken word rides on the TITLE's own label rather than the row's: every one of those surfaces
/// combines its children into one element, so the struck title's label is what the row says.
extension Text {
    /// Struck through, and spoken as `CadenceCalendarDayAccessibility.eventTitleLabel` spells it.
    func cadenceCancelledEventTitle(_ title: String, isCancelled: Bool) -> Text {
        strikethrough(isCancelled)
            .accessibilityLabel(CadenceCalendarDayAccessibility.eventTitleLabel(title: title, isCancelled: isCancelled))
    }
}

extension View {
    /// The whole chip, card or row dimmed together, as the timed block is, so no label tier moves
    /// against the plate it was solved on.
    func cadenceCancelledEventDim(_ isCancelled: Bool) -> some View {
        opacity(isCancelled ? CadenceCalendarEventVisibility.cancelledOpacity : 1)
    }
}
