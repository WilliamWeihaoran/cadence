import Foundation
import Testing

@testable import Cadence

/// **One search section vocabulary on both platforms** ([[T-8765]], owner decision 2026-10-31
/// under [[T-8201]]).
///
/// The defect was two hand-written lists. The Mac palette declared eight cases in
/// `GlobalSearchCategory`; iOS Search passed five string literals of its own — "Pages", "Tasks",
/// "Lists", "Notes", "Calendar Events" — into its section builder, in an order of its own. So one
/// query read **Lists** on the phone and **Areas** / **Projects** on the Mac, and an event note
/// sat under **Notes** on the phone and **Event Notes** on the Mac.
///
/// The scope chips above the phone's sections are deliberately NOT unified: the owner kept them
/// iOS-only, justified by narrow screens, so what is pinned here is the vocabulary and the order,
/// and separately that each chip maps onto the shared cases rather than a sixth list of names.
///
/// `iOSSearchView` and `iOSSearchSupportViews` are behind `#if os(iOS)`, so their half is a source
/// reading — the shape `CadenceIOSSearchNoResultsGateTests` already uses on the same file.
struct CadenceSearchSectionParityTests {

    private func iOSSearchViewCode() throws -> String {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw, "non-vacuity: comments were not stripped")
        #expect(code.count == raw.count, "the stripper blanks rather than removes")
        return code
    }

    private func iOSSearchSupportCode() throws -> String {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchSupportViews.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw, "non-vacuity: comments were not stripped")
        return code
    }

    // MARK: - The vocabulary itself

    /// The headings a reader sees, in the order they are drawn. Asserted as the whole list rather
    /// than case by case: what regressed before was a *list* that drifted, and a per-case check
    /// cannot see a case added to one platform alone.
    @Test func theSharedSectionVocabularyIsTheMacsEightHeadingsInTheMacsOrder() {
        #expect(CadenceSearchSection.allCases.map(\.title) == [
            "Commands",
            "Pages",
            "Areas",
            "Projects",
            "Tasks",
            "Calendar Events",
            "Event Notes",
            "Notes"
        ])
        // The heading and the identity are one string, so a section's title cannot drift from the
        // id the palette's expanded-section state is keyed on.
        for section in CadenceSearchSection.allCases {
            #expect(section.title == section.rawValue)
            #expect(section.id == section.rawValue)
        }
    }

    /// `touchSections` is the single place "iOS does not draw Commands" is written down, and it is
    /// a filter of `allCases`, not a second list — so a case added to the vocabulary reaches the
    /// phone unless someone deliberately holds it back here.
    @Test func everySectionButCommandsIsDrawnOnTouch() {
        #expect(CadenceSearchSection.touchSections == [
            .pages, .areas, .projects, .tasks, .events, .meetingNotes, .notes
        ])
        #expect(!CadenceSearchSection.touchSections.contains(.commands))
        #expect(CadenceSearchSection.touchSections.count == CadenceSearchSection.allCases.count - 1)
        // Order-preserving: `touchSections` is `allCases` minus one, not a re-spelling of it.
        #expect(
            CadenceSearchSection.touchSections
                == CadenceSearchSection.allCases.filter { $0 != .commands }
        )
    }

    // MARK: - iOS draws the shared sections, in the shared order

    /// The phone iterates the vocabulary instead of spelling five `if shows…` gates over five
    /// literals. Both halves are asserted: the loop exists, and the headings come off the section.
    @Test func theIOSSearchListIteratesTheSharedSectionsAndTakesTheirTitles() throws {
        let code = try iOSSearchViewCode()

        #expect(code.contains("ForEach(visibleSections) { section in"))
        #expect(code.contains("resultSection(section.title, results: results(for: section))"))
        #expect(code.contains("private var visibleSections: [CadenceSearchSection] {"))

        // The five literals are gone as section headings. `resultSection` takes a `String`, so a
        // literal here is exactly how the two vocabularies would drift apart again.
        for literal in [
            #"resultSection("Pages""#,
            #"resultSection("Tasks""#,
            #"resultSection("Lists""#,
            #"resultSection("Notes""#,
            #"resultSection("Calendar Events""#
        ] {
            let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
            #expect(!raw.contains(literal), "\(literal) is a hand-spelled section heading")
        }
    }

    /// Every shared case is answered, including the one the phone does not draw: `.commands`
    /// returns no rows rather than being left out, so `touchSections` stays the only statement of
    /// which sections a touch surface shows.
    @Test func theIOSSectionLookupAnswersEverySharedCase() throws {
        let code = try iOSSearchViewCode()
        let body = try #require(
            CadenceSourceScan.declarationBody(
                "private func results(for section: CadenceSearchSection) -> [iOSSearchResult]",
                in: code
            ),
            "could not read iOSSearchView.results(for:)"
        )

        for section in CadenceSearchSection.allCases {
            #expect(body.contains("case .\(section.caseName):"), "\(section.caseName)")
        }
        #expect(body.contains("case .commands: return []"))
        #expect(body.contains("case .meetingNotes: return eventNoteResults"))
        #expect(body.contains("case .notes: return noteResults"))
        #expect(body.contains("case .areas: return listResults[.areas]"))
        #expect(body.contains("case .projects: return listResults[.projects]"))
    }

    /// The chips stay iOS-only, so what has to be pinned is that each one names shared *sections*
    /// rather than a sixth vocabulary — and that the two merging chips keep covering both halves
    /// of what they used to merge into one heading.
    @Test func eachIOSScopeChipNarrowsToSharedSections() throws {
        let code = try iOSSearchSupportCode()
        let body = try #require(
            CadenceSourceScan.declarationBody("var sections: [CadenceSearchSection]", in: code),
            "could not read iOSSearchScope.sections"
        )

        #expect(body.contains("case .all: return CadenceSearchSection.touchSections"))
        #expect(body.contains("case .tasks: return [.tasks]"))
        // The two that used to be one heading apiece on the phone.
        #expect(body.contains("case .lists: return [.areas, .projects]"))
        #expect(body.contains("case .notes: return [.meetingNotes, .notes]"))
        #expect(body.contains("case .events: return [.events]"))
        #expect(body.contains("case .progress: return [.pages]"))

        // The chips are not a second copy of the vocabulary: `.all` defers to `touchSections`.
        #expect(!body.contains(".commands"))
    }

    /// [[T-6984]]: the chip that narrows to the one section headed "Pages" is titled by that
    /// section, so the chip, the heading it opens and the Mac's category say one word. It read
    /// "More" until 2026-11-02. The other five chip titles are pinned beside it so a rename of
    /// any chip is a decision this suite sees.
    @Test func thePagesChipIsTitledByTheSectionItOpens() throws {
        // Comments stripped but string literals kept: `codeOnly` blanks literals, and the titles
        // are literals.
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchSupportViews.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("var title: String", in: code),
            "could not read iOSSearchScope.title"
        )

        #expect(body.contains("case .progress: return CadenceSearchSection.pages.title"))
        #expect(CadenceSearchSection.pages.title == "Pages")
        #expect(!body.contains("\"More\""))

        #expect(body.contains("case .all: return \"All\""))
        #expect(body.contains("case .tasks: return \"Tasks\""))
        #expect(body.contains("case .lists: return \"Lists\""))
        #expect(body.contains("case .notes: return \"Notes\""))
        #expect(body.contains("case .events: return \"Events\""))
    }

    /// An event note is an **Event Notes** row on the phone too. The split is `kind == .meeting`,
    /// which is the Mac's own gate rather than a second rule written beside it.
    @Test func theIOSNoteSectionsSplitOnTheMacsEventNoteGate() throws {
        let code = try iOSSearchViewCode()
        #expect(code.contains("noteSectionResults(matching: { $0.kind == .meeting })"))
        #expect(code.contains("noteSectionResults(matching: { $0.kind != .meeting })"))
        // The Mac's gate, read from its own source, so the two cannot drift to different kinds.
        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/GlobalSearchIndexSupport.swift")
        )
        #expect(mac.contains("notes.filter { $0.kind == .meeting }"))
    }
}

