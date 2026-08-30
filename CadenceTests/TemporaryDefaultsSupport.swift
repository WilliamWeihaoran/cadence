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
    try withTemporaryDefaults(scope, test: test, opening: { UserDefaults(suiteName: $0) }, body)
}

/// The same, for a test whose store is a `UserDefaults` **subclass** — a counting or recording
/// double, which is the only reason a suite here is ever opened by hand.
///
/// `opening` exists because a default argument cannot pin a generic parameter: spelling
/// `UserDefaults(suiteName:)` as the default would fix `Store` to `UserDefaults` and make the
/// overload above the only one anybody could call. It is the whole difference between this helper
/// covering `CalendarDateMemoryWriterTests` and that suite keeping its own `UUID()` (T-516).
func withTemporaryDefaults<Store: UserDefaults, T>(
    _ scope: String,
    test: String = #function,
    opening open: (String) -> Store?,
    _ body: (Store) throws -> T
) throws -> T {
    let name = temporaryDefaultsSuiteName(scope: scope, test: test)
    let defaults = try #require(
        open(name),
        "Could not open the temporary UserDefaults suite \(name)"
    )
    defaults.removePersistentDomain(forName: name)
    defer { defaults.removePersistentDomain(forName: name) }
    return try body(defaults)
}

/// And the `async` spelling, for the two writer tests that await a scheduled write inside the
/// scope. Sharing a name with the two above is deliberate and safe: overload resolution picks the
/// `async` one only in an `async` context, so a synchronous caller cannot reach it by accident and
/// an asynchronous one cannot silently get the version that would drop its `await`.
func withTemporaryDefaults<Store: UserDefaults, T>(
    _ scope: String,
    test: String = #function,
    opening open: (String) -> Store?,
    _ body: (Store) async throws -> T
) async throws -> T {
    let name = temporaryDefaultsSuiteName(scope: scope, test: test)
    let defaults = try #require(
        open(name),
        "Could not open the temporary UserDefaults suite \(name)"
    )
    defaults.removePersistentDomain(forName: name)
    defer { defaults.removePersistentDomain(forName: name) }
    return try await body(defaults)
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

// MARK: - Keeping the trait on the suites that need it

/// Which top-level suites in a test file reach a launch-report writer **without** carrying
/// `.preservesTheStoredLaunchReports` (T-485).
///
/// The trait above is a one-line fix that has to be remembered, and T-480 landed it on one suite
/// while three siblings kept leaking — `DataIntegrityRepairServiceTests`,
/// `CadenceHabitCompletionDuplicateTests` and `CadenceNoteFolderSurfaceTests`, 15 call sites
/// between them. This is the half that makes it durable: the next suite to call `repairIfNeeded`
/// without the trait is named by a test rather than found by whoever next reads the app's stored
/// report and wonders why it says `{"source":"test"}`.
///
/// Attribution is **per suite, not per file**. A file-level rule would pass a two-suite file the
/// moment either suite carried the trait, and a suite trait does not reach its sibling; the
/// extents come from `cadenceTopLevelTypeExtents(inCodeOnly:)`, the same reader
/// `noTestInTheTargetIsDeclaredOutsideEverySuite` uses.
///
/// Read through `CadenceSourceScan.codeOnly`, which blanks comments *and* string literals. Both
/// halves are load-bearing here: this very file names both writers in prose above and spells both
/// of them as literals below, and a scan that read either would report the guard's own definition
/// as the thing that needs guarding.
nonisolated enum StoredLaunchReportSuiteRule {
    /// The two calls that write `StoredLaunchReports.keys` as a side effect of doing their job.
    /// Neither takes an injectable store, which is the whole reason the trait exists.
    static let writers = ["migrateIfNeeded(", "repairIfNeeded("]

    /// Spelled as the trait is written at a use site, `@Suite(.preservesTheStoredLaunchReports)`,
    /// rather than as the type name: the type name also appears in this file's own declarations.
    static let traitSpelling = ".preservesTheStoredLaunchReports"

    static func unguardedSuites(in source: String) -> [String] {
        let code = CadenceSourceScan.codeOnly(source)
        let text = code as NSString
        var offenders: [String] = []
        var previousClose = 0

        for extent in cadenceTopLevelTypeExtents(inCodeOnly: code) {
            defer { previousClose = min(extent.close + 1, text.length) }
            guard extent.declaration >= previousClose else { continue }

            let body = text.substring(
                with: NSRange(location: extent.open, length: extent.close - extent.open)
            )
            guard writers.contains(where: { body.contains($0) }) else { continue }

            // The attributes belong to this declaration only when they sit between it and the end
            // of whatever came before it. Taking "the lines above" instead would let one annotated
            // suite vouch for the sibling declared under it.
            let attributes = text.substring(
                with: NSRange(
                    location: previousClose,
                    length: extent.declaration - previousClose
                )
            )
            if !attributes.contains(traitSpelling) { offenders.append(extent.name) }
        }
        return offenders
    }
}

