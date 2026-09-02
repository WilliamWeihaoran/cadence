import Foundation

/// Where this app's stored preferences live — `UserDefaults.standard` in the product, and a
/// private per-agent suite when a launch asks for one.
///
/// **T-735, and it is a tooling defect that reads as a product bug.** `scripts/simulator-claim.sh`
/// hands each agent a private *store* (`CADENCE_UI_TEST_STORE_ID`), and its header argues from
/// that store that two agents on one shared simulator cannot merge data. That argument holds for
/// SwiftData and is false for `UserDefaults`: every `@AppStorage` value and every remembered
/// position lives in one device-wide domain that survives reinstall.
///
/// The cost was measured on 2026-09-03. The compact Calendar tab opened on **August 2026 with
/// Aug 17 selected** on a cold launch against an **empty** private store, which looks exactly like
/// a date bug and was chased as one for twenty minutes. It was another agent's leftover
/// `CadenceCalendarDateMemory` keys.
///
/// So the redirect is mechanical rather than a warning in a header, because a header only helps an
/// agent who reads it *before* being misled. A launch argument names the suite:
///
/// ```sh
/// xcrun simctl launch <udid> com.haoranwei.Cadence -CadenceSuiteName j4
/// ```
///
/// `-CadenceSuiteName` lands in `NSArgumentDomain`, which is read-only and per-launch, so nothing
/// about this reaches a user's device: with no such argument `store` **is** `UserDefaults.standard`
/// and every call site behaves exactly as it did.
///
/// **What it does not cover**, deliberately, so nobody reads more into it than it says: an app
/// launched by *tapping its icon* on the simulator carries no launch arguments and so shares the
/// device-wide domain again, and the direct `UserDefaults.standard` reads in the service layer
/// (notifications, integrity reports, restores) are not routed through here.
enum CadenceDefaults {
    /// The launch-argument key. Spelled once: the script that passes it is scanned for this exact
    /// text by `CadenceAgentDefaultsIsolationTests`.
    static let suiteNameArgumentKey = "CadenceSuiteName"

    /// The prefix a private suite's name is built from. Not the bundle identifier itself —
    /// `UserDefaults(suiteName:)` answers `nil` for the app's own domain, which would silently
    /// fall back to the shared one.
    static let suiteNamePrefix = "com.haoranwei.Cadence.agent."

    /// The suite a launch argument asks for, or `nil` for "use the standard domain".
    ///
    /// A pure decision so it can be tested without launching anything. It refuses more than it
    /// accepts on purpose: the value becomes a preferences *filename*, and an id carrying a slash
    /// or a space would either fail to open or write somewhere nobody expects. Refusing lands on
    /// `UserDefaults.standard`, which is the shared domain — the pre-T-735 behaviour, not a
    /// silently different one.
    static func suiteName(forAgentID raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return suiteNamePrefix + trimmed
    }

    /// The store every `@AppStorage` in the app resolves against, via `defaultAppStorage` on the
    /// scene, and the default `CadenceCalendarDateMemory` reads and writes through.
    ///
    /// Resolved once: the argument domain cannot change while the process runs, and a `lazy static`
    /// keeps the two readers from disagreeing halfway through a launch.
    static let store: UserDefaults = resolvedStore()

    /// The resolution, with the argument-domain read handed in so a test can drive it.
    static func resolvedStore(agentID: String? = UserDefaults.standard.string(forKey: suiteNameArgumentKey)) -> UserDefaults {
        guard let name = suiteName(forAgentID: agentID),
              let suite = UserDefaults(suiteName: name) else { return .standard }
        return suite
    }
}