/// The Mac half, which can be run rather than read: `GlobalSearchIndexSupport` is macOS-only and
/// is compiled into this target on the macOS host.
#if os(macOS)
@MainActor
struct CadenceMacSearchSectionOrderTests {

    /// **The palette's section order IS the shared order**, asserted against a built index rather
    /// than against the append calls: the order a reader sees is the order the sections come back
    /// in, and a reordered `appendSection` call is exactly the drift this pins.
    ///
    /// Every section has to be non-empty for the order to be observable, because `appendSection`
    /// drops an empty one — so the fixture gives each of the eight at least one row.
    @Test func theMacPaletteBuildsItsSectionsInTheSharedOrder() {
        let area = Area(name: "Roadmap area")
        let project = Project(name: "Roadmap project")
        let task = AppTask(title: "Roadmap task")
        let eventNote = Note(kind: .meeting, title: "Roadmap sync")
        let plainNote = Note(kind: .permanent, title: "Roadmap notes")
        let event = GlobalSearchResult(
            id: "event-roadmap",
            category: .events,
            title: "Roadmap review",
            subtitle: "Today",
            icon: "calendar",
            tintHex: Theme.blueHex,
            destination: .event("event-roadmap")
        )

        let sections = GlobalSearchIndexSupport.buildIndexedSource(
            query: "roadmap",
            hiddenTabs: [],
            areas: [area],
            projects: [project],
            tasks: [task],
            notes: [eventNote, plainNote],
            eventResults: [event],
            sidebarTabColorsRaw: "",
            includesCompletedTasks: false
        ).sections

        // Non-vacuity: a query that matched nothing would make the order claim empty and true.
        #expect(!sections.isEmpty)
        let built = sections.map(\.category)
        #expect(built == CadenceSearchSection.allCases.filter { built.contains($0) })
        // And the four the fixture was built to reach are among them, in the shared relative order.
        for section in [CadenceSearchSection.areas, .projects, .meetingNotes, .notes] {
            #expect(built.contains(section), "\(section.title)")
        }
    }

    /// The event note is in **Event Notes** and not in **Notes**, on the platform where that can
    /// be run. This is the membership half of the vocabulary: one note, one section.
    @Test func anEventNoteIsOnlyEverInTheEventNotesSection() throws {
        let eventNote = Note(kind: .meeting, title: "Roadmap sync")
        let sections = GlobalSearchIndexSupport.buildIndexedSource(
            query: "roadmap",
            hiddenTabs: [],
            areas: [],
            projects: [],
            tasks: [],
            notes: [eventNote],
            eventResults: [],
            sidebarTabColorsRaw: "",
            includesCompletedTasks: false
        ).sections

        let meeting = try #require(sections.first { $0.category == .meetingNotes })
        #expect(meeting.results.count == 1)
        #expect(sections.first { $0.category == .notes } == nil)
    }
}
#endif

extension CadenceSearchSection {
    /// The Swift case name, for a source scan that has to spell `case .<name>:`. Derived rather
    /// than listed, because the one case whose name is not its title is the one a second list
    /// would get wrong.
    fileprivate var caseName: String {
        switch self {
        case .commands: "commands"
        case .pages: "pages"
        case .areas: "areas"
        case .projects: "projects"
        case .tasks: "tasks"
        case .events: "events"
        case .meetingNotes: "meetingNotes"
        case .notes: "notes"
        }
    }
}
