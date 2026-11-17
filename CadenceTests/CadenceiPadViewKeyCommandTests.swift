#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// [[T-17173]]. **On an iPad hardware keyboard, Cmd+, opens Settings, Cmd+O toggles the sidebar and
/// Cmd+\ toggles the timeline, as they do on the Mac.** The iPad bound Cmd+K and Cmd+N alone
/// ([[T-8766]], [[T-13281]]). `Cadence/iOS/` is invisible to this macOS target and a hardware key
/// cannot be pressed from it, so the wiring is read from source, for the reason
/// `CadenceiPadSearchKeyCommandTests` gives. The keys and titles are compared with the Mac's own
/// menu data, so editing one platform's key cannot leave the other behind.
@Suite
struct CadenceiPadViewKeyCommandTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    private static func literal(_ character: Character) -> String {
        "\"" + String(character).replacingOccurrences(of: "\\", with: "\\\\") + "\""
    }

    private static func iOSCode() throws -> [String: String] {
        let folder = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence/iOS")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var code: [String: String] = [:]
        for file in files {
            code[file.lastPathComponent] = try Self.code("Cadence/iOS/\(file.lastPathComponent)")
        }
        return code
    }

    @Test func theKeysAndTitlesAreTheMacItemsOwn() throws {
        let keys = try Self.code("Cadence/iOS/iOSHardwareKeyCommands.swift")
        #expect(keys.contains("static let settingsKey: Character = \(Self.literal(CadenceAppSettingsMenu.settingsShortcut))"))
        #expect(keys.contains("static let toggleSidebarTitle = \"\(CadenceViewMenu.toggleSidebar.title)\""))
        #expect(keys.contains("static let toggleSidebarKey: Character = \(Self.literal(CadenceViewMenu.toggleSidebar.shortcut))"))
        #expect(keys.contains("static let toggleTimelineTitle = \"\(CadenceViewMenu.toggleTimeline.title)\""))
        #expect(keys.contains("static let toggleTimelineKey: Character = \(Self.literal(CadenceViewMenu.toggleTimeline.shortcut))"))
        // "Settings…" on the Mac opens a window; on the iPad the key navigates to a page.
        #expect(keys.contains("static let settingsTitle = \"Settings\""))
    }

    /// The same zero-size, transparent button Cmd+K and Cmd+N ride on, never `.hidden()`.
    @Test func theHelperBindsThePlainCommandKeyOnATransparentButton() throws {
        let keys = try Self.code("Cadence/iOS/iOSHardwareKeyCommands.swift")
        let helper = try #require(CadenceSourceScan.functionBody(named: "iOSCommandKey", in: keys))
        #expect(helper.contains("Button(title, action: action)\n                .keyboardShortcut(KeyEquivalent(key), modifiers: .command)"))
        #expect(helper.contains(".opacity(0)"))
        #expect(helper.contains(".frame(width: 0, height: 0)"))
        #expect(!helper.contains(".hidden()"))
    }

    /// Each key is bound exactly once in the iOS sources, by the surface that owns its state.
    @Test func eachKeyIsBoundOnceByItsOwner() throws {
        let code = try Self.iOSCode()
        #expect(code.count > 50, "the iOS folder scan found almost nothing")
        let owners: [(String, String)] = [
            ("iOSCommandKey(iOSHardwareKeyCommand.settingsTitle, key: iOSHardwareKeyCommand.settingsKey)", "iOSRootView.swift"),
            ("iOSCommandKey(iOSHardwareKeyCommand.toggleSidebarTitle, key: iOSHardwareKeyCommand.toggleSidebarKey)", "iOSRootSidebar.swift"),
            ("iOSCommandKey(iOSHardwareKeyCommand.toggleTimelineTitle, key: iOSHardwareKeyCommand.toggleTimelineKey)", "iOSTodayView.swift")
        ]
        for (call, owner) in owners {
            let perFile = code.compactMapValues { text -> Int? in
                let count = text.components(separatedBy: call).count - 1
                return count > 0 ? count : nil
            }
            #expect(perFile == [owner: 1], "\(call)")
        }
        // Nothing else in the iOS folder spends the three keys.
        for key in [CadenceAppSettingsMenu.settingsShortcut, CadenceViewMenu.toggleSidebar.shortcut, CadenceViewMenu.toggleTimeline.shortcut] {
            for (file, text) in code {
                #expect(!text.contains(".keyboardShortcut(\(Self.literal(key))"), "\(file) binds \(key)")
            }
        }
    }

    /// Cmd+, takes Settings' route on both shells, the way Cmd+K's `openSearch` takes Search's.
    @Test func commandCommaRoutesBothShellsToSettings() throws {
        let root = try Self.code("Cadence/iOS/iOSRootView.swift")
        let call = "iOSCommandKey(iOSHardwareKeyCommand.settingsTitle, key: iOSHardwareKeyCommand.settingsKey)"
        let body = try #require(CadenceSourceScan.declarationBody(call, in: root))
        #expect(body.contains("selection = CadenceFeatureDestination.settings.item"))
        #expect(body.contains("apply(CadenceFeatureDestination.settings.compactRoute)"))
        #expect(CadenceFeatureDestination.settings.compactRoute.pushedDestination == .settings)
    }

    /// Cmd+O flips what is on screen: the docked fold, or the drawer below the docking width.
    @Test func commandOTogglesTheSidebarThatIsDrawn() throws {
        let shell = try Self.code("Cadence/iOS/iOSRootSidebar.swift")
        let root = try cadenceFunctionBody("struct iPadMacStyleRootShell<Content: View>: View", in: shell)
        let call = "iOSCommandKey(iOSHardwareKeyCommand.toggleSidebarTitle, key: iOSHardwareKeyCommand.toggleSidebarKey)"
        let body = try #require(CadenceSourceScan.declarationBody(call, in: root))
        #expect(body.contains("setSidebarVisible(!isSidebarVisible, isDrawerMode: isDrawerMode)"))
        #expect(root.contains("let isSidebarVisible = isDrawerMode ? isDrawerPresented : !isSidebarCollapsed"))
    }

    /// Cmd+\ is bound on the two-pane Today only, and flips its inspector pane.
    @Test func commandBackslashFlipsTodaysInspectorPaneInTheTwoPaneLayoutOnly() throws {
        let today = try Self.code("Cadence/iOS/iOSTodayView.swift")
        let call = "iOSCommandKey(iOSHardwareKeyCommand.toggleTimelineTitle, key: iOSHardwareKeyCommand.toggleTimelineKey)"
        let twoPane = try #require(CadenceSourceScan.functionBody(named: "twoPaneTodayLayout", in: today))
        #expect(twoPane.contains(call))
        let compact = try #require(CadenceSourceScan.functionBody(named: "compactTodayLayout", in: today))
        #expect(!compact.contains(call))
        let body = try #require(CadenceSourceScan.declarationBody(call, in: today))
        #expect(body.contains("sidePanelRaw = sidePanel.togglingTimeline.rawValue"))

        let keys = try Self.code("Cadence/iOS/iOSHardwareKeyCommands.swift")
        let toggle = try #require(CadenceSourceScan.declarationBody("var togglingTimeline: iOSTodaySidePanel", in: keys))
        #expect(toggle.contains("self == .timeline ? .notes : .timeline"))
    }

    /// The note editor's text view is the one iOS responder with its own key table; it must leave
    /// the three plain Cmd-keys unbound so the shell's bindings are reached while typing.
    @Test func theNoteEditorLeavesTheThreeKeysUnbound() throws {
        let editor = try Self.code("Cadence/iOS/iOSMarkdownTextView.swift")
        #expect(editor.contains("command(\"k\", [.command, .shift],"), "non-vacuity: the key table moved")
        for key in [CadenceAppSettingsMenu.settingsShortcut, CadenceViewMenu.toggleSidebar.shortcut, CadenceViewMenu.toggleTimeline.shortcut] {
            #expect(!editor.contains("command(\(Self.literal(key)), [.command],"))
            #expect(!editor.contains("input: \(Self.literal(key)), modifierFlags: .command"))
        }
    }
}
#endif
