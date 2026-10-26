import Foundation
import Testing
@testable import Cadence

/// [[T-7070]]: one set of words for deleting a calendar event, on both platforms.
///
/// The Mac's three delete sites asked "Delete Calendar Event?" and named the event; the iPhone's
/// event sheet asked "Delete Event?" over "This removes the event from Apple Calendar." The
/// words now live once on `CadenceCalendarEventEditingSupport`, and every site reads them.
@MainActor
struct CadenceCalendarEventDeleteCopyTests {
    @Test func theMessageNamesTheEventAndSaysHowFarTheDeleteReaches() {
        #expect(CadenceCalendarEventEditingSupport.deleteConfirmationTitle == "Delete Calendar Event?")
        #expect(CadenceCalendarEventEditingSupport.deleteConfirmationLabel == "Delete")
        #expect(
            CadenceCalendarEventEditingSupport.deleteConfirmationMessage(eventTitle: "Standup", scope: .thisOccurrence)
                == "This will permanently delete \"Standup\" from your calendar."
        )
        #expect(
            CadenceCalendarEventEditingSupport.deleteConfirmationMessage(eventTitle: "Standup", scope: .futureOccurrences)
                == "This will permanently delete \"Standup\" and future events from your calendar."
        )
    }

    /// `Cadence/iOS/` is invisible to this macOS-built target, so the iPhone's sheet is read as
    /// source: it must ask through the shared copy, and its old private words must be gone.
    @Test func theIPhoneEventSheetAsksInTheMacsWords() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        )
        #expect(source.contains("CadenceCalendarEventEditingSupport.deleteConfirmationTitle"))
        #expect(source.contains("CadenceCalendarEventEditingSupport.deleteConfirmationLabel"))
        #expect(CadenceSourceScan.matchCount(#"CadenceCalendarEventEditingSupport\.deleteConfirmationMessage\("#, in: source) == 1)
        #expect(!source.contains("\"Delete Event?\""), "the iPhone sheet types its own delete title again")
        #expect(!source.contains("This removes the event from Apple Calendar."))
    }

    /// No site on either platform types the sentence out again.
    @Test func noSurfaceTypesTheDeleteWordsOutAgain() throws {
        var typedSites: [String] = []
        for directory in ["Cadence/macOS", "Cadence/iOS"] {
            for path in try CadenceSourceScan.swiftFiles(under: directory) {
                let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
                if source.contains("\"Delete Calendar Event?\"") || source.contains("from your calendar.\"") {
                    typedSites.append(path)
                }
            }
        }
        #expect(typedSites.isEmpty, "typed the event-delete copy out again: \(typedSites)")
    }
}

/// [[T-7075]]: deleting a repeating event asks how far first, then confirms for that scope.
///
/// The iPhone confirmed first and asked the scope second, so its confirmation could only read the
/// single-occurrence sentence even when the delete went on to remove the rest of the series.
@MainActor
struct CadenceEventDeleteStepTests {
    @Test func aSeriesMemberIsAskedTheScopeBeforeAnyConfirmation() {
        #expect(CadenceEventDeleteStep.first(isRecurringSeriesMember: true) == .askScope)
        #expect(CadenceEventDeleteStep.first(isRecurringSeriesMember: true).confirmationScope == nil)
    }

    @Test func aSingleEventGoesStraightToTheOneConfirmation() {
        #expect(CadenceEventDeleteStep.first(isRecurringSeriesMember: false) == .confirm(.thisOccurrence))
    }

    @Test func theConfirmationAfterTheScopeNamesTheScopeChosen() {
        for scope in CalendarRecurrenceEditScope.allCases {
            #expect(CadenceEventDeleteStep.afterScope(scope) == .confirm(scope))
            #expect(CadenceEventDeleteStep.afterScope(scope).confirmationScope == scope)
        }
    }

    /// `Cadence/iOS/` is not compiled into this target, so the wiring is read as source: the
    /// Delete button opens on `CadenceEventDeleteStep.first`, the scope dialog's delete path only
    /// queues the confirmation (on a later main-queue turn, after the scope dialog has gone), and
    /// the only delete write sits behind the confirmation, which names the scope it carries.
    @Test func theIPhoneSheetAsksScopeThenConfirmsThatScope() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        )
        let begin = try #require(CadenceSourceScan.functionBody(named: "beginDelete", in: source))
        #expect(begin.contains("CadenceEventDeleteStep.first(isRecurringSeriesMember: isRecurringEvent)"))
        #expect(!begin.contains("applyDelete("), "Delete writes before anything is confirmed")

        let pending = try #require(CadenceSourceScan.functionBody(named: "applyPendingAction", in: source))
        #expect(pending.contains("confirmDelete(after: scope)"))
        #expect(!pending.contains("applyDelete("), "the scope dialog deletes without a confirmation")

        let queued = try #require(CadenceSourceScan.functionBody(named: "confirmDelete", in: source))
        #expect(queued.contains("CadenceEventDeleteStep.afterScope(scope)"))
        #expect(queued.contains("DispatchQueue.main.async"), "the confirmation is raised while the scope dialog dismisses")

        // One write site plus its declaration, and that site is the confirmation's Delete button.
        #expect(CadenceSourceScan.matchCount(#"applyDelete\(scope:"#, in: source) == 2)
        let dialog = try #require(
            CadenceSourceScan.declarationBody(
                ".confirmationDialog(\n            CadenceCalendarEventEditingSupport.deleteConfirmationTitle",
                in: source
            )
        )
        #expect(dialog.contains("applyDelete(scope: scope)"))
        #expect(source.contains("eventTitle: iOSCalendarEventSupport.title(for: event),\n                    scope: scope"))
        #expect(!source.contains("scope: .thisOccurrence\n                )"), "the confirmation reads a fixed scope again")
    }
}

