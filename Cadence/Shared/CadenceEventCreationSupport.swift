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

// MARK: - Repeat on an existing event

extension CadenceEventCreationSupport {

    /// The span an edit to an EXISTING event saves with ([[T-3171]] (ii)).
    ///
    /// The user's scope answer, unless the edit changes the series' rule or end — then always
    /// `.futureEvents`. **An occurrence cannot carry a rule of its own**: `.thisEvent` with a new
    /// rule would ask EventKit to detach one instance into a series of its own, which is not what
    /// either Calendar app means by "Repeat". Apple Calendar answers the same edit the same way: a
    /// changed Repeat on a repeating event offers "Save for future events" and nothing else. On the
    /// first occurrence `.futureEvents` re-rules the whole series; on a later one EventKit ends the
    /// old series the day before and starts the new rule here. On an event that did not repeat,
    /// `.futureEvents` is `creationSpan`'s answer for a series being created.
    static func editSpan(for scope: CalendarRecurrenceEditScope, changesRecurrence: Bool) -> EKSpan {
        changesRecurrence ? .futureEvents : scope.eventSpan
    }

    /// Writes a Repeat answer onto an event: the one rule `recurrenceRule` spells, or none.
    /// Replaces whatever the event carried — the editor only offers Repeat on an event whose rules
    /// `CadenceEventRepeatSetting(rules:…)` could read, so there is nothing Cadence cannot spell
    /// to lose.
    static func applyRecurrence(_ setting: CadenceEventRepeatSetting, to event: EKCalendarItem) {
        event.recurrenceRules = setting.eventKitRule.map { [$0] }
    }
}

/// An event's Repeat answer as the shared panel holds it: the frequency and the resolved series end
/// ([[T-3171]] (ii)). The value the existing-event editors open with, compare against, and write.
struct CadenceEventRepeatSetting: Equatable {
    var rule: TaskRecurrenceRule
    var endMode: TaskRecurrenceEndMode
    var endDateKey: String
    var endCount: Int

    static let noRepeat = CadenceEventRepeatSetting(rule: .none, endMode: .never, endDateKey: "", endCount: 0)

    init(rule: TaskRecurrenceRule, endMode: TaskRecurrenceEndMode, endDateKey: String, endCount: Int) {
        self.rule = rule
        self.endMode = endMode
        self.endDateKey = endDateKey
        self.endCount = endCount
    }

    /// The draft's answer, **resolved** through `effectiveSeriesEndMode` — the same degrade the
    /// create path forwards, so an `.onDate` with no day writes no end rather than a wrong one.
    init(draft: CadenceScheduleDraft) {
        let mode = draft.effectiveSeriesEndMode
        self.init(
            rule: draft.repeatRule,
            endMode: mode,
            endDateKey: mode == .onDate ? draft.seriesEndDateKey : "",
            endCount: mode == .afterCount ? draft.seriesEndCount : 0
        )
    }

    /// What an event's own rules read as — or `nil` when Cadence cannot spell them, in which case
    /// the editor offers no Repeat row at all rather than showing a rule it would overwrite.
    ///
    /// Readable: no rule (a one-off), or exactly one rule at interval 1 with no by-day, by-month or
    /// set-position refinements — except the one refinement that changes nothing: a weekly rule
    /// naming only the event's own weekday, or a monthly rule naming only its own day of the month,
    /// which is how Google- and Exchange-synced series often spell plain "weekly" and "monthly".
    ///
    /// **A detached occurrence with no rule of its own is not a one-off** — it is a member of a
    /// series whose rule it does not carry, and reading it as "Never" would offer to end a series
    /// the editor cannot see.
    ///
    /// An `.onDate` end reads back as the day it falls on, the inverse of `recurrenceRule`, which
    /// writes the last instant of the named day.
    init?(rules: [EKRecurrenceRule]?, isDetached: Bool, start: Date?, calendar: Calendar = .current) {
        let rules = rules ?? []
        guard let only = rules.first else {
            if isDetached { return nil }
            self = .noRepeat
            return
        }
        guard rules.count == 1, only.interval == 1,
              (only.monthsOfTheYear ?? []).isEmpty,
              (only.weeksOfTheYear ?? []).isEmpty,
              (only.daysOfTheYear ?? []).isEmpty,
              (only.setPositions ?? []).isEmpty
        else { return nil }
        let days = only.daysOfTheWeek ?? []
        let monthDays = only.daysOfTheMonth ?? []
        let rule: TaskRecurrenceRule
        switch only.frequency {
        case .daily:
            guard days.isEmpty, monthDays.isEmpty else { return nil }
            rule = .daily
        case .weekly:
            guard monthDays.isEmpty else { return nil }
            if !days.isEmpty {
                guard days.count == 1, days[0].weekNumber == 0, let start,
                      days[0].dayOfTheWeek.rawValue == calendar.component(.weekday, from: start)
                else { return nil }
            }
            rule = .weekly
        case .monthly:
            guard days.isEmpty else { return nil }
            if !monthDays.isEmpty {
                guard monthDays.count == 1, let start,
                      monthDays[0].intValue == calendar.component(.day, from: start)
                else { return nil }
            }
            rule = .monthly
        case .yearly:
            guard days.isEmpty, monthDays.isEmpty else { return nil }
            rule = .yearly
        @unknown default:
            return nil
        }
        guard let end = only.recurrenceEnd else {
            self.init(rule: rule, endMode: .never, endDateKey: "", endCount: 0)
            return
        }
        if let endDate = end.endDate {
            self.init(
                rule: rule,
                endMode: .onDate,
                endDateKey: DateFormatters.dateKey(from: endDate, calendar: calendar),
                endCount: 0
            )
        } else if end.occurrenceCount >= 1 {
            self.init(rule: rule, endMode: .afterCount, endDateKey: "", endCount: end.occurrenceCount)
        } else {
            return nil
        }
    }

    /// An event's own answer — `init(rules:…)` over its rules, detachment and start.
    init?(event: EKEvent, calendar: Calendar = .current) {
        self.init(
            rules: event.recurrenceRules,
            isDetached: event.isDetached,
            start: event.startDate,
            calendar: calendar
        )
    }

    /// The rule this answer writes — `CadenceEventCreationSupport.recurrenceRule`, the create
    /// path's own mapping, so creating and editing cannot disagree about what "monthly" means.
    var eventKitRule: EKRecurrenceRule? {
        CadenceEventCreationSupport.recurrenceRule(
            for: rule,
            endMode: endMode,
            endDateKey: endDateKey,
            endCount: endCount
        )
    }

    /// Opens a draft on this answer, so the panel's Repeat and Ends rows show what the event does.
    func seed(_ draft: inout CadenceScheduleDraft) {
        draft.repeatRule = rule
        draft.seriesEndMode = endMode
        draft.seriesEndDateKey = endDateKey
        draft.seriesEndCount = endCount
    }

    /// What a Save writes for the series: `nil` — leave the event's rules alone — unless the draft's
    /// Repeat or Ends moved from what it opened with (`changesRecurrence(from:)`, the task editor's
    /// own test). An untouched Save therefore never rewrites a rule, even one it read.
    static func edit(draft: CadenceScheduleDraft, opened: CadenceScheduleDraft) -> CadenceEventRepeatSetting? {
        draft.changesRecurrence(from: opened) ? CadenceEventRepeatSetting(draft: draft) : nil
    }
}
