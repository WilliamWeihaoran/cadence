import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// T-182: "derive a pane decision from the width you were handed" is one rule with nine
/// expressions living in four files, and the decision was to leave them in their surfaces and put a
/// **register** at the top of `CadenceRegularPaneLayout.swift` saying so.
///
/// A register is a comment, and a comment cannot fail. This file is what makes it fail.
///
/// **Why the inventory rather than the arithmetic.** Every floor here is already pinned numerically
/// somewhere: `CadenceTodayLayoutSupportTests` pins 761 and its sum, `CadenceNotesListSupportTests`
/// pins 601 and its sum, `CadenceRegularPaneLayoutTests` pins 681 and the week grid's 842. None of
/// them can fail when a *fifth* surface writes a sixth floor of its own in a new file, which is
/// exactly what happened between `d0adfdc` and this ticket: the notes split was added with the whole
/// suite green because nothing observed where the rule was allowed to live. So the assertions below
/// are about placement, not about values, and they change no computed value to make them.
///
/// **The style is `CadenceSharedTaskRowJobsTests`'s**, for the same reason it gives: exact per-file
/// counts rather than "contains", comment-stripping rather than allowlisting, and a non-vacuity test
/// so a scan that has stopped reading anything cannot make the absence assertions pass silently.
///
/// **These counts are meant to be annoying.** Adding a width-taking function to one of the four
/// homes fails `theWidthRuleIsDeclaredOnlyInItsRegisteredHomes` until the number here is edited, and
/// editing the number is the prompt to go and edit the register. That is the whole mechanism —
/// a fifth copy in a new file cannot be committed without walking past the list of the four places
/// it should have gone instead.
struct CadencePaneWidthRuleHomesTests {

    // MARK: - The inventory

    /// The house file. Holds six of the nine expressions and the register naming all of them.
    private static let houseFile = "Cadence/Shared/CadenceRegularPaneLayout.swift"

    /// Every file allowed to *declare* a function that takes a host-supplied width, and how many
    /// such functions each may declare.
    ///
    /// - `CadenceRegularPaneLayout.swift` (13): `CadenceRegularSplitLayout`'s `listPaneWidth` /
    ///   `supportsTwoPanes` (T-252), `CadenceCalendarPaneLayout`'s `inspectorWidth` /
    ///   `calendarWidth` / `showsInspector` / `showsDayInspector`,
    ///   `CadenceSettingsTemplatesCardLayout`'s `supportsTwoColumns` / `layout` (T-248/T-249),
    ///   `CadenceDesktopSplitLayout`'s `todayLayout` / `goalsShowsInspector` / `focusShowsSidebar`
    ///   (T-250), and `CadenceCalendarBoardLayout`'s `railForm` / `dayColumnsWidth` (T-251).
    ///   `CadenceCalendarBoardLayout.railWidth(form:)` is deliberately not among them: it answers
    ///   from a form the caller already has, not from a width, which is the same distinction the
    ///   `availableWidth` note below draws.
    /// - `CadenceTodayLayoutSupport.swift` (5): `supportsTwoPane`, `layout`, `inspectorPaneFloor`,
    ///   `taskPaneWidth`, `inspectorPaneIdealWidth`.
    /// - `CadenceRootShellLayout.swift` (3): `usesExpandedSidebar`, `sidebarWidth`, `detailWidth`.
    /// - `CadenceNotesListSupport.swift` (2): `supportsTwoColumns`, `layout`.
    private static let registeredHomes: [String: Int] = [
        houseFile: 13,
        "Cadence/Shared/CadenceTodayLayoutSupport.swift": 5,
        "Cadence/Shared/CadenceRootShellLayout.swift": 3,
        "Cadence/Shared/CadenceNotesListSupport.swift": 2,
    ]

    /// The one file that takes a `paneWidth` and owns none of the rule:
    /// `CadenceCalendarMonthLayout.placement(paneWidth:)` asks `CadenceCalendarPaneLayout` and
    /// translates the answer into Month's vocabulary. Listed separately because it is the *model*,
    /// not an exemption — `theDelegatingReaderStillOnlyDelegates` is what keeps it one.
    private static let delegatingReader = "Cadence/Shared/CadenceCalendarAgendaSupport.swift"
    private static let delegatingReaderDeclarationCount = 1

