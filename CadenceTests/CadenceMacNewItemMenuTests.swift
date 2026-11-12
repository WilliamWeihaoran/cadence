// macOS only: the File ▸ New group and the window group it reopens are macOS concerns.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-5953]] — Cmd+N is New Task everywhere, and File ▸ New Window keeps its item without the
/// shortcut.**
///
/// Off a Kanban column the root key monitor handed Cmd+N on, and with no `.commands` anywhere in
/// `Cadence/` it reached SwiftUI's own File ▸ New Window. The app is built for one window: the
/// New Task panel, Cmd+K search and the delete confirmation are driven by `.shared` managers
/// injected once, so each drew in both windows at once — over one SwiftData store behind
/// CloudKit, which makes a second window two writers rather than only a duplicated surface.
///
/// Two kinds of test, for the reason the repo's other menu-shaped pins give. The group's contents
/// are a value type and are read directly; the *wiring* — a `Commands` value attached to a
/// `Scene` — cannot be built or keyed from this target, so it is pinned as source with exact
/// counts, and each scan asserts something that proves it read code rather than prose.
@MainActor
struct CadenceMacNewItemMenuTests {

    // MARK: - What the group offers

    @Test func newTaskCarriesCommandNAndNewWindowCarriesNoShortcut() {
        #expect(CadenceNewItemMenu.newTask.title == "New Task")
        #expect(CadenceNewItemMenu.newTask.commandShortcut == "n")
        #expect(CadenceNewItemMenu.newWindow.title == "New Window")
        #expect(
            CadenceNewItemMenu.newWindow.commandShortcut == nil,
            "New Window took Cmd+N back, which is the whole defect"
        )
    }

    /// The shortcut is claimed exactly once. A second item binding Cmd+N is the ambiguity that
    /// sends the key somewhere the owner did not choose.
    @Test func exactlyOneItemInTheGroupBindsCommandN() {
        let bound = CadenceNewItemMenu.items.filter { $0.commandShortcut == CadenceNewItemMenu.newTaskShortcut }
        #expect(bound == [CadenceNewItemMenu.newTask])
        #expect(CadenceNewItemMenu.items.count == 2)
        #expect(CadenceNewItemMenu.items.contains(CadenceNewItemMenu.newWindow))
    }

    // MARK: - That the group is actually installed

    /// **The replacement is the fix.** Without `CommandGroup(replacing: .newItem)` the default
    /// New Window item stays, with its Cmd+N, whatever the table above says.
    @Test func theAppReplacesSwiftUIsNewItemGroupExactlyOnce() throws {
        let menu = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/macOSRootMenuCommands.swift")
        #expect(menu.contains("struct macOSRootMenuCommands: Commands"), "non-vacuity: the scan read the menu")
        #expect(CadenceSourceScan.matchCount(#"CommandGroup\(replacing: \.newItem\)"#, in: menu) == 1)

        // The menu's own file is the only place in the app that replaces a command group, so a
        // second one cannot quietly re-add a Cmd+N elsewhere.
        var replacements = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let source = try CadenceSourceScan.strippedSourceReader()(path)
            replacements += CadenceSourceScan.matchCount(#"CommandGroup\(replacing: \.newItem\)"#, in: source)
        }
        #expect(replacements == 1)
    }

    /// One `.keyboardShortcut` in the whole group: New Task's. New Window's absence is the owner's
    /// decision and cannot be asserted by its presence anywhere, only by this count.
    @Test func theGroupBindsOneKeyEquivalentAndItIsNewTasks() throws {
        let menu = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/macOSRootMenuCommands.swift")
        let group = try #require(CadenceSourceScan.declarationBody("CommandGroup(replacing: .newItem)", in: menu))
        #expect(CadenceSourceScan.matchCount(#"\.keyboardShortcut\("#, in: group) == 1)
        // [[T-7232]]: Settings…'s Cmd+, , in its own group; [[T-7203]]: the View group's one,
        // written once inside the `ForEach` over `CadenceViewMenu.items`.
        #expect(CadenceSourceScan.matchCount(#"\.keyboardShortcut\("#, in: menu) == 3)
        #expect(menu.contains("KeyEquivalent(CadenceNewItemMenu.newTaskShortcut), modifiers: .command"))
        // [[T-17170]]: New Task goes through the menu route to Cmd+K's own New Task command, never
        // straight at the manager, which skipped the palette's dismissal and every modal gate.
        #expect(group.contains("CadenceMenuCommandRoute.shared.send(CadenceNewItemMenu.newTaskCommand)"), "Cmd+N no longer opens the New Task panel")
        #expect(!group.contains("TaskCreationManager.shared.present()"), "New Task bypasses the route again")
        #expect(menu.contains("openWindow(id: CadenceWindowGroupID.main)"), "New Window opens nothing")
    }

    /// **[[T-17170]] — File ▸ New Task is Cmd+K's New Task row.** It clears editing focus, opens
    /// the panel once, and closes the palette, which the direct `present()` it used to call left
    /// standing over the panel.
    @Test func newTaskRunsThePalettesNewTaskCommandAndClosesSearch() throws {
        #expect(CadenceNewItemMenu.newTaskCommand == .newTask)

        let route = CadenceMenuCommandRoute()
        route.send(CadenceNewItemMenu.newTaskCommand)
        let request = try #require(route.request)

        var selections: [SidebarItem] = []
        var dismissals = 0
        var creations = 0
        var focusClears = 0
        RootCommandActionSupport.handleMenuCommand(
            request.command,
            hasModal: false,
            clearAppEditingFocus: { focusClears += 1 },
            presentTaskCreation: { creations += 1 },
            setSelection: { selections.append($0) },
            dismissSearch: { dismissals += 1 }
        )

        #expect(creations == 1)
        #expect(dismissals == 1)
        #expect(focusClears == 1)
        #expect(selections.isEmpty)
    }

    /// The scene half: the commands have to be attached, and the window group has to be named for
    /// "New Window" to have something to open now that SwiftUI's own item is gone.
    @Test func theMacSceneAttachesTheCommandsAndNamesItsWindowGroup() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/CadenceApp.swift")
        let source = CadenceSourceScan.strippingComments(raw)
        // Non-vacuity: the reader read the file and the stripper took the prose with it.
        #expect(source.contains("struct CadenceApp: App"))
        #expect(raw.contains("T-5953. The app's only `.commands`"))
        #expect(!source.contains("T-5953. The app's only `.commands`"))

        #expect(CadenceSourceScan.matchCount(#"\.commands \{ macOSRootMenuCommands\(\) \}"#, in: source) == 1)
        #expect(CadenceSourceScan.matchCount(#"WindowGroup\(id: CadenceWindowGroupID\.main\)"#, in: source) == 1)
        #expect(
            CadenceSourceScan.matchCount(#"WindowGroup \{"#, in: source) == 0,
            "an unidentified WindowGroup has no id for New Window to open"
        )
    }

    /// The monitor's Cmd+N arm is unchanged in substance and must stay that way: over a Kanban
    /// column the key makes a card in *that* column, and only an unclaimed one reaches the menu.
    @Test func theRootMonitorStillLetsAKanbanColumnClaimCommandNFirst() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/macOSRootCommandEventSupport.swift")
        let handler = try #require(CadenceSourceScan.declarationBody("static func handleCommandKeyEvent", in: source))
        #expect(handler.contains("if context.hoveredKanbanColumnManager.triggerCreateTask() { return nil }"))
        #expect(handler.contains("case 40:"), "non-vacuity: the scan read the whole shortcut table")
    }
}
#endif
