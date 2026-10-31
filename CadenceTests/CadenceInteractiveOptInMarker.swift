// [[T-8926]]: this file lives in `CadenceTests/` so its cases run unattended, and it is ALSO a
// member of `CadenceUITests` (an exception set on the `CadenceTests` folder in `project.pbxproj`),
// because `CadenceUITestEnvironment.requireInteractiveUITests()` asks it before every suite that
// takes over the pointer and the keyboard.
import Foundation

/// **The interactive opt-in marker is honoured only while it is fresh.**
///
/// The marker is a `touch` of a file in the UI-test runner's container, and nothing removes it.
/// On 2026-10-30 it was found ARMED with an mtime 29 days old ([[T-8926]]), which made every bare
/// full-scheme run in that month a run that would drive the owner's screen. A marker that old is
/// nobody's live opt-in, so the verdict below refuses it, and the person who does mean it re-arms
/// it with the same `touch` right before the run.
enum CadenceInteractiveOptInMarker {

    static let fileName = "cadence-run-interactive-ui-tests"

    /// How long after its last `touch` the marker still counts as an opt-in. One hour covers an
    /// attended run started right after arming it; it does not cover a marker left behind.
    static let maximumAge: TimeInterval = 60 * 60

    /// A marker dated in the future is refused as well, beyond this much clock or timestamp slack:
    /// otherwise `touch -t` far ahead would re-open exactly the standing opt-in this closes.
    static let futureTolerance: TimeInterval = 60

    enum Verdict: Equatable {
        case absent
        case fresh
        /// `age` is negative for a marker dated in the future.
        case stale(age: TimeInterval)
    }

    static func verdict(
        atPath path: String,
        now: Date,
        maximumAge: TimeInterval = Self.maximumAge,
        fileManager: FileManager = .default
    ) -> Verdict {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { return .absent }
        guard let modified = attributes[.modificationDate] as? Date else {
            return .stale(age: .infinity)
        }
        let age = now.timeIntervalSince(modified)
        guard age >= -futureTolerance, age <= maximumAge else { return .stale(age: age) }
        return .fresh
    }

    /// The age as a person reads it in a skip message: whole minutes under two days, days after.
    static func describe(age: TimeInterval) -> String {
        guard age.isFinite else { return "of unknown age" }
        if age < 0 { return "dated \(Int((-age / 60).rounded())) minute(s) in the future" }
        let minutes = Int((age / 60).rounded())
        if minutes < 48 * 60 { return "\(minutes) minute(s) old" }
        return "\(minutes / (24 * 60)) day(s) old"
    }
}
