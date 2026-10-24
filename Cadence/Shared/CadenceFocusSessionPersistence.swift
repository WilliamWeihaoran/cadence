import Foundation
import SwiftData

/// A running (or paused) iOS focus session, as `CadenceDefaults.store` holds it ([[T-6001]]).
///
/// The three fields are exactly `CadenceFocusTimerState`'s, plus the subject they were measured
/// against — the owner's decision names them `{target, startedAt, accumulated}`. `isRunning` is in
/// it because the timer state's two halves are not derivable from each other: a *paused* session
/// has `startedAt == nil` and seconds on the clock, and must come back paused rather than start
/// counting again on its own.
///
/// `Codable` with plain members rather than a bespoke string format, because the one hand-rolled
/// alternative — joining the fields with a separator — has to decide what a `Date` looks like, and
/// that is `ISO8601`/epoch arithmetic nobody needs to re-litigate.
struct CadenceFocusSessionRecord: Equatable, Codable {
    var taskID: UUID
    var isRunning: Bool
    var startedAt: Date?
    var accumulatedSeconds: Int
}

/// **[[T-6001]].** The iOS focus session survives eviction and a force-quit, as it already does on
/// the Mac.
///
/// `iOSFocusView` banked only on `.onDisappear`, which does not run when iOS evicts a backgrounded
/// app or the user swipes it away, so the clock and every unlogged minute went with the process.
/// The owner's answer is **option (a): persist the session and resume it live on next open.**
/// Option (b) — banking a partial log on `scenePhase == .background` — was declined for the stated
/// reason: it would end the session every time the user glances at another app, which is most of
/// how a phone is used.
///
/// **It persists rather than banks, so nothing here writes to the SwiftData store.** Minutes are
/// still logged by exactly one path, `CadenceFocusSupport.endSession`, on exactly the exits that
/// already called it. This file holds a note of what is on the clock; losing that note loses a
/// resume, never a minute that was already banked.
///
/// `UserDefaults` is the right home for the same reason `CadenceCalendarDateMemory` uses it: it is
/// per-device session state, not user data to sync. A session resumed on the iPad would be a
/// second clock running against the same task.
///
/// **Not `nonisolated`**, unlike the `CadenceDefaults` it writes through: `resumed(from:tasks:)`
/// reads `AppTask` and asks `CadenceFocusSupport.canFocus`, both of which this project's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` puts on the main actor, and the warning baseline is
/// zero. Every caller — `iOSFocusView` and this file's tests — is already there.
enum CadenceFocusSessionPersistence {

    /// What a screen in this state should have on disk — **`nil` means "nothing worth resuming"**,
    /// which is what `write` stores as "no record".
    ///
    /// An idle clock is not a session: with nothing running and nothing accumulated there is no
    /// minute to lose, and persisting one would make every visit to Focus resume a zero against
    /// whichever task happened to head the picker.
    static func record(
        target: CadenceFocusTarget?,
        state: CadenceFocusTimerState
    ) -> CadenceFocusSessionRecord? {
        guard let taskID = target?.taskID else { return nil }
        guard state.isRunning || state.accumulatedSeconds > 0 else { return nil }
        return CadenceFocusSessionRecord(
            taskID: taskID,
            isRunning: state.isRunning,
            startedAt: state.startedAt,
            accumulatedSeconds: state.accumulatedSeconds
        )
    }

    /// The session to put back on screen, or `nil` to open as Focus always did.
    ///
    /// **The task has to still be there and still be focusable.** `CadenceFocusSupport.canFocus` is
    /// the same predicate the picker filters on, asked here for the reason T-276 states: banking
    /// minutes against something completed or cancelled on another device moves `actualMinutes`,
    /// and from there a goal. A record naming a task that is gone, done or cancelled resolves to
    /// nothing and the caller clears it.
    static func resumed(
        from record: CadenceFocusSessionRecord?,
        tasks: [AppTask]
    ) -> (target: CadenceFocusTarget, state: CadenceFocusTimerState)? {
        guard let record else { return nil }
        guard let task = tasks.first(where: { $0.id == record.taskID }),
              CadenceFocusSupport.canFocus(task) else { return nil }
        var state = CadenceFocusTimerState()
        state.isRunning = record.isRunning
        state.startedAt = record.startedAt
        state.accumulatedSeconds = record.accumulatedSeconds
        return (.task(task.id), state)
    }

    // MARK: - The defaults round trip

    static func encoded(_ record: CadenceFocusSessionRecord) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Refuses rather than guesses. A key holding something else — a half-written string, a value
    /// from a future build — resolves to no session, which is the behaviour before this existed.
    static func decoded(_ raw: String?) -> CadenceFocusSessionRecord? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CadenceFocusSessionRecord.self, from: data)
    }

    static func read(from defaults: UserDefaults = CadenceDefaults.store) -> CadenceFocusSessionRecord? {
        decoded(defaults.string(forKey: CadencePreferenceKeys.iosFocusSession))
    }

    /// Writes the record, or removes the key when there is nothing worth resuming — one call for
    /// both, so a caller cannot persist a session and forget the path that ends it.
    static func write(
        _ record: CadenceFocusSessionRecord?,
        to defaults: UserDefaults = CadenceDefaults.store
    ) {
        guard let record, let encoded = encoded(record) else {
            defaults.removeObject(forKey: CadencePreferenceKeys.iosFocusSession)
            return
        }
        defaults.set(encoded, forKey: CadencePreferenceKeys.iosFocusSession)
    }

    static func clear(in defaults: UserDefaults = CadenceDefaults.store) {
        write(nil, to: defaults)
    }
}
