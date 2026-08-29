import Foundation
import Testing

/// Runs `body` against a `UserDefaults` suite that belongs to the calling test alone.
///
/// The suite name used to carry a fresh `UUID()`, so every run opened a suite it had never used
/// before. `removePersistentDomain(forName:)` empties a suite's domain but does **not** delete the
/// plist `cfprefsd` writes to back it, so each run stranded another 42-byte empty file in the
/// container's `Library/Preferences` — 4,629 of them, 18.5 MB, by the time it was measured against
/// four legitimate files.
///
/// Deriving the name from the calling test keeps the property the `UUID()` was there for and drops
/// the one that leaked:
/// - **unique per test**, because Swift Testing runs tests in parallel by default and two tests
///   sharing one suite would read and clobber each other's writes;
/// - **stable across runs**, so the backing file is reused instead of multiplied. The count is
///   bounded at one file per test that asks for a suite, forever, rather than one per test per run.
///
/// The domain is cleared on the way in as well as on the way out. That matters now that the name is
/// reused: a run killed mid-test would otherwise leave values behind for the next run to read.
///
/// - Parameters:
///   - scope: The suite-name prefix for this test file, e.g. `"CadenceTests.ai"`.
///   - test: Defaults to the calling test's own name, which is what makes each name unique. Pass it
///     explicitly only when one test needs two suites at once.
func withTemporaryDefaults<T>(
    _ scope: String,
    test: String = #function,
    _ body: (UserDefaults) throws -> T
) throws -> T {
    let name = temporaryDefaultsSuiteName(scope: scope, test: test)
    let defaults = try #require(
        UserDefaults(suiteName: name),
        "Could not open the temporary UserDefaults suite \(name)"
    )
    defaults.removePersistentDomain(forName: name)
    defer { defaults.removePersistentDomain(forName: name) }
    return try body(defaults)
}

/// `#function` arrives as `someTestName()`; the parentheses would land in the plist's filename.
private func temporaryDefaultsSuiteName(scope: String, test: String) -> String {
    let identifier = test.filter { $0.isLetter || $0.isNumber }
    return identifier.isEmpty ? scope : "\(scope).\(identifier)"
}

// MARK: - The two launch reports the app reads back on the next launch

/// The `UserDefaults` keys a test writes just by running a migration or a repair (T-480).
///
/// Both hold "what happened to your data the last time the app touched it", read back on the next
/// launch, and neither service takes an injectable store: `record(_:)` is a private static that
/// writes `UserDefaults.standard`, so **any** test that reaches `migrateIfNeeded` or
/// `repairIfNeeded` writes one of these — deliberately or not.
///
/// That both keys belong here was measured rather than reasoned about. On 2026-08-29 the app's
/// stored repair report read `{"source":"test-again",…}` and its migration report
/// `{"source":"startup-test-2",…}`; both strings appear in exactly one place in the repo, and it is
/// the same place — `CadenceTests/NoteMigrationServiceTests.swift`. So the app had been reading two
/// fabricated launch reports, from one test file, for as long as anyone had run the suite.
nonisolated enum StoredLaunchReports {
    static let keys = [
        "noteMigration.lastReport.v1",
        "dataIntegrityRepair.lastReport.v1"
    ]

    static func snapshot() -> [(key: String, value: Data?)] {
        keys.map { ($0, UserDefaults.standard.data(forKey: $0)) }
    }

    /// Restoring an **absent** key means removing it, not skipping it. Skipping is the quiet half
    /// of this bug: a fresh install has neither key, so a guard that only puts back what it found
    /// would still leave a fabricated report behind for exactly the user least able to spot it.
    static func restore(_ saved: [(key: String, value: Data?)]) {
        for (key, value) in saved {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

/// Runs `body` with those keys snapshotted and put back afterwards.
///
/// A free function as well as a trait, so the restore itself is testable: a scoped trait can only
/// be observed from outside the test it scopes, and a guard nobody can fail is the kind that stops
/// working without telling anyone.
nonisolated func withStoredLaunchReportsPreserved<T>(_ body: () throws -> T) rethrows -> T {
    let saved = StoredLaunchReports.snapshot()
    defer { StoredLaunchReports.restore(saved) }
    return try body()
}

/// The same save-and-restore, applied to every test in a suite rather than to the one test whose
/// subject happens to be the key.
///
/// `DataIntegrityRepairServiceTests` established the convention with a hand-written
/// `let saved = … defer { … }` inside a single test, which is right when a single test touches the
/// key deliberately. `NoteMigrationServiceTests` has twenty call sites that touch it
/// *incidentally*, and repeating the block twenty times is twenty chances to miss the twenty-first.
///
/// `isRecursive` is what carries a suite trait down to the tests inside it, and it is load-bearing
/// — **measured, because this is the one part of the guard no test in the suite can fail on.** With
/// the flag flipped to `false`, all 20 tests still pass and the app's stored
/// `noteMigration.lastReport.v1` still goes from its real 426-byte report to a 54-byte fixture.
/// The three-way reading, taken by hashing the key out of the test host's own preferences plist
/// either side of a scoped run:
///
/// | suite annotation      | tests | `noteMigration.lastReport.v1` |
/// | --------------------- | ----- | ----------------------------- |
/// | removed               | 20 ✓  | **changed**                   |
/// | present, `isRecursive` false | 20 ✓ | **changed**            |
/// | present, as written   | 20 ✓  | unchanged                     |
///
/// Every row passes. That is the whole point: the failure this guard prevents is invisible from
/// inside the process, so `theStoredLaunchReportGuardPutsEveryKeyBackBothWaysRound` can only cover
/// the restore *logic*, and the wiring has to be checked from outside or not at all.
///
/// A caution for whoever measures it next: compare the **whole** stored value. The first version of
/// this measurement truncated the key's base64 to 44 characters, which cut off `startedAt` and
/// `finishedAt` — the only fields two runs of the same deterministic fixture differ in — and so
/// reported "unchanged" for every configuration above, including the unguarded one.
nonisolated struct PreservedLaunchReportsTrait: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    /// `@concurrent` on the closure is not decoration: this target compiles with
    /// `nonisolated(nonsending)` closures by default, which is *not* the type `TestScoping`
    /// declares, so the plain spelling fails to satisfy the requirement outright.
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        let saved = StoredLaunchReports.snapshot()
        defer { StoredLaunchReports.restore(saved) }
        try await function()
    }
}

nonisolated extension Trait where Self == PreservedLaunchReportsTrait {
    static var preservesTheStoredLaunchReports: Self { Self() }
}
