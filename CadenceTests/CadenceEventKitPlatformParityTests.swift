import Foundation
import Testing
@testable import Cadence

// Two places where the iOS EventKit surface lagged a pattern macOS already had.
//
// T-323: an `EKEventStoreChanged` notification means either "the data changed" or "the user just
// granted or revoked Calendar access in Settings". macOS's handler answered both; iOS's bumped
// `storeVersion` and stopped, so a mid-session revocation left `isAuthorized` stale-true until
// relaunch.
//
// T-325: `iOSEventNoteEditorSheet` committed the note with `try? modelContext.save()` and then
// pushed the same text into the native `EKEvent` regardless of whether that commit landed. Apple
// Calendar is outside Cadence and cannot be rolled back from inside it.
//
// EventKit cannot be driven from a unit test — nothing here can make it post a notification or
// revoke a grant — so both fixes are values in `Cadence/Shared/` that a test can run directly,
// the same move `CadenceRemindersManager.reconcileLedger` makes. The call sites live under
// `Cadence/iOS/`, which `CadenceTests` does not compile, so those are pinned by reading the
// source; every such assertion below is positive and comment-stripped.
@Suite(.serialized)
struct CadenceEventKitPlatformParityTests {

    // MARK: - T-323: a store change re-derives authorization

    /// Stands in for a calendar manager: a cached `isAuthorized`, a version counter, and a live
    /// EventKit status the cache can disagree with. Exactly the state a revocation creates.
    private final class StoreChangeStandIn {
        var isAuthorized: Bool
        var storeVersion = 0
        var liveStatusGrantsAccess: Bool

        init(cachedAuthorization: Bool, liveStatusGrantsAccess: Bool) {
            self.isAuthorized = cachedAuthorization
            self.liveStatusGrantsAccess = liveStatusGrantsAccess
        }

        @discardableResult
        func handleStoreChange() -> CadenceCalendarStoreChangeEffects {
            CadenceCalendarStoreChangeSupport.apply(
                bumpVersion: { storeVersion += 1 },
                refreshAuthorization: { isAuthorized = liveStatusGrantsAccess }
            )
        }
    }

    @Test func aStoreChangeCorrectsACachedGrantThatWasRevokedOutsideTheApp() {
        let manager = StoreChangeStandIn(cachedAuthorization: true, liveStatusGrantsAccess: false)

        let effects = manager.handleStoreChange()

        // The bug: this was the only thing that happened.
        #expect(manager.storeVersion == 1)
        // The fix: the cached grant is re-derived from the live status, not kept.
        #expect(manager.isAuthorized == false)
        #expect(effects == CadenceCalendarStoreChangeEffects(versionBumps: 1, authorizationRefreshes: 1))
    }

    /// Converges from the other direction too, so a handler that hardcoded `false` — or one that
    /// only ever tightened — would not pass either.
    @Test func aStoreChangeAlsoAdoptsAGrantMadeOutsideTheApp() {
        let manager = StoreChangeStandIn(cachedAuthorization: false, liveStatusGrantsAccess: true)

        manager.handleStoreChange()

        #expect(manager.isAuthorized == true)
        #expect(manager.storeVersion == 1)
    }

    @Test func repeatedStoreChangesKeepCountingBothEffects() {
        let manager = StoreChangeStandIn(cachedAuthorization: true, liveStatusGrantsAccess: true)

        for _ in 0..<3 {
            manager.handleStoreChange()
        }

        #expect(manager.storeVersion == 3)
    }

    /// The version bump is published before authorization is re-derived, because re-deriving it
    /// is the step that can tear the observer down mid-notification.
    @Test func theVersionBumpHappensBeforeAuthorizationIsReDerived() {
        var order: [String] = []

        let effects = CadenceCalendarStoreChangeSupport.apply(
            bumpVersion: { order.append("bump") },
            refreshAuthorization: { order.append("refresh") }
        )

        #expect(order == ["bump", "refresh"])
        #expect(effects.versionBumps == 1)
        #expect(effects.authorizationRefreshes == 1)
    }

