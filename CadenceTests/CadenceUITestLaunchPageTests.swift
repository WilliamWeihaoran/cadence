import Foundation
import Testing

@testable import Cadence

/// **[[T-3200]] — the launch-page selector, pinned from both sides.**
///
/// `CADENCE_UI_TEST_PAGE` lets a seeded agent launch open on a named root page so a window capture
/// can reach it. The hazard is the inverse: a shipping launch that could be steered off Today by a
/// stray variable. So the gate is what is under test, with literal environment dictionaries, plus
/// one scan that the root's initial selection is actually routed through it.
@Suite("UI-test launch page (T-3200)")
struct CadenceUITestLaunchPageTests {

    private static let mode = CadenceEventKitLaunchGate.uiTestModeVariable
    private static let page = CadenceUITestLaunchPage.pageVariable

    @Test func theVariableIsSpelledOnce() {
        #expect(Self.page == "CADENCE_UI_TEST_PAGE")
    }

    @Test func nothingAskedMeansTheAppDecides() {
        #expect(CadenceUITestLaunchPage.requested(in: [:]) == nil)
        #expect(CadenceUITestLaunchPage.requested(in: [Self.mode: "1"]) == nil)
        #expect(CadenceUITestLaunchPage.requested(in: [Self.mode: "1", Self.page: ""]) == nil)
    }

    /// The shipping-launch claim: the page variable alone, or with the mode set to anything but
    /// `1`, is ignored.
    @Test func thePageWithoutUITestModeIsIgnored() {
        #expect(CadenceUITestLaunchPage.requested(in: [Self.page: "calendar"]) == nil)
        #expect(CadenceUITestLaunchPage.requested(in: [Self.mode: "0", Self.page: "calendar"]) == nil)
        #expect(CadenceUITestLaunchPage.requested(in: [Self.mode: "true", Self.page: "calendar"]) == nil)
    }

    @Test func anUnknownPageIsIgnored() {
        #expect(CadenceUITestLaunchPage.requested(in: [Self.mode: "1", Self.page: "Calendar"]) == nil)
        #expect(CadenceUITestLaunchPage.requested(in: [Self.mode: "1", Self.page: "bogus"]) == nil)
    }

    @Test func everyPageIsReachableByItsRawValue() {
        #expect(CadenceUITestLaunchPage.allCases.count == 7)
        for page in CadenceUITestLaunchPage.allCases {
            #expect(CadenceUITestLaunchPage.requested(in: [Self.mode: "1", Self.page: page.rawValue]) == page)
        }
    }

    /// A launch that can be steered here is a launch EventKit is disarmed for.
    @Test func aSteerableLaunchIsAnEventKitDisarmedLaunch() {
        for page in CadenceUITestLaunchPage.allCases {
            let environment = [Self.mode: "1", Self.page: page.rawValue]
            #expect(CadenceUITestLaunchPage.requested(in: environment) != nil)
            #expect(CadenceEventKitLaunchGate.isDisarmed(in: environment))
        }
    }

    @Test func theRunningProcessIsItselfOutsideTheGate() {
        #expect(ProcessInfo.processInfo.environment[Self.mode] != "1", "non-vacuity: this host must not be in UI-test mode")
        #expect(CadenceUITestLaunchPage.requested() == nil)
    }

    #if os(macOS)
    @MainActor @Test func theMacRootMapsEachPageToItsSidebarItem() {
        func selection(_ raw: String?) -> SidebarItem {
            var environment = [Self.mode: "1"]
            environment[Self.page] = raw
            return SidebarItem.launchSelection(in: environment)
        }
        #expect(selection(nil) == .today)
        #expect(selection("today") == .today)
        #expect(selection("all-tasks") == .allTasks)
        #expect(selection("inbox") == .inbox)
        #expect(selection("notes") == .notes)
        #expect(selection("calendar") == .calendar)
        #expect(selection("focus") == .focus)
        #expect(selection("settings") == .settings)
        #expect(SidebarItem.launchSelection(in: [Self.page: "calendar"]) == .today)
        #expect(SidebarItem.launchSelection() == .today)
    }

    /// The root's initial selection goes through the selector, and nowhere else spells a
    /// hard-coded initial page that would shadow it.
    @Test func theMacRootSeedsItsSelectionFromTheSelector() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/macOSRootView.swift"))
        #expect(source.contains("@State private var selection: SidebarItem? = SidebarItem.launchSelection()"))
        #expect(CadenceSourceScan.matchCount(#"@State private var selection: SidebarItem\? = \.today"#, in: source) == 0)
    }
    #endif

    /// The launcher reads this enum's raw values out of the source with one regex; a case written
    /// another way would silently drop out of its vocabulary.
    @Test func everyCaseIsSpelledTheWayTheLauncherReadsIt() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Services/CadenceUITestLaunchPage.swift")
        #expect(CadenceSourceScan.matchCount(#"case [A-Za-z]+ = "[a-z0-9-]+""#, in: source) == CadenceUITestLaunchPage.allCases.count)
        let launcher = try CadenceSourceScan.sourceFile("scripts/run-macos-app.sh")
        #expect(launcher.contains("Cadence/Services/CadenceUITestLaunchPage.swift"))
        #expect(launcher.contains("CADENCE_UI_TEST_PAGE=$PAGE"))
    }
}