// MARK: - Suites nobody can bound (T-516)

/// Which `UserDefaults` suite names a test file derives from `UUID()`.
///
/// **The leak this exists to stop, measured in the app's own container:** 7,727 preference plists,
/// ~30 MB, 316 of them written in 48 hours and growing every run. `removePersistentDomain(forName:)`
/// empties a suite's domain; it does **not** delete the plist `cfprefsd` wrote to back it. So a
/// suite name carrying a fresh `UUID()` strands one more file per test per run, forever, and the
/// `defer { removePersistentDomain(…) }` beside it looks exactly like the cleanup that would have
/// prevented it.
///
/// `withTemporaryDefaults` above is the fix and has been since [[T-480]] — its name comes from
/// `#function`, so the file count is bounded at one per test rather than one per test per run.
/// Four files kept rolling their own anyway, which is the half a helper cannot do by existing.
///
/// **What it reads, and why not `codeOnly`.** Two of the four spelled the name as
/// `"prefix.\(UUID().uuidString)"`, and `CadenceSourceScan.codeOnly` blanks a string literal
/// whole — interpolation included — so the `UUID()` inside one is invisible to it. This rule
/// therefore reads ordinary literals and blanks only comments and triple-quoted blocks. Blanking
/// the triple-quoted blocks is what keeps the sweep from reporting its own witnesses: every
/// fixture in this target is a multi-line literal, and every real suite name is a single-line one.
nonisolated enum TemporaryDefaultsSuiteRule {

    /// The offending suite-name expressions in `source`, sorted. Empty is the state the target is
    /// held in.
    static func uuidDerivedSuiteNames(in source: String) -> [String] {
        let text = readableSource(source)
        let bindings = uuidDerivedBindings(in: text)
        var offenders: Set<String> = []
        for argument in suiteNameArguments(in: text) {
            let expression = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expression.isEmpty else { continue }
            if expression.contains("UUID(") || bindings.contains(expression) {
                offenders.insert(expression)
            }
        }
        return offenders.sorted()
    }

    /// Comments and *fixture* literals blanked, ordinary literals kept.
    ///
    /// A fixture in this target is written one of two ways — a triple-quoted block or a raw
    /// `#"..."#` literal — and a real suite name is written as neither. That is what lets this rule
    /// read literal *content*, which it must for the interpolated names, without reporting the
    /// witnesses that quote the very line it hunts. Both forms are blanked and both were needed:
    /// blanking only the blocks left the two single-line raw fixtures in
    /// `CadenceTestTargetHygieneTests` as the sweep's own first offenders, measured.
    static func readableSource(_ source: String) -> String {
        blankingFixtureLiterals(CadenceSourceScan.strippingComments(source))
    }

    /// Every name bound to an expression that mentions `UUID(` — `let suite = UUID().uuidString`,
    /// and the parameter default `_ name: String = UUID().uuidString` that hid the same thing
    /// behind a helper in `CalendarDateMemoryTests`. File-scoped rather than statement-scoped: a
    /// suite name is bound in one line and spent in another.
    static func uuidDerivedBindings(in text: String) -> Set<String> {
        var bindings: Set<String> = []
        for match in captures(#"\b(\w+)\s*(?::\s*[A-Za-z0-9_.<>\[\]?, ]+?)?\s*=(?!=)([^\n]*)"#, in: text) {
            if match.count == 2, match[1].contains("UUID(") { bindings.insert(match[0]) }
        }
        return bindings
    }

    /// Every expression that reaches a `suiteName:` argument: the ones written there directly, and
    /// the ones handed to a local helper that writes one.
    ///
    /// The second half is not thoroughness for its own sake. Three of the four offending sites
    /// passed their `UUID()` string *positionally* into a `freshDefaults(_:)` or
    /// `countingDefaults(_:)` one line further up the file, so a rule that only read the literal
    /// `suiteName:` argument would have named one file of the four. The `withTemporaryDefaults`
    /// scope is there for the same reason from the other end: routing through the helper and then
    /// handing it a `UUID()` scope looks like the fix and leaks like the bug.
    static func suiteNameArguments(in text: String) -> [String] {
        var arguments = captures(#"suiteName:\s*([^,)\n]*)"#, in: text).compactMap(\.first)
        // The helper's own `scope`, because handing it a `UUID()` leaks exactly as hard as
        // opening the suite by hand: `temporaryDefaultsSuiteName` appends the test's name to
        // whatever it is given, so a unique scope is a unique suite is another stranded plist.
        arguments += captures(#"withTemporaryDefaults\(\s*([^,)\n]*)"#, in: text).compactMap(\.first)
        for sink in suiteNameSinks(in: text) {
            arguments += captures("\\b\(sink)\\s*\\(([^()\n]*)\\)", in: text).compactMap(\.first)
        }
        return arguments
    }

    /// Functions declared in this file whose body opens a suite.
    static func suiteNameSinks(in text: String) -> [String] {
        captures(#"func\s+(\w+)\s*\("#, in: text)
            .compactMap(\.first)
            .filter { CadenceSourceScan.functionBody(named: $0, in: text)?.contains("suiteName:") == true }
    }

    /// The capture groups of every match, or `[]` when the pattern does not compile.
    private static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let value = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: value.length)).map { match in
            (1..<match.numberOfRanges).map { group in
                let range = match.range(at: group)
                return range.location == NSNotFound ? "" : value.substring(with: range)
            }
        }
    }

    /// Triple-quoted blocks blanked to spaces of equal length, newlines kept — the same shape
    /// `CadenceSourceScan`'s strippers use, so offsets and line numbers survive.
    private static func blankingFixtureLiterals(_ source: String) -> String {
        var characters = Array(source)
        let count = characters.count

        func blank(_ range: Range<Int>) {
            for position in range where !characters[position].isNewline { characters[position] = " " }
        }

        var index = 0
        while index < count {
            // A raw literal, of any hash width, single-line or multi-line. Its terminator carries
            // the same run of `#`, which is what tells a single-line one where it ends — the shape
            // `CadenceSourceScan.codeOnly` already had to learn (T-465).
            if characters[index] == "#" {
                var hashEnd = index
                while hashEnd < count, characters[hashEnd] == "#" { hashEnd += 1 }
                let hashes = hashEnd - index
                if hashEnd < count, characters[hashEnd] == "\"" {
                    let quotes = isTripleQuote(characters, at: hashEnd, count: count) ? 3 : 1
                    var end = hashEnd + quotes
                    var close = count
                    while end < count {
                        if characters[end] == "\"",
                           end + quotes + hashes <= count,
                           (end..<(end + quotes)).allSatisfy({ characters[$0] == "\"" }),
                           ((end + quotes)..<(end + quotes + hashes)).allSatisfy({ characters[$0] == "#" }) {
                            close = end + quotes + hashes
                            break
                        }
                        // A single-line raw literal cannot span a newline; stopping here keeps an
                        // unterminated one from blanking the rest of the file.
                        if quotes == 1, characters[end].isNewline { close = end; break }
                        end += 1
                    }
                    blank(index..<close)
                    index = close
                    continue
                }
            }

            if isTripleQuote(characters, at: index, count: count) {
                var end = index + 3
                while end + 2 < count, !isTripleQuote(characters, at: end, count: count) { end += 1 }
                let close = end + 2 < count ? end + 3 : count
                blank(index..<close)
                index = close
                continue
            }

            index += 1
        }
        return String(characters)
    }

    private static func isTripleQuote(_ characters: [Character], at index: Int, count: Int) -> Bool {
        index + 2 < count
            && characters[index] == "\""
            && characters[index + 1] == "\""
            && characters[index + 2] == "\""
    }
}
