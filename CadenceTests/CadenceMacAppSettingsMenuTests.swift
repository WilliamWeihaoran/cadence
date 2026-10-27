// macOS only: the Cadence ▸ Settings… item and the root it routes to are macOS concerns.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-7232]] — Cadence ▸ Settings… exists, carries Cmd+, , and opens the Settings page.**
///
/// The app has no `Settings` scene, so SwiftUI left the app menu without a Settings… item and
/// Cmd+, reached nothing. Settings is an in-app page, so the item routes through
/// `CadenceMenuCommandRoute` to the same command table Cmd+K's "Settings" row runs.
///
/// The item and the route are values and are driven directly; the wiring — a `Commands` value on
/// a `Scene`, and the root's `.onChange` — cannot be built from this target, so it is pinned as
/// source, the way `CadenceMacNewItemMenuTests` pins the New Task item.
@MainActor
struct CadenceMacAppSettingsMenuTests {

    // MARK: - The item

    @Test func settingsCarriesCommandCommaAndRunsThePalettesSettingsCommand() {
        #expect(CadenceAppSettingsMenu.settings.title == "Settings…")
        #expect(CadenceAppSettingsMenu.settings.commandShortcut == ",")
        #expect(CadenceAppSettingsMenu.command == .settings)
        // Cmd+, is not also claimed by File ▸ New.
        #expect(!CadenceNewItemMenu.items.contains { $0.commandShortcut == CadenceAppSettingsMenu.settingsShortcut })
    }

    // MARK: - The route

    /// Each send is a new request, so a second Cmd+, — after the user has left Settings — still
    /// changes the token the root observes.
    @Test func everySendIsAFreshRequestForTheCommand() throws {
        let route = CadenceMenuCommandRoute()
        #expect(route.request == nil)

        route.send(.settings)
        let first = try #require(route.request)
        #expect(first.command == .settings)

        route.send(.settings)
        let second = try #require(route.request)
        #expect(second.command == .settings)
        #expect(second.token != first.token)
    }

    /// The routed request opens the Settings page exactly once, and dismisses Cmd+K so the palette
    /// does not stand over the page it opened.
    @Test func aRoutedSettingsRequestSelectsTheSettingsPageAndDismissesSearch() throws {
        let route = CadenceMenuCommandRoute()
        route.send(CadenceAppSettingsMenu.command)
        let request = try #require(route.request)

        var selections: [SidebarItem] = []
        var dismissals = 0
        var creations = 0
        RootCommandActionSupport.handleMenuCommand(
            request.command,
            clearAppEditingFocus: {},
            presentTaskCreation: { creations += 1 },
            setSelection: { selections.append($0) },
            dismissSearch: { dismissals += 1 }
        )

        #expect(selections == [.settings])
        #expect(dismissals == 1)
        #expect(creations == 0)
    }

    // MARK: - That it is installed

    @Test func theMenuReplacesTheAppSettingsGroupOnceAndBindsCommandComma() throws {
        let menu = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/macOSRootMenuCommands.swift")
        #expect(menu.contains("struct macOSRootMenuCommands: Commands"), "non-vacuity: the scan read the menu")
        let group = try #require(CadenceSourceScan.declarationBody("CommandGroup(replacing: .appSettings)", in: menu))
        #expect(group.contains("CadenceMenuCommandRoute.shared.send(CadenceAppSettingsMenu.command)"))
        #expect(group.contains("KeyEquivalent(CadenceAppSettingsMenu.settingsShortcut), modifiers: .command"))
        #expect(CadenceSourceScan.matchCount(#"\.keyboardShortcut\("#, in: group) == 1)

        var replacements = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let source = try CadenceSourceScan.strippedSourceReader()(path)
            replacements += CadenceSourceScan.matchCount(#"CommandGroup\(replacing: \.appSettings\)"#, in: source)
        }
        #expect(replacements == 1)
    }

    /// The root is the one observer of the route, and hands it to the menu-command arm.
    @Test func theRootObservesTheRouteAndRunsTheMenuCommand() throws {
        let root = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/macOSRootView.swift")
        #expect(root.contains("struct macOSRootView: View"), "non-vacuity: the scan read the root")
        #expect(CadenceSourceScan.matchCount(#"\.onChange\(of: menuCommandRoute\.request\?\.token\)"#, in: root) == 1)
        #expect(root.contains("RootCommandHandler.handleMenuCommand(request.command, context: makeSearchSelectionContext())"))
    }

    /// **No double fire.** The root key monitor sees Cmd+, before the menu does; it has no arm for
    /// keyCode 43, so the key reaches the menu item once and only there.
    @Test func theRootMonitorHasNoArmForCommandComma() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/macOSRootCommandEventSupport.swift")
        let handler = try #require(CadenceSourceScan.declarationBody("static func handleCommandKeyEvent", in: source))
        #expect(handler.contains("case 40:"), "non-vacuity: the scan read the whole shortcut table")
        #expect(CadenceSourceScan.matchCount(#"case[^:\n]*\b43\b"#, in: handler) == 0)
        #expect(!RootCommandTextEditingGate.hoverScopedKeyCodes.contains(43))
    }
}
#endif
