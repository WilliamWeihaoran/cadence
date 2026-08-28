import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-376: five macOS surfaces could read a failed task delete and said nothing.
///
/// `ModelContext.deleteTask(_:)` started returning `Bool` in [[T-365]]; `TasksPanelComponents`,
/// `KanbanCardStateSupport`, `TaskInspectorContentSupportViews`,
/// `TimelineTaskBlockInteractionSupport` and `macOSRootCommandActionSupport` all discarded it.
/// Nothing was *lost* — the rollback puts the row back on screen by itself — but macOS stayed silent
/// where the iOS row shows `CadenceTaskMutationSupport.deleteFailureNotice`.
///
/// **The decision this pins.** The notice goes on the confirmation, not on the five rows. Those five
/// have five different geometries and one of them is not a view at all, while the confirmation
/// overlay is the one thing all five already share, is on screen when the answer arrives, and is
/// what asked the question. So a refused delete leaves the overlay standing and puts the sentence
/// inside it — the shape `EditListSheet` and `iOSNoteDeleteConfirmationSheet` already use.
@MainActor
struct MacOSTaskDeleteNoticeTests {

    private func deleteContext() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    private func seededTask(in context: ModelContext) throws -> AppTask {
        let task = AppTask(title: "Delete me")
        context.insert(task)
        try context.save()
        return task
    }

    /// The app's singleton, reset first. `DeleteConfirmationManager` is deliberately a `shared`
    /// with a private `init` — adding a test-only factory to production code to avoid that would be
    /// a bigger change than the reset. The scheme is `parallelizable = "NO"` and this whole suite is
    /// `@MainActor`, so the reset is enough.
    private func manager() -> DeleteConfirmationManager {
        let confirmations = DeleteConfirmationManager.shared
        confirmations.cancel()
        return confirmations
    }

    // MARK: - The behaviour

    /// The ordinary path is unchanged: the delete goes through, the overlay dismisses, no notice.
    @Test func aTaskDeleteThatCommitsDismissesTheConfirmationSilently() throws {
        let context = try deleteContext()
        let task = try seededTask(in: context)
        let confirmations = manager()

        confirmations.presentTaskDelete(task, in: context)
        #expect(confirmations.isPresented)
        confirmations.confirm()

        #expect(!confirmations.isPresented, "the overlay stayed open after a delete that worked")
        #expect(confirmations.failureNotice == nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// The bug. A refused commit rolls the delete back, and the user must be told — the overlay
    /// stays open carrying the shared sentence.
    @Test func aRefusedTaskDeleteHoldsTheConfirmationOpenAndSaysWhy() throws {
        struct Refused: Error {}
        let context = try deleteContext()
        let task = try seededTask(in: context)
        let confirmations = manager()

        confirmations.presentTaskDelete(task, in: context, commit: { _ in throw Refused() })
        confirmations.confirm()

        #expect(confirmations.isPresented, "the overlay dismissed on a delete that never happened (T-376)")
        #expect(confirmations.failureNotice == CadenceTaskMutationSupport.deleteFailureNotice)
        // "Nothing was removed" has to be true, not approximately true.
        #expect(try context.fetch(FetchDescriptor<AppTask>()).count == 1)
    }

    /// Cancelling clears the notice with the request, so re-opening the same confirmation does not
    /// inherit a stale sentence from the previous attempt.
    @Test func cancellingClearsBothTheRequestAndTheNotice() throws {
        struct Refused: Error {}
        let context = try deleteContext()
        let task = try seededTask(in: context)
        let confirmations = manager()

        confirmations.presentTaskDelete(task, in: context, commit: { _ in throw Refused() })
        confirmations.confirm()
        #expect(confirmations.failureNotice != nil)

        confirmations.cancel()

        #expect(!confirmations.isPresented)
        #expect(confirmations.failureNotice == nil)
    }

    /// Presenting a new request clears the previous failure too — otherwise the next delete opens
    /// already accusing itself.
    @Test func presentingANewRequestClearsThePreviousFailureNotice() throws {
        struct Refused: Error {}
        let context = try deleteContext()
        let task = try seededTask(in: context)
        let confirmations = manager()

        confirmations.presentTaskDelete(task, in: context, commit: { _ in throw Refused() })
        confirmations.confirm()
        #expect(confirmations.failureNotice != nil)

        confirmations.present(title: "Delete Note?", message: "Gone forever.") {}

        #expect(confirmations.failureNotice == nil)
    }

    /// A retry after a refusal succeeds and clears the notice, so the overlay does not keep a
    /// sentence that has stopped being true.
    @Test func retryingAfterARefusalDismissesAndClearsTheNotice() throws {
        struct Refused: Error {}
        let context = try deleteContext()
        let task = try seededTask(in: context)
        let confirmations = manager()
        var refuse = true

        confirmations.presentTaskDelete(task, in: context, commit: { context in
            if refuse { throw Refused() }
            try context.save()
        })
        confirmations.confirm()
        #expect(confirmations.failureNotice != nil)

        refuse = false
        confirmations.confirm()

        #expect(!confirmations.isPresented)
        #expect(confirmations.failureNotice == nil)
        #expect(try context.fetch(FetchDescriptor<AppTask>()).isEmpty)
    }

    /// The surface-local teardown a row passes still runs, and runs before the delete.
    @Test func theTeardownClosureRunsBeforeTheDelete() throws {
        let context = try deleteContext()
        let task = try seededTask(in: context)
        let confirmations = manager()
        var order: [String] = []

        confirmations.presentTaskDelete(task, in: context, willDelete: { order.append("teardown") }, commit: { context in
            order.append("commit")
            try context.save()
        })
        #expect(order.isEmpty, "the teardown ran at present time rather than at confirm time")
        confirmations.confirm()

        #expect(order == ["teardown", "commit"])
    }

    /// The plain `present(_:)` path is untouched: a Void action always counts as done, so the twelve
    /// non-task callers keep dismissing on confirm.
    @Test func aPlainVoidConfirmationStillAlwaysDismisses() {
        let confirmations = manager()
        var ran = false

        confirmations.present(title: "Delete List?", message: "Everything in it goes.") { ran = true }
        confirmations.confirm()

        #expect(ran)
        #expect(!confirmations.isPresented)
        #expect(confirmations.failureNotice == nil)
    }

    /// The title fallback is the shared one. Four of the five call sites open-coded
    /// `task.title.isEmpty ? "Untitled" : task.title` and the fifth used `TaskTitleSupport`; folding
    /// them into one entry point settles it on the shared spelling.
    @Test func theConfirmationMessageNamesTheTaskThroughTheSharedTitleHelper() throws {
        let context = try deleteContext()
        let untitled = try seededTask(in: context)
        untitled.title = "   "
        try context.save()
        let confirmations = manager()

        confirmations.presentTaskDelete(untitled, in: context)

        #expect(confirmations.request?.title == "Delete Task?")
        #expect(confirmations.request?.message.contains("Untitled") == true)
    }

    // MARK: - Shape: the five surfaces route through it

    private static let macOSTaskDeleteSurfaces = [
        "Cadence/macOS/Views/TasksPanelComponents.swift",
        "Cadence/macOS/Views/KanbanCardStateSupport.swift",
        "Cadence/macOS/Views/TaskInspectorContentSupportViews.swift",
        "Cadence/macOS/Views/TimelineTaskBlockInteractionSupport.swift",
        "Cadence/macOS/Views/macOSRootCommandActionSupport.swift"
    ]

    /// The discarded call the ticket names: `deleteTask(` on a context, with the answer thrown away.
    private static let discardedDelete = #"\bdeleteTask\("#

    @Test func theFiveMacOSTaskDeleteSurfacesRouteThroughTheConfirmation() throws {
        var filesRead = 0

        for path in Self.macOSTaskDeleteSurfaces {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 400, "\(path) read as \(raw.count) characters")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(path): the stripper changed the length")

            #expect(
                stripped.contains("presentTaskDelete("),
                "\(path) no longer confirms task deletion through the shared entry point (T-376)"
            )
            #expect(
                CadenceSourceScan.matchCount(Self.discardedDelete, in: stripped) == 0,
                "\(path) calls deleteTask directly and discards the answer (T-376)"
            )

