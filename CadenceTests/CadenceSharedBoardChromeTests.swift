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
    @Test func theSourceScanActuallyReachesBothPlatformsSourceInSharedBoardChrome() throws {
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

    // MARK: - T-331: the column due date both boards now show

    /// The hide flag is the whole reason a column with no date can still draw a line. macOS read it
    /// from the list; iOS drew no line at all, so the flag had nothing to govern there.
    @Test func anEmptyColumnDueDateIsDrawnOnlyWhenTheListDidNotAskToHideIt() {
        let hidden = CadenceBoardColumnDueDatePlan.plan(dueDate: "", hideWhenEmpty: true, isCompleted: false)
        #expect(hidden.isVisible == false)

        let shown = CadenceBoardColumnDueDatePlan.plan(dueDate: "", hideWhenEmpty: false, isCompleted: false)
        #expect(shown.isVisible)
        #expect(shown.hasDueDate == false)
        #expect(shown.label == "No due date")
        #expect(shown.isOverdue == false)
    }

    /// A column that *has* a date shows it whichever way the flag is set — the flag hides empties,
    /// not dates. This is the case T-331 is actually about: set on iPhone, stored, never drawn.
    @Test func aColumnWithADueDateShowsItWhicheverWayTheHideFlagIsSet() throws {
        let reference = try #require(DateFormatters.date(from: "2026-08-26"))
        let expected = DateFormatters.relativeDate(from: "2026-09-02", relativeTo: reference)

        for hideWhenEmpty in [true, false] {
            let plan = CadenceBoardColumnDueDatePlan.plan(
                dueDate: "2026-09-02",
                hideWhenEmpty: hideWhenEmpty,
                isCompleted: false,
                relativeTo: reference
            )
            #expect(plan.isVisible, "a dated column vanished at hideWhenEmpty: \(hideWhenEmpty)")
            #expect(plan.hasDueDate)
            #expect(plan.label == expected)
            #expect(plan.label != "No due date")
        }
    }

    /// `sectionDueDateIsOverdue` used to be a private var on the macOS column and nothing else.
    /// Three cases, because the middle one is the one a re-derivation loses: a column that wound
    /// down is not late, whatever date it holds.
    @Test func aColumnIsLateOnlyWhenItsDatePassedAndItHasNotWoundDown() throws {
        let reference = try #require(DateFormatters.date(from: "2026-08-26"))

        func plan(_ dueDate: String, isCompleted: Bool) -> CadenceBoardColumnDueDatePlan {
            CadenceBoardColumnDueDatePlan.plan(
                dueDate: dueDate,
                hideWhenEmpty: false,
                isCompleted: isCompleted,
                relativeTo: reference
            )
        }

        #expect(plan("2026-08-25", isCompleted: false).isOverdue)
        #expect(plan("2026-08-25", isCompleted: true).isOverdue == false)
        // Today is not late, and neither is tomorrow.
        #expect(plan("2026-08-26", isCompleted: false).isOverdue == false)
        #expect(plan("2026-08-27", isCompleted: false).isOverdue == false)
        #expect(plan("", isCompleted: false).isOverdue == false)
    }

    /// **The T-161 test for T-331.** Both list boards must reach the same rule and the same line.
    /// Pinning `plan(...)` above proves the rule is right and proves nothing about iOS asking it —
    /// which is exactly the state the ticket describes, a correct shared component that one
    /// platform handed less metadata.
    @Test func bothListBoardsAskTheSharedRuleAndDrawTheSharedLine() throws {
        try expectCallSites(
            of: "CadenceBoardColumnDueDatePlan.plan",
            at: [
                "Cadence/macOS/Views/KanbanColumnSupportViews.swift": 1,
                "Cadence/iOS/iOSListSupportViews.swift": 1
            ]
        )
        try expectCallSites(
            of: "CadenceBoardColumnDueDateLine",
            at: [
                "Cadence/macOS/Views/KanbanColumnSupportViews.swift": 1,
                "Cadence/iOS/iOSListSupportViews.swift": 1
            ]
        )

        // Neither board may re-spell the empty label or the overdue comparison it used to own.
        for path in [
            "Cadence/macOS/Views/KanbanColumnSupportViews.swift",
            "Cadence/macOS/Views/KanbanSectionColumnView.swift",
            "Cadence/iOS/iOSListSupportViews.swift"
        ] {
            let raw = try sourceFile(path)
            let code = try strippingComments(raw)
            #expect(code != raw, "\(path) has no comments at all, so the stripper read the wrong file")
            #expect(code.count == raw.count, "the comment stripper changed \(path)'s length")
            #expect(code.contains("ColumnHeader"), "\(path) is not a board column file")
            #expect(!code.contains("\"No due date\""), "\(path) spells the empty label itself again")
            #expect(!code.contains("DateFormatters.todayKey()"), "\(path) re-derives overdue itself")
        }
    }

    /// The flag reaches the iOS board, and iOS can now set it. Wiring the board without the toggle
    /// would have left iPhone users reading a setting only a Mac could change; wiring the toggle
    /// without the board would have left it governing nothing.
    @Test func iOSBothSuppliesTheColumnHideFlagToItsBoardAndOffersAToggleForIt() throws {
        let detail = try strippingComments(sourceFile("Cadence/iOS/iOSListDetailView.swift"))
        #expect(detail.contains("iOSListKanbanPanel("), "the iOS list detail no longer draws the board")
        #expect(
            detail.range(of: "hideSectionDueDateIfEmpty:\\s*hideSectionDueDateIfEmpty", options: .regularExpression) != nil,
            "the iOS board is not handed the list's hideSectionDueDateIfEmpty"
        )

        let editor = try strippingComments(sourceFile("Cadence/iOS/iOSListEditorViews.swift"))
        #expect(editor.contains("Hide empty column due dates"), "the iOS list editor offers no column-due-date toggle")
        for model in ["area", "project"] {
            #expect(
                editor.range(of: "\(model)\\.hideSectionDueDateIfEmpty\\s*=", options: .regularExpression) != nil,
                "the iOS list editor never writes \(model).hideSectionDueDateIfEmpty"
            )
        }

        // Self-check for the regex shape used twice above: it must match a real assignment and must
        // not match the read that loads the toggle back out of the model.
        #expect("area.hideSectionDueDateIfEmpty = flag".range(of: "area\\.hideSectionDueDateIfEmpty\\s*=", options: .regularExpression) != nil)
        #expect("flag = area.hideSectionDueDateIfEmpty".range(of: "area\\.hideSectionDueDateIfEmpty\\s*=", options: .regularExpression) == nil)
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

    /// **The allowlist is empty, and that is the T-277 outcome rather than a retirement.**
    ///
    /// It held one entry: `CalendarPageMonthSupportViews`, whose `MON` sits above a day number as
    /// that column's *date* label — not a section eyebrow, so pointing it at `SectionEyebrowLabel`
    /// would have settled "do the two weekday headers agree with each other" by accident. T-277
    /// settled that question directly: both headers read `CadenceCalendarWeekdayHeaderMetrics` now,
    /// so the file no longer spells a literal font size and the entry's own escape clause fired —
    /// "if the weekday header ever stops drawing the shape, the entry goes". It went, along with the
    /// test that guarded it. The sweep below now reads every file under `Cadence/` with no
    /// exemptions at all. `CadenceCalendarWeekdayHeaderConvergenceTests` is where that header is
    /// pinned instead.
    private static let notAnEyebrow: Set<String> = []

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

    /// The allowlist was never a place to retire the check to, so the check that it stayed earned
    /// outlived it: an entry had to keep drawing the shape it was excused for. Now that the set is
    /// empty, what has to stay true is that it *stays* empty — an exemption is how a sweep like this
    /// quietly stops covering the surface it was written for.
    @Test func theEyebrowSweepHasNoExemptionsLeft() {
        #expect(Self.notAnEyebrow.isEmpty)
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

        // Uppercase and dim, but at the 9pt sub-label tier. This detector still does not model it,
        // and that is the division of labour rather than an omission: T-284 gave the sub-label its
        // own detector below, because folding 9pt into this one would have made "is there a second
        // tier" and "is the second tier consistent" the same question. What was NOT true when this
        // case was written is the comment that used to sit here calling the 9pt tier
        // "self-consistent" — it had four kernings, and 0.45 was one of them.
        #expect(handRolledEyebrowLines(in: """
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.45)
        """) == 0)
        // The sub-label detector is the one that sees it.
        #expect(handRolledCompactEyebrowLines(in: """
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.45)
        """) == 1)
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
            // Zero since T-286, and still a count rather than a deletion. This pane drew an
            // eyebrow because it declared `TemplateEditorField`, a private copy of
            // `CadenceSettingsField`; the eyebrow moved *into* the shared component along with the
            // well. Its three fields are pinned as `CadenceSettingsField` call sites by
            // `SettingsSevenPaneVocabularyTests.theSevenPanesReadTheSharedFieldVocabulary`, so a
            // pane that stops drawing labelled fields altogether still fails something.
            "Cadence/macOS/Views/SettingsTemplatesSection.swift": 0,
            "Cadence/macOS/Views/TaskBundlePickerSupportViews.swift": 1,
            "Cadence/Shared/CadenceSettingsSharedViews.swift": 1,
            "Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift": 1,
            "Cadence/macOS/Views/CommitmentSharedViews.swift": 1,
            "Cadence/Shared/Components/HabitProgressViews.swift": 1,
            "Cadence/iOS/iOSFeatureDetailViews.swift": 1,
            "Cadence/iOS/iOSTodaySchedulePanel.swift": 1
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

/// **T-277: the two calendar weekday headers.**
///
/// `MON` over a day column was a literal `10` semibold kerned `0.5` on macOS and a named
/// `iOSCalendarTimelineMetrics.weekdaySize` of `11` with no kerning on iOS — one literal against one
/// constant, which is a fork that no grep for a shared token can find, and it is why this one
/// survived the T-275 sweep as that sweep's single allowlist entry.
///
/// The figures are asserted as **values** first and scanned for as source second. The value half is
/// what catches the iOS side re-forking `iOSCalendarTimelineMetrics`, which is a `Cadence/iOS/`
/// file this macOS-built target cannot otherwise see the inside of: those members are computed
/// forwards, so reading them here reads what the phone draws.
@MainActor
struct CadenceCalendarWeekdayHeaderConvergenceTests {

    /// 10, and it is not a number of the calendar's own: it is the size of every uppercased
    /// semibold label in the app. `CadenceBoardColumnHeaderMetrics` settled this exact 10-against-11
    /// argument against an iOS 11 already, which is the second time the phone's calendar chrome has
    /// been the outlier.
    @Test func theWeekdayLabelIsTheAppsOneLabelSize() {
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelSize == 10)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelSize == SectionEyebrowLabel.fontSize)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelSize == CadenceBoardColumnHeaderMetrics.labelSize)
    }

    /// The kerning iOS was missing. Asserted as a positive number *and* as the exact figure: a
    /// mutation putting the iOS side back to no kerning at all is the regression this exists for,
    /// and `> 0` is the half that names it.
    @Test func theUppercasedWeekdayIsKerned() {
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelKerning == 0.5)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelKerning > 0)
    }

    /// The day number and its today-circle were the half the two platforms *already* agreed on,
    /// 18-in-32 both. Stating them once is what keeps that true; this is the assertion that fails
    /// if either side goes back to a literal.
    @Test func theDayNumberAndCircleAreStatedOnce() {
        #expect(CadenceCalendarWeekdayHeaderMetrics.dayNumberSize == 18)
        #expect(CadenceCalendarWeekdayHeaderMetrics.dayCircleSize == 32)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelSpacing == 2)
    }

    /// The iOS band reads the shared figures rather than keeping its own copy of them.
    ///
    /// `iOSCalendarTimelineMetrics` is inside `#if os(iOS)`-adjacent source this target cannot
    /// render, but the enum itself is `nonisolated` and unguarded, so its members are readable here
    /// — and they are computed forwards now, so an inequality below means the phone's day header has
    /// re-forked.
    @Test func theIOSDayHeaderReadsTheSharedBand() {
        #expect(iOSCalendarTimelineMetrics.weekdaySize == CadenceCalendarWeekdayHeaderMetrics.labelSize)
        #expect(iOSCalendarTimelineMetrics.dayLabelSpacing == CadenceCalendarWeekdayHeaderMetrics.labelSpacing)
        #expect(iOSCalendarTimelineMetrics.dayNumberSize == CadenceCalendarWeekdayHeaderMetrics.dayNumberSize)
        #expect(iOSCalendarTimelineMetrics.dayCircleSize == CadenceCalendarWeekdayHeaderMetrics.dayCircleSize)
    }

    /// The derived band still clears what sits in it after the label shrank — the arithmetic
    /// `iOSCalendarMetricsTests` pins, restated against the shared numbers because they are what
    /// feeds it now. Taking the label to 10 and the gap to 2 hands the chip strip 2.2pt back.
    @Test func theSharedBandStillFitsTheIOSDayHeader() {
        #expect(
            iOSCalendarTimelineMetrics.dateBlockHeight
                >= CadenceCalendarWeekdayHeaderMetrics.labelSize * 1.2
                    + CadenceCalendarWeekdayHeaderMetrics.labelSpacing
                    + CadenceCalendarWeekdayHeaderMetrics.dayCircleSize
        )
    }

    /// The whole app draws exactly **two** uppercased weekday labels, and neither may set its own
    /// size beside one.
    ///
    /// The count is the load-bearing half. A third hand-rolled day header would satisfy any
    /// "the two existing ones are fine" assertion, which is the failure mode the eyebrow sweep in
    /// this file was written for; a new one has to be a line in the table below.
    ///
    /// The third entry is not a day header. `CadenceWidgetDateSupport.weekdayLabel` is a string
    /// helper — the widget target draws its result, over in `CadenceWidgets/`, which this walk does
    /// not reach — and it reads `DateFormatters.dayOfWeek` for the reason this file cares about in
    /// the first place: it used to spell the day with `date.formatted(...)` and followed the host
    /// locale (T-301). It has no font to set, which is why the offender check below still passes
    /// over it unchanged.
    @Test func theOnlyTwoWeekdayLabelsInTheAppReadTheSharedMetric() throws {
        var found: [String] = []
        var offenders: [String] = []
        var scanned = 0

        for path in try swiftFiles(under: "Cadence") {
            scanned += 1
            let lines = strippingLineCommentsFast(try sourceFile(path)).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                guard line.contains("DateFormatters.dayOfWeek"), line.contains(".uppercased()") else { continue }
                found.append(path)
                let window = lines[max(0, index - 6)...min(lines.count - 1, index + 6)].joined(separator: "\n")
                if window.range(of: "\\.font\\(\\.system\\(size: [0-9]", options: .regularExpression) != nil {
                    offenders.append(path)
                }
            }
        }

        #expect(scanned > 250, "scanned only \(scanned) files under Cadence/")
        #expect(found.sorted() == [
            "Cadence/Services/CadenceTodayWidgetSupport.swift",
            "Cadence/iOS/iOSCalendarTimelineViews.swift",
            "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"
        ])
        #expect(
            offenders.isEmpty,
            "weekday header(s) setting their own font size: \(offenders.sorted().joined(separator: ", "))"
        )
    }

    /// The positive half, with exact reference counts, so a site that drops *one* of the five
    /// figures back to a literal fails rather than riding on the four it kept.
    @Test func theWeekdayHeaderSitesNameTheSharedMetric() throws {
        let expected = [
            "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift": 6,
            "Cadence/iOS/iOSCalendarTimelineViews.swift": 1,
            "Cadence/iOS/iOSCalendarMetrics.swift": 4,
            "Cadence/iOS/iOSCalendarMonthViews.swift": 1
        ]

        for (path, count) in expected {
            let code = try strippingComments(sourceFile(path))
            let actual = code.components(separatedBy: "CadenceCalendarWeekdayHeaderMetrics.").count - 1
            #expect(actual == count, "\(path) names the shared metric \(actual) times, expected \(count)")
        }
    }

    /// The month grids' weekday row took a `weekdaySymbolSize` parameter that this grid's two
    /// callers disagreed about — 10 for the agenda, 11 for the full month — so one view drew the
    /// same row at two sizes, and the timed grid's day header named "the month grid" as the reason
    /// for *its* 11. The parameter is gone rather than merely unified: a knob with one caller is how
    /// the disagreement gets rebuilt.
    @Test func theMonthGridsWeekdayRowHasNoSizeKnobLeft() throws {
        for path in try swiftFiles(under: "Cadence") {
            let code = try strippingComments(sourceFile(path))
            #expect(!code.contains("weekdaySymbolSize"), "\(path) still carries a weekday size knob")
        }
    }
}

// MARK: - Source-reading helpers

// MARK: - T-284: the sub-label tier is a tier, not four kernings

/// **The 9pt eyebrow.** `SectionEyebrowLabel` is the app's one uppercase eyebrow and macOS reads it
/// in 19 files. Beside it sat six hand-rolled 9pt spellings of the same idea — a popover group
/// heading, an inspector well label — at kernings of 0.45, 0.54, 0.6, 0.7 and, at two sites, none
/// at all, plus a seventh in a *shared* component (`EstimatePickerControl`) and an eighth on iOS.
///
/// **The size stayed; the kerning converged.** A previous audit looked at this tier and left it
/// alone on the grounds that folding 9pt into 10pt would be a size decision dressed as a refactor.
/// That reading was right about the size and wrong about the kerning: nine points is a legitimate
/// second tier, four kernings is drift. So the shared label gained a `Size`, every site above reads
/// it, and letterspacing is derived from the size by one ratio rather than chosen per site.
/// Nothing changed tier — the 9pt labels are still 9pt and the 10pt ones still 10pt.
@MainActor
struct CadenceCompactEyebrowConvergenceTests {

    /// The value half. Both tiers still draw at the size they always drew at, and the compact one
    /// is genuinely smaller — a "consolidation" that quietly promoted the sub-labels to 10pt would
    /// satisfy every source scan below and is the outcome this ticket was told not to produce.
    @Test func theTwoTiersKeepTheirSizesAndDeriveOneKerning() {
        #expect(SectionEyebrowLabel.Size.standard.fontSize == 10)
        #expect(SectionEyebrowLabel.Size.compact.fontSize == 9)
        #expect(SectionEyebrowLabel.fontSize == SectionEyebrowLabel.Size.standard.fontSize)
        #expect(SectionEyebrowLabel.compactFontSize == SectionEyebrowLabel.Size.compact.fontSize)
        #expect(SectionEyebrowLabel.Size.compact.fontSize < SectionEyebrowLabel.Size.standard.fontSize)

        // 0.08em. The standard tier's long-standing 0.8 at 10pt, reproduced exactly, so this
        // conversion did not move the 19 files that were already correct.
        #expect(SectionEyebrowLabel.kerningRatio == 0.08)
        #expect(abs(SectionEyebrowLabel.Size.standard.kerning - 0.8) < 0.0001)
        #expect(abs(SectionEyebrowLabel.Size.compact.kerning - 0.72) < 0.0001)
        #expect(SectionEyebrowLabel.Size.compact.kerning < SectionEyebrowLabel.Size.standard.kerning)
    }

    /// None of the four kernings the sub-label tier had accumulated is what it draws at now. Stated
    /// as a set rather than as one comparison because the failure being guarded is a site being
    /// *reverted*, and any of the four is a revert.
    @Test func noneOfTheFourStrayKerningsSurvives() {
        let retired: [CGFloat] = [0.45, 0.54, 0.6, 0.7]
        let live = SectionEyebrowLabel.Size.compact.kerning
        #expect(!retired.contains { abs($0 - live) < 0.0001 })
    }

    /// `SidebarMetrics` re-typed the eyebrow's own two numbers as literals, and
    /// `SettingsViewSupport`'s group header chains off that pair — so the settings rail and the
    /// sidebar would both have kept drawing 10/0.8 through any change to the eyebrow. The equality
    /// is what a size change to `SectionEyebrowLabel` now has to carry with it.
    @Test func theSidebarContextHeaderIsTheEyebrow() throws {
        #expect(SidebarMetrics.contextHeaderFontSize == SectionEyebrowLabel.Size.standard.fontSize)
        #expect(abs(SidebarMetrics.contextHeaderKerning - SectionEyebrowLabel.Size.standard.kerning) < 0.0001)
        #expect(SettingsRailMetrics.groupHeaderFontSize == SectionEyebrowLabel.Size.standard.fontSize)
        #expect(abs(SettingsRailMetrics.groupHeaderKerning - SectionEyebrowLabel.Size.standard.kerning) < 0.0001)

        // The equality above holds just as well for two hand-typed 10s, which is how the pair got
        // here. What may not come back is the literal.
        let sidebar = try strippingComments(sourceFile("Cadence/macOS/Views/SidebarViewSupport.swift"))
        #expect(sidebar.contains("enum SidebarMetrics"), "non-vacuity: still the metrics' file")
        #expect(sidebar.contains("contextHeaderFontSize: CGFloat = SectionEyebrowLabel"))
        #expect(sidebar.contains("contextHeaderKerning: CGFloat = SectionEyebrowLabel"))
    }

    /// **The load-bearing negative.** Same shape as `noSurfaceHandRollsTheSharedEyebrow` above and
    /// the colour sweep in `CadenceAccentStorageSweepTests`: the fork has to be absent from every
    /// file under `Cadence/`, which no amount of the shared spelling elsewhere can satisfy. No
    /// allowlist — measured at six hits before this conversion and none after, with no false
    /// positive in either direction.
    @Test func noSurfaceHandRollsTheCompactEyebrow() throws {
        var scanned = 0
        var offenders: [String] = []

        for path in try swiftFiles(under: "Cadence") {
            scanned += 1
            if handRolledCompactEyebrowLines(in: strippingLineCommentsFast(try sourceFile(path))) > 0 {
                offenders.append(path)
            }
        }

        #expect(scanned > 250, "scanned only \(scanned) files under Cadence/")
        #expect(
            offenders.isEmpty,
            "hand-rolled 9pt sub-label eyebrow(s) in: \(offenders.sorted().joined(separator: ", "))"
        )
    }

    /// The detector against text that is not the repository, so the sweep above cannot be one typo
    /// away from scanning for a pattern nothing matches.
    @Test func theCompactDetectorFindsTheShapeAndIgnoresItsNeighbours() {
        #expect(handRolledCompactEyebrowLines(in: """
        Text(group.source.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.6)
        """) == 1)

        // Tinted by the context's own colour rather than `Theme.dim` — two of the six were, and a
        // detector keyed only on the neutral tints would have missed them.
        #expect(handRolledCompactEyebrowLines(in: """
        Text(group.context.name.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(hex: group.context.colorHex))
        """) == 1)

        // The shared spelling.
        #expect(handRolledCompactEyebrowLines(in: "SectionEyebrowLabel(text: title, size: .compact)") == 0)

        // A 9pt semibold chevron beside an uppercase title — the commonest 9pt shape in the app and
        // the one a looser detector would drown in. It is a glyph, not a `Text`.
        #expect(handRolledCompactEyebrowLines(in: """
        Text(title.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.text)
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color.opacity(0.55))
        """) == 0)

        // The 10pt tier, which is the *other* detector's job.
        #expect(handRolledCompactEyebrowLines(in: """
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
        """) == 0)
    }

    /// The positive half, with exact counts, so a converted site that leaves for a *new* bespoke
    /// spelling the detector does not model still fails something. `TaskInspectorFieldSupportViews`
    /// is in the list at 1 because its group label reads the shared view while the count drawn
    /// beside it reads `SectionEyebrowLabel.Size.compact.font` — one call, one derived font, no
    /// second kerning constant.
    @Test func theConvertedCompactSitesCallTheSharedLabel() throws {
        try expectCallSites(of: "SectionEyebrowLabel", at: [
            "Cadence/macOS/CadenceCalendarPicker.swift": 1,
            "Cadence/macOS/Views/AIActionsSupportViews.swift": 1,
            "Cadence/macOS/Views/ContainerPickerSupportViews.swift": 1,
            "Cadence/macOS/Views/GoalAttachWorkSheet.swift": 1,
            "Cadence/macOS/Views/TaskInspectorFieldSupportViews.swift": 1,
            "Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift": 1,
            "Cadence/Shared/Components/EstimatePickerControl.swift": 1,
            "Cadence/iOS/iOSChoicePicker.swift": 1
        ])

        // The inspector's own kerning constant is gone rather than left unread — a metric that
        // still compiles and is drawn by nothing is how `subtitle` survived three deletions.
        try expectNoLiveMention(of: "groupLabelKerning")
    }

    /// **The derivation, not just the two numbers it lands on (T-452).** `SectionEyebrowLabel`'s
    /// own prose has cited a test by this name since T-284 — and no test by this name existed
    /// anywhere in the target until now, so the property it was cited for was unguarded while
    /// reading as guarded. That is the worse of the two failures: a named test nobody can find is
    /// how `theTwoTiersKeepTheirSizesAndDeriveOneKerning` came to look like more coverage than it is.
    ///
    /// Every value assertion in this suite is satisfied by a per-case literal
    /// (`case .standard: 0.8` / `case .compact: 0.72`), which puts the two tiers back on two
    /// independently editable numbers and leaves `kerningRatio` dead — the whole defect T-284
    /// closed. So the source has to *read* the ratio, not merely agree with it.
    @Test func theCompactKerningIsDerivedRatherThanASecondLiteral() throws {
        let path = "Cadence/Shared/Components/SectionEyebrowLabel.swift"
        let code = try strippingComments(sourceFile(path))
        #expect(code.contains("enum Size"), "non-vacuity: still the eyebrow's file")

        // The call site reads the shared token. Whitespace-insensitive, and indifferent to the
        // `nonisolated` in front of it, so a reformat is not a failure but a rewrite is.
        let dense = code.filter { !$0.isWhitespace }
        #expect(
            dense.contains("varkerning:CGFloat{fontSize*SectionEyebrowLabel.kerningRatio}"),
            "the tier's kerning no longer derives from kerningRatio"
        )

        // And neither tier's kerning is written down. `0.08` does not contain either string, so
        // the ratio itself is not what these catch.
        #expect(!dense.contains("0.8"), "the standard tier's kerning is a literal again")
        #expect(!dense.contains("0.72"), "the compact tier's kerning is a literal again")

        // The arithmetic identity, independent of spelling: one ratio, both tiers.
        #expect(
            SectionEyebrowLabel.Size.standard.kerning
                == SectionEyebrowLabel.Size.standard.fontSize * SectionEyebrowLabel.kerningRatio
        )
        #expect(
            SectionEyebrowLabel.Size.compact.kerning
                == SectionEyebrowLabel.Size.compact.fontSize * SectionEyebrowLabel.kerningRatio
        )
    }

    /// **The eyebrow's prose names types that exist (T-477).** `Size` justified its `nonisolated`
    /// members by "`CadenceEyebrowMetrics`' readers" and no such type has ever been in this repo —
    /// T-284's own conversion renamed the prose out from under itself. A stale *rationale* is worse
    /// than none: the next reader keeps or deletes the annotation on the strength of a type they
    /// cannot find, which is how the annotation survived unexamined until somebody grepped the name.
    ///
    /// Deliberately narrow — this one file, and only backticked `…Metrics` identifiers. That is the
    /// naming shape the eyebrow's neighbours use (`CadenceTaskGroupHeadingMetrics`,
    /// `CadenceBoardColumnHeaderMetrics`, `SidebarMetrics`, `TaskInspectorFieldRowMetrics`), and a
    /// checker for every capitalised word in every doc comment in the app is a different, much
    /// noisier ticket. Live *code* is the corpus, so a name that survives only in this file's own
    /// prose does not vouch for itself.
    @Test func theEyebrowDocOnlyNamesMetricsTypesThatExist() throws {
        let eyebrowPath = "Cadence/Shared/Components/SectionEyebrowLabel.swift"
        let named = backtickedMetricsNames(inProseOf: try sourceFile(eyebrowPath))

        #expect(named.count >= 3, "non-vacuity: read \(named.count) backticked metrics names out of the eyebrow's prose")
        #expect(
            named.contains("CadenceTaskGroupHeadingMetrics"),
            "non-vacuity: the extractor missed a name this file demonstrably carries"
        )

        var live: Set<String> = []
        var scanned = 0
        for path in try swiftFiles(under: "Cadence") {
            scanned += 1
            let code = try strippingComments(sourceFile(path))
            for name in named where code.contains(name) { live.insert(name) }
        }

        #expect(scanned > 250, "scanned only \(scanned) files under Cadence/")
        let ghosts = named.subtracting(live).sorted()
        #expect(
            ghosts.isEmpty,
            "the eyebrow's prose names type(s) no live source declares: \(ghosts.joined(separator: ", "))"
        )
    }

    /// The extractor against text that is not the repository, so the check above cannot pass by
    /// reading nothing. It must see a backticked name, follow it through a member access, and stay
    /// out of live code and out of non-metrics symbols.
    @Test func theMetricsNameExtractorReadsProseAndNotCode() {
        #expect(backtickedMetricsNames(inProseOf: "/// see `CadenceTaskGroupHeadingMetrics`")
            == ["CadenceTaskGroupHeadingMetrics"])
        #expect(backtickedMetricsNames(inProseOf: "/// see `SidebarMetrics.contextHeaderKerning`")
            == ["SidebarMetrics"])
        // A possessive, which is how the stale name was spelled.
        #expect(backtickedMetricsNames(inProseOf: "/// `CadenceEyebrowMetrics`' readers")
            == ["CadenceEyebrowMetrics"])
        // Not a metrics type, and not prose.
        #expect(backtickedMetricsNames(inProseOf: "/// the shared `SectionEyebrowLabel`").isEmpty)
        #expect(backtickedMetricsNames(inProseOf: "let x = SidebarMetrics.contextHeaderKerning").isEmpty)
    }
}

/// Backticked `…Metrics` identifiers appearing in **comments only**, with any `.member` suffix
/// dropped. Comment-only because the point is to check prose against code: a name that appears in
/// live source is not the failure being hunted.
private func backtickedMetricsNames(inProseOf source: String) -> Set<String> {
    var names: Set<String> = []
    for line in source.components(separatedBy: "\n") {
        guard let marker = line.range(of: "//") else { continue }
        let prose = String(line[marker.upperBound...])
        var spans = prose.components(separatedBy: "`")
        // An unterminated backtick leaves a trailing fragment that was never inside a span.
        if spans.count % 2 == 0 { spans.removeLast() }
        for (index, span) in spans.enumerated() where index % 2 == 1 {
            let head = span.components(separatedBy: ".")[0]
            guard head.hasSuffix("Metrics"), let first = head.first, first.isUppercase else { continue }
            guard head.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { continue }
            names.insert(head)
        }
    }
    return names
}

/// Counts the hand-rolled **sub-label** eyebrow: a 9pt semibold/bold `Text` that is uppercased,
/// within six lines of an eyebrow tint — `Theme.dim`, `Theme.muted`, or a list/context
/// `Color(hex:)`, because two of the six converted sites took the container's own colour.
///
/// Deliberately a second function rather than a wider `handRolledEyebrowLines`: the two tiers are
/// separate decisions, and one detector spanning both would report "the sub-label tier exists" as a
/// failure. `.uppercased()` is required rather than optional here (the 10pt detector also accepts
/// `.kerning(0.8)`) because the sub-label tier has no single kerning to key on — that was the bug.
private func handRolledCompactEyebrowLines(in source: String) -> Int {
    let fonts = [
        ".font(.system(size: 9, weight: .semibold))",
        ".font(.system(size: 9, weight: .bold))"
    ]
    let lines = source.components(separatedBy: "\n")
    var count = 0

    for (index, line) in lines.enumerated() {
        guard fonts.contains(where: line.contains) else { continue }
        let window = lines[max(0, index - 6)...min(lines.count - 1, index + 6)].joined(separator: "\n")
        guard window.contains(".textCase(.uppercase)") || window.contains(".uppercased()") else { continue }
        let eyebrowTint = window.contains("Theme.dim")
            || window.contains("Theme.muted")
            || window.contains("Color(hex:")
        if eyebrowTint { count += 1 }
    }
    return count
}

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

// MARK: - T-496: one uppercase label size, three trackings

/// **Three labels with the same typographic role, one size, and three different trackings.**
///
/// `SectionEyebrowLabel.Size.standard` draws 10pt semibold uppercase kerned `0.8` — derived, as
/// `fontSize * kerningRatio`, i.e. 0.08em. `CadenceBoardColumnHeaderMetrics` draws the same 10pt
/// semibold uppercase kerned a literal `0.4` (0.04em). `CadenceCalendarWeekdayHeaderMetrics` draws
/// it kerned a literal `0.5` (0.05em). The *sizes* converged across T-275, T-277 and T-284 and the
/// trackings were never part of that argument, so the app now states one type size three times and
/// three letterspacings for it.
///
/// **This suite deliberately does not pick a ratio, and that is the finding rather than a gap.**
/// Adopting 0.08em doubles the tracking on every kanban, section-board, list-board and
/// calendar-board column header and adds 60% to every weekday label on four calendar surfaces —
/// an un-inspected visual change of exactly the kind T-452 is already open for, and one an
/// agent correctly declined to make. Adopting 0.05em or 0.04em instead moves ~50 eyebrows and the
/// 9pt sub-label tier, which is a larger blast radius for the same reason. All three are decisions
/// a reviewer has to *look* at; none is a refactor.
///
/// So what is pinned here is the status quo, precisely enough that the disagreement cannot widen
/// while the decision is pending:
///
/// - the three roles really are one role — same size, same weight, same uppercasing, asserted as
///   values where the type is readable and as source where it is inside `Cadence/iOS/`;
/// - the three trackings, by value *and* as em ratios, so a fourth spelling or a silent nudge to
///   one of the three fails here;
/// - the arithmetic a reviewer would be signing off under each candidate, so the conversion factors
///   are checked rather than recomputed by hand in the ticket.
///
/// **What a reviewer needs to look at**, when the decision is taken: a kanban column header and a
/// section-board column header (macOS and iOS, since both boards draw the shared component), the
/// collapsed calendar-board rail — whose label is rotated -90°, which is the one place letterspacing
/// changes a *layout* slot rather than a line width — a macOS week/2-week day column and the iOS
/// timed grid's day header, and any 9pt `SectionEyebrowLabel(size: .compact)` popover heading, which
/// moves under a re-derivation even though nobody proposed changing it.
///
/// **The citation graph is 4 of 6, not mutual**, which is worth writing down because the ticket
/// recorded it as mutual: the calendar file cites both of the others, the board file and the eyebrow
/// file each cite one — each other — and neither cites the calendar. So the calendar's `0.5` is the
/// only one of the three chosen with both siblings in view, and it still disagrees with both.
@MainActor
struct CadenceUppercaseLabelTrackingTests {

    /// One size, and it is the eyebrow's. This half is already true and is restated here so the
    /// suite's premise — *same role* — is asserted rather than assumed by the tests below.
    @Test func theThreeUppercaseLabelRolesAreOneSize() {
        #expect(SectionEyebrowLabel.Size.standard.fontSize == 10)
        #expect(CadenceBoardColumnHeaderMetrics.labelSize == SectionEyebrowLabel.Size.standard.fontSize)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelSize == SectionEyebrowLabel.Size.standard.fontSize)
        // The sub-label tier is one point smaller on purpose (T-284) and is not a fourth opinion
        // about this size — but it does move under a re-derivation, which is why it is named here.
        #expect(SectionEyebrowLabel.Size.compact.fontSize == 9)
    }

    /// **The disagreement, frozen.** Three trackings for one size, stated as values and as the em
    /// ratios they work out to.
    ///
    /// If this goes red, one of two things happened. Either somebody nudged a tracking without
    /// taking the decision — put it back — or the T-496 decision has been taken, in which case this
    /// is the test to rewrite, and the ticket asks for a rendered pass over the sites listed in this
    /// suite's doc *before* the numbers move, not after.
    @Test func theThreeUppercaseTrackingsAreStillThreeAndStillTheseThree() {
        #expect(SectionEyebrowLabel.Size.standard.kerning == 0.8)
        #expect(CadenceBoardColumnHeaderMetrics.labelKerning == 0.4)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelKerning == 0.5)

        // As ratios of the one shared size — the form the decision will be taken in, since the
        // eyebrow's is already spelled that way and the other two are literals.
        let size = SectionEyebrowLabel.Size.standard.fontSize
        #expect(SectionEyebrowLabel.kerningRatio == 0.08)
        #expect(CadenceBoardColumnHeaderMetrics.labelKerning / size == 0.04)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelKerning / size == 0.05)

        // Pairwise distinct, which is the ticket's actual claim and the thing that must not become
        // *more* true. Two of these collapsing is progress and would land as a rewrite of this test;
        // a fourth value appearing is the regression.
        #expect(SectionEyebrowLabel.Size.standard.kerning != CadenceBoardColumnHeaderMetrics.labelKerning)
        #expect(SectionEyebrowLabel.Size.standard.kerning != CadenceCalendarWeekdayHeaderMetrics.labelKerning)
        #expect(CadenceBoardColumnHeaderMetrics.labelKerning != CadenceCalendarWeekdayHeaderMetrics.labelKerning)
    }

    /// **What each candidate would cost, as arithmetic rather than as a sentence in a ticket.**
    ///
    /// The multipliers are the whole argument for not picking one here: no candidate moves fewer
    /// than two of the three roles, and the cheapest-looking one (0.08em, the ratio the design
    /// system already derives from) is the one with the largest single jump — a doubling on every
    /// board column header in the app.
    @Test func eachCandidateRatioMovesTheOtherTwoRolesByTheseFactors() {
        let size = SectionEyebrowLabel.Size.standard.fontSize
        let eyebrow = SectionEyebrowLabel.Size.standard.kerning
        let board = CadenceBoardColumnHeaderMetrics.labelKerning
        let calendar = CadenceCalendarWeekdayHeaderMetrics.labelKerning

        // 0.08em — the eyebrow's own ratio. Board doubles, calendar +60%, ~50 eyebrows unmoved.
        #expect(SectionEyebrowLabel.kerningRatio * size == board * 2)
        #expect(SectionEyebrowLabel.kerningRatio * size == calendar * 1.6)

        // 0.05em — the calendar's. Board +25%, every eyebrow loses 37.5% of its tracking, and the
        // 9pt sub-label tier goes 0.72 -> 0.45.
        #expect(0.05 * size == board * 1.25)
        #expect(0.05 * size == eyebrow * 0.625)
        #expect(0.05 * SectionEyebrowLabel.Size.compact.fontSize == 0.45)

        // 0.04em — the board's, and the tightest. Calendar -20%, eyebrows halved, sub-labels to 0.36.
        #expect(0.04 * size == calendar * 0.8)
        #expect(0.04 * size == eyebrow * 0.5)
        #expect(0.04 * SectionEyebrowLabel.Size.compact.fontSize == 0.36)
    }

    /// **The role claim, at the four places it is drawn.**
    ///
    /// Values cannot carry this half: uppercasing and weight are applied at the call site, and two
    /// of the four sites are inside `Cadence/iOS/`, which this macOS-built target cannot see. Read
    /// as source, with comments stripped and whitespace removed so a reformat is not a failure and
    /// a rewrite is.
    @Test func allFourDrawSitesSetTheSameUppercaseSemiboldLabel() throws {
        let sites: [(path: String, needles: [String])] = [
            (
                "Cadence/Shared/Components/SectionEyebrowLabel.swift",
                [
                    "Text(text.uppercased()).font(size.font)",
                    "varfont:Font{.system(size:fontSize,weight:.semibold)}",
                    ".kerning(size.kerning)"
                ]
            ),
            (
                "Cadence/Shared/Components/CadenceBoardColumnHeader.swift",
                [
                    "Text(title.uppercased()).font(.system(size:CadenceBoardColumnHeaderMetrics.labelSize,weight:.semibold))",
                    ".kerning(CadenceBoardColumnHeaderMetrics.labelKerning)"
                ]
            ),
            (
                "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift",
                [
                    "Text(DateFormatters.dayOfWeek.string(from:date).uppercased()).font(.system(size:CadenceCalendarWeekdayHeaderMetrics.labelSize,weight:.semibold))",
                    ".kerning(CadenceCalendarWeekdayHeaderMetrics.labelKerning)"
                ]
            ),
            (
                "Cadence/iOS/iOSCalendarTimelineViews.swift",
                [
                    "Text(DateFormatters.dayOfWeek.string(from:date).uppercased()).font(.system(size:iOSCalendarTimelineMetrics.weekdaySize,weight:.semibold))",
                    ".kerning(CadenceCalendarWeekdayHeaderMetrics.labelKerning)"
                ]
            )
        ]

        for site in sites {
            let raw = try sourceFile(site.path)
            let stripped = try strippingComments(raw)
            #expect(stripped != raw, "non-vacuity: \(site.path) carries no comments to strip")
            let dense = stripped.filter { !$0.isWhitespace }
            for needle in site.needles {
                #expect(dense.contains(needle), "\(site.path) no longer draws \(needle)")
            }
        }
    }

    /// **The two literals are still literals, and the derived one is still derived.**
    ///
    /// Which spelling each tracking has is the shape of the decision, not a detail: two hand-typed
    /// numbers are what let the three drift in the first place, and a third file quietly deriving
    /// its own ratio would be a fourth opinion wearing the design system's clothes. When T-496
    /// lands, all three become one ratio and this test goes with it.
    @Test func theTwoBoardAndCalendarTrackingsAreStillHandTypedAndTheEyebrowsIsNot() throws {
        func dense(_ path: String) throws -> String {
            let raw = try sourceFile(path)
            let stripped = try strippingComments(raw)
            #expect(stripped != raw, "non-vacuity: \(path) carries no comments to strip")
            return stripped.filter { !$0.isWhitespace }
        }

        let board = try dense("Cadence/Shared/Components/CadenceBoardColumnHeader.swift")
        #expect(board.contains("staticletlabelKerning:CGFloat=0.4"))
        #expect(board.contains("kerningRatio") == false, "the board tracking is derived now — T-496 landed?")

        let calendar = try dense("Cadence/Shared/CadenceCalendarWeekdayHeaderMetrics.swift")
        #expect(calendar.contains("staticletlabelKerning:CGFloat=0.5"))
        #expect(calendar.contains("kerningRatio") == false, "the calendar tracking is derived now — T-496 landed?")

        let eyebrow = try dense("Cadence/Shared/Components/SectionEyebrowLabel.swift")
        #expect(eyebrow.contains("varkerning:CGFloat{fontSize*SectionEyebrowLabel.kerningRatio}"))
        #expect(eyebrow.contains("staticletkerningRatio:CGFloat=0.08"))
    }

    /// **The citation graph, as it actually is.**
    ///
    /// Each of the three files justifies its 10 by pointing at a sibling, which is why the "same
    /// role" premise above is the codebase's own claim and not this suite's. It is not mutual: the
    /// calendar cites both siblings, the eyebrow and the board cite each other, and neither cites
    /// the calendar. Asserted over raw source rather than stripped, because the citations *are*
    /// prose — that is the defect the ticket is about.
    @Test func eachTrackingsFileCitesTheSiblingItAgreesWithOnSizeAndNotOnTracking() throws {
        let eyebrow = try sourceFile("Cadence/Shared/Components/SectionEyebrowLabel.swift")
        let board = try sourceFile("Cadence/Shared/Components/CadenceBoardColumnHeader.swift")
        let calendar = try sourceFile("Cadence/Shared/CadenceCalendarWeekdayHeaderMetrics.swift")

        // Non-vacuity: the three files are the three declarations, not three paths that read.
        #expect(eyebrow.contains("struct SectionEyebrowLabel: View {"), "non-vacuity: wrong file read")
        #expect(board.contains("struct CadenceBoardColumnHeaderMetrics"), "non-vacuity: wrong file read")
        #expect(calendar.contains("struct CadenceCalendarWeekdayHeaderMetrics"), "non-vacuity: wrong file read")

        #expect(eyebrow.contains("CadenceBoardColumnHeaderMetrics.labelSize"))
        #expect(board.contains("`SectionEyebrowLabel`"))
        #expect(calendar.contains("`SectionEyebrowLabel.fontSize`"))
        #expect(calendar.contains("`CadenceBoardColumnHeaderMetrics.labelSize`"))
        #expect(calendar.contains("`CadenceBoardColumnHeaderMetrics.labelKerning`"))

        // The two edges that do *not* exist, which is the asymmetry the ticket recorded as
        // symmetry. Adding either citation is an improvement, not a regression — if one of these
        // fails because somebody wrote the missing cross-reference, delete the line and say so in
        // T-496. It is asserted at all so the "4 of 6" in this suite's doc is a measurement.
        #expect(
            eyebrow.contains("CadenceCalendarWeekdayHeaderMetrics") == false,
            "the eyebrow now cites the calendar too — the citation graph is no longer 4 of 6"
        )
        #expect(
            board.contains("CadenceCalendarWeekdayHeaderMetrics") == false,
            "the board header now cites the calendar too — the citation graph is no longer 4 of 6"
        )
    }
}
