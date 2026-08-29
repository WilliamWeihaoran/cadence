import EventKit
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-403.** `CadenceCalendarEventSearchSupport.identity(of:)` re-spelled the first two lines of
/// `CadenceEventNoteSupport.rawIdentifier`, because `precedes` is handed to `sorted(by:)` from
/// `iOSCalendarManager.fetchEvents` as a plain function value and so has to stay `nonisolated`,
/// while `rawIdentifier` was main-actor isolated under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
///
/// This suite is deliberately **not** `@MainActor`. That is the load-bearing part: every call to
/// `CadenceEventNoteSupport.rawIdentifier` below is synchronous from a nonisolated context, which
/// is a thing the compiler either allows or diagnoses. Before the fix it diagnosed it — measured,
/// not assumed: with `nonisolated` on `rawIdentifier` alone the macOS build still *succeeded*,
/// because the app target is in the Swift 5 language mode where isolation violations are warnings,
/// and emitted exactly one — `call to main actor-isolated static method 'fallbackIdentifier(for:)'
/// in a synchronous nonisolated context`. Against a zero warning baseline that is a regression, and
/// under Swift 6 it is an error, so the keyword had to reach `fallbackIdentifier` and the
/// `startMinute` it calls in turn. The enum as a whole cannot take it: the rest of it works on
/// `Note`, a `@Model` type.
struct CadenceEventIdentityBorrowTests {

    /// One store for the suite, for the reason `CadenceCalendarEventSearchSupportTests` gives.
    private let store = EKEventStore()

    private func event(title: String, start: Date) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        return event
    }

    private var noon: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    /// The borrow itself, at the only isolation that matters. If `rawIdentifier` ever goes back to
    /// being main-actor isolated this line stops compiling, which is a louder failure than a red
    /// assertion and is the actual guarantee T-403 needs.
    @Test func theSearchIdentityLegIsTheEventNoteSupportIdentifier() {
        let event = event(title: "Standup", start: noon)
        #expect(CadenceCalendarEventSearchSupport.identity(of: event)
                == CadenceEventNoteSupport.rawIdentifier(for: event))
        #expect(!CadenceCalendarEventSearchSupport.identity(of: event).isEmpty,
                "EventKit minted no identifier at all, so this test compared nothing")
    }

    /// The suffix stays out of the identity leg. `identifier(for:)` appends `#occurrence=` for a
    /// series member, and `precedes` compares `startInstant` first — so the suffix could never
    /// break a tie this leg is asked to break, and borrowing the wrong one of the two functions
    /// would be a silently different sort.
    @Test func theIdentityLegBorrowsTheRawIdentifierAndNotTheOccurrenceScopedOne() {
        let recurring = event(title: "Weekly sync", start: noon)
        recurring.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))

        #expect(CadenceEventNoteSupport.isRecurringSeriesMember(recurring),
                "the fixture is not a series member, so the two identifiers cannot differ")
        #expect(!CadenceCalendarEventSearchSupport.identity(of: recurring).contains("#occurrence="))
    }

    /// `precedes` still runs, still totally orders, and still does it from a nonisolated context —
    /// which is what `sorted(by:)` needs of it. Two events sharing a start and a title are
    /// separated by the borrowed leg.
    @Test func precedesStillTotallyOrdersTwoEventsSharingAStartAndATitle() {
        let first = event(title: "Standup", start: noon)
        let second = event(title: "Standup", start: noon)

        let ordered = [first, second].sorted(by: CadenceCalendarEventSearchSupport.precedes)
        let reversed = [second, first].sorted(by: CadenceCalendarEventSearchSupport.precedes)
        #expect(ordered.map(CadenceCalendarEventSearchSupport.identity)
                == reversed.map(CadenceCalendarEventSearchSupport.identity),
                "the two arrangements sorted differently, so the order is still not total")
        #expect(CadenceCalendarEventSearchSupport.precedes(first, second)
                != CadenceCalendarEventSearchSupport.precedes(second, first),
                "neither event precedes the other, so the identity leg separated nothing")
    }

    /// The copy is gone from the source, not merely equivalent to the original at runtime. The two
    /// spellings agree today on every event EventKit will mint — that is why the duplication
    /// survived — so equality alone cannot tell a borrow from a re-typing.
    @Test func theIdentityLegNoLongerRespellsTheIdentifierRule() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceCalendarEventSearchSupport.swift")
        #expect(raw.count > 400, "the search support file read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")
        #expect(stripped.contains("enum CadenceCalendarEventSearchSupport"), "the scan read the wrong file")

        let identity = try #require(
            CadenceSourceScan.functionBody(named: "identity", in: stripped),
            "CadenceCalendarEventSearchSupport has no identity(of:)"
        )
        #expect(identity.contains("CadenceEventNoteSupport.rawIdentifier(for: event)"),
                "identity(of:) does not borrow the identifier rule")
        #expect(CadenceSourceScan.matchCount(#"event\.eventIdentifier"#, in: identity) == 0,
                "identity(of:) still re-spells rawIdentifier's first line (T-403)")
        #expect(CadenceSourceScan.matchCount(#"event\.calendarItemIdentifier"#, in: identity) == 0,
                "identity(of:) still re-spells rawIdentifier's second line (T-403)")
    }

    /// The keyword reaches everything `rawIdentifier` calls. Stated on the source because the
    /// alternative — the warning it otherwise emits — is invisible to a test, and a build that
    /// succeeds with a new warning is exactly how this would come back.
    @Test func theBorrowedIdentifierAndEverythingItReachesAreNonisolated() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceEventNoteSupport.swift")
        #expect(raw.count > 400, "CadenceEventNoteSupport.swift read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.contains("enum CadenceEventNoteSupport"), "the scan read the wrong file")

        for declaration in [
            "nonisolated static func rawIdentifier(for event: EKEvent) -> String",
            "nonisolated private static func fallbackIdentifier(for event: EKEvent) -> String",
            "nonisolated static func startMinute(for date: Date, calendar: Calendar = .current) -> Int"
        ] {
            #expect(stripped.contains(declaration), "not nonisolated: \(declaration)")
        }

        // Not the enum. `note(for:in:)` and its neighbours work on `Note`, a `@Model` type, and a
        // nonisolated enum would drag every one of them off the main actor.
        #expect(CadenceSourceScan.matchCount(#"nonisolated enum CadenceEventNoteSupport"#, in: stripped) == 0)
    }
}

