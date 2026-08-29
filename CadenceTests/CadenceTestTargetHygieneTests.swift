import Foundation
import Testing

// MARK: - T-161, part one: the instrument

/// `CadenceScanInstrument` exists because the last five "tests that guarded nothing" in this repo
/// were not all the same defect, and the newest one was not an assertion at all.
///
/// Four were hollow *assertions*: arithmetic that could not go red, a needle counted over a scope a
/// mutation walked around, a test appended to the wrong `struct`, a name shared with another suite.
/// The fifth (`b05869d`, M2) was a hollow **instrument** feeding a sound assertion — the detector
/// under a whole-folder sweep was blinded to `false`, the sweep reported no offenders, and the
/// repo's rule was enforced nowhere while the suite stayed green.
///
/// The type's answer is that a sweep is only reachable through a constructor that has already run
/// the detector against a positive and a negative witness. These tests are that claim, stated
/// against the instrument itself.
struct CadenceScanInstrumentTests {

    private let saysDone: (String) -> Bool = { $0.contains("status: .done") }

    private func doneInstrument(
        by detect: @escaping (String) -> Bool
    ) throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "done status",
            fires: "let task = make(status: .done)",
            andNotOn: "let task = make(status: .cancelled)",
            by: detect
        )
    }

    @Test func aSoundInstrumentIsBuiltAndAnswersBothWays() throws {
        let instrument = try doneInstrument(by: saysDone)
        #expect(instrument.name == "done status")
        #expect(instrument.fires(on: "status: .done"))
        #expect(instrument.fires(on: "status: .cancelled") == false)
    }

    /// The M2 shape. A detector blinded to `false` looks exactly like a clean repo to every sweep
    /// written over it, so the refusal has to happen before the sweep can run at all.
    @Test func aDetectorBlindedToFalseCannotBeBuilt() {
        #expect(throws: CadenceScanInstrument.Failure.self) {
            _ = try doneInstrument(by: { _ in false })
        }
    }

    /// The other degenerate end, and the one that would make a sweep report the whole repo. It is
    /// also the shape a never-true assertion takes when it is written as a predicate.
    @Test func aDetectorThatFiresOnEverythingCannotBeBuilt() {
        #expect(throws: CadenceScanInstrument.Failure.self) {
            _ = try doneInstrument(by: { _ in true })
        }
    }

    /// A sweep over nothing is the oldest way a source scan passes forever: a walk pointed at a
    /// renamed folder returns `[]`, `offenders.isEmpty` holds, and the test is green.
    @Test func aSweepOverAnEmptyWalkRefusesRatherThanReportingNoOffenders() throws {
        let instrument = try doneInstrument(by: saysDone)
        #expect(throws: CadenceScanInstrument.Failure.self) {
            _ = try instrument.sweep([], atLeast: 0, including: "a", read: { _ in "" })
        }
    }

    /// `atLeast` and `including` are non-defaulted arguments, so a sweep that forgets its
    /// non-vacuity claim does not compile. These two are what they cost when they are wrong.
    @Test func aSweepThatWalksFewerFilesThanClaimedRefuses() throws {
        let instrument = try doneInstrument(by: saysDone)
        #expect(throws: CadenceScanInstrument.Failure.self) {
            _ = try instrument.sweep(["a", "b"], atLeast: 9, including: "a", read: { _ in "" })
        }
    }

    @Test func aSweepThatNeverReachesItsWitnessFileRefuses() throws {
        let instrument = try doneInstrument(by: saysDone)
        #expect(throws: CadenceScanInstrument.Failure.self) {
            _ = try instrument.sweep(["a", "b"], atLeast: 2, including: "c", read: { _ in "" })
        }
    }

    @Test func aSoundSweepReturnsTheOffendersItFoundSorted() throws {
        let sources = [
            "b.swift": "let task = make(status: .done)",
            "a.swift": "let task = make(status: .done)",
            "c.swift": "let task = make(status: .cancelled)"
        ]
        let offenders = try doneInstrument(by: saysDone).sweep(
            ["a.swift", "b.swift", "c.swift"],
            atLeast: 3,
            including: "c.swift",
            read: { sources[$0] ?? "" }
        )
        #expect(offenders == ["a.swift", "b.swift"])
    }
}

// MARK: - T-161, part two: the target scanned against itself

