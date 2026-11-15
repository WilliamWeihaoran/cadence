#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// Covers the shared highlight-index math used by `ContainerPickerBadge`,
/// `TaskSectionPickerBadge`, and the CreateTaskSheet tilde (`~`) inline pickers —
/// specifically the edge cases raised by fast typing (query changes shrinking the
/// filtered list out from under the current index) and an empty results list.
@MainActor
struct TaskPickerHighlightSupportTests {

    // MARK: - clampedIndex

    @Test func clampedIndexReturnsZeroForAnEmptyList() {
        #expect(TaskPickerHighlightSupport.clampedIndex(0, count: 0) == 0)
        #expect(TaskPickerHighlightSupport.clampedIndex(4, count: 0) == 0)
        #expect(TaskPickerHighlightSupport.clampedIndex(-1, count: 0) == 0)
    }

    @Test func clampedIndexNeverGoesNegative() {
        #expect(TaskPickerHighlightSupport.clampedIndex(-3, count: 5) == 0)
    }

    @Test func clampedIndexNeverExceedsLastValidRow() {
        #expect(TaskPickerHighlightSupport.clampedIndex(99, count: 5) == 4)
    }

    @Test func clampedIndexHandlesAFastTypedQueryThatShrinksTheListBelowTheCurrentIndex() {
        // e.g. highlight was on row 4 of 5, then a fast keystroke narrows the
        // filtered list down to 2 rows before the index gets reset.
        #expect(TaskPickerHighlightSupport.clampedIndex(4, count: 2) == 1)
    }

    // MARK: - clampedMovedIndex (ContainerPickerBadge / TaskSectionPickerBadge arrow nav)

    @Test func clampedMovedIndexStopsAtTheFirstRowGoingUp() {
        #expect(TaskPickerHighlightSupport.clampedMovedIndex(0, by: -1, count: 5) == 0)
    }

    @Test func clampedMovedIndexStopsAtTheLastRowGoingDown() {
        #expect(TaskPickerHighlightSupport.clampedMovedIndex(4, by: 1, count: 5) == 4)
    }

    @Test func clampedMovedIndexAdvancesNormallyWithinBounds() {
        #expect(TaskPickerHighlightSupport.clampedMovedIndex(1, by: 1, count: 5) == 2)
        #expect(TaskPickerHighlightSupport.clampedMovedIndex(1, by: -1, count: 5) == 0)
    }

    @Test func clampedMovedIndexOnAnEmptyListStaysAtZeroInEitherDirection() {
        #expect(TaskPickerHighlightSupport.clampedMovedIndex(0, by: 1, count: 0) == 0)
        #expect(TaskPickerHighlightSupport.clampedMovedIndex(0, by: -1, count: 0) == 0)
    }

    @Test func clampedMovedIndexRecoversWhenTheListShrankBelowTheStoredIndex() {
        // Highlight was at row 6; the list shrank to 3 rows from a rapid query
        // change. The very next arrow press must land on a valid row, not walk
        // off into an out-of-range index.
        #expect(TaskPickerHighlightSupport.clampedMovedIndex(6, by: -1, count: 3) == 1)
        #expect(TaskPickerHighlightSupport.clampedMovedIndex(6, by: 1, count: 3) == 2)
    }

    // MARK: - wrappedMovedIndex (tilde `~` list/section pickers, Cmd+Shift+=/-)

    @Test func wrappedMovedIndexCyclesPastTheEndBackToTheStart() {
        #expect(TaskPickerHighlightSupport.wrappedMovedIndex(4, by: 1, count: 5) == 0)
    }

    @Test func wrappedMovedIndexCyclesPastTheStartBackToTheEnd() {
        #expect(TaskPickerHighlightSupport.wrappedMovedIndex(0, by: -1, count: 5) == 4)
    }

    @Test func wrappedMovedIndexOnAnEmptyListStaysAtZero() {
        #expect(TaskPickerHighlightSupport.wrappedMovedIndex(0, by: 1, count: 0) == 0)
        #expect(TaskPickerHighlightSupport.wrappedMovedIndex(0, by: -1, count: 0) == 0)
    }

    @Test func wrappedMovedIndexRecoversWhenTheListShrankBelowTheStoredIndex() {
        // Same fast-typing scenario as the clamped variant, but for the cycling
        // (tilde picker) flavor: an out-of-range starting index must still land
        // on a valid row instead of producing a negative modulo or crashing.
        #expect(TaskPickerHighlightSupport.wrappedMovedIndex(6, by: 1, count: 3) == 0)
        #expect(TaskPickerHighlightSupport.wrappedMovedIndex(6, by: -1, count: 3) == 1)
    }
}
/// **[[T-17465]]: the Mac section picker's search field.** It matched `hasPrefix` on the raw,
/// untrimmed field, so a stray space hid every section, and a miss drew nothing at all under the
/// field. It now reads the field by the list picker's rule -- trimmed, case-insensitive, prefix.
@MainActor
struct TaskSectionPickerFilterTests {
    private let sections = ["Default", "Code Review", "Backlog", "Blocked"]

    @Test func surroundingWhitespaceIsIgnored() {
        #expect(TaskSectionPickerBadge.filteredSections(sections, query: "  back ") == ["Backlog"])
        #expect(TaskSectionPickerBadge.filteredSections(sections, query: " b") == ["Backlog", "Blocked"])
        #expect(TaskSectionPickerBadge.filteredSections(sections, query: "   ") == sections)
    }

    @Test func caseIsFolded() {
        #expect(TaskSectionPickerBadge.filteredSections(sections, query: "CODE") == ["Code Review"])
    }

    @Test func aBlankFieldListsEverySectionInOrder() {
        #expect(TaskSectionPickerBadge.filteredSections(sections, query: "") == sections)
    }

    /// The list chip beside this one matches by prefix on purpose (`CadenceTaskComposerSupport
    /// .matchesQuery`); the two chips must agree about what a query finds.
    @Test func itMatchesByTheListPickersRule() {
        for query in ["review", "co", " de", "lock", "B", "x"] {
            let expected = sections.filter { ContainerPickerFilterSupport.matches($0, query: query) }
            #expect(TaskSectionPickerBadge.filteredSections(sections, query: query) == expected, "\(query)")
        }
    }

    @Test func aMissSaysSoInWords() throws {
        #expect(TaskSectionPickerBadge.filteredSections(sections, query: "zzz").isEmpty)
        #expect(TaskSectionPickerBadge.noMatchesText == "No matching sections")
        let view = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelSupportViews.swift"))
        #expect(view.contains("if filteredSections.isEmpty {"), "the popover draws nothing for a miss again")
        #expect(view.contains("Text(Self.noMatchesText)"))
    }
}

#endif
