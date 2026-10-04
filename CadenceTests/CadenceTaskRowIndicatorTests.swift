import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// The three row indicator glyphs, as values (T-2058).
///
/// The owner asked for them by name — *"for tasks with subtasks, comments, and tags, show
/// corresponding icons after the title"* — and separately chose that the tag glyph **replaces** the
/// named tag chips on the row, accepting that you cannot see *which* tags without opening the task.
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

    /// **The behaviour the ticket names, and the one the mutation run breaks.** One fact lights one
    /// glyph, and the other two stay dark — which a test over a fully annotated task alone could
    /// not tell apart from "always draws three".
    @Test func aNoteAloneLightsExactlyTheNoteGlyph() {
        let noted = task(notes: "Rebalance before the quarter closes")

        #expect(CadenceTaskRowIndicatorSupport.indicators(for: noted) == [.notes])
        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: noted) == "Has notes")
    }

    /// The second and third unobliged rows, so reverting any one predicate to a constant leaves
    /// something red. A table with one row is a table that passes with the logic inverted.
    @Test func subtasksAloneAndTagsAloneLightExactlyTheirOwnGlyph() {
        #expect(CadenceTaskRowIndicatorSupport.indicators(for: task(subtasks: 2)) == [.subtasks])
        #expect(CadenceTaskRowIndicatorSupport.indicators(for: task(tags: ["work"])) == [.tags])

        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: task(subtasks: 2)) == "Has subtasks")
        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: task(tags: ["work"])) == "Has tags")
    }

    // MARK: - The notes predicate

    /// **`plainPreviewText(...).isEmpty`, not `notes.isEmpty`** — the predicate `iOSTaskRow`
    /// already draws its secondary line from. A notes field holding only markdown punctuation
    /// renders as nothing, so a glyph promising a note the row cannot show would be a lie the user
    /// has to open the task to catch.
    ///
    /// Each string here is non-empty as a `String` and empty as prose, which is exactly the gap
    /// `notes.isEmpty` cannot see.
    @Test func aNoteOfNothingButMarkdownPunctuationLightsNoGlyph() {
        for punctuation in ["---", "\n\n", "   ", "***"] {
            let task = task(notes: punctuation)
            #expect(!task.notes.isEmpty, "the fixture stopped being the case this test is about")
            #expect(
                CadenceTaskRowIndicatorSupport.indicators(for: task).isEmpty,
                "\(punctuation.debugDescription) lit the note glyph with nothing to show"
            )
        }

        // The control, same predicate, same call: real prose still lights it.
        #expect(CadenceTaskRowIndicatorSupport.hasNotes(task(notes: "# Heading\n\nbody")))
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
    /// disagree about which glyph comes first — and the order is the one in the owner's reference
    /// shot: note, checklist, tag.
    @Test func everyIndicatorLitKeepsTheOrderTheGlyphsAreDrawnIn() {
        let full = task(notes: "Check the fees", subtasks: 1, tags: ["finance", "home"])

        #expect(CadenceTaskRowIndicator.allCases == [.notes, .subtasks, .tags])
        #expect(CadenceTaskRowIndicatorSupport.indicators(for: full) == CadenceTaskRowIndicator.allCases)
        #expect(
            CadenceTaskRowIndicatorSupport.accessibilityLabel(for: full)
                == "Has notes, Has subtasks, Has tags"
        )
    }

    /// One element with one folded label, not three unlabelled images — the shape
    /// `CadenceSidebarLayout.rowAccessibilityLabel` uses, with the same `", "`. Pinned on the
    /// separator because that is the part a future edit is most likely to "tidy" into a `" "`.
    @Test func theIndicatorLabelFoldsItsPhrasesTheWayASidebarRowDoes() {
        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: []) == nil)
        #expect(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: [.notes, .tags])
                == "Has notes, Has tags")
        #expect(CadenceSidebarLayout.rowAccessibilityLabel("Today", count: nil) == "Today")
    }

    /// The symbols are the ones already in the tree rather than three new ones, and all three are
    /// distinct — a copy/paste that gave two indicators one glyph would otherwise ship silently.
    @Test func eachIndicatorCarriesItsOwnSymbolAlreadyInUseInThisApp() {
        #expect(CadenceTaskRowIndicator.notes.symbolName == "note.text")
        #expect(CadenceTaskRowIndicator.subtasks.symbolName == "checklist")
        #expect(CadenceTaskRowIndicator.tags.symbolName == "tag")
        #expect(Set(CadenceTaskRowIndicator.allCases.map(\.symbolName)).count
                == CadenceTaskRowIndicator.allCases.count)
    }

    // MARK: - Width: T-1720's bound gets easier, and here is the figure

    /// **The strip's widest possible width is a number, not an assurance.** T-1720's
    /// `CadenceTodayRowCrushUITests.Bound.titleShareOfItsOwnRow = 0.25` holds the title to a
    /// quarter of its own row, and anything new beside the title has to be accounted for against
    /// it. Three glyphs are a constant 48pt — every indicator lit, every row, every window width —
    /// where the three `CadenceTagChip`s they replaced were `maximumLabelWidth` apiece plus
    /// padding, which is name-dependent and far larger.
    @Test func theLitStripIsAConstantWidthAndSmallerThanTheChipsItReplaced() {
        // Both sides `CGFloat`, deliberately. Written as `== 3 * 14 + 2 * 3` this read `48.0 == 48
        // → false`: Swift typed the right-hand side `Int` and the comparison went through a
        // heterogeneous overload rather than failing to compile, so a *true* statement came back
        // red. Measured, not guessed — see the first run of this suite.
        #expect(
            CadenceTaskRowIndicatorStrip.maximumIntrinsicWidth
                == 3 * CadenceTaskRowIndicatorStrip.glyphWidth + 2 * CadenceTaskRowIndicatorStrip.spacing
        )
        #expect(CadenceTaskRowIndicatorStrip.maximumIntrinsicWidth == CGFloat(48))

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
    /// number after this change. Rebuilt here as a value rather than asserted in prose, so the
    /// claim fails if the seed ever gains one of the three.
    @Test func theRowCrushFixtureDrawsNoIndicatorGlyphsAtAll() {
        let crushed = AppTask(title: CadenceUITestScenarioSeed.Fixture.crushedTitle)
        crushed.scheduledDate = "2026-10-04"
        crushed.dueDate = "2026-08-14"
        crushed.estimatedMinutes = CadenceUITestScenarioSeed.Fixture.crushedEstimateMinutes

        #expect(CadenceTaskRowIndicatorSupport.indicators(for: crushed).isEmpty)
    }
}
