import Foundation
import Testing
@testable import Cadence

/// **T-17036: the Mac list page header drew a blank-named area or project as an empty title.**
///
/// The iPhone/iPad header, both sidebars and the header's own edit label already said "Untitled";
/// the Mac's `DesktopPageHeader` was handed the raw name. Both headers read one helper now.
struct CadenceListHeaderBlankTitleTests {

    /// **Behavioural.**
    @Test func aBlankListNameTitlesItsHeaderUntitled() {
        #expect(ListDetailHeaderAccessibility.displayTitle(listName: "") == "Untitled")
        #expect(ListDetailHeaderAccessibility.displayTitle(listName: " \n ") == "Untitled")
        #expect(ListDetailHeaderAccessibility.displayTitle(listName: "  Roadmap ") == "Roadmap")
        #expect(ListDetailHeaderAccessibility.editLabel(listName: "") == "Edit Untitled")
    }

    /// **Source scan**: both headers title themselves through the helper, not the raw name.
    @Test func bothListHeadersTitleThemselvesThroughTheHelper() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let mac = try read("Cadence/macOS/Views/ListDetailView.swift")
        let iOS = try read("Cadence/iOS/iOSListDetailView.swift")
        #expect(mac.contains("title: ListDetailHeaderAccessibility.displayTitle(listName: name)"))
        #expect(!mac.contains("DesktopPageHeader(\n            title: name,"))
        #expect(iOS.contains("title: ListDetailHeaderAccessibility.displayTitle(listName: title)"))
    }
}
