import Foundation
import Testing
@testable import Cadence

/// T-136: three macOS↔iOS forks that the `iOS` prefix kept out of review.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning
/// `CadenceBoardColumnHeaderMetrics.labelSize == 10` proves the shared thing is correct; it proves
/// nothing about anybody *using* it. T-161 is the standing example: a committed fix was reverted and
/// all 1692 tests stayed green, because the tests pinned a helper while nothing observed the call
/// sites. So every unification below also gets a call-site test that reads the real source files and
/// fails the moment a board goes back to drawing its own header, chip or empty row.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
/// The precedent is `NoteEditorPerformanceRegressionTests`, which guards the note editor's
/// persistence call sites the same way.
struct CadenceSharedBoardChromeTests {

    // MARK: - Board column header — the figures

    /// 10 wins for the label, and macOS had it: every uppercased-kerned-semibold label in the app
    /// is 10pt (`SectionEyebrowLabel`, `CadencePageHeaderMetrics.eyebrowSize`, 14 call sites), and
    /// the iOS board column header at 11 was one of only two exceptions in the codebase.
    @Test func theColumnLabelIsTheAppsOneEyebrowSize() {
        #expect(CadenceBoardColumnHeaderMetrics.labelSize == 10)
        #expect(CadenceBoardColumnHeaderMetrics.labelSize == CadencePageHeaderMetrics.metrics(role: .page, surface: .desktop).eyebrowSize)
    }

    /// 10 wins for the count, and neither platform had it: macOS drew 9 and iOS drew 11. The count
    /// is already demoted from the label by weight (`.medium` vs `.semibold`) and by colour
    /// (`Theme.dim` vs `Theme.muted`), so it does not also need to be smaller — and it must not be
    /// bigger, which is what iOS's 11 made it.
    @Test func theCountMatchesTheLabelAndLetsWeightAndColourDoTheDemoting() {
        #expect(CadenceBoardColumnHeaderMetrics.countSize == 10)
        #expect(CadenceBoardColumnHeaderMetrics.countSize == CadenceBoardColumnHeaderMetrics.labelSize)
    }

    /// macOS's `kanbanColumnHeaderPadding()` was the deliberate spelling; the iOS copy reproduced
    /// the horizontal 4 and the bottom 8 and dropped the top 2. A copy losing a line is not a
    /// platform making a choice.
    @Test func theHeaderKeepsTheFullMacOSPadding() {
        #expect(CadenceBoardColumnHeaderMetrics.horizontalPadding == 4)
        #expect(CadenceBoardColumnHeaderMetrics.topPadding == 2)
        #expect(CadenceBoardColumnHeaderMetrics.bottomPadding == 8)
    }

    /// Both platforms already drew a 7pt dot and the same three accent-rule stops. They are stated
    /// once now so the next change to either lands once.
    @Test func theDotAndTheAccentRuleWereAlreadyAgreedAndAreNowStatedOnce() {
        #expect(CadenceBoardColumnHeaderMetrics.dotSize == 7)
        #expect(CadenceBoardColumnHeaderMetrics.accentRuleOpacities == [0.85, 0.45, 0.16])
    }

    // MARK: - Board column header — the call sites

    /// **The T-161 test.** Every board column on both platforms must reach the shared header. Revert
    /// any one of these seven call sites to a local copy and this fails; pinning the metrics above
    /// would not have noticed.
    @Test func everyBoardColumnOnBothPlatformsDrawsTheSharedHeader() throws {
        try expectCallSites(
            of: "CadenceBoardColumnHeader",
            at: [
                // macOS: section kanban column, list kanban column, Calendar Board day column, rails.
                "Cadence/macOS/Views/KanbanColumnSupportViews.swift": 1,
                "Cadence/macOS/Views/KanbanListColumnView.swift": 1,
                "Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift": 1,
                "Cadence/macOS/Views/CalendarBoardRailSupportViews.swift": 1,
                // iOS: list kanban column, Calendar Board day column, month agenda day section.
                "Cadence/iOS/iOSListSupportViews.swift": 1,
                "Cadence/iOS/iOSCalendarBoardView.swift": 1,
                "Cadence/iOS/iOSCalendarMonthAgendaViews.swift": 1,
            ]
        )
    }

