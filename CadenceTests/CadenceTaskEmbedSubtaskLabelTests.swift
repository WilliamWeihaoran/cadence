import Foundation
import Testing
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
@testable import Cadence

// [[T-17765]]: the note task-embed card's subtask overflow read "+2" on iOS and "+2 more" on the
// Mac, and both cards typed their own `done/total` although `CadenceSubtaskProgress.compactLabel`
// is the shared spelling. One app, two platforms: both cards now read the one shared label for
// each, and the iOS overflow slot is sized from the longer text rather than a fixed 34pt.
struct CadenceTaskEmbedSubtaskLabelTests {

    private func task(done: [Bool]) -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: UUID(),
            title: "Quarter close",
            statusRaw: TaskStatus.todo.rawValue,
            priorityRaw: TaskPriority.none.rawValue,
            sectionName: "",
            containerName: "",
            containerColorHex: Theme.blueHex,
            dueDate: "",
            scheduledDate: "",
            scheduledStartMin: -1,
            estimatedMinutes: 0,
            actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue,
            isDone: false,
            isCancelled: false,
            isMissing: false,
            subtasks: done.enumerated().map {
                MarkdownTaskEmbedSubtaskRenderInfo(id: UUID(), title: "Step \($0)", isDone: $1, order: $0)
            }
        )
    }

    /// The card's progress is the shared struct, so its label is the row badge's word for word.
    @Test func theCardsProgressIsTheSharedSubtaskProgress() {
        let info = task(done: [true, false, false])
        #expect(info.subtaskProgress?.completed == 1)
        #expect(info.subtaskProgress?.total == 3)
        #expect(info.subtaskProgress?.compactLabel == "1/3")
        #expect(task(done: []).subtaskProgress == nil, "no subtasks draws no chip")
    }

    #if os(iOS)
    @Test func theIOSCardReadsTheSharedLabels() {
        let info = task(done: [true, true, false, false, false])
        #expect(iOSMarkdownTaskEmbedLayoutInfo.subtaskProgressLabel(for: info) == "2/5")
        #expect(iOSMarkdownTaskEmbedLayoutInfo.subtaskOverflowLabel(count: 2) == "+2 more")
        #expect(
            iOSMarkdownTaskEmbedLayoutInfo.subtaskOverflowLabel(count: 2)
                == CadenceTaskSurfaceOptions.moreLabel(hidden: 2)
        )
    }

    /// The slot that held a bare `+N` in 34pt now fits `+N more` in the card's 10pt font.
    @Test func theIOSOverflowSlotFitsTheLongerLabel() {
        let card = iOSMarkdownTaskEmbedLayoutInfo(task: task(done: [false, false, false, false, false]))
        let font = UIFont.systemFont(ofSize: 10, weight: .medium)
        for count in [1, 2, 9, 12, 120] {
            let label = iOSMarkdownTaskEmbedLayoutInfo.subtaskOverflowLabel(count: count)
            let measured = NSString(string: label).size(withAttributes: [.font: font]).width
            #expect(card.subtaskOverflowWidth(count: count) >= measured, "\(label)")
            #expect(card.subtaskOverflowWidth(count: count) >= iOSMarkdownTaskEmbedLayoutInfo.subtaskOverflowMinWidth)
        }
    }
    #endif

    #if os(macOS)
    @MainActor @Test func theMacCardReadsTheSharedLabels() {
        let info = task(done: [true, true, false, false, false])
        #expect(MarkdownTaskEmbedDrawing.subtaskProgressLabel(for: info) == "2/5")
        #expect(MarkdownTaskEmbedDrawing.subtaskOverflowLabel(count: 2) == "+2 more")
    }
    #endif

    /// The drawing reads the seams the value tests pin -- neither card types its own `+N` or
    /// `done/total`. Source-read, so it runs on either leg over both platforms' files.
    @Test func bothCardsDrawThroughTheSharedLabels() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let iOS = try cadenceFunctionBody(
            "private func drawSubtasks(width: CGFloat)",
            in: try read("Cadence/iOS/iOSMarkdownTaskEmbedLayoutInfo.swift")
        )
        let mac = try cadenceFunctionBody(
            "static func drawSubtasks(",
            in: try read("Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift")
        )
        #expect(iOS.contains("Self.subtaskOverflowLabel(count: overflow.count)"))
        #expect(iOS.contains("Self.subtaskProgressLabel(for: task)"))
        #expect(mac.contains("subtaskProgressLabel(for: task)"))
        let macChip = try cadenceFunctionBody(
            "static func drawOverflowChip(",
            in: try read("Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift")
        )
        #expect(macChip.contains("subtaskOverflowLabel(count: count)"))
        for (name, body) in [("iOS", iOS), ("Mac", mac)] {
            #expect(CadenceSourceScan.matchCount(#""\+\\\("#, in: body) == 0, "\(name) card spells its own overflow")
            #expect(
                CadenceSourceScan.matchCount(#"completedSubtaskCount\)/"#, in: body) == 0,
                "\(name) card spells its own done/total"
            )
        }
    }
}
