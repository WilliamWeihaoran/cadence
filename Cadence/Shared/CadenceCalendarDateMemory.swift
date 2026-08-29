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
    ///
    /// **`calendar` is honoured all the way to the string**, not just to `startOfDay`. Snapping in
    /// the caller's calendar and then spelling the result with the default-time-zone
    /// `DateFormatters.dateKey(from:)` reads correctly and is wrong the moment the two disagree:
    /// midnight in Tokyo is the previous afternoon in New York, so the key written for a day the
    /// user is looking at would name the day before it. Every call site passes `Calendar.current`
    /// today, so this is the parameter being made to mean what it says rather than a live bug —
    /// but a parameter that is read for one half of a two-step conversion and dropped for the
    /// other is the shape that becomes one.
    static func storageKey(for date: Date, calendar: Calendar = .current) -> String {
        DateFormatters.dateKey(from: calendar.startOfDay(for: date), calendar: calendar)
    }

    /// A stored key read back, or `nil` for "nothing remembered". An empty string is what an
    /// unwritten key reads as, and a garbage one is what a downgrade or a hand-edited plist leaves
    /// behind; both mean the caller should fall back rather than land on a date it invented.
    ///
    /// Parsed in `calendar`'s time zone for the reason `storageKey` writes in it: a key parsed in
    /// the system zone and then snapped in another calendar's is a day off whenever the two zones
    /// straddle midnight, which would make the round trip through this type lossy.
    ///
    /// It goes through `normalizedDateKey` first because the calendar-aware parse is component
    /// arithmetic, and `DateComponents(month: 13)` *rolls over* into the next year rather than
    /// failing. A hand-edited plist saying `2026-13-01` has to keep reading as "nothing
    /// remembered", not as January 2027.
    static func date(fromStored raw: String?, calendar: Calendar = .current) -> Date? {
        guard let raw, !raw.isEmpty,
              let key = DateFormatters.normalizedDateKey(raw),
              let parsed = DateFormatters.date(from: key, in: calendar) else { return nil }
        return calendar.startOfDay(for: parsed)
    }

    /// Where the calendar page opens: the remembered position, with a dated link laid over it.
    ///
    /// **T-405.** `iOSCalendarView.restorePersistedCalendarDates()` used to spell this ordering
    /// inline — restore the two remembered days, then call the deep-link applier — and
    /// `CadenceTests` cannot see `Cadence/iOS/`, so the ordering that is the *whole* of [[T-369]]
    /// was verified by an iOS-simulator build and nothing else. It is a decision over four
    /// optionals, none of them a view, so it belongs where a test can call it and the view can be a
    /// thin caller.
    ///
    /// The ordering it encodes: **a link that names a day outranks where the calendar was left.**
    /// The Calendar widget's "Open Calendar" link carries the day it is drawing, and a tap that
    /// landed on last week's remembered scroll position instead was T-369's bug. A link with no
    /// day of its own already means today by the time it reaches here — `calendarDateKey(todayKey:)`
    /// is where that is decided, once, for both shells.
    ///
    /// The link sets **both** days, not just the selection. `anchorDate` is the leading column of
    /// the grid, so restoring last week's anchor beside the link's selection would open on the
    /// linked day scrolled off-screen.
    ///
    /// Everything is taken as raw stored strings rather than as `Date`s so the whole decision is
    /// pure: garbage in either key, or in the link, falls back exactly the way `date(fromStored:)`
    /// says it does rather than landing on a day the caller invented.
    ///
    /// - Parameter fallback: The page's own default when nothing is remembered — today.
    static func restoredPosition(
        fallback: Date,
        storedSelection: String?,
        storedAnchor: String?,
        deepLinkDateKey: String?,
        calendar: Calendar = .current
    ) -> CadenceCalendarRestoredPosition {
        if let linked = date(fromStored: deepLinkDateKey, calendar: calendar) {
            return CadenceCalendarRestoredPosition(selectedDate: linked, anchorDate: linked)
        }
        let selection = date(fromStored: storedSelection, calendar: calendar)
            ?? calendar.startOfDay(for: fallback)
        return CadenceCalendarRestoredPosition(
            selectedDate: selection,
            anchorDate: date(fromStored: storedAnchor, calendar: calendar) ?? selection
        )
    }

    // MARK: Reading and writing

    /// The raw stored keys, for `restoredPosition` — which takes strings so that it stays pure.
    /// `anchorDate()` / `selectedDate()` below are the same reads already parsed.
    var storedAnchorKey: String? { defaults.string(forKey: Self.anchorKey) }

    var storedSelectionKey: String? { defaults.string(forKey: Self.selectionKey) }

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

