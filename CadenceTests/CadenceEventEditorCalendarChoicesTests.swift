import SwiftUI
import Testing
@testable import Cadence

/// **[[T-12753]].** A read-only event's Calendar row read "Holidays (Read-only)" in the Mac event
/// editor and bare "Holidays" in the iOS sheet: the Mac built its rows through the event's
/// `CadenceCalendarLink` ([[T-467]]), the phone returned the calendar's name for a read-only event
/// and `writableCalendars` titles otherwise. No hardware constraint separates them ([[T-8201]]).
/// Both editors now call `CadenceEventEditorCalendarChoices`.
///
/// The builder is pinned on value types (no `EKCalendar`, so no event store), and each editor is
/// read from source for its call.
@MainActor
struct CadenceEventEditorCalendarChoicesTests {

    private static let work = CadenceCalendarChoice(id: "cal-work", title: "Work")
    private static let holidays = CadenceCalendarChoice(id: "cal-holidays", title: "Holidays")

    private static func rows(selectedID: String) -> [CadenceSchedulePanelChoice] {
        let link = CadenceEventEditorCalendarChoices.link(
            selectedID: selectedID,
            availableCalendars: [work, holidays],
            writableCalendarIDs: [work.id]
        )
        return CadenceEventEditorCalendarChoices.choices(link: link, selectedID: selectedID) { _ in Theme.blue }
    }

    /// The defect itself: the read-only calendar the event is on is named with its word.
    @Test func aReadOnlyEventsRowSaysReadOnly() {
        let rows = Self.rows(selectedID: Self.holidays.id)
        #expect(rows.map(\.id) == [Self.work.id, Self.holidays.id])
        #expect(rows.first { $0.id == Self.holidays.id }?.name == "Holidays (Read-only)")
        #expect(rows.first { $0.id == Self.work.id }?.name == "Work")
    }

    /// An editable event is offered the writable calendars alone, by their plain names.
    @Test func aWritableEventIsOfferedTheWritableCalendars() {
        let rows = Self.rows(selectedID: Self.work.id)
        #expect(rows.map(\.id) == [Self.work.id])
        #expect(rows.map(\.name) == ["Work"])
    }

    /// An event whose calendar the fetch no longer lists still names what the link calls it rather
    /// than leaving the panel to say "Choose Calendar".
    @Test func anOrphanedCalendarIsNamedByTheLink() {
        let link = CadenceEventEditorCalendarChoices.link(
            selectedID: "gone",
            availableCalendars: [Self.work],
            writableCalendarIDs: [Self.work.id]
        )
        let rows = CadenceEventEditorCalendarChoices.choices(link: link, selectedID: "gone") { _ in Theme.blue }
        #expect(rows.count == 2)
        #expect(rows.last?.id == "gone")
        #expect(rows.last?.name == link.rowState.valueText)
    }

    /// A calendar with no title reads as the shared unnamed-calendar fallback, as the iOS sheet's
    /// read-only row did before it moved here ([[T-7034]]).
    @Test func anUntitledCalendarReadsTheUnnamedFallback() {
        let untitled = CadenceCalendarChoice(id: "cal-untitled", title: "  ")
        let link = CadenceEventEditorCalendarChoices.link(
            selectedID: untitled.id,
            availableCalendars: [untitled],
            writableCalendarIDs: [untitled.id]
        )
        let rows = CadenceEventEditorCalendarChoices.choices(link: link, selectedID: untitled.id) { _ in Theme.blue }
        #expect(rows.map(\.name) == [CadenceAppleCalendarNaming.unnamedCalendarTitle])
    }

    /// Both editors build their Calendar row through the shared builder, and neither keeps a
    /// private list of its own.
    @Test func bothEventEditorsCallTheSharedBuilder() throws {
        for path in [
            "Cadence/macOS/Views/TimelineEventBlockSupportViews.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift",
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let source = CadenceSourceScan.strippingComments(raw)
            #expect(source != raw, "\(path): the comment stripper removed nothing")
            let body = try #require(
                CadenceSourceScan.declarationBody("private var calendarChoices", in: source),
                "\(path) no longer declares calendarChoices"
            )
            #expect(body.contains("CadenceEventEditorCalendarChoices.choices("),
                    "\(path) builds its Calendar row without the shared builder")
            #expect(!body.contains("writableCalendars.map"),
                    "\(path) titles the writable calendars itself again")
        }
    }
}
