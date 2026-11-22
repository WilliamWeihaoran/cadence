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

    // MARK: - [[T-19009]]: a typing transform that changes nothing

    /// The defect: a hand-typed `1. ` is rewritten to itself, and that identical write was a
    /// registered edit. In the app the marker's keystrokes have already joined NSTextView's
    /// coalesced typing record, so the space's event held nothing but that write -- a Cmd+Z that
    /// changed no text. Run here as the transform pass alone, grouped by event as the app is: a
    /// pass that writes nothing registers nothing, so there is no group to undo.
    @Test func aHandTypedCanonicalNumberedMarkerRegistersNoUndoStep() {
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = Self.makeTextView("")
        view.delegate = coordinator
        view.string = "1. "
        view.setSelectedRange(NSRange(location: 3, length: 0))

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))

        #expect(view.string == "1. ")
        #expect(coordinator.undoManager.canUndo == false)
    }

    // MARK: - [[T-19010]]: the title field's rename folded into one body step

    private static func coalescingCoordinator(
        _ text: String
    ) -> (MarkdownEditorCoordinator, CadenceTextView, UndoManager) {
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = Self.makeTextView(text)
        view.delegate = coordinator
        let manager = coordinator.undoManager
        manager.groupsByEvent = false
        return (coordinator, view, manager)
    }

    private static func setCoalescing(_ coalesces: Bool, on coordinator: MarkdownEditorCoordinator) {
        coordinator.update(parent: MarkdownEditorView(text: .constant(""), coalescesExternalText: coalesces))
    }

    /// One title keystroke: an event of its own, so a group of its own.
    private static func write(_ text: String, from coordinator: MarkdownEditorCoordinator,
                              to view: CadenceTextView, in manager: UndoManager) {
        manager.beginUndoGrouping()
        coordinator.applyExternalText(text, to: view)
        manager.endUndoGrouping()
    }

    /// The text after each Cmd+Z, until nothing is left. A press that changes nothing is dropped:
    /// a headless test groups by hand, so a keystroke that rightly registers nothing still leaves
    /// an empty group, which the app's event grouping never makes.
    private static func undoneTexts(_ view: CadenceTextView, in manager: UndoManager) -> [String] {
        var texts: [String] = []
        var last = view.string
        var presses = 0
        while manager.canUndo, presses < 20 {
            manager.undo()
            presses += 1
            if view.string != last { texts.append(view.string) }
            last = view.string
        }
        return texts
    }

    /// The defect: every title keystroke rewrote the `# H1` as its own body step, so Cmd+Z in the
    /// body took a rename back one letter at a time. Three keystrokes, then the edit settles: one
    /// press returns the opening heading, the next the body typing before it.
    @Test func aTitleRenameIsOneBodyUndoStep() {
        let (coordinator, view, manager) = Self.coalescingCoordinator("# Groceries\n\nMilk")
        Self.type(" and eggs", atEndOf: view, in: manager)

        Self.setCoalescing(true, on: coordinator)
        Self.write("# W\n\nMilk and eggs", from: coordinator, to: view, in: manager)
        Self.write("# We\n\nMilk and eggs", from: coordinator, to: view, in: manager)
        Self.write("# Wee\n\nMilk and eggs", from: coordinator, to: view, in: manager)
        #expect(view.string == "# Wee\n\nMilk and eggs")

        Self.setCoalescing(false, on: coordinator)
        manager.beginUndoGrouping()
        coordinator.settleCoalescedExternalText(in: view)
        manager.endUndoGrouping()
        #expect(view.string == "# Wee\n\nMilk and eggs")

        #expect(Self.undoneTexts(view, in: manager) == ["# Groceries\n\nMilk and eggs", "# Groceries\n\nMilk"])
        while manager.canRedo { manager.redo() }
        #expect(view.string == "# Wee\n\nMilk and eggs")
    }

    /// The settle that lands with the fold's last text -- a title left blank restores the opening
    /// heading as the field ends -- is the same one step, not a step of its own.
    @Test func aWriteAsTheRenameSettlesJoinsTheRenamesStep() {
        let (coordinator, view, manager) = Self.coalescingCoordinator("# Groceries\n\nMilk")
        Self.type(" and eggs", atEndOf: view, in: manager)

        Self.setCoalescing(true, on: coordinator)
        Self.write("# \n\nMilk and eggs", from: coordinator, to: view, in: manager)
        Self.write("# X\n\nMilk and eggs", from: coordinator, to: view, in: manager)
        Self.setCoalescing(false, on: coordinator)
        Self.write("# Groceries list\n\nMilk and eggs", from: coordinator, to: view, in: manager)
        #expect(view.string == "# Groceries list\n\nMilk and eggs")

        #expect(Self.undoneTexts(view, in: manager) == ["# Groceries\n\nMilk and eggs", "# Groceries\n\nMilk"])
    }

    /// The pane asks to fold exactly while a title edit is open -- the window in which every
    /// keystroke rewrites the heading. A source read: the pane is SwiftUI state this target cannot
    /// drive.
    @Test func theNotePaneFoldsTheTitleFieldsHeadingWrites() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Cadence/macOS/Views/NoteEditorPane.swift"),
            encoding: .utf8
        )
        let code = CadenceSourceScan.strippingComments(source)
        #expect(code.components(separatedBy: "coalescesExternalText: pendingTitleEdit != nil").count == 2)
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

    // MARK: - [[T-18594]]: undo of an inline rename over a task card

    /// A note holding one card for a committed "Milk" task, wired to the real handlers the way
    /// every Mac host wires them.
    private static func renameHarness() throws -> (EmbedHarness, AppTask) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let task = AppTask(title: "Milk")
        modelContext.insert(task)
        try modelContext.save()
        let handlers = TaskNotesEmbedHandlers(hoverIDPrefix: "undo-test-")
        let scope = TaskNotesEmbedScope(referenceTasks: [task], embedTarget: .coreNotes, modelContext: modelContext)
        let coordinator = MarkdownEditorCoordinator(parent: MarkdownEditorView(text: .constant("")))
        let view = makeTextView("Buy [[task:\(task.id.uuidString)|Milk]] today")
        view.delegate = coordinator
        view.markdownTaskEmbeds[task.id] = MarkdownTaskEmbedRenderInfo.task(task)
        view.onRenameEmbeddedMarkdownTask = { handlers.renameEmbeddedTask(id: $0, title: $1, in: scope) }
        handlers.editorTextView = view
        coordinator.undoManager.groupsByEvent = false
        let harness = EmbedHarness(
            container: container,
            modelContext: modelContext,
            handlers: handlers,
            coordinator: coordinator,
            view: view
        )
        return (harness, task)
    }

    /// The defect: renaming the card "Milk" -> "Eggs" and pressing Cmd+Z took back only the hidden
    /// title inside the reference; the task (and so the card, drawn from it) kept "Eggs". Undo now
    /// renames the task back with the text, redo renames both forward, and the cycle repeats.
    @Test func undoOfAnInlineCardRenameRenamesTheTaskBack() throws {
        let (harness, task) = try Self.renameHarness()
        let id = task.id

        harness.manager.beginUndoGrouping()
        harness.view.commitInlineTaskRename(id: id, typed: "Eggs")
        harness.manager.endUndoGrouping()
        #expect(task.title == "Eggs")
        #expect(harness.view.string == "Buy [[task:\(id.uuidString)|Eggs]] today")

        harness.manager.undo()
        #expect(task.title == "Milk", "undo left the task renamed")
        #expect(harness.view.string == "Buy [[task:\(id.uuidString)|Milk]] today")
        #expect(harness.view.markdownTaskEmbeds[id]?.title == "Milk", "the card was not repainted")
        #expect(try harness.tasks(titled: "Milk").map(\.id) == [id], "the store does not hold the undone title")

        harness.manager.redo()
        #expect(task.title == "Eggs", "redo did not rename the task forward")
        #expect(harness.view.string == "Buy [[task:\(id.uuidString)|Eggs]] today")

        harness.manager.undo()
        #expect(task.title == "Milk")
        #expect(harness.view.string == "Buy [[task:\(id.uuidString)|Milk]] today")
    }

    /// Undo never overwrites a title the task has been given elsewhere since: the text reverts,
    /// the task keeps the later name, and redo does not resurrect "Eggs" over it.
    @Test func undoOfAnInlineCardRenameLeavesATaskRenamedSince() throws {
        let (harness, task) = try Self.renameHarness()

        harness.manager.beginUndoGrouping()
        harness.view.commitInlineTaskRename(id: task.id, typed: "Eggs")
        harness.manager.endUndoGrouping()
        task.title = "Bread"
        try harness.modelContext.save()

        harness.manager.undo()
        #expect(task.title == "Bread", "undo overwrote a rename made after it")

        harness.manager.redo()
        #expect(task.title == "Bread", "redo overwrote a rename made after it")
    }

    // MARK: - [[T-18594]]: a reference-title sync is never an undo step of its own

    /// The task renamed outside the note's text -- the popover, the inline panel, a field chip --
    /// committed to the store and handed to the editor's embed table, as the host does. A longer
    /// title, so an earlier record replayed at stale offsets would show.
    private static func renameOutsideTheNote(_ task: AppTask, to title: String, in harness: EmbedHarness) throws {
        task.title = title
        try harness.modelContext.save()
        harness.view.markdownTaskEmbeds[task.id] = MarkdownTaskEmbedRenderInfo.task(task)
    }

    /// One outside-rename sync delivered as the app's event loop delivers it ([[T-18712]]):
    /// `groupsByEvent` on, so a registration made outside any group opens the event's own group
    /// lazily, and that group closed as the event ends. Not a group opened around the call: that
    /// would put the sync under `MarkdownReferenceTitleSyncUndo`'s already-grouped rule and make it
    /// a step of its own, the very thing these tests catch. Without this, a write that skipped the
    /// sync registered with no group open, `NSUndoManager` raised, AppKit swallowed it, and the
    /// test hung instead of failing.
    ///
    /// The close is Foundation's own end-of-event close. The test host never delivers that itself
    /// (measured: neither a run-loop turn, a main-actor yield nor a posted `NSEvent` closed the
    /// group), and a plain `endUndoGrouping()` leaves the manager still expecting it, so the next
    /// event's lazy open raises -- under mutant M5 the second sync in
    /// `aHoverExitAfterAnUndoKeepsTheRedo` hung exactly so. Where the selector is missing the plain close stands in; every test passes on
    /// it, only a mutant's second write would hang.
    private static func asOneEvent(_ manager: UndoManager, _ body: () -> Void) {
        manager.groupsByEvent = true
        body()
        let endEvent = Selector(("_endEventGroupingIfOpen"))
        if manager.responds(to: endEvent) { _ = manager.perform(endEvent) }
        while manager.groupingLevel > 0 { manager.endUndoGrouping() }
        manager.groupsByEvent = false
    }

    /// The defect: type, rename the task in its popover, close it, Cmd+Z -- the press took back the
    /// hidden reference title and left the typing. Now the press takes the typing back (the
    /// reference reads as it did then), the next press the typing before it, and redo replays both
    /// steps against the text they were recorded on.
    @Test func undoAfterAPopoverRenameTakesBackTheTypingNotTheHiddenTitle() throws {
        let (harness, task) = try Self.renameHarness()
        let id = task.id.uuidString
        Self.type(" one", atEndOf: harness.view, in: harness.manager)
        Self.type(" two", atEndOf: harness.view, in: harness.manager)

        try Self.renameOutsideTheNote(task, to: "Oat milk", in: harness)
        Self.asOneEvent(harness.manager) { harness.handlers.reconcileEmbeddedTaskReferenceTitles() }
        #expect(harness.view.string == "Buy [[task:\(id)|Oat milk]] today one two")

        harness.manager.undo()
        #expect(harness.view.string == "Buy [[task:\(id)|Milk]] today one", "the press landed on the hidden title")
        harness.manager.undo()
        #expect(harness.view.string == "Buy [[task:\(id)|Milk]] today")
        #expect(harness.manager.canUndo == false)

        harness.manager.redo()
        #expect(harness.view.string == "Buy [[task:\(id)|Milk]] today one")
        harness.manager.redo()
        #expect(harness.view.string == "Buy [[task:\(id)|Oat milk]] today one two")
        #expect(harness.manager.canRedo == false)
        #expect(task.title == "Oat milk", "undo is not meant to rename the task back")

        harness.manager.undo()
        #expect(harness.view.string == "Buy [[task:\(id)|Milk]] today one")
    }

    /// The inline panel's and field chip's saves take `refreshEmbeddedTask`: the same rule, and
    /// typing after the sync is its own step again.
    @Test func undoAfterAPanelSaveRenameTakesBackTheTyping() throws {
        let (harness, task) = try Self.renameHarness()
        let id = task.id.uuidString
        Self.type(" abc", atEndOf: harness.view, in: harness.manager)

        try Self.renameOutsideTheNote(task, to: "Oat milk", in: harness)
        Self.asOneEvent(harness.manager) { harness.handlers.refreshEmbeddedTask(task) }
        #expect(harness.view.string == "Buy [[task:\(id)|Oat milk]] today abc")
        Self.type(" def", atEndOf: harness.view, in: harness.manager)

        harness.manager.undo()
        #expect(harness.view.string == "Buy [[task:\(id)|Oat milk]] today abc")
        harness.manager.undo()
        #expect(harness.view.string == "Buy [[task:\(id)|Milk]] today", "the press landed on the hidden title")
        #expect(harness.manager.canUndo == false)
    }

    /// The pointer leaving a card after an undo must not empty the redo stack: the sync waits while
    /// there is something to redo, and catches up once there is not.
    @Test func aHoverExitAfterAnUndoKeepsTheRedo() throws {
        let (harness, task) = try Self.renameHarness()
        let id = task.id.uuidString
        let scope = TaskNotesEmbedScope(referenceTasks: [task], embedTarget: .coreNotes, modelContext: harness.modelContext)
        Self.type(" abc", atEndOf: harness.view, in: harness.manager)
        try Self.renameOutsideTheNote(task, to: "Oat milk", in: harness)
        Self.asOneEvent(harness.manager) { harness.handlers.reconcileEmbeddedTaskReferenceTitles() }

        harness.manager.undo()
        #expect(harness.view.string == "Buy [[task:\(id)|Milk]] today")
        Self.asOneEvent(harness.manager) {
            harness.handlers.hoverEmbeddedTask(
                id: task.id,
                hovering: false,
                in: scope,
                hoveredTaskManager: .shared,
                hoveredEditableManager: .shared
            )
        }
        #expect(harness.view.string == "Buy [[task:\(id)|Milk]] today")
        #expect(harness.manager.canRedo, "a hover exit emptied the redo stack")

        harness.manager.redo()
        #expect(harness.view.string == "Buy [[task:\(id)|Oat milk]] today abc")
    }

    /// With nothing on the stack there is no step for the sync to ride on, and it adds none.
    @Test func aSyncIntoAnUntouchedNoteAddsNoUndoStep() throws {
        let (harness, task) = try Self.renameHarness()
        try Self.renameOutsideTheNote(task, to: "Oat milk", in: harness)
        Self.asOneEvent(harness.manager) { harness.handlers.reconcileEmbeddedTaskReferenceTitles() }
        #expect(harness.view.string == "Buy [[task:\(task.id.uuidString)|Oat milk]] today")
        #expect(harness.manager.canUndo == false)
    }

    // MARK: - [[T-18963]]: an outside rename after the step that owns the card

    /// The defect: Return on `( ) Milk`, rename the card's task in its popover, Cmd+Z. The sync
    /// rode on the creation, whose withdrawal refused because the task no longer read "Milk" -- so
    /// the line came back beside an orphaned "Oat milk", and Return on it minted a second task.
    /// Now the one press takes the task out with the card, and redo puts the same task back renamed.
    @Test func undoAfterAnOutsideRenameOfAJustMadeCardTakesTheTaskBackOut() throws {
        let harness = try Self.embedHarness("( ) Milk")
        harness.handlers.editorTextView = harness.view
        harness.pressReturn()
        let task = try #require(try harness.tasks(titled: "Milk").first)
        let id = task.id

        try Self.renameOutsideTheNote(task, to: "Oat milk", in: harness)
        Self.asOneEvent(harness.manager) { harness.handlers.refreshEmbeddedTask(task) }
        #expect(harness.view.string.contains("[[task:\(id.uuidString)|Oat milk]]"))

        harness.manager.undo()
        #expect(harness.view.string == "( ) Milk")
        #expect(try harness.tasks(titled: "Oat milk").isEmpty, "undo left the renamed task orphaned in the store")
        #expect(try harness.tasks(titled: "Milk").isEmpty)

        harness.manager.redo()
        #expect(harness.view.string.contains("[[task:\(id.uuidString)|Oat milk]]"))
        #expect(try harness.tasks(titled: "Oat milk").map(\.id) == [id], "redo did not restore the same task, renamed")
        #expect(try harness.tasks(titled: "Milk").isEmpty)

        harness.manager.undo()
        #expect(harness.view.string == "( ) Milk")
        #expect(try harness.tasks(titled: "Oat milk").isEmpty, "a second undo after redo left the task")
    }

    /// Only the title is adopted: a just-made card whose task was also re-prioritised outside the
    /// note is still a task the user edited, and undo leaves it.
    @Test func undoAfterAnOutsideRenameStillLeavesATaskEditedOtherwise() throws {
        let harness = try Self.embedHarness("( ) Milk")
        harness.handlers.editorTextView = harness.view
        harness.pressReturn()
        let task = try #require(try harness.tasks(titled: "Milk").first)
        task.priority = .high
        try Self.renameOutsideTheNote(task, to: "Oat milk", in: harness)
        Self.asOneEvent(harness.manager) { harness.handlers.refreshEmbeddedTask(task) }

        harness.manager.undo()
        #expect(harness.view.string == "( ) Milk")
        #expect(try harness.tasks(titled: "Oat milk").count == 1, "undo deleted a task the user had edited")
    }

    /// The inline rename's own sync is not an outside rename: a card renamed inline straight after
    /// its Return still undoes as two steps -- the rename back to "Milk", then the task out.
    @Test func anInlineRenameAfterTheReturnStillUndoesBothSteps() throws {
        let harness = try Self.embedHarness("( ) Milk")
        let scope = TaskNotesEmbedScope(referenceTasks: [], embedTarget: .coreNotes, modelContext: harness.modelContext)
        harness.handlers.editorTextView = harness.view
        harness.view.onRenameEmbeddedMarkdownTask = { harness.handlers.renameEmbeddedTask(id: $0, title: $1, in: scope) }
        harness.pressReturn()
        let task = try #require(try harness.tasks(titled: "Milk").first)

        harness.manager.beginUndoGrouping()
        harness.view.commitInlineTaskRename(id: task.id, typed: "Eggs")
        harness.manager.endUndoGrouping()
        #expect(task.title == "Eggs")

        harness.manager.undo()
        #expect(task.title == "Milk")
        harness.manager.undo()
        #expect(harness.view.string == "( ) Milk")
        #expect(try harness.tasks(titled: "Milk").isEmpty, "the inline rename's own sync moved the creation's baseline")
    }

    /// The same shape after the card's inline rename: "Milk" -> "Eggs" inline, then "Oat milk" in
    /// the popover. The press used to refuse the rename back (the task no longer read "Eggs") and
    /// move only the hidden title. Now it renames the task back to "Milk", and redo forward again.
    @Test func undoAfterAnOutsideRenameOfAnInlineRenamedCardRenamesTheTaskBack() throws {
        let (harness, task) = try Self.renameHarness()
        let id = task.id.uuidString

        harness.manager.beginUndoGrouping()
        harness.view.commitInlineTaskRename(id: task.id, typed: "Eggs")
        harness.manager.endUndoGrouping()
        try Self.renameOutsideTheNote(task, to: "Oat milk", in: harness)
        Self.asOneEvent(harness.manager) { harness.handlers.refreshEmbeddedTask(task) }
        #expect(harness.view.string == "Buy [[task:\(id)|Oat milk]] today")

        harness.manager.undo()
        #expect(task.title == "Milk", "undo refused the rename back")
        #expect(harness.view.string == "Buy [[task:\(id)|Milk]] today")
        #expect(harness.manager.canUndo == false)

        harness.manager.redo()
        #expect(task.title == "Oat milk", "redo did not rename the task forward to its latest title")
        #expect(harness.view.string == "Buy [[task:\(id)|Oat milk]] today")
    }
}
#endif
