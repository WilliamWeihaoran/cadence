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
/// observer writes the state only when the key it sees has really changed, so a notification that
/// does not move the day costs no body pass.
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

    init(observedKey: String = DateFormatters.todayKey()) {
        self.observedKey = observedKey
    }

    var todayKey: String { DateFormatters.todayKey() }

    /// Records `key` and says whether it moved. A `false` must leave the value untouched, which is
    /// what keeps a same-day notification from costing a body pass.
    @discardableResult
    mutating func observe(_ key: String) -> Bool {
        guard key != observedKey else { return false }
        observedKey = key
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
            if next.observe(DateFormatters.todayKey()) {
                day.wrappedValue = next
            }
        }
    }
}
