import Foundation
import Testing
@testable import Cadence

/// What CloudKit mirroring has actually done — the half of "is iCloud working" the app could not
/// answer at all before [[T-2000]].
///
/// **Why the reader is tested and the stream is not.** A mirroring event cannot be produced on
/// demand: `NSPersistentCloudKitContainer` posts one when it has decided to mirror, and there is
/// no public call that makes one happen. There is also no reaching for the owner's real container
/// or app group to watch a real one, which is an absolute rule here. So the event stream is a
/// protocol with a one-line live implementation and no logic in it, and everything with a decision
/// in it — which pass is "the last import", whether a failure is still current, what an empty
/// history reads as — is a pure fold these tests drive directly.
///
/// **The trap these are written against.** An empty history is the state most likely to be
/// vacuously green: "nothing has happened" and "everything succeeded" are both the absence of a
/// failure, and a reader that renders them the same reports the defect as its own absence. The
/// first two tests below are that pair, asserted as two readings that must DIFFER rather than as
/// one reading that must look right.
@MainActor
struct CadenceSyncActivityTests {

    // MARK: - Fixtures

    private func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        return calendar
    }

    /// 2026-10-02 at `hour`:`minute` UTC.
    private func moment(_ hour: Int, _ minute: Int, day: Int = 2) throws -> Date {
        let calendar = try calendar()
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = day
        components.hour = hour
        components.minute = minute
        return try #require(calendar.date(from: components))
    }

    private func finished(
        _ phase: CadenceSyncActivityPhase,
        endingAt end: Date,
        succeeded: Bool = true,
        error: String? = nil,
        identifier: UUID = UUID()
    ) -> CadenceSyncActivityEvent {
        CadenceSyncActivityEvent(
            identifier: identifier,
            phase: phase,
            startDate: end.addingTimeInterval(-2),
            endDate: end,
            succeeded: succeeded,
            errorDescription: error
        )
    }

    private func began(
        _ phase: CadenceSyncActivityPhase,
        at start: Date,
        identifier: UUID = UUID()
    ) -> CadenceSyncActivityEvent {
        CadenceSyncActivityEvent(identifier: identifier, phase: phase, startDate: start)
    }

    private let english = Locale(identifier: "en_US")

    // MARK: - "Nothing has happened" is not "everything succeeded"

    /// The empty reading, stated in full. Every clause here is one of the ways a status surface
    /// quietly turns silence into reassurance.
    @Test func anEmptyMirroringHistoryReadsAsNoNewsRatherThanAsGoodNews() throws {
        let now = try moment(15, 45)
        let summary = CadenceSyncActivitySummary.empty
        let line = summary.statusLine(now: now, calendar: try calendar(), locale: english)

        #expect(summary.hasHistory == false)
        #expect(summary.observedEventCount == 0)

        // Not green. A device that has never imported anything is not a device that is fine.
        #expect(summary.tone != .positive)
        #expect(summary.tone == .neutral)

        // And the sentence says nothing about errors, because there having been none is true and
        // completely beside the point.
        #expect(!line.contains("No errors"))
        #expect(!line.contains("Last import"))
        #expect(!line.contains("Last export"))
        #expect(!line.contains("·"))
        #expect(line.contains("has not seen"))
        #expect(summary.headline == "No sync activity yet")
    }

    /// The control for the test above, and the half that makes it mean something: a history that
    /// *did* happen and *did* succeed must read differently in every one of those four places.
    /// Without this pair, a reader that always returned the empty copy would be green.
    @Test func aHealthyMirroringHistoryRendersNothingTheEmptyOneDoes() throws {
        let now = try moment(15, 45)
        let healthy = CadenceSyncActivitySummary.summarize([
            finished(.import, endingAt: try moment(15, 25)),
            finished(.export, endingAt: try moment(15, 45))
        ])
        let empty = CadenceSyncActivitySummary.empty

        let healthyLine = healthy.statusLine(now: now, calendar: try calendar(), locale: english)
        let emptyLine = empty.statusLine(now: now, calendar: try calendar(), locale: english)

        #expect(healthyLine != emptyLine)
        #expect(healthy.headline != empty.headline)
        #expect(healthy.tone != empty.tone)
        #expect(healthy.iconName != empty.iconName)

        // And it is the line the ticket asked for, spelled out.
        #expect(healthyLine == "Last import 3:25 PM · Last export 3:45 PM · No errors")
        #expect(healthy.tone == .positive)
    }

    /// The narrower version of the same trap: a history holding only a successful *setup* has
    /// happened, but no data has moved. It must not read as "no import yet, no export yet, all
    /// good" in the same breath it reads as an empty one — and it must not read as the empty one
    /// either, because something did happen.
    @Test func aSetupOnlyHistoryIsNeitherEmptyNorAFullAnswer() throws {
        let now = try moment(15, 45)
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.setup, endingAt: try moment(15, 0))
        ])
        let calendar = try calendar()
        let line = summary.statusLine(now: now, calendar: calendar, locale: english)
        let emptyLine = CadenceSyncActivitySummary.empty.statusLine(now: now, calendar: calendar, locale: english)

        #expect(summary.hasHistory)
        #expect(line != emptyLine)
        #expect(line == "No import yet · No export yet · No errors")
        #expect(summary.lastSuccess(.import) == nil)
        #expect(summary.lastSuccess(.export) == nil)
        #expect(summary.lastSuccess(.setup) != nil)
    }

    // MARK: - Import and export are two answers, not one

    /// The two directions are reported separately, and the test is that swapping which one
    /// happened when changes the line. A reader collapsing them into a single "last synced" would
    /// pass an assertion that only checked both timestamps appeared somewhere.
    @Test func theLatestImportAndTheLatestExportAreReportedAsSeparateFacts() throws {
        let now = try moment(16, 0)
        let early = try moment(15, 25)
        let late = try moment(15, 45)

        let importFirst = CadenceSyncActivitySummary.summarize([
            finished(.import, endingAt: early),
            finished(.export, endingAt: late)
        ])
        let exportFirst = CadenceSyncActivitySummary.summarize([
            finished(.export, endingAt: early),
            finished(.import, endingAt: late)
        ])

        #expect(importFirst.lastSuccess(.import) == early)
        #expect(importFirst.lastSuccess(.export) == late)
        #expect(exportFirst.lastSuccess(.import) == late)
        #expect(exportFirst.lastSuccess(.export) == early)

        let a = importFirst.statusLine(now: now, calendar: try calendar(), locale: english)
        let b = exportFirst.statusLine(now: now, calendar: try calendar(), locale: english)
        #expect(a != b, "the two directions render identically: \(a)")
    }

    /// One direction working while the other has never run is the owner's own case — the Mac
    /// exported past 19:45 while the phone had not imported since 19:25 — so the half with no
    /// history must say so rather than borrowing the other half's timestamp.
    @Test func aDirectionThatHasNeverSucceededSaysSoRatherThanBorrowingTheOther() throws {
        let now = try moment(16, 0)
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.export, endingAt: try moment(15, 45))
        ])
        let line = summary.statusLine(now: now, calendar: try calendar(), locale: english)

        #expect(line == "No import yet · Last export 3:45 PM · No errors")
        #expect(summary.lastSuccess(.import) == nil)
    }

    /// `lastSuccess` is the last pass that **worked**, not the last pass that ran. A failed import
    /// did not bring anything down, so stamping the line with its end time would be a wrong
    /// reading rather than a stale one.
    @Test func aFailedPassIsNotTheLastSuccessfulOne() throws {
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.import, endingAt: try moment(15, 0)),
            finished(.import, endingAt: try moment(15, 25), succeeded: false, error: "BAD_REQUEST")
        ])

        #expect(summary.lastSuccess(.import) == (try moment(15, 0)))
        #expect(summary.failure(.import) == "BAD_REQUEST")
    }

    // MARK: - A failure is surfaced, not swallowed

    @Test func aFailedPassSurfacesItsOwnErrorInTheLine() throws {
        let now = try moment(16, 0)
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.import, endingAt: try moment(15, 25)),
            finished(.export, endingAt: try moment(15, 45), succeeded: false, error: "Quota exceeded")
        ])
        let line = summary.statusLine(now: now, calendar: try calendar(), locale: english)

        #expect(summary.failure(.export) == "Quota exceeded")
        #expect(line.contains("Quota exceeded"), "the error never reached the line: \(line)")
        #expect(!line.contains("No errors"))
        #expect(summary.tone == .caution)
        #expect(summary.headline == "Export failed")
    }

    /// `Event.error` is optional, so `succeeded == false` with no error attached is a real shape —
    /// and it is the one that would let a failure fall out of the summary entirely while every
    /// "does the message appear" assertion stayed green.
    @Test func aFailureCarryingNoErrorIsStillAFailure() throws {
        let now = try moment(16, 0)
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.import, endingAt: try moment(15, 25), succeeded: false, error: nil)
        ])
        let line = summary.statusLine(now: now, calendar: try calendar(), locale: english)

        #expect(summary.failure(.import) != nil)
        #expect(summary.failingPhases == [.import])
        #expect(line.contains("Import failed"))
        #expect(!line.contains("No errors"))
        #expect(summary.tone == .caution)
    }

    /// An empty error string is not an error message, and must not render as `Import failed: `.
    @Test func anEmptyErrorStringStillGetsASentence() throws {
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.export, endingAt: try moment(15, 25), succeeded: false, error: "")
        ])
        let reason = try #require(summary.failure(.export))
        #expect(!reason.isEmpty)
    }

    /// A setup failure and an import failure are different news: setup failing means the other two
    /// phases never ran at all. They must not render as the same sentence.
    @Test func aSetupFailureIsDistinguishableFromAnImportFailure() throws {
        let now = try moment(16, 0)
        let end = try moment(15, 25)
        let setupFailed = CadenceSyncActivitySummary.summarize([
            finished(.setup, endingAt: end, succeeded: false, error: "schema mismatch")
        ])
        let importFailed = CadenceSyncActivitySummary.summarize([
            finished(.import, endingAt: end, succeeded: false, error: "schema mismatch")
        ])

        #expect(setupFailed.failure(.setup) != nil)
        #expect(setupFailed.failure(.import) == nil)
        #expect(importFailed.failure(.import) != nil)
        #expect(importFailed.failure(.setup) == nil)

        #expect(setupFailed.headline == "Setup failed")
        #expect(importFailed.headline == "Import failed")

        let setupLine = setupFailed.statusLine(now: now, calendar: try calendar(), locale: english)
        let importLine = importFailed.statusLine(now: now, calendar: try calendar(), locale: english)
        #expect(setupLine != importLine, "both failures render as \(setupLine)")
        #expect(setupLine.contains("Setup failed: schema mismatch"))
        #expect(importLine.contains("Import failed: schema mismatch"))
    }

    /// Both failing at once is a third sentence, not either of the two above.
    @Test func twoFailingPhasesAreBothNamedAndInAStableOrder() throws {
        let now = try moment(16, 0)
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.export, endingAt: try moment(15, 30), succeeded: false, error: "export boom"),
            finished(.import, endingAt: try moment(15, 25), succeeded: false, error: "import boom")
        ])
        let line = summary.statusLine(now: now, calendar: try calendar(), locale: english)

        #expect(summary.failingPhases == [.import, .export])
        #expect(line.contains("Import failed: import boom"))
        #expect(line.contains("Export failed: export boom"))
        #expect(summary.headline == "iCloud sync is failing")
    }

    // MARK: - A failure is current, or it is history

    /// The owner's one real error in a week of logs was a 105 ms `BAD_REQUEST` on `_pcs_data`
    /// surrounded by successful operations in the same second. A card that stays amber for the
    /// rest of the launch over that is a card the owner learns to ignore.
    @Test func aLaterSuccessInTheSamePhaseRetiresTheFailure() throws {
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.export, endingAt: try moment(15, 25), succeeded: false, error: "BAD_REQUEST"),
            finished(.export, endingAt: try moment(15, 26))
        ])

        #expect(summary.failure(.export) == nil)
        #expect(summary.failingPhases.isEmpty)
        #expect(summary.tone == .positive)
    }

    /// And the control that makes the rule above a rule rather than a leak: a success in a
    /// *different* phase clears nothing. An export failing while imports keep succeeding is
    /// exactly the asymmetry this surface exists to show.
    @Test func aSuccessInAnotherPhaseDoesNotRetireAFailure() throws {
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.export, endingAt: try moment(15, 25), succeeded: false, error: "BAD_REQUEST"),
            finished(.import, endingAt: try moment(15, 40))
        ])

        #expect(summary.failure(.export) == "BAD_REQUEST")
        #expect(summary.failingPhases == [.export])
        #expect(summary.tone == .caution)
        #expect(summary.lastSuccess(.import) == (try moment(15, 40)))
    }

    /// Notifications are not ordered by anything this app controls, so a late-delivered older
    /// event must not overwrite a newer answer.
    @Test func anOlderEventDeliveredLateCannotOverwriteANewerAnswer() throws {
        let newest = try moment(15, 45)
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.import, endingAt: newest),
            finished(.import, endingAt: try moment(15, 0), succeeded: false, error: "stale failure")
        ])

        #expect(summary.lastSuccess(.import) == newest)
        #expect(summary.failure(.import) == nil, "an older failure overwrote a newer success")
    }

    // MARK: - A pass in flight is neither a success nor a failure

    /// CloudKit posts each pass twice and the first half carries `succeeded == false` with no
    /// `endDate`. Reading that as a failure would paint the card amber every time a sync started.
    @Test func aPassStillRunningIsNotReportedAsAFailure() throws {
        let now = try moment(16, 0)
        let summary = CadenceSyncActivitySummary.summarize([
            began(.import, at: try moment(15, 59))
        ])
        let line = summary.statusLine(now: now, calendar: try calendar(), locale: english)

        #expect(summary.hasHistory, "a started pass is history")
        #expect(summary.failure(.import) == nil)
        #expect(summary.lastSuccess(.import) == nil)
        #expect(summary.isWorking)
        #expect(summary.phasesInProgress == [.import])
        #expect(line.contains("Syncing now"))
        #expect(!line.contains("No errors"))
        #expect(summary.tone == .info)
    }

    /// The identifier is what retires the begin-half. Without it a device that finished importing
    /// an hour ago still renders "Syncing now" forever.
    @Test func theEndHalfOfAPassRetiresItsOwnBeginHalf() throws {
        let identifier = UUID()
        let start = try moment(15, 44)
        let end = try moment(15, 45)

        let matched = CadenceSyncActivitySummary.summarize([
            began(.import, at: start, identifier: identifier),
            finished(.import, endingAt: end, identifier: identifier)
        ])
        #expect(matched.isWorking == false)
        #expect(matched.lastSuccess(.import) == end)
        #expect(matched.observedEventCount == 2, "both halves were observed")

        // The control: the same two events under two identifiers are two passes, one of which is
        // still running. If the fold ignored identifiers entirely, this and the case above would
        // agree — and they must not.
        let unmatched = CadenceSyncActivitySummary.summarize([
            began(.import, at: start, identifier: UUID()),
            finished(.import, endingAt: end, identifier: UUID())
        ])
        #expect(unmatched.isWorking, "an unfinished second pass was retired by someone else's end")
        #expect(matched.isWorking != unmatched.isWorking)
    }

    /// A phase retrying after a failure keeps the failure until the retry lands. "Something went
    /// wrong and it is trying again" is not "something went wrong and is fine".
    @Test func aRetryInFlightDoesNotClearTheFailureItIsRetrying() throws {
        let now = try moment(16, 0)
        let summary = CadenceSyncActivitySummary.summarize([
            finished(.export, endingAt: try moment(15, 25), succeeded: false, error: "BAD_REQUEST"),
            began(.export, at: try moment(15, 59))
        ])
        let line = summary.statusLine(now: now, calendar: try calendar(), locale: english)

        #expect(summary.isWorking)
        #expect(summary.failure(.export) == "BAD_REQUEST")
        #expect(line.contains("BAD_REQUEST"))
    }

    // MARK: - The stamp

    /// A bare clock time on a four-day-old reading is not a stale answer, it is a wrong one — and
    /// a stale import is the defect this ticket was filed about. `now` and `calendar` are
    /// parameters so this is arithmetic rather than the host's longitude ([[T-1115]]).
    @Test func aStampOlderThanYesterdayStopsNamingAClockTime() throws {
        let calendar = try calendar()
        let now = try moment(16, 0, day: 6)

        let today = CadenceSyncActivityStamp.string(
            for: try moment(15, 25, day: 6), now: now, calendar: calendar, locale: english
        )
        let yesterday = CadenceSyncActivityStamp.string(
            for: try moment(15, 25, day: 5), now: now, calendar: calendar, locale: english
        )
        let older = CadenceSyncActivityStamp.string(
            for: try moment(15, 25, day: 2), now: now, calendar: calendar, locale: english
        )

        #expect(today == "3:25 PM")
        #expect(yesterday == "yesterday 3:25 PM")
        #expect(older == "4 days ago")

        // All three differ, which is the claim: three readings that render alike are one reading.
        #expect(Set([today, yesterday, older]).count == 3)
    }

    /// Two different clock times on the same day render differently, so the stamp is reading the
    /// date rather than printing a constant.
    @Test func twoDifferentClockTimesOnOneDayRenderDifferently() throws {
        let calendar = try calendar()
        let now = try moment(16, 0)
        let early = CadenceSyncActivityStamp.string(for: try moment(15, 25), now: now, calendar: calendar, locale: english)
        let late = CadenceSyncActivityStamp.string(for: try moment(15, 45), now: now, calendar: calendar, locale: english)

        #expect(early != late)
        #expect(early == "3:25 PM")
        #expect(late == "3:45 PM")
    }

    /// The 24-hour clock reaches this line too — it goes through `TimeFormatters`, which is the
    /// app's one clock face ([[T-1135]]), rather than a `DateFormatter` of its own.
    @Test func theStampFollowsTheAppsOwnClockFace() throws {
        let calendar = try calendar()
        let now = try moment(16, 0)
        let twentyFourHour = CadenceSyncActivityStamp.string(
            for: try moment(15, 25),
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        #expect(twentyFourHour == "15:25")
    }

    /// A stamp from the future is clock skew between this device and CloudKit, not a date worth
    /// narrating — and it must not fall into the "N days ago" branch with a negative number.
    @Test func aStampFromTheFutureNarratesNoDay() throws {
        let calendar = try calendar()
        let stamp = CadenceSyncActivityStamp.string(
            for: try moment(15, 25, day: 4),
            now: try moment(16, 0, day: 2),
            calendar: calendar,
            locale: english
        )
        #expect(stamp == "3:25 PM")
        #expect(!stamp.contains("-"))
        #expect(!stamp.contains("ago"))
    }

    // MARK: - The injected stream

    /// The seam, end to end: the log subscribes once, folds what arrives, and starting twice does
    /// not double-count. Everything above this point is the reader; this is the only test that
    /// touches the wiring, because the wiring is the only part with no decisions in it.
    @Test func theLogFoldsWhatArrivesOnTheInjectedStream() throws {
        let stream = CadenceSyncActivityTestStream()
        let log = CadenceSyncActivityLog(stream: stream)

        #expect(log.summary.hasHistory == false)
        #expect(stream.startCount == 0)

        log.startIfNeeded()
        log.startIfNeeded()
        #expect(stream.startCount == 1, "the log subscribed \(stream.startCount) times")

        let identifier = UUID()
        stream.emit(began(.import, at: try moment(15, 24), identifier: identifier))
        #expect(log.summary.isWorking)
        #expect(log.summary.lastSuccess(.import) == nil)

        stream.emit(finished(.import, endingAt: try moment(15, 25), identifier: identifier))
        #expect(log.summary.isWorking == false)
        #expect(log.summary.lastSuccess(.import) == (try moment(15, 25)))

        stream.emit(finished(.export, endingAt: try moment(15, 45), succeeded: false, error: "boom"))
        #expect(log.summary.failure(.export) == "boom")
        #expect(
            log.summary.statusLine(now: try moment(16, 0), calendar: try calendar(), locale: english)
                == "Last import 3:25 PM · No export yet · Export failed: boom"
        )
    }
}

