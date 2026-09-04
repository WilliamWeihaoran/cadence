import AppKit
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

    /// **T-571.** The two Calendar Board day columns reach the shared header with the same *number*.
    ///
    /// They did not. macOS passed `activeItems.count`; iOS passed `activeItems.count +
    /// completedTasks.count`, so a day with two open and three done read **5** on the phone and
    /// **2** on the Mac, in one shared component.
    ///
    /// Active only is the meaning that survives, and it is not a coin toss. The number sits
    /// directly above the column's own list, and that list is the active items; finished work is
    /// behind the "Completed" toggle underneath, which carries its own count. Summing the two
    /// stated a total nothing on screen adds up to, counted the same task twice on a column that
    /// shows both halves, and made a day fully cleared read as busy as one untouched. It is also
    /// what every other board column header in the app already passes —
    /// `KanbanSectionColumnView` hands `KanbanColumnHeader` its `activeTasks.count`.
    ///
    /// A scan, because the iOS half is behind `#if os(iOS)` and this target builds for macOS.
    @Test func bothCalendarBoardDayColumnsCountOnlyTheWorkTheColumnStillLists() throws {
        let sites = [
            ("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift", "struct CalendarBoardDayColumn: View {"),
            ("Cadence/iOS/iOSCalendarBoardView.swift", "struct iOSCalendarBoardDayColumn: View {")
        ]

        for (path, declaration) in sites {
            let raw = try sourceFile(path)
            let stripped = try strippingComments(raw)
            #expect(stripped != raw, "non-vacuity: \(path) carries no comments to strip")
            let dense = stripped.filter { !$0.isWhitespace }
            #expect(dense.contains(declaration.filter { !$0.isWhitespace }), "non-vacuity: wrong file read")

            #expect(
                dense.contains("count:activeItems.count,accentRule:"),
                "\(path) no longer heads its day column with the count of what the column lists"
            )
            // The drift, by name. macOS keeps a `totalCount` for its accessibility label, so this
            // is the *header argument* rather than the sum's existence.
            #expect(
                !dense.contains("count:totalCount"),
                "\(path) is heading its day column with active + completed again (T-571)"
            )
            // And the finished half is still counted, once, where it belongs: on its own toggle.
            #expect(
                dense.contains("completedTasks.count"),
                "\(path) stopped counting completed work anywhere at all"
            )
        }
    }

    // MARK: - T-572: what VoiceOver calls a Board day column

    /// The label's words and its plural, as a value.
    ///
    /// This is the half a scan cannot make: the sweep below only knows that both columns *call*
    /// the shared function, and would stay green if the function itself started saying nothing.
    @Test func theDayColumnAccessibilityLabelNamesTheDayAndPluralisesItsCount() throws {
        let date = try #require(DateFormatters.date(from: "2026-08-31"))
        let long = DateFormatters.longDate.string(from: date)

        #expect(
            CadenceBoardColumnAccessibility.dayColumnLabel(date: date, itemCount: 3)
                == "\(long), 3 scheduled items"
        )
        #expect(
            CadenceBoardColumnAccessibility.dayColumnLabel(date: date, itemCount: 1)
                == "\(long), 1 scheduled item"
        )
        // An empty day still says so rather than announcing a bare date.
        #expect(
            CadenceBoardColumnAccessibility.dayColumnLabel(date: date, itemCount: 0)
                == "\(long), 0 scheduled items"
        )
    }

    /// **T-572, and the trap it was carrying.** Both Calendar Board day columns state a name, and
    /// they state it with the count of what the column lists.
    ///
    /// The ticket said to copy macOS's hand-written label to iOS as "the correct pattern". By the
    /// time it was worked it was not: [[T-571]] had just moved the visible header beside that label
    /// to `activeItems.count`, while the label still read a local `totalCount` of active +
    /// completed — so on macOS VoiceOver and the number on screen disagreed, and copying it would
    /// have made that two platforms' bug while closing an accessibility ticket.
    ///
    /// Hence one shared function rather than two labels that agree today. This asserts the
    /// *argument* as well as the call: passing `totalCount` back in would satisfy a call-site count
    /// and reinstate the whole defect.
    @Test func bothCalendarBoardDayColumnsAnnounceTheSameNumberTheirHeaderDraws() throws {
        let sites = [
            ("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift", "struct CalendarBoardDayColumn: View {"),
            ("Cadence/iOS/iOSCalendarBoardView.swift", "struct iOSCalendarBoardDayColumn: View {")
        ]

        for (path, declaration) in sites {
            let raw = try sourceFile(path)
            let stripped = try strippingComments(raw)
            #expect(stripped != raw, "non-vacuity: \(path) carries no comments to strip")
            let dense = stripped.filter { !$0.isWhitespace }
            #expect(dense.contains(declaration.filter { !$0.isWhitespace }), "non-vacuity: wrong file read")

            #expect(
                dense.contains(".accessibilityLabel(CadenceBoardColumnAccessibility.dayColumnLabel(date:date,itemCount:activeItems.count))"),
                "\(path) no longer names its day column from the shared label with the count it lists"
            )
            // The defect by name: a local sum of active + completed, which is what macOS announced
            // and what the ticket asked iOS to copy.
            #expect(
                dense.contains("activeItems.count+completedTasks.count") == false,
                "\(path) has a total of active + completed again — check nothing announces it (T-572)"
            )
        }
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
            ("Cadence/iOS/iOSCalendarInspectorView.swift", "surface: .touch"),
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

    /// **T-601(a). The fifth call site above is a fork this ticket closed, not one it found kept.**
    ///
    /// `iOSCalendarInspectorView` drew `CadenceInlineEmpty(surface: .touch)` by hand — the same
    /// sentence, the same 13pt `Theme.dim`, the same `Theme.surfaceElevated.opacity(0.38)` wash and
    /// the same `Theme.radiusControl` — **at 6pt of vertical padding against the shared touch
    /// metric's 14**, on the same screen as the Board day column that used the real component.
    ///
    /// It also folded an `iOSActionButton` "Add" into the card. That is why the fix is not a
    /// one-line substitution: the Board answers the same need with the ordinary
    /// `iOSCalendarAddItemRow` *above* the line, and the inspector's own non-empty branch was
    /// already drawing exactly that row. So the empty branch became the same two views in the same
    /// order, and the component stayed text-only rather than growing an accessory parameter for one
    /// caller.
    ///
    /// **The sentence had to move to `CadenceEmptyStateCopy` in the same change.** With both files
    /// reading the real component, `CadenceEmptyStateAuditTests.noEmptyStateSentenceIsSpelledInTwoFiles`
    /// sees "Nothing scheduled" harvested from two `CadenceInlineEmpty(text:)` calls — the hand-rolled
    /// copy was invisible to that sweep precisely because it was not a component call.
    @Test func theCalendarDayInspectorDrawsTheSharedInlineEmptyRatherThanACopyOfIt() throws {
        #expect(CadenceEmptyStateCopy.nothingScheduledTitle == "Nothing scheduled")
        // Seventeen characters, so unlike most of what T-598 touched this one genuinely clears
        // `CadenceSharedConstantReuseSweepTests`' twelve-character floor and is armed there.
        #expect(CadenceEmptyStateCopy.nothingScheduledTitle.count >= 12)

        let inspector = try sourceFile("Cadence/iOS/iOSCalendarInspectorView.swift")

        // Non-vacuity: this is still the day inspector, and it is still the empty branch that draws
        // the line.
        #expect(inspector.contains("struct iOSCalendarDayInspector: View"))
        #expect(inspector.contains("if !hasItems {"))

        #expect(
            inspector.contains("CadenceInlineEmpty(") && inspector.contains("CadenceEmptyStateCopy.nothingScheduledTitle"),
            "the day inspector does not draw the shared inline empty with the shared sentence"
        )
        #expect(
            CadenceSourceScan.matchCount(#"iOSCalendarInspectorEmptyState"#, in: inspector) == 0,
            "the hand-rolled empty state is back"
        )
        #expect(
            CadenceSourceScan.matchCount(#"padding\(\.vertical, 6\)"#, in: inspector) == 0,
            "the day inspector still pads its empty line by 6 instead of the shared touch metric"
        )
        #expect(
            CadenceSourceScan.matchCount(#""Nothing scheduled""#, in: inspector) == 0,
            "the day inspector spells the sentence instead of reading it"
        )
        // The add affordance is the shared row both branches of this file and the Board use, not a
        // second control of its own.
        #expect(CadenceSourceScan.matchCount("iOSCalendarAddItemRow\\(", in: inspector) == 2)
        #expect(CadenceSourceScan.matchCount("iOSActionButton\\(", in: inspector) == 0)

        // And the Board, whose copy of the sentence is now the same constant.
        let board = try sourceFile("Cadence/iOS/iOSCalendarBoardView.swift")
        #expect(board.contains("CadenceEmptyStateCopy.nothingScheduledTitle"))
        #expect(CadenceSourceScan.matchCount(#""Nothing scheduled""#, in: board) == 0)
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
    ///
    /// **The figure is 0.8 since T-496**, and it is not typed here or there: this label takes the
    /// app's one uppercase ratio at its own size, so the number below is the arithmetic and
    /// `CadenceUppercaseLabelTrackingTests` is what holds the file to deriving it.
    @Test func theUppercasedWeekdayIsKerned() {
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelKerning == 0.8)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelKerning > 0)
        #expect(
            CadenceCalendarWeekdayHeaderMetrics.labelKerning
                == CadenceCalendarWeekdayHeaderMetrics.labelSize * SectionEyebrowLabel.kerningRatio
        )
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
            // Two: the label's size, and — since T-595 — the height of the band it sits in.
            "Cadence/iOS/iOSCalendarMonthViews.swift": 2,
            // The sibling container that framed the same row at 22 while the grid above framed it
            // at 36. It reads the band now, which is why it is in this table at all.
            "Cadence/iOS/iOSCalendarMonthAgendaViews.swift": 1
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
    ///
    /// **The needle is retired, so this corpus can never witness it** (T-553). `weekdaySymbolSize`
    /// survives under `Cadence/` in two doc comments and nowhere else, and comments are what this
    /// reader blanks — so every file the sweep walks is *required* not to contain it, and nothing
    /// in the walk could show the spelling still matches anything. Blinding the needle to
    /// `weekdaySymbolSizeZZZ` left this test green. The instrument supplies the witness the corpus
    /// cannot: two literal fixtures, checked when it is built, so a detector that has stopped
    /// discriminating cannot reach the walk.
    @Test func theMonthGridsWeekdayRowHasNoSizeKnobLeft() throws {
        let carriesTheKnob = try CadenceScanInstrument(
            "a weekday-row size knob",
            fires: "iOSCalendarMonthScrollingGrid(month: month, weekdaySymbolSize: 10)",
            andNotOn: "iOSCalendarMonthScrollingGrid(month: month)",
            by: { CadenceSourceScan.codeOnly($0).contains("weekdaySymbolSize") }
        )

        let offenders = try carriesTheKnob.sweep(
            try swiftFiles(under: "Cadence"),
            // 558 files when this was written.
            atLeast: 300,
            including: "Cadence/iOS/iOSCalendarMonthViews.swift",
            read: sourceFile
        )
        #expect(
            offenders.isEmpty,
            "weekday size knob(s) in: \(offenders.joined(separator: ", "))"
        )

        // The two readers genuinely differ, pinned rather than assumed: the grid's own file still
        // names the retired parameter in the prose explaining why it went, so a raw read finds it
        // and the scanned read must not. Without this the zero above is equally satisfied by a
        // reader that returned nothing at all.
        let grid = try sourceFile("Cadence/iOS/iOSCalendarMonthViews.swift")
        #expect(
            grid.contains("weekdaySymbolSize"),
            "the prose naming the retired knob is gone; re-anchor this witness or drop the sweep"
        )
        #expect(!carriesTheKnob.fires(on: grid))
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

