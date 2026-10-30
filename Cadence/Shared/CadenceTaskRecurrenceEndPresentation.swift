import Foundation

/// What a recurrence end mode needs beside it, once it is selected.
///
/// The mode alone does not say what to draw: `.onDate` needs a day and `.afterCount` needs a
/// number, and `.never` needs neither. Both platforms' Repeat controls ask this rather than
/// switching on the mode themselves, so the two cannot disagree about which mode owns which
/// field — which is the same shape of bug as an `.onDate` stored with an empty date key, where
/// `AppTask.effectiveRecurrenceEndMode` silently degrades the mode back to `.never` and the
/// control appears to refuse the click.
nonisolated enum CadenceRecurrenceEndDetail: Equatable, CaseIterable {
    case none
    case date
    case count
}

/// How a series' end condition reads, and what a control has to seed to make each mode stick.
///
/// This exists in `Shared/` rather than beside either Repeat control for two reasons. The first is
/// the ordinary one: macOS's inspector row and iOS's Schedule well both state the bound, and two
/// spellings of "3 of 5" is how they drift. The second is that `Cadence/iOS/` is inside
/// `#if os(iOS)` and invisible to the macOS-built test target, so an iOS-only copy of these
/// decisions could not be pinned at all.
///
/// The arithmetic itself is **not** here. `CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceEnd`
/// owns the write — normalization, series propagation, and clearing the values that do not belong
/// to the chosen mode — and both platforms call it. Nothing in this file touches an `AppTask`.
nonisolated enum CadenceTaskRecurrenceEndPresentation {
    /// The count a fresh `.afterCount` selection starts at.
    ///
    /// A stored `0` means "never configured"; seeding the field with the clamp value (`1`) would
    /// end the series on its very first occurrence, so the number the user is shown before they
    /// touch anything must not be the floor.
    static let seededEndCount = 10

    /// How far out a fresh `.onDate` selection lands.
    static let seededEndMonthsAhead = 1

    /// An end condition only means something for a task that repeats.
    static func showsEndControls(rule: TaskRecurrenceRule) -> Bool {
        rule != .none
    }

    static func detail(for mode: TaskRecurrenceEndMode) -> CadenceRecurrenceEndDetail {
        switch mode {
        case .never: return .none
        case .onDate: return .date
        case .afterCount: return .count
        }
    }

    /// The line under a Repeat row: what bounds the series, or `nil` when nothing does.
    ///
    /// `.never` deliberately says nothing rather than "Repeats forever" — the row above already
    /// says "Every week", and the only next-occurrence date math in the app is private to the
    /// spawn path in `CadenceTaskRecurrenceWorkflowSupport`, so there is no honest date to add.
    ///
    /// `.afterCount` reads "N of M" rather than "M left": the position in the series is the fact
    /// the user cannot get anywhere else, and "M left" throws away where you are.
    static func summary(
        mode: TaskRecurrenceEndMode,
        endDateKey: String,
        occurrenceNumber: Int,
        endCount: Int,
        relativeTo referenceDate: Date = Date()
    ) -> String? {
        switch mode {
        case .never:
            return nil
        case .onDate:
            return "Until \(DateFormatters.shortDateString(from: endDateKey, relativeTo: referenceDate))"
        case .afterCount:
            return "\(occurrenceNumber) of \(endCount)"
        }
    }

    /// The value a dedicated "Ends" control shows: the same sentence as `summary`, with the one
    /// mode that has nothing to say naming itself instead of going blank.
    ///
    /// A trigger button cannot render `nil` — a row whose value is empty reads as broken rather
    /// than as unbounded — but it must not restate the bound in different words either, which is
    /// why this is one line over `summary` and not a second `switch`.
    static func valueLabel(
        mode: TaskRecurrenceEndMode,
        endDateKey: String,
        occurrenceNumber: Int,
        endCount: Int
    ) -> String {
        summary(mode: mode, endDateKey: endDateKey, occurrenceNumber: occurrenceNumber, endCount: endCount)
            ?? TaskRecurrenceEndMode.never.label
    }

    /// The day a fresh `.onDate` selection is seeded with. Selecting the mode has to store a real
    /// key: an empty one degrades straight back to `.never`.
    static func defaultEndDateKey(from reference: Date = Date(), calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: reference)
        let target = calendar.date(byAdding: .month, value: seededEndMonthsAhead, to: start) ?? start
        return DateFormatters.dateKey(from: target)
    }

    /// The date an `.onDate` control should show, falling back to the seed when nothing is stored.
    static func resolvedEndDate(
        _ endDateKey: String,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        DateFormatters.date(from: endDateKey)
            ?? DateFormatters.date(from: defaultEndDateKey(from: reference, calendar: calendar))
            ?? calendar.startOfDay(for: reference)
    }

    /// What an `.afterCount` control should *display* for a stored value, seeding an unconfigured
    /// one rather than showing the floor.
    static func resolvedEndCount(_ stored: Int) -> Int {
        stored >= 1 ? stored : seededEndCount
    }

    /// What an `.afterCount` control may *write*. Matches the clamp `applyRecurrenceEnd` applies
    /// anyway, so a stepper cannot walk a series down to zero occurrences and appear to have
    /// disabled the limit.
    static func normalizedEndCount(_ raw: Int) -> Int {
        max(1, raw)
    }

    /// **T-6114:** what an editor's After count *displays and seeds* on a task whose current
    /// occurrence is `occurrenceNumber`: the stored-or-seeded count, floored at that occurrence.
    ///
    /// Without the floor a task on its 15th occurrence picks up the flat seed of 10, reads
    /// "15 of 10", and its next completion silently ends the series. An unconfigured count seeds
    /// `seededEndCount(occurrenceNumber:)`; a stored one is only floored at the occurrence.
    static func resolvedEndCount(_ stored: Int, occurrenceNumber: Int) -> Int {
        guard stored >= 1 else { return seededEndCount(occurrenceNumber: occurrenceNumber) }
        return max(stored, occurrenceNumber)
    }

    /// **T-6114 (owner decision 2026-10-26):** the count a fresh `.afterCount` selection seeds on a
    /// task whose current occurrence is `occurrenceNumber` -- `max(seededEndCount, n + 1)`.
    ///
    /// Seeding `n` ("15 of 15") would end an old series on its very next completion, which picking
    /// Ends -> After must never do on its own; plain `n + 1` was declined because it seeds 1 or 2 on
    /// a brand-new series. A young series keeps the flat 10, an old one gets at least one more.
    static func seededEndCount(occurrenceNumber: Int) -> Int {
        max(seededEndCount, occurrenceNumber + 1)
    }

    /// **T-6114:** what an editor's After count may *write*: `normalizedEndCount`, floored at the
    /// task's current occurrence number, so a typed or picked count cannot fall below it.
    static func normalizedEndCount(_ raw: Int, occurrenceNumber: Int) -> Int {
        max(normalizedEndCount(raw), occurrenceNumber)
    }

    /// The schedule capture card's "after N" stepper title. **T-4980:** it typed
    /// `"\(max(1, count)) occurrences"`, and the stepper's floor is 1, so its lowest value read
    /// "1 occurrences".
    static func endCountStepperLabel(_ raw: Int) -> String {
        CadencePluralization.phrase(normalizedEndCount(raw), singular: "occurrence", plural: "occurrences")
    }
}
