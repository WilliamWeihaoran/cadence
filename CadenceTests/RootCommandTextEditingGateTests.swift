#if os(macOS)
import AppKit
import SwiftData
import Testing
@testable import Cadence

/// The root key monitor while a text field is editing (T-5800), and its Cmd+Return arm while the
/// in-window New Task panel is up (T-5802).
///
/// The monitor is an app-wide local monitor, so it sees every key before the first responder.
/// T-5800: the hover-scoped shortcuts acted on the task under the pointer while the user typed —
/// Cmd+Delete, the system's "delete to start of line", asked to delete that task. T-5802: with the
/// panel up, the Cmd+Return arm returned `nil`, which swallowed the key before the panel's Create
/// button (`.keyboardShortcut(.return, modifiers: [.command])`) could take it.
///
/// The handler tests build their own offscreen window and synthesize the `NSEvent` against it;
/// nothing is dispatched, so no real responder sees the key.
@Suite(.serialized)
@MainActor
struct RootCommandTextEditingGateTests {
    private static let hoverScopedKeys: [UInt16] = [51, 36, 76, 17, 2, 35, 44, 1, 24, 27, 14, 45]
    /// Cmd+K, Cmd+\ and Cmd+O name no hovered object.
    private static let globalKeys: [UInt16] = [40, 42, 31]
    private static let priorityKey: UInt16 = 35
    private static let returnKey: UInt16 = 36

    @Test func everyHoverScopedKeyPassesThroughWhileEditingText() {
        for key in Self.hoverScopedKeys {
            #expect(RootCommandTextEditingGate.passesThrough(keyCode: key, isEditingText: true), "key \(key)")
            #expect(!RootCommandTextEditingGate.passesThrough(keyCode: key, isEditingText: false), "key \(key)")
        }
        #expect(RootCommandTextEditingGate.hoverScopedKeyCodes == Set(Self.hoverScopedKeys))
    }

    @Test func globalShortcutsStayGlobalWhileEditingText() {
        for key in Self.globalKeys {
            #expect(!RootCommandTextEditingGate.passesThrough(keyCode: key, isEditingText: true), "key \(key)")
        }
    }

    @Test func onlyAnEditableTextViewCountsAsEditing() {
        let editable = NSTextView(frame: .zero)
        editable.isEditable = true
        let readOnly = NSTextView(frame: .zero)
        readOnly.isEditable = false

        #expect(RootCommandTextEditingGate.isEditingText(editable))
        #expect(!RootCommandTextEditingGate.isEditingText(readOnly))
        #expect(!RootCommandTextEditingGate.isEditingText(nil))
        #expect(!RootCommandTextEditingGate.isEditingText(NSButton(frame: .zero)))
    }

    @Test func aTextFieldsFieldEditorCountsAsEditing() throws {
        // A SwiftUI `TextField` edits through its window's field editor, not a text view of its own.
        let window = makeWindow()
        defer { window.close() }
        let editor = try #require(window.fieldEditor(true, for: nil))
        #expect(RootCommandTextEditingGate.isEditingText(editor))
    }

    @Test func aHoverShortcutTypedIntoATextViewReachesTheTextNotTheHoveredTask() throws {
        let container = try CadenceTestStore.container()
        let modelContext = container.mainContext
        let task = AppTask(title: "Parent")
        modelContext.insert(task)
        try modelContext.save()
        let before = task.priority

        let window = makeWindow()
        defer { window.close() }
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        textView.isEditable = true
        window.contentView?.addSubview(textView)
        try #require(window.makeFirstResponder(textView))

        HoveredTaskManager.shared.clear()
        HoveredTaskManager.shared.beginHovering(task, source: .list)
        defer { HoveredTaskManager.shared.clear() }
        try #require(HoveredTaskManager.shared.hoveredTask?.id == task.id)

        let event = try commandKeyEvent(Self.priorityKey, in: window)
        let result = RootCommandEventSupport.handleCommandKeyEvent(event, context: makeContext(modelContext))

        #expect(result === event)
        #expect(task.priority == before)

        // Scope control: the same key with nothing editing still acts on the hovered task.
        textView.isEditable = false
        let control = RootCommandEventSupport.handleCommandKeyEvent(event, context: makeContext(modelContext))
        #expect(control == nil)
        #expect(task.priority != before)
    }

    @Test func commandReturnReachesTheNewTaskPanelInsteadOfBeingSwallowed() throws {
        let container = try CadenceTestStore.container()
        let window = makeWindow()
        defer { window.close() }
        // Nothing editing, so this is the panel guard's answer, not the text-editing gate's.
        try #require(window.makeFirstResponder(nil))
        try #require(!RootCommandTextEditingGate.isEditingText(window.firstResponder))

        TaskCreationManager.shared.isPresented = true
        defer { TaskCreationManager.shared.isPresented = false }

        let event = try commandKeyEvent(Self.returnKey, in: window)
        let result = RootCommandEventSupport.handleCommandKeyEvent(event, context: makeContext(container.mainContext))

        #expect(result === event)
    }

    // MARK: - Fixtures

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func commandKeyEvent(_ keyCode: UInt16, in window: NSWindow) throws -> NSEvent {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
        // Non-vacuity: the handler reads the first responder of `event.window`.
        try #require(event.window === window)
        return event
    }

    private func makeContext(_ modelContext: ModelContext) -> RootCommandContext {
        RootCommandContext(
            selection: nil,
            showTimelineSidebar: false,
            modelContext: modelContext,
            deleteConfirmationManager: .shared,
            hoveredTaskDatePickerManager: .shared,
            taskCreationManager: .shared,
            todayTimelineFocusManager: .shared,
            globalSearchManager: .shared,
            hoveredTaskManager: .shared,
            hoveredEditableManager: .shared,
            hoveredKanbanColumnManager: .shared,
            hoveredSectionManager: .shared,
            taskCompletionAnimationManager: .shared,
            taskSubtaskEntryManager: .shared,
            clearAppEditingFocus: {},
            setShowTimelineSidebar: { _ in },
            toggleSidebarVisibility: {}
        )
    }
}
#endif
