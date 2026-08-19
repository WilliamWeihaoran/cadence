import Foundation

/// Where the calendar left off — the leading day of the timed grid and the selected day.
///
/// ## The scroll must not write user defaults
///
/// The timed grid reports its leading column back into `anchorDate` on **every column the user
/// scrolls past**, and `iOSCalendarView` used to answer each of those reports by writing two
/// `@AppStorage` keys: the anchor directly, and the selection through `keepSelectedDateInView()`.
///
/// A defaults write is not a cheap thing to do inside a scroll. Measured on an iPad Air 11" at
/// 8,000–13,000pt/s of horizontal fling (T-152), against a diagnostic that logged the scroll
/// geometry every frame: frames on which the leading column did **not** change took a clean 16.7ms,
/// and frames on which it did took **32.7ms** — every column crossed cost a dropped frame. With
/// both writes suppressed the same frames took 16.8ms. One write instead of two landed in between.
/// Dropping the `@AppStorage` wrapper but keeping the per-column write did *not* fix it, which is
/// the finding that decided the shape of this type: the cost is the write reaching `UserDefaults`
/// at all, not the property wrapper around it.
///
/// At fling speed a column goes past roughly every two frames, so the surface spent the whole fling
/// dropping every other one. The day header band is where that reads, because it is the only part
/// of the grid carrying high-contrast content that moves — under it are hour rules on near-black,
/// where a repeated frame looks like nothing at all.
///
/// So the position is written **once the scroll settles**, by `CadenceCalendarDateMemoryWriter`,
/// and it is plain storage rather than `@AppStorage` because nothing reads it as a live value:
/// `restorePersistedCalendarDates()` reads it once, behind a latch, and the observation was pure
/// cost.
///
/// This is the same coarsening `CadenceCalendarTimelineWindow.eventWindowStart` already applies to
/// the EventKit fetch — which was keyed off the per-column path while the two defaults keys beside
/// it were not.
struct CadenceCalendarDateMemory {
    /// The defaults keys, pinned here because they are a user's saved position: renaming one
    /// silently drops where they were, and there is nothing to notice it by.
    static let anchorKey = "ios.calendar.anchorDateKey"
    static let selectionKey = "ios.calendar.selectedDateKey"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Pure decisions

    /// The value to store for `date`, or `nil` when the store already holds it.
    ///
    /// Scrolling recrosses the same column constantly — a fling settles by oscillating across one
    /// boundary, and the rubber band at either end reports the same day repeatedly. Returning `nil`
    /// for an unchanged key is what keeps those from reaching `UserDefaults` at all.
    static func valueToStore(for date: Date, stored: String?, calendar: Calendar = .current) -> String? {
        let key = storageKey(for: date, calendar: calendar)
        return key == stored ? nil : key
    }

    /// The `yyyy-MM-dd` spelling of a remembered day. Normalised to the start of the day, so two
    /// instants on the same day are one stored value.
    static func storageKey(for date: Date, calendar: Calendar = .current) -> String {
        DateFormatters.dateKey(from: calendar.startOfDay(for: date))
    }

    /// A stored key read back, or `nil` for "nothing remembered". An empty string is what an
    /// unwritten key reads as, and a garbage one is what a downgrade or a hand-edited plist leaves
    /// behind; both mean the caller should fall back rather than land on a date it invented.
    static func date(fromStored raw: String?, calendar: Calendar = .current) -> Date? {
        guard let raw, !raw.isEmpty, let parsed = DateFormatters.date(from: raw) else { return nil }
        return calendar.startOfDay(for: parsed)
    }

    // MARK: Reading and writing

    func anchorDate(calendar: Calendar = .current) -> Date? {
        Self.date(fromStored: defaults.string(forKey: Self.anchorKey), calendar: calendar)
    }

    func selectedDate(calendar: Calendar = .current) -> Date? {
        Self.date(fromStored: defaults.string(forKey: Self.selectionKey), calendar: calendar)
    }

    func setAnchorDate(_ date: Date, calendar: Calendar = .current) {
        store(date, forKey: Self.anchorKey, calendar: calendar)
    }

    func setSelectedDate(_ date: Date, calendar: Calendar = .current) {
        store(date, forKey: Self.selectionKey, calendar: calendar)
    }

    private func store(_ date: Date, forKey key: String, calendar: Calendar) {
        guard let value = Self.valueToStore(
            for: date,
            stored: defaults.string(forKey: key),
            calendar: calendar
        ) else { return }
        defaults.set(value, forKey: key)
    }
}

/// One write per settle, instead of one per column.
///
/// Held by the calendar page in `@State` and deliberately **not** `@Observable`: it is a place to
/// put a pending write, and a page that re-rendered every time one was scheduled would be back
/// where it started.
///
/// `remember` is called from the same places the eager writes used to be — so the recorded position
/// is still exactly "wherever the calendar currently is" — but each call cancels the one before it,
/// so a fling that crosses forty columns performs two writes rather than eighty. `flush` is the
/// escape hatch for the page going away or the app leaving the foreground, where waiting out the
/// quiet period would mean losing the position outright. That is the one thing this must not do:
/// the eager write was wrong about *when*, not about *whether*.
@MainActor
final class CadenceCalendarDateMemoryWriter {
    /// How long the position has to hold still before it is written.
    ///
    /// Long enough to outlast a fling's deceleration — each column crossed pushes the deadline out,
    /// so the write lands once, after the last one — and short enough that ordinary use has already
    /// stored the position long before the app is anywhere near being torn down.
    static let quietPeriod: Duration = .milliseconds(400)

    private let memory: CadenceCalendarDateMemory
    private let quietPeriod: Duration
    private var pending: Task<Void, Never>?

    // Spelled out rather than defaulted: a default argument is evaluated in a `nonisolated`
    // context, and both of these are main-actor — which is a warning today and an error in the
    // Swift 6 language mode. The repo's warning baseline is zero on every scheme.
    convenience init() {
        self.init(memory: CadenceCalendarDateMemory(), quietPeriod: Self.quietPeriod)
    }

    init(memory: CadenceCalendarDateMemory, quietPeriod: Duration) {
        self.memory = memory
        self.quietPeriod = quietPeriod
    }

    /// Record where the calendar is, to be written once it stops moving.
    func remember(anchor: Date, selection: Date, calendar: Calendar = .current) {
        pending?.cancel()
        pending = Task { [memory, quietPeriod] in
            try? await Task.sleep(for: quietPeriod)
            guard !Task.isCancelled else { return }
            memory.setAnchorDate(anchor, calendar: calendar)
            memory.setSelectedDate(selection, calendar: calendar)
        }
    }

    /// Write now. For leaving the page or the foreground, where there is no settle to wait for.
    func flush(anchor: Date, selection: Date, calendar: Calendar = .current) {
        pending?.cancel()
        pending = nil
        memory.setAnchorDate(anchor, calendar: calendar)
        memory.setSelectedDate(selection, calendar: calendar)
    }
}
