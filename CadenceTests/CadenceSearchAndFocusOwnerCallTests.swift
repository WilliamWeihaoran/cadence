import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-11195]]**, decided under [[T-8201]]: three Search row/field differences no hardware or
/// input forced. The iOS half lives inside `#if os(iOS)` and this target builds for macOS, so the
/// iOS rows are pinned by source, scoped to the bodies that draw them; the shared halves by value.
@MainActor
struct CadenceSearchOwnerCallParityTests {
    private static let iOSSearchPath = "Cadence/iOS/iOSSearchView.swift"
    private static let macIndexPath = "Cadence/macOS/Views/GlobalSearchIndexSupport.swift"
    private static let macViewsPath = "Cadence/macOS/Views/GlobalSearchSupportViews.swift"

    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: (a) task glyph

    // `GlobalSearchIndexSupport` is a macOS type (`#if os(macOS)` file), and this bundle also
    // compiles for iOS in CI's build-for-testing leg ([[T-12200]]).
    #if os(macOS)
    /// An open task and a finished one draw different glyphs in Cmd+K, the pair iOS drew.
    @Test func aCmdKTaskRowDrawsTheSameGlyphPairIOSSearchDraws() {
        #expect(CadenceTaskSearchGlyph.active.systemImage == "circle")
        #expect(CadenceTaskSearchGlyph.completed.systemImage == "checkmark.circle.fill")
        #expect(CadenceTaskSearchGlyph.scheduled.systemImage == "calendar.badge.clock")

        let open = AppTask(title: "Draft roadmap")
        let done = AppTask(title: "Ship roadmap")
        done.status = .done
        let rows = Dictionary(uniqueKeysWithValues: GlobalSearchIndexSupport.taskResults(
            tasks: [open, done], query: "roadmap", includingCompleted: true
        ).map { ($0.title, $0.icon) })

        #expect(rows["Draft roadmap"] == "circle")
        #expect(rows["Ship roadmap"] == "checkmark.circle.fill")
        #expect(rows["Draft roadmap"] != rows["Ship roadmap"], "an open and a finished task read alike again")
    }
    #endif

    @Test func neitherSurfaceSpellsItsOwnTaskGlyphs() throws {
        for path in [Self.iOSSearchPath, Self.macIndexPath] {
            let code = try Self.code(path)
            #expect(code.contains("CadenceTaskSearchSupport.glyph(for: task).systemImage"), "\(path) moved its task row")
            #expect(!code.contains("func taskIcon("), "\(path) spells its own task glyphs again")
            #expect(!code.contains("\"checkmark.circle\""), "\(path) draws the retired open-and-done glyph")
        }
    }

    // MARK: (b) field placeholder

    @Test func bothFieldsNameWhatTheyFindAndOnlyTheMacAddsCommands() throws {
        #expect(CadenceSearchFieldPrompt.text(offersCommands: false) == "Tasks, lists, notes, events")
        #expect(CadenceSearchFieldPrompt.text(offersCommands: true) == "Tasks, lists, notes, events, or a command")

        let ios = try Self.code(Self.iOSSearchPath)
        let mac = try Self.code(Self.macViewsPath)
        #expect(CadenceSourceScan.matchCount(#"prompt:\s*CadenceSearchFieldPrompt\.text\(offersCommands:\s*false\)"#, in: ios) == 1)
        #expect(CadenceSourceScan.matchCount(#"TextField\(CadenceSearchFieldPrompt\.text\(offersCommands:\s*true\),"#, in: mac) == 1)
    }

    // MARK: (c) event-note subtitle

    private static func localDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func anEventNoteNamesItsDayThenItsTimeAndNoKindWord() {
        let reference = Self.localDay(2027, 10, 25)
        let timed = Note(kind: .meeting, title: "Sync", eventDateKey: "2027-11-04", eventStartMin: 600, eventEndMin: 660)
        let allDay = Note(kind: .meeting, title: "Offsite", eventDateKey: "2027-11-04")
        let undated = Note(kind: .meeting, title: "Loose")

        let timedFacts = CadenceSearchEventNoteSupport.subtitleFacts(for: timed, relativeTo: reference)
        #expect(timedFacts == [
            DateFormatters.absoluteDay(Self.localDay(2027, 11, 4), relativeTo: reference),
            TimeFormatters.timeRange(startMin: 600, endMin: 660)
        ])
        #expect(CadenceSearchEventNoteSupport.subtitleFacts(for: allDay, relativeTo: reference).count == 1)
        #expect(CadenceSearchEventNoteSupport.subtitleFacts(for: undated) == ["Event note"])
        #expect(!timedFacts.contains { $0.hasPrefix("Event") }, "the row says its section's name again")
    }

    #if os(macOS)
    /// Cmd+K joins exactly the shared facts; iOS joins the same call in its own separator.
    @Test func bothEventNoteRowsReadTheSharedFacts() throws {
        let reference = Self.localDay(2027, 10, 25)
        let note = Note(kind: .meeting, title: "Sync", eventDateKey: "2027-11-04", eventStartMin: 600, eventEndMin: 660)
        let row = try #require(GlobalSearchIndexSupport.eventNoteResults(
            notes: [note], query: "Sync", taskTitles: [:], relativeTo: reference
        ).first)
        #expect(row.subtitle == CadenceSearchEventNoteSupport.subtitleFacts(for: note, relativeTo: reference).joined(separator: " • "))

        let ios = try Self.code(Self.iOSSearchPath)
        let subtitle = try #require(CadenceSourceScan.functionBody(named: "noteSubtitle", in: ios))
        #expect(subtitle.contains("note.kind == .meeting"))
        #expect(subtitle.contains(#"CadenceSearchEventNoteSupport.subtitleFacts(for: note).joined(separator: " · ")"#))
        // Every other kind keeps the shared detail.
        #expect(subtitle.contains("NoteReferencePanelSupport.noteKindDetail(note)"))
    }
    #endif
}

