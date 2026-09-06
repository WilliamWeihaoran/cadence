import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// The store a **composed-window** UI test needs, as opposed to the one every other test in this
/// repository gets.
///
/// `CadenceUITestSupport`'s stock seed is three sidebar lists and nothing else, which is all the
/// existing UI tests look at. It cannot express the state the four defects found by hand this week
/// were found in: a Today with yesterday's unfinished work on it, and a daily note holding a
/// picture. Neither is reachable from an empty store, and a test that has to *create* them through
/// the UI first is measuring the composer, not the surface it wanted.
///
/// So this is a named scenario, selected by `CADENCE_UI_TEST_SCENARIO`, and the stock seed is
/// untouched: `todayGeometry` is additive, runs after it, and every existing UI test keeps the
/// store it already had.
///
/// **Everything it writes is derived from `todayKey`,** never from a literal date, so the scenario
/// means the same thing on any day it is run. The one thing it does not control is the clock
/// crossing midnight mid-run; that is noted in T-1068 rather than papered over.
enum CadenceUITestScenarioSeed {

    /// The scenarios this build knows how to seed. A value the build does not recognise seeds
    /// nothing and says so in the log rather than silently falling back to the stock store, because
    /// a scenario that quietly does not happen is a UI test that quietly asserts about an empty
    /// screen.
    enum Scenario: String {
        case todayGeometry = "today-geometry"
    }

    /// The alt text on the seeded picture, and the text of the paragraph under it. Both are read
    /// back by the test, so they live here rather than being typed twice.
    enum Fixture {
        static let imageAltText = "Cadence UI test fixture image"
        static let paragraphUnderImage = "Paragraph under the fixture image."
        static let noteHeading = "UI Test Daily Note"

        /// The fixture picture's stored pixel size. A landscape 8:5, so a renderer that loses the
        /// aspect ratio produces a visibly different box rather than a plausible one — a square
        /// fixture would make the commonest aspect bug invisible.
        static let imagePixelWidth = 800
        static let imagePixelHeight = 500

        /// The width the note stores for the picture, well inside
        /// `MarkdownImageAssetService.clampedDisplayWidth`'s bounds so the test's own resize is
        /// the only thing that can move it.
        static let imageDisplayWidth: Double = 320

        /// The three task names the scenario puts on Today, one per standing. The test reads rows
        /// back by these strings, so a rename here is a rename there.
        static let pastDoTaskNames = ["Rollover One", "Rollover Two", "Rollover Three"]
        static let overdueTaskNames = ["Overdue One", "Overdue Two"]
        static let todayTaskNames = ["Today One", "Today Two"]
    }

    static var requestedScenario: Scenario? {
        guard let raw = ProcessInfo.processInfo.environment["CADENCE_UI_TEST_SCENARIO"], !raw.isEmpty else {
            return nil
        }
        guard let scenario = Scenario(rawValue: raw) else {
            print("[CadenceUITestScenarioSeed] unknown scenario '\(raw)'; nothing seeded")
            return nil
        }
        return scenario
    }

    @MainActor
    static func seedIfRequested(modelContext: ModelContext) {
        guard let scenario = requestedScenario else { return }
        switch scenario {
        case .todayGeometry:
            seedTodayGeometry(modelContext: modelContext)
        }
    }

