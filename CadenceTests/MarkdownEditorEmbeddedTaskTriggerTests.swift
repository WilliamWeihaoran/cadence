import Foundation
import Testing
#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
#endif

@testable import Cadence

#if os(macOS)
/// When the Mac note editor turns a `( ) …` line into a task ([[T-18141]]).
///
/// Return is the only trigger, as on iOS. Typing `( ) ` used to mint an "Untitled Task" the
/// instant the space landed, so a marker typed and then deleted left a task in the store. Runs the
/// real `CadenceTextView`, `MarkdownEditorCoordinator` and the handlers every Mac host uses, over
/// an in-memory store, in `MarkdownEditorUndoHistoryTests`' harness shape.
@MainActor
struct MarkdownEditorEmbeddedTaskTriggerTests {
    @MainActor
    private final class Harness {
        let container: ModelContainer
        let modelContext: ModelContext
        let handlers: TaskNotesEmbedHandlers
        let coordinator: MarkdownEditorCoordinator
        let view: CadenceTextView
        /// Every title `onCreateEmbeddedMarkdownTask` was asked to mint, in order.
        var requestedTitles: [String] = []

        init(_ text: String) throws {
            container = try CadenceModelContainerFactory.makeInMemoryContainer()
            modelContext = ModelContext(container)
            handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "trigger-test-")
            coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
            view = CadenceTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
            view.isEditable = true
            view.isRichText = true
            view.allowsUndo = true
            view.string = text
            view.delegate = coordinator
            let scope = TaskNotesEmbedScope(referenceTasks: [], embedTarget: .coreNotes, modelContext: modelContext)
            let handlers = handlers
            view.onCreateEmbeddedMarkdownTask = { [unowned self] title in
                self.requestedTitles.append(title)
                return handlers.createUndoableEmbeddedTask(title: title, in: scope)
            }
            coordinator.undoManager.groupsByEvent = false
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }

        /// Types `text` one keystroke at a time at the caret, each grouped as the event loop would.
        func type(_ text: String) {
            for character in text {
                let caret = view.selectedRange()
                coordinator.undoManager.beginUndoGrouping()
                view.insertText(String(character), replacementRange: caret)
                coordinator.undoManager.endUndoGrouping()
            }
        }

        func pressReturn() {
            coordinator.undoManager.beginUndoGrouping()
            _ = coordinator.textView(view, doCommandBy: #selector(NSResponder.insertNewline(_:)))
            coordinator.undoManager.endUndoGrouping()
        }

        func storedTasks() throws -> [AppTask] {
            try modelContext.fetch(FetchDescriptor<AppTask>())
        }
    }

    /// The defect: the trailing space of `( ) ` minted a task before the user had pressed Return.
    @Test(arguments: ["( ) ", "() "])
    func typingTheMarkerCreatesNoTask(marker: String) throws {
        let harness = try Harness("")

        harness.type(marker)

        #expect(harness.requestedTitles.isEmpty, "typing the marker asked for a task")
        #expect(try harness.storedTasks().isEmpty)
        #expect(harness.view.string == marker)
    }

    /// A bare marker still becomes an "Untitled Task" — on Return, once.
    @Test func returnOnABareMarkerCreatesOneUntitledTask() throws {
        let harness = try Harness("")

        harness.type("( ) ")
        #expect(harness.requestedTitles.isEmpty)
        #expect(harness.view.string == "( ) ")

        harness.pressReturn()

        let untitled = MarkdownTaskEmbedRenderInfo.untitledTaskTitle
        #expect(harness.requestedTitles == [untitled])
        let made = try harness.storedTasks()
        #expect(made.map(\.title) == [untitled])
        let id = try #require(made.first?.id)
        #expect(harness.view.string.contains("[[task:\(id.uuidString)|\(untitled)]]"))
    }

    /// A titled marker becomes a task already named, on Return, once.
    @Test func returnOnATitledMarkerCreatesOneNamedTask() throws {
        let harness = try Harness("")

        harness.type("( ) Milk")
        #expect(harness.requestedTitles.isEmpty)
        #expect(harness.view.string == "( ) Milk")

        harness.pressReturn()

        #expect(harness.requestedTitles == ["Milk"])
        #expect(try harness.storedTasks().map(\.title) == ["Milk"])
    }

    /// A marker typed and then deleted leaves nothing behind.
    @Test func aMarkerTypedThenDeletedLeavesNoTask() throws {
        let harness = try Harness("")

        harness.type("( ) ")
        for _ in 0..<4 {
            harness.view.setSelectedRange(NSRange(location: (harness.view.string as NSString).length, length: 0))
            harness.view.deleteBackward(nil)
        }

        #expect(harness.view.string.isEmpty)
        #expect(harness.requestedTitles.isEmpty)
        #expect(try harness.storedTasks().isEmpty)
    }

    /// Undo of the Return that made the untitled task takes that task back out ([[T-18174]]).
    @Test func undoOfTheReturnOnABareMarkerTakesItsTaskBackOut() throws {
        let harness = try Harness("( ) ")

        harness.pressReturn()
        #expect(try harness.storedTasks().count == 1)

        harness.coordinator.undoManager.undo()
        #expect(harness.view.string == "( ) ")
        #expect(try harness.storedTasks().isEmpty, "undo left the untitled task in the store")
    }
}
#endif
