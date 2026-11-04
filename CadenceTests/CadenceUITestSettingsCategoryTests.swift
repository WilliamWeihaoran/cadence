import Foundation
import Testing

@testable import Cadence

/// **[[T-11451]] — the launch SETTINGS-CATEGORY selector, pinned from both sides.**
///
/// `CADENCE_UI_TEST_SETTINGS_CATEGORY` lets a seeded agent launch open the macOS settings pane on a
/// named category, so a window capture can reach a pane that otherwise needed a click — and macOS
/// UI automation is not approved here. The hazard is the inverse, and it is the same one
/// [[T-3200]] guarded: a shipping launch steered off `.navigation` by a stray variable. So the gate
/// is what is under test, with literal environment dictionaries, plus one scan that the pane's
/// initial selection is actually routed through it.
@Suite("UI-test launch settings category (T-11451)")
struct CadenceUITestSettingsCategoryTests {

    private static let mode = CadenceEventKitLaunchGate.uiTestModeVariable
    private static let category = CadenceUITestSettingsCategory.categoryVariable

    @Test func theCategoryVariableIsSpelledOnce() {
        #expect(Self.category == "CADENCE_UI_TEST_SETTINGS_CATEGORY")
    }

    @Test func nothingAskedMeansTheNavigationDefault() {
        #expect(CadenceUITestSettingsCategory.requested(in: [:]) == nil)
        #expect(CadenceUITestSettingsCategory.requested(in: [Self.mode: "1"]) == nil)
        #expect(CadenceUITestSettingsCategory.requested(in: [Self.mode: "1", Self.category: ""]) == nil)
    }

    /// The shipping-launch claim: the category variable alone, or with the mode set to anything
    /// but `1`, is ignored.
    @Test func theCategoryWithoutUITestModeIsIgnored() {
        #expect(CadenceUITestSettingsCategory.requested(in: [Self.category: "sidebar"]) == nil)
        #expect(CadenceUITestSettingsCategory.requested(in: [Self.mode: "0", Self.category: "sidebar"]) == nil)
        #expect(CadenceUITestSettingsCategory.requested(in: [Self.mode: "true", Self.category: "sidebar"]) == nil)
    }

    @Test func anUnknownCategoryIsIgnored() {
        #expect(CadenceUITestSettingsCategory.requested(in: [Self.mode: "1", Self.category: "Sidebar"]) == nil)
        #expect(CadenceUITestSettingsCategory.requested(in: [Self.mode: "1", Self.category: "data-safety"]) == nil)
        #expect(CadenceUITestSettingsCategory.requested(in: [Self.mode: "1", Self.category: "bogus"]) == nil)
    }

    @Test func everyCategoryIsReachableByItsRawValue() {
        #expect(CadenceSettingsCategoryKind.allCases.count == 15)
        for kind in CadenceSettingsCategoryKind.allCases {
            let environment = [Self.mode: "1", Self.category: kind.rawValue]
            #expect(CadenceUITestSettingsCategory.requested(in: environment) == kind)
        }
    }

    /// A launch that can be steered here is a launch EventKit is disarmed for.
    @Test func aSteerableCategoryLaunchIsAnEventKitDisarmedLaunch() {
        for kind in CadenceSettingsCategoryKind.allCases {
            let environment = [Self.mode: "1", Self.category: kind.rawValue]
            #expect(CadenceUITestSettingsCategory.requested(in: environment) != nil)
            #expect(CadenceEventKitLaunchGate.isDisarmed(in: environment))
        }
    }

    @Test func theRunningProcessAsksForNoSettingsCategory() {
        #expect(ProcessInfo.processInfo.environment[Self.mode] != "1", "non-vacuity: this host must not be in UI-test mode")
        #expect(CadenceUITestSettingsCategory.requested() == nil)
    }

    #if os(macOS)
    /// The rail's own case, not a near miss: every shared kind maps back, and an ungated launch
    /// maps to nothing at all.
    @Test func theMacRailResolvesEveryKindAndNothingUngated() {
        for kind in CadenceSettingsCategoryKind.allCases {
            let resolved = SettingsCategory.launchRequested(in: [Self.mode: "1", Self.category: kind.rawValue])
            #expect(resolved?.sharedKind == kind)
        }
        #expect(SettingsCategory.launchRequested(in: [Self.category: "sidebar"]) == nil)
        #expect(SettingsCategory.launchRequested(in: [:]) == nil)
        #expect(SettingsCategory.launchRequested() == nil)
    }

    /// The pane's initial selection goes through the selector, and the bare `.navigation` literal
    /// that would shadow it is gone.
    @Test func theSettingsPaneSeedsItsSelectionFromTheSelector() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsView.swift"))
        #expect(source.contains("@State private var selectedCategory: SettingsCategory = SettingsCategory.launchRequested() ?? .navigation"))
        #expect(CadenceSourceScan.matchCount(#"@State private var selectedCategory: SettingsCategory = \.navigation"#, in: source) == 0)
    }
    #endif

    /// The launcher reads the vocabulary out of the SHARED category table with one regex, and
    /// `CadenceSettingsCategoryKind` takes its raw values implicitly — so a case written with an
    /// explicit raw value, or at another indent, would silently drop out of the launcher's list
    /// while still existing in the app.
    @Test func everyCategoryCaseIsSpelledTheWayTheLauncherReadsIt() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceSettingsPresentationSupport.swift")
        let body = source.components(separatedBy: "enum CadenceSettingsCategoryKind")
        let declaration = try #require(body.count > 1 ? body[1] : nil)
        let upToClose = declaration.components(separatedBy: "\n}\n").first ?? declaration
        #expect(CadenceSourceScan.matchCount(#"(?m)^    case [a-zA-Z]+$"#, in: upToClose) == CadenceSettingsCategoryKind.allCases.count)

        let launcher = try CadenceSourceScan.sourceFile("scripts/run-macos-app.sh")
        #expect(launcher.contains("Cadence/Shared/CadenceSettingsPresentationSupport.swift"))
        #expect(launcher.contains("CADENCE_UI_TEST_SETTINGS_CATEGORY=$CATEGORY"))
        #expect(launcher.contains("enum CadenceSettingsCategoryKind"))
        #expect(launcher.contains("refuse_bad_category"))
    }

    /// **`up` hands the category to `start`, and this is pinned because it was the live bug.**
    ///
    /// `up` does not launch anything itself: it builds and then re-invokes this same script as
    /// `start`. The first cut of [[T-11451]] set the category in `start`'s parser and in the env
    /// assembly, both correct, and forgot this one line — so `up ... settings sidebar` built,
    /// launched, printed a page of success and opened on Navigation, which looks exactly like the
    /// selector not working. The argument before it was an UNQUOTED `$PAGE`, which collapses to no
    /// word when empty, so a category would also have slid into the page's position.
    @Test func theUpCommandForwardsThePageAndCategoryToStart() throws {
        let launcher = try CadenceSourceScan.sourceFile("scripts/run-macos-app.sh")
        #expect(launcher.contains(#"zsh "$SELF" start "$APP" "$ID" "${SCENARIO:-none}" "$PAGE" "$CATEGORY""#))
        #expect(CadenceSourceScan.matchCount(#"\$SELF" start .* \$PAGE( |$)"#, in: launcher) == 0)
    }
}
