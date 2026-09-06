import Foundation
import Testing
@testable import Cadence

/// Four surfaces host the same markdown editing surface as a *well* — the task inspector, the
/// Settings template editor, `iOSCalendarEventEditSheet` and `iOSCalendarQuickCreateSheet` — and
/// they gave it four resting heights, two of them ramped by the width of the screen behind the
/// sheet: 340, 340, `300 : 240` and `280 : 230`.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so what these
/// pin is the thing worth pinning: the decisions themselves. `iOSEditorSheetMetrics` lives outside
/// the platform guard for exactly that reason, as `iOSTaskInspectorMetrics` and
/// `CadencePageHeaderMetrics` already do.
struct iOSEditorSheetMetricsTests {

    // MARK: - The markdown well

    /// One resting height, at every width and on every sheet. 340 is the height the two surfaces
    /// that never ramped already agreed on, and the tallest of the four — not a split of them.
    /// A well inside a scroll view grows with its content, so the minimum's only job is to be a
    /// canvas worth tapping into, and the largest existing spelling is the one that does that.
    @Test func aMarkdownWellHasOneRestingHeight() {
        #expect(iOSEditorSheetMetrics.notesMinHeight == 340)
    }

    /// A canvas, not a field: the well has to hold enough lines that writing into it does not feel
    /// like typing into a caption. Measured against the sheet's own title line, which is the tallest
    /// line of text on it — anything under a handful of those is a text field with a big border.
    @Test func theWellIsACanvasRatherThanAField() {
        #expect(iOSEditorSheetMetrics.notesMinHeight > iOSTaskInspectorMetrics.titleLineHeight * 6)
    }

    /// The inspector reads the same number rather than keeping its own copy of it — which is what
    /// let two of these four drift in the first place.
    @Test func theInspectorsWellIsTheSameWell() {
        #expect(iOSTaskInspectorMetrics.notesMinHeight == iOSEditorSheetMetrics.notesMinHeight)
    }

    // MARK: - The one thing that varies

    /// The gutter is a fact about the *host*: what is left between the sheet's edge and a content
    /// column that has already stopped growing. It stays a ramp, and it is now the same ramp for
    /// the inspector and both calendar sheets instead of three copies of one ternary.
    @Test func theGutterIsTheOnlyFigureThatTakesAWidth() {
        let regular = iOSEditorSheetMetrics.gutter(isRegularWidth: true)
        let compact = iOSEditorSheetMetrics.gutter(isRegularWidth: false)

        #expect(regular == 20)
        #expect(compact == 18)
        #expect(regular > compact)
    }