            filesRead += 1
        }

        #expect(filesRead == 5, "the scan read \(filesRead) of 5 macOS task-delete surfaces")
    }

    /// The overlay actually draws the notice. `DeleteConfirmationOverlay` is a SwiftUI view body, so
    /// a scan is the tool — and the two ends have to match: the layer hands the manager's notice in,
    /// and the overlay renders it with the shared failure component rather than a local `Text`.
    @Test func theConfirmationOverlayDrawsTheFailureNotice() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/macOSRootSupportViews.swift")
        #expect(raw.count > 400)
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw)
        #expect(stripped.count == raw.count)

        // Non-vacuity: this really is the file that declares the overlay.
        #expect(stripped.contains("struct DeleteConfirmationOverlay: View"))
        #expect(stripped.contains("failureNotice: deleteConfirmationManager.failureNotice"))
        #expect(stripped.contains("CadenceInlineFailureNotice(text: failureNotice)"))
    }

    /// The needles match what they hunt and miss what they must not, and the reader reaches real
    /// files — the macOS delete wrapper is *supposed* to declare `deleteTask`, so the needle must
    /// fire there and only there.
    @Test func theMacOSDeleteNoticeScanNeedlesAndReaderAreNotVacuous() throws {
        #expect(CadenceSourceScan.matchCount(Self.discardedDelete, in: "modelContext.deleteTask(task)") == 1)
        #expect(CadenceSourceScan.matchCount(Self.discardedDelete, in: "context.modelContext.deleteTask(task)") == 1)
        #expect(CadenceSourceScan.matchCount(Self.discardedDelete, in: "confirmations.presentTaskDelete(task, in: context)") == 0)
        #expect(CadenceSourceScan.matchCount(Self.discardedDelete, in: "modelContext.deleteTasks(withIDs: ids)") == 0)

        let helpers = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Services/TaskDeleteHelpers.swift")
        )
        #expect(
            CadenceSourceScan.matchCount(Self.discardedDelete, in: helpers) >= 1,
            "the scan read no deleteTask declaration in TaskDeleteHelpers, so it read the wrong file"
        )
    }
}
