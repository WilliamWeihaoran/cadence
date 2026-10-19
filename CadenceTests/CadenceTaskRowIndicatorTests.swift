import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// The row indicator glyphs, as values (T-2058, revised by [[T-3231]]).
///
/// The owner asked for them by name — *"for tasks with subtasks, comments, and tags, show
/// corresponding icons after the title"* — and separately chose that the tag glyph **replaces** the
/// named tag chips on the row, accepting that you cannot see *which* tags without opening the task.
///
/// **There were three and there are two: the `note.text` glyph came off both rows in [[T-3231]].**
/// The assertions below are re-pointed, not relaxed — the "a note alone lights exactly the note
/// glyph" case is now "a note alone lights NOTHING", which is a stronger statement about the same
/// input and still fails if `indicators(for:)` is reverted to a constant. The glyph went because
/// both rows now print the notes: iOS always did, macOS gained the excerpt in [[T-1467]]
/// (`MacTaskRow.inlineDetail`), which is the precondition [[T-3196]] gated the drop on.
///
/// Everything here is a fact about an `AppTask`, which is the whole reason
/// `CadenceTaskRowIndicatorSupport` was split out of the view: `Cadence/iOS/` is inside
/// `#if os(iOS)` and this target builds for macOS, so a predicate living in `iOSTaskRow` would have
/// been untestable on the platform that reported it. The two rows' *call sites* are pinned
/// separately, by `CadenceTodayUnificationTests.bothRowsReplaceTheirTagChipsWithTheSharedIndicatorGlyphs`.
struct CadenceTaskRowIndicatorTests {

    // MARK: - Fixtures

    private func task(
        notes: String = "",
        subtasks: Int = 0,
        finishedSubtasks: Int = 0,
        tags: [String] = []
    ) -> AppTask {
        let task = AppTask(title: "Update investment tracker")
        task.notes = notes
        let open = (0..<subtasks).map { index -> Subtask in
            let subtask = Subtask(title: "open \(index)")
            subtask.order = index
            return subtask
        }
        let done = (0..<finishedSubtasks).map { index -> Subtask in
            let subtask = Subtask(title: "done \(index)")
            subtask.order = subtasks + index
            subtask.isDone = true
            return subtask
        }
        let all = open + done
        task.subtasks = all.isEmpty ? nil : all
        task.tags = tags.isEmpty ? nil : tags.map { Tag(name: $0) }
        return task
    }

    // MARK: - One fact, one glyph