/// A stream that delivers exactly what a test hands it, on the main actor, synchronously.
///
/// This is the whole reason `CadenceSyncActivityEventStream` exists. The live implementation
/// observes `NSPersistentCloudKitContainer.eventChangedNotification`, which no test may provoke:
/// there is no API to make a mirroring pass happen, and the owner's real container and app group
/// are off limits.
@MainActor
private final class CadenceSyncActivityTestStream: CadenceSyncActivityEventStream {
    private(set) var startCount = 0
    private var handler: (@MainActor (CadenceSyncActivityEvent) -> Void)?

    func start(_ handler: @escaping @MainActor (CadenceSyncActivityEvent) -> Void) {
        startCount += 1
        self.handler = handler
    }

    func stop() { handler = nil }

    func emit(_ event: CadenceSyncActivityEvent) { handler?(event) }
}

/// Both platforms get this surface, and the launch wiring that feeds it.
///
/// [[T-1841]] is the standing example of iOS being given neither of two sections macOS got, and
/// shipping this one on macOS alone would repeat it precisely: iOS is the platform the owner could
/// not diagnose. `CadenceTests` builds on macOS, so `Cadence/iOS/` is behind `#if os(iOS)` and
/// unreachable at runtime — hence a source scan, with the non-vacuity guards `Cadence/Shared/AGENTS.md`
/// requires.
@MainActor
struct CadenceSyncActivitySurfaceParityTests {

