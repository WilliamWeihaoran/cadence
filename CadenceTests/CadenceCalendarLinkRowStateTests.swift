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

        #expect(source.contains("CadenceCalendarLink("),
                "the row does not ask for the link state")
        #expect(source.contains("linkState: CadenceCalendarLinkRowState { link.rowState }"),
                "the row's value no longer comes off the shared link value")
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

/// **T-464.** The row could say "Team (Hidden)" over a picker with no Team in it.
///
/// [[T-441]] taught the row to tell a hidden calendar from a deleted one and left the picker
/// offering `CalendarManager.availableCalendars` — the visible subset — so the one calendar the row
/// was talking about was the one calendar the menu did not contain. The user could read the state
/// and could not act on it: no re-pick of the same calendar, no confirmation of it, and the only
/// reachable move was "None", which is the silent overwrite T-441 exists to prevent, performed by
/// hand instead of by the code.
///
/// These pin the offer (visible **plus the linked one**, never any other hidden calendar) and pin
/// that the two surfaces read hiddenness off one value rather than each subtracting two arrays.
struct CadenceCalendarLinkPickerOfferTests {

    private let team = CadenceCalendarChoice(id: "cal-team", title: "Team")
    private let personal = CadenceCalendarChoice(id: "cal-personal", title: "Personal")
    private let archive = CadenceCalendarChoice(id: "cal-archive", title: "Archive")

    private func link(_ id: String, visible: Set<String>) -> CadenceCalendarLink {
        CadenceCalendarLink(
            linkedCalendarID: id,
            allCalendars: [team, personal, archive],
            visibleCalendarIDs: visible
        )
    }

    // MARK: - The offer

