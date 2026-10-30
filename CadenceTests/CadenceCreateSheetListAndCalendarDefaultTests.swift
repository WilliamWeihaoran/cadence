import Foundation
import SwiftData
import Testing
@testable import Cadence

/// Two visible defects in the New Task / New Event card, found by a read-from-source sweep of the
/// iOS create sheet (agent `iosinbox0038`).
///
/// - [[T-8551]]: a blank-named list drew a blank row in the card's List picker and an empty List
///   chip, because both shared list-row builders passed the raw `name`. The iOS `~` suggestions
///   tested `name.isEmpty` (so a name of spaces drew an empty chip) and matched the query against
///   the raw name rather than the one drawn.
/// - [[T-8552]]: a new event with no calendar picked went to the system default calendar on the
///   Mac and to the alphabetically first writable calendar on iOS.
@MainActor
struct CadenceCreateSheetListAndCalendarDefaultTests {

    // MARK: - T-8551

    private func makeDraft() -> CadenceScheduleDraft {
        CadenceScheduleDraft.quickCreate(dateKey: DateFormatters.todayKey(), startMin: 9 * 60, opensTimed: false, kind: .task)
    }

    @Test func theCreatingListRowsNameABlankListUntitled() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let blankArea = Area(name: "   ")
        let namedArea = Area(name: "Operations")
        namedArea.order = 1
        let blankProject = Project(name: "")
        for model in [blankArea, namedArea] { context.insert(model) }
        context.insert(blankProject)
        try context.save()

        let names = CadenceScheduleDraftChoices.listChoices(
            for: makeDraft(),
            areas: [blankArea, namedArea],
            projects: [blankProject]
        ).map(\.name)

