import EventKit
import Foundation

/// The parts of creating an event that both platforms' calendar managers spell the same way
/// ([[T-3171]] (iii), the event half).
///
/// **Moved out of `iOSCalendarManager`, which is one `#if os(iOS)`.** The recurrence mapping lived
/// there as `eventRecurrenceRule`, so when the macOS drag-create popover began offering Repeat on
/// its Event arm, `CalendarManager.createStandaloneEvent` had no way to name it short of a second
/// copy of the `switch` — and a second copy is how the two platforms come to disagree about what
/// "monthly" means. `CalendarRecurrenceEditScope` and `CalendarWriteFailure` left the same fences
/// for the same reason. Being here also means the mapping is *run* by the macOS test target
/// rather than read as source: an `EKRecurrenceRule` is a value and needs no `EKEventStore`.
enum CadenceEventCreationSupport {

    /// `TaskRecurrenceRule` as EventKit's own rule, or `nil` for `.none`.
    ///
    /// Interval 1, because no Cadence surface offers "every 2 weeks" — inventing one here would be
    /// this function answering a question nothing asked.
    ///
    /// **The series end is carried, not dropped** ([[T-3229]]). The capture card asks it in Event
    /// mode as well as Task mode, and `end: nil` used to turn a bounded series into an endless one
    /// with nothing anywhere saying so.
    ///
    /// The three end parameters are **defaulted**, so a caller with no end to pass gets exactly the
    /// endless rule it always got.
    ///
    /// The mode is expected to be the RESOLVED one — `CadenceScheduleDraft.effectiveSeriesEndMode`
    /// owns the degrade from an `.onDate` with no day, or an `.afterCount` of zero, back to
    /// `.never`. This function does not trust that: a value it cannot spell falls back to no end
    /// rather than to a wrong one.
    ///
    /// **`.onDate` ends at the last instant of the named day, not at its midnight.** `EKRecurrenceEnd`
    /// takes a point in time and Cadence stores a `yyyy-MM-dd` day, so a 2 PM weekly series told to
    /// end on the 10th has to carry 23:59:59 on the 10th or EventKit drops the occurrence the user
    /// was naming.
    static func recurrenceRule(
        for rule: TaskRecurrenceRule,
        endMode: TaskRecurrenceEndMode = .never,
        endDateKey: String = "",
        endCount: Int = 0
    ) -> EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch rule {
        case .none: return nil
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        let seriesEnd: EKRecurrenceEnd?
        switch endMode {
        case .never:
            seriesEnd = nil
        case .onDate:
            let calendar = Calendar.current
            if let day = DateFormatters.date(from: endDateKey),
               let lastInstant = calendar.date(
                   byAdding: DateComponents(day: 1, second: -1),
                   to: calendar.startOfDay(for: day)
               ) {
                seriesEnd = EKRecurrenceEnd(end: lastInstant)
            } else {
                seriesEnd = nil
            }
        case .afterCount:
            seriesEnd = endCount >= 1 ? EKRecurrenceEnd(occurrenceCount: endCount) : nil
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: seriesEnd)
    }

    /// The span a new event is saved with. A new series is saved whole: `.thisEvent` on an event
    /// that carries a recurrence rule would ask EventKit to detach the first occurrence from a
    /// series it is creating.
    static func creationSpan(for rule: TaskRecurrenceRule) -> EKSpan {
        rule == .none ? .thisEvent : .futureEvents
    }

    /// What `EKEvent.location` is written with: the trimmed text, or `nil` for none. `nil` rather
    /// than `""`, because an empty string is a location Calendar renders a blank row for, and "no
    /// location" is the absence of one.
    static func storedLocation(_ location: String) -> String? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
