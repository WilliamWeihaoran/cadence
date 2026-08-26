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
    @Test func theIOSNoteSyncReportsWhetherAppleCalendarTookIt() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarManager.swift")
        )

        #expect(code.contains("func updateEventNotes(_ event: EKEvent, notes: String) -> Bool"))
        #expect(code.contains("func updateEventNotes(calendarEventID: String, notes: String) -> Bool"))
    }

    // MARK: - Non-vacuity

    /// Every source-reading test above passes trivially if the read returns nothing, so prove the
    /// reads are real and that a needle which must not be there can in fact be detected.
    @Test func theSourceReadingHelpersActuallyReadTheseFiles() throws {
        for path in [
            "Cadence/iOS/iOSCalendarManager.swift",
            "Cadence/iOS/iOSEventNoteEditorSheet.swift",
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
