import EventKit
import Foundation
import Testing
@testable import Cadence

/// **T-441.** The list editor's Apple Calendar row said "None" for three different situations.
///
/// `ListEditorCalendarRow` looked its title up in `CalendarManager.availableCalendars` — the
/// *visible* subset — and rendered `selectedTitle ?? "None"`. So a link to a live calendar the user
/// had merely unticked in Cadence's calendar settings was indistinguishable from a list that had
/// never been linked, and so was a link whose calendar Apple Calendar had deleted.
///
/// `CadenceCalendarLinkHealth` names this exact trap in its own contract — hidden is not missing,
/// and passing the visible subset reports every hidden link dead. These pin that the row's decision
/// now honours it.
struct CadenceCalendarLinkRowStateTests {

    private let team = CadenceCalendarChoice(id: "cal-team", title: "Team")
    private let personal = CadenceCalendarChoice(id: "cal-personal", title: "Personal")

    private func state(
        linkedTo id: String,
        all: [CadenceCalendarChoice],
        visible: Set<String>
    ) -> CadenceCalendarLinkRowState {
        CadenceCalendarLinkRowState.forLink(
            linkedCalendarID: id,
            allCalendars: all,
            visibleCalendarIDs: visible
        )
    }

    // MARK: - The three cases the row used to collapse

    /// The whole ticket in one assertion: three inputs that used to render the same word are three
    /// different verdicts, and none of them equals another.
    @Test func unlinkedHiddenAndMissingAreThreeDifferentAnswers() {
        let unlinked = state(linkedTo: "", all: [team, personal], visible: ["cal-team", "cal-personal"])
        let hidden = state(linkedTo: "cal-team", all: [team, personal], visible: ["cal-personal"])
        let missing = state(linkedTo: "cal-gone", all: [team, personal], visible: ["cal-team"])
        let linked = state(linkedTo: "cal-team", all: [team, personal], visible: ["cal-team"])

        #expect(unlinked == .unlinked)
        #expect(hidden == .hidden(title: "Team"))
        #expect(missing == .missing)
        #expect(linked == .linked(title: "Team"))

        let verdicts = [unlinked, hidden, missing, linked]
        for (index, one) in verdicts.enumerated() {
            for other in verdicts[(index + 1)...] {
                #expect(one != other, "\(one) and \(other) are still the same answer")
            }
        }
    }

