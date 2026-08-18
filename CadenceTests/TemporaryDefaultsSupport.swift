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
