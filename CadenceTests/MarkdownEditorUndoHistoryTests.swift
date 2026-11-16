import Foundation
import Testing
#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
#endif

@testable import Cadence

#if os(macOS)
/// Cmd+Z in the Mac note editor ([[T-17181]], [[T-17182]]).
///
/// Both run the real `CadenceTextView` and `MarkdownEditorCoordinator`. A headless test has no run
/// loop, so `groupsByEvent` is off and each user step is grouped by hand — the shape the app's
/// event loop gives a keystroke.
@MainActor
struct MarkdownEditorUndoHistoryTests {
    private static func makeTextView(_ text: String) -> CadenceTextView {
        let view = CadenceTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        view.isEditable = true
        view.isRichText = true
        view.allowsUndo = true
        view.string = text
        return view
    }

    private static func type(_ text: String, atEndOf view: CadenceTextView, in manager: UndoManager) {
        let end = (view.string as NSString).length
        manager.beginUndoGrouping()
        view.setSelectedRange(NSRange(location: end, length: 0))
        view.insertText(text, replacementRange: NSRange(location: end, length: 0))
        manager.endUndoGrouping()
    }

    // MARK: - T-17181: a body rewritten from outside the view

    /// The defect: the user types, then links an unlinked mention (or applies a template, or an
    /// external write lands), and the host hands the editor a rewritten body. The first Cmd+Z
    /// must take the rewrite back and the second the typing — not replay the typing record at
    /// offsets the rewrite shifted, which gave `"[[Sam]] Call Soday now"`.
    @Test func undoAfterAnExternalRewriteTakesTheRewriteBackThenTheTyping() {
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = Self.makeTextView("Call Sam today")
        view.delegate = coordinator
        let manager = coordinator.undoManager
        manager.groupsByEvent = false

        Self.type(" now", atEndOf: view, in: manager)
        #expect(view.string == "Call Sam today now")

        manager.beginUndoGrouping()
        coordinator.applyExternalText("[[Sam]] Call Sam today now", to: view)
        manager.endUndoGrouping()
        #expect(view.string == "[[Sam]] Call Sam today now")

        manager.undo()
        #expect(view.string == "Call Sam today now")
        manager.undo()
        #expect(view.string == "Call Sam today")

        manager.redo()
        manager.redo()
        #expect(view.string == "[[Sam]] Call Sam today now")
    }

    /// The other half of the rule: every host opens its editor on `""` and fills it from the note
    /// on appear. That load is not an edit, so Cmd+Z straight after opening a note must not blank
    /// it.
    @Test func theLoadIntoAnEmptyEditorIsNotAnUndoableStep() {
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = Self.makeTextView("")
        view.delegate = coordinator
        // Left grouping by event, the app's own setting: any registration opens a group that
        // `undo()` closes, so a load that wrongly registered would be undone below. An explicit
        // empty group would make `canUndo` read true and hide that.

        coordinator.applyExternalText("# Groceries\n\nMilk", to: view)

        #expect(view.string == "# Groceries\n\nMilk")
        #expect(coordinator.undoManager.canUndo == false)
        if coordinator.undoManager.canUndo { coordinator.undoManager.undo() }
        #expect(view.string == "# Groceries\n\nMilk")
    }

    // MARK: - T-17182: one history per editor

    /// The defect: the editor is rebuilt per note, but its text view used the window's undo
    /// manager, so the note just left stayed on the stack. Opening another note showed
    /// "Undo Typing" and Cmd+Z there reverted the detached view instead of anything on screen.
    @Test func anotherNotesEditorStartsWithNoUndoHistory() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        window.contentView = container

        let first = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let noteA = Self.makeTextView("Note A")
        noteA.delegate = first
        container.addSubview(noteA)
        window.makeFirstResponder(noteA)
        let managerA = try #require(noteA.undoManager)
        managerA.groupsByEvent = false
        Self.type(" typed", atEndOf: noteA, in: managerA)
        #expect(managerA.canUndo)

        noteA.removeFromSuperview()
        let second = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let noteB = Self.makeTextView("Note B")
        noteB.delegate = second
        container.addSubview(noteB)
        window.makeFirstResponder(noteB)