/// Two of the five failure shapes are properties of the **test target**, not of any one test, and
/// neither is visible from inside the suite that suffers from it.
///
/// - A test appended to the wrong `struct` is invisible to `-only-testing:CadenceTests/ThatSuite`
///   while passing in a full run, so every mutation reads as a survivor.
/// - A test name shared with another suite makes mutation evidence ambiguous, because the log
///   prints the bare function name with no suite qualifier: `grep '✔ Test name()'` on a green log
///   cannot tell a survivor in your suite from a pass in someone else's.
///
/// The second is mechanically checkable target-wide, so it is checked here. When this suite was
/// written **13 names were shared across 46 declarations**, and the concentration is the finding:
/// `theSourceScanActuallyReachesBothPlatformsSource` had eleven copies,
/// `theSourceScanActuallyReadsTheseFiles` six, `theSourceScanIsNotVacuous` six,
/// `theCommentStrippingIsActuallyStripping` three. Those are the *non-vacuity self-checks* — the
/// tests whose whole job is to notice a hollow instrument, and the ones a masked survivor hurts
/// most. Renamed, and kept unique by the test below.
struct CadenceTestTargetHygieneTests {

    /// The rule `docs/SUBAGENT_RUNBOOK.md` states as a manual step, held mechanically instead.
    @Test func everyTestFunctionNameInTheTargetIsUniqueAcrossSuites() throws {
        let declarations = try cadenceTestDeclarations()

        // Non-vacuity, three ways: the walk reached the target, the parser found roughly the
        // number of tests the suite reports, and it found *this* test — a parser that returns
        // nothing satisfies "no duplicates" perfectly.
        #expect(declarations.count > 3000, "parsed only \(declarations.count) @Test functions")
        #expect(
            declarations.contains { $0.name == "everyTestFunctionNameInTheTargetIsUniqueAcrossSuites" },
            "non-vacuity: the parser did not find the test asking the question"
        )
        #expect(
            declarations.contains { $0.suite == "CadenceTestTargetHygieneTests" },
            "non-vacuity: the parser did not attribute anything to this suite"
        )

        var byName: [String: [String]] = [:]
        for declaration in declarations {
            byName[declaration.name, default: []].append("\(declaration.suite) (\(declaration.file))")
        }
        let shared = byName
            .filter { $0.value.count > 1 }
            .map { "\($0.key): \($0.value.sorted().joined(separator: ", "))" }
            .sorted()
        // A literal with interpolation, not a concatenation: `#expect`'s second argument is a
        // `Comment`, which is `ExpressibleByStringInterpolation` but not convertible from a
        // computed `String`.
        #expect(
            shared.isEmpty,
            """
            test names shared across suites, which makes mutation evidence ambiguous:
            \(shared.joined(separator: "\n"))
            """
        )
    }

    /// The parser above is itself an instrument, so it is built like one.
    ///
    /// The negative witness is the case that matters: a bare `func` with no `@Test` in front of it
    /// is most of every test file, and a parser that counted those would report thousands of
    /// "duplicates" named `makeContainer`.
    @Test func theTestDeclarationParserTellsATestFromAPlainFunction() throws {
        let instrument = try CadenceScanInstrument(
            "@Test declaration",
            fires: """
            struct Suite {
                @Test func theThingHolds() throws { #expect(true) }
            }
            """,
            andNotOn: """
            struct Suite {
                private func makeContainer() throws -> Int { 0 }
            }
            """,
            by: { !cadenceTestDeclarations(in: $0, file: "fixture").isEmpty }
        )
        // And the shape the survey script had to handle: `@Test` carrying a display name, on its
        // own line, above the signature.
        #expect(
            instrument.fires(on: """
            struct Suite {
                @Test("a display name")
                func theThingHolds() throws {}
            }
            """)
        )
    }

    /// String literals are masked before the target is parsed, and this suite is the reason it is
    /// not optional: the fixtures above spell `@Test func theThingHolds` inside a literal, in a
    /// file the scan walks. Without masking, this suite would report itself as a duplicate.
    @Test func theTargetScanReadsCodeRatherThanItsOwnFixtures() throws {
        let declarations = try cadenceTestDeclarations()
        #expect(
            declarations.contains { $0.name == "theThingHolds" } == false,
            "the scan counted a needle spelled inside a string literal as a declaration"
        )
        #expect(
            CadenceSourceScan.codeOnly("let needle = \"@Test func ghost()\" // and a comment")
                .contains("ghost") == false
        )
        // Equal length, so every offset a scan computes still points where it did. This is the
        // assertion `Cadence/Shared/AGENTS.md` says to write instead of `stripped.count < raw.count`.
        let raw = "let needle = \"@Test func ghost()\" // and a comment"
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw)
        #expect(code.count == raw.count)
    }

    /// One never-true spelling, pinned by name because it has been written here before and the
    /// stripper's contract guarantees it can never fail.
    ///
    /// This is a *spelling* guard and nothing more — it says what it can catch, which is the same
    /// thing said the same way. It cannot recognise the general shape "an assertion that is red
    /// whatever the code does".
    @Test func noTestClaimsStrippingCommentsMakesTheSourceShorter() throws {
        let instrument = try CadenceScanInstrument(
            "never-true stripped-length comparison",
            fires: "#expect(stripped.count < raw.count)",
            andNotOn: "#expect(stripped.count == raw.count)",
            by: { source in
                CadenceSourceScan.matchCount(
                    "\\bstripped[A-Za-z0-9_]*\\.count\\s*<(?!=)|\\.count\\s*>(?!=)\\s*stripped[A-Za-z0-9_]*\\.count",
                    in: CadenceSourceScan.codeOnly(source)
                ) > 0
            }
        )
        let files = try cadenceTestFiles()
        let offenders = try instrument.sweep(
            files,
            atLeast: 200,
            including: "CadenceTests/CadenceSourceScanSupport.swift",
            read: cadenceTestSource
        )
        #expect(
            offenders.isEmpty,
            "`stripped.count < raw.count` is never true — the stripper blanks, it does not remove: \(offenders)"
        )
    }
}

