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
    @Test func everyTaskSurfaceOffersTheSameOptions() {
        let today = CadenceTaskSurfaceOptions.options(for: .today)

        for surface in CadenceTaskSurface.allCases {
            #expect(
                CadenceTaskSurfaceOptions.options(for: surface) == today,
                "\(surface.rawValue) diverged from the shared task-surface options"
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