    @Test func everySheetSharesTheOneGutter() {
        for isRegular in [true, false] {
            #expect(
                iOSTaskInspectorMetrics.sheetGutter(isRegularWidth: isRegular)
                    == iOSEditorSheetMetrics.gutter(isRegularWidth: isRegular),
                "regular=\(isRegular)"
            )
        }
    }

    // MARK: - The gap between two groups, and the frame around them

    /// The split T-112 closed. Three surfaces said 16 — `iOSCalendarEventEditSheet`,
    /// `iOSCalendarQuickCreateSheet` and `iOSTrackingEditorShell` — and two said 14: the task
    /// inspector and the Settings template editor.
    ///
    /// 16 is not a vote. It is that the two structural families here do not line up with the split:
    /// quick-create is the inspector's twin (ruled sections inside one sheet card, six groups each)
    /// and says 16, and the two free-standing-card sheets say 16 as well. Whichever way the five are
    /// grouped, 14 is the odd one out.
    @Test func twoGroupsOfFieldsAreOneDistanceApart() {
        #expect(iOSEditorSheetMetrics.groupSpacing == 16)
        #expect(iOSTaskInspectorMetrics.sectionSpacing == iOSEditorSheetMetrics.groupSpacing)
    }

    /// **The rule, not just the number: a sheet does not buy density with this figure.**
    ///
    /// The inspector's 14 read like a density allowance — it carries more groups than the template
    /// editor and was the densest-looking of the five — and it was not one. What a sheet writes here
    /// is not the gap the eye sees: `iOSEditorSection(style: .ruled)` adds 12pt of its own above
    /// every group's hairline, so the inspector's visible gap was 26 against quick-create's 28,
    /// while the two card-section sheets sat at a flat 16. The families that *do* differ differ by
    /// 12, which is the shared section's doing; the sheets' own figures differed by 2, which is
    /// nobody's.
    ///
    /// So density is `iOSEditorSection`'s decision — it is the thing that knows whether a group is
    /// separated by a hairline or by a card edge — and a sheet only says how far apart two groups
    /// are. The sheet with the strongest claim to an exception takes none: one figure for its group
    /// gap and for the card framing them, and it is every other sheet's figure.
    @Test func noSheetKeepsADensityAllowanceOfItsOwn() {
        #expect(iOSTaskInspectorMetrics.sectionSpacing == iOSEditorSheetMetrics.groupSpacing)
        #expect(iOSTaskInspectorMetrics.cardPadding == iOSEditorSheetMetrics.groupSpacing)
    }

    /// The card is the frame around the form, so it leaves the same gap on the outside that the form
    /// leaves between its own groups. Both sheets that draw such a card had already set these two
    /// equal, independently — the inspector at 14/14 and quick-create at 16/16 — which is what makes
    /// it one figure rather than two that happen to match.
    @Test func theCardsFrameIsOneMoreGapOfTheSameSize() {
        #expect(iOSEditorSheetMetrics.cardPadding == iOSEditorSheetMetrics.groupSpacing)
        #expect(iOSTaskInspectorMetrics.cardPadding == iOSEditorSheetMetrics.cardPadding)
    }

    /// The gutter is outside the card and the padding is inside it, so a gutter that dropped below
    /// the padding would make the sheet look glued to the edge of a screen it is floating above.
    @Test func theCardSitsFurtherFromTheScreenThanItsFormSitsFromTheCard() {
        for isRegular in [true, false] {
            #expect(
                iOSEditorSheetMetrics.gutter(isRegularWidth: isRegular) >= iOSEditorSheetMetrics.cardPadding,
                "regular=\(isRegular)"
            )
        }
    }

    // MARK: - The name of the thing being edited

    /// A task title, an event title and a quick-create title are the same thing — the one field the
    /// sheet exists to fill in — and all three sheets already drew it at 22pt bold. They drew it
    /// from three separate literals, so the agreement was a coincidence any one of them could end.
    @Test func everyEditorSheetNamesItsSubjectAtOneSize() {
        #expect(iOSEditorSheetMetrics.titleSize == 22)
        #expect(iOSTaskInspectorMetrics.titleSize == iOSEditorSheetMetrics.titleSize)
    }

    @Test func aTitleWrapsToTheSameNumberOfLinesEverywhereInIOSEditorSheetMetrics() {
        #expect(iOSEditorSheetMetrics.titleLineLimit == 3)
        #expect(iOSTaskInspectorMetrics.titleLineLimit == iOSEditorSheetMetrics.titleLineLimit)
    }

    /// The title is the loudest text on the sheet — it outranks the secondary type of the rows that
    /// open it, at either width.
    @Test func theSheetTitleOutranksTheRowThatOpensIt() {
        #expect(iOSEditorSheetMetrics.titleSize > CadenceTaskRowMetrics.regularWidth.secondaryFontSize)
        #expect(iOSEditorSheetMetrics.titleSize > CadenceTaskRowMetrics.compactWidth.secondaryFontSize)
    }

    // MARK: - Splitting into two columns

    /// Both calendar sheets had written these five widths down independently, byte for byte. The
    /// trailing column is the wider one because it is the one carrying the markdown well.
    @Test func theTwoColumnFormIsStatedOnce() {
        #expect(iOSEditorSheetMetrics.primaryColumnMinWidth == 340)
        #expect(iOSEditorSheetMetrics.primaryColumnMaxWidth == 440)
        #expect(iOSEditorSheetMetrics.secondaryColumnMinWidth == 360)
        #expect(iOSEditorSheetMetrics.secondaryColumnMaxWidth == 520)
        #expect(iOSEditorSheetMetrics.twoColumnMaxWidth == 980)
    }

    /// A column whose minimum exceeded its maximum would resolve to a fixed width and silently stop
    /// being a range — the failure mode a pile of loose literals invites.
    @Test func everyColumnRangeIsARange() {
        #expect(iOSEditorSheetMetrics.primaryColumnMinWidth < iOSEditorSheetMetrics.primaryColumnMaxWidth)
        #expect(iOSEditorSheetMetrics.secondaryColumnMinWidth < iOSEditorSheetMetrics.secondaryColumnMaxWidth)
        #expect(iOSEditorSheetMetrics.secondaryColumnMaxWidth > iOSEditorSheetMetrics.primaryColumnMaxWidth)
    }

    /// Both columns at their widest, plus the gap between them, must fit inside the cap — otherwise
    /// the cap is what sets the column widths and the two ranges above are decoration.
    @Test func bothColumnsFitInsideTheSheetsCap() {
        let widest = iOSEditorSheetMetrics.primaryColumnMaxWidth + iOSEditorSheetMetrics.secondaryColumnMaxWidth
        #expect(widest < iOSEditorSheetMetrics.twoColumnMaxWidth)
    }

    /// A gutter that ate into the content would stop being a margin and start being layout.
    @Test func theGutterNeverCrowdsTheColumns() {
        for isRegular in [true, false] {
            let gutter = iOSEditorSheetMetrics.gutter(isRegularWidth: isRegular)
            let narrowest = iOSEditorSheetMetrics.primaryColumnMinWidth
                + iOSEditorSheetMetrics.secondaryColumnMinWidth

            #expect(gutter > 0, "regular=\(isRegular)")
            #expect(gutter * 2 < narrowest, "regular=\(isRegular)")
        }
    }

    // MARK: - Sanity

    /// A zero anywhere in here draws as a collapsed sheet rather than as an error.
    @Test func everyMeasurementIsPositiveInIOSEditorSheetMetrics() {
        #expect(iOSEditorSheetMetrics.notesMinHeight > 0)
        #expect(iOSEditorSheetMetrics.groupSpacing > 0)
        #expect(iOSEditorSheetMetrics.cardPadding > 0)
        #expect(iOSEditorSheetMetrics.titleSize > 0)
        #expect(iOSEditorSheetMetrics.titleLineLimit > 0)
        #expect(iOSEditorSheetMetrics.primaryColumnMinWidth > 0)
        #expect(iOSEditorSheetMetrics.primaryColumnMaxWidth > 0)
        #expect(iOSEditorSheetMetrics.secondaryColumnMinWidth > 0)
        #expect(iOSEditorSheetMetrics.secondaryColumnMaxWidth > 0)
        #expect(iOSEditorSheetMetrics.twoColumnMaxWidth > 0)
    }

    // MARK: - One section style across the three calendar sheets (T-604)

    /// **The same "Schedule" group, drawn as two different components.** Quick-create built its
    /// groups with `iOSEditorSection(style: .ruled)` — hairline-separated rows on the sheet's own
    /// plate — while the event-edit and block-detail sheets took the `.card` default, so a reader
    /// moving between two sheets in one feature saw the identical Date / Start / Duration stack
    /// once as ruled rows and once as a raised card. All three are `.ruled` now, which is what
    /// `CadenceFieldSectionStyle.ruled`'s own doc asks for: *compact sheets where a stack of cards
    /// would read as a stack of unrelated boxes*.
    ///
    /// **The plate came with it, and had to.** `.ruled` draws no card of its own, so a ruled group
    /// needs a surface to be ruled *on*; quick-create and the task inspector both already framed
    /// their form in `cardPadding` inside `Theme.radiusPanel`. Converting the section style without
    /// that frame would have left the two sheets' fields lying directly on `Theme.bg` and the
    /// convergence unachieved — the Schedule group would still have read as two components, just
    /// two different ones. So the frame is pinned here beside the style.
    @Test func allThreeCalendarSheetsDrawRuledSections() throws {
        // The style's own contract, so the assertions below are about a decision and not a spelling.
        #expect(CadenceFieldSectionStyle.ruled != CadenceFieldSectionStyle.card)

        let sheets = [
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift": 6,
            "Cadence/iOS/iOSCalendarEventEditSheet.swift": 7,
            "Cadence/iOS/iOSCalendarBundleDetailSheet.swift": 3
        ]

        for (path, expected) in sheets {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))

            // Non-vacuity: the right file, past the comment stripper, still building sections.
            #expect(code.contains("iOSEditorSection("), "non-vacuity: \(path)")

            let sections = CadenceSourceScan.matchCount(#"iOSEditorSection\("#, in: code)
            let ruled = CadenceSourceScan.matchCount(#"style: \.ruled"#, in: code)
            #expect(
                sections == expected,
                "\(path) declares \(sections) sections, expected \(expected) — re-count before bumping"
            )
            #expect(
                ruled == sections,
                "\(path) draws \(sections) sections but only \(ruled) of them ruled"
            )
            #expect(
                CadenceSourceScan.matchCount(#"style: \.card"#, in: code) == 0,
                "\(path) still asks for a carded group"
            )

            // The frame a ruled form is ruled on, in the shared figures rather than three literals.
            #expect(
                code.contains("iOSEditorSheetMetrics.cardPadding"),
                "\(path) does not pad its form with the shared card padding"
            )
            #expect(
                code.contains("cornerRadius: Theme.radiusPanel"),
                "\(path) does not frame its ruled form at the shared panel radius"
            )
            #expect(
                code.contains("iOSEditorSheetMetrics.gutter(isRegularWidth:"),
                "\(path) does not inset its sheet by the shared gutter"
            )
            #expect(
                code.contains("iOSEditorSheetMetrics.groupSpacing"),
                "\(path) does not space its groups by the shared figure"
            )
        }

        // The detector is not blind: it separates the two spellings it has to tell apart.
        #expect(CadenceSourceScan.matchCount(#"style: \.ruled"#, in: "iOSEditorSection(title: nil, style: .ruled) {") == 1)
        #expect(CadenceSourceScan.matchCount(#"style: \.card"#, in: "iOSEditorSection(title: nil, style: .ruled) {") == 0)
        #expect(CadenceSourceScan.matchCount(#"iOSEditorSection\("#, in: "iOSEditorSection(title: \"Schedule\") {") == 1)
    }

    /// The one field each of the three sheets exists to fill in, read from one place. The block
    /// sheet drew its title at a literal 22 inside an inset well of `Theme.surfaceElevated` at 65%
    /// — legible only while the group sat on a card, and invisible once the group sat on the
    /// sheet's own elevated plate. It is a bare field at the shared size now, like its two
    /// siblings.
    @Test func theBlockSheetsTitleFieldJoinedTheSharedSubjectSize() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarBundleDetailSheet.swift")
        )
        #expect(code.contains("struct iOSCalendarBundleDetailSheet: View"))
        #expect(code.contains("size: iOSEditorSheetMetrics.titleSize, weight: .bold"))
        #expect(
            CadenceSourceScan.matchCount(#"Theme\.surfaceElevated\.opacity\(0\.65\)"#, in: code) == 0,
            "the block title still sits in a well that is its own plate at 65%"
        )
        #expect(
            CadenceSourceScan.matchCount(#"size: 22, weight: \.bold"#, in: code) == 0,
            "the block title still names its own size"
        )
    }

    // MARK: - Where the regular arm can actually be reached (T-731)

    /// **The `true` arm of `gutter(isRegularWidth:)` — the one figure on this enum that varies — is
    /// not reached on either target device, and what this pins is the *reason*, not the reading.**
    ///
    /// T-731 measured three note/event editors rendering their compact branch at 834pt and stopped
    /// there. The cause is not about those three: a plain `.sheet` on iPad is a form sheet, a form
    /// sheet is ~577pt wide however wide the host is, and UIKit hands anything that narrow a
    /// **compact** horizontal size class. So the arm is unreachable for every surface presented that
    /// way — which, at the time of writing, is **all seventeen files below**: the task inspector,
    /// both calendar sheets, both tracking editors, both AI review sheets, the shared note-editor
    /// header and the three editors T-731 named. Not three surfaces, all of them.
    ///
    /// Two things would wake it up, and this test watches for exactly those two:
    ///
    /// 1. **`.presentationSizing` or `.presentationDetents`.** Neither appears anywhere under
    ///    `Cadence/`, which is what makes "a plain `.sheet`" true rather than assumed.
    /// 2. **A `.fullScreenCover`.** A cover on iPad *is* regular width. There are two in this chain,
    ///    both named below, and both present `iOSNoteEditorCover` — the one note editor that reads
    ///    no size class and none of this enum's ramps.
    ///
    /// It deliberately does **not** assert that the regular branches still exist. Deleting them is
    /// one of the two resolutions T-731 leaves open, and a test that blocked it would be picking the
    /// other one. Widening a presentation is the change that has to be noticed, because it turns a
    /// branch nobody has ever seen into one every iPad draws.
    @Test func everySurfaceThatReadsTheEditorSheetRampsIsPresentedAsAPlainSheet() throws {
        /// Every file that reads a ramp on `iOSEditorSheetMetrics` with a live flag, plus every file
        /// that presents one of the views that do.
        let chain = [
            "Cadence/iOS/iOSAINoteActionsViews.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift",
            "Cadence/iOS/iOSCalendarInspectorView.swift",
            "Cadence/iOS/iOSCalendarMonthAgendaViews.swift",
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
            "Cadence/iOS/iOSCalendarView.swift",
            "Cadence/iOS/iOSCaptureRadialMenu.swift",
            "Cadence/iOS/iOSEventNoteEditorSheet.swift",
            "Cadence/iOS/iOSFeatureViews.swift",
            "Cadence/iOS/iOSMarkdownReferenceSupport.swift",
            "Cadence/iOS/iOSNoteEditorSheetHeader.swift",
            "Cadence/iOS/iOSNotesView.swift",
            "Cadence/iOS/iOSSearchView.swift",
            "Cadence/iOS/iOSTaskDetailSheet.swift",
            "Cadence/iOS/iOSTaskInspectorHost.swift",
            "Cadence/iOS/iOSTrackingEditorComponents.swift",
            "Cadence/iOS/iOSTrackingEditorSheets.swift"
        ]

        /// The two covers in the chain, and the single editor behind both of them.
        let coversOfTheNoteEditor = [
            "Cadence/iOS/iOSCaptureRadialMenu.swift",
            "Cadence/iOS/iOSNotesView.swift"
        ]

        /// Non-vacuity, per file: the thing that put it on the list. A presenter names the editor it
        /// presents; a declaration names the ramp it reads.
        let needles = [
            "Cadence/iOS/iOSAINoteActionsViews.swift": "iOSAISummaryReviewSheet(",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift": "iOSEventNoteEditorSheet(",
            "Cadence/iOS/iOSCalendarInspectorView.swift": "iOSCalendarEventEditSheet(",
            "Cadence/iOS/iOSCalendarMonthAgendaViews.swift": "iOSCalendarEventEditSheet(",
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift": "iOSEditorSheetMetrics.gutter(",
            "Cadence/iOS/iOSCalendarView.swift": "iOSCalendarQuickCreateSheet(",
            "Cadence/iOS/iOSCaptureRadialMenu.swift": "iOSCalendarQuickCreateSheet(",
            "Cadence/iOS/iOSEventNoteEditorSheet.swift": "iOSNoteEditorSheetHeader(",
            "Cadence/iOS/iOSFeatureViews.swift": "iOSHabitEditorSheet(",
            "Cadence/iOS/iOSMarkdownReferenceSupport.swift": "iOSLinkedNoteEditorSheet(",
            "Cadence/iOS/iOSNoteEditorSheetHeader.swift": "iOSEditorSheetMetrics.gutter(",
            "Cadence/iOS/iOSNotesView.swift": "iOSEventNoteEditorSheet(",
            "Cadence/iOS/iOSSearchView.swift": "iOSCalendarEventEditSheet(",
            "Cadence/iOS/iOSTaskDetailSheet.swift": "iOSTaskInspectorMetrics.sheetGutter(",
            "Cadence/iOS/iOSTaskInspectorHost.swift": "iOSTaskDetailSheet(",
            "Cadence/iOS/iOSTrackingEditorComponents.swift": "iOSEditorSheetMetrics.gutter(",
            "Cadence/iOS/iOSTrackingEditorSheets.swift": "iOSTrackingEditorShell("
        ]

        for path in chain {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))

            let needle = try #require(needles[path], "no non-vacuity needle for \(path)")
            #expect(code.contains(needle), "non-vacuity: \(path) no longer contains \(needle)")

            #expect(
                CadenceSourceScan.matchCount(#"presentationSizing"#, in: code) == 0,
                "\(path) asks for a sheet size — the regular ramp may now be live on iPad, re-read T-731"
            )
            #expect(
                CadenceSourceScan.matchCount(#"presentationDetents"#, in: code) == 0,
                "\(path) asks for sheet detents — re-measure the sheet's width before trusting T-731"
            )

            let covers = CadenceSourceScan.matchCount(#"\.fullScreenCover\("#, in: code)
            if coversOfTheNoteEditor.contains(path) {
                #expect(
                    covers == 1,
                    "\(path) presents \(covers) covers, not the one note-editor cover — re-read T-731"
                )
                #expect(
                    code.contains("iOSNoteEditorCover("),
                    "\(path)'s cover no longer presents the note editor"
                )
            } else {
                #expect(
                    covers == 0,
                    "\(path) presents an editor full-screen, which on iPad is regular width — re-read T-731"
                )
            }
        }

        // The one editor presented full-screen reads none of the ramps this enum owns, which is why
        // a cover in the chain is not a counterexample to the claim above.
        let notes = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNotesView.swift")
        )
        #expect(notes.contains("struct iOSNoteEditorCover: View"))
        #expect(
            CadenceSourceScan.matchCount(#"iOSEditorSheetMetrics\.gutter\("#, in: notes) == 0,
            "the full-screen note editor's file now reads the editor-sheet gutter ramp"
        )
        #expect(
            CadenceSourceScan.matchCount(#"iOSNoteEditorSheetHeader\("#, in: notes) == 0,
            "the full-screen note editor's file now draws the ramped editor-sheet header"
        )

        // The detector is not blind: it tells the two presentations apart, and sees the modifiers
        // whose absence the loop is asserting.
        #expect(CadenceSourceScan.matchCount(#"\.fullScreenCover\("#, in: ".sheet(item: $x) { }") == 0)
        #expect(CadenceSourceScan.matchCount(#"\.fullScreenCover\("#, in: ".fullScreenCover(item: $x) { }") == 1)
        #expect(CadenceSourceScan.matchCount(#"presentationSizing"#, in: ".presentationSizing(.page)") == 1)
        #expect(CadenceSourceScan.matchCount(#"presentationDetents"#, in: ".presentationDetents([.large])") == 1)
    }
}