/// The two days `CadenceCalendarDateMemory.restoredPosition` hands back: what is selected, and
/// which column the grid leads with. A pair rather than two returns because the deep-link branch
/// sets them together and a caller that applied one without the other would open on a day it had
/// scrolled out of view.
struct CadenceCalendarRestoredPosition: Equatable {
    var selectedDate: Date
    var anchorDate: Date
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
    private let sleep: @Sendable (Duration) async -> Void
    private var pending: Task<Void, Never>?

    /// The most recently scheduled settle write, **cancelled or not**, kept only so a test can
    /// await it. `pending` is nilled by `flush` because nothing is pending afterwards; this is not,
    /// because "the write you cancelled must not land later and undo the flush" is a thing worth
    /// asserting and there would otherwise be no handle to await.
    private var scheduled: Task<Void, Never>?

    // Spelled out rather than defaulted: a default argument is evaluated in a `nonisolated`
    // context, and both of these are main-actor — which is a warning today and an error in the
    // Swift 6 language mode. The repo's warning baseline is zero on every scheme.
    convenience init() {
        self.init(memory: CadenceCalendarDateMemory(), quietPeriod: Self.quietPeriod)
    }

    convenience init(memory: CadenceCalendarDateMemory, quietPeriod: Duration) {
        self.init(
            memory: memory,
            quietPeriod: quietPeriod,
            sleep: { try? await Task.sleep(for: $0) }
        )
    }

    /// `sleep` is the seam that keeps this type's tests off the wall clock.
    ///
    /// The behaviour under test is *how many writes reach `UserDefaults`*, and a test can only see
    /// that by observing the moment between "scheduled" and "written". Waiting a fixed interval
    /// longer than `quietPeriod` looks like it does that and does not: the scheduled `Task` still
    /// has to be given a thread, so on a machine running several builds at once the writer's own
    /// 60ms sleep can outlast a 400ms wait and the test fails having found nothing wrong. That
    /// happened (T-176) — 43 seconds and a failure under load, 0.4s and a pass alone.
    ///
    /// A longer interval only moves the threshold. Handing the sleep in lets a test replace it with
    /// a gate it opens itself, so "the write has not landed yet" and "the write has landed" become
    /// two states it controls rather than two instants it hopes for.
    init(
        memory: CadenceCalendarDateMemory,
        quietPeriod: Duration,
        sleep: @escaping @Sendable (Duration) async -> Void
    ) {
        self.memory = memory
        self.quietPeriod = quietPeriod
        self.sleep = sleep
    }

    /// Test seam: await the settle write scheduled by the last `remember`, however it ends.
    func awaitScheduledWrite() async {
        await scheduled?.value
    }

    /// Record where the calendar is, to be written once it stops moving.
    func remember(anchor: Date, selection: Date, calendar: Calendar = .current) {
        pending?.cancel()
        let task = Task { [memory, quietPeriod, sleep] in
            await sleep(quietPeriod)
            guard !Task.isCancelled else { return }
            memory.setAnchorDate(anchor, calendar: calendar)
            memory.setSelectedDate(selection, calendar: calendar)
        }
        pending = task
        scheduled = task
    }

    /// Write now. For leaving the page or the foreground, where there is no settle to wait for.
    func flush(anchor: Date, selection: Date, calendar: Calendar = .current) {
        pending?.cancel()
        pending = nil
        memory.setAnchorDate(anchor, calendar: calendar)
        memory.setSelectedDate(selection, calendar: calendar)
    }
}
