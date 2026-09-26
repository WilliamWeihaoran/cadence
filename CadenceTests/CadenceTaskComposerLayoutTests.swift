import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// The create-task sheet's height, held against the software keyboard.
///
/// This suite exists because a *comment* claiming the sheet fit was what shipped last time, and it
/// was wrong: the Tags row sat about 70pt under the fold on a 390pt phone. `CadenceTaskComposerLayout`
/// composes its answer from the same constants the sheet lays itself out with and from
/// `CadenceValueTileMetrics`, so if someone grows a tile or adds a field, the number moves and these
/// tests are what notice.
///
/// The device figures are **measured**, on iPhone 17e with the software keyboard actually raised:
/// its top edge at 508pt down a 844pt screen, and the sheet's scroll viewport starting ~118pt down.
/// They correct the 452pt this redesign was specified against, which subtracted a navigation bar
/// from the 508 but not the ~50pt a sheet is inset from the top of the screen.
@MainActor
struct CadenceTaskComposerLayoutTests {
    @Test("Every field clears the keyboard fold, section tile or not")
    func contentFitsAboveTheFold() {
        for showsSection in [false, true] {
            let height = CadenceTaskComposerLayout.contentHeight(showsSectionTile: showsSection)
            #expect(height <= CadenceTaskComposerLayout.keyboardVisibleContentHeight)
            #expect(CadenceTaskComposerLayout.slackBelowFold(showsSectionTile: showsSection) >= 0)
        }
    }

    /// The shape was chosen for a margin, not a squeak: anything that eats most of the headroom has
    /// undone the redesign even if it still technically fits. 40pt is most of a tile.
    @Test("The sheet keeps a real margin, not a hairline")
    func sheetKeepsHeadroom() {
        #expect(CadenceTaskComposerLayout.slackBelowFold() >= 40)
    }

    /// The point of putting the conditional field in the last row's spare half rather than on a row
    /// of its own: picking a list with sections must not push anything toward the keyboard.
    @Test("The section tile costs no height at all")
    func sectionTileCostsNoHeight() {
        #expect(CadenceTaskComposerLayout.contentHeight(showsSectionTile: true)
            == CadenceTaskComposerLayout.contentHeight(showsSectionTile: false))
        #expect(CadenceTaskComposerLayout.tileCount(showsSectionTile: true)
            - CadenceTaskComposerLayout.tileCount(showsSectionTile: false) == 1)
        // Six tiles across three rows of two is what makes that free.
        #expect(CadenceTaskComposerLayout.tileCount(showsSectionTile: true)
            == CadenceTaskComposerLayout.gridRowCount * 2)
    }

    /// The whole argument for tiles over rows, against the height the shape they replaced actually
    /// measured at. It did not fit; this has to, with room to spare.
    @Test("The grid is decisively shorter than the rows it replaced")
    func gridBeatsTheRowsItReplaced() {
        let rowsHeight = CadenceTaskComposerLayout.supersededRowLayoutHeight
        #expect(rowsHeight > CadenceTaskComposerLayout.keyboardVisibleContentHeight)
        #expect(CadenceTaskComposerLayout.contentHeight() < rowsHeight - 100)
    }

    /// The tile's own geometry is the sheet's input, so the two must not be able to drift.
    @Test("The sheet counts the tile the tile actually draws")
    func tileHeightComesFromTheTile() {
        #expect(CadenceTaskComposerLayout.tileHeight == CadenceValueTileMetrics.minHeight)
        // Caption line + gap + value line + padding both sides has to fit inside the tile, or the
        // frame's `minHeight` stops being what the tile measures.
        let intrinsic = 2 * CadenceValueTileMetrics.verticalPadding
            + 12
            + CadenceValueTileMetrics.captionValueSpacing
            + CadenceValueTileMetrics.valueFontSize + 3
        #expect(intrinsic <= CadenceValueTileMetrics.minHeight)
    }

    @Test("The stated device figures are the ones the fold is measured against")
    func deviceAssumptionsAreExplicit() {
        #expect(CadenceTaskComposerLayout.keyboardVisibleContentHeight
            == CadenceTaskComposerLayout.keyboardTopFromScreenTop
            - CadenceTaskComposerLayout.scrollViewportTop)
        // 844pt of screen less the 508pt the keyboard's top edge was measured at is a 336pt
        // keyboard, which is what an iPhone this size has.
        #expect(844 - CadenceTaskComposerLayout.keyboardTopFromScreenTop == 336)
    }
}