    /// The nine expressions, by type name. Every one must be named in the register.
    private static let registeredTypeNames = [
        "CadenceRegularSplitLayout",
        "CadenceCalendarWeekGridLayout",
        "CadenceCalendarPaneLayout",
        "CadenceTodayLayoutSupport",
        "CadenceNotesListMetrics",
        "CadenceRootShellLayout",
        "CadenceSettingsTemplatesCardLayout",
        "CadenceDesktopSplitLayout",
        "CadenceCalendarBoardLayout",
    ]

    /// A function declaration whose parameter list takes a width its host measured and handed down.
    ///
    /// The three spellings are the whole vocabulary this repo uses for that — `paneWidth` (the
    /// window less the shell sidebar), `hostWidth` (whatever a surface's own `onGeometryChange`
    /// reported) and `windowWidth` (the shell itself). `availableWidth` is deliberately **not** in
    /// the list: `CadenceCalendarWeekGridLayout.dayColumnWidth` and `CadenceFlowLayoutSupport.lines`
    /// both take one, and dividing a run into N items is a different job from deciding whether two
    /// panes fit. Including it would make this test about wrapping helpers.
    ///
    /// A fifth surface could of course dodge the scan by calling its parameter `w`. That is what
    /// `theRegisterNamesEveryFileTheScanFinds` is for — it derives its expectation from the scan
    /// rather than from a literal list, so the two tests fail together on a new file and the register
    /// is the thing that has to be brought up to date either way.
    private static let declarationPattern = #"func\s+\w+\s*\([^)]*?(paneWidth|hostWidth|windowWidth)"#

    // MARK: - Where the rule may be declared