    /// The ticket in one assertion. `Team` is hidden and linked, `Archive` is hidden and not — the
    /// first is offered because it is already stored, the second is not, because linking to a
    /// calendar Cadence is not showing is still a decision for calendar settings.
    @Test func theLinkedHiddenCalendarIsOfferedAndOtherHiddenOnesAreNot() {
        let hidden = link("cal-team", visible: ["cal-personal"])

        #expect(hidden.rowState == .hidden(title: "Team"))
        #expect(hidden.pickableCalendars.map(\.id) == ["cal-team", "cal-personal"])
        #expect(hidden.pickableCalendars.contains(team),
                "the row names Team and the picker cannot offer it")
        #expect(hidden.pickableCalendars.contains(archive) == false,
                "a hidden calendar that was never linked reached the picker")
    }

    /// The T-441 decision, still intact where it applies: with nothing stored, the offer is exactly
    /// what Cadence is showing.
    @Test func anUnlinkedListIsOfferedTheVisibleCalendarsAlone() {
        let unlinked = link("", visible: ["cal-personal"])

        #expect(unlinked.rowState == .unlinked)
        #expect(unlinked.pickableCalendars == [personal])
        #expect(unlinked.hiddenPickableCalendarIDs.isEmpty)
    }

    /// A dead identifier names no calendar, so there is nothing to add back — the repair is still
    /// picking a live one, which is what [[T-400]] wanted.
    @Test func aDeadLinkAddsNothingToTheOffer() {
        let missing = link("cal-deleted-by-apple-calendar", visible: ["cal-personal"])

        #expect(missing.rowState == .missing)
        #expect(missing.pickableCalendars == [personal])
        #expect(missing.hiddenPickableCalendarIDs.isEmpty)
    }

    /// The ordinary case must not grow a duplicate row for the calendar that is both visible and
    /// linked — a `filter` says this by construction and an `append` would not, so it is pinned.
    @Test func aLinkedVisibleCalendarAppearsInTheOfferExactlyOnce() {
        let linked = link("cal-personal", visible: ["cal-personal", "cal-archive"])

        #expect(linked.rowState == .linked(title: "Personal"))
        #expect(linked.pickableCalendars.map(\.id) == ["cal-personal", "cal-archive"])
        #expect(linked.pickableCalendars.filter { $0.id == "cal-personal" }.count == 1)
        #expect(linked.hiddenPickableCalendarIDs.isEmpty)
    }

    /// Fixing the picker must not un-fix the row: the same value still reaches all four verdicts.
    @Test func theSharedValueStillReachesTheSameFourRowVerdicts() {
        #expect(link("", visible: ["cal-team"]).rowState == .unlinked)
        #expect(link("cal-team", visible: ["cal-team"]).rowState == .linked(title: "Team"))
        #expect(link("cal-team", visible: ["cal-personal"]).rowState == .hidden(title: "Team"))
        #expect(link("cal-gone", visible: ["cal-team"]).rowState == .missing)
    }

    // MARK: - One opinion about "hidden", not two

    /// The row's verdict and the picker's label are the same question asked once. If `isHidden`
    /// and `rowState` could disagree, the row would say "(Hidden)" over an undecorated menu row or
    /// the reverse.
    @Test func theRowVerdictAndThePickerLabelAgreeOnWhichCalendarIsHidden() {
        let hidden = link("cal-team", visible: ["cal-personal"])

        #expect(hidden.isHidden("cal-team"))
        #expect(hidden.isHidden("cal-personal") == false)
        #expect(hidden.hiddenPickableCalendarIDs == ["cal-team"])
        #expect(hidden.pickerLabel(title: "Team", calendarID: "cal-team") == hidden.rowState.valueText)
        #expect(hidden.pickerLabel(title: "Personal", calendarID: "cal-personal") == "Personal")
    }

    /// One spelling of the hidden wording, read by both surfaces rather than typed twice — the same
    /// rule `CadenceCalendarLinkHealth.missingLinkTitle` keeps for the dead-link wording.
    @Test func theHiddenWordingIsSpelledInExactlyOnePlace() {
        #expect(CadenceCalendarLinkRowState.hiddenTitle("Team") == "Team (Hidden)")
        #expect(CadenceCalendarLinkRowState.hidden(title: "Team").valueText
                == CadenceCalendarLinkRowState.hiddenTitle("Team"))
        #expect(CadenceCalendarLinkRowState.hiddenTitle("Team") != "Team",
                "a hidden calendar is indistinguishable from a shown one in the menu")
        #expect(CadenceCalendarLinkRowState.hiddenTitle("Team")
                != CadenceCalendarLinkRowState.unlinkedText)
    }

    // MARK: - The EventKit-shaped call the picker actually takes

    /// The picker draws `[EKCalendar]` — it needs each calendar's source for its group heading and
    /// its `cgColor` for the dot — so the shape the row hands it is pinned on real ones.
    @Test func theEventKitOfferCarriesTheHiddenCalendarThroughAsACalendar() {
        let store = EKEventStore()
        let visibleCalendar = EKCalendar(for: .event, eventStore: store)
        visibleCalendar.title = "Personal"
        let hiddenCalendar = EKCalendar(for: .event, eventStore: store)
        hiddenCalendar.title = "Team"
        #expect(visibleCalendar.calendarIdentifier != hiddenCalendar.calendarIdentifier,
                "EventKit minted one identifier for two calendars, so this arranges nothing")

        let all = [hiddenCalendar, visibleCalendar]
        let visible = [visibleCalendar]

        let linked = CadenceCalendarLink(
            linkedCalendarID: hiddenCalendar.calendarIdentifier,
            allCalendars: all,
            visibleCalendars: visible
        )
        #expect(linked.rowState == .hidden(title: "Team"))
        #expect(linked.pickableCalendars(from: all).map(\.calendarIdentifier)
                == [hiddenCalendar.calendarIdentifier, visibleCalendar.calendarIdentifier])
        #expect(linked.hiddenPickableCalendarIDs == [hiddenCalendar.calendarIdentifier])

        let unlinked = CadenceCalendarLink(
            linkedCalendarID: "",
            allCalendars: all,
            visibleCalendars: visible
        )
        #expect(unlinked.pickableCalendars(from: all).map(\.calendarIdentifier)
                == [visibleCalendar.calendarIdentifier])
        #expect(unlinked.hiddenPickableCalendarIDs.isEmpty)
    }

    // MARK: - The two surfaces

    /// A **source scan**: the row's popover is private SwiftUI, so what a test can check is that it
    /// hands the picker the offer and the hidden set rather than the visible subset it used to.
    @Test func theListEditorRowHandsThePickerTheOfferRatherThanTheVisibleSubset() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/ListEditorSupportViews.swift")
        #expect(raw.count > 400, "the support views read as \(raw.count) characters")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper removed nothing")
        #expect(source.count == raw.count, "the stripper changed the length")
        #expect(source.contains("struct ListEditorCalendarRow: View"), "the row moved")

        #expect(source.contains("calendars: link.pickableCalendars(from: allCalendars)"),
                "the row still opens a picker over the calendars it can see")
        #expect(source.contains("hiddenCalendarIDs: link.hiddenPickableCalendarIDs"),
                "the picker is not told which of the calendars it was handed are hidden")
        #expect(CadenceSourceScan.matchCount(#"calendars: calendars,"#, in: source) == 0,
                "the picker is handed the visible subset again, which is the T-464 bug")
    }

    /// The picker labels a hidden row by reading the row's wording. It must not spell "(Hidden)"
    /// itself — two literals is how the pair drifts, and the ticket asks for one meaning of hidden.
    @Test func thePickerReadsTheHiddenWordingInsteadOfSpellingIt() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/macOS/CadenceCalendarPicker.swift")
        #expect(raw.count > 400, "the picker read as \(raw.count) characters")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw, "the comment stripper removed nothing")
        #expect(source.count == raw.count, "the stripper changed the length")
        #expect(source.contains("struct CadenceCalendarPickerList: View"), "the picker moved")

        #expect(source.contains("var hiddenCalendarIDs: Set<String> = []"),
                "the picker cannot be told which calendars are hidden")
        #expect(source.contains("CadenceCalendarLinkRowState.hiddenTitle("),
                "the picker does not read the row's wording")
        #expect(CadenceSourceScan.matchCount(#"\(Hidden\)"#, in: source) == 0,
                "the picker spells the hidden wording itself")
        #expect(CadenceSourceScan.matchCount(#""None""#, in: source) == 0,
                "the picker spells the unlinked word itself rather than reading it")
    }

    /// Without these every `== 0` above is true of any text at all and every `contains` could be
    /// pinning a string that never appears in either shape.
    @Test func thePickerOfferScanNeedlesAreNotVacuous() {
        #expect(CadenceSourceScan.matchCount(#"calendars: calendars,"#,
                                             in: "CadenceCalendarPickerList(\ncalendars: calendars,\n") == 1)
        #expect(CadenceSourceScan.matchCount(#"calendars: calendars,"#,
                                             in: "calendars: link.pickableCalendars(from: allCalendars),") == 0)
        #expect(CadenceSourceScan.matchCount(#"\(Hidden\)"#, in: #"label = "\(title) (Hidden)""#) == 1)
        #expect(CadenceSourceScan.matchCount(#"\(Hidden\)"#,
                                             in: "label = CadenceCalendarLinkRowState.hiddenTitle(title)") == 0)
        #expect(CadenceSourceScan.matchCount(#""None""#, in: #"row(id: "", label: "None")"#) == 1)
        #expect(CadenceSourceScan.matchCount(#""None""#,
                                             in: "row(id: \"\", label: CadenceCalendarLinkRowState.unlinkedText)") == 0)
    }
}