// MARK: - Reading the test target

struct CadenceTestDeclaration: Equatable {
    let name: String
    let suite: String
    let file: String
}

/// `#filePath` rather than a resolved path, for the reason `CadenceMisfiledSurfaceTests` gives:
/// an isolated build tree reaches the repo through a symlinked prefix.
private func cadenceTestRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func cadenceTestSource(_ relativePath: String) throws -> String {
    try String(
        contentsOf: cadenceTestRepositoryRoot().appendingPathComponent(relativePath),
        encoding: .utf8
    )
}

func cadenceTestFiles() throws -> [String] {
    cadenceRepoSwiftFiles(under: "CadenceTests")
}

/// Every `.swift` **file** under a repo-relative directory, as repo-relative paths.
///
/// The `isDirectory` check is not defensive tidiness: `CadenceTests` really does contain a
/// *directory* called `CadenceCalendarLinkHealthTests.swift`, with the suite of that name inside
/// it. A walk that trusts the suffix hands that path to a reader, the read throws, and every sweep
/// written over the walk fails for a reason that has nothing to do with what it was checking.
func cadenceRepoSwiftFiles(under relativeDirectory: String) -> [String] {
    let root = cadenceTestRepositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }
    return enumerator
        .compactMap { element -> String? in
            guard let name = element as? String, name.hasSuffix(".swift") else { return nil }
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(name).path
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { return nil }
            return "\(relativeDirectory)/\(name)"
        }
        .sorted()
}

/// Every `@Test` function in the target, with the type that declares it.
func cadenceTestDeclarations() throws -> [CadenceTestDeclaration] {
    try cadenceTestFiles().flatMap { path in
        cadenceTestDeclarations(in: try cadenceTestSource(path), file: path)
    }
}

/// The parser. Literals are masked and comments blanked first, so neither a needle nor a doc
/// comment can present itself as a declaration; both passes keep the source's length, so the
/// offsets below still point at the code they came from.
func cadenceTestDeclarations(in source: String, file: String) -> [CadenceTestDeclaration] {
    let code = CadenceSourceScan.codeOnly(source)
    let nsCode = code as NSString

    // Brace depth per UTF-16 offset, so only *top-level* type declarations count as suites. A
    // nested `private struct Store` fixture is not the suite its neighbours are declared in, and
    // attributing tests to it produces a failure message that sends the reader to the wrong place.
    var depths = [Int](repeating: 0, count: nsCode.length)
    var depth = 0
    for offset in 0..<nsCode.length {
        depths[offset] = depth
        let unit = nsCode.character(at: offset)
        if unit == 0x7B { depth += 1 } else if unit == 0x7D { depth -= 1 }
    }

    var types: [(location: Int, name: String)] = []
    if let typeRegex = try? NSRegularExpression(
        pattern: "\\b(?:struct|final class|class|actor|enum)\\s+([A-Za-z0-9_]+)"
    ) {
        for match in typeRegex.matches(in: code, range: NSRange(location: 0, length: nsCode.length))
        where depths[match.range.location] == 0 {
            types.append((match.range.location, nsCode.substring(with: match.range(at: 1))))
        }
    }

    guard let testRegex = try? NSRegularExpression(pattern: "@Test\\b(?s:.)*?\\bfunc\\s+([A-Za-z0-9_]+)")
    else { return [] }

    return testRegex
        .matches(in: code, range: NSRange(location: 0, length: nsCode.length))
        .map { match in
            let start = match.range.location
            let suite = types.last { $0.location < start }?.name ?? "<file scope>"
            return CadenceTestDeclaration(
                name: nsCode.substring(with: match.range(at: 1)),
                suite: suite,
                file: file
            )
        }
}