    /// Exact counts in the five files that may declare it, and zero everywhere else in `Cadence/`.
    @Test func theWidthRuleIsDeclaredOnlyInItsRegisteredHomes() throws {
        var expected = Self.registeredHomes
        expected[Self.delegatingReader] = Self.delegatingReaderDeclarationCount

        for path in try paneRuleSwiftFiles(under: "Cadence") {
            let actual = try paneRuleMatchCount(
                of: Self.declarationPattern,
                in: paneRuleStrippingComments(paneRuleSource(path))
            )
            let allowed = expected[path] ?? 0
            #expect(
                actual == allowed,
                """
                \(path) declares \(actual) width-derived pane decisions, expected \(allowed). \
                If this is a new split surface, it belongs in one of the four files listed in the \
                register at the top of \(Self.houseFile) — not in a fifth copy of the arithmetic.
                """
            )
        }
    }

    /// Nine expressions, twenty-four declarations, five files. The absolute total, so that a
    /// rename that happened to keep every per-file count intact while moving a function between two
    /// registered homes still trips something.
    @Test func theInventoryIsStillTwentyFourDeclarationsAcrossFiveFiles() throws {
        var total = 0
        var files: Set<String> = []

        for path in try paneRuleSwiftFiles(under: "Cadence") {
            let count = try paneRuleMatchCount(
                of: Self.declarationPattern,
                in: paneRuleStrippingComments(paneRuleSource(path))
            )
            if count > 0 {
                total += count
                files.insert(path)
            }
        }

        #expect(total == 24, "the width rule is declared \(total) times, expected 24")
        #expect(files.count == 5, "it is spread over \(files.count) files, expected 5")
        #expect(files == Set(Self.registeredHomes.keys).union([Self.delegatingReader]))
    }

    // MARK: - The register cannot go stale

    /// The register's list is checked against the *scan*, not against this file's literal map. So a
    /// new home fails here even if somebody updates `registeredHomes` and forgets the comment.
    @Test func theRegisterNamesEveryFileTheScanFinds() throws {
        // Comments intact: the register *is* a comment.
        let register = try paneRuleSource(Self.houseFile)

        for path in try paneRuleSwiftFiles(under: "Cadence") {
            let count = try paneRuleMatchCount(
                of: Self.declarationPattern,
                in: paneRuleStrippingComments(paneRuleSource(path))
            )
            guard count > 0, path != Self.houseFile else { continue }

            let fileName = (path as NSString).lastPathComponent
            #expect(
                register.contains(fileName),
                "\(fileName) declares the width rule but the register in \(Self.houseFile) does not name it"
            )
        }
    }

    @Test func theRegisterNamesAllNineExpressionsAndTheModelToCopy() throws {
        let register = try paneRuleSource(Self.houseFile)

        for name in Self.registeredTypeNames {
            #expect(register.contains(name), "the register does not name \(name)")
        }
        // The delegating reader is part of the register's argument, not a footnote to it.
        #expect(register.contains("CadenceCalendarMonthLayout"))
        #expect(register.contains("CadenceCalendarAgendaSupport.swift"))
        // And the register has to point at this file, or nothing tells the next agent the list is
        // enforced rather than aspirational.
        #expect(register.contains("CadencePaneWidthRuleHomesTests"))
    }

    // MARK: - The one reader that is the model

    /// `CadenceCalendarAgendaSupport.swift` may take a `paneWidth`; it may not grow a floor.
    ///
    /// This is the shape a fifth surface should copy, so it is pinned as a *delegation*: one call
    /// into the house file, and no width constant of its own. `Month` splitting at 681 because
    /// `CadenceCalendarPaneLayout` does is a reading of one rule; `Month` splitting at 681 because
    /// it says `681` is a seventh copy.
    @Test func theDelegatingReaderStillOnlyDelegates() throws {
        let code = try paneRuleStrippingComments(paneRuleSource(Self.delegatingReader))

        #expect(
            code.components(separatedBy: "CadenceCalendarPaneLayout.showsInspector(").count - 1 == 1,
            "Month's placement no longer asks the house file for the split"
        )
        for floorSpelling in ["MinimumWidth", "MinWidth", "paneDividerWidth"] {
            #expect(
                code.components(separatedBy: floorSpelling).count - 1 == 0,
                "\(Self.delegatingReader) has grown its own \(floorSpelling) instead of reading one"
            )
        }
    }

    // MARK: - The floors are still sums of their parts

    /// Raising a column has to move the floor with it. That property is a *spelling*: a floor
    /// written as `a + divider + b` follows its parts and a floor written as `601` does not, and
    /// both satisfy every numeric assertion in the suite on the day they are written.
    ///
    /// One occurrence each, in live code. The comment in `CadenceTodayLayoutSupport.swift` that
    /// quotes its own sum is stripped before counting — which is also what
    /// `theCommentStrippingIsActuallyStripping` uses to prove the stripper runs.
    @Test func everyRegisteredFloorIsStillSpelledAsASumRatherThanTyped() throws {
        // An array rather than a dictionary: the house file states two of them now, and a map
        // keyed on the path can only hold one sum per file.
        let sums: [(path: String, sum: String)] = [
            ("Cadence/Shared/CadenceTodayLayoutSupport.swift",
             "taskPaneMinWidth + inspectorPaneMinWidth + paneDividerWidth"),
            ("Cadence/Shared/CadenceNotesListSupport.swift",
             "regularColumnWidth + columnDividerWidth + minimumEditorWidth"),
            (Self.houseFile, "inspectorMinWidth * 2 + paneDividerWidth"),
            (Self.houseFile,
             "chooserWidth(isDesktop: isDesktop) + columnSpacing * 2 + columnDividerWidth + minimumEditorWidth"),
            // T-252: derived from this type's own share, because the four details state no floor.
            (Self.houseFile, "listPaneMinWidth / listPaneFraction"),
            // T-250: three macOS pages, each summing the panes' own declared minimums.
            (Self.houseFile,
             "todayNotesPaneMinWidth + todayTaskPaneMinWidth + todaySchedulePaneMinWidth"),
            (Self.houseFile, "todayTaskPaneMinWidth + todaySchedulePaneMinWidth + paneDividerWidth"),
            (Self.houseFile, "goalListPaneMinWidth + goalInspectorPaneMinWidth + paneDividerWidth"),
            (Self.houseFile,
             "focusSessionPaneMinWidth + focusSidebarPaneMinWidth + paneDividerWidth"),
            // T-251: the Calendar Board's three, including the one borrowed floor. The rails' gate
            // is a sum of the board's own parts, and the collapsed strip's floor is a *reference*
            // to the control minimum this file already states — typing `44` here would satisfy
            // every value assertion in the suite and stop following its source the next day.
            (Self.houseFile, "dayColumnWidth + dayColumnHorizontalPadding * 2"),
            (Self.houseFile, "expandedRailWidth * 2 + oneDayColumnMinimumWidth"),
            (Self.houseFile,
             "CadenceCalendarWeekGridLayout.minimumTouchTarget + railHorizontalPadding * 2"),
        ]

        for (path, sum) in sums {
            let code = try paneRuleStrippingComments(paneRuleSource(path))
            let actual = code.components(separatedBy: sum).count - 1
            #expect(
                actual == 1,
                "\(path) spells its floor as `\(sum)` \(actual) times, expected 1 — a typed floor stops following its parts"
            )
        }
    }

    /// The notes floor's parts are not all local to it, deliberately: the editor half's minimum *is*
    /// Today's inspector floor, by reference. Pinned because it is reason 3 in the register — the
    /// coupling that matters was already crossing a file boundary before the consolidation question
    /// was asked, which is why co-locating the sums would not have been what prevented anything.
    @Test func theNotesFloorStillBorrowsTodaysInspectorFloorByReference() throws {
        let code = try paneRuleStrippingComments(
            paneRuleSource("Cadence/Shared/CadenceNotesListSupport.swift")
        )
        #expect(code.contains("CadenceTodayLayoutSupport.inspectorPaneMinWidth"))
        #expect(
            CadenceNotesListMetrics.minimumEditorWidth
                == CadenceTodayLayoutSupport.inspectorPaneMinWidth
        )
    }

    // MARK: - Non-vacuity

    /// Everything above is an absence assertion over a file enumeration, and a file enumeration that
    /// silently returns nothing makes all of them pass. `CadenceSharedBoardChromeTests` records the
    /// case that motivated this: a `/tmp` against `/private/tmp` path mismatch on an isolated build
    /// tree made four real regressions look like a clean run.
    @Test func theSourceScanActuallyReachesTheFilesItIsCounting() throws {
        let files = try paneRuleSwiftFiles(under: "Cadence")

        #expect(files.count > 300, "the scan found \(files.count) files and cannot be doing its job")
        for path in Self.registeredHomes.keys {
            #expect(files.contains(path), "the scan never reached \(path)")
        }
        #expect(files.contains(Self.delegatingReader))
        // A file the rule must never reach, so the zero-expectation half is exercised against
        // something that really exists rather than only against absences.
        #expect(files.contains("Cadence/Shared/Theme.swift"))
    }

    /// Proof the stripper runs, from a case that exists in the tree rather than a synthetic one:
    /// `CadenceTodayLayoutSupport.swift` states its floor once in code and quotes it once in the
    /// prose explaining the divider bug. Raw source therefore sees two and stripped source one. If
    /// stripping ever silently became the identity function, every exact count above would drift.
    @Test func theCommentStrippingIsActuallyStrippingInPaneWidthRuleHomes() throws {
        let path = "Cadence/Shared/CadenceTodayLayoutSupport.swift"
        let sum = "taskPaneMinWidth + inspectorPaneMinWidth + paneDividerWidth"

        let raw = try paneRuleSource(path)
        let stripped = try paneRuleStrippingComments(raw)

        #expect(raw.components(separatedBy: sum).count - 1 == 2)
        #expect(stripped.components(separatedBy: sum).count - 1 == 1)
    }
}

// MARK: - Source-reading helpers

/// Prefixed rather than shared: the equivalents in `CadenceSharedTaskRowJobsTests`,
/// `CadenceSharedBoardChromeTests` and `CadenceNotesListSupportTests` are all `private` to their
/// files, and hoisting them into a common helper is a separate change from this one.
private func paneRuleRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields *absolute* paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func paneRuleSwiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = paneRuleRepositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func paneRuleSource(_ relativePath: String) throws -> String {
    try String(contentsOf: paneRuleRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions read code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make these
/// checks stricter about what counts as a comment, never looser about live code.
private func paneRuleStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}

/// `NSRegularExpression` rather than a `range(of:options:.regularExpression)` loop, because the
/// declaration pattern spans a multi-line parameter list and counting needs every match rather than
/// the first.
private func paneRuleMatchCount(of pattern: String, in source: String) throws -> Int {
    let regex = try NSRegularExpression(pattern: pattern)
    return regex.numberOfMatches(
        in: source,
        range: NSRange(source.startIndex..<source.endIndex, in: source)
    )
}