// MARK: - T-496: one uppercase label size, one tracking

/// **Three labels with the same typographic role, one size, and — since T-496 — one tracking.**
///
/// `SectionEyebrowLabel.Size.standard`, `CadenceBoardColumnHeaderMetrics` and
/// `CadenceCalendarWeekdayHeaderMetrics` all draw 10pt semibold uppercase. The *sizes* converged
/// across T-275, T-277 and T-284; the trackings were never part of that argument, so the app spent
/// a year stating one type size three times and three letterspacings for it — `0.8` derived as
/// `fontSize * kerningRatio` (0.08em), a literal `0.4` (0.04em) and a literal `0.5` (0.05em) — with
/// each file's doc citing a sibling as the authority for its size while disagreeing on tracking.
///
/// **The user took the decision: 0.08em everywhere.** What it cost was measured before it was
/// taken, not argued from the design system:
///
/// - **1–6pt of line width, and no truncation anywhere.** `MON` goes 26→28, `WED` 26→27,
///   `IN PROGRESS` 74→79, `LAUNCH CHECKLIST` 112→118, in a 232pt column.
/// - **The collapsed calendar-board rail is not a constraint**, which was the ticket's strongest
///   structural argument against moving. `UNSCHEDULED` measures 88pt at 0.08em against a 96pt
///   `collapsedRailLabelSlotHeight` and `OVERDUE` 55pt — measured twice, by `ImageRenderer`
///   intrinsic size and by `NSAttributedString.size()`, which agreed exactly.
/// - **0.04em was ruled out by an observable defect, not by arithmetic**: it drops the 9pt compact
///   tier to 0.36, which renders visibly set solid — the exact defect [[T-284]] closed.
/// - **"Both platforms" is answered by construction.** `CadenceBoardColumnHeader` is one shared
///   component and both call sites pass no tracking of their own; the iOS timed-grid day header
///   reads the identical `CadenceCalendarWeekdayHeaderMetrics.labelKerning` the macOS week column
///   reads. A cross-platform difference in these labels is not expressible.
///
/// **What this suite asserts now, and why it is not three literals that happen to agree.** Every
/// value assertion below — `0.8 == 0.8 == 0.8` — is satisfied by three hand-typed `0.8`s, which is
/// the *same* defect one number later: three independently editable constants, and `kerningRatio`
/// dead beside them. So the load-bearing test here is
/// `everyUppercaseTrackingReadsTheOneRatioRatherThanRestatingIt`, which reads the three
/// declarations as source and requires each to *name* `SectionEyebrowLabel.kerningRatio`. That is
/// the shape `theCompactKerningIsDerivedRatherThanASecondLiteral` already holds the two eyebrow
/// tiers to; this extends it to the two files that were the literals.
@MainActor
struct CadenceUppercaseLabelTrackingTests {

