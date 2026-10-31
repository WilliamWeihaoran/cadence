import Foundation
import Testing

/// **[[T-8926]]: the interactive opt-in marker expires.**
///
/// Every case points the verdict at a marker under this test's OWN temporary directory and hands
/// it the clock, so nothing here touches the real marker in the UI-test runner's container and
/// nothing here can arm a run that drives the owner's screen.
struct CadenceInteractiveOptInMarkerTests {

    private let now = Date(timeIntervalSinceReferenceDate: 815_000_000)

    /// A fresh directory per call, removed by the caller's `defer`.
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-optin-marker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes the marker and backdates its mtime to `now - age`.
    private func marker(in directory: URL, age: TimeInterval) throws -> String {
        let path = directory.appendingPathComponent(CadenceInteractiveOptInMarker.fileName).path
        #expect(FileManager.default.createFile(atPath: path, contents: Data()))
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: path)
        return path
    }

    @Test func noMarkerIsNoOptIn() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(CadenceInteractiveOptInMarker.fileName).path
        #expect(CadenceInteractiveOptInMarker.verdict(atPath: path, now: now) == .absent)
    }

    @Test func aMarkerTouchedMinutesAgoIsHonoured() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try marker(in: directory, age: 5 * 60)
        #expect(CadenceInteractiveOptInMarker.verdict(atPath: path, now: now) == .fresh)
    }

    /// The measured case: present, size 0, mtime 29 days before it was found.
    @Test func theMarkerFoundArmedAfterTwentyNineDaysIsRefused() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let age: TimeInterval = 29 * 24 * 60 * 60
        let path = try marker(in: directory, age: age)
        let verdict = CadenceInteractiveOptInMarker.verdict(atPath: path, now: now)
        guard case .stale(let measured) = verdict else {
            Issue.record("a 29-day-old marker was \(verdict), and would have driven the owner's screen")
            return
        }
        #expect(abs(measured - age) < 2, "the stale verdict misreports the marker's age: \(measured)")
        #expect(CadenceInteractiveOptInMarker.describe(age: measured) == "29 day(s) old")
    }

    /// Either side of the window, so a mutation that moves or drops the bound flips one of them.
    @Test func theWindowEdgeIsWhereTheVerdictTurns() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let window = CadenceInteractiveOptInMarker.maximumAge
        let inside = try marker(in: directory, age: window - 60)
        #expect(CadenceInteractiveOptInMarker.verdict(atPath: inside, now: now) == .fresh)
        let outside = try marker(in: directory, age: window + 60)
        #expect(CadenceInteractiveOptInMarker.verdict(atPath: outside, now: now) != .fresh)
    }

    /// `touch -t` into the future must not re-open a standing opt-in.
    @Test func aMarkerDatedFarInTheFutureIsRefused() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try marker(in: directory, age: -24 * 60 * 60)
        #expect(CadenceInteractiveOptInMarker.verdict(atPath: path, now: now) != .fresh)
    }

    /// A relation, not a pinned figure: short enough that a marker left behind lapses within a
    /// sitting (the ticket's own ceiling is 4 hours), long enough to cover arming then running.
    @Test func theWindowIsShort() {
        #expect(CadenceInteractiveOptInMarker.maximumAge >= 10 * 60)
        #expect(CadenceInteractiveOptInMarker.maximumAge <= 4 * 60 * 60)
    }

    /// The gate actually asks the verdict, and the script that tells a reader how to arm it states
    /// the same window the verdict enforces.
    @Test func theGateAndTheArmingHintAgreeWithTheVerdict() throws {
        let environment = try CadenceSourceScan.sourceFile("CadenceUITests/CadenceUITestEnvironment.swift")
        #expect(environment.contains("interactiveOptInMarkerVerdict == .fresh"),
                "requireInteractiveUITests no longer gates on the marker's freshness")
        #expect(!environment.contains("fileExists(atPath: interactiveOptInMarkerPath)"),
                "the bare existence check is back, so a marker never expires")

        let xcb = try CadenceSourceScan.sourceFile("scripts/xcb.sh")
        let minutes = Int(CadenceInteractiveOptInMarker.maximumAge / 60)
        #expect(xcb.contains("marker counts only for \(minutes) minutes after its last touch"),
                "scripts/xcb.sh's arming hint no longer states the \(minutes)-minute window")
    }
}
