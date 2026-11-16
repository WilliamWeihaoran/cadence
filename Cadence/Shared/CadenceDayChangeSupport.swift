import Combine
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// What tells a Today surface that the day it is drawing is over (T-3104).
///
/// Today's views compute `todayKey` from the clock during `body`, which is right whenever a body
/// pass happens — and nothing made one happen at midnight. A Mac or iPad left open overnight kept
/// listing yesterday's tasks, computed overdue against yesterday's key, and never raised the
/// rollover banner whose whole job is yesterday's leftovers, until some unrelated change happened
/// to invalidate the view. The widgets already reload at the next midnight ([[T-851]]), so after
/// midnight the widget and the app disagreed.
///
/// The fix is a dependency, not a timer: a view holds a `CadenceObservedDay` in `@State`, reads
/// `todayKey` through it, and installs `.cadenceTracksDayChanges($observedDay)`. The key still
/// comes from the clock on every read, so a body pass for any other reason stays correct, and the
/// observer writes the state only when the key (or, [[T-17442]], the zone) has really changed, so
/// a notification that moves neither costs no body pass.
nonisolated enum CadenceDayChangeSupport {
    /// Every system signal after which "today" may be a different key.
    ///
    /// - `NSCalendarDayChanged`: the calendar day rolled over (posted on wake, too, if midnight
    ///   passed while asleep).
    /// - `NSSystemTimeZoneDidChange` / `NSSystemClockDidChange`: a flight, or a manual clock change,
    ///   can move the key without midnight.
    /// - App activation: the belt to the braces above — a suspended iOS app or a long-asleep Mac
    ///   is re-checked the moment it is in front of someone. Cheap, because the observer only
    ///   writes when the key differs.
    /// - iOS `significantTimeChangeNotification`: UIKit's own "midnight / carrier time / DST"
    ///   signal, also delivered on return from suspension.
    static var notificationNames: [Notification.Name] {
        var names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemTimeZoneDidChange,
            .NSSystemClockDidChange,
        ]
        #if os(macOS)
        names.append(NSApplication.didBecomeActiveNotification)
        #elseif os(iOS)
        names.append(UIApplication.significantTimeChangeNotification)
        names.append(UIApplication.didBecomeActiveNotification)
        #endif
        return names
    }

    /// One merged stream of `notificationNames` on `center`. Each post yields exactly one value.
    static func dayMayHaveChanged(on center: NotificationCenter = .default) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(notificationNames.map { name in
            center.publisher(for: name).map { _ in () }
        })
        .eraseToAnyPublisher()
    }
}

/// A view's handle on which day it is. See `CadenceDayChangeSupport`.
nonisolated struct CadenceObservedDay: Equatable {
    /// The key this view last observed. It is the invalidation token, **not** the answer:
    /// `todayKey` reads the clock, so a missed notification can delay a redraw but never make a
    /// redraw wrong.
    private(set) var observedKey: String
    /// The zone this view last laid out in ([[T-17442]]).
    private(set) var observedTimeZoneIdentifier: String

    init(observedKey: String = DateFormatters.todayKey(), observedTimeZone: TimeZone = Calendar.current.timeZone) {
        self.observedKey = observedKey
        observedTimeZoneIdentifier = observedTimeZone.identifier
    }

    var todayKey: String { DateFormatters.todayKey() }

    /// Records `key` and says whether it moved. A `false` must leave the value untouched, which is
    /// what keeps a same-day notification from costing a body pass.
    ///
    /// **[[T-17442]]: a new zone is a change too, even on the same day.** Flying New York ->
    /// Chicago at 10:00 keeps the key, so a key-only comparison cost no body pass and every timed
    /// surface kept its events laid out and labelled in the old zone while the now-line, which
    /// ticks on its own schedule, moved. `timeZone` is the zone the caller lays out in; `nil`
    /// compares the key alone.
    @discardableResult
    mutating func observe(_ key: String, timeZone: TimeZone? = nil) -> Bool {
        let zoneMoved = timeZone.map { $0.identifier != observedTimeZoneIdentifier } ?? false
        guard key != observedKey || zoneMoved else { return false }
        observedKey = key
        if let timeZone { observedTimeZoneIdentifier = timeZone.identifier }
        return true
    }
}

