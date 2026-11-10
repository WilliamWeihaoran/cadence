import Combine
import Foundation
import Testing
@testable import Cadence

/// **T-15200 — the Debug-only lever that moves the app's idea of today, so a midnight rollover
/// can be driven on a simulator.**
///
/// Three things are pinned: the gate (what arms it, and that a non-Debug binary never is), the
/// mechanism (an advance moves the key one day and sends the signal `cadenceTracksDayChanges`
/// listens for, including when it arrives as the Darwin notification an agent posts with
/// `notifyutil`), and the shipping fence, read from source and from the project file because a
/// Debug test host cannot execute a Release branch.
struct CadenceTodayOverrideTests {

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-11-09 23:30 UTC -- half an hour before a real midnight, so an off-by-one in where the
    /// offset is measured from would show.
    private static let lateEvening = Date(timeIntervalSince1970: 1_794_267_000)

    private static func armed(_ today: String) -> [String: String] {
        [CadenceEventKitLaunchGate.uiTestModeVariable: "1", CadenceTodayOverride.variable: today]
    }

    // MARK: - The gate

    @Test func theOverrideIsArmedOnlyByUITestModePlusAWellFormedDayInADebugBinary() {
        #expect(DateFormatters.dateKey(from: Self.lateEvening, calendar: Self.utc) == "2026-11-09")

        let offset = CadenceTodayOverride.requestedOffsetDays(
            environment: Self.armed("2026-11-12"), realNow: Self.lateEvening, calendar: Self.utc, compiledIn: true
        )
        #expect(offset == 3)
        #expect(CadenceTodayOverride.requestedOffsetDays(
            environment: Self.armed("2026-11-08"), realNow: Self.lateEvening, calendar: Self.utc, compiledIn: true
        ) == -1)
        #expect(CadenceTodayOverride.requestedOffsetDays(
            environment: Self.armed("2026-11-09"), realNow: Self.lateEvening, calendar: Self.utc, compiledIn: true
        ) == 0)

        // A shipping binary: the identical environment arms nothing.
        #expect(CadenceTodayOverride.requestedOffsetDays(
            environment: Self.armed("2026-11-12"), realNow: Self.lateEvening, calendar: Self.utc, compiledIn: false
        ) == nil)
        // The day without UI-test mode, and UI-test mode without a day.
        #expect(CadenceTodayOverride.requestedOffsetDays(
            environment: [CadenceTodayOverride.variable: "2026-11-12"], realNow: Self.lateEvening, calendar: Self.utc, compiledIn: true
        ) == nil)
        #expect(CadenceTodayOverride.requestedOffsetDays(
            environment: [CadenceEventKitLaunchGate.uiTestModeVariable: "1"], realNow: Self.lateEvening, calendar: Self.utc, compiledIn: true
        ) == nil)
        // Malformed or leniently-parsed keys are refused rather than guessed at.
        for bad in ["2026-13-40", "2026-11", "tomorrow", ""] {
            #expect(CadenceTodayOverride.requestedOffsetDays(
                environment: Self.armed(bad), realNow: Self.lateEvening, calendar: Self.utc, compiledIn: true
            ) == nil, "\(bad)")
        }
    }

    /// The test host carries neither variable, so the process-wide override must be off -- which
    /// is also what keeps every other suite's `todayKey()` on the real clock.
    @Test func thisUnarmedProcessHasNoLiveOverride() {
        let environment = ProcessInfo.processInfo.environment
        #expect(environment[CadenceTodayOverride.variable] == nil)
        #expect(CadenceTodayOverride.live == nil)
    }

    // MARK: - The mechanism

    @Test func anAdvanceMovesTheKeyOneDayAndSendsTheDayChangeSignalOnce() {
        let center = NotificationCenter()
        let override = CadenceTodayOverride(offsetDays: 3, center: center)
        var received = 0
        let subscription = CadenceDayChangeSupport.dayMayHaveChanged(on: center).sink { received += 1 }
        defer { subscription.cancel() }

        func key() -> String {
            DateFormatters.dateKey(from: override.shifted(Self.lateEvening, calendar: Self.utc), calendar: Self.utc)
        }
        #expect(key() == "2026-11-12")
        #expect(received == 0)

        override.advance()
        #expect(key() == "2026-11-13")
        #expect(received == 1)

        // The observer a view installs sees a new day, which is what costs the body pass.
        var day = CadenceObservedDay(observedKey: "2026-11-12")
        let moved = day.observe(key())
        #expect(moved)

        override.advance()
        #expect(override.offsetDays == 5)
        #expect(received == 2)
    }

    /// The route an agent actually has: `simctl spawn <udid> notifyutil -p <name>`. A unique name,
    /// so nothing else on this Mac can post it and the live name is never touched.
    @Test func aDarwinPostOfTheListenedNameAdvancesTheOverride() async throws {
        let name = "com.haoranwei.Cadence.tests.todayOverride.\(UUID().uuidString)"
        let override = CadenceTodayOverride(offsetDays: 0, center: NotificationCenter())
        override.listen(forDarwinNotificationNamed: name)
        defer { override.stopListening(forDarwinNotificationNamed: name) }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true
        )
        // Delivery is asynchronous (the main run loop); poll for the COUNT, not for a time.
        for _ in 0..<200 where override.offsetDays == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(override.offsetDays == 1)
    }

    // MARK: - The shipping fence

    private static let formattersPath = "Cadence/Shared/DateFormatters.swift"

    /// A Debug test host cannot run the Release branch, so the branch is read: the live instance
    /// is built only under `#if DEBUG` with a literal `nil` otherwise, `isCompiledIn` is `false`
    /// outside DEBUG, the gate defaults to it, and `todayKey()` reads the clock through the
    /// override and nowhere else.
    @Test func theLiveOverrideIsUnreachableOutsideADebugBuild() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.formattersPath)
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code != raw && code.count == raw.count, "the stripper did not run")

        let compiledIn = #"static var isCompiledIn: Bool \{\s*#if DEBUG\s*return true\s*#else\s*return false\s*#endif\s*\}"#
        #expect(CadenceSourceScan.matchCount(compiledIn, in: code) == 1, "isCompiledIn must be true only under DEBUG")

        let live = #"static let live: CadenceTodayOverride\? = \{\s*#if DEBUG\s*guard let offset = requestedOffsetDays\([^#]*#else\s*return nil\s*#endif\s*\}\(\)"#
        #expect(CadenceSourceScan.matchCount(live, in: code) == 1, "the live override must be built only under DEBUG, nil otherwise")

        #expect(CadenceSourceScan.matchCount(#"compiledIn: Bool = isCompiledIn\s*\)"#, in: code) == 1)
        #expect(CadenceSourceScan.matchCount(#"guard compiledIn,"#, in: code) == 1)

        let todayKey = try #require(CadenceSourceScan.functionBody(named: "todayKey", in: code))
        #expect(todayKey.contains("CadenceTodayOverride.live?.shifted(now) ?? now"), "todayKey() no longer reads through the override")

        // Regex self-check: the needle matches the fenced shape and not an unfenced one.
        let fenced = "static var isCompiledIn: Bool {\n#if DEBUG\nreturn true\n#else\nreturn false\n#endif\n}"
        let unfenced = "static var isCompiledIn: Bool {\nreturn true\n}"
        #expect(CadenceSourceScan.matchCount(compiledIn, in: fenced) == 1)
        #expect(CadenceSourceScan.matchCount(compiledIn, in: unfenced) == 0)
    }

    /// The fence above is only a fence if Release does not define DEBUG, and if the archive the
    /// TestFlight build comes from is Release.
    @Test func noReleaseConfigurationDefinesDebugAndTheArchiveIsRelease() throws {
        let project = try CadenceSourceScan.sourceFile("Cadence.xcodeproj/project.pbxproj")
        let blocks = project.components(separatedBy: "isa = XCBuildConfiguration;").dropFirst()
        let release = blocks.filter { $0.contains("name = Release;") }
        let debug = blocks.filter { $0.contains("name = Debug;") }
        #expect(release.count >= 6, "expected a Release configuration per target plus the project's, found \(release.count)")

        // Non-vacuity: the same reader finds DEBUG where it is meant to be.
        #expect(debug.contains { $0.contains(#"SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";"#) })

        for block in release {
            let lines = block.components(separatedBy: "\n").filter {
                $0.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS") || $0.contains("OTHER_SWIFT_FLAGS")
            }
            for line in lines {
                #expect(line.contains("DEBUG") == false, "a Release configuration defines DEBUG: \(line)")
            }
        }

        let scheme = try CadenceSourceScan.sourceFile("Cadence.xcodeproj/xcshareddata/xcschemes/Cadence.xcscheme")
        #expect(CadenceSourceScan.matchCount(#"<ArchiveAction\s+buildConfiguration = "Release""#, in: scheme) == 1)
    }
}