    /// The floor. A task with none of the three says nothing and, crucially, adds **no**
    /// accessibility element — `CadenceSidebarLayout.badge`'s call about ", 0", one surface along.
    @Test func aTaskWithNoneOfTheThreeDrawsNothingAndSaysNothing() {
        let bare = task()

        #expect(CadenceTaskRowIndicatorSupport.indicators(for: bare).isEmpty)
        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: bare) == nil)
    }

    /// **The behaviour [[T-3231]] names.** This test asserted `== [.notes]` while the glyph
    /// existed; it now asserts that a task carrying real prose and nothing else draws **no** glyph
    /// and adds **no** accessibility element. That is the removal stated as a behaviour rather
    /// than as an absent enum case, so putting `case notes` back goes red here as well as in
    /// `everyIndicatorLitKeepsTheOrderTheGlyphsAreDrawnIn`.
    ///
    /// **The fact is not lost, and this names where it went:** the notes are printed on both rows
    /// now, off the same `plainPreviewText` the retired predicate asked, so the control below is
    /// that the *preview* is non-empty on the very input that used to light the glyph. A reading
    /// that merely deleted the glyph without the excerpt would fail that line.
    @Test func aNoteAloneLightsNoGlyphBecauseBothRowsNowPrintTheNote() {
        let noted = task(notes: "Rebalance before the quarter closes")

        #expect(CadenceTaskRowIndicatorSupport.indicators(for: noted).isEmpty)
        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: noted) == nil)

        // The replacement, measured rather than asserted in prose: the text both rows draw is
        // non-empty for this task, at both tiers' limits.
        for metrics in [CadenceTaskRowMetrics.desktop, .regularWidth, .compactWidth] {
            #expect(
                !CadenceTaskPresentationSupport.plainPreviewText(
                    from: noted.notes,
                    limit: metrics.notesPreviewLimit
                ).isEmpty,
                "the row that replaced the glyph must still have something to print"
            )
        }
    }

    /// The two unobliged rows, so reverting either predicate to a constant leaves something red. A
    /// table with one row is a table that passes with the logic inverted.
    @Test func subtasksAloneAndTagsAloneLightExactlyTheirOwnGlyph() {
        #expect(CadenceTaskRowIndicatorSupport.indicators(for: task(subtasks: 2)) == [.subtasks])
        #expect(CadenceTaskRowIndicatorSupport.indicators(for: task(tags: ["work"])) == [.tags])

        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: task(subtasks: 2)) == "Has subtasks")
        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: task(tags: ["work"])) == "Has tags")
    }

    // MARK: - Notes are content now, not a glyph

    /// **Where `hasNotes` went, and why nothing regressed with it ([[T-3231]]).**
    ///
    /// This test guarded the glyph's predicate: `plainPreviewText(...).isEmpty` rather than
    /// `notes.isEmpty`, so a notes field holding only markdown punctuation lit nothing. The glyph
    /// is gone and the predicate with it — but the *case it protected* is not retired, it moved
    /// one layer up into the rows' own excerpt, which asks the same parser. So the same table runs
    /// against the thing that draws now.
    ///
    /// Each string here is non-empty as a `String` and empty as prose, which is exactly the gap
    /// `notes.isEmpty` cannot see. The glyph could never promise a note the row would not show;
    /// the excerpt cannot either, for the same reason, and that is the whole argument for dropping
    /// one in favour of the other.
    @Test func aNoteOfNothingButMarkdownPunctuationPrintsNothingAndLightsNothing() {
        for punctuation in ["---", "\n\n", "   ", "***"] {
            let task = task(notes: punctuation)
            #expect(!task.notes.isEmpty, "the fixture stopped being the case this test is about")
            #expect(
                CadenceTaskRowIndicatorSupport.indicators(for: task).isEmpty,
                "\(punctuation.debugDescription) lit a glyph with nothing to show"
            )
            // Both tiers, because the two rows read different limits off the same parser.
            for metrics in [CadenceTaskRowMetrics.desktop, .regularWidth, .compactWidth] {
                #expect(
                    CadenceTaskPresentationSupport.plainPreviewText(
                        from: task.notes,
                        limit: metrics.notesPreviewLimit
                    ).isEmpty,
                    "\(punctuation.debugDescription) would have drawn a blank notes line"
                )
            }
        }

        // The control, same parser, same call: real prose still has something to print.
        #expect(!CadenceTaskPresentationSupport.plainPreviewText(
            from: task(notes: "# Heading\n\nbody").notes,
            limit: CadenceTaskRowMetrics.desktop.notesPreviewLimit
        ).isEmpty)
    }

    // MARK: - The subtask predicate is not the row list's

    /// **A finished checklist is still a checklist.** `CadenceTaskPresentationSupport.listedSubtasks`
    /// answers `[]` for a settled task and for one whose boxes are all ticked — right for a row
    /// that lists *what is left*, wrong for a glyph that answers *is there a checklist here*.
    /// Reading the row list's answer would make the glyph vanish the moment you tick the last box.
    @Test func aChecklistWithEveryBoxTickedStillLightsTheSubtaskGlyph() {
        let finished = task(subtasks: 0, finishedSubtasks: 3)

        #expect(CadenceTaskPresentationSupport.listedSubtasks(for: finished).isEmpty,
                "non-vacuity: the two predicates have stopped disagreeing, so this proves nothing")
        #expect(CadenceTaskRowIndicatorSupport.indicators(for: finished) == [.subtasks])
    }

    // MARK: - Order and label

    /// `allCases` is the draw order and the speaking order, so the row and VoiceOver cannot
    /// disagree about which glyph comes first — and the order is the owner's reference shot's,
    /// minus the note glyph [[T-3231]] retired: checklist, tag.
    ///
    /// **This is the exact-equality line that makes the removal a guard rather than a deletion.**
    /// `allCases` is stated as a whole list, so re-adding `case notes` — in any position — fails
    /// here, in `aNoteAloneLightsNoGlyphBecauseBothRowsNowPrintTheNote`, in the label below and in
    /// the width figure. The fixture still carries notes, deliberately: a task with all three
    /// facts must draw exactly two glyphs, which is a stronger statement than one built from a
    /// task that has no notes to ignore.
    @Test func everyIndicatorLitKeepsTheOrderTheGlyphsAreDrawnIn() {
        let full = task(notes: "Check the fees", subtasks: 1, tags: ["finance", "home"])

        #expect(CadenceTaskRowIndicator.allCases == [.subtasks, .tags])
        #expect(CadenceTaskRowIndicatorSupport.indicators(for: full) == CadenceTaskRowIndicator.allCases)
        #expect(
            CadenceTaskRowIndicatorSupport.accessibilityLabel(for: full)
                == "Has subtasks, Has tags"
        )
        // Non-vacuity on the notes half: the fixture really does carry notes the retired glyph
        // would have lit, so the two-element answer above is a statement about this change.
        #expect(!CadenceTaskPresentationSupport.plainPreviewText(
            from: full.notes,
            limit: CadenceTaskRowMetrics.desktop.notesPreviewLimit
        ).isEmpty)
    }

    /// One element with one folded label, not three unlabelled images — the shape
    /// `CadenceSidebarLayout.rowAccessibilityLabel` uses, with the same `", "`. Pinned on the
    /// separator because that is the part a future edit is most likely to "tidy" into a `" "`.
    @Test func theIndicatorLabelFoldsItsPhrasesTheWayASidebarRowDoes() {
        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: []) == nil)
        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: [.subtasks, .tags])
                == "Has subtasks, Has tags")
        #expect(CadenceSidebarLayout.rowAccessibilityLabel("Today", count: nil) == "Today")
    }

    /// The symbols are the ones already in the tree rather than new ones, and they are distinct —
    /// a copy/paste that gave two indicators one glyph would otherwise ship silently.
    ///
    /// **`note.text` is asserted ABSENT here rather than simply dropped from the list** ([[T-3231]]),
    /// because that symbol is still very much in this app — it names the NOTES FEATURE at
    /// `CadenceFeatureDestination.swift:201`, `iPadTodaySupportViews.swift:158`,
    /// `iOSSearchSupportViews.swift:32` and `FocusNotesPanel.swift:14`. A grep for the string
    /// would therefore keep finding it forever; only a statement about *this* vocabulary can say
    /// the task row stopped using it.
    @Test func eachIndicatorCarriesItsOwnSymbolAlreadyInUseInThisApp() {
        #expect(!CadenceTaskRowIndicator.allCases.map(\.symbolName).contains("note.text"))
        #expect(!CadenceTaskRowIndicator.allCases.map(\.accessibilityPhrase).contains("Has notes"))
        #expect(CadenceTaskRowIndicator.subtasks.symbolName == "checklist")
        #expect(CadenceTaskRowIndicator.tags.symbolName == "tag")
        #expect(Set(CadenceTaskRowIndicator.allCases.map(\.symbolName)).count
                == CadenceTaskRowIndicator.allCases.count)
    }

    // MARK: - Width: T-1720's bound gets easier, and here is the figure

    /// **The strip's widest possible width is a number, not an assurance.** T-1720's
    /// `CadenceTodayRowCrushUITests.Bound.titleShareOfItsOwnRow = 0.25` holds the title to a
    /// quarter of its own row, and anything new beside the title has to be accounted for against
    /// it. Two glyphs are a constant 31pt — every indicator lit, every row, every window width —
    /// where the three `CadenceTagChip`s they replaced were `maximumLabelWidth` apiece plus
    /// padding, which is name-dependent and far larger.
    ///
    /// **48pt -> 31pt is [[T-3231]], and the figure is re-stated rather than relaxed.** Losing a
    /// glyph makes T-1720's bound strictly easier to hold, so no UI bound moves; this assertion
    /// exists so the *number* stays a thing a test reads rather than a thing that drifts with the
    /// case list.
    @Test func theLitStripIsAConstantWidthAndSmallerThanTheChipsItReplaced() {
        // Both sides `CGFloat`, deliberately. Written as `== 2 * 14 + 1 * 3` this would read
        // `31.0 == 31 → false`: Swift types the right-hand side `Int` and the comparison goes
        // through a heterogeneous overload rather than failing to compile, so a *true* statement
        // comes back red. Measured, not guessed — see the first run of this suite.
        #expect(
            CadenceTaskRowIndicatorStrip.maximumIntrinsicWidth
                == 2 * CadenceTaskRowIndicatorStrip.glyphWidth + 1 * CadenceTaskRowIndicatorStrip.spacing
        )
        #expect(CadenceTaskRowIndicatorStrip.maximumIntrinsicWidth == CGFloat(31))
        // The derivation, not just the total: the width is a function of the case list, so a
        // returning case moves it and this says by how much.
        #expect(CadenceTaskRowIndicator.allCases.count == 2)

        // The comparison, over the chip's own published figures rather than over an estimate: one
        // compact chip at its widest already costs more than the entire three-glyph strip.
        let chip = CadenceTagChipStyle(size: .compact, isArchived: false)
        let oneChipAtItsWidest = chip.maximumLabelWidth + chip.horizontalPadding * 2 + chip.dotDiameter
        #expect(oneChipAtItsWidest > CadenceTaskRowIndicatorStrip.maximumIntrinsicWidth,
                "one tag chip is \(oneChipAtItsWidest)pt against a \(CadenceTaskRowIndicatorStrip.maximumIntrinsicWidth)pt strip")
    }

    /// **And T-1720's own fixture does not move at all.** `CadenceUITestScenarioSeed` plants the
    /// crushed row with a title, a do date, a due date and an estimate — and **no notes, no
    /// subtasks and no tags** — so it draws zero glyphs and the 0.42 that run measured is the same
    /// number after this change, and after [[T-3231]]'s removal too: a row that drew none of them
    /// cannot draw one fewer. Rebuilt here as a value rather than asserted in prose, so the claim
    /// fails if the seed ever gains one.
    @Test func theRowCrushFixtureDrawsNoIndicatorGlyphsAtAll() {
        let crushed = AppTask(title: CadenceUITestScenarioSeed.Fixture.crushedTitle)
        crushed.scheduledDate = "2026-10-04"
        crushed.dueDate = "2026-08-14"
        crushed.estimatedMinutes = CadenceUITestScenarioSeed.Fixture.crushedEstimateMinutes

        #expect(CadenceTaskRowIndicatorSupport.indicators(for: crushed).isEmpty)
    }
}