/// **T-407.** `iOSTaskDetailSheet` was the one task surface outside both the date wrapper
/// ([[T-362]]) and the status wrapper ([[T-343]]), and it also threw away what `delete` returned.
/// Neither wrapper reached it because both halves belong to the sheet's own lifecycle rather than
/// to a row action.
///
/// All of it is a **source scan**: the file is under `Cadence/iOS/`, behind `#if os(iOS)`, and this
/// target builds for macOS — so it cannot be instantiated here. What the behaviour of the routed
/// wrapper is worth is pinned in `CadenceTaskStatusEditingSurfaceTests`; this pins that the sheet
/// reaches it, and that the two things which must *not* be routed still are not.
@MainActor
struct IOSTaskDetailSheetResidueTests {

    private static let path = "Cadence/iOS/iOSTaskDetailSheet.swift"

    private func sheetSource() throws -> String {
        let raw = try CadenceSourceScan.sourceFile(Self.path)
        #expect(raw.count > 400, "\(Self.path) read as \(raw.count) characters")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper removed nothing")
        #expect(stripped.count == raw.count, "the stripper changed the length")
        #expect(stripped.contains("struct iOSTaskDetailSheet: View"), "the sheet moved")
        return stripped
    }

    /// The sheet already had a `ModelContext` in the environment, which is why routing it is two
    /// call-site edits and not a signature change — the same thing that let T-343 close its other
    /// six surfaces outright.
    @Test func theSheetAlreadyHoldsTheModelContextTheWrappersNeed() throws {
        let sheet = try sheetSource()
        #expect(sheet.contains(#"@Environment(\.modelContext) private var modelContext"#))
    }

    /// The two real transitions this sheet offers: the status well and the completion circle.
    @Test func bothStatusTransitionsInTheSheetRouteThroughTheStatusWrapper() throws {
        let sheet = try sheetSource()

        #expect(sheet.contains("CadenceTaskStatusEditing.setStatus(status, for: task, in: modelContext)"),
                "the status well still calls the pure mutation layer, so its change never reconciles (T-407)")