/// What each tile says, given what the draft currently holds.
///
/// A tile that only *displays* is the failure mode this sheet has already been caught in once, so
/// the labels are pinned here and the write-back is pinned by the view holding a `Binding` into
/// `CadenceTaskComposerFields` — there is no second copy of the value for a tile to render instead.
@MainActor
struct CadenceTaskComposerTileValueTests {
    @Test("A date tile names today and tomorrow and dates everything else")
    func dateValueLabels() {
        let today = DateFormatters.todayKey()
        let tomorrow = CadenceTaskComposerSupport.dateKey(for: .tomorrow)
        let farOff = "2031-03-04"

        #expect(CadenceTaskComposerSupport.dateValueLabel("") == "None")
        #expect(CadenceTaskComposerSupport.dateValueLabel(today) == "Today")
        #expect(CadenceTaskComposerSupport.dateValueLabel(tomorrow) == "Tomorrow")
        #expect(CadenceTaskComposerSupport.dateValueLabel(farOff) == DateFormatters.shortDateString(from: farOff))
    }

    /// Yesterday is a real answer for a due date and must not be swallowed by the "Today" branch.
    @Test("A past date is stated, not rounded to today")
    func pastDateIsStated() {
        let yesterday = CadenceTaskComposerSupport.dateKey(for: .today, from: Date().addingTimeInterval(-86_400))
        #expect(CadenceTaskComposerSupport.dateValueLabel(yesterday) == DateFormatters.shortDateString(from: yesterday))
    }

    /// The full-width tags tile spells two names; the half-width default spells one.
    @Test("The tags tile spells names up to its limit, then counts")
    func tagsValueLabelHonoursItsLimit() {
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: [], limit: 2) == "None")
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent"], limit: 2) == "urgent")
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent", "home"], limit: 2) == "urgent, home")
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent", "home", "errand"], limit: 2) == "3 tags")
        // The default is unchanged, so the row-era call sites still read the same.
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent", "home"]) == "2 tags")
        // A limit below one cannot make the label meaningless.
        #expect(CadenceTaskComposerSupport.tagsValueLabel(names: ["urgent"], limit: 0) == "urgent")
    }

    /// The section tile is full width *below* the grid precisely so that its appearing cannot move
    /// anything else; this pins the rule it appears by.
    @Test("The section tile appears only when there is something to choose")
    func sectionTileVisibility() {
        #expect(CadenceTaskComposerSupport.showsSectionRow(
            container: .inbox,
            availableSections: ["Default", "Doing"]
        ) == false)

        #expect(CadenceTaskComposerSupport.showsSectionRow(
            container: .area(UUID()),
            availableSections: [TaskSectionDefaults.defaultName]
        ) == false)

        #expect(CadenceTaskComposerSupport.showsSectionRow(
            container: .area(UUID()),
            availableSections: [TaskSectionDefaults.defaultName, "Doing"]
        ))
    }
}

/// The same sheet, at the text sizes it was never evaluated at (T-1364).
///
/// **The suite above is exactly the trap the audit names.** Every assertion in it is arithmetic over
/// constants at the default text size, and every one of them stays green while the composer clips:
/// `contentHeight()` would go on returning 342 with a 47pt title drawn inside a 52pt box. So this
/// suite asks the fold question again, once per `DynamicTypeSize`, and — more importantly — states
/// what the honest answer is when the answer stops being "it fits".
///
/// **It stops being "it fits", and that is the result rather than a failure.** A 390×844pt phone
/// gives a sheet about 390pt above a raised keyboard. Six fields at `accessibility5` need roughly
/// 730. No arrangement of them fits, so a test asserting they do would be a test asserting the
/// feature had not been built. What is asserted instead is the pair of properties that make the
/// screen usable anyway: the form fits **whole** at every non-accessibility size, and the field the
/// sheet opens focused on clears the keyboard at **every** size, so it never opens onto a blank
/// scroll position with the keyboard covering the only thing the user came here to type.
@MainActor
struct CadenceTaskComposerLargeTextLayoutTests {

    private let everySize = DynamicTypeSize.allCases

