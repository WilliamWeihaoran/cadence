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
#endif