/// The day-change stream, built **once** per centre (T-3124).
///
/// `onReceive` keeps its subscription across body passes only when it is handed the same
/// publisher: `AnyPublisher` is not `Equatable`, and a freshly built one is a fresh box. Building
/// `dayMayHaveChanged()` inline in the modifier therefore tore down and re-added every
/// notification observer on every body pass of every adopter — measured in
/// `CadenceDayChangeSubscriptionTests` at one full resubscription per pass, against exactly one
/// subscription for a stream built once. `TasksPanel`'s body is one of the expensive ones.
///
/// A `@MainActor` class rather than a `static let` on the `nonisolated` support enum: an actor-
/// isolated static needs no `Sendable` storage, so the cache costs no concurrency warning.
@MainActor
final class CadenceDayChangeStream {
    /// The stream every adopter observes by default, over `NotificationCenter.default`.
    static let main = CadenceDayChangeStream(center: .default)

    let publisher: AnyPublisher<Void, Never>

    init(center: NotificationCenter) {
        publisher = CadenceDayChangeSupport.dayMayHaveChanged(on: center)
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}

extension View {
    /// Re-runs the caller's `body` when the day changes. The caller must *read* `day` in its body
    /// (through `todayKey`), or SwiftUI has no dependency to invalidate.
    func cadenceTracksDayChanges(_ day: Binding<CadenceObservedDay>) -> some View {
        cadenceTracksDayChanges(day, from: .main)
    }

    /// The same observer over an explicit stream. `stream` must outlive body passes — hand in a
    /// stored instance, never one built in `body`, or the subscription is rebuilt every pass.
    func cadenceTracksDayChanges(
        _ day: Binding<CadenceObservedDay>,
        from stream: CadenceDayChangeStream
    ) -> some View {
        onReceive(stream.publisher) { _ in
            var next = day.wrappedValue
            if next.observe(DateFormatters.todayKey(), timeZone: Calendar.current.timeZone) {
                day.wrappedValue = next
            }
        }
    }
}

/// What a page holding a DAY, or a cache keyed by one, must do when the zone moves under it
/// ([[T-18186]], [[T-18187]]).
///
/// [[T-17442]] made a zone change cost a body pass, and the pass re-read whatever the page held.
/// Two kinds of held state outlive the zone they were taken in:
///
/// - **A day held as an instant.** The Calendar pages keep their selected and anchor days as the
///   midnight `Date` of the zone the page was opened in. Every reader turns it back into a day in
///   the CURRENT zone, so after a westward change (New York -> Los Angeles) Nov 16 00:00 EST reads
///   as Nov 15: the selected day, its inspector and the Mac timeline's columns slide a day back.
///   `resnappedDay` keeps the day and moves the instant.
/// - **A day cache keyed by `yyyy-MM-dd` alone.** Each day's events are fetched between that day's
///   bounds in the zone current at FETCH time, so a bucket filled in New York holds
///   [21:00, 21:00) Pacific once the device is in Los Angeles -- an evening event is missing and
///   the previous evening is clamped in as a sliver. `zoneScopedKey` puts the zone into the
///   identity, so a cache keyed on it refetches.
nonisolated enum CadenceTimeZoneChangeSupport {
    /// `key`, scoped to `timeZone`: a cache identity that changes when the zone does.
    static func zoneScopedKey(_ key: String, timeZone: TimeZone = .current) -> String {
        "\(key)@\(timeZone.identifier)"
    }

    /// The first instant, in `newZone`, of the calendar day `instant` named in `oldZone`.
    ///
    /// Identity when the zones are the same, so a caller may run it on every day-change signal.
    static func resnappedDay(_ instant: Date, from oldZone: TimeZone, to newZone: TimeZone) -> Date {
        guard oldZone.identifier != newZone.identifier else { return instant }
        var oldCalendar = Calendar(identifier: .gregorian)
        oldCalendar.timeZone = oldZone
        var newCalendar = Calendar(identifier: .gregorian)
        newCalendar.timeZone = newZone
        let key = DateFormatters.dateKey(from: instant, calendar: oldCalendar)
        return DateFormatters.date(from: key, in: newCalendar) ?? instant
    }

    /// `resnappedDay` across one `CadenceObservedDay` transition, the form a page's
    /// `.onChange(of: observedDay)` hands it. An unknown identifier leaves the instant alone.
    static func resnappedDay(_ instant: Date, from old: CadenceObservedDay, to new: CadenceObservedDay) -> Date {
        guard let oldZone = TimeZone(identifier: old.observedTimeZoneIdentifier),
              let newZone = TimeZone(identifier: new.observedTimeZoneIdentifier) else { return instant }
        return resnappedDay(instant, from: oldZone, to: newZone)
    }
}