/// **[[T-11210]]**, decided under [[T-8201]]: three Focus picker differences no hardware forced.
@MainActor
struct CadenceFocusPickOwnerCallParityTests {
    private static let macPicker = "Cadence/macOS/Views/FocusPickerSupportViews.swift"
    private static let macSidebar = "Cadence/macOS/Views/FocusSidebarSupportViews.swift"
    private static let macPage = "Cadence/macOS/Views/FocusView.swift"
    private static let ios = "Cadence/iOS/iOSFocusView.swift"

    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: (a) play plate tint

    /// Both Mac rows tint their play plate in the task's list colour, as iOS's row does.
    @Test func everyPickRowPlayPlateReadsTheTasksListColour() throws {
        let picker = try #require(CadenceSourceScan.declarationBody(
            "private struct FocusPickItemRow: View", in: try Self.code(Self.macPicker)
        ))
        let tint = try #require(CadenceSourceScan.declarationBody("private var tint: Color", in: picker))
        #expect(tint.contains("return Color(hex: task.containerColor)"))
        #expect(!tint.contains("Theme.blue"), "the Mac pick row's play plate is blue again")
        #expect(picker.contains(".foregroundStyle(tint)"), "non-vacuity: the play glyph no longer reads `tint`")

        let sidebar = try #require(CadenceSourceScan.declarationBody(
            "struct FocusSidebarTaskRow: View", in: try Self.code(Self.macSidebar)
        ))
        let play = try #require(sidebar.range(of: "Image(systemName: \"play.fill\")"), "non-vacuity: the Next up play glyph moved")
        let plate = String(sidebar[play.lowerBound...].prefix(400))
        #expect(plate.contains(".foregroundStyle(Color(hex: task.containerColor))"))
        #expect(plate.contains(".background(Color(hex: task.containerColor).opacity("))
        #expect(!plate.contains("Theme.blue"), "the Next up row's play plate is blue again")

        let ios = try Self.code(Self.ios)
        let iosTint = try #require(CadenceSourceScan.functionBody(named: "tint", in: ios))
        #expect(iosTint.contains("Color(hex: task.containerColor)"))
    }

    // MARK: (b) pick card subtitle

    @Test func theMacPickCardDrawsNoSubtitle() throws {
        let card = try #require(CadenceSourceScan.declarationBody(
            "struct FocusPickSessionCard: View", in: try Self.code(Self.macPicker)
        ))
        #expect(card.contains("Text(title)"), "non-vacuity: the card's title moved")
        #expect(!card.contains("subtitle"), "the pick card describes the page again")
        let page = try Self.code(Self.macPage)
        #expect(page.contains("FocusPickSessionCard("), "non-vacuity: the idle page no longer builds the card")
        #expect(!page.contains("start the cleanest next session"))
    }

    // MARK: (c) how the list is counted

    @Test func iOSCountsThePickListWithTheSharedSummaryLineAndNoBadge() throws {
        let ios = try Self.code(Self.ios)
        #expect(CadenceSourceScan.matchCount(
            #"iOSPanelHeader\(eyebrow:\s*CadenceFocusSupport\.pickListEyebrow,\s*title:\s*CadenceFocusSupport\.pickListTitle\)"#,
            in: ios
        ) == 1, "the iOS pick list header draws a count badge again")
        #expect(CadenceSourceScan.matchCount(#"count:\s*listedPickItems"#, in: ios) == 0)

        let summary = try #require(CadenceSourceScan.declarationBody("private var pickListSummary: some View", in: ios))
        #expect(CadenceSourceScan.matchCount(
            #"CadenceFocusPickItem\.summary\(\s*shownCount:\s*listedPickItems\.count,\s*readyCount:\s*pickItems\.count,\s*query:\s*pickSearchText"#,
            in: summary
        ) == 1)
        // Drawn beside the search field, so only when there is a list to search.
        #expect(CadenceSourceScan.matchCount(#"pickSearchField\s*pickListSummary"#, in: ios) == 1)

        // The Mac card reads the same function.
        #expect(try Self.code(Self.macPicker).contains("FocusPickItem.summary(shownCount: items.count, readyCount: readyCount, query: searchText)"))
        // An uncapped list never says "Top".
        #expect(CadenceFocusPickItem.summary(shownCount: 40, readyCount: 40, query: "") == "40 ready tasks")
    }
}
