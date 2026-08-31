import EventKit

/// Which occurrences of a repeating calendar event a save or a delete applies to.
///
/// The two cases carry **both** halves of the decision: the words on the button and the `EKSpan`
/// the write actually uses. Keeping them on one value is the point of the type — a button reading
/// "Only This Event" that resolved to `.futureEvents` would look right in review, pass any check
/// written over labels alone, and destroy the rest of somebody's series. `label` and `eventSpan`
/// switch over the same `self`, so the words and the effect cannot disagree.
///
/// **T-549 moved this out of `CalendarManager.swift` and into `Shared/`.** That file is one large
/// `#if os(macOS)`, so iOS could not name the type and `iOSCalendarEventEditSheet` declared its own
/// `private enum iOSCalendarRecurrenceEditScope` — the same two cases, the same two `rawValue`s,
/// the same two labels and the same two spans, byte for byte, with nothing holding them in step
/// until a pin was added. That pin was a source-text scan over the phone's file, and it is deleted
/// by this move: there is one type now, so the label/span pairing is checked by *running* it.
///
/// This is the second type to leave that fence for the same reason — `CalendarWriteFailure` was the
/// first, under T-339 — and neither was ever desktop-only. `EKSpan` ships on both platforms.
///
/// The shape is the one T-200 arrived at for the *task* scopes: `CadenceTaskRecurrenceEditScope`
/// replaced `TaskWorkflowService`'s byte-identical private copy with one type plus a test on the
/// labels. The dialog prose around both lives in `CadenceRecurrenceScopeCopy`; the buttons stay
/// here, beside the span they resolve to.
enum CalendarRecurrenceEditScope: String, CaseIterable, Hashable {
    case thisOccurrence
    case futureOccurrences

    var label: String {
        switch self {
        case .thisOccurrence: return "Only This Event"
        case .futureOccurrences: return "This And Future Events"
        }
    }

    var eventSpan: EKSpan {
        switch self {
        case .thisOccurrence: return .thisEvent
        case .futureOccurrences: return .futureEvents
        }
    }
}
