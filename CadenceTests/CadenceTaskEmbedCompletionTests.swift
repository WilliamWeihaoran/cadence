import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-8395]]: a task-embed card's circle joins the deferred completion, on both platforms.**
///
/// The card circle in a note, in Focus's task notes and in the inspector's notes wrote completion
/// at once while every other task circle filled for `CadenceTaskCompletionTiming.animationDuration`
/// with a take-back ([[T-8203]]). It now walks the same `TaskCompletionAnimationManager`, and
/// `CadenceTaskEmbedCompletionDriver` repaints the card — drawn from a snapshot, so nothing else
/// would — while the fill runs and once when it settles. Windows are closed by calling the
/// manager's `windowClosed` and frames stepped with `tick(now:)` ([[T-268]]: no sleep-and-assert).
@MainActor
struct CadenceTaskEmbedCompletionTests {

    private func seeded(_ title: String, status: TaskStatus = .todo) throws -> (ModelContainer, ModelContext, AppTask) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: title)
        task.status = status
        context.insert(task)
        try context.save()
        return (container, context, task)
    }

    private final class Recorder {
        var repainted: [UUID] = []
        var settled: [UUID] = []
    }

    private func driver(_ recorder: Recorder) -> CadenceTaskEmbedCompletionDriver {
        let driver = CadenceTaskEmbedCompletionDriver()
        driver.repaint = { recorder.repainted.append($0) }
        driver.settled = { recorder.settled.append($0) }
        return driver
    }

    @Test func aCardTapFillsFirstAndWritesDoneOnlyWhenTheWindowCloses() throws {
        let (container, _, task) = try seeded("Embedded")
        let manager = TaskCompletionAnimationManager.shared
        let recorder = Recorder()
        let driver = driver(recorder)
        defer { manager.cancelPending(for: task.id) }

        driver.tap(task)

        #expect(task.status == .todo, "the card wrote completion at once instead of filling")
        #expect(manager.isPending(task))
        #expect(manager.embedPendingFill(forTaskID: task.id)?.kind == .completing)
        #expect(recorder.repainted == [task.id], "the tap did not repaint the filling circle")
        #expect(recorder.settled.isEmpty)
        #expect(driver.isTracking)

        manager.windowClosed(onCompletionOf: task.id)
        driver.tick()

        #expect(task.status == .done)
        #expect(recorder.settled == [task.id], "the card was not rebuilt when the write landed")
        #expect(!driver.isTracking, "the repaint kept running after the settle")
        let stored = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first { $0.id == task.id }
        #expect(stored?.status == .done, "the store does not hold the completion the card shows")
    }

    @Test func theCardWalksTheSameThreeTapsAsEveryOtherCircle() throws {
        let (container, _, task) = try seeded("Embedded")
        let manager = TaskCompletionAnimationManager.shared
        let recorder = Recorder()
        let driver = driver(recorder)
        defer {
            manager.cancelPending(for: task.id)
            manager.cancelCancelPending(for: task.id)
        }

        driver.tap(task)
        driver.tap(task)
        #expect(manager.embedPendingFill(forTaskID: task.id)?.kind == .cancelling, "a second tap did not turn the fill into a cancellation")
        driver.tap(task)
        #expect(manager.embedPendingFill(forTaskID: task.id) == nil, "a third tap did not take the cancellation back")
        #expect(recorder.settled == [task.id])

        manager.windowClosed(onCompletionOf: task.id)
        manager.windowClosed(onCancellationOf: task.id)
        let stored = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first { $0.id == task.id }
        #expect(stored?.status == .todo, "a taken-back card still settled its task")
    }

    /// [[T-8394]] through the shared walk: a settled card restores at once, and the card is rebuilt
    /// on that same tap rather than after a window that never opened.
    @Test func aSettledCardRestoresAtOnceAndIsRebuiltOnTheSameTap() throws {
        let (container, _, task) = try seeded("Embedded", status: .cancelled)
        let recorder = Recorder()
        let driver = driver(recorder)

        driver.tap(task)

        #expect(task.status == .todo, "a cancelled card's tick did not restore it")
        #expect(recorder.settled == [task.id])
        #expect(recorder.repainted.isEmpty)
        #expect(!driver.isTracking)
        let stored = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).first { $0.id == task.id }
        #expect(stored?.status == .todo)
    }

    @Test func thePendingFillRunsFromZeroToOneOverTheSharedWindow() throws {
        let (_, _, task) = try seeded("Embedded")
        let manager = TaskCompletionAnimationManager.shared
        defer { manager.cancelPending(for: task.id) }

        manager.advanceCompletionControl(for: task)
        let start = try #require(manager.pendingStartTimes[task.id])
        let half = start.addingTimeInterval(CadenceTaskCompletionTiming.animationDuration / 2)
        let fill = try #require(manager.embedPendingFill(forTaskID: task.id, now: half))
        #expect(abs(fill.progress - 0.5) < 0.001)
        let late = start.addingTimeInterval(CadenceTaskCompletionTiming.animationDuration * 2)
        #expect(manager.embedPendingFill(forTaskID: task.id, now: late)?.progress == 1)
        #expect(manager.embedPendingFill(forTaskID: UUID()) == nil)
        #expect(CadenceTaskEmbedPendingFill(kind: .completing, progress: 0).wedgePath(in: CGRect(x: 0, y: 0, width: 22, height: 22)).isEmpty)
    }

    /// Both editors, by source — the iOS one is not compiled by a macOS test host, and each card is
    /// drawn by a text view no unit test can paint.
    @Test func bothEditorsWalkTheSharedControlAndDrawItsFill() throws {
        let mac = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskNotesEmbedHandlers.swift"))
        let macToggle = try #require(CadenceSourceScan.functionBody(named: "toggleEmbeddedTask", in: mac))
        #expect(macToggle.contains("completionDriver.tap(embeddedTask)"), "the Mac card writes completion at once again")
        #expect(!macToggle.contains("toggleCompletion("), "the Mac card writes completion at once again")

        let macDecorations = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownEditorTextViewDecorations.swift"))
        #expect(macDecorations.contains("pendingFill: TaskCompletionAnimationManager.shared.embedPendingFill(forTaskID: embed.task.id)"))
        let macDrawing = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift"))
        #expect(macDrawing.contains("pendingFill.draw("), "the Mac card does not draw the fill")

        let surface = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift"))
        let iosToggle = try #require(CadenceSourceScan.functionBody(named: "toggleEmbeddedTask", in: surface))
        #expect(iosToggle.contains("TaskCompletionAnimationManager.shared.advanceCompletionControl(for: task)"), "the iOS card does not start the shared fill")
        #expect(!surface.contains("CadenceTaskStatusEditing.toggleCompletion("), "the iOS card writes completion at once again")

        let editor = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditor.swift"))
        #expect(editor.contains("trackEmbedCompletion(taskID: refreshed.id, in: textView)"), "the iOS editor does not repaint the fill")
        #expect(editor.contains("pendingFill: fill,"))
        let layout = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownTaskEmbedLayoutInfo.swift"))
        #expect(layout.contains("pendingFill.draw("), "the iOS card does not draw the fill")
    }
}