    /// The user-visible half. Four states, four strings — and the two that used to be "None" now
    /// say what is actually wrong.
    @Test func theRowValueSaysWhichOfTheThreeItIs() {
        #expect(CadenceCalendarLinkRowState.unlinked.valueText == "None")
        #expect(CadenceCalendarLinkRowState.linked(title: "Team").valueText == "Team")
        #expect(CadenceCalendarLinkRowState.hidden(title: "Team").valueText == "Team (Hidden)")
        #expect(CadenceCalendarLinkRowState.hidden(title: "Team").valueText != "None")
        #expect(CadenceCalendarLinkRowState.missing.valueText != "None")
        #expect(CadenceCalendarLinkRowState.missing.valueText
                != CadenceCalendarLinkRowState.unlinked.valueText)
    }

    /// The break is worded by `CadenceCalendarLinkHealth`, not re-typed here. Two surfaces report
    /// the same dead link; that type keeps the one spelling and this row reads it.
    @Test func theBrokenLinkIsWordedByTheHealthCheckRatherThanTheRow() {
        #expect(CadenceCalendarLinkRowState.missing.valueText
                == CadenceCalendarLinkHealth.missingLinkTitle)
        #expect(!CadenceCalendarLinkHealth.missingLinkTitle.isEmpty)
    }

    /// A broken link is a *set* field. Something is stored, and dimming it back to the unset
    /// treatment is the collapse the whole ticket is about — the row has to look occupied so that
    /// "None" keeps meaning "nothing here".
    @Test func onlyAnUnlinkedListDrawsAsAnUnsetField() {
        #expect(CadenceCalendarLinkRowState.unlinked.isSet == false)
        #expect(CadenceCalendarLinkRowState.linked(title: "Team").isSet)
        #expect(CadenceCalendarLinkRowState.hidden(title: "Team").isSet)
        #expect(CadenceCalendarLinkRowState.missing.isSet)
    }

    /// The false alarm `CadenceCalendarLinkHealth`'s contract warns about, reproduced against this
    /// type: hand it only what the picker can see and a hidden calendar's link reads as dead.
    /// Passing both lists is the fix, so this pins that both are actually read.
    @Test func passingOnlyTheVisibleCalendarsIsWhatMadeHiddenLookMissing() {
        let honest = state(linkedTo: "cal-team", all: [team, personal], visible: ["cal-personal"])
        let visibleSubsetOnly = state(linkedTo: "cal-team", all: [personal], visible: ["cal-personal"])

        #expect(honest == .hidden(title: "Team"))
        #expect(visibleSubsetOnly == .missing)
        #expect(honest != visibleSubsetOnly)
    }

    /// An empty identifier is unlinked whatever the calendar lists hold — including when EventKit
    /// has nothing at all, which is what an unauthorized store looks like.
    @Test func anEmptyIdentifierIsUnlinkedEvenWithNoCalendarsAtAll() {
        #expect(state(linkedTo: "", all: [], visible: []) == .unlinked)
        #expect(state(linkedTo: "", all: [team], visible: ["cal-team"]) == .unlinked)
    }

    // MARK: - The EventKit-shaped call the row actually makes

    /// The row hands `[EKCalendar]`, so the overload it uses is pinned on real ones rather than on
    /// the value type alone.
    @Test func theEventKitOverloadReachesTheSameVerdict() {
        let store = EKEventStore()
        let visibleCalendar = EKCalendar(for: .event, eventStore: store)
        visibleCalendar.title = "Team"
        let hiddenCalendar = EKCalendar(for: .event, eventStore: store)
        hiddenCalendar.title = "Personal"
        #expect(visibleCalendar.calendarIdentifier != hiddenCalendar.calendarIdentifier,
                "EventKit minted one identifier for two calendars, so this arranges nothing")

        let all = [visibleCalendar, hiddenCalendar]
        let visible = [visibleCalendar]

        #expect(CadenceCalendarLinkRowState.forLink(
            linkedCalendarID: visibleCalendar.calendarIdentifier,
            allCalendars: all,
            visibleCalendars: visible
        ) == .linked(title: "Team"))

        #expect(CadenceCalendarLinkRowState.forLink(
            linkedCalendarID: hiddenCalendar.calendarIdentifier,
            allCalendars: all,
            visibleCalendars: visible
        ) == .hidden(title: "Personal"))

        #expect(CadenceCalendarLinkRowState.forLink(
            linkedCalendarID: "cal-deleted-by-apple-calendar",
            allCalendars: all,
            visibleCalendars: visible
        ) == .missing)

        #expect(CadenceCalendarLinkRowState.forLink(
            linkedCalendarID: "",
            allCalendars: all,
            visibleCalendars: visible
        ) == .unlinked)
    }

    // MARK: - The row asks

    /// A **source scan**: `ListEditorCalendarRow` is a SwiftUI view whose `linkState` is private, so
    /// what a test can check is that the row routes to the decision above rather than titling what
    /// it can see. `ListEditorSupportViews.swift` is macOS, which this target does compile — the
    /// scan is about reachability, not about the platform.
    @Test func theListEditorRowAsksForTheLinkStateInsteadOfTitlingWhatItCanSee() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/ListEditorSupportViews.swift")
        #expect(raw.count > 400, "the support views read as \(raw.count) characters")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper removed nothing")
        #expect(source.count == raw.count, "the stripper changed the length")
        #expect(source.contains("struct ListEditorCalendarRow: View"), "the row moved")

        #expect(source.contains("CadenceCalendarLinkRowState.forLink("),
                "the row does not ask for the link state")
        #expect(source.contains("let allCalendars: [EKCalendar]"),
                "the row cannot tell hidden from missing without every calendar EventKit has")
        #expect(source.contains("valueText: linkState.valueText"))
        #expect(source.contains("isSet: linkState.isSet"))

        #expect(CadenceSourceScan.matchCount(#"selectedTitle"#, in: source) == 0,
                "the row still derives its value from the calendars it can see")
        #expect(CadenceSourceScan.matchCount(#"\?\?\s*"None""#, in: source) == 0,
                "the row still spells the unlinked word itself")
    }

    /// Both editors hand the row every calendar, not the pickable subset — the parameter exists in
    /// the row and is fed the wrong thing is exactly how this bug would come back.
    @Test func bothListEditorsHandTheRowEveryCalendarEventKitHas() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/EditListSheet.swift")
        #expect(raw.count > 400, "the edit sheet read as \(raw.count) characters")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper removed nothing")
        #expect(source.count == raw.count, "the stripper changed the length")
        #expect(source.contains("struct EditAreaSheet: View"), "the area editor moved")
        #expect(source.contains("struct EditProjectSheet: View"), "the project editor moved")

        #expect(CadenceSourceScan.matchCount(#"ListEditorCalendarRow\("#, in: source) == 2,
                "there are no longer exactly two calendar rows to check")
        #expect(CadenceSourceScan.matchCount(#"allCalendars: calendarManager\.allCalendars"#, in: source) == 2,
                "an editor hands the row the visible subset, which is the T-441 bug")
    }

    /// Without this every `== 0` above is true of any text at all, and every `== 2` could be
    /// counting something else.
    @Test func theLinkRowScanNeedlesAreNotVacuous() {
        #expect(CadenceSourceScan.matchCount(#"selectedTitle"#, in: "let x = selectedTitle ?? \"None\"") == 1)
        #expect(CadenceSourceScan.matchCount(#"selectedTitle"#, in: "let x = linkState.valueText") == 0)
        #expect(CadenceSourceScan.matchCount(#"\?\?\s*"None""#, in: "valueText: selectedTitle ?? \"None\"") == 1)
        #expect(CadenceSourceScan.matchCount(#"\?\?\s*"None""#, in: "valueText: linkState.valueText") == 0)
        #expect(CadenceSourceScan.matchCount(#"ListEditorCalendarRow\("#,
                                             in: "ListEditorCalendarRow(\nListEditorCalendarRow(") == 2)
        #expect(CadenceSourceScan.matchCount(#"allCalendars: calendarManager\.allCalendars"#,
                                             in: "allCalendars: calendarManager.availableCalendars") == 0)
    }
}