/// [[T-7072]]: a completed timed task's block says it is completed.
@MainActor
struct CadenceTimelineTaskBlockSpeechTests {
    @Test func aCompletedBlockIsAnnouncedAsCompleted() {
        #expect(
            CadenceCalendarDayAccessibility.timedTaskLabel(title: "Standup", timeRange: "9:00 – 9:30 AM", isDone: false)
                == "Standup, 9:00 – 9:30 AM"
        )
        #expect(
            CadenceCalendarDayAccessibility.timedTaskLabel(title: "Standup", timeRange: "9:00 – 9:30 AM", isDone: true)
                == "Standup, 9:00 – 9:30 AM, completed"
        )
    }

    /// The block is drawn struck through on `task.isDone`; the label must read the same flag.
    @Test func theIOSTimelineBlockPassesTheDoneFlagItDrawsWith() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        )
        #expect(CadenceSourceScan.matchCount(#"\.strikethrough\(task\.isDone"#, in: source) == 1)
        #expect(
            CadenceSourceScan.matchCount(
                #"CadenceCalendarDayAccessibility\.timedTaskLabel\([\s\S]{0,400}?isDone: task\.isDone"#,
                in: source
            ) == 1,
            "the timeline task block no longer speaks its done state"
        )
    }
}

/// [[T-7071]]: the phone's Notes tab strip draws "Pad" and "Events" for width, and VoiceOver
/// should still hear the tab's real name.
@MainActor
struct CadenceNotesTabSpokenLabelTests {
    @Test func theAbbreviatedTabsAreSpokenInFull() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNotesView.swift")
        )
        #expect(
            CadenceSourceScan.matchCount(#"spokenTitle:\s*tab\.label\b"#, in: source) == 1,
            "the Notes tab strip no longer hands its buttons the full tab name to speak"
        )
        #expect(CadenceSourceScan.matchCount(#"\.accessibilityLabel\(spokenTitle \?\? title\)"#, in: source) == 1)
        // Voice Control still answers to the drawn word.
        #expect(CadenceSourceScan.matchCount(#"\.accessibilityInputLabels\("#, in: source) == 1)
        #expect(CadenceNotesTabVocabulary.notepad.label == "Notepad")
        #expect(CadenceNotesTabVocabulary.notepad.shortLabel != CadenceNotesTabVocabulary.notepad.label)
    }
}

/// [[T-7073]]: the capture card's "Allow Calendar Access" did nothing on a device that had already
/// refused, because iOS never shows the prompt twice. Both capture hosts now read the shared
/// access notice, which offers the Settings app in that state.
@MainActor
struct CadenceCaptureCalendarAccessTests {
    @Test func bothCaptureHostsAskThroughTheOneNoticeReadingControl() throws {
        let slotSheet = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")
        )
        let plusSheet = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCreateTaskSheet.swift")
        )
        let button = try #require(
            CadenceSourceScan.declarationBody("struct iOSCaptureCalendarAccessButton: View", in: slotSheet),
            "non-vacuity: the shared capture access control was not found"
        )
        #expect(button.contains("CadenceCalendarAccessNotice.resolve("))
        #expect(button.contains("isDenied: calendarManager.isDenied"), "a refusal is no longer told apart from never asked")
        #expect(button.contains("notice.actionTitle(on: .mobile)"))
        #expect(button.contains("case .openSystemSettings:"))
        #expect(button.contains("UIApplication.openSettingsURLString"), "a refused device is offered nothing that works")

        for (name, source) in [("slot sheet", slotSheet), ("+ sheet", plusSheet)] {
            #expect(
                CadenceSourceScan.matchCount(#"iOSCaptureCalendarAccessButton\(calendarManager: calendarManager\)"#, in: source) == 1,
                "the \(name) no longer draws the shared access control"
            )
            #expect(!source.contains("\"Allow Calendar Access\""), "the \(name) spells its own access button again")
        }
        // The only prompt either host raises is the shared control's.
        #expect(CadenceSourceScan.matchCount(#"requestAccess\(\)"#, in: plusSheet) == 0)
        #expect(CadenceCalendarAccessNotice.resolve(isAuthorized: false, isDenied: true)?.action == .openSystemSettings)
        #expect(CadenceCalendarAccessNotice.resolve(isAuthorized: false, isDenied: false)?.action == .requestAccess)
        #expect(CadenceCalendarAccessNotice.resolve(isAuthorized: true, isDenied: false) == nil)
    }
}
