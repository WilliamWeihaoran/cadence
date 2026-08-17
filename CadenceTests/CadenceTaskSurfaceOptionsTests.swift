import Foundation
import Testing
@testable import Cadence

/// iPhone Today shipped with no sort chip and no way to show Completed while iPad Today had both,
/// and the compact view still *read* `showCompleted` — a binding nothing on screen could write.
/// The options a surface offers are now stated once, per surface, with no size class involved;
/// these pin that they stay stated once.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so what can be
/// asserted here is the value both widths read. That is deliberately where the decision lives.
struct CadenceTaskSurfaceOptionsTests {
    @Test func todayOffersBothControlsJustLikeEveryOtherTaskSurface() {
        let today = CadenceTaskSurfaceOptions.options(for: .today)

        #expect(today.showsSort)
        #expect(today.showsCompletedToggle)
    }

    /// The sweep's actual claim: no surface is a special case, so no *width* of a surface can be
    /// one either. If a future surface earns an exception it will fail here, which is the point —
    /// the exception has to be written down for both widths at once.
    @Test func everyTaskSurfaceOffersTheSameChromeControls() {
        for surface in CadenceTaskSurface.allCases {
            let options = CadenceTaskSurfaceOptions.options(for: surface)

            #expect(options.showsSort, "\(surface.rawValue) lost its sort control")
            #expect(options.showsCompletedToggle, "\(surface.rawValue) lost its completed toggle")
        }
    }

    // MARK: - The list chip

    /// Every Inbox row carried a chip reading "Inbox" — the chip's job is to say which list a task
    /// is in, and on the Inbox page the answer is the page title. It started rendering for
    /// container-less tasks for a good reason (otherwise the tasks most in need of filing were the
    /// only ones that could not be filed from their row); that reason is about the row, and this is
    /// where it does not apply.
    @Test func theInboxDoesNotNameItselfOnEveryRow() {
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .inbox) == false)
        #expect(CadenceTaskSurfaceOptions.options(for: .inbox).showsContainerChip == false)
    }

    /// The same defect one screen over: a list's own Tasks tab would name that list on every row.
    /// It was already passing `false` at both widths by hand; this is what stops the hand-written
    /// answer and the table's answer drifting apart.
    @Test func aListsOwnPageDoesNotNameItselfOnEveryRow() {
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .listDetail) == false)
    }

    /// The mixed surfaces keep it. Today and All Tasks draw rows from every list at once, so the
    /// chip is both the answer to "which list" and the control for changing it — suppressing it
    /// there would be the regression the chip was added to fix.
    @Test func theSurfacesThatMixListsStillNameThem() {
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .today))
        #expect(CadenceTaskSurfaceOptions.showsContainerChip(on: .allTasks))
    }

    /// The point of putting this in `Shared/`: a surface has **one** answer, which both the compact
    /// and the regular layout of that surface read. `Cadence/iOS/` is invisible to this target, so
    /// what is pinned here is that there is only one value to read.
    @Test func everySurfaceHasExactlyOneAnswerForTheListChip() {
        for surface in CadenceTaskSurface.allCases {
            #expect(
                CadenceTaskSurfaceOptions.options(for: surface).showsContainerChip
                    == CadenceTaskSurfaceOptions.showsContainerChip(on: surface),
                "\(surface.rawValue) reports the list chip two different ways"
            )
        }
    }

    // MARK: - The completed cap

    /// Today, Inbox and list detail capped their completed list at 12 while All Tasks capped it at
    /// 24, so the same finished task was listed on one screen and silently dropped on another.
    @Test func theCompletedListIsCappedAtOneSharedLimit() {
        let tasks = Array(0..<200)

        #expect(CadenceTaskSurfaceOptions.completedRows(from: tasks).count == CadenceTaskSurfaceOptions.completedRowLimit)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: tasks) == Array(0..<CadenceTaskSurfaceOptions.completedRowLimit))
    }

    /// The cap must never *add* to, reorder, or drop from a list that is already short enough —
    /// the completed section on a quiet day is a handful of rows and has to be all of them.
    @Test func aShorterCompletedListIsPassedThroughUntouched() {
        #expect(CadenceTaskSurfaceOptions.completedRows(from: [Int]()).isEmpty)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: [7, 3, 9]) == [7, 3, 9])

        let exactlyAtTheLimit = Array(0..<CadenceTaskSurfaceOptions.completedRowLimit)
        #expect(CadenceTaskSurfaceOptions.completedRows(from: exactlyAtTheLimit) == exactlyAtTheLimit)
    }

    /// The limit is the larger of the two that shipped, so unifying could not hide work a screen
    /// used to show.
    @Test func theSharedLimitIsNoSmallerThanEitherCapItReplaced() {
        #expect(CadenceTaskSurfaceOptions.completedRowLimit >= 24)
    }
}

/// Copy that appears on more than one screen. Each of these was written out at both call sites and
/// drifted; the constants are what stop a third spelling appearing.
struct CadenceEmptyStateCopyTests {
    /// The iPad spelling read "on iPad or Mac", omitting the device most of these rows are read on.
    @Test func theAllTasksEmptyStateNamesEveryPlatformTheAppRunsOn() {
        for platform in ["iPhone", "iPad", "Mac"] {
            #expect(
                CadenceEmptyStateCopy.allTasksSubtitle.contains(platform),
                "\(platform) is missing from the All Tasks empty state"
            )
        }
    }

    @Test func sharedEmptyStateCopyIsPresentAndDistinct() {
        let subtitles = [
            CadenceEmptyStateCopy.inboxSubtitle,
            CadenceEmptyStateCopy.allTasksSubtitle,
            CadenceEmptyStateCopy.focusSubtitle
        ]

        #expect(subtitles.allSatisfy { !$0.isEmpty })
        #expect(Set(subtitles).count == subtitles.count)
    }
}