    /// The conversion has to be reviewable as a refactor, so the whole of the suite above has to
    /// still be describing what is drawn.
    @Test("At the default text size the sheet is the sheet the fold tests measured")
    func theComposerIsUnchangedAtTheDefaultTextSize() {
        for scaling in CadenceTypographyScaling.allCases {
            #expect(CadenceTaskComposerLayout.contentHeight(at: .large, scaling: scaling)
                == CadenceTaskComposerLayout.contentHeight())
            #expect(CadenceTaskComposerLayout.titleHeight(at: .large, scaling: scaling)
                == CadenceTaskComposerLayout.titleHeight)
            #expect(CadenceTaskComposerLayout.notesRestingHeight(at: .large, scaling: scaling)
                == CadenceTaskComposerLayout.notesRestingHeight)
            #expect(CadenceTaskComposerLayout.tileHeight(at: .large, scaling: scaling)
                == CadenceTaskComposerLayout.tileHeight)
        }
        #expect(CadenceTaskComposerLayout.slackBelowFold(at: .large, scaling: .enabled) >= 40)
    }

    /// An unconverted copy of this sheet — which is what every other form in the app still is —
    /// must be the same 342pt at `accessibility5`, or the migration boundary is not a boundary.
    @Test("Scaling off leaves the composer at its old height at every size")
    func anUnconvertedComposerDoesNotMove() {
        for size in everySize {
            #expect(CadenceTaskComposerLayout.contentHeight(at: size, scaling: .fixed)
                == CadenceTaskComposerLayout.contentHeight())
            #expect(CadenceTaskComposerLayout.fitsAboveFold(at: size, scaling: .fixed))
        }
    }

    @Test("Every block of the sheet grows with the reader's text size")
    func everyBlockOfTheComposerGrows() {
        var previousContent: CGFloat = 0
        for size in everySize {
            let content = CadenceTaskComposerLayout.contentHeight(at: size, scaling: .enabled)
            #expect(content >= previousContent, "content height went backwards at \(size)")
            previousContent = content
        }

        let big = DynamicTypeSize.accessibility5
        #expect(CadenceTaskComposerLayout.titleHeight(at: big, scaling: .enabled)
            > CadenceTaskComposerLayout.titleHeight)
        #expect(CadenceTaskComposerLayout.notesRestingHeight(at: big, scaling: .enabled)
            > CadenceTaskComposerLayout.notesRestingHeight)
        #expect(CadenceTaskComposerLayout.tileHeight(at: big, scaling: .enabled)
            > CadenceTaskComposerLayout.tileHeight)
        #expect(CadenceTaskComposerLayout.suggestionHeight(at: big, scaling: .enabled)
            > CadenceTaskComposerLayout.suggestionHeight)

        // Each field's box is at least the line of text drawn inside it plus its own padding, which
        // is the property that separates "grew" from "stopped clipping".
        for size in everySize {
            let titleLine = CadenceTypeScale.lineHeight(.composerTitle, at: size, scaling: .enabled)
            let notesLine = CadenceTypeScale.lineHeight(.bodyText, at: size, scaling: .enabled)
            let padding: CGFloat = 2 * CadenceTaskComposerLayout.fieldPadding
            #expect(CadenceTaskComposerLayout.titleHeight(at: size, scaling: .enabled) >= titleLine + padding)
            #expect(CadenceTaskComposerLayout.notesRestingHeight(at: size, scaling: .enabled) >= notesLine + padding)
        }
    }

    /// The boundary, asserted at both ends rather than only at the end that passes.
    @Test("The whole form clears the keyboard up to the accessibility sizes, and not past them")
    func theFoldHoldsUntilTheAccessibilitySizes() {
        for size in everySize {
            let fits = CadenceTaskComposerLayout.fitsAboveFold(at: size, scaling: .enabled)
            if CadenceTypeScale.isAccessibilitySize(size) {
                #expect(fits == false,
                        "\(size) is claimed to fit above the keyboard; six fields at that size do not")
            } else {
                #expect(fits, "\(size) no longer fits, which is a regression in the default experience")
            }
        }
        // Once it stops fitting it stays stopped: a non-monotonic answer here would mean some
        // block shrank as the text grew.
        #expect(CadenceTaskComposerLayout.slackBelowFold(at: .accessibility5, scaling: .enabled)
            < CadenceTaskComposerLayout.slackBelowFold(at: .accessibility1, scaling: .enabled))
    }

    /// The invariant that has to hold everywhere, and the one an "it just scrolls" answer drops.
    @Test("The field the sheet opens focused on clears the keyboard at every size")
    func theFocusedTitleAlwaysClearsTheFold() {
        for size in everySize {
            #expect(CadenceTaskComposerLayout.titleClearsFold(at: size, scaling: .enabled),
                    "the title field is under the keyboard at \(size), so the sheet opens on nothing")
        }
        // With real room left over, not by a hairline: the notes field under it should be reachable
        // with one short scroll rather than a full screen of it.
        #expect(CadenceTaskComposerLayout.keyboardVisibleContentHeight
            - CadenceTaskComposerLayout.contentTopPadding
            - CadenceTaskComposerLayout.titleHeight(at: .accessibility5, scaling: .enabled) > 200)
    }
}