    /// Neither retired spelling may come back — as a call or as a declaration — anywhere in the app
    /// source. `iOSBoardColumnHeader` is the name this ticket exists about: it announced itself as
    /// "iOS counterpart of macOS's `BoardColumnHeader`" in its own doc comment and still read as an
    /// iOS thing rather than a second copy.
    @Test func theForkedColumnHeaderSpellingsAreGone() throws {
        try expectNoLiveMention(of: "iOSBoardColumnHeader")
        try expectNoLiveMention(of: "BoardColumnHeader", excludingPrefixes: ["Cadence", "iOS"])
        try expectNoDeclaration(of: "KanbanColumnTitleRow")
    }

    // MARK: - Board metadata chip

    /// 10 wins for the glyph, and iOS had it. macOS set it at 9 under an 11pt label; two points
    /// under the text it labels is where a glyph stops reading as that text's icon.
    @Test func theChipGlyphSitsOnePointUnderItsLabel() {
        #expect(CadenceBoardMetadataChipMetrics.iconSize == 10)
        #expect(CadenceBoardMetadataChipMetrics.labelSize == 11)
        #expect(CadenceBoardMetadataChipMetrics.iconSize == CadenceBoardMetadataChipMetrics.labelSize - 1)
    }

    /// The chip's radius is the one difference here that was **not** drift, so it is kept — but as a
    /// rule rather than as two literals. A macOS board card rounds at `kanbanCardCornerRadius` (7)
    /// and an iOS one at `Theme.radiusCard` (18); a chip cannot be rounder than the card it is
    /// inside. `min(control, card - 1)` reproduces both platforms' existing values exactly.
    @Test func theChipRadiusFollowsTheCardItSitsIn() {
        #expect(CadenceBoardMetadataChipMetrics.cornerRadius(inCardOfRadius: 7) == 6)
        #expect(CadenceBoardMetadataChipMetrics.cornerRadius(inCardOfRadius: Theme.radiusCard) == Theme.radiusControl)
    }

    /// The rule, not the two answers: a chip never out-rounds its card, never exceeds the control
    /// radius, and never goes negative on a card with no corners at all.
    @Test func theChipIsNeverRounderThanItsCardAndNeverRounderThanAControl() {
        for cardRadius in stride(from: CGFloat(0), through: 30, by: 0.5) {
            let chip = CadenceBoardMetadataChipMetrics.cornerRadius(inCardOfRadius: cardRadius)
            #expect(chip <= Theme.radiusControl)
            #expect(chip <= max(0, cardRadius))
            #expect(chip >= 0)
        }
    }