    @Test func bothCalendarManagersRouteTheirStoreChangeThroughTheSharedHandler() throws {
        for path in [
            "Cadence/iOS/iOSCalendarManager.swift",
            "Cadence/macOS/Services/CalendarManager.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.strippingComments(raw)
            #expect(code.count == raw.count, "\(path): the stripper must blank, never shorten")
            #expect(code != raw, "\(path): expected comments to have been blanked")

            let handler = try #require(
                CadenceSourceScan.functionBody(named: "handleStoreChangeNotification", in: code),
                "\(path) has no handleStoreChangeNotification body to read"
            )
            #expect(
                handler.contains("CadenceCalendarStoreChangeSupport.apply("),
                "\(path) must route its store change through the shared handler, not bump a version inline"
            )
        }
    }

    /// The iOS observer used to be `self?.storeVersion += 1` inline — half the handler, with no
    /// name to hang the other half on.
    @Test func theIOSStoreObserverDelegatesToTheHandlerInsteadOfBumpingInline() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarManager.swift")
        )
        let observer = try #require(CadenceSourceScan.functionBody(named: "startObserving", in: code))

        #expect(observer.contains(".EKEventStoreChanged"))
        #expect(observer.contains("self?.handleStoreChangeNotification()"))
        #expect(!observer.contains("storeVersion += 1"))
    }

    // MARK: - T-325: the local commit is ordered before the external write

    private var commitFailure: NSError {
        NSError(domain: "CadenceTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])
    }

    /// The ticket's whole point: Apple Calendar can hold text Cadence does not, and nothing the
    /// user does inside Cadence takes it back. So a save that threw must not be followed by the
    /// sync at all — not "followed by a sync that is then apologised for".
    @Test func aFailedLocalCommitNeverReachesAppleCalendar() {
        var syncCalls = 0

        let outcome = CadenceEventNoteSupport.commitNote(
            syncToCalendar: true,
            save: { throw self.commitFailure },
            syncToNativeEvent: {
                syncCalls += 1
                return true
            }
        )

        #expect(syncCalls == 0)
        #expect(outcome == .notSaved("disk full"))
        #expect(outcome.isSaved == false)
        #expect(outcome.notice != nil)
    }

    @Test func aSuccessfulCommitSyncsExactlyOnceAndHasNothingToReport() {
        var syncCalls = 0

        let outcome = CadenceEventNoteSupport.commitNote(
            syncToCalendar: true,
            save: {},
            syncToNativeEvent: {
                syncCalls += 1
                return true
            }
        )

        #expect(syncCalls == 1)
        #expect(outcome == .saved)
        #expect(outcome.isSaved)
        #expect(outcome.notice == nil)
    }

    /// A refused calendar write is a different situation from a lost note, and says so: the
    /// user's writing is safe, only the mirror is missing.
    @Test func aRefusedCalendarWriteIsReportedWithoutClaimingTheNoteWasLost() {
        var syncCalls = 0

        let outcome = CadenceEventNoteSupport.commitNote(
            syncToCalendar: true,
            save: {},
            syncToNativeEvent: {
                syncCalls += 1
                return false
            }
        )

        #expect(syncCalls == 1)
        #expect(outcome == .savedButNotSynced)
        #expect(outcome.isSaved)
        #expect(outcome.notice != nil)
        #expect(outcome.notice != CadenceEventNoteCommitOutcome.notSaved("disk full").notice)
    }

    /// The editor's on-appear metadata write is Cadence's own bookkeeping and must not push
    /// anything outward.
    @Test func aCommitThatDidNotAskForASyncDoesNotTouchTheCalendarOrComplain() {
        var syncCalls = 0

        let outcome = CadenceEventNoteSupport.commitNote(
            syncToCalendar: false,
            save: {},
            syncToNativeEvent: {
                syncCalls += 1
                return false
            }
        )

        #expect(syncCalls == 0)
        #expect(outcome == .savedWithoutSync)
        #expect(outcome.isSaved)
        #expect(outcome.notice == nil)
    }

    /// A save that throws is reported by its own message, so the notice cannot be a fixed string
    /// that happens to fit one failure.
    @Test func theFailedCommitCarriesTheErrorItActuallyGot() {
        let outcome = CadenceEventNoteSupport.commitNote(
            syncToCalendar: true,
            save: { throw NSError(domain: "CadenceTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "iCloud rejected the write"]) },
            syncToNativeEvent: { true }
        )

        #expect(outcome == .notSaved("iCloud rejected the write"))
        #expect(outcome != .notSaved("disk full"))
    }

    @Test func theEventNoteEditorCommitsThroughTheOrderedHelperAndNotATryQuestionMark() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSEventNoteEditorSheet.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.count == raw.count, "the stripper must blank, never shorten")
        #expect(code != raw, "expected comments to have been blanked")

        let persist = try #require(CadenceSourceScan.functionBody(named: "persistNote", in: code))
        #expect(persist.contains("CadenceEventNoteSupport.commitNote("))
        #expect(persist.contains("syncToNativeEvent: syncNoteToNativeEvent"))
        // The sheet must not keep a second, unordered way to commit beside the helper.
        #expect(!code.contains("try? modelContext.save()"))
        // Done may not close over a commit that did not land.
        #expect(code.contains("guard persistNote().isSaved else { return }"))
    }

    /// The native write has to be able to answer, or ordering the save first buys nothing: the
    /// sheet would still be guessing at the second half.
    ///
    /// The answer was `Bool` until T-339 and is a `CalendarWriteFailure?` now; `nil` is the value
    /// a completed write returns, so the editor narrows it with `== nil` at the one place that
    /// needs a yes/no — the same narrowing `EventNoteSupport.syncNativeCalendarNotes` does on the
    /// desktop.
    @Test func theIOSNoteSyncReportsWhetherAppleCalendarTookIt() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarManager.swift")
        )

        #expect(code.contains("func updateEventNotes(_ event: EKEvent, notes: String) -> CalendarWriteFailure?"))
        #expect(code.contains("func updateEventNotes(calendarEventID: String, notes: String) -> CalendarWriteFailure?"))

        let sheet = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSEventNoteEditorSheet.swift")
        )
        let sync = try #require(CadenceSourceScan.functionBody(named: "syncNoteToNativeEvent", in: sheet))
        #expect(
            CadenceSourceScan.matchCount(#"updateEventNotes\([^\n]*\) == nil"#, in: sync) == 2,
            "the editor stopped narrowing both note writes to an answer"
        )
    }

    // MARK: - T-389: the desktop reports the same miss iOS does

    /// The stale-id case, on the manager macOS actually calls.
    ///
    /// `updateEventNotes(calendarEventID:)` looks the id up and, when nothing comes back, used to
    /// `return nil` — which in this API is the *success* value, the same thing a completed write
    /// returns. So a note whose `calendarEventID` no longer resolves reported that Apple Calendar
    /// had taken the change. iOS's overload has always answered `false` here for exactly this
    /// reason ("an identifier that resolves to nothing is a sync that did not happen").
    #if os(macOS)
    @Test func aStoredEventIdThatResolvesToNothingIsAFailureAndNotASilentSuccess() {
        // Nothing here forces `isAuthorized`, deliberately. A fabricated identifier resolves to
        // nothing on an unauthorized machine *and* on an authorized one, so the test needs no
        // seam — and `CalendarManagerScenarioTests` already toggles this singleton, which is not
        // state two suites should be writing at once.
        let manager = CalendarManager.shared

        #expect(manager.event(withIdentifier: "cadence-tests-no-such-event") == nil)
        let result = manager.updateEventNotes(calendarEventID: "cadence-tests-no-such-event", notes: "Body")
        #expect(result != nil, "an unresolvable id reported success")
        #expect(result == .eventNotFound)
    }

    /// The desktop mirror helper has to be able to answer, or `commitNote`'s second half is a
    /// guess. This is the macOS counterpart of `theIOSNoteSyncReportsWhetherAppleCalendarTookIt`,
    /// except that `EventNoteSupport` is compiled into this target, so it is checked by running it
    /// rather than by reading it.
    @Test func theMacNoteSyncReportsWhetherAppleCalendarTookIt() {
        let manager = CalendarManager.shared

        let stale = Note(kind: .meeting, title: "Standup", calendarEventID: "cadence-tests-no-such-event")
        #expect(EventNoteSupport.syncNativeCalendarNotes(for: stale, content: "Body", calendarManager: manager) == false)

        // A note with nothing to mirror into has nothing that can fail, so it is not a miss —
        // otherwise every ordinary note would wear the "not synced" notice.
        let notAnEventNote = Note(kind: .permanent, title: "Notepad")
        #expect(EventNoteSupport.syncNativeCalendarNotes(for: notAnEventNote, content: "Body", calendarManager: manager) == true)
        let meetingWithoutAnEvent = Note(kind: .meeting, title: "Orphan")
        #expect(EventNoteSupport.syncNativeCalendarNotes(for: meetingWithoutAnEvent, content: "Body", calendarManager: manager) == true)
    }
    #endif

    /// Both macOS editors of an event note must go through the shared outcome helper and show its
    /// notice. Views cannot be driven from a unit test, so the wiring is pinned by reading it —
    /// positively, and comment-stripped.
    ///
    /// `NotesView`'s Event Notes tab is here because it is the same defect one surface further on:
    /// it edited meeting notes through a bare `NoteEditorPane` with no `onPersistContent` at all,
    /// so that editor never reached Apple Calendar under any circumstances.
    @Test func bothMacEventNoteEditorsCommitThroughTheSharedOutcomeHelper() throws {
        for path in [
            "Cadence/macOS/Views/EventNoteSupportViews.swift",
            "Cadence/macOS/Views/NotesView.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.strippingComments(raw)
            #expect(code.count == raw.count, "the stripper must blank, never shorten")

            #expect(code.contains("CadenceEventNoteSupport.commitNote("), "\(path) does not commit through the helper")
            #expect(code.contains("commitNotice = "), "\(path) never stores the outcome notice")
            #expect(code.contains("EventNoteCommitNoticeBanner("), "\(path) never shows the outcome notice")
        }

        // The mirror helper must hand its answer back, and must not let a caller drop it — the
        // whole of T-389 was one discarded return value.
        let support = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/EventNoteSupportViews.swift")
        )
        #expect(support.contains("static func syncNativeCalendarNotes(for note: Note, content: String, calendarManager: CalendarManager) -> Bool"))
        #expect(CadenceSourceScan.matchCount("@discardableResult\\s+static func syncNativeCalendarNotes", in: support) == 0)
    }

    // MARK: - T-390: a list's calendar link is the identifier and nothing else

    /// The decision recorded for T-390: `linkedCalendarID` is an opaque, permanent EventKit
    /// identifier, stored alone, and a link whose calendar was deleted and recreated stays visibly
    /// dead rather than being re-matched.
    ///
    /// This is the half a test can hold on to. Storing a title and source beside the id is the
    /// other branch of that decision and is **not** taken: it is a stored-property change to two
    /// `@Model` types and this project has no `SchemaMigrationPlan`. So the contract is that the id
    /// is the whole link, and this fails the moment someone adds companion metadata without doing
    /// the migration work first.
    @Test func aListsCalendarLinkStoresTheIdentifierAndNoCompanionMetadata() throws {
        for path in ["Cadence/Models/Area.swift", "Cadence/Models/Project.swift"] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.strippingComments(raw)

            #expect(code.contains("var linkedCalendarID: String = \"\""), "\(path) no longer stores the link as a bare id")
            #expect(
                CadenceSourceScan.matchCount("var +linkedCalendar[A-Za-z]*", in: code) == 1,
                "\(path) grew a second linkedCalendar* stored property; that needs a SchemaMigrationPlan"
            )
            // The assumption has to be written down where a model edit will meet it, not merely
            // be true. Comments are read from the raw source here, deliberately.
            #expect(raw.contains("T-390"), "\(path) does not state the calendar-link contract")
        }
    }

    /// The behavioural half: a calendar that Apple Calendar deleted and recreated comes back under
    /// a new identifier, and the old link must not quietly adopt it.
    ///
    /// Event-note lookup has a date/title fallback for events whose *event* id churned, and that
    /// fallback is the one place a recreated calendar could leak in. It requires an exact
    /// `calendarID` match, so it does not. Auto-matching by title without a conflict UI is worse
    /// than a visibly broken link, and this is what keeps it out.
    @Test func aRecreatedCalendarNeverAdoptsTheOldLinksNotes() {
        let note = Note(
            kind: .meeting,
            title: "Weekly Sync",
            calendarEventID: "event-1",
            calendarID: "calendar-before",
            eventDateKey: "2026-06-01",
            eventStartMin: 540,
            eventEndMin: 600
        )

        // Same event, same day, same minutes, same title — only the calendar identifier moved.
        #expect(
            CadenceEventNoteSupport.note(
                for: "event-2",
                eventTitle: "Weekly Sync",
                calendarID: "calendar-after",
                eventDateKey: "2026-06-01",
                eventStartMin: 540,
                eventEndMin: 600,
                in: [note]
            ) == nil
        )
        // The identical call under the stored id still resolves, so the guard above is the
        // calendar identifier and not the fallback being broken outright.
        #expect(
            CadenceEventNoteSupport.note(
                for: "event-2",
                eventTitle: "Weekly Sync",
                calendarID: "calendar-before",
                eventDateKey: "2026-06-01",
                eventStartMin: 540,
                eventEndMin: 600,
                in: [note]
            ) === note
        )

        // The list-scoped read is the same exact-id rule: a dead link shows nothing rather than
        // showing someone else's notes.
        #expect(CadenceEventNoteSupport.meetingNotes(forLinkedCalendarID: "calendar-after", in: [note]).isEmpty)
        #expect(CadenceEventNoteSupport.meetingNotes(forLinkedCalendarID: "", in: [note]).isEmpty)
        #expect(CadenceEventNoteSupport.meetingNotes(forLinkedCalendarID: "calendar-before", in: [note]).count == 1)
    }

    // MARK: - T-339: one EventKit failure vocabulary, on both platforms

    /// The typed failure used to be declared inside `CalendarManager.swift`, which is one big
    /// `#if os(macOS)` — so the only platform that could name a cause was the one that already
    /// had a shared alert to show it in. iOS answered `Bool` and reached for T-324's one-sentence
    /// notices, which exist precisely because a `Bool` cannot say *why*.
    ///
    /// Moving the enum is the whole of the port: it is a bare value type over `String`s with no
    /// EventKit in it, so nothing about it was ever desktop-only.
    @Test func theTypedCalendarWriteFailureIsDeclaredOnceInSharedCode() throws {
        let rawShared = try CadenceSourceScan.sourceFile("Cadence/Shared/CalendarWriteFailure.swift")
        let shared = CadenceSourceScan.strippingComments(rawShared)
        #expect(rawShared.count > 800, "the shared file read as \(rawShared.count) characters")
        #expect(shared != rawShared, "expected comments to have been blanked")
        #expect(shared.count == rawShared.count, "the stripper changed the length")

        // `nonisolated` for the reason `NonisolatedValueTypeTests` records: without it the
        // synthesized `Equatable` is main-actor isolated and every `#expect(a == b)` warns.
        #expect(shared.contains("nonisolated enum CalendarWriteFailure: Equatable"))
        for cause in [
            "case notAuthorized",
            "case noWritableCalendar",
            "case invalidRange",
            "case eventNotFound",
            "case saveFailed(String)"
        ] {
            #expect(shared.contains(cause), "the shared failure lost \(cause)")
        }
        #expect(
            CadenceSourceScan.matchCount(#"#if os\(macOS\)"#, in: shared) == 0,
            "the shared failure is still fenced to one platform"
        )

        // And it is declared *once*: the desktop manager returns it but no longer owns it.
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Services/CalendarManager.swift")
        )
        #expect(mac.contains("-> CalendarWriteFailure?"), "the desktop manager stopped returning the typed failure")
        #expect(
            CadenceSourceScan.matchCount("enum CalendarWriteFailure", in: mac) == 0,
            "the desktop manager still declares its own copy"
        )
    }

    /// Every write on the iOS manager answers with a cause. `Bool` survives only on the two
    /// members that are genuinely yes/no questions — `requestAccess()` and `canModify(_:)`.
    @Test func theIOSCalendarWritesAnswerWithTheTypedFailureRatherThanABool() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarManager.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(raw.count > 1_000, "iOSCalendarManager.swift read as \(raw.count) characters")
        #expect(code != raw, "expected comments to have been blanked")
        #expect(code.count == raw.count, "the stripper changed the length")

        // Five writes: create, update, delete, and the two note overloads.
        #expect(
            CadenceSourceScan.matchCount(#"\) -> CalendarWriteFailure\? \{"#, in: code) == 5,
            "not every iOS calendar write returns the typed failure"
        )
        #expect(
            code.contains("func requestAccess() async -> Bool"),
            "the authorization question should still be a Bool"
        )
        #expect(
            code.contains("func canModify(_ event: EKEvent) -> Bool"),
            "the editability question should still be a Bool"
        )

        // The causes are named, not collapsed. `eventNotFound` is the one the old comment
        // described in prose ("a sync that did not happen, not a no-op") and could not return.
        for cause in [
            "return .notAuthorized",
            "return .noWritableCalendar",
            "return .invalidRange",
            "return .eventNotFound",
            "return .saveFailed(error.localizedDescription)"
        ] {
            #expect(code.contains(cause), "the iOS manager never returns \(cause)")
        }
    }

    /// Both iOS event sheets show the cause, through the shared notices rather than a third
    /// wording of their own.
    @Test func bothIOSEventSheetsNameTheCauseOfARejectedWrite() throws {
        for path in [
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.strippingComments(raw)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters")
            #expect(code != raw, "\(path): expected comments to have been blanked")

            #expect(
                code.contains("CadenceCalendarEventEditingSupport.saveFailureNotice(for:"),
                "\(path) still shows a causeless save-failure notice"
            )
            #expect(
                CadenceSourceScan.matchCount(#""Couldn.t save this event"#, in: code) == 0,
                "\(path) spells the save-failure notice itself"
            )
        }

        let editSheet = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        )
        #expect(
            editSheet.contains("CadenceCalendarEventEditingSupport.deleteFailureNotice(for:"),
            "the edit sheet still shows a causeless delete-failure notice"
        )
    }

    /// Behavioural, not a scan: the notice a sheet shows for each cause, run directly.
    ///
    /// The lead sentence names the operation and the rest is `CalendarWriteFailure.message` — the
    /// same string the desktop alert has shown since the type existed, which is what "the same
    /// cause-aware notice" means. `nil` keeps T-324's one sentence, for the caller that failed
    /// before EventKit was asked.
    @Test func theCauseAwareEventNoticeAddsTheCauseToTheOperationSentence() {
        let causes: [CalendarWriteFailure] = [
            .notAuthorized,
            .noWritableCalendar,
            .invalidRange,
            .eventNotFound,
            .saveFailed("iCloud rejected the write")
        ]

        for cause in causes {
            let save = CadenceCalendarEventEditingSupport.saveFailureNotice(for: cause)
            let delete = CadenceCalendarEventEditingSupport.deleteFailureNotice(for: cause)

            #expect(save.hasPrefix(CadenceCalendarEventEditingSupport.saveFailureNotice))
            #expect(delete.hasPrefix(CadenceCalendarEventEditingSupport.deleteFailureNotice))
            #expect(save.contains(cause.message), "the save notice drops the cause for \(cause)")
            #expect(delete.contains(cause.message), "the delete notice drops the cause for \(cause)")
            // The whole point: it says more than the causeless sentence did.
            #expect(save != CadenceCalendarEventEditingSupport.saveFailureNotice)
            #expect(save != delete)
        }

        // Five causes, five distinct sentences — a `message` that collapsed two of them would
        // leave the sheet no better off than the `Bool` it replaced.
        #expect(Set(causes.map { CadenceCalendarEventEditingSupport.saveFailureNotice(for: $0) }).count == 5)
        #expect(
            CadenceCalendarEventEditingSupport.saveFailureNotice(for: .saveFailed("iCloud rejected the write"))
                .contains("iCloud rejected the write"),
            "the EventKit error text is the only new information a save failure carries"
        )

        // No cause to name is still a sentence, and it is T-324's.
        #expect(
            CadenceCalendarEventEditingSupport.saveFailureNotice(for: nil)
                == CadenceCalendarEventEditingSupport.saveFailureNotice
        )
        #expect(
            CadenceCalendarEventEditingSupport.deleteFailureNotice(for: nil)
                == CadenceCalendarEventEditingSupport.deleteFailureNotice
        )
    }

    // MARK: - T-658: a refused macOS write keeps the draft

    /// Behavioural: the rule both platforms now read, run directly.
    ///
    /// The claim is not "there is a sentence" — `saveFailureNotice(for:)` already had that — it is
    /// that a refusal and a success are *different decisions about the editor*. A committed write
    /// closes it and says nothing; a refused one keeps it open and says why. macOS made the same
    /// decision either way, which is how the draft went missing.
    @Test func aRefusedCalendarWriteKeepsTheEditorOpenAndACommittedOneClosesIt() {
        #expect(CadenceCalendarEventEditingSupport.saveOutcome(for: nil) == .committed)
        #expect(CadenceCalendarEventEditingSupport.saveOutcome(for: nil).closesEditor)
        #expect(CadenceCalendarEventEditingSupport.saveOutcome(for: nil).failureNotice == nil)

        let causes: [CalendarWriteFailure] = [
            .notAuthorized,
            .noWritableCalendar,
            .invalidRange,
            .eventNotFound,
            .saveFailed("iCloud rejected the write")
        ]
        for cause in causes {
            let save = CadenceCalendarEventEditingSupport.saveOutcome(for: cause)

            // The editor stays put. This is the half T-658 was about: everything the user typed
            // lives in the editor's own state, so closing it is what loses the draft.
            #expect(save.closesEditor == false, "a refused save still closes the editor for \(cause)")
            #expect(save != .committed)

            // And it says which operation failed, and why — the iOS wording, not a third one.
            #expect(save == .refused(notice: CadenceCalendarEventEditingSupport.saveFailureNotice(for: cause)))
            #expect(save.failureNotice?.hasPrefix(CadenceCalendarEventEditingSupport.saveFailureNotice) == true)
            #expect(save.failureNotice?.contains(cause.message) == true)
            #expect(
                save.failureNotice != CadenceCalendarEventEditingSupport.deleteFailureNotice(for: cause),
                "the save outcome is showing the delete sentence"
            )
        }

        // A refusal with no cause to name is still a refusal. This is the branch the two macOS
        // event editors reach when the edited time range cannot be formed at all: EventKit was
        // never asked, so there is nothing to quote, but the popover must not close on it.
        let uncaused = CadenceCalendarWriteOutcome.refused(
            notice: CadenceCalendarEventEditingSupport.saveFailureNotice(for: nil)
        )
        #expect(uncaused.closesEditor == false)
        #expect(uncaused.failureNotice == CadenceCalendarEventEditingSupport.saveFailureNotice)
    }

    /// The macOS event editor now has somewhere to put that notice, and the host owns it.
    @Test func theMacOSEventEditPopoverDrawsTheHostsFailureNotice() throws {
        let path = "Cadence/macOS/Views/TimelineEventBlockSupportViews.swift"
        let raw = try CadenceSourceScan.sourceFile(path)
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters")
        #expect(code != raw, "expected comments and literals to have been blanked")
        #expect(code.count == raw.count, "the stripper changed the length")

        #expect(
            CadenceSourceScan.matchCount(#"@Binding var actionFailureNotice: String\?"#, in: code) == 1,
            "CalendarEventEditPopover does not take the host's failure notice"
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceInlineFailureNotice\(text: actionFailureNotice\)"#, in: code) == 1,
            "CalendarEventEditPopover never draws the host's failure notice"
        )
    }

    /// Every macOS calendar write that is made from a surface holding a draft reports its outcome
    /// instead of discarding it.
    ///
    /// Exact counts, and each occurrence is named below, because the population is small and
    /// fixed: two in the board card and two in the timeline block — the save, plus the branch
    /// where the edited range cannot be formed at all — and one in the day canvas for quick-create.
    /// A floor would let any one of the five drift back.
    ///
    /// The two deletes are deliberately absent. They leave through `DeleteConfirmationManager`'s
    /// full-window overlay, which closes the transient popover on the way, so there is nothing left
    /// to draw an inline notice on; they keep the global alert, which already names the cause.
    @Test func everyMacOSCalendarDraftSurfaceReportsItsWriteOutcome() throws {
        let expected: [(path: String, reports: Int, outcomes: [String], closes: String, closeCount: Int)] = [
            (
                "Cadence/macOS/Views/CalendarBoardItemSupportViews.swift",
                2,
                ["CadenceCalendarEventEditingSupport.saveOutcome(for: failure)"],
                #"\) \{ showPopover = false \}"#,
                1
            ),
            (
                "Cadence/macOS/Views/TimelineEventBlock.swift",
                2,
                ["CadenceCalendarEventEditingSupport.saveOutcome(for: failure)"],
                #"\) \{ selectedEventID = nil \}"#,
                1
            ),
            (
                "Cadence/macOS/Views/TimelineDayCanvas.swift",
                1,
                ["CadenceCalendarEventEditingSupport.saveOutcome(for: failure)"],
                #"\) \{ finishDraftCreation\(\) \}"#,
                1
            )
        ]

        for (path, reports, outcomes, closes, closeCount) in expected {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.codeOnly(raw)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters")
            #expect(code != raw, "\(path): expected comments and literals to have been blanked")
            #expect(code.count == raw.count, "\(path): the stripper changed the length")

            #expect(
                CadenceSourceScan.matchCount(#"calendarManager\.report\("#, in: code) == reports,
                "\(path) does not report exactly \(reports) calendar write outcomes"
            )
            for outcome in outcomes {
                #expect(code.contains(outcome), "\(path) never builds \(outcome)")
            }
            // The closing lines that used to run unconditionally now sit in `report`'s committed
            // branch. The needle keeps the `)` that closes the `report(…)` call, so a copy that
            // drifted back out to the top of the closure would not match — and the count is exact
            // rather than a floor, because the point is that *neither* of a pair is left outside.
            #expect(
                CadenceSourceScan.matchCount(closes, in: code) == closeCount,
                "\(path) does not close its editor exactly \(closeCount) times, all inside a committed outcome"
            )
        }

        // And the notice each of them writes into is drawn.
        for (path, needle) in [
            ("Cadence/macOS/Views/CalendarBoardItemSupportViews.swift", "actionFailureNotice: $actionFailureNotice"),
            ("Cadence/macOS/Views/TimelineEventBlock.swift", "actionFailureNotice: $actionFailureNotice"),
            ("Cadence/macOS/Views/TimelineDayCanvas.swift", "createFailureNotice: $eventCreateFailureNotice")
        ] {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains(needle), "\(path) never hands its editor the notice it writes")
        }
    }

    /// The quick-create callback carries the typed failure from the manager down to the canvas
    /// that owns the draft popover. Both declarations on that path used to narrow it to `Void`, so
    /// `createStandaloneEvent`'s answer was gone before anything could act on it.
    ///
    /// The popover's own callback stays `Void`: the canvas is the frame that dismisses it, so the
    /// canvas is where the decision belongs, and the popover reads the answer back as a binding.
    @Test func theMacOSQuickCreateEventCallbackKeepsTheTypedFailure() throws {
        for (path, needle) in [
            ("Cadence/macOS/Views/TimelineDayCanvas.swift",
             "var onCreateEvent: ((String, Int, Int, String, String) -> CalendarWriteFailure?)? = nil"),
            ("Cadence/macOS/Views/SchedulePanelShellViews.swift",
             "let onCreateEvent: (String, Int, Int, String, String) -> CalendarWriteFailure?")
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.codeOnly(raw)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters")
            #expect(code.count == raw.count, "\(path): the stripper changed the length")
            #expect(code.contains(needle), "\(path) still narrows the create callback to Void")
            #expect(
                CadenceSourceScan.matchCount(#"onCreateEvent: \(\(String, Int, Int, String, String\) -> Void\)\?"#, in: code) == 0,
                "\(path) still declares a Void-returning create callback"
            )
        }

        let popover = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/QuickCreateChoicePopover.swift")
        )
        #expect(
            CadenceSourceScan.matchCount(#"@Binding var createFailureNotice: String\?"#, in: popover) == 1,
            "the quick-create popover has nowhere to show a refused event write"
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceInlineFailureNotice\(text: createFailureNotice\)"#, in: popover) == 1,
            "the quick-create popover never draws its failure notice"
        )
    }

    /// `CalendarManager.report` is the one place the inline path and the alert path are separated,
    /// and clearing `lastWriteFailure` is load-bearing rather than tidy: an alert raised over a
    /// macOS popover dismisses that popover, which is the draft loss T-658 is about.
    @Test func reportingAWriteFailureInlineTakesItOffTheGlobalAlert() throws {
        let path = "Cadence/macOS/Views/TimelineCalendarWriteFailureAlert.swift"
        let raw = try CadenceSourceScan.sourceFile(path)
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters")
        #expect(code != raw, "expected comments and literals to have been blanked")

        #expect(code.contains("func report("), "there is no single inline-reporting path")
        #expect(code.contains("notice.wrappedValue = outcome.failureNotice"))
        #expect(code.contains("if outcome.closesEditor {"))
        #expect(
            CadenceSourceScan.matchCount(#"lastWriteFailure = nil"#, in: code) == 3,
            "expected exactly three clears: the alert's binding, its OK button, and the inline handover"
        )

        // And the two event deletes stay on the alert, so neither host reports one inline.
        for path in [
            "Cadence/macOS/Views/CalendarBoardItemSupportViews.swift",
            "Cadence/macOS/Views/TimelineEventBlock.swift"
        ] {
            let host = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            #expect(
                CadenceSourceScan.matchCount(#"deleteEvent\(item\.ekEvent, scope: scope\)"#, in: host) == 1,
                "\(path) does not delete the event exactly once"
            )
            #expect(
                CadenceSourceScan.matchCount(#"deleteOutcome"#, in: host) == 0,
                "\(path) reports a delete inline, on a popover the confirmation overlay has closed"
            )
        }
    }

    // MARK: - Non-vacuity

    /// Every source-reading test above passes trivially if the read returns nothing, so prove the
    /// reads are real and that a needle which must not be there can in fact be detected.
    @Test func theSourceReadingHelpersActuallyReadTheseFiles() throws {
        for path in [
            "Cadence/iOS/iOSCalendarManager.swift",
            "Cadence/iOS/iOSEventNoteEditorSheet.swift",
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift",
            "Cadence/macOS/Services/CalendarManager.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters")
            #expect(raw.contains("import EventKit") || raw.contains("import SwiftUI"), "\(path) does not look like the file it claims to be")
        }

        // The stripper blanks rather than deletes, and it really does blank.
        let sample = "let a = 1 // not code\n/* also not code */let b = 2\n"
        let stripped = CadenceSourceScan.strippingComments(sample)
        #expect(stripped.count == sample.count)
        #expect(stripped.contains("let a = 1"))
        #expect(stripped.contains("let b = 2"))
        #expect(!stripped.contains("not code"))
    }
}
