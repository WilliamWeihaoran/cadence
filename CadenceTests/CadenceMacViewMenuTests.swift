// macOS only: the View menu, the root key monitor and the root it routes to are macOS concerns.
#if os(macOS)
import AppKit
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-7203]] — View ▸ Search (Cmd+K), Toggle Sidebar (Cmd+O) and Toggle Timeline (Cmd+\).**
///
/// The three keys lived only in the root key monitor's arms, so the menu bar named none of them.
/// The menu now names them, and both the arms and the items run one body,
/// `RootCommandEventSupport.performViewCommand`. The arms consume the key before
/// `performKeyEquivalent`, so a press is handled once; the item acts only where the arm would have.
///
/// The items, the route and the gate are values and are driven directly; the `Commands` group and
/// the root's `.onChange` cannot be built from this target, so they are pinned as source, the way
/// `CadenceMacAppSettingsMenuTests` pins Cadence ▸ Settings….
@Suite(.serialized)
@MainActor
struct CadenceMacViewMenuTests {

    // MARK: - The items

    @Test func theViewMenuNamesSearchSidebarAndTimelineWithTheirKeys() {
        #expect(CadenceViewMenu.items.map(\.title) == ["Search", "Toggle Sidebar", "Toggle Timeline"])
        #expect(CadenceViewMenu.items.map(\.shortcut) == ["k", "o", "\\"])
        #expect(CadenceViewMenu.items.map(\.keyCode) == [40, 31, 42])
        #expect(CadenceViewMenu.items.map(\.command) == [.search, .toggleSidebar, .toggleTimeline])
        #expect(Set(CadenceViewMenu.items.map(\.command)) == Set(CadenceViewMenuCommand.allCases))
    }

    /// No View item takes a key another menu item already binds.
    @Test func noViewItemSharesAKeyWithFileNewOrSettings() {
        let others = CadenceNewItemMenu.items.compactMap(\.commandShortcut) + [CadenceAppSettingsMenu.settingsShortcut]
        for item in CadenceViewMenu.items {
            #expect(!others.contains(item.shortcut), "\(item.title)")
        }
    }

    /// The three keys name no hovered object, so they stay live while a text field is editing,
    /// as they did before the menu existed.
    @Test func theViewKeysAreNotHoverScoped() {
        for item in CadenceViewMenu.items {
            #expect(!RootCommandTextEditingGate.hoverScopedKeyCodes.contains(item.keyCode), "\(item.title)")
        }
    }

    // MARK: - The route

    @Test func everyViewMenuSendIsAFreshRequest() throws {
        let route = CadenceViewMenuRoute()
        #expect(route.request == nil)

        route.send(.toggleSidebar)
        let first = try #require(route.request)
        #expect(first.command == .toggleSidebar)

        route.send(.toggleSidebar)
        let second = try #require(route.request)
        #expect(second.command == .toggleSidebar)
        #expect(second.token != first.token)
    }

    // MARK: - One path

    /// The key and the item reach the same body: Cmd+O through the monitor arm and Toggle Sidebar
    /// through the menu handler each toggle the sidebar exactly once.
    @Test func theSidebarKeyAndTheSidebarItemEachToggleOnce() throws {
        let container = try CadenceTestStore.container()
        let window = makeWindow()
        defer { window.close() }
        try #require(window.makeFirstResponder(nil))
        try #require(DeleteConfirmationManager.shared.request == nil)
        try #require(HoveredTaskDatePickerManager.shared.request == nil)
        try #require(!GlobalSearchManager.shared.isPresented)

        var toggles = 0
        let context = makeContext(container.mainContext, toggleSidebar: { toggles += 1 })

        let event = try commandKeyEvent(CadenceViewMenu.toggleSidebar.keyCode, in: window)
        let result = RootCommandEventSupport.handleCommandKeyEvent(event, context: context)
        // `nil` is what keeps the press from reaching the menu item's key equivalent as well.
        #expect(result == nil)
        #expect(toggles == 1)

        RootCommandHandler.handleViewMenuCommand(.toggleSidebar, context: context)
        #expect(toggles == 2)
    }

    /// Every View key is consumed by its arm, which runs that item's command.
    @Test func everyViewArmConsumesItsKeyAndRunsItsCommand() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/macOSRootCommandEventSupport.swift")
        let handler = try #require(CadenceSourceScan.declarationBody("static func handleCommandKeyEvent", in: source))
        #expect(handler.contains("case 51:"), "non-vacuity: the scan read the whole shortcut table")
        for item in CadenceViewMenu.items {
            let pattern = #"case "# + String(item.keyCode)
                + #":\s*performViewCommand\(\.\#(item.command), context: context\)\s*return nil"#
            #expect(CadenceSourceScan.matchCount(pattern, in: handler) == 1, "\(item.title)")
        }
    }

    /// The item acts only in the states where the monitor would have run the key itself: behind a
    /// modal, over Cmd+K and over the quick-task panel the monitor hands the key on, and it must not
    /// reach the menu item from there and act after all.
    @Test func theMenuGateRunsOnlyWhereTheMonitorWouldHave() {
        #expect(RootViewMenuGate.runs(hasModal: false, isSearchPresented: false, isQuickTaskPanelVisible: false))
        #expect(!RootViewMenuGate.runs(hasModal: true, isSearchPresented: false, isQuickTaskPanelVisible: false))
        #expect(!RootViewMenuGate.runs(hasModal: false, isSearchPresented: true, isQuickTaskPanelVisible: false))
        #expect(!RootViewMenuGate.runs(hasModal: false, isSearchPresented: false, isQuickTaskPanelVisible: true))
    }

    // MARK: - That it is installed

    @Test func theMenuGroupBindsEveryItemThroughTheRoute() throws {
        let menu = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/macOSRootMenuCommands.swift")
        #expect(menu.contains("struct macOSRootMenuCommands: Commands"), "non-vacuity: the scan read the menu")
        let group = try #require(CadenceSourceScan.declarationBody("CommandGroup(before: .toolbar)", in: menu))
        #expect(group.contains("ForEach(CadenceViewMenu.items"))
        #expect(group.contains("CadenceViewMenuRoute.shared.send(item.command)"))
        #expect(group.contains("KeyEquivalent(item.shortcut), modifiers: .command"))
        // The existing replacements are kept.
        #expect(menu.contains("CommandGroup(replacing: .newItem)"))
        #expect(menu.contains("CommandGroup(replacing: .appSettings)"))
        // A `CommandMenu("View")` would draw a second View menu beside the system one.
        #expect(CadenceSourceScan.matchCount(#"CommandMenu\("#, in: menu) == 0)
    }

    @Test func theRootObservesTheRouteAndRunsTheGatedHandler() throws {
        let root = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/macOSRootView.swift")
        #expect(root.contains("struct macOSRootView: View"), "non-vacuity: the scan read the root")
        #expect(CadenceSourceScan.matchCount(#"\.onChange\(of: viewMenuRoute\.request\?\.token\)"#, in: root) == 1)
        #expect(root.contains("RootCommandHandler.handleViewMenuCommand(request.command, context: makeCommandContext())"))
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
        try #require(event.window === window)
        return event
    }

    private func makeContext(_ modelContext: ModelContext, toggleSidebar: @escaping () -> Void) -> RootCommandContext {
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
            toggleSidebarVisibility: toggleSidebar
        )
    }
}
#endif