        // Non-vacuity: the three lists and the Inbox are all rows.
        #expect(names.count == 4)
        #expect(names.contains("Operations"))
        #expect(names.filter { CadenceTitleNormalization.isBlank($0) }.isEmpty, "a list row draws no name: \(names)")
        #expect(names.contains(CadenceTitleNormalization.defaultAreaName))
        #expect(names.contains(CadenceTitleNormalization.defaultProjectName))
    }

    @Test func theEditingListRowsNameABlankListUntitled() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let blankArea = Area(name: "\n")
        let blankProject = Project(name: "  ")
        context.insert(blankArea)
        context.insert(blankProject)
        try context.save()

        let names = CadenceSchedulePanelChoice.editableTaskListChoices(
            areas: [blankArea],
            projects: [blankProject],
            selection: .inbox
        ).map(\.name)

        #expect(names.count == 3)
        #expect(names.filter { CadenceTitleNormalization.isBlank($0) }.isEmpty, "a list row draws no name: \(names)")
        #expect(names.contains(CadenceTitleNormalization.defaultAreaName))
        #expect(names.contains(CadenceTitleNormalization.defaultProjectName))
    }

    private static let markerSuggestionsPath = "Cadence/iOS/iOSCreateTaskSheetSupportViews.swift"

    private func code(_ path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 500, "\(path) read back too small to be the real file")
        return CadenceSourceScan.strippingComments(raw)
    }

    /// The macOS test target does not compile `#if os(iOS)` views, so the `~` strip's call sites
    /// are pinned by source: it titles and matches through the picker's fallback.
    @Test func theIOSTildeSuggestionsTitleAndMatchThroughThePickerFallback() throws {
        let source = try code(Self.markerSuggestionsPath)
        #expect(CadenceSourceScan.matchCount(#"struct iOSTaskComposerMarkerSuggestions"#, in: source) == 1)
        #expect(
            CadenceSourceScan.matchCount(#"matchesQuery\(CadenceAreaPickerSupport\.title\(for: \$0\)"#, in: source) == 1,
            "the area suggestions match the raw name, not the one drawn"
        )
        #expect(
            CadenceSourceScan.matchCount(#"matchesQuery\(CadenceProjectPickerSupport\.title\(for: \$0\)"#, in: source) == 1,
            "the project suggestions match the raw name, not the one drawn"
        )
        #expect(CadenceSourceScan.matchCount(#"title: CadenceAreaPickerSupport\.title\(for: area\)"#, in: source) == 1)
        #expect(CadenceSourceScan.matchCount(#"title: CadenceProjectPickerSupport\.title\(for: project\)"#, in: source) == 1)
        #expect(
            CadenceSourceScan.matchCount(#"\.name\.isEmpty \? CadenceTitleNormalization"#, in: source) == 0,
            "a hand-rolled isEmpty fallback lets a name of spaces through"
        )
    }

    // MARK: - T-8552

    @Test func aNewEventPrefersTheSystemDefaultCalendarWhenItIsWritable() {
        let writable = ["a-family", "b-home", "c-work"]
        #expect(CadenceCalendarSorting.defaultWritableID(writableIDs: writable, systemDefaultID: "c-work") == "c-work")
        // A default Cadence may not write to (read-only, or hidden in Settings) is not offered.
        #expect(CadenceCalendarSorting.defaultWritableID(writableIDs: writable, systemDefaultID: "z-subscribed") == "a-family")
        #expect(CadenceCalendarSorting.defaultWritableID(writableIDs: writable, systemDefaultID: nil) == "a-family")
        #expect(CadenceCalendarSorting.defaultWritableID(writableIDs: [], systemDefaultID: "c-work") == nil)
    }

    private static let iOSManagerPath = "Cadence/iOS/iOSCalendarManager.swift"
    private static let macManagerPath = "Cadence/macOS/Services/CalendarManager.swift"
    private static let iOSDraftCreationPath = "Cadence/iOS/iOSTimelineDraftCreate.swift"
    private static let iOSCreateSheetPath = "Cadence/iOS/iOSCreateTaskSheet.swift"

    @Test func bothCalendarManagersResolveTheDefaultThroughTheSharedRule() throws {
        for path in [Self.iOSManagerPath, Self.macManagerPath] {
            let source = try code(path)
            #expect(CadenceSourceScan.matchCount(#"var defaultWritableCalendar: EKCalendar\?"#, in: source) == 1, "\(path)")
            #expect(
                CadenceSourceScan.matchCount(#"CadenceCalendarSorting\.defaultWritableID\("#, in: source) == 1,
                "\(path) does not resolve the default through the shared rule"
            )
            #expect(
                CadenceSourceScan.matchCount(#"systemDefaultID: store\.defaultCalendarForNewEvents\?\.calendarIdentifier"#, in: source) == 1,
                "\(path) does not hand the shared rule EventKit's default calendar"
            )
        }
        // iOS's own write falls back to the default, not to the first calendar in the list.
        let iOS = try code(Self.iOSManagerPath)
        #expect(CadenceSourceScan.matchCount(#"\?\? defaultWritableCalendar else"#, in: iOS) == 1)
        #expect(CadenceSourceScan.matchCount(#"\?\? writableCalendars\.first"#, in: iOS) == 0)
    }

    @Test func everyIOSCreatingHostPicksTheDefaultCalendar() throws {
        let creation = try code(Self.iOSDraftCreationPath)
        #expect(CadenceSourceScan.matchCount(#"static func resolveCalendarSelection\("#, in: creation) == 1)
        #expect(
            CadenceSourceScan.matchCount(#"draft\.calendarID = calendarManager\.defaultWritableCalendar\?\.calendarIdentifier"#, in: creation) == 1,
            "the shared iOS resolution does not pick the default calendar"
        )
        for path in [Self.iOSDraftCreationPath, Self.iOSCreateSheetPath] {
            #expect(
                CadenceSourceScan.matchCount(#"writableCalendars\.first\?\.calendarIdentifier"#, in: try code(path)) == 0,
                "\(path) still picks the alphabetically first calendar"
            )
        }
        #expect(
            CadenceSourceScan.matchCount(#"iOSScheduleDraftCreation\.resolveCalendarSelection\(&draft"#, in: try code(Self.iOSCreateSheetPath)) == 1,
            "the + sheet keeps its own copy of the calendar resolution"
        )
    }
}
