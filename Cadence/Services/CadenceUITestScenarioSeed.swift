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
        /// Two Today rows built to make the row's *horizontal* allocation measurable (T-1432): one
        /// carrying the decoration the owner's screenshot had, one carrying none, and both titled
        /// far too long to fit at any pane width this app is drawn at.
        case todayRowCrush = "today-row-crush"
        /// One board card carrying **every chip that opens a popover of its own** (T-1740), on a
        /// day the Calendar Board draws: a scheduled start (so the schedule top row and its
        /// duration badge exist), a list, a tag and a deadline. Plus a block on the same day, for
        /// `CalendarBoardBundleCard`. The point is that all five of the board's `arrowEdge:
        /// .trailing` anchors are on screen in ONE window, so their frames are comparable.
        case popoverAnchors = "popover-anchors"
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

        // MARK: - today-row-crush (T-1432)

        /// The tail both crush titles carry. Long enough that **neither title can fit at any pane
        /// width this app is drawn at**, which is deliberate: the defect only exists in the state
        /// where the row has less width than its children want, so a fixture that fits some of the
        /// time would pass some of the time for the wrong reason.
        static let crushTitleTail = " title that has to keep the majority of its own row, at a length no task pane on this machine can draw in full"

        /// The row the owner photographed: an estimate chip, the focus control and an overdue
        /// due-date chip, all trailing a title far too long for the space left.
        static let crushedTitle = "Crushed" + crushTitleTail

        /// The control, and it is what makes the reading a **comparison** rather than a threshold.
        /// Same length, same font, same pane, same instant — and nothing trailing it. A title width
        /// in points means nothing on its own; a title width next to the width the same title got
        /// with no decoration beside it is the whole of T-1432 stated as a number.
        ///
        /// `Control` and `Crushed` are both seven characters so the two titles differ by a glyph or
        /// two of advance width, not by a word.
        static let bareTitle = "Control" + crushTitleTail

        /// Days before today the crushed row's deadline sits. **51 is the figure in the screenshot
        /// that filed T-1432** — `51 days ago` is three words, and three words is what wrapped onto
        /// three lines.
        static let crushedDueDaysAgo = 51

        /// Minutes on the crushed row, so the estimate chip is drawn and the metadata strip has
        /// something it can shed before it reaches the due chip.
        static let crushedEstimateMinutes = 95

        // MARK: - popover-anchors (T-1740)

        /// The one board card the sweep reads. Named rather than titled "Task" because the test
        /// addresses it by an identifier derived from this string.
        static let boardCardTitle = "Board Anchor Card"

        /// The tag on it. `KanbanCardTagStrip` renders **nothing** for a task with no tags, so
        /// without this the tag anchor would silently not exist and the sweep would report four
        /// readings where it meant five — the exact reporting failure T-1722 was written against.
        static let boardCardTagName = "Anchor"

        /// The block on the same day, which is what puts a `CalendarBoardBundleCard` in the
        /// column beside the card.
        static let boardBundleTitle = "Anchor Block"

        /// 9:00. Any scheduled start does; `KanbanCard.hasScheduleTopRow` is `scheduledStartMin >= 0`.
        static let boardCardStartMinute = 9 * 60

        /// Minutes, so the duration badge reads a real value rather than the em dash placeholder.
        static let boardCardEstimateMinutes = 90

        /// The **calendar event** the board draws beside the two of them ([[T-1843]]).
        ///
        /// Not seeded here, and it cannot be: everything else in this scenario is a SwiftData
        /// object and this one is an `EKEvent`, which lives in a store this process holds no
        /// authorisation for. `CalendarBoardUITestEventSupport` builds it, unsaved, at the point
        /// the board asks EventKit for the day — the only place a display item can be put on
        /// screen without one. The strings live here because they are the scenario's, and because
        /// the test addresses the card by an identifier slugged from this title.
        static let boardEventTitle = "Anchor Event"

        /// 1:00 pm, after the card's 9:00 start, so the event card sorts below the task card and
        /// the block rather than on top of either. Any later minute does.
        static let boardEventStartMinute = 13 * 60

        /// Minutes. Long enough that the card's time-range chip draws two distinct times.
        static let boardEventDurationMinutes = 60

        /// The unsaved calendar the fixture event is put on. It exists because
        /// `CalendarEventEditPopover` reads `ekEvent.calendar` through an implicitly-unwrapped
        /// optional and an event without one crashes the app when its card is clicked — measured
        /// 2026-10-03, see [[T-2047]]. Not a user-facing name on any shipping surface.
        static let boardEventCalendarTitle = "Anchor Calendar"
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
        case .todayRowCrush:
            seedTodayRowCrush(modelContext: modelContext)
        case .popoverAnchors:
            seedPopoverAnchors(modelContext: modelContext)
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

    /// **Two rows whose only difference is what trails the title** (T-1432).
    ///
    /// The row that filed the ticket had a title truncated to about ten characters beside a due
    /// chip that had wrapped `51 days ago` onto three lines. Neither fact is reachable from a unit
    /// test: SwiftUI publishes no seam saying which subview of an `HStack` won the width, and the
    /// pin that shipped with the fix reads the *source* for `.layoutPriority(1)` — which can only
    /// fail when someone deletes the modifier, never when the modifier is present and the layout
    /// still comes out wrong.
    ///
    /// So the scenario plants the two rows a comparison needs and nothing else: no rollover banner,
    /// no daily note, no second list. Fewer moving parts than `todayGeometry` on purpose — the only
    /// figures the test reads are widths and heights of four elements, and anything else on screen
    /// is a thing that can move them.
    @MainActor
    private static func seedTodayRowCrush(modelContext: ModelContext) {
        let todayKey = DateFormatters.ymd.string(from: Date())
        let dueKey = DateFormatters.ymd.string(
            from: Calendar.current.date(byAdding: .day, value: -Fixture.crushedDueDaysAgo, to: Date()) ?? Date()
        )

        // Idempotent by the same test the stock seed and `todayGeometry` use.
        let existingTasks = (try? modelContext.fetch(FetchDescriptor<AppTask>())) ?? []
        guard existingTasks.isEmpty else { return }

        let areas = (try? modelContext.fetch(FetchDescriptor<Area>())) ?? []
        let host = areas.first { $0.name == "Alpha Area" } ?? areas.first

        // Both are planned for **today**, so Today's section already states the day and the row
        // drops its do-date pill (`MacTaskRow.statedDoDate`). That is what leaves the crushed row
        // with exactly the trailing strip the screenshot had, and the bare row with none.
        let crushed = AppTask(title: Fixture.crushedTitle)
        crushed.scheduledDate = todayKey
        crushed.dueDate = dueKey
        crushed.estimatedMinutes = Fixture.crushedEstimateMinutes
        crushed.order = 0
        crushed.area = host
        crushed.context = host?.context
        modelContext.insert(crushed)

        let bare = AppTask(title: Fixture.bareTitle)
        bare.scheduledDate = todayKey
        bare.dueDate = ""
        bare.estimatedMinutes = 0
        bare.order = 1
        bare.area = host
        bare.context = host?.context
        modelContext.insert(bare)

        // **Not `try?`** — an inserting function that swallows its commit is the shape
        // `CadenceSaveCommitDisciplineTests` refuses, and a scenario that silently failed to seed
        // is a UI test that silently asserts about an empty screen.
        do {
            try modelContext.save()
        } catch {
            print("[CadenceUITestScenarioSeed] the today-row-crush seed could not be saved: \(error)")
        }
    }

    /// **One card with every popover-bearing chip on it, and a block beside it** (T-1740).
    ///
    /// The board's five `arrowEdge: .trailing` anchors are opened by a list chip, a tag strip, a
    /// duration badge, the card itself and a block card beside it — and three of those only exist
    /// when the task carries the field behind them. A task with no tags draws no tag strip; a task
    /// with no scheduled start draws no schedule top row and therefore no duration badge; a card
    /// asked not to show a container chip draws none. So the fixture sets all of them, on
    /// **today**, which is the column the Calendar Board opens on.
    ///
    /// Deliberately **one** card. Two would put a second copy of every identifier on screen and the
    /// sweep's queries would each match two elements.
    @MainActor
    private static func seedPopoverAnchors(modelContext: ModelContext) {
        let todayKey = DateFormatters.ymd.string(from: Date())
        // **Tomorrow, not today, and it was an attempt to narrow the list chip that did not work.**
        // The Calendar Board passes each column's own day as `dayAlreadyStatedBySurface` and
        // `CadenceBoardCardMetadata` drops a date chip that would only repeat it, so a card due
        // today draws one metadata chip and the list chip has the row to itself — which would have
        // made the list picker's measured clearance an accident of the fixture. A deadline on
        // another day was meant to put a second chip beside it.
        //
        // **It does not, and the reason is better than the fixture.** Measured 2026-09-30: the card
        // was unchanged, 146pt tall with content still ending at x = 830, because
        // `KanbanCard.metadataRows` appends the list chip **alone on its own row** whatever else is
        // on the card. The list chip spans the content column structurally, not by luck, and no
        // fixture can make it not. The deadline stays: it is what puts a due chip on the *Today*
        // row, which is what extended that row's content to x = 1106 and produced the 10pt reading
        // filed as T-1845.
        let tomorrowKey = DateFormatters.ymd.string(
            from: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )

        // Idempotent by the same test the stock seed and the other two scenarios use.
        let existingTasks = (try? modelContext.fetch(FetchDescriptor<AppTask>())) ?? []
        guard existingTasks.isEmpty else { return }

        let areas = (try? modelContext.fetch(FetchDescriptor<Area>())) ?? []
        let host = areas.first { $0.name == "Alpha Area" } ?? areas.first

        let tag = Tag(name: Fixture.boardCardTagName, colorHex: "#5AA2FF", order: 0)
        modelContext.insert(tag)

        let card = AppTask(title: Fixture.boardCardTitle)
        card.scheduledDate = todayKey
        card.scheduledStartMin = Fixture.boardCardStartMinute
        card.estimatedMinutes = Fixture.boardCardEstimateMinutes
        card.dueDate = tomorrowKey
        card.order = 0
        card.area = host
        card.context = host?.context
        // A to-many CloudKit relationship is an optional array and is appended to by assigning a
        // new one, never by mutating in place.
        card.tags = [tag]
        modelContext.insert(card)

        let bundle = TaskBundle(
            title: Fixture.boardBundleTitle,
            dateKey: todayKey,
            startMin: Fixture.boardCardStartMinute + 240,
            durationMinutes: 60
        )
        modelContext.insert(bundle)

        // **Not `try?`**, for the reason the two scenarios above state: a scenario that silently
        // failed to seed is a UI test that silently asserts about an empty screen.
        do {
            try modelContext.save()
        } catch {
            print("[CadenceUITestScenarioSeed] the popover-anchors seed could not be saved: \(error)")
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