    /// **The T-161 test for the chip.** Both boards' cards must reach the shared chip.
    @Test func bothBoardsDrawTheSharedMetadataChip() throws {
        let callSites = [
            "Cadence/macOS/Views/CalendarBoardItemSupportViews.swift": 4,
            "Cadence/iOS/iOSBoardCards.swift": 4,
        ]
        try expectCallSites(of: "CadenceBoardMetadataChip", at: callSites)

        for path in callSites.keys {
            // Every call site must hand the chip its card's radius rather than typing a number:
            // that parameter is the whole mechanism by which the kept difference stays a rule.
            let source = try sourceFile(path)
            #expect(
                source.components(separatedBy: "cardCornerRadius:").count - 1 == callSites[path],
                "\(path) has a metadata chip that stopped deriving its radius from its card"
            )
        }
    }

    @Test func theForkedChipSpellingsAreGone() throws {
        try expectNoLiveMention(of: "iOSCalendarBoardMetadataChip")
        try expectNoLiveMention(of: "CalendarBoardMetadataChip", excludingPrefixes: ["iOS"])
    }

    // MARK: - Inline empty

    /// The 12/13 split is kept, because it is the same relationship twice rather than two
    /// decisions: Cadence's desktop body is 13pt and its touch body is 14, and this line sat one
    /// point under the rows it stands in for on each. Flattening it would have made the empty line
    /// louder than the content on one platform.
    @Test func theInlineEmptySitsOnePointUnderTheRowsAroundIt() {
        #expect(CadenceInlineEmptyMetrics.metrics(for: .desktop).textSize == 12)
        #expect(CadenceInlineEmptyMetrics.metrics(for: .touch).textSize == 13)
        #expect(CadenceInlineEmptyMetrics.metrics(for: .desktop).padding == 12)
        #expect(CadenceInlineEmptyMetrics.metrics(for: .touch).padding == 14)
    }

    /// Two surfaces, not three: this is a row among rows, and iPhone and iPad draw the same rows.
    @Test func theInlineEmptyHasNoIPhoneVersusIPadSplit() {
        #expect(CadenceInlineEmptySurface.allCases.count == 2)
    }

    /// `Theme.radiusControl` wins, and only iOS had it — macOS's copy was a bare `9`, which is on no
    /// scale in `Theme` (the ramp is 10 / 18 / 22).
    @Test func theInlineEmptyRoundsOnTheTokenNotOnANearbyNumber() {
        #expect(CadenceInlineEmptyMetrics.cornerRadius == Theme.radiusControl)
    }

    /// **The T-161 test for the inline empty**, and the one that catches the specific failure this
    /// component already had: the shared version lived in `Shared/Components/` the whole time, and
    /// iOS still wrote its own because the file around it was `#if os(macOS)`.
    @Test func bothPlatformsDrawTheSharedInlineEmpty() throws {
        let expectations: [(path: String, surface: String)] = [
            ("Cadence/macOS/Views/GoalsSupportViews.swift", "surface: .desktop"),
            ("Cadence/macOS/Views/GoalAttachWorkSheet.swift", "surface: .desktop"),
            ("Cadence/iOS/iOSCalendarBoardView.swift", "surface: .touch"),
            ("Cadence/iOS/iOSMarkdownAccessoryViews.swift", "surface: .touch"),
        ]

        try expectCallSites(
            of: "CadenceInlineEmpty",
            at: Dictionary(uniqueKeysWithValues: expectations.map { ($0.path, 1) })
        )

        for expectation in expectations {
            let source = try sourceFile(expectation.path)
            #expect(
                source.contains(expectation.surface),
                "\(expectation.path) draws the shared inline empty at the wrong surface tier"
            )
        }
    }

    @Test func theForkedInlineEmptySpellingsAreGone() throws {
        try expectNoLiveMention(of: "iOSInlineEmpty")
        try expectNoLiveMention(of: "CommitmentInlineEmpty")
        try expectNoLiveMention(of: "GoalInlineEmpty")
    }

    // MARK: - The scan itself

    /// The absence assertions below are only worth anything if the scan actually reads files, and a
    /// scan that silently returns nothing passes every one of them. This is the test that stops
    /// them going vacuous — the exact failure mode that let a `/tmp` against `/private/tmp` path
    /// mismatch look like four real regressions while the scan was reading nothing at all.
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/macOS/Views/KanbanColumnSupportViews.swift"))
        #expect(files.contains("Cadence/iOS/iOSDesignSystem.swift"))
        #expect(files.contains("Cadence/Shared/Components/CadenceBoardColumnHeader.swift"))
        #expect(files.contains("Cadence/Shared/Components/CadenceBoardMetadataChip.swift"))
        #expect(files.contains("Cadence/Shared/Components/CadenceInlineEmpty.swift"))
    }

    // MARK: - The method behind T-136

    /// The audit that found these: strip the platform prefix from every top-level type in
    /// `Cadence/iOS/` and intersect with `Cadence/macOS/`. Whatever else that set still contains,
    /// these three names must never re-enter it — a regression test on the *inventory*, not on any
    /// one component.
    @Test func theUnifiedComponentsAreNoLongerInThePrefixStrippedIntersection() throws {
        let iosTypes = try topLevelTypeNames(in: "Cadence/iOS")
        let macTypes = try topLevelTypeNames(in: "Cadence/macOS")

        let strippedIOSTypes = Set(iosTypes.compactMap(stripPlatformPrefix))
        let intersection = strippedIOSTypes.intersection(macTypes)

        for unified in ["BoardColumnHeader", "CalendarBoardMetadataChip", "InlineEmpty"] {
            #expect(!intersection.contains(unified), "\(unified) is forked across platforms again")
        }
    }
}

// MARK: - T-275: the eyebrow is spelled once

