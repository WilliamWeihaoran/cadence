import Foundation
import Testing
@testable import Cadence

/// [[T-15433]]: a list's Notes tab heads its Notes, Events and Task Notes sections with one shared
/// heading -- title, count and fold -- on both platforms. The Mac had a count and a fold; iOS had
/// neither, and no list-notes heading at all.
@MainActor
struct CadenceListNotesSectionHeadingTests {
    @Test func theSectionsAreTheMacsThreeInColumnOrder() {
        #expect(CadenceListNotesSection.allCases.map(\.title) == [
            "Notes", CadenceNotesTabVocabulary.events.columnTitle, "Task Notes",
        ])
    }

    @Test func aHeadingCarriesItsCountAndExistsOnlyOverRows() throws {
        #expect(CadenceListNotesSectionHeading.heading(.notes, count: 0) == nil)
        let heading = try #require(CadenceListNotesSectionHeading.heading(.taskNotes, count: 3))
        #expect(heading.title == "Task Notes")
        #expect(heading.countText == "3")
        #expect(heading.accessibilityValue(isCollapsed: true) == "Collapsed, 3 tasks")
        #expect(heading.accessibilityValue(isCollapsed: false) == "Expanded, 3 tasks")
        let one = try #require(CadenceListNotesSectionHeading.heading(.events, count: 1))
        #expect(one.accessibilityValue(isCollapsed: false) == "Expanded, 1 note")
    }

    /// Both tabs draw every section through the shared heading, built from the count of the same
    /// filtered array the section's rows read, and neither keeps a hand-rolled heading beside it.
    @Test func bothTabsDrawEverySectionThroughTheSharedHeading() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let mac = try read("Cadence/macOS/Views/ListNotesView.swift")
        let iOS = try read("Cadence/iOS/iOSListNotesView.swift")
        let cases: [(String, String, String)] = [
            ("listNoteSection", ".notes", "filteredListNotes"),
            ("eventNoteSection", ".events", "filteredEventNotes"),
            ("taskNoteSection", ".taskNotes", "filteredTaskNotes"),
        ]
        for (path, source) in [("macOS", mac), ("iOS", iOS)] {
            for (name, section, rows) in cases {
                let body = try #require(
                    CadenceSourceScan.declarationBody("private var \(name): some View", in: source),
                    "\(path) \(name) has moved -- this pin is unanchored"
                )
                #expect(
                    body.contains("CadenceListNotesSectionHeading.heading(\(section), count: \(rows).count)"),
                    "\(path) \(name) does not head itself from its rows' own array"
                )
                #expect(body.contains("CollapsibleNoteSection(heading: heading"), "\(path) \(name) draws no fold")
            }
        }
        #expect(!iOS.contains("relatedSectionHeader"), "iOS keeps a second, count-less heading")
        // The iOS list notes sit under the heading, not loose in the column.
        let column = try #require(CadenceSourceScan.declarationBody("private var notesColumnContent: some View", in: iOS))
        #expect(column.contains("listNoteSection"))
        #expect(!column.contains("NoteFolderGroupList("))
        // The iOS section reads the tier's metrics, so its heading takes the touch floor.
        #expect(iOS.contains("CollapsibleNoteSection(heading: heading, metrics: metrics,"))
    }
}
