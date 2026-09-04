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

// MARK: - T-644 / T-659: the readers the sweeps are built on

/// The instrument above refuses a blinded *detector*. These are the layer under it: the two shared
/// **readers** that decide which text a detector is even shown.
///
/// Both defects in this suite are the same shape and neither was an error or a warning — a green
/// assertion over the wrong span. `functionBody(named:)` handed back a default closure instead of a
/// function body; `reportFollowsTheCatch` answered a weaker question than its own name. A reader
/// that reads slightly other than what the rule says makes every suite built on it less trustworthy
/// than its green result looks, so the discriminating cases live here rather than only inside the
/// suites that happen to call them.
struct CadenceSourceScanReaderTests {

    /// **T-644.** The exact shape that broke it: a `commit:` parameter defaulted to a closure. The
    /// old reader took the first `{` after `func <name>(` and returned `try $0.save()`; the reader
    /// balances the parameter list first, so it returns the body.
    ///
    /// The assertions are written in both directions on purpose. `contains("theRealBody()")` is
    /// what the callers do and is what silently went green; `!contains("try $0.save()")` is what
    /// says the returned span is not merely a *superset* that happens to include the body.
    @Test func theFunctionBodyReaderSkipsADefaultedClosureInTheParameterList() {
        let source = """
        static func toggleCompletion(
            _ task: Task,
            in modelContext: ModelContext,
            commit: (ModelContext) throws -> Void = { try $0.save() }
        ) throws {
            theRealBody()
        }
        """
        let body = CadenceSourceScan.functionBody(named: "toggleCompletion", in: source)
        #expect(body?.contains("theRealBody()") == true, "read \(body ?? "nil") instead of the body")
        #expect(
            body?.contains("try $0.save()") == false,
            "the reader is still handing back the default closure (T-644)"
        )
    }

    /// The same reader on the ordinary shape, so the fix is not "returns something bigger". A
    /// signature with no brace in it must still read exactly as it did before.
    @Test func theFunctionBodyReaderStillReadsAPlainSignatureUnchanged() {
        let source = "func plain(a: Int, b: (Int) -> Int) -> Int {\n    a + b(a)\n}"
        #expect(CadenceSourceScan.functionBody(named: "plain", in: source)?.contains("a + b(a)") == true)
        #expect(CadenceSourceScan.functionBody(named: "absent", in: source) == nil)
        // A signature whose parentheses never balance is a `nil`, not a body read off the end.
        #expect(CadenceSourceScan.functionBody(named: "torn", in: "func torn(a: Int {\n    x\n") == nil)
    }

    /// **T-668.** The same defect one layer out, in the reader `cadenceFunctionBody` used to spell
    /// for itself: an *arbitrary* declaration prefix, which is why the second copy existed at all.
    /// A prefix that stops inside the parameter list must still skip a defaulted closure, and the
    /// throwing wrapper the 83 call sites use must read the same span the shared reader does.
    @Test func theDeclarationBodyReaderSkipsADefaultedClosureInAnOpenParameterList() throws {
        let source = """
        static func rollOver(
            _ tasks: [AppTask],
            todayKey: String,
            modelContext: ModelContext,
            commit: (ModelContext) throws -> Void = { try $0.save() }
        ) throws -> String {
            try CadencePendingChangePersistence.commitDelete(in: modelContext, commit: commit)
            return todayKey
        }
        """
        let body = try #require(CadenceSourceScan.declarationBody("static func rollOver(", in: source))
        #expect(body.contains("commitDelete(in: modelContext, commit: commit)"),
                "read \(body) instead of the body")
        #expect(body.contains("try $0.save()") == false,
                "the reader is still handing back the default closure (T-644, T-668)")
        #expect(try cadenceFunctionBody("static func rollOver(", in: source) == body,
                "the throwing wrapper and the shared reader disagree about the span")

        // The prefix that stops *before* the parameter list opens, which the copied reader also
        // could not see past: `handleCommandKeyEvent` is called that way at a real site.
        let named = try #require(CadenceSourceScan.declarationBody("static func rollOver", in: source))
        #expect(named == body, "a prefix stopping at the name reads a different span")
    }

    /// The other direction, so T-668's fix is not "returns something bigger". A prefix with no
    /// parentheses, and one whose parentheses are already closed, must read exactly what they read
    /// before — the second is `.onChange(of:)`, where the brace that follows *is* the span wanted.
    @Test func theDeclarationBodyReaderLeavesAClosedOrParenlessPrefixWhereItWas() throws {
        let view = "struct MacTaskRow: View {\n    var body: some View { Text(\"row\") }\n}"
        #expect(CadenceSourceScan.declarationBody("var body: some View", in: view) == " Text(\"row\") ")

        let onChange = ".onChange(of: scenePhase) { _, phase in\n    reconcile()\n}"
        #expect(
            CadenceSourceScan.declarationBody(".onChange(of: scenePhase)", in: onChange)?
                .contains("reconcile()") == true
        )

        #expect(CadenceSourceScan.declarationBody("func absent(", in: view) == nil)
        #expect(CadenceSourceScan.declarationBody("func torn(", in: "func torn(a: Int {\n    x\n") == nil)

        // `functionBody(named:)` is this read with one prefix, so the two cannot drift apart.
        let function = "func plain(a: Int, b: (Int) -> Int) -> Int {\n    a + b(a)\n}"
        #expect(
            CadenceSourceScan.functionBody(named: "plain", in: function)
                == CadenceSourceScan.declarationBody("func plain(", in: function)
        )
    }

    /// `matchedRange` is `matchedBody`'s span, and the pairing has to stay honest: `upperBound` is
    /// the index **of** the closing character, which is what lets `functionBody` resume from it.
    @Test func theMatchedRangeAndMatchedBodyReadersAgreeOnTheSameSpan() throws {
        let source = "func f(a: (Int) -> Int = { $0 }) { body() }"
        let parameters = try #require(
            CadenceSourceScan.matchedRange(
                after: source.startIndex,
                in: source,
                open: "(",
                close: ")"
            )
        )
        #expect(String(source[parameters]) == "a: (Int) -> Int = { $0 }")
        #expect(source[parameters.upperBound] == ")")
        #expect(
            CadenceSourceScan.matchedBody(after: source.startIndex, in: source, open: "(", close: ")")
                == String(source[parameters])
        )
    }

    /// **T-659.** The case a surviving mutation found: the report written on *both* sides of the
    /// failure branch. A backwards search finds the copy below and calls the body ordered; the
    /// forwards search anchors on the copy above and refuses it.
    ///
    /// This is the whole defect. The mutation added a second `newTagName = ""` at the top of
    /// `iOSTaskTagPickerPopover.addTag` — clearing the field before the guard, the exact regression
    /// the assertion exists to catch — and stayed green.
    @Test func theOrderingReaderRefusesAReportWrittenOnBothSidesOfTheFailureBranch() {
        let above = "report()\ndo { try commit() } catch { notice = text; return }"
        let below = "do { try commit() } catch { notice = text; return }\nreport()"
        let both = "report()\ndo { try commit() } catch { notice = text; return }\nreport()"

        #expect(!CadenceCommitSurfaceScan.reportFollowsTheCatch("report()", in: above))
        #expect(CadenceCommitSurfaceScan.reportFollowsTheCatch("report()", in: below))
        #expect(
            !CadenceCommitSurfaceScan.reportFollowsTheCatch("report()", in: both),
            "the ordering reader still anchors on the last occurrence (T-659)"
        )
        // The `catch` end stays anchored on the *last* failure branch, so a report between two
        // catches is not ordered either.
        let betweenCatches = """
        do { try one() } catch { return }
        report()
        do { try two() } catch { return }
        """
        #expect(!CadenceCommitSurfaceScan.reportFollowsTheCatch("report()", in: betweenCatches))
        #expect(!CadenceCommitSurfaceScan.reportFollowsTheCatch("report()", in: "report()"))
        #expect(!CadenceCommitSurfaceScan.reportFollowsTheCatch("absent()", in: below))
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

    /// **T-463.** A `.swift` path that is a *directory* has to be reported, not skipped.
    ///
    /// `CadenceTests/CadenceCalendarLinkHealthTests.swift` was a directory containing a file of the
    /// same name — a staging error, flattened in `193f257`. Nothing caught it while it was there:
    /// the target's synchronized root group descends into directories, so the suite inside compiled
    /// and ran, and every walk over the tree either threw on the read or, like
    /// `cadenceRepoSwiftFiles(under:)`, skipped it quietly. The shape was legible to the file system
    /// the whole time and nothing was asking.
    ///
    /// This asks. It is deliberately the *only* reader that fails on the shape: the walks stay
    /// forgiving so a recurrence does not scramble every unrelated sweep into a mystery, and this
    /// one names it.
    @Test func noSwiftPathInTheRepositoryIsADirectory() throws {
        let fileManager = FileManager.default

        // The witnesses first, on a tree this test builds: a real file and a directory wearing the
        // suffix. A detector that has stopped telling them apart passes over the repo trivially.
        let fixtureRoot = fileManager.temporaryDirectory
            .appendingPathComponent("cadence-swift-path-shape-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: fixtureRoot) }
        try fileManager.createDirectory(
            at: fixtureRoot.appendingPathComponent("Impostor.swift", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "// a real source file\n".write(
            to: fixtureRoot.appendingPathComponent("Honest.swift"),
            atomically: true,
            encoding: .utf8
        )
        #expect(cadenceDirectoryShapedSwiftPaths(under: fixtureRoot) == ["Impostor.swift"],
                "the detector cannot tell a directory from a file, so the sweep below proves nothing")

        let root = cadenceTestRepositoryRoot()
        let sourceRoots = ["Cadence", "CadenceTests", "CadenceUITests", "CadenceWidgets", "CadenceMCPServer"]
        var offenders: [String] = []
        var walked = 0
        for directory in sourceRoots {
            let files = cadenceRepoSwiftFiles(under: directory)
            #expect(!files.isEmpty, "the walk reached no Swift file under \(directory)")
            walked += files.count
            offenders += cadenceDirectoryShapedSwiftPaths(
                under: root.appendingPathComponent(directory)
            ).map { "\(directory)/\($0)" }
        }
        #expect(walked > 600, "the sweep saw only \(walked) Swift files, so it walked the wrong tree")
        #expect(
            offenders.isEmpty,
            """
            .swift paths that are directories, which compile by accident and break every walk:
            \(offenders.sorted().joined(separator: "\n"))
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

    /// Suite attribution is brace arithmetic, so it is only as good as the masking underneath it.
    /// A file whose braces do not balance after masking has an offset the parser cannot trust,
    /// and it fails as *eleven stray tests* rather than as one broken file — which is the wrong
    /// message pointed at the wrong place.
    ///
    /// `CadenceTests/MarkdownImageAssetServiceTests.swift` was that file: `#"photo\"#` inside a
    /// `for` header made the masker eat the `{` after it. Asserted target-wide rather than for
    /// that file, because the next raw string is the one nobody will remember to add here.
    @Test func everyTestFileBalancesItsBracesAfterMaskingSoSuiteExtentsCanBeTrusted() throws {
        let instrument = try CadenceScanInstrument(
            "unbalanced braces after masking",
            fires: "struct Suite { func a() { }",
            andNotOn: "struct Suite { func a() { } }",
            by: { source in
                let code = CadenceSourceScan.codeOnly(source)
                return code.filter { $0 == "{" }.count != code.filter { $0 == "}" }.count
            }
        )
        let files = try cadenceTestFiles()
        let offenders = try instrument.sweep(
            files,
            atLeast: 200,
            including: "CadenceTests/MarkdownImageAssetServiceTests.swift",
            read: cadenceTestSource
        )
        #expect(
            offenders.isEmpty,
            """
            braces do not balance after masking, so every offset a scan computes in these files is \
            wrong and suite attribution cannot be trusted: \(offenders)
            """
        )
    }

    /// The masking defect underneath the test above, stated on its own so the fix is pinned rather
    /// than implied by a target that happens to be clean.
    ///
    /// Both raw strings here end in a backslash. Reading it as an escape skips the closing quote,
    /// runs to the end of the line, and takes the `{` with it — so the discriminating assertion is
    /// the brace count *after* the literals, not whether the literals were masked.
    @Test func theMaskerReadsARawStringsTrailingBackslashAsContentRatherThanAnEscape() throws {
        let source = ##"""
        let labels = [#"photo\"#, #"a\"#]; if labels.isEmpty { print("x") }
        """##
        let code = CadenceSourceScan.codeOnly(source)

        // Equal length, so every offset a scan computes still points where it did.
        #expect(code.count == source.count)
        #expect(code != source)
        // The literals are masked...
        #expect(code.contains("photo") == false)
        #expect(code.contains("isEmpty"), "non-vacuity: the masker blanked code either side of it")
        // ...and the code sharing their line survives. This is the assertion that was false.
        #expect(code.filter { $0 == "{" }.count == 1)
        #expect(code.filter { $0 == "}" }.count == 1)
    }

    /// **T-465, the arm of the wrong-`struct` family that *is* mechanical.**
    ///
    /// A `@Test` appended past the closing brace of the last suite in a file is a free function.
    /// It compiles, it runs in a full pass, and it is invisible to
    /// `-only-testing:CadenceTests/ThatSuite` — so every mutation against it reads as a survivor,
    /// which is the exact failure T-161 shipped `scripts/test-suite-index.sh` to make visible.
    ///
    /// Worse than invisible: until this test was written, the parser below answered *wrongly* for
    /// it. `types.last { $0.location < start }` is "the nearest type declared above", which for a
    /// trailing test is the suite it just escaped — so the index built to answer "where did my
    /// test actually land?" named the suite the author meant, for the one case where the author is
    /// wrong. Attribution is by suite **extent** now, and a test outside every extent is
    /// `<file scope>`.
    ///
    /// The target currently holds zero of these, so this is a hard guard with no allowlist. It
    /// does **not** catch the residual case — a test declared inside the wrong *sibling* suite of a
    /// multi-suite file — and nothing here claims to; see the T-465 note in `docs/TODO.md`.
    ///
    /// One known way to trip it falsely: `extension SomeSuite { @Test ... }` at file scope. The
    /// type regex above reads declarations, not extensions, so such a test lands in `<file scope>`
    /// while `-only-testing:CadenceTests/SomeSuite` reaches it perfectly well. The target has none
    /// today, which is why the regex is left alone rather than widened on speculation — if one
    /// lands, add `extension` there rather than allowlisting the file.
    @Test func noTestInTheTargetIsDeclaredOutsideEverySuite() throws {
        let instrument = try CadenceScanInstrument(
            "@Test declared outside every suite",
            fires: """
            struct Suite {
                @Test func theInsideOne() throws {}
            }

            @Test func theStrayOne() throws {}
            """,
            andNotOn: """
            struct Suite {
                @Test func theInsideOne() throws {}
                @Test func theOtherInsideOne() throws {}
            }
            """,
            by: { source in
                cadenceTestDeclarations(in: source, file: "fixture")
                    .contains { $0.suite == CadenceTestDeclaration.fileScope }
            }
        )
        let files = try cadenceTestFiles()
        let offenders = try instrument.sweep(
            files,
            atLeast: 200,
            including: "CadenceTests/CadenceTestTargetHygieneTests.swift",
            read: cadenceTestSource
        )
        #expect(
            offenders.isEmpty,
            """
            these files declare a @Test outside every suite, so `-only-testing:` cannot reach it \
            and a mutation against it reads as a survivor: \(offenders)
            """
        )
    }

    /// The attribution rule stated directly, because the instrument above only asks whether *some*
    /// file-scope declaration exists — it would be satisfied by a parser that called everything
    /// file scope.
    ///
    /// The gap between the second and third cases is the whole point: the same `@Test`, moved four
    /// lines down past a `}`, stops belonging to the suite above it.
    @Test func theDeclarationParserAttributesByExtentRatherThanByWhatIsAboveIt() throws {
        let source = """
        struct FirstSuite {
            @Test func theFirstOne() throws {}
        }

        @Test func theStrandedOne() throws {}

        struct SecondSuite {
            @Test func theSecondOne() throws {}

            private struct Fixture {
                @Test func theNestedOne() throws {}
            }
        }
        """
        let declarations = cadenceTestDeclarations(in: source, file: "fixture")
        #expect(declarations.count == 4, "parsed \(declarations.count) declarations")

        func suite(of name: String) -> String? {
            declarations.first { $0.name == name }?.suite
        }
        #expect(suite(of: "theFirstOne") == "FirstSuite")
        #expect(suite(of: "theSecondOne") == "SecondSuite")
        // A nested fixture type is not a suite: the test inside it still belongs to the top-level
        // type, which is the rule the index has always documented.
        #expect(suite(of: "theNestedOne") == "SecondSuite")
        // The one this test exists for. "Nearest type above" answers `FirstSuite`.
        #expect(
            suite(of: "theStrandedOne") == CadenceTestDeclaration.fileScope,
            "a test past its suite's closing brace was attributed to that suite"
        )
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

    // MARK: - Launch reports the test host leaves behind (T-485)

    /// Every suite that reaches `migrateIfNeeded`/`repairIfNeeded` carries
    /// `.preservesTheStoredLaunchReports`.
    ///
    /// Neither service takes an injectable store — `record(_:)` is a private static writing
    /// `UserDefaults.standard` — so a suite that calls either one rewrites the report the *app*
    /// reads on its next launch, whether or not the report is what the test is about. T-480 fixed
    /// the suite whose subject it was and left three siblings leaking `{"source":"test"}` into the
    /// test host's preferences, which is the shape this sweep exists to stop repeating: the fix is
    /// one line, so the only hard part is noticing it is needed.
    ///
    /// Through `CadenceScanInstrument` because the repo has **zero** offenders once the three are
    /// annotated, and "no offenders" is what a clean repo and a blind detector both look like. The
    /// two witnesses are literal fixtures a line apart — the same suite with and without the
    /// annotation — so a rule that stopped reading the annotation fails the constructor rather than
    /// sweeping green.
    @Test func everyTestSuiteReachingALaunchReportWriterPreservesTheStoredReports() throws {
        let unguarded = """
        @MainActor
        struct ASuiteThatRepairs {
            @Test func aRepairIsIdempotent() throws {
                _ = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
            }
        }
        """
        let instrument = try CadenceScanInstrument(
            "a suite reaches a launch-report writer without the preserving trait",
            fires: unguarded,
            andNotOn: "@Suite(.preservesTheStoredLaunchReports)\n" + unguarded,
            by: { !StoredLaunchReportSuiteRule.unguardedSuites(in: $0).isEmpty }
        )

        let offenders = try instrument.sweep(
            try cadenceTestFiles(),
            atLeast: 200,
            including: "CadenceTests/NoteMigrationServiceTests.swift",
            read: cadenceTestSource
        )
        #expect(
            offenders.isEmpty,
            """
            these suites call migrateIfNeeded/repairIfNeeded without \
            @Suite(.preservesTheStoredLaunchReports), so running them overwrites the launch report \
            the app reads back: \(offenders)
            """
        )
    }

    // MARK: - Suites the test host cannot clean up after (T-516)

    /// No test file derives a `UserDefaults` suite name from `UUID()`.
    ///
    /// `removePersistentDomain(forName:)` empties a suite's domain and leaves the plist `cfprefsd`
    /// wrote to back it, so a suite named after a fresh `UUID()` strands one more file per test per
    /// run — **7,727 of them, ~30 MB, in the app's own container** by the time this was measured,
    /// 316 written in the preceding 48 hours. `withTemporaryDefaults` has derived its name from
    /// `#function` since [[T-480]] precisely so the count is bounded at one file per test forever;
    /// four files kept rolling their own anyway, which is the half a helper cannot do by existing.
    ///
    /// Through `CadenceScanInstrument` for the reason every clean-repo sweep here is: once the four
    /// are routed through the helper the offender list is empty, and empty is what a fixed repo and
    /// a blind detector both look like. The witnesses are the same test with the suite name minted
    /// two ways, so a rule that stopped reading the `UUID()` fails the constructor.
    @Test func noTestInTheTargetNamesAUserDefaultsSuiteAfterAFreshUUID() throws {
        let leaking = """
        @Test func aStoredSelectionRoundTrips() throws {
            let suite = "cadence.tests.palette.\\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            #expect(defaults.string(forKey: "k") == nil)
        }
        """
        let bounded = """
        @Test func aStoredSelectionRoundTrips() throws {
            try withTemporaryDefaults("cadence.tests.palette") { defaults in
                #expect(defaults.string(forKey: "k") == nil)
            }
        }
        """
        let instrument = try CadenceScanInstrument(
            "a UserDefaults suite named after a fresh UUID",
            fires: leaking,
            andNotOn: bounded,
            by: { !TemporaryDefaultsSuiteRule.uuidDerivedSuiteNames(in: $0).isEmpty }
        )

        let offenders = try instrument.sweep(
            try cadenceTestFiles(),
            atLeast: 200,
            including: "CadenceTests/CalendarDateMemoryTests.swift",
            read: cadenceTestSource
        )
        #expect(
            offenders.isEmpty,
            """
            these files open a UserDefaults suite whose name carries a UUID, so every run strands \
            another preference plist in the app's container that nothing ever deletes: \(offenders)
            """
        )
    }

    /// The three readings the rule turns on, none of which a clean sweep can demonstrate.
    ///
    /// The middle one is the reason the rule is not simply "a `suiteName:` argument that spells
    /// `UUID`": **three of the four sites passed the name positionally into a local helper** a few
    /// lines up, so a detector that only read the literal argument would have named one file of
    /// four and left the leak at three-quarters strength.
    @Test func theTemporaryDefaultsSuiteRuleFollowsANameIntoTheHelperThatOpensTheSuite() {
        // 1. Written straight into the argument.
        let inline = #"let defaults = UserDefaults(suiteName: "x.\(UUID().uuidString)")"#
        #expect(!TemporaryDefaultsSuiteRule.uuidDerivedSuiteNames(in: inline).isEmpty)

        // 2. Bound here, spent in a helper whose parameter has a different name entirely — so this
        //    cannot pass by the two identifiers happening to match.
        let throughAHelper = """
        private func store(_ named: String) -> UserDefaults? {
            UserDefaults(suiteName: named)
        }

        @Test func t() throws {
            let chosen = UUID().uuidString
            let defaults = try #require(store(chosen))
        }
        """
        #expect(TemporaryDefaultsSuiteRule.uuidDerivedSuiteNames(in: throughAHelper) == ["chosen"])

        // 2b. Routed through `withTemporaryDefaults` and *then* handed a unique scope. This is the
        //     next mistake rather than a hypothetical one: it reads as the fix, and it leaks
        //     identically, because the helper appends the test's name to whatever scope it is
        //     given.
        let uniqueScope = """
        @Test func t() throws {
            let scope = "cadence.tests.reset.\\(UUID().uuidString)"
            try withTemporaryDefaults(scope) { defaults in
                #expect(defaults.string(forKey: "k") == nil)
            }
        }
        """
        #expect(TemporaryDefaultsSuiteRule.uuidDerivedSuiteNames(in: uniqueScope) == ["scope"])

        // 3. And the fixed suite the app really owns is not an offender. `CadenceAccentPaletteTests`
        //    opens the app group by identifier, which is one file and always the same file.
        let appGroup = """
        @Test func t() throws {
            let group = try #require(UserDefaults(suiteName: CadenceStoreSupport.appGroupIdentifier))
            let probeKey = "cadence.tests.t15.\\(UUID().uuidString)"
            group.set("x", forKey: probeKey)
        }
        """
        #expect(TemporaryDefaultsSuiteRule.uuidDerivedSuiteNames(in: appGroup).isEmpty)
    }

    /// Why the rule reads ordinary string literals when every other structural scan here reads
    /// `CadenceSourceScan.codeOnly`, and what it blanks instead.
    ///
    /// `codeOnly` blanks a literal whole, interpolation included — which is right for a scan
    /// looking for *code shape* and fatal for this one, because two of the four sites spelled the
    /// name as `"prefix.\(UUID().uuidString)"` and the `UUID()` lives inside the literal. So the
    /// rule keeps ordinary literals and blanks the two forms a *fixture* takes — a triple-quoted
    /// block and a raw `#"..."#` literal — because the witnesses above have to quote the very line
    /// the rule hunts. Both halves were measured rather than assumed: with only the blocks blanked
    /// the sweep's first and only offender was this file, named by its own two raw witnesses.
    @Test func theTemporaryDefaultsSuiteRuleReadsLiteralsButNotItsOwnFixtures() {
        let interpolated = #"UserDefaults(suiteName: "x.\(UUID().uuidString)")"#
        #expect(
            CadenceSourceScan.codeOnly(interpolated).contains("UUID(") == false,
            "codeOnly stopped blanking interpolations, so this rule could read it after all"
        )
        #expect(TemporaryDefaultsSuiteRule.readableSource(interpolated).contains("UUID("))

        // A fixture quoting the offending line is not the offending line.
        let fixture = "let sample = \"\"\"\n" + interpolated + "\n\"\"\"\n"
        #expect(TemporaryDefaultsSuiteRule.uuidDerivedSuiteNames(in: fixture).isEmpty)
        #expect(
            TemporaryDefaultsSuiteRule.readableSource(fixture).contains("suiteName") == false,
            "the fixture block was not blanked"
        )

        // ...and so is a fixture written as a single-line raw literal, which is the form both
        // witnesses in the test above take.
        let rawFixture = """
        let inline = #"UserDefaults(suiteName: "x.\\(UUID().uuidString)")"#
        """
        #expect(rawFixture.contains("UUID("), "the raw fixture interpolated instead of quoting")
        #expect(TemporaryDefaultsSuiteRule.uuidDerivedSuiteNames(in: rawFixture).isEmpty)
        #expect(
            TemporaryDefaultsSuiteRule.readableSource(rawFixture).contains("suiteName") == false,
            "the raw fixture was not blanked"
        )

        // ...and comments are gone the way they are everywhere else here.
        #expect(
            TemporaryDefaultsSuiteRule.uuidDerivedSuiteNames(
                in: "// UserDefaults(suiteName: UUID().uuidString)"
            ).isEmpty
        )
    }

    /// The rule's near misses, and the one that matters most: **the trait is attributed per suite.**
    ///
    /// A file-level spelling would have been shorter and is wrong for the same reason T-465's
    /// "nearest declaration above" was wrong — a trait on one top-level type does not reach the
    /// sibling declared beside it, and a file-level rule would let the annotated suite vouch for the
    /// leaking one forever.
    @Test func theLaunchReportSuiteRuleAttributesTheTraitToOneSuiteRatherThanTheWholeFile() throws {
        let siblings = """
        @Suite(.preservesTheStoredLaunchReports)
        struct TheGuardedOne {
            @Test func one() throws {
                _ = try NoteMigrationService.migrateIfNeeded(in: context, source: "test")
            }
        }

        struct TheLeakingOne {
            @Test func two() throws {
                _ = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
            }
        }
        """
        #expect(StoredLaunchReportSuiteRule.unguardedSuites(in: siblings) == ["TheLeakingOne"])

        // ...and the annotation does not reach *upwards* either: a trait written below a suite
        // belongs to whatever follows it.
        let annotationBelow = """
        struct TheLeakingOne {
            @Test func two() throws {
                _ = try DataIntegrityRepairService.repairIfNeeded(in: context, source: "test")
            }
        }

        @Suite(.preservesTheStoredLaunchReports)
        struct SomethingElse {}
        """
        #expect(StoredLaunchReportSuiteRule.unguardedSuites(in: annotationBelow) == ["TheLeakingOne"])

        // A suite that only *mentions* a writer is not one that calls it. Both spellings below are
        // blanked by `codeOnly`, and this file and `TemporaryDefaultsSupport.swift` are each full
        // of them — without this the guard would report its own definition.
        let mentionsOnly = """
        /// Explains what repairIfNeeded(in:source:) does, at length.
        struct TheProseOne {
            @Test func three() throws {
                #expect(name == "migrateIfNeeded(in:source:)")
            }
        }
        """
        #expect(StoredLaunchReportSuiteRule.unguardedSuites(in: mentionsOnly).isEmpty)

        // Non-vacuity for the three negatives above: the same reader does fire when the call is
        // real code, so their emptiness is the rule discriminating rather than the rule being dead.
        #expect(
            StoredLaunchReportSuiteRule.unguardedSuites(in: """
            struct TheRealOne {
                @Test func four() throws {
                    _ = try NoteMigrationService.migrateIfNeeded(in: context, source: "test")
                }
            }
            """) == ["TheRealOne"]
        )
    }

    // MARK: - The real-tree sweep manifest (T-808)

    /// **The pin.** Every `@Test` on `CadenceRealTreeSweepManifest.txt` still exists.
    ///
    /// This is the assertion the manifest was built for. An audit measured 216 tests that walk the
    /// real product tree and found **0** of them pinned: delete one and the ledgers, parsers and
    /// fixtures beside it all keep passing, so an app-wide sweep can stop happening without one
    /// red line anywhere. Deleting any named function now fails here **and**
    /// `theRealTreeSweepManifestIsExactlyWhatTheScanFinds` below, and the two say different things:
    /// this one names the function that went missing, that one names the file to regenerate.
    ///
    /// It asserts nothing about what any swept rule *checks* — that would be a second copy of a
    /// detector, and the suites remain the behavioural authority for their own rules.
    @Test func everyRealTreeSweepOnTheManifestStillExists() throws {
        let listed = try CadenceRealTreeSweepScan.manifest()
        let live = Set(
            try cadenceTestDeclarations()
                .map { CadenceRealTreeSweepScan.Entry(suite: $0.suite, name: $0.name) }
        )

        #expect(!listed.isEmpty, "the manifest is empty, so it pins nothing")
        #expect(
            Set(listed).count == listed.count,
            "the manifest lists a name twice, so one deletion would still leave it looking pinned"
        )

        let gone = listed.filter { !live.contains($0) }.sorted()
        #expect(
            gone.isEmpty,
            """
            these product-tree sweeps are on the manifest but no longer declared: \
            \(gone.map(\.description).joined(separator: ", ")). Either the @Test was deleted — \
            which is what this manifest exists to make visible — or it was renamed or moved, in \
            which case regenerate with `scripts/real-tree-sweep-manifest.sh <id> --write`.
            """
        )
    }

    /// **And the manifest is what the scan finds, not what someone typed.** A ledger nothing
    /// regenerates is the failure this repository keeps re-finding, so the committed file is
    /// compared to the derivation every run: a new sweep that is not listed fails here, and so
    /// does a listed name the scan no longer classifies.
    ///
    /// On a mismatch the regenerated file is printed between banners, which is exactly what
    /// `scripts/real-tree-sweep-manifest.sh` lifts back out of the log — so no second copy of the
    /// classifier lives in a shell script where nothing can fail on it.
    @Test func theRealTreeSweepManifestIsExactlyWhatTheScanFinds() throws {
        let found = try CadenceRealTreeSweepScan.entries()
        let listed = try CadenceRealTreeSweepScan.manifest()

        let unlisted = Set(found).subtracting(listed).sorted()
        let stale = Set(listed).subtracting(found).sorted()
        if !unlisted.isEmpty || !stale.isEmpty {
            CadenceRealTreeSweepScan.printRegenerated(found)
        }

        #expect(
            unlisted.isEmpty,
            """
            these sweep the real product tree and are not on the manifest, so deleting them would \
            still be invisible: \(unlisted.map(\.description).joined(separator: ", ")). \
            Regenerate with `scripts/real-tree-sweep-manifest.sh <id> --write`.
            """
        )
        #expect(
            stale.isEmpty,
            """
            the manifest names these and the scan no longer classifies them as product-tree \
            sweeps: \(stale.map(\.description).joined(separator: ", ")).
            """
        )
    }

    /// The instrument's own witnesses, in this file rather than in a neighbouring suite — the
    /// T-161 lesson that a detector nothing checks is how "no offenders" and "blind" come to look
    /// alike.
    ///
    /// The three fixtures are the three ways this classification is wrong if any one of its
    /// conditions is dropped: a walk of the app tree behind a helper (must fire), a fixed-file
    /// assertion about one real app file (must not), and a walk of `CadenceTests` (must not — it
    /// sweeps the test target, not the app).
    @Test func theRealTreeSweepScanTellsASweepFromAFixedFileAssertion() throws {
        let walksTheApp = """
        import Testing

        struct FixtureSweepTests {
            private func appSources() throws -> [String] {
                try CadenceSourceScan.swiftFiles(under: "Cadence")
            }

            @Test func noSurfaceHandTypesTheThing() throws {
                for path in try appSources() { _ = path }
            }
        }
        """
        let readsOneFixedFile = """
        import Testing

        struct FixtureFixedFileTests {
            @Test func theSharedHelperIsSpelledOnce() throws {
                let source = try CadenceSourceScan.sourceFile("Cadence/Shared/CadencePickerSupport.swift")
                #expect(source.contains("func items("))
            }
        }
        """
        let walksTheTestTarget = """
        import Testing

        struct FixtureTestTreeTests {
            @Test func everyTestFileIsCounted() throws {
                for path in try CadenceSourceScan.swiftFiles(under: "CadenceTests") { _ = path }
            }
        }
        """

        let found = try CadenceRealTreeSweepScan.entries(inSources: [
            (path: "CadenceTests/FixtureSweepTests.swift", source: walksTheApp),
            (path: "CadenceTests/FixtureFixedFileTests.swift", source: readsOneFixedFile),
            (path: "CadenceTests/FixtureTestTreeTests.swift", source: walksTheTestTarget),
        ])

        #expect(
            found.map(\.description) == ["FixtureSweepTests/noSurfaceHandTypesTheThing"],
            "the classifier found \(found.map(\.description)) rather than the one walk of the app"
        )
    }

    /// Non-vacuity for the walk itself: the manifest names sweeps from four different files, and
    /// each is spelled out rather than counted. A manifest that had quietly emptied — a scan that
    /// read no files, a parse that matched nothing — passes both assertions above and fails this.
    @Test func theRealTreeSweepManifestNamesTheSweepsItIsSupposedTo() throws {
        let listed = Set(try CadenceRealTreeSweepScan.manifest().map(\.description))
        for expected in [
            "CadenceRetiredCopyTests/noRetiredCopyIsStillDrawnAnywhereInTheApp",
            "CadenceEmptyStateAuditTests/noEmptyStateSentenceIsSpelledInTwoFiles",
            "CadenceSeedColourSourceTests/noFileOnTheMacOSSurfaceHandTypesAColourHex",
            "WidgetSupportTests/theTitleTrimRuleIsDeclaredOnceInAFileTheWidgetTargetCompiles",
        ] {
            #expect(listed.contains(expected), "the manifest no longer names \(expected)")
        }
    }

    // MARK: - The non-product-tree sweep manifest (T-809)

    /// **A second, small, HAND-pinned manifest — deliberately not a third copy of
    /// `CadenceRealTreeSweepScan`'s transitive-reach classifier.**
    ///
    /// [[T-809]]: two tests walk a real tree — `themoveAnswerIsDiscardedAtFiveTestCallSitesAndNowhereElse`
    /// walks `CadenceTests` itself, `noAgentFacingDocSpellsARetiredIPadName` walks the agent-facing
    /// docs — but neither satisfies [[T-808]]'s rule, because neither reach contains a product-root
    /// path literal. Widening that rule to catch them would also catch the families it excludes on
    /// purpose (see `CadenceRealTreeSweepScan`'s header): dropping the product-root requirement
    /// alone was tried and measured to also catch ~24 unrelated tests across the target — anything
    /// whose *transitive* reach happens to touch a file-scope helper that walks something,
    /// regardless of what the test is actually about. That is the T-808 rule's whole reason for
    /// requiring all three markers together, and loosening it for a two-entry exception reintroduces
    /// exactly the noise it exists to keep out.
    ///
    /// So this manifest is pinned by name, like `misfiledGutterRampAllowed` or
    /// `CadenceEmptyTitleFallbackSweepTests.constantFallbackExemptions` — a handful of exact
    /// entries with their own non-vacuity checks, not a population a scan discovers.
    @Test func everyNonProductTreeSweepOnTheManifestStillExists() throws {
        let listed = try CadenceRealTreeSweepScan.manifest(
            in: cadenceTestSource("CadenceTests/CadenceNonProductTreeSweepManifest.txt")
        )
        let live = Set(
            try cadenceTestDeclarations()
                .map { CadenceRealTreeSweepScan.Entry(suite: $0.suite, name: $0.name) }
        )

        #expect(!listed.isEmpty, "the non-product-tree manifest is empty, so it pins nothing")
        #expect(
            Set(listed).count == listed.count,
            "the non-product-tree manifest lists a name twice, so one deletion would still leave it looking pinned"
        )

        let gone = listed.filter { !live.contains($0) }.sorted()
        #expect(
            gone.isEmpty,
            """
            these non-product-tree sweeps are on the manifest but no longer declared: \
            \(gone.map(\.description).joined(separator: ", ")). Either the @Test was deleted, or it \
            was renamed or moved — update CadenceNonProductTreeSweepManifest.txt by hand.
            """
        )
    }

    /// The two manifests are disjoint by construction — that is the entire point of having two —
    /// checked against the trusted, already-verified [[T-808]] classifier rather than reimplemented.
    /// A name that migrated onto the product-tree manifest (it gained a product-root literal) no
    /// longer belongs on this one; it belongs nowhere twice.
    @Test func noNonProductTreeSweepIsAlsoOnTheProductTreeManifest() throws {
        let nonProduct = try CadenceRealTreeSweepScan.manifest(
            in: cadenceTestSource("CadenceTests/CadenceNonProductTreeSweepManifest.txt")
        )
        let product = Set(try CadenceRealTreeSweepScan.manifest())

        let overlap = nonProduct.filter { product.contains($0) }.sorted()
        #expect(
            overlap.isEmpty,
            "these are pinned on both manifests: \(overlap.map(\.description)) — they satisfy T-808's rule now, so drop them from the non-product-tree manifest instead"
        )
    }

    /// Non-vacuity for each pinned entry, individually: its own function body — not its transitive
    /// reach, which is exactly the machinery this manifest deliberately does not reuse — still
    /// contains one of the walk needles [[T-808]]'s scan looks for. A test that stopped walking
    /// anything at all would still pass `everyNonProductTreeSweepOnTheManifestStillExists` (it still
    /// exists) and this is what would catch that it no longer belongs here.
    @Test func eachNonProductTreeSweepsOwnBodyStillWalksSomething() throws {
        let walkNeedles = [
            "swiftFiles(", "enumerator(atPath:", "enumerator(at:",
            "contentsOfDirectory(at", "subpathsOfDirectory", ".sweep(",
        ]
        let witnesses: [(file: String, function: String)] = [
            (
                "CadenceTests/CadenceInPlaceEditFlushCommitTests.swift",
                "themoveAnswerIsDiscardedAtFiveTestCallSitesAndNowhereElse"
            ),
            ("CadenceTests/CadenceMisfiledSurfaceTests.swift", "noAgentFacingDocSpellsARetiredIPadName"),
        ]
        for witness in witnesses {
            let source = CadenceSourceScan.codeOnly(try cadenceTestSource(witness.file))
            let body = try #require(
                CadenceSourceScan.functionBody(named: witness.function, in: source),
                "\(witness.function) no longer balances in \(witness.file)"
            )
            #expect(
                walkNeedles.contains { body.contains($0) },
                "\(witness.function)'s own body no longer walks anything -- it may no longer belong on the non-product-tree manifest at all"
            )
        }
    }

    /// Non-vacuity, named rather than counted — only two, so both are named.
    @Test func theNonProductTreeSweepManifestNamesTheSweepsItIsSupposedTo() throws {
        let listed = Set(
            try CadenceRealTreeSweepScan.manifest(
                in: cadenceTestSource("CadenceTests/CadenceNonProductTreeSweepManifest.txt")
            ).map(\.description)
        )
        for expected in [
            "CadenceInPlaceEditFlushCommitTests/themoveAnswerIsDiscardedAtFiveTestCallSitesAndNowhereElse",
            "TodayAndInboxNamingTests/noAgentFacingDocSpellsARetiredIPadName",
        ] {
            #expect(listed.contains(expected), "the non-product-tree manifest no longer names \(expected)")
        }
    }
}

// MARK: - Reading the test target

struct CadenceTestDeclaration: Equatable {
    /// The suite name given to a `@Test` that is inside no top-level type at all. Spelled once,
    /// because `scripts/test-suite-index.sh` prints the same string and both are read by eye.
    static let fileScope = "<file scope>"

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
/// The `isDirectory` check is not defensive tidiness. `CadenceTests` once contained a *directory*
/// called `CadenceCalendarLinkHealthTests.swift` with the suite of that name inside it — flattened
/// in `193f257`, and recorded as [[T-463]]. A walk that trusts the suffix hands such a path to a
/// reader, the read throws, and every sweep written over the walk fails for a reason that has
/// nothing to do with what it was checking. Skipping it here keeps the sweeps honest; the shape
/// itself is reported by `noSwiftPathInTheRepositoryIsADirectory`, because a walk that quietly
/// skips one is how the original went unnoticed for a whole session.
/// Every `.swift` path under `root` that is really a **directory**, relative to `root`.
///
/// The inverse of the filter above, and the thing the filter must never be the only reader of: one
/// walk skipping these silently is exactly how [[T-463]] survived.
func cadenceDirectoryShapedSwiftPaths(under root: URL) -> [String] {
    guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }
    return enumerator
        .compactMap { element -> String? in
            guard let name = element as? String, name.hasSuffix(".swift") else { return nil }
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(name).path
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }
            return name
        }
        .sorted()
}

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

/// One top-level type's *extent* in a file whose comments and literals are already blanked.
///
/// UTF-16 offsets, because that is the unit `NSRegularExpression` and `NSString` count in and the
/// parsers below index straight into a `[Int]` of brace depths.
struct CadenceTopLevelTypeExtent: Equatable {
    let name: String
    /// Offset of the `struct`/`class`/`enum`/`actor` keyword that opens the declaration.
    let declaration: Int
    /// Offset of the `{` that opens its body.
    let open: Int
    /// Offset of the `}` that closes it, or the end of the file when the braces never balance.
    let close: Int
}

/// Every top-level type in a file, with the span it encloses.
///
/// Extracted from `cadenceTestDeclarations(in:file:)` (T-485) rather than copied: two suites now
/// ask "which top-level type is this offset inside", and this repo's most common defect is the
/// second copy of an answer like that. Takes source with literals and comments **already blanked**
/// — a caller that hands it raw text gets its own fixtures parsed as declarations.
///
/// "The nearest type declared above this offset" is the wrong rule and this is the right one: a
/// test appended past a closing brace belongs to the file scope the compiler sees, not to the suite
/// the author meant (T-465).
func cadenceTopLevelTypeExtents(inCodeOnly code: String) -> [CadenceTopLevelTypeExtent] {
    let nsCode = code as NSString

    // Brace depth per UTF-16 offset, so only *top-level* type declarations count. A nested
    // `private struct Store` fixture is not the suite its neighbours are declared in, and
    // attributing tests to it produces a failure message that sends the reader to the wrong place.
    var depths = [Int](repeating: 0, count: nsCode.length)
    var depth = 0
    for offset in 0..<nsCode.length {
        depths[offset] = depth
        let unit = nsCode.character(at: offset)
        if unit == 0x7B { depth += 1 } else if unit == 0x7D { depth -= 1 }
    }

    guard let typeRegex = try? NSRegularExpression(
        pattern: "\\b(?:struct|final class|class|actor|enum)\\s+([A-Za-z0-9_]+)"
    ) else { return [] }

    var extents: [CadenceTopLevelTypeExtent] = []
    for match in typeRegex.matches(in: code, range: NSRange(location: 0, length: nsCode.length))
    where depths[match.range.location] == 0 {
        let name = nsCode.substring(with: match.range(at: 1))
        var open = NSNotFound
        var cursor = match.range.location + match.range.length
        while cursor < nsCode.length {
            if nsCode.character(at: cursor) == 0x7B {
                open = cursor
                break
            }
            cursor += 1
        }
        guard open != NSNotFound else { continue }
        var close = nsCode.length
        var scan = open + 1
        while scan < nsCode.length {
            // `depths[scan]` is the depth *before* the character at `scan`, so the brace that
            // closes this body is the first `}` seen back at depth 1.
            if nsCode.character(at: scan) == 0x7D, depths[scan] == 1 {
                close = scan
                break
            }
            scan += 1
        }
        extents.append(
            CadenceTopLevelTypeExtent(
                name: name,
                declaration: match.range.location,
                open: open,
                close: close
            )
        )
    }
    return extents
}

/// The parser. Literals are masked and comments blanked first, so neither a needle nor a doc
/// comment can present itself as a declaration; both passes keep the source's length, so the
/// offsets below still point at the code they came from.
func cadenceTestDeclarations(in source: String, file: String) -> [CadenceTestDeclaration] {
    let code = CadenceSourceScan.codeOnly(source)
    let nsCode = code as NSString
    let types = cadenceTopLevelTypeExtents(inCodeOnly: code)

    guard let testRegex = try? NSRegularExpression(pattern: "@Test\\b(?s:.)*?\\bfunc\\s+([A-Za-z0-9_]+)")
    else { return [] }

    return testRegex
        .matches(in: code, range: NSRange(location: 0, length: nsCode.length))
        .map { match in
            let start = match.range.location
            let suite = types.last { $0.open < start && start < $0.close }?.name
                ?? CadenceTestDeclaration.fileScope
            return CadenceTestDeclaration(
                name: nsCode.substring(with: match.range(at: 1)),
                suite: suite,
                file: file
            )
        }
}