/// `SectionEyebrowLabel` exists to stop section eyebrows being re-typed, and twenty call sites on
/// both platforms were re-typing one anyway — six of them in files that used the shared label
/// correctly a few lines away. They had drifted exactly the way independently-typed values do:
/// six specified no kerning at all, three specified 0.6, 0.7 and 0.8, one drew the whole heading at
/// 11pt, one tinted `Theme.muted`, and two were `.bold` where the rest were `.semibold`.
///
/// **The load-bearing test here is the negative one, and that is deliberate.** A positive scan —
/// "this file mentions `SectionEyebrowLabel`" — has twice passed in this repo while the bug was
/// fully restored, because the string it looked for was still present somewhere unreachable. A
/// sweep of the whole `Cadence/` tree for the hand-rolled *shape* cannot be satisfied that way: the
/// fork has to be absent everywhere, not the shared spelling present somewhere.
@MainActor
struct CadenceSectionEyebrowConvergenceTests {

    /// The one file allowed to draw the shape, with the reason it is not an eyebrow.
    ///
    /// A calendar month column's `MON` sits above the day number as its *date* label, in
    /// `isToday ? Theme.blue : Theme.dim` and kerned 0.5 to sit under a 32pt circle. iOS draws the
    /// same header in `iOSCalendarTimelineViews` at `iOSCalendarTimelineMetrics.weekdaySize`. The
    /// two weekday headers have to agree with **each other**, which is a different question from
    /// whether either agrees with a section eyebrow, and answering it by pointing both at
    /// `SectionEyebrowLabel` would decide the first question by accident.
    private static let notAnEyebrow: Set<String> = [
        "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"
    ]