        #expect(noteB.undoManager?.canUndo == false)
        _ = noteB.tryToPerform(Selector(("undo:")), with: nil)
        #expect(noteA.string == "Note A typed")
        #expect(noteB.string == "Note B")
    }

    /// And within one note Cmd+Z still reaches the editor's history through the responder chain,
    /// the route the Edit menu takes.
    @Test func undoThroughTheResponderChainReachesTheEditorsOwnHistory() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = Self.makeTextView("Note")
        view.delegate = coordinator
        window.contentView = view
        window.makeFirstResponder(view)
        coordinator.undoManager.groupsByEvent = false

        Self.type(" typed", atEndOf: view, in: coordinator.undoManager)
        #expect(view.undoManager === coordinator.undoManager)

        _ = view.tryToPerform(Selector(("undo:")), with: nil)
        #expect(view.string == "Note")
    }

    // MARK: - [[T-18174]]: undo of the edit that made a task card

    @MainActor
    private struct EmbedHarness {
        let container: ModelContainer
        let modelContext: ModelContext
        let handlers: TaskNotesEmbedHandlers
        let coordinator: MarkdownEditorCoordinator
        let view: CadenceTextView
        var manager: UndoManager { coordinator.undoManager }

        func tasks(titled title: String) throws -> [AppTask] {
            try modelContext.fetch(FetchDescriptor<AppTask>()).filter { $0.title == title }
        }

        /// One Return keystroke, grouped as the event loop would group it.
        func pressReturn() {
            manager.beginUndoGrouping()
            _ = coordinator.textView(view, doCommandBy: #selector(NSResponder.insertNewline(_:)))
            manager.endUndoGrouping()
        }
    }

    /// A real in-memory store, the real handlers every Mac host uses, and the real editor.
    private static func embedHarness(_ text: String) throws -> EmbedHarness {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "undo-test-")
        let scope = TaskNotesEmbedScope(referenceTasks: [], embedTarget: .coreNotes, modelContext: modelContext)
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = makeTextView(text)
        view.delegate = coordinator
        view.onCreateEmbeddedMarkdownTask = { handlers.createUndoableEmbeddedTask(title: $0, in: scope) }
        coordinator.undoManager.groupsByEvent = false
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return EmbedHarness(
            container: container,
            modelContext: modelContext,
            handlers: handlers,
            coordinator: coordinator,
            view: view
        )
    }

    /// The defect: Return on `( ) Milk` makes a "Milk" task and a card; Cmd+Z put the line back
    /// and left "Milk" in the store, so Return again made a second one. Undo now takes the task
    /// out with the card, redo puts the same task back, and the cycle repeats.
    @Test func undoOfTheReturnThatMadeATaskCardTakesTheTaskBackOut() throws {
        let harness = try Self.embedHarness("( ) Milk")

        harness.pressReturn()
        let made = try harness.tasks(titled: "Milk")
        #expect(made.count == 1)
        let id = try #require(made.first?.id)
        #expect(harness.view.string.contains("[[task:\(id.uuidString)|Milk]]"))

        harness.manager.undo()
        #expect(harness.view.string == "( ) Milk")
        #expect(try harness.tasks(titled: "Milk").isEmpty, "undo left the minted task in the store")

        harness.manager.redo()
        #expect(harness.view.string.contains("[[task:\(id.uuidString)|Milk]]"))
        #expect(try harness.tasks(titled: "Milk").map(\.id) == [id], "redo did not restore the same task")

        harness.manager.undo()
        #expect(harness.view.string == "( ) Milk")
        #expect(try harness.tasks(titled: "Milk").isEmpty, "a second undo after redo left the task")

        // And Return again makes one task, not a second beside a survivor.
        harness.view.setSelectedRange(NSRange(location: 8, length: 0))
        harness.pressReturn()
        #expect(try harness.tasks(titled: "Milk").count == 1)
    }

    /// Undo never deletes a task the user has since changed: the text reverts, the task stays.
    @Test func undoLeavesAMintedTaskTheUserHasSinceEdited() throws {
        let harness = try Self.embedHarness("( ) Milk")
        harness.pressReturn()
        let task = try #require(try harness.tasks(titled: "Milk").first)
        task.priority = .high
        try harness.modelContext.save()

        harness.manager.undo()
        #expect(harness.view.string == "( ) Milk")
        #expect(try harness.tasks(titled: "Milk").count == 1, "undo deleted a task the user had edited")

        harness.manager.redo()
        #expect(try harness.tasks(titled: "Milk").count == 1, "redo duplicated a task undo had kept")
    }

    /// The Mac's instant `( ) ` trigger ([[T-18141]]) mints an "Untitled Task" the same way, and
    /// its undo takes that task back out too.
    @Test func undoOfTheUntitledTriggerTakesItsTaskBackOut() throws {
        let harness = try Self.embedHarness("")
        let untitled = MarkdownTaskEmbedRenderInfo.untitledTaskTitle

        harness.manager.beginUndoGrouping()
        harness.view.insertText("( ) ", replacementRange: NSRange(location: 0, length: 0))
        harness.manager.endUndoGrouping()
        #expect(try harness.tasks(titled: untitled).count == 1)
        #expect(harness.view.string.hasPrefix("[[task:"))

        harness.manager.undo()
        #expect(!harness.view.string.contains("[[task:"))
        #expect(try harness.tasks(titled: untitled).isEmpty, "undo left the untitled task in the store")
    }
}
#endif