    /// `anchor` is the non-vacuity claim: a wrong path or an empty read must fail here rather
    /// than make every `contains` assertion below trivially false.
    ///
    /// It is deliberately **not** `stripped != raw`. That is the right guard for a file that is
    /// known to carry comments, and `CadenceAppDelegate.swift` carries none — the guard reddened
    /// on a perfectly correct read. What the stripper does guarantee is that it blanks comments to
    /// spaces of equal length, so the length equality below holds either way.
    private func stripped(_ path: String, containing anchor: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.contains(anchor), "\(path) does not contain \(anchor); \(raw.count) bytes read")
        let strippedSource = CadenceSourceScan.strippingComments(raw)
        #expect(strippedSource.count == raw.count, "the stripper changed \(path)'s length")
        return strippedSource
    }

    @Test func bothPlatformsLaunchTheMirroringEventLog() throws {
        let macPath = "Cadence/macOS/Services/CadenceAppDelegate.swift"
        let iOSPath = "Cadence/iOS/iOSAppDelegate.swift"

        let mac = try stripped(macPath, containing: "NSApplicationDelegate")
        let macLaunch = try #require(
            CadenceSourceScan.functionBody(named: "applicationDidFinishLaunching", in: mac),
            "applicationDidFinishLaunching is gone from \(macPath)"
        )
        #expect(
            macLaunch.contains("CadenceSyncActivityLog.shared.startIfNeeded()"),
            "the Mac no longer starts the mirroring log at launch"
        )

        // Every UIKit delegate callback in the iOS file is *named* `application`, so the anchor is
        // the part of the signature that tells them apart — the same reason
        // `CadenceLaunchWiringTests` uses `declarationBody` here.
        let iOS = try stripped(iOSPath, containing: "UIApplicationDelegate")
        let iOSLaunch = try #require(
            CadenceSourceScan.declarationBody("didFinishLaunchingWithOptions", in: iOS),
            "didFinishLaunchingWithOptions is gone from \(iOSPath)"
        )
        #expect(
            iOSLaunch.contains("CadenceSyncActivityLog.shared.startIfNeeded()"),
            "iOS no longer starts the mirroring log at launch — the platform that could not be diagnosed"
        )

        // Both files are platform-guarded, so two call sites never land in one binary.
        #expect(mac.hasPrefix("#if os(macOS)"))
        #expect(iOS.hasPrefix("#if os(iOS)"))
    }

    @Test func bothSettingsSurfacesDrawTheMirroringActivityRow() throws {
        for (path, anchor) in [
            ("Cadence/macOS/Views/SettingsSyncSection.swift", "struct SettingsSyncSection"),
            ("Cadence/iOS/iOSSettingsOverviewSections.swift", "struct iOSSyncSettingsSection")
        ] {
            let code = try stripped(path, containing: anchor)
            #expect(
                code.contains("CadenceSyncActivityLog.shared.summary"),
                "\(path) does not read the mirroring log"
            )
            #expect(
                code.contains("activity.statusLine(now:"),
                "\(path) reads the log but never draws the line"
            )
            #expect(
                code.contains("activity.headline"),
                "\(path) draws the line with no headline over it"
            )
            #expect(
                code.contains("activity.tone.tint"),
                "\(path) draws the row with no tone"
            )
        }
    }

    /// **The one way this ticket fails.** There is no public API to force a
    /// `NSPersistentCloudKitContainer` sync. The two things that look like one are a nudge — touch
    /// a record so an export pass is scheduled, which pulls nothing down — and a destructive
    /// re-import that deletes the local store metadata. Neither may be shipped behind a control
    /// named for the thing it is not.
    ///
    /// A sweep rather than a two-file check: the failure guarded against is the button appearing
    /// *somewhere*, and the nearest-miss negative witness is the button this pane really does have.
    @Test func noSurfaceOffersAControlNamedForASyncItCannotForce() throws {
        let instrument = try CadenceScanInstrument(
            "a user-facing control claiming to force a sync",
            fires: #"SettingsActionButton(tone: .filled(Theme.blue), action: resync) { Text("Sync Now") }"#,
            andNotOn: #"SettingsActionButton(tone: .tinted(Theme.blue), action: probe.refresh) { Text("Check iCloud Status") }"#,
            by: { source in
                CadenceSourceScan.matchCount(
                    #""(Sync Now|Sync now|Resync|Re-sync|Force Sync|Force sync|Sync Again)""#,
                    in: source
                ) > 0
            }
        )

        let reader = CadenceSourceScan.strippedSourceReader()
        let offenders = try instrument.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            atLeast: 400,
            including: "Cadence/macOS/Views/SettingsSyncSection.swift",
            read: reader
        )

        #expect(offenders.isEmpty, "a fake resync control is back in: \(offenders.joined(separator: ", "))")

        // And the honest control the sync pane *does* have is still there, so the sweep above is
        // not green because the pane lost all of its buttons.
        let mac = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/SettingsSyncSection.swift")
        #expect(mac.contains(#"Text("Check iCloud Status")"#))
    }
}