        let toggle = try #require(
            CadenceSourceScan.functionBody(named: "toggleCompletion", in: sheet),
            "the sheet has no toggleCompletion()"
        )
        #expect(toggle.contains("CadenceTaskStatusEditing.toggleCompletion(task, in: modelContext)"),
                "the completion circle still calls the pure mutation layer (T-407)")
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskMutationSupport\.toggleCompletion"#, in: sheet) == 0)
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskMutationSupport\.setStatus"#, in: sheet) == 0)
    }

    /// The explicit carve-out, stated as an assertion so it cannot be "tidied" later.
    ///
    /// `normalizeCompletionState` is the repair every field observer on the sheet fires through —
    /// title keystrokes, priority, estimate, section, and the date loads on appear. Routing it
    /// through the status wrapper would run a store-wide notification reconcile on every one of
    /// them, for a status that in almost all of those calls did not move.
    @Test func theSheetsCompletionNormalisationIsDeliberatelyNotRouted() throws {
        let sheet = try sheetSource()
        let save = try #require(
            CadenceSourceScan.functionBody(named: "saveTask", in: sheet),
            "the sheet has no saveTask()"
        )
        #expect(save.contains("CadenceTaskMutationSupport.normalizeCompletionState(for: task, modelContext: modelContext)"),
                "the normalisation moved or was routed through the status wrapper (T-407)")
        #expect(!save.contains("CadenceTaskStatusEditing"),
                "opening the sheet now reconciles, which is the thing T-407 warns against")

        // And the wrapper never grew an entry point for it, which is the other way this could land.
        let wrapper = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskStatusEditing.swift")
        )
        #expect(wrapper.contains("enum CadenceTaskStatusEditing"), "the scan read the wrong file")
        #expect(CadenceSourceScan.matchCount(#"normalizeCompletionState"#, in: wrapper) == 0)
    }

    /// The delete half. `delete` has answered `false` for a refused-and-rolled-back commit since
    /// T-365; this sheet dismissed on the tap either way, so it closed announcing a removal the
    /// store never took.
    @Test func theSheetOnlyDismissesOnADeleteThatLanded() throws {
        let sheet = try sheetSource()

        let delete = try #require(
            CadenceSourceScan.functionBody(named: "deleteTask", in: sheet),
            "the sheet has no deleteTask(), so the delete still runs inline in the alert button"
        )
        #expect(delete.contains("guard CadenceTaskMutationSupport.delete(task, modelContext: modelContext) else"),
                "the sheet still throws away the delete's answer (T-407)")
        #expect(delete.contains("deleteFailed = true"))
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: delete) == 1,
                "the sheet dismisses on a path other than the successful delete")

        // The `return` before it is what keeps the single `dismiss()` out of the failure branch.
        // Ordered as offsets rather than as a slice: a mutation that reverses them must fail this
        // assertion, not trap building the range for it.
        let failure = try #require(delete.range(of: "deleteFailed = true"))
        let success = try #require(delete.range(of: "dismiss()"))
        let failureOffset = delete.distance(from: delete.startIndex, to: failure.upperBound)
        let successOffset = delete.distance(from: delete.startIndex, to: success.lowerBound)
        #expect(failureOffset < successOffset, "the dismiss runs before the failure is recorded")
        guard failureOffset < successOffset else { return }
        #expect(delete[failure.upperBound..<success.lowerBound].contains("return"),
                "the failure branch falls through into the dismiss")
    }

    /// **T-376's pattern, not a third one.** A confirmation alert dismisses itself on the button
    /// tap, so the failure lands on a second alert wording the shared sentence — the same shape
    /// `iOSTaskRow` took, which is the only other surface with this problem.
    @Test func theRefusedDeleteNoticeMatchesTheRowsRatherThanInventingAThirdShape() throws {
        let sheet = try sheetSource()
        #expect(sheet.contains("@State private var deleteFailed = false"))
        #expect(sheet.contains(#".alert("Couldn't Delete Task", isPresented: $deleteFailed)"#),
                "the sheet has nowhere to report a failed delete")
        #expect(sheet.contains("Text(CadenceTaskMutationSupport.deleteFailureNotice)"),
                "the sheet words the failure itself instead of reading the shared sentence")

        let row = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift")
        )
        #expect(row.contains("struct iOSTaskRow: View"), "the scan read the wrong file")
        for shared in [
            "@State private var deleteFailed = false",
            #".alert("Couldn't Delete Task", isPresented: $deleteFailed)"#,
            "Text(CadenceTaskMutationSupport.deleteFailureNotice)"
        ] {
            #expect(row.contains(shared), "the row no longer carries \(shared), so this is not one pattern")
        }
    }

    /// The needles fire on the shapes they hunt and stay silent on the ones they must not —
    /// without which every `== 0` above is true of any text at all.
    @Test func theSheetScanNeedlesAndReaderAreNotVacuous() throws {
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskMutationSupport\.setStatus"#,
                                             in: "CadenceTaskMutationSupport.setStatus(s, for: t, modelContext: c)") == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskMutationSupport\.setStatus"#,
                                             in: "CadenceTaskStatusEditing.setStatus(s, for: t, in: c)") == 0)
        #expect(CadenceSourceScan.matchCount(#"normalizeCompletionState"#,
                                             in: "CadenceTaskMutationSupport.normalizeCompletionState(for: t, modelContext: c)") == 1)
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: "dismiss()\ndismiss()") == 2)
        #expect(CadenceSourceScan.matchCount(#"dismiss\(\)"#, in: "dismissed(x)") == 0)

        // The reader really returns the repository's text, and the sheet really is the file with
        // both problems' fixes in it.
        let sheet = try sheetSource()
        #expect(sheet.contains("iOSTaskStatusActionsSection(task: task)"),
                "the status well moved out of the sheet, so the routing assertions prove nothing")
    }
}
