// SIGHTING HARNESS for [[T-19922]] (agent fix1708a), not a regression suite: the steps the slot1953
// by-section probe took (Seed Tasks, open `[Sample] TestFlight Readiness`, one swipe By Date as
// the control, then Group By Section and swipe), each swipe timed into `log.txt` and a frame at
// every step under `scratchpad/T-19922-frames/<TEST_RUNNER_FIX1708A_FRAMES or "frames">/`. A
// frozen list shows as a swipe that takes ~60 s (XCUITest's idle wait) and identical frames.
#if os(iOS)
import XCTest

@MainActor
final class CadenceIPhoneBySectionScrollFix1708aUITests: XCTestCase {
    private var app: XCUIApplication!
    private var step = 0

    override func setUpWithError() throws {
        try CadenceUITestEnvironment.requireAnUnlockedScreen()
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testBySectionScroll() throws {
        app = XCUIApplication()
        app.launchEnvironment["CADENCE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CADENCE_LOCAL_STORE_ONLY"] = "1"
        CadenceUITestEnvironment.isolateStoreAndPreferences(app, storeID: "fix1708a-\(UUID().uuidString)")
        app.launchEnvironment["CADENCE_RESET_STORE"] = "1"
        app.launchEnvironment["CADENCE_RESET_USER_DEFAULTS"] = "1"
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: CadenceUITestBounds.foreground)
        sleep(2)
        tap("More")
        tap("Settings")
        for _ in 0..<5 where visible("Data Safety", timeout: 1) == nil { app.swipeUp() }
        tap("Data Safety")
        for _ in 0..<8 where visible("Seed Tasks", timeout: 1) == nil { app.swipeUp() }
        tap("Seed Tasks")
        tap("Tasks")
        tap("TestFlight Readiness", contains: true)
        look("bydate")
        timed("by-date swipe 1") { app.swipeUp() }
        look("bydate-scrolled")
        app.swipeDown()
        tap("Group", contains: true)
        tap("By Section", contains: true)
        look("bysection")
        timed("by-section swipe 1") { app.swipeUp() }
        look("bysection-scrolled")
        timed("by-section swipe 2") { app.swipeUp() }
        look("bysection-scrolled-2")
        timed("by-section swipe down") { app.swipeDown() }
        look("bysection-scrolled-back")
        sleep(5)
        look("bysection-later")
    }

    private func timed(_ name: String, _ body: () -> Void) {
        let start = Date()
        body()
        record(String(format: "%@: %.1f s", name, Date().timeIntervalSince(start)))
    }

    private var frameDirectory: URL {
        let base = ProcessInfo.processInfo.environment["FIX1708A_FRAMES"] ?? "frames"
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scratchpad/T-19922-frames/\(base)", isDirectory: true)
    }

    private func look(_ name: String) {
        sleep(1)
        step += 1
        let shot = XCUIScreen.main.screenshot()
        try? FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(
            to: frameDirectory.appendingPathComponent(String(format: "%02d-%@.png", step, name))
        )
    }

    private func visible(_ label: String, contains: Bool = false, timeout: TimeInterval = 4) -> XCUIElement? {
        let predicate = contains
            ? NSPredicate(format: "label CONTAINS %@", label)
            : NSPredicate(format: "label == %@", label)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let all = app.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
            if let hit = all.first(where: { $0.exists && $0.frame.width > 1 && $0.frame.height > 1 && $0.isHittable }) {
                return hit
            }
            usleep(250_000)
        } while Date() < deadline
        return nil
    }

    @discardableResult
    private func tap(_ label: String, contains: Bool = false, timeout: TimeInterval = 4) -> Bool {
        guard let hit = visible(label, contains: contains, timeout: timeout) else {
            record("missing control: \(label)")
            return false
        }
        hit.tap()
        sleep(1)
        return true
    }

    private func record(_ line: String) {
        try? FileManager.default.createDirectory(at: frameDirectory, withIntermediateDirectories: true)
        let url = frameDirectory.appendingPathComponent("log.txt")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (old + "\(Date()) " + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
