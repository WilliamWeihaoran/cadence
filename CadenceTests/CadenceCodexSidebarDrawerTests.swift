import Foundation
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexSidebarDrawerTests {
    #if os(macOS)
    @Test func codexSidebarResetsEveryExistingWidthOnce() throws {
        for oldWidth in [220.0, 249.6, 264, 390] {
            try withTemporaryDefaults("cadence.codex.sidebar", test: "reset\(oldWidth)") { defaults in
                defaults.set(oldWidth, forKey: CadenceMainSidebarWidthPreference.widthKey)
                #expect(CadenceMainSidebarWidthPreference.restore(in: defaults) == 320)
                #expect(defaults.double(forKey: CadenceMainSidebarWidthPreference.widthKey) == 320)
                #expect(defaults.bool(forKey: CadenceMainSidebarWidthPreference.resetKey))
                defaults.set(288, forKey: CadenceMainSidebarWidthPreference.widthKey)
                #expect(CadenceMainSidebarWidthPreference.restore(in: defaults) == 288)
            }
        }
    }

    @Test func codexSidebarResetMarkerAndLaterResizeSurviveReopeningTheSuite() throws {
        let scope = "cadence.codex.sidebar"
        let test = "reopen"
        try withTemporaryDefaults(scope, test: test) { defaults in
            #expect(CadenceMainSidebarWidthPreference.restore(in: defaults) == 320)
            defaults.set(350, forKey: CadenceMainSidebarWidthPreference.widthKey)
            let reopened = try #require(UserDefaults(suiteName: "\(scope).\(test)"))
            #expect(reopened.bool(forKey: CadenceMainSidebarWidthPreference.resetKey))
            #expect(CadenceMainSidebarWidthPreference.restore(in: reopened) == 350)
        }
    }

    @Test func codexSidebarMissingWidthStillHasTheNewDefaultAfterMigration() throws {
        try withTemporaryDefaults("cadence.codex.sidebar") { defaults in
            defaults.set(true, forKey: CadenceMainSidebarWidthPreference.resetKey)
            #expect(CadenceMainSidebarWidthPreference.restore(in: defaults) == 320)
        }
    }
    #endif

    /// Source wiring, not a claim about rendered pixels or VoiceOver traversal.
    @Test func codexDrawerKeepsOneDetailAndMakesTheMainPageInactive() throws {
        let rule = try CadenceScanInstrument(
            "drawer main-page isolation",
            fires: "detail().frame(width: detailWidth).clipped().allowsHitTesting(!isModal).accessibilityHidden(isModal).zIndex(0)",
            andNotOn: "detail().frame(width: detailWidth).clipped().allowsHitTesting(true).accessibilityHidden(false).zIndex(0)",
            by: { source in
                let code = CadenceSourceScan.codeOnly(source)
                guard let start = code.range(of: "detail()"),
                      let end = code.range(of: ".zIndex(0)", range: start.upperBound..<code.endIndex)
                else { return false }
                let chain = code[start.upperBound..<end.lowerBound]
                return chain.contains(".frame(width: detailWidth") && chain.contains(".clipped()")
                    && chain.contains(".allowsHitTesting(!isModal)")
                    && chain.contains(".accessibilityHidden(isModal)")
            }
        )
        let path = "Cadence/iOS/iOSRootSidebar.swift"
        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try rule.sweep([path], atLeast: 1, including: path, read: read) == [path])
        let root = try cadenceFunctionBody("struct iPadMacStyleRootShell<Content: View>: View",
                                           in: CadenceSourceScan.codeOnly(try read(path)))
        #expect(root.components(separatedBy: "detail()").count - 1 == 1)
        #expect(root.components(separatedBy: "iOSSidebar(").count - 1 == 1)
        #expect(root.contains("@State private var isDrawerPresented = false"))
        #expect(root.contains("let isDrawerMode = !CadenceRootShellLayout.usesExpandedSidebar(windowWidth: proxy.size.width)"))
        #expect(root.contains("let isModal = isDrawerMode && isDrawerPresented"))
        #expect(root.contains("style: .expanded"))
        #expect(root.contains("Theme.scrim"))
        #expect(root.contains(".keyboardShortcut(.escape, modifiers: [])"))
        #expect(root.contains(".accessibilityAction(.escape)"))
        let resize = try cadenceFunctionBody(".onChange(of: isDrawerMode)", in: root)
        #expect(resize.contains("isDrawerPresented = false"))
        #expect(!resize.contains("isSidebarCollapsed ="))
        let setter = try cadenceFunctionBody("private func setSidebarVisible", in: root)
        #expect(setter.contains("if isDrawerMode"))
        #expect(setter.contains("isDrawerPresented = visible"))
        #expect(setter.contains("isSidebarCollapsed = !visible"))
    }

    @Test func codexDrawerDestinationWritesDismissEvenWithoutASelectionChange() throws {
        let rule = try CadenceScanInstrument(
            "drawer dismisses from the selection binding setter",
            fires: "private func navigationSelection(isDrawerMode: Bool) -> Binding<iOSSidebarItem?> { Binding(get: { selection }, set: { selection = $0; if isDrawerMode { setSidebarVisible(false, isDrawerMode: true) } }) }",
            andNotOn: "private func navigationSelection(isDrawerMode: Bool) -> Binding<iOSSidebarItem?> { Binding(get: { selection }, set: { selection = $0 }) } // setSidebarVisible(false, isDrawerMode: true)",
            by: { source in
                let code = CadenceSourceScan.codeOnly(source)
                guard let function = CadenceSourceScan.functionBody(named: "navigationSelection", in: code),
                      let setter = CadenceSourceScan.declarationBody("set:", in: function)
                else { return false }
                return setter.contains("selection = $0") && setter.contains("if isDrawerMode")
                    && setter.contains("setSidebarVisible(false, isDrawerMode: true)")
                    && !setter.contains("selection !=") && !setter.contains("selection ==")
            }
        )
        let path = "Cadence/iOS/iOSRootSidebar.swift"
        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try rule.sweep([path], atLeast: 1, including: path, read: read) == [path])
        let code = CadenceSourceScan.codeOnly(try read(path))
        #expect(code.contains("selection: navigationSelection(isDrawerMode: isDrawerMode)"))
    }
}