    @MainActor
    private static func seedTodayGeometry(modelContext: ModelContext) {
        let todayKey = DateFormatters.ymd.string(from: Date())
        let yesterdayKey = DateFormatters.ymd.string(
            from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        )

        // Idempotent by the same test the stock seed uses: a relaunch with `CADENCE_RESET_STORE`
        // unset must find the store it left, not a second copy of it.
        let existingTasks = (try? modelContext.fetch(FetchDescriptor<AppTask>())) ?? []
        guard existingTasks.isEmpty else { return }

        let areas = (try? modelContext.fetch(FetchDescriptor<Area>())) ?? []
        let host = areas.first { $0.name == "Alpha Area" } ?? areas.first
        let hostContext = host?.context

        var order = 0
        // The context is a parameter rather than a capture (T-1078). `CadenceSaveCommitRule`
        // reads ownership off a signature, and a nested `func` that captures its parent's
        // `ModelContext` reads as owning the unit of work while its parent's `save()` is not
        // credited to it. Naming it says the same thing to the rule and to a reader.
        func insertTask(_ name: String, dueDate: String, scheduledDate: String, in modelContext: ModelContext) {
            let task = AppTask(title: name)
            task.dueDate = dueDate
            task.scheduledDate = scheduledDate
            task.order = order
            task.area = host
            task.context = hostContext
            order += 1
            modelContext.insert(task)
        }

        // `pastDo` — planned for yesterday, no due date, so `CadenceTodayRolloverSupport` offers
        // them and the rollover notice is on screen.
        for name in Fixture.pastDoTaskNames {
            insertTask(name, dueDate: "", scheduledDate: yesterdayKey, in: modelContext)
        }
        // `pastDue` — a deadline already missed. Deliberately separate: a due date outranks a do
        // date on Today, so these must *not* appear in the rollover offer.
        for name in Fixture.overdueTaskNames {
            insertTask(name, dueDate: yesterdayKey, scheduledDate: "", in: modelContext)
        }
        for name in Fixture.todayTaskNames {
            insertTask(name, dueDate: "", scheduledDate: todayKey, in: modelContext)
        }

        seedDailyNoteWithImage(todayKey: todayKey, modelContext: modelContext)

        // **Not `try?`.** This function inserts, and a swallowed commit on an inserting function is
        // the shape `CadenceSaveCommitDisciplineTests` exists to refuse — see the `try? save()` rule
        // in `AGENTS.md`. There is no user here to report a failure to, but there *is* a reader of
        // the log wondering why Today came up empty, and a scenario that silently failed to seed is
        // a UI test that silently asserts about an empty screen.
        do {
            try modelContext.save()
        } catch {
            print("[CadenceUITestScenarioSeed] the today-geometry seed could not be saved: \(error)")
        }
    }

    @MainActor
    private static func seedDailyNoteWithImage(todayKey: String, modelContext: ModelContext) {
        guard let data = solidFixturePNGData() else {
            print("[CadenceUITestScenarioSeed] could not build the fixture image; note seeded without one")
            return
        }

        let asset = MarkdownImageAsset(
            data: data,
            mimeType: "image/png",
            originalFilename: "cadence-ui-test-fixture.png",
            altText: Fixture.imageAltText,
            pixelWidth: Fixture.imagePixelWidth,
            pixelHeight: Fixture.imagePixelHeight,
            displayWidth: Fixture.imageDisplayWidth
        )
        modelContext.insert(asset)

        // The reference sits **alone on its line** — `MarkdownImageAssetService.standaloneReferences`
        // is what decides an image renders as a block, and an inline one deliberately stays text.
        let content = """
        # \(Fixture.noteHeading)

        \(MarkdownImageAssetService.markdown(for: asset))

        \(Fixture.paragraphUnderImage)
        """

        let existing = (try? modelContext.fetch(FetchDescriptor<Note>()))?
            .first { $0.kind == .daily && $0.dateKey == todayKey }
        if let existing {
            existing.content = content
            return
        }

        modelContext.insert(Note(kind: .daily, title: todayKey, content: content, dateKey: todayKey))
    }

    /// A single-colour PNG, built rather than checked in.
    ///
    /// It is built because the test's pixel assertions need a picture whose *correct* rendering is
    /// stateable in one sentence — "every pixel inside its box is the same colour" — and a real
    /// photograph is not. Anything drawn on top of the picture, which is the defect this exists to
    /// see, breaks that sentence and nothing else does.
    ///
    /// A 2588-character base64 literal would have done the same job and is what the first cut had;
    /// this is 20 lines that any reader can check by eye instead.
    static func solidFixturePNGData() -> Data? {
        let width = Fixture.imagePixelWidth
        let height = Fixture.imagePixelHeight
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }

        // Not a `Theme` colour and deliberately not one: this is a test fixture's pigment, not app
        // chrome. Fully saturated magenta is the point — it is the one hue no Cadence surface
        // draws, so the test can find the picture in a screenshot without being told where it is.
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