    /// One size, and it is the eyebrow's. This half was already true before T-496 and is restated
    /// here so the suite's premise — *same role* — is asserted rather than assumed by the tests
    /// below.
    @Test func theThreeUppercaseLabelRolesAreOneSize() {
        #expect(SectionEyebrowLabel.Size.standard.fontSize == 10)
        #expect(CadenceBoardColumnHeaderMetrics.labelSize == SectionEyebrowLabel.Size.standard.fontSize)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelSize == SectionEyebrowLabel.Size.standard.fontSize)
        // The sub-label tier is one point smaller on purpose (T-284) and is not a fourth opinion
        // about this size — but it moves with the ratio, which is why it is named here.
        #expect(SectionEyebrowLabel.Size.compact.fontSize == 9)
    }

    /// **One tracking, stated as the ratio it is rather than as the number it lands on.**
    ///
    /// The `== 0.8` lines are deliberately *not* the claim. They pin what a reviewer looked at, and
    /// nothing more; the claim is the three identities beside them, each of which re-derives the
    /// value from the size in front of it and the one shared ratio. Change `kerningRatio` to 0.05
    /// and every line here still passes — as it should, because that is a decision, not a drift —
    /// while three files quietly disagreeing again cannot.
    @Test func theThreeUppercaseTrackingsAreOneRatioAppliedThreeTimes() {
        let ratio = SectionEyebrowLabel.kerningRatio

        #expect(
            SectionEyebrowLabel.Size.standard.kerning
                == SectionEyebrowLabel.Size.standard.fontSize * ratio
        )
        #expect(
            CadenceBoardColumnHeaderMetrics.labelKerning
                == CadenceBoardColumnHeaderMetrics.labelSize * ratio
        )
        #expect(
            CadenceCalendarWeekdayHeaderMetrics.labelKerning
                == CadenceCalendarWeekdayHeaderMetrics.labelSize * ratio
        )

        // Pairwise *equal* now, which is the whole ticket inverted: what used to be asserted here
        // was that no two of them agreed.
        #expect(SectionEyebrowLabel.Size.standard.kerning == CadenceBoardColumnHeaderMetrics.labelKerning)
        #expect(SectionEyebrowLabel.Size.standard.kerning == CadenceCalendarWeekdayHeaderMetrics.labelKerning)

        // And the arithmetic a reviewer signed off, so the numbers in T-496's closing entry are
        // checked rather than restated: 0.08em at 10pt, and the compact tier at 9pt with it.
        #expect(ratio == 0.08)
        #expect(SectionEyebrowLabel.Size.standard.kerning == 0.8)
        #expect(CadenceBoardColumnHeaderMetrics.labelKerning == 0.8)
        #expect(CadenceCalendarWeekdayHeaderMetrics.labelKerning == 0.8)
        #expect(SectionEyebrowLabel.Size.compact.kerning == 0.72)
    }

    /// **What the two retired literals were, and what taking them cost — as arithmetic rather than
    /// as a sentence in a ticket.**
    ///
    /// Kept from the pre-decision suite because it is the evidence the decision rests on, and
    /// because the numbers are otherwise only in `docs/TODO.md`, where nothing checks them. The
    /// board header's tracking **doubled** (0.4 → 0.8) and the weekday label's gained 60%
    /// (0.5 → 0.8); the ~50 `SectionEyebrowLabel` sites and the 9pt tier did not move at all, which
    /// is why 0.08em was the candidate with the smallest blast radius despite having the largest
    /// single jump.
    ///
    /// **The two retired values are bound to `let`s rather than written inline, and that is not
    /// style.** Measured 2026-09-03: `#expect(adopted == 0.5 * 1.6)` **fails** in this target while
    /// `#expect(adopted == retiredWeekday * 1.6)` passes for the same numbers, and a standalone
    /// `swiftc -Onone` binary computing both spellings prints one bit pattern for all of them. So
    /// the difference is something about how `#expect` evaluates a literal-times-literal operand,
    /// not about the tracking — which is the whole reason to keep it out of an assertion whose
    /// subject is typography. Reported as observed; the mechanism is not explained here because it
    /// is not understood, and a guess in a doc comment is worse than the measurement.
    @Test func theTwoRetiredLiteralsAndWhatAdoptingTheRatioCostThem() {
        let size = SectionEyebrowLabel.Size.standard.fontSize
        let adopted = SectionEyebrowLabel.kerningRatio * size
        let retiredBoard: CGFloat = 0.4
        let retiredWeekday: CGFloat = 0.5

        // The board header's retired 0.04em, doubled.
        #expect(0.04 * size == retiredBoard)
        #expect(adopted == retiredBoard * 2)

        // The weekday label's retired 0.05em, +60%.
        #expect(0.05 * size == retiredWeekday)
        #expect(adopted == retiredWeekday * 1.6)

        // Unmoved: the eyebrow tier the ratio already came from, at both sizes.
        #expect(adopted == 0.8)
        #expect(SectionEyebrowLabel.kerningRatio * SectionEyebrowLabel.Size.compact.fontSize == 0.72)

        // The candidate that was ruled out by looking rather than by counting: 0.04em takes the
        // 9pt tier to 0.36, which renders set solid — the defect T-284 closed.
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

    /// **The derivation, not the number it lands on — the load-bearing test of this suite.**
    ///
    /// Every value assertion above is satisfied by three hand-typed `0.8`s, which puts the three
    /// roles back on three independently editable constants and leaves `kerningRatio` read by one
    /// file again. That is the defect T-496 closed, one number later, and only source can see it.
    ///
    /// So each of the three declarations has to *name* the ratio, and none of the three files may
    /// carry `0.8` or `0.72` written down. `0.08` contains neither string, so the ratio's own
    /// declaration is not what these catch.
    ///
    /// Named rather than counted on purpose: an aggregate "three files mention `kerningRatio`"
    /// cannot tell you the three are the three, and the runbook's rule against a floor over a
    /// population the repo is shrinking applies to agreement counts as much as to occurrence
    /// counts.
    @Test func everyUppercaseTrackingReadsTheOneRatioRatherThanRestatingIt() throws {
        func dense(_ path: String, containing declaration: String) throws -> String {
            let raw = try sourceFile(path)
            let stripped = try strippingComments(raw)
            #expect(stripped != raw, "non-vacuity: \(path) carries no comments to strip")
            let dense = stripped.filter { !$0.isWhitespace }
            #expect(dense.contains(declaration), "non-vacuity: wrong file read for \(path)")
            return dense
        }

        let board = try dense(
            "Cadence/Shared/Components/CadenceBoardColumnHeader.swift",
            containing: "structCadenceBoardColumnHeaderMetrics"
        )
        #expect(
            board.contains("staticletlabelKerning:CGFloat=labelSize*SectionEyebrowLabel.kerningRatio"),
            "the board column tracking is a literal again"
        )

        let calendar = try dense(
            "Cadence/Shared/CadenceCalendarWeekdayHeaderMetrics.swift",
            containing: "structCadenceCalendarWeekdayHeaderMetrics"
        )
        #expect(
            calendar.contains("staticletlabelKerning:CGFloat=labelSize*SectionEyebrowLabel.kerningRatio"),
            "the weekday tracking is a literal again"
        )

        let eyebrow = try dense(
            "Cadence/Shared/Components/SectionEyebrowLabel.swift",
            containing: "structSectionEyebrowLabel:View"
        )
        #expect(eyebrow.contains("varkerning:CGFloat{fontSize*SectionEyebrowLabel.kerningRatio}"))
        #expect(eyebrow.contains("staticletkerningRatio:CGFloat=0.08"))

        // No file states a tracking it could edit on its own. Anchored to the **declaration**
        // rather than to the digits: a bare `!contains("0.8")` reads the whole file, and this one
        // legitimately carries `accentRuleOpacities = [0.85, 0.45, 0.16]`, whose first element
        // contains `0.8` — the runbook's rule about a regex turned loose on a body, one file over.
        // Named per file so a failure says which one went back to a literal.
        for (path, source) in [
            ("CadenceBoardColumnHeader.swift", board),
            ("CadenceCalendarWeekdayHeaderMetrics.swift", calendar)
        ] {
            #expect(
                !source.contains("letlabelKerning:CGFloat=0."),
                "\(path) writes its tracking down as a decimal literal again"
            )
        }
        // The eyebrow's own two tiers, the pair `theCompactKerningIsDerivedRatherThanASecondLiteral`
        // holds. Restated here because this suite's claim is about all three roles, and a per-case
        // literal in `Size` would satisfy every value assertion above.
        #expect(!eyebrow.contains("case.standard:0."), "the standard tier's kerning is a literal again")
        #expect(!eyebrow.contains("case.compact:0."), "the compact tier's kerning is a literal again")
    }

    /// **The citation graph, as it actually is.**
    ///
    /// Each of the three files justified its 10 by pointing at a sibling, which is why the "same
    /// role" premise above is the codebase's own claim and not this suite's. It was never mutual:
    /// the calendar cites both siblings, the eyebrow and the board cite each other, and neither
    /// cites the calendar. Asserted over raw source rather than stripped, because the citations
    /// *are* prose — that half of the defect is now cosmetic rather than load-bearing, since no
    /// file can disagree with a sibling about a value it no longer holds, but the edges are what
    /// the ticket's "4 of 6" measured and a measurement nothing checks decays.
    @Test func eachTrackingsFileCitesTheSiblingItTakesItsSizeFrom() throws {
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

        // The two files that were the literals now cite the ratio in *code*, which is the citation
        // that cannot go stale — the prose above is checked, the code is compiled.
        #expect(board.contains("SectionEyebrowLabel.kerningRatio"))
        #expect(calendar.contains("SectionEyebrowLabel.kerningRatio"))

        // The two edges that still do *not* exist, kept from the pre-decision suite so the "4 of 6"
        // stays a measurement rather than a remembered number. Adding either citation is an
        // improvement, not a regression — if one of these fails because somebody wrote the missing
        // cross-reference, delete the line and say so in T-496.
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

/// **T-728 and T-729.** Both live in the collapsed Calendar Board rail's rotated label, one comment
/// above `CalendarBoardRailColumn.collapsedContent`'s `Text(rail.label)`.
///
/// **T-728: `UNSCHEDULED` measures 88pt against a 96pt `collapsedRailLabelSlotHeight` was prose,
/// not a test.** `CadenceUppercaseLabelTrackingTests`' own doc comment above states the figure as
/// the structural argument that adopting 0.08em tracking cannot overflow the collapsed rail — but
/// nothing here compared the two numbers; a widened label or a shrunk slot could disagree with that
/// sentence and every test in this file would still pass. `labelFitsTheCollapsedRailSlot` below
/// measures every `CalendarBoardRail` label at the real font, weight and kerning
/// `CalendarBoardRailColumn` draws it with, the same way the doc comment says it was checked once —
/// by `NSAttributedString.size()` — and asserts the result against the slot, for every case rather
/// than the two that happened to exist when the comment was written.
///
/// **T-729: the same view's `.frame` gave the rotated label's *width* the font's point size, not its
/// line height.** Rotation swaps the label's two dimensions in the slot: the height it is framed to
/// is the text's pre-rotation *width*, correctly bounded by `collapsedRailLabelSlotHeight`; the width
/// it is framed to is the text's pre-rotation *height* — a line of type, not a point size — and
/// `CadenceBoardColumnHeaderMetrics.labelSize` names the latter. A system font's line height is
/// measurably taller than its point size, so the slot was narrower than the rotated glyphs need,
/// which is the overhang the ticket describes as slight and reachable on any Calendar open with a
/// collapsed rail. `CadenceBoardColumnHeaderMetrics.labelLineHeight` is the fix, read from the
/// platform's own font metrics rather than approximated by a second literal; the tests below pin
/// both that the call site reads it and that reading it is not a no-op rename of `labelSize`.
struct CadenceCollapsedRailLabelSlotTests {
    /// The body of `CalendarBoardRailColumn.collapsedContent`, comment-stripped once for every test
    /// below rather than re-read per test.
    private func collapsedContentBody() throws -> String {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarBoardRailSupportViews.swift")
        )
        #expect(source.count > 400, "read \(source.count) characters")
        return try #require(
            CadenceSourceScan.declarationBody("private var collapsedContent: some View", in: source),
            "could not read collapsedContent's body"
        )
    }

    /// **T-728.** The measurement the doc comment describes, run for real: every rail label, at the
    /// font/kerning `collapsedContent` draws it with, against the slot it is framed to. A label that
    /// grows past the slot fails here instead of only overhanging on screen.
    @Test func labelFitsTheCollapsedRailSlot() {
        let font = NSFont.systemFont(
            ofSize: CadenceBoardColumnHeaderMetrics.labelSize,
            weight: .semibold
        )
        for rail in CalendarBoardRail.allCases {
            let attributed = NSAttributedString(
                string: rail.label,
                attributes: [
                    .font: font,
                    .kern: CadenceBoardColumnHeaderMetrics.labelKerning,
                ]
            )
            let measuredWidth = attributed.size().width
            #expect(
                measuredWidth <= CadenceCalendarBoardLayout.collapsedRailLabelSlotHeight,
                "\(rail.label) measures \(measuredWidth)pt, past the \(CadenceCalendarBoardLayout.collapsedRailLabelSlotHeight)pt slot"
            )
        }
    }

    /// **T-729, the call site.** A value-only pin cannot see which dimension a fifth rail label's
    /// frame reads; this reads the source so a regression back to `labelSize` — or a rewrite that
    /// drops the reference some other way — fails here rather than only on a screen with a collapsed
    /// rail open.
    @Test func collapsedLabelFrameReadsLineHeightNotPointSize() throws {
        let body = try collapsedContentBody()
        #expect(
            CadenceSourceScan.matchCount(#"CadenceBoardColumnHeaderMetrics\.labelLineHeight"#, in: body) == 1,
            "collapsedContent does not frame the rotated label's width with the line height exactly once"
        )
        #expect(
            CadenceSourceScan.matchCount(#"width:\s*CadenceBoardColumnHeaderMetrics\.labelSize"#, in: body) == 0,
            "collapsedContent still frames the rotated label's width with the font's point size"
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"height:\s*CadenceCalendarBoardLayout\.collapsedRailLabelSlotHeight"#,
                in: body
            ) == 1,
            "collapsedContent's rotated-label frame no longer bounds its height with the stated slot"
        )
    }

    /// **T-729, the derivation.** `labelLineHeight` has to be a real read of the platform's font
    /// metrics rather than `labelSize` under a second name — a mutation that redefined it as
    /// `labelSize` would still make the call-site test above pass, since the identifier used at the
    /// call site would not have changed.
    @Test func labelLineHeightIsARealMeasurementNotAnAliasForPointSize() {
        #expect(CadenceBoardColumnHeaderMetrics.labelLineHeight > CadenceBoardColumnHeaderMetrics.labelSize)
        #expect(
            CadenceBoardColumnHeaderMetrics.labelLineHeight
                == NSLayoutManager().defaultLineHeight(
                    for: NSFont.systemFont(ofSize: CadenceBoardColumnHeaderMetrics.labelSize, weight: .semibold)
                )
        )
    }
}
