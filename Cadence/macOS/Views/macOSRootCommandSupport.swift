#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import EventKit

struct RootCommandContext {
    var selection: SidebarItem?
    var showTimelineSidebar: Bool
    let modelContext: ModelContext
    let deleteConfirmationManager: DeleteConfirmationManager
    let hoveredTaskDatePickerManager: HoveredTaskDatePickerManager
    let taskCreationManager: TaskCreationManager
    let todayTimelineFocusManager: TodayTimelineFocusManager
    let globalSearchManager: GlobalSearchManager
    let hoveredTaskManager: HoveredTaskManager
    let hoveredEditableManager: HoveredEditableManager
    let hoveredKanbanColumnManager: HoveredKanbanColumnManager
    let hoveredSectionManager: HoveredSectionManager
    let taskCompletionAnimationManager: TaskCompletionAnimationManager
    let taskSubtaskEntryManager: TaskSubtaskEntryManager
    let clearAppEditingFocus: () -> Void
    let setShowTimelineSidebar: (Bool) -> Void
    let toggleSidebarVisibility: () -> Void
}

struct RootSearchSelectionContext {
    let modelContext: ModelContext
    let calendarManager: CalendarManager
    let globalSearchManager: GlobalSearchManager
    let listNavigationManager: ListNavigationManager
    let notesNavigationManager: NotesNavigationManager
    let calendarNavigationManager: CalendarNavigationManager
    let clearAppEditingFocus: () -> Void
    let setSelection: (SidebarItem) -> Void
    let presentTaskCreation: () -> Void
    /// [[T-5300]] — raises `TaskDetailPopover` for a task picked in Cmd+K, which has no row on
    /// screen to attach a popover to.
    let presentTaskInspector: (UUID) -> Void
}

/// [[T-7203]] — when a View-menu item may act: exactly the states in which
/// `RootCommandHandler.handle` reaches `handleCommandKeyEvent` for its key.
nonisolated enum RootViewMenuGate {
    static func runs(hasModal: Bool, isSearchPresented: Bool, isQuickTaskPanelVisible: Bool) -> Bool {
        !hasModal && !isSearchPresented && !isQuickTaskPanelVisible
    }
}

/// **[[T-18603]] — which root a command is for, once File ▸ New Window has made two.**
///
/// Every `macOSRootView` installs its own app-wide key monitor and observes the same `.shared`
/// routes, so with two windows open Cmd+O / Cmd+\ / Cmd+K ran in whichever monitor AppKit called
/// first (folding the OTHER window's sidebar), a View-menu item or Settings… ran in both, and a
/// Cmd+K pick moved both windows. A command now belongs to the root whose window is the app's
/// main window -- the one in front, which stays main while a sheet, popover or menu of it is key.
///
/// **Either side unknown claims**, which is exactly the one-window behaviour before this: a root
/// that has not joined a window yet, or no main window at all (the app inactive), still acts
/// rather than dropping the command.
nonisolated enum RootWindowAddressing {
    static func claims(ownWindow: AnyObject?, mainWindow: AnyObject?) -> Bool {
        guard let ownWindow, let mainWindow else { return true }
        return ownWindow === mainWindow
    }
}

/// A root's own window, learned by `RootWindowReader`. A reference, so the key monitor's closure,
/// the root's route observers and the pages below (through `cadenceRootWindowHandle`) share one,
/// and learning the window re-renders nothing; weak, so a closed window is not kept.
@MainActor
final class RootWindowHandle {
    weak var window: NSWindow?

    init() {}

    /// Whether a command arriving now is this root's ([[T-18603]]).
    func isAddressed() -> Bool {
        isAddressed(mainWindow: NSApp.mainWindow)
    }

    func isAddressed(mainWindow: NSWindow?) -> Bool {
        RootWindowAddressing.claims(ownWindow: window, mainWindow: mainWindow)
    }
}

extension EnvironmentValues {
    /// [[T-18603]]: the enclosing root's window, for a page that takes a `.shared` navigation
    /// request or keeps a key monitor of its own. `nil` outside a root, which claims.
    @Entry var cadenceRootWindowHandle: RootWindowHandle? = nil
}

/// Hands the root's window to its `RootWindowHandle` as the view joins one, the shape of
/// `CreateTaskHostWindowReader`.
struct RootWindowReader: NSViewRepresentable {
    let handle: RootWindowHandle

    func makeNSView(context: NSViewRepresentableContext<RootWindowReader>) -> RootWindowReaderView {
        let view = RootWindowReaderView()
        view.handle = handle
        return view
    }

    func updateNSView(_ nsView: RootWindowReaderView, context: NSViewRepresentableContext<RootWindowReader>) {
        nsView.handle = handle
        handle.window = nsView.window
    }
}

final class RootWindowReaderView: NSView {
    weak var handle: RootWindowHandle?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        handle?.window = window
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

enum RootCommandHandler {
    static func handle(_ event: NSEvent, context: RootCommandContext) -> NSEvent? {
        switch RootCommandEventSupport.handleModalConfirmations(event, context: context) {
        case .act:
            return nil
        case .passToOverlay:
            return event
        case .noModal:
            break
        }

        if context.globalSearchManager.isPresented {
            return RootCommandEventSupport.handlePresentedGlobalSearch(event, context: context)
        }

        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else {
            return event
        }

        if QuickTaskPanelController.shared.isVisible {
            return event
        }

        return RootCommandEventSupport.handleCommandKeyEvent(event, context: context)
    }

    /// **[[T-7203]] — a View-menu item, as `CadenceViewMenuRoute` hands it over.**
    ///
    /// The item runs only where `handle(_:context:)` would have run its key: the monitor hands
    /// Cmd+K / Cmd+O / Cmd+\ on to the responder chain behind a modal, with Cmd+K open and over
    /// the quick-task panel, and from there the key reaches the menu item's key equivalent. The
    /// gate keeps that from opening Search behind a delete confirmation, which the key alone never
    /// could.
    ///
    /// [[T-16050]]: the panel's visibility is a parameter because it is the one gate input the
    /// context does not carry. Read from the singleton inside, a test could pin the other three
    /// and still not this one, and a quick panel left up in the test host (the host registers the
    /// global ⌃Space, [[T-18294]]) closed the gate for a test that never touched it.
    static func handleViewMenuCommand(
        _ command: CadenceViewMenuCommand,
        context: RootCommandContext,
        isQuickTaskPanelVisible: Bool = QuickTaskPanelController.shared.isVisible
    ) {
        guard RootViewMenuGate.runs(
            hasModal: context.deleteConfirmationManager.request != nil
                || context.hoveredTaskDatePickerManager.request != nil,
            isSearchPresented: context.globalSearchManager.isPresented,
            isQuickTaskPanelVisible: isQuickTaskPanelVisible
        ) else { return }
        RootCommandEventSupport.performViewCommand(command, context: context)
    }

    static func handleSearchSelection(_ result: GlobalSearchResult, context: RootSearchSelectionContext) {
        RootCommandActionSupport.handleSearchSelection(result, context: context)
    }

    /// [[T-18440]]: the panel defaults to the singleton here, as in `handleViewMenuCommand`.
    static func handleMenuCommand(
        _ command: GlobalSearchCommand,
        context: RootSearchSelectionContext,
        hasModal: Bool,
        isQuickTaskPanelVisible: Bool = QuickTaskPanelController.shared.isVisible
    ) {
        RootCommandActionSupport.handleMenuCommand(
            command,
            context: context,
            hasModal: hasModal,
            isQuickTaskPanelVisible: isQuickTaskPanelVisible
        )
    }
}
#endif
