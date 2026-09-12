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
/// **The service layer routes through here now (T-745, of which T-949 is the same ticket
/// re-counted).** It used to read the device-wide domain directly at **27** sites the app target
/// alone compiles — 15 literal `UserDefaults.standard` calls, and 12 parameters defaulted to
/// `.standard`, which T-949's census did not count because it greps one spelling. Six keys were
/// reachable through two stores at once: `notificationsEnabled`, `noteTemplateOverrides`, the
/// hidden- and observed-calendar lists, the four `CadencePreferenceKeys` the UI-test reset clears,
/// and the retired key `purgeRetiredKeys` drops. They agreed only because no launch argument was
/// present, which is the sense in which there was no invariant here at all — and the reason this is
/// now a rule rather than a header: `CadenceDefaultsRoutingSweepTests`.
///
/// **What it still does not cover**, deliberately, so nobody reads more into it than it says.
///
/// 1. An app launched by *tapping its icon* on the simulator carries no launch arguments and so
///    shares the device-wide domain again.
/// 2. Two files keep an unrouted store because a target that cannot compile *this* file also
///    compiles them: `Theme` and `CadenceWidgetRefreshCenter` reach the **app-group** suite on
///    purpose — the widget is a separate process, and the accent id and the reload state are the
///    two facts both processes must agree about.
///
/// **`DataIntegrityRepairService` and `NoteMigrationService` used to be a third and fourth
/// ([[T-1170]]), and the reason they no longer are is worth keeping.** They were exempt because
/// `CadenceMCPServer`'s explicit source list had no `CadenceDefaults` in it — which is a statement
/// about a *build graph*, not about who owns the file being written. Measured: the signed-in
/// person's own `com.haoranwei.Cadence.plist` came out of an ordinary `CadenceTests` run with the
/// same 86 keys and two different values, both `…lastReport.v1`, stamped inside the run — a debug
/// test host carries this app's bundle id, so `UserDefaults.standard` there is their file. This
/// file is in that target's Sources phase now, so both services route; and the shared scheme's
/// `TestAction` passes `-CadenceSuiteName xctest-host`, so the store they route *to* during a test
/// run is a private suite. Neither half works alone: with no launch argument `store` **is**
/// `UserDefaults.standard`.
/// `nonisolated`, and it has to be: three of the sites routed through it — `NoteTemplateLibrary`,
/// `PursuitToGoalMigration` and `CadenceCalendarLinkObservations` — are themselves `nonisolated`,
/// and under this project's main-actor default isolation a `static let` here is main-actor-bound.
/// Measured: routing them at an isolated `CadenceDefaults` produced seven
/// *"main actor-isolated static property 'store' can not be referenced from a nonisolated context"*
/// warnings against a zero baseline, and no error — a preference store is per-process state, not
/// UI state, so the isolation was never load-bearing.
nonisolated enum CadenceDefaults {
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

    /// Whether a store is one of the private per-launch suites rather than the shared domain —
    /// **T-1157**, and the question a destructive tooling path has to ask before it deletes.
    ///
    /// It lives *here* for the same reason `resolvedStore` does: this is the one file in the app
    /// target allowed to name `UserDefaults.standard`, and `CadenceDefaultsRoutingSweepTests`
    /// enforces that. `CadenceUITestSupport` asked the question itself first and the sweep caught
    /// it — correctly, and for exactly the reason the sweep exists, since a second file spelling
    /// the shared domain is how the app ends up reading one key out of two stores.
    static func isPrivateSuite(_ store: UserDefaults) -> Bool {
        store !== UserDefaults.standard
    }
}