    /// **The T-161 test.** Re-fork any one of the twenty converted sites and this fails, because
    /// the shape reappears — no matter how many other files still name the shared label.
    @Test func noSurfaceHandRollsTheSharedEyebrow() throws {
        var scanned = 0
        var offenders: [String] = []

        for path in try swiftFiles(under: "Cadence") {
            scanned += 1
            guard !Self.notAnEyebrow.contains(path) else { continue }
            if handRolledEyebrowLines(in: strippingLineCommentsFast(try sourceFile(path))) > 0 {
                offenders.append(path)
            }
        }

        // Non-vacuity: a loop over nothing passes, and `swiftFiles` returning `[]` on a path
        // mistake is exactly how that happens.
        #expect(scanned > 250, "scanned only \(scanned) files under Cadence/")
        #expect(
            offenders.isEmpty,
            "hand-rolled section eyebrow(s) in: \(offenders.sorted().joined(separator: ", "))"
        )
    }

    /// The allowlist is not a place to retire the check to. If the weekday header ever stops
    /// drawing the shape, this fails and the entry goes — an allowlist nobody can prove is still
    /// needed is an allowlist that grows.
    @Test func theAllowlistedFileStillDrawsTheShapeItIsExcusedFor() throws {
        for path in Self.notAnEyebrow {
            let hits = handRolledEyebrowLines(in: strippingLineCommentsFast(try sourceFile(path)))
            #expect(hits > 0, "\(path) no longer draws the shape it is allowlisted for — delete the entry")
        }
    }

    /// The detector itself, against text that is not the repository. Without this the sweep above
    /// is one typo away from scanning for a pattern nothing can match and passing forever.
    @Test func theDetectorFindsTheShapeAndIgnoresItsNeighbours() {
        let handRolled = """
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
        """
        #expect(handRolledEyebrowLines(in: handRolled) == 1)

        // The shared spelling, which is what the twenty sites read now.
        #expect(handRolledEyebrowLines(in: "SectionEyebrowLabel(text: title)") == 0)

        // A 10pt semibold glyph that is neither uppercased nor an eyebrow tint — the commonest
        // shape in the app, and the one a looser detector would drown in.
        #expect(handRolledEyebrowLines(in: """
        Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.blue)
        """) == 0)

        // Uppercase and dim, but at the 9pt sub-label tier, which is a separate self-consistent
        // tier and out of scope.
        #expect(handRolledEyebrowLines(in: """
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.45)
        """) == 0)
    }

    /// The positive half, with exact counts, so a site that leaves the shared label for a *new*
    /// bespoke spelling the detector does not model still fails something.
    @Test func theConvertedSitesCallTheSharedLabel() throws {
        try expectCallSites(of: "SectionEyebrowLabel", at: [
            "Cadence/macOS/Sheets/CreateGoalSheet.swift": 1,
            "Cadence/macOS/Sheets/ListEditorSupportViews.swift": 1,
            "Cadence/macOS/Views/FocusChromeSupportViews.swift": 1,
            "Cadence/macOS/Views/FocusPickerSupportViews.swift": 1,
            "Cadence/macOS/Views/FocusSidebarSupportViews.swift": 1,
            "Cadence/macOS/Views/GlobalSearchOverlayShellViews.swift": 1,
            "Cadence/macOS/Views/GoalsSupportViews.swift": 1,
            "Cadence/macOS/Views/HabitsFormSupportViews.swift": 1,
            "Cadence/macOS/Views/ListDetailSupportViews.swift": 1,
            "Cadence/macOS/Views/ListNotesViewSupportViews.swift": 1,
            "Cadence/macOS/Views/NoteReferenceSupportViews.swift": 1,
            "Cadence/macOS/Views/SchedulePanelShellViews.swift": 1,
            "Cadence/macOS/Views/SettingsTemplatesSection.swift": 1,
            "Cadence/macOS/Views/TaskBundlePickerSupportViews.swift": 1,
            "Cadence/Shared/CadenceSettingsSharedViews.swift": 1,
            "Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift": 1,
            "Cadence/Shared/Components/CommitmentSharedViews.swift": 1,
            "Cadence/Shared/Components/HabitProgressViews.swift": 1,
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/iOS/iPadTodayScheduleViews.swift": 1
        ])
    }

    /// The one measurement the conversion changed rather than preserved: the overdue summary
    /// heading drew label *and* count at 11pt, the app's only eyebrow at that size. Both are 10
    /// now, and the count reads the shared constant rather than a second literal — the rule the
    /// board column header and the task group heading already state.
    @Test func theCountBesideAnEyebrowIsTheEyebrowsOwnSize() throws {
        #expect(SectionEyebrowLabel.fontSize == 10)
        #expect(CadenceTaskGroupHeadingMetrics.countSize == SectionEyebrowLabel.fontSize)
        #expect(CadenceBoardColumnHeaderMetrics.countSize == SectionEyebrowLabel.fontSize)

        let card = try strippingComments(sourceFile("Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift"))
        #expect(card.contains("struct CadenceTodayOverdueSummaryHeading"), "non-vacuity: still the heading's file")
        #expect(card.contains("size: SectionEyebrowLabel.fontSize"))
        // The file keeps a plain 11pt body line; what may not come back is an 11pt *eyebrow*.
        #expect(!card.contains("size: 11, weight: .semibold"), "the 11pt eyebrow tier is back")
    }
}

/// Counts the hand-rolled eyebrow: a 10 or 11pt semibold/bold `Text` that is uppercased or kerned
/// 0.8, in one of the two eyebrow tints, within six lines of the font it is drawn in.
///
/// Six lines is the whole modifier run at every one of the twenty sites this replaced and is far
/// short of a view body, which is what keeps it from reporting an unrelated uppercase `Text` that
/// happens to sit near a semibold glyph. Measured against the tree at the time of writing: 26 hits
/// before the conversion, 1 after, no false positives in either direction.
///
/// **Literal `contains`, not a regular expression.** Four exact strings cover the whole eyebrow
/// tier, and a sweep of all 509 files under `Cadence/` runs one substring check per line instead
/// of compiling and running a pattern. Same reason `strippingLineCommentsFast` exists below: the
/// other tests in this file read a handful of named paths, and a helper that is fine at that size
/// is the wrong shape for a whole-tree sweep.
private func handRolledEyebrowLines(in source: String) -> Int {
    let fonts = [
        ".font(.system(size: 10, weight: .semibold))",
        ".font(.system(size: 10, weight: .bold))",
        ".font(.system(size: 11, weight: .semibold))",
        ".font(.system(size: 11, weight: .bold))"
    ]
    let lines = source.components(separatedBy: "\n")
    var count = 0

    for (index, line) in lines.enumerated() {
        guard fonts.contains(where: line.contains) else { continue }
        let window = lines[max(0, index - 6)...min(lines.count - 1, index + 6)].joined(separator: "\n")
        let uppercased = window.contains(".textCase(.uppercase)") || window.contains(".uppercased()")
        let kerned = window.contains(".kerning(0.8)")
        let eyebrowTint = window.contains("Theme.dim") || window.contains("Theme.muted")
        if (uppercased || kerned) && eyebrowTint { count += 1 }
    }
    return count
}

/// `strippingComments` for a whole-tree sweep: it blanks comments by repeatedly rewriting the
/// string, which is fine for the handful of files the other tests read and quadratic across 509.
///
/// Truncating each line at its first `//` is the same guarantee in the direction that matters —
/// every `///` doc comment quoting the shape it replaced disappears — and a `//` inside a string
/// literal only ever makes the sweep blind to *more* text, never to less. Block comments are left
/// alone: this repo writes doc comments with `///`, and a `/* */` would have to contain a literal
/// SwiftUI font modifier to matter.
private func strippingLineCommentsFast(_ source: String) -> String {
    source
        .components(separatedBy: "\n")
        .map { line -> Substring in
            guard let marker = line.range(of: "//") else { return line[...] }
            return line[line.startIndex..<marker.lowerBound]
        }
        .joined(separator: "\n")
}

// MARK: - Source-reading helpers

/// Fails unless `name` is called exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** The first version of these tests asserted only that each file
/// still mentioned the shared component somewhere, and a mutation run caught it: reverting *one* of
/// four metadata-chip call sites to a locally-declared copy left the test green, because the other
/// three still matched. That is T-161 reproduced inside the test written to prevent T-161. A count
/// that has to be edited on purpose is the point — a legitimate new board column should be a line
/// in this table, and a call site quietly leaving the shared component cannot be.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails if `name` appears anywhere in `Cadence/` as live code rather than inside a comment.
///
/// Comments are exempt deliberately — the tombstones left where each fork used to be declared say
/// what was there and why, and a test that forbade the *words* would force the next agent to delete
/// the explanation along with the code. Stripping comments rather than allowlisting whole files is
/// what makes that exemption exact: an earlier draft allowlisted the two files holding tombstones,
/// and a mutation that re-declared `CalendarBoardMetadataChip` in one of them passed unnoticed.
private func expectNoLiveMention(
    of name: String,
    excludingPrefixes prefixes: [String] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let negativeLookbehind = prefixes.isEmpty ? "" : "(?<!" + prefixes.joined(separator: ")(?<!") + ")"
    let pattern = "(?<![A-Za-z0-9_])\(negativeLookbehind)\(name)(?![A-Za-z0-9_])"

    for path in try swiftFiles(under: "Cadence") {
        let code = try strippingComments(sourceFile(path))
        #expect(
            code.range(of: pattern, options: .regularExpression) == nil,
            "\(path) still refers to the retired type \(name)",
            sourceLocation: sourceLocation
        )
    }
}

private func expectNoDeclaration(
    of name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for path in try swiftFiles(under: "Cadence") {
        let code = try strippingComments(sourceFile(path))
        #expect(
            code.range(of: "(struct|class|enum|typealias)\\s+\(name)\\b", options: .regularExpression) == nil,
            "\(path) declares \(name) again",
            sourceLocation: sourceLocation
        )
    }
}

private func topLevelTypeNames(in directory: String) throws -> Set<String> {
    var names: Set<String> = []
    let pattern = "^(?:public |private |internal |fileprivate |final |nonisolated )*(?:struct|class|enum|actor|protocol)\\s+([A-Za-z_][A-Za-z0-9_]*)"

    for path in try swiftFiles(under: directory) {
        for line in try sourceFile(path).split(separator: "\n", omittingEmptySubsequences: false) {
            guard let first = line.first, first != " ", first != "\t" else { continue }
            guard let range = line.range(of: pattern, options: .regularExpression) else { continue }
            let declaration = line[range]
            if let name = declaration.split(separator: " ").last {
                names.insert(String(name))
            }
        }
    }
    return names
}

private func stripPlatformPrefix(_ name: String) -> String? {
    for prefix in ["iOSCompact", "iOSRegular", "iPadMacStyle", "iOS", "iPad", "iPhone"] where name.hasPrefix(prefix) && name.count > prefix.count {
        return String(name.dropFirst(prefix.count))
    }
    return nil
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields *absolute* paths, and `#filePath` can name the repo through a symlinked prefix
/// (`/tmp` against `/private/tmp` on an isolated build tree) that `FileManager` resolves and the
/// literal does not. Deriving relative paths by trimming an absolute prefix silently produced
/// absolute ones there, which broke the allowlist and every subsequent read. The path variant
/// hands back relative paths and cannot drift.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose. Crude on purpose: a `//` inside a string literal is blanked too, which can
/// only ever make these checks *stricter* about what counts as a comment, never looser about live
/// code.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
