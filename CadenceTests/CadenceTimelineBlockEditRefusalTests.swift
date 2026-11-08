// macOS-only: the Mac canvas's support types (`TimelineDayCanvasStateSupport`,
// `TimelineTaskBlockInteractionSupport`, `SchedulingActions`) do not exist on iOS. The iOS half
// is read from source, which needs no platform.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-13301]]: a refused timeline move or resize says so on the Mac, as it already did on iOS,
/// and a refused drop onto a timeline says so on both.
///
/// The Mac's move is a drop (`SchedulingActions.commitDropTask`) and its resize ends in
/// `TimelineTaskBlockInteractionSupport.commitResize`. Both have answered whether they landed since
/// [[T-4970]], and both answers were discarded, so the block went back to where it started without
/// a word, while the iOS grid drew `CadencePendingChangePersistence.editFailureNotice` above the
/// canvas for the same refusal. The iOS drop's `Bool` was likewise returned by both hosts and
/// thrown away by the column's drop delegate.
@MainActor
struct CadenceTimelineBlockEditRefusalTests {
    private struct CommitRefused: Error {}

    private func scheduledTask(in context: ModelContext) throws -> AppTask {
        let task = AppTask(title: "Deep work")
        task.scheduledDate = "2026-06-01"
        task.scheduledStartMin = 540
        task.estimatedMinutes = 30
        context.insert(task)
        try context.save()
        return task
    }

    // MARK: - Behavioural

    /// The mapping both refusals go through: the iOS sentence for a refusal, nothing for a write
    /// that landed, so a later landed edit clears an earlier refusal's alert.
    @Test func aRefusedEditIsNamedInTheIOSSentenceAndALandedOneClearsIt() {
        #expect(
            TimelineDayCanvasStateSupport.blockEditFailureNotice(landed: false)
                == CadencePendingChangePersistence.editFailureNotice
        )
        #expect(TimelineDayCanvasStateSupport.blockEditFailureNotice(landed: true) == nil)
    }

    /// A real refused resize, end to end through the commit the block calls, reaches the sentence.
    @Test func aRefusedResizeReachesTheSentence() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = try scheduledTask(in: context)
        let origin = CadenceTaskFieldSnapshot(task)
        task.estimatedMinutes = 90
        let landed = TimelineTaskBlockInteractionSupport.commitResize(
            task, restoring: origin, in: context, commit: { _ in throw CommitRefused() }
        )
        #expect(
            TimelineDayCanvasStateSupport.blockEditFailureNotice(landed: landed)
                == CadencePendingChangePersistence.editFailureNotice
        )
    }

    /// A real refused move — on the Mac, a drop — reaches the sentence; a landed one does not.
    @Test func aRefusedMoveReachesTheSentenceAndALandedOneDoesNot() throws {
        let context = ModelContext(try CadenceTestStore.container())
        let task = try scheduledTask(in: context)
        let refused = SchedulingActions.commitDropTask(
            task, to: "2026-06-01", startMin: 600, in: context, commit: { _ in throw CommitRefused() }
        )
        #expect(
            TimelineDayCanvasStateSupport.blockEditFailureNotice(landed: refused)
                == CadencePendingChangePersistence.editFailureNotice
        )
        let landed = SchedulingActions.commitDropTask(task, to: "2026-06-01", startMin: 600, in: context)
        #expect(TimelineDayCanvasStateSupport.blockEditFailureNotice(landed: landed) == nil)
    }

    // MARK: - Wiring, read from source

    private func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    /// The resize's answer leaves the block, the layer hands it on, and the canvas names it.
    @Test func theMacResizeAnswerReachesTheCanvas() throws {
        let block = try code("Cadence/macOS/Views/TimelineTaskBlock.swift")
        let endResize = try #require(CadenceSourceScan.functionBody(named: "endResize", in: block))
        #expect(CadenceSourceScan.matchCount(
            #"onResizeAnswered\(\s*TimelineTaskBlockInteractionSupport\.commitResize\(task, restoring: resizeOrigin, in: modelContext\)\s*\)"#,
            in: endResize
        ) == 1, "the block drops the resize's answer again")

        let layers = try code("Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift")
        let layer = try #require(CadenceSourceScan.declarationBody("struct TimelineScheduledBlocksLayer: View", in: layers))
        #expect(CadenceSourceScan.matchCount(#"onResizeAnswered: onBlockEditAnswered"#, in: layer) == 1)

        let canvas = try code("Cadence/macOS/Views/TimelineDayCanvas.swift")
        #expect(CadenceSourceScan.matchCount(#"onBlockEditAnswered: reportBlockEdit"#, in: canvas) == 1)
    }

    /// The canvas reports every drop's answer and draws what it was told, in an alert.
    @Test func theMacCanvasNamesARefusedDropAndDrawsTheSentence() throws {
        let canvas = try code("Cadence/macOS/Views/TimelineDayCanvas.swift")
        #expect(CadenceSourceScan.matchCount(
            #"onDropTaskAtMinute: \{ task, startMin in\s*reportBlockEdit\(landed: onDropTaskAtMinute\(task, startMin\)\)\s*\}"#,
            in: canvas
        ) == 1, "the canvas hands the drop delegate the host's closure bare, discarding its answer")
        let report = try #require(CadenceSourceScan.functionBody(named: "reportBlockEdit", in: canvas))
        #expect(report.contains("blockEditFailureNotice = TimelineDayCanvasStateSupport.blockEditFailureNotice(landed: landed)"))
        #expect(CadenceSourceScan.matchCount(
            #"\.alert\(\s*TimelineDayCanvasStateSupport\.blockEditFailureAlertTitle,"#,
            in: canvas
        ) == 1)
        #expect(CadenceSourceScan.matchCount(#"Text\(blockEditFailureNotice \?\? "#, in: canvas) == 1)
    }

    /// iOS: the column's drop answer reaches the strip the move and resize already use.
    @Test func theIOSDropAnswerReachesTheStrip() throws {
        let source = try code("Cadence/iOS/iOSCalendarTimelineViews.swift")
        let grid = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarTimelineGrid: View", in: source))
        #expect(CadenceSourceScan.matchCount(
            #"onDropTaskAtMinute: \{ id, minute in reportTimelineWrite\(landed: onDropTaskAtMinute\(id, key, minute\)\) \}"#,
            in: grid
        ) == 1, "the grid hands the column a drop closure whose answer nobody reads")
        #expect(CadenceSourceScan.matchCount(#"reportTimelineWrite\(landed: CadenceTimelineBlockEdit\.commit\("#, in: grid) == 1)
    }
}
#endif
