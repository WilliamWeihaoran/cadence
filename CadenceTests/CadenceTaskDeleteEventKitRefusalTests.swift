import Foundation
import Testing

/// **T-3033.** Deleting a Cadence task must never delete the owner's real calendar event.
///
/// `AppTask.calendarEventID`'s doc comment used to tell the next reader that one of the property's
/// readers was "deleting a linked event with its task in `TaskDeleteHelpers`". That was false —
/// `TaskDeleteHelpers.swift` reaches no EventKit symbol at all — and the danger in a false comment
/// of that shape is specific: an agent reads it, notices the code does not match, and "restores"
/// the missing outbound delete. The comment is now a refusal and this suite is what makes the
/// refusal cost something to overturn.
///
/// **Why the code is the safe one.** The `AppTask` row belongs to Cadence; the `EKEvent` does not.
/// It may live on a shared or subscribed calendar, it may be owned by somebody else, it may carry
/// attendees and a history Cadence never saw, and `EKEventStore.remove` cannot be undone from
/// inside this app. Cadence→Calendar deletes do exist, in `CalendarManager.deleteEvent` and
/// `iOSCalendarManager.deleteEvent`, and every one of them is reached from an explicit Delete
/// gesture aimed at the *event*. Tidying a task list is not such a gesture.
///
/// The written contract for all four sync directions is `Cadence/macOS/Services/AGENTS.md`,
/// "EventKit Sync Directions".
///
/// **This is a source scan, and it has to be.** `CadenceTests` cannot drive EventKit — it cannot
/// make a store post a notification, and it must not open a real one — so the only way to hold
/// "this file reaches EventKit at all" is to read the file. The scan is comment-stripped on
/// purpose: a future reader is *welcome* to write the word `EventKit` in a comment explaining the
/// refusal, and only code may fail this.
struct CadenceTaskDeleteEventKitRefusalTests {

    /// The macOS task-delete cascade — the file the false comment named.
    private static let deleteHelpersPath = "Cadence/macOS/Services/TaskDeleteHelpers.swift"

    /// Reaching any of these from the delete cascade means a task delete has grown an outbound
    /// reach into the owner's real Calendar or Reminders database, or the link field that would
    /// give it a target.
    private static let eventKitSymbols = [
        "EventKit",
        "EKEvent",
        "EKEventStore",
        "EKSpan",
        "EKReminder",
        "EKCalendar",
        "CalendarManager",
        "calendarEventID",
        "deleteEvent",
    ]

    @Test func deletingATaskReachesNoEventKitSymbolSoItCannotDestroyTheOwnersRealCalendarEvent() throws {
        // Non-vacuity, first half: the file is still where the scan looks, found by walking the
        // directory rather than by trusting the remembered path. A scan whose subject has been
        // renamed or moved away must go red rather than quietly measure nothing (T-3015).
        let macOSServiceFiles = try CadenceSourceScan.swiftFiles(under: "Cadence/macOS/Services")
        #expect(
            macOSServiceFiles.contains(Self.deleteHelpersPath),
            """
            \(Self.deleteHelpersPath) is not under Cadence/macOS/Services any more. \
            The task-delete cascade moved; move this scan with it rather than deleting it — \
            the refusal it holds is that deleting a task must not delete a real calendar event.
            """
        )

        let source = try CadenceSourceScan.sourceFile(Self.deleteHelpersPath)
        let code = CadenceSourceScan.strippingComments(source)

        // Non-vacuity, second half: the stripper preserved offsets (its own contract), and what is
        // left is still the delete cascade and not an empty tombstone. Without this floor an
        // emptied, renamed or wholly commented-out file would pass every assertion below.
        #expect(code.count == source.count)
        #expect(CadenceSourceScan.matchCount(#"func deleteTask\("#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"func deleteTasks\("#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount("CadenceTaskMutationSupport", in: code) >= 1)
        let codeLines = code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(
            codeLines.count >= 40,
            "only \(codeLines.count) lines of code left in \(Self.deleteHelpersPath) — scan is vacuous"
        )

        // The refusal itself.
        for symbol in Self.eventKitSymbols {
            let hits = CadenceSourceScan.matchLines(symbol, in: code)
            #expect(
                hits.isEmpty,
                """
                \(Self.deleteHelpersPath) now reaches `\(symbol)` at \
                \(hits.map { "line \($0.line + 1)" }.joined(separator: ", ")).

                Deleting a Cadence task must not delete the owner's real calendar event. The event \
                may be shared, may be owned by someone else, and `EKEventStore.remove` is not \
                undoable from inside this app — so a task-list tidy would silently take events out \
                of other people's calendars. This is T-3033's refusal, not a missing feature: see \
                `AppTask.calendarEventID` and `Cadence/macOS/Services/AGENTS.md`, \
                "EventKit Sync Directions". If it must be overturned, overturn it there first.
                """
            )
        }
    }
}
