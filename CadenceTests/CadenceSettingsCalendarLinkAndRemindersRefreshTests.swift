import Foundation
import Testing
@testable import Cadence

/// **T-6973.** Settings > Calendars printed raw `area.name` / `project.name` in the per-calendar
/// connect menu and in the row's "connected to" line, so a blank-named list drew an empty menu
/// item and an empty slot in the summary. Both now go through `CadenceCalendarSettingsCopy`'s
/// display fallbacks, the same `CadenceTitleNormalization.display` call T-577 gave
/// `ListLifecycleRow`.
@Suite
struct CadenceCalendarLinkDisplayNameTests {

    @Test func aBlankAreaOrProjectNameFallsBackToItsDefaultName() {
        #expect(CadenceCalendarSettingsCopy.areaDisplayName("   ") == CadenceTitleNormalization.defaultAreaName)
        #expect(CadenceCalendarSettingsCopy.areaDisplayName("") == CadenceTitleNormalization.defaultAreaName)
        #expect(CadenceCalendarSettingsCopy.projectDisplayName("\n\t") == CadenceTitleNormalization.defaultProjectName)
        #expect(CadenceCalendarSettingsCopy.areaDisplayName("  Home ") == "Home")
        #expect(CadenceCalendarSettingsCopy.projectDisplayName("Launch") == "Launch")
    }

    @Test func theSummaryNamesEveryLinkedListWithNoEmptySlot() {
        let summary = CadenceCalendarSettingsCopy.connectionSummary(
            areaNames: ["Work", " "],
            projectNames: ["", "Launch"]
        )
        #expect(summary == "Work, Untitled Area, Untitled Project, Launch")
        #expect(!summary.contains(",  ,"))
        #expect(!summary.contains(", ,"))
    }

    @Test func theSummaryWithNothingLinkedIsTheUnconnectedLine() {
        #expect(
            CadenceCalendarSettingsCopy.connectionSummary(areaNames: [], projectNames: [])
                == CadenceCalendarSettingsCopy.unconnectedSummary
        )
    }

    /// Both calendar rows must ask the shared helpers rather than print the raw name: a row
    /// that goes back to `Label(area.name, ...)` reopens the empty menu item.
    @Test func bothCalendarRowsPrintListNamesThroughTheDisplayFallback() throws {
        for path in Self.calendarRowFiles {
            let source = try settingsSourceWithoutComments(path)
            #expect(source.contains("Label(CadenceCalendarSettingsCopy.areaDisplayName(area.name)"), "\(path) menu prints a raw area name")
            #expect(source.contains("Label(CadenceCalendarSettingsCopy.projectDisplayName(project.name)"), "\(path) menu prints a raw project name")
            #expect(!source.contains("Label(area.name,"), "\(path) menu prints a raw area name")
            #expect(!source.contains("Label(project.name,"), "\(path) menu prints a raw project name")
            #expect(source.contains("CadenceCalendarSettingsCopy.connectionSummary("), "\(path) summary joins raw names")
            #expect(!source.contains("connectedNames.joined("), "\(path) summary joins raw names")
        }
    }

    static let calendarRowFiles = [
        "Cadence/macOS/Views/SettingsListManagementSections.swift",
        "Cadence/iOS/iOSCalendarSettingsSection.swift"
    ]
}

/// **T-6974.** Settings > Reminders "Refresh" drew the loading row only while the list was empty,
/// so a refresh over a listed store showed nothing, and the button stayed live mid-fetch. Both
/// surfaces now take the "Check iCloud Status" shape: a spinner gated on the fetch, and the
/// button disabled on it.
@Suite
struct CadenceRemindersRefreshInFlightTests {

    @Test func theMacRefreshButtonIsDisabledAndShowsASpinnerDuringAFetch() throws {
        let card = try refreshBranch(in: "Cadence/macOS/Views/SettingsRemindersSection.swift")
        #expect(card.contains(".disabled(remindersManager.isLoading)"), "the Mac Refresh stays live mid-fetch")
        #expect(card.contains("if remindersManager.isLoading {"), "the Mac Refresh draws no in-flight spinner")
        #expect(card.contains("ProgressView()"), "the Mac Refresh draws no in-flight spinner")
    }

    @Test func theIOSRefreshButtonIsDisabledAndShowsASpinnerDuringAFetch() throws {
        let card = try refreshBranch(in: "Cadence/iOS/iOSRemindersSettingsSection.swift")
        #expect(card.contains("isDisabled: remindersManager.isLoading"), "the iOS Refresh stays live mid-fetch")
        #expect(card.contains("if remindersManager.isLoading {"), "the iOS Refresh draws no in-flight spinner")
        #expect(card.contains("ProgressView()"), "the iOS Refresh draws no in-flight spinner")
    }

    /// The text from the `state.isConnected` branch to the T-256 `.restricted` note that closes
    /// it: the Refresh branch alone, so the loading row elsewhere in the file cannot satisfy
    /// the scan above.
    private func refreshBranch(in path: String) throws -> String {
        let raw = try settingsRawSource(path)
        guard let start = raw.range(of: "} else if state.isConnected {"),
              let end = raw.range(of: "T-256", range: start.upperBound..<raw.endIndex) else {
            Issue.record("\(path): the Refresh branch moved; re-pick the anchors")
            return ""
        }
        let branch = try settingsStrippingComments(String(raw[start.lowerBound..<end.lowerBound]))
        #expect(branch.contains("\"Refresh\""), "\(path): the slice is not the Refresh branch")
        #expect(branch.count < 1500, "\(path): the slice ran past the Refresh branch")
        return branch
    }
}

private func settingsRawSource(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private func settingsSourceWithoutComments(_ relativePath: String) throws -> String {
    try settingsStrippingComments(settingsRawSource(relativePath))
}

/// Drops `//` line comments so prose naming a call cannot satisfy a scan for it.
private func settingsStrippingComments(_ source: String) throws -> String {
    let regex = try NSRegularExpression(pattern: "//[^\n]*")
    let range = NSRange(source.startIndex..., in: source)
    return regex.stringByReplacingMatches(in: source, range: range, withTemplate: "")
}
