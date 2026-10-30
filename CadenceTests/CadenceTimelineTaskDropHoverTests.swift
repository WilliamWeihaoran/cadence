#if os(macOS)
import CoreGraphics
import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Cadence

/// **[[T-8142]]: a task dragged over an iOS day column shows where it will land before the
/// release, in the plate the Mac canvas has always drawn** -- and **[[T-8143]]: the Calendar page
/// that column sits on can start such a drag, from its own unscheduled chips.**
///
/// The rule half (`CadenceTimelineTaskDropHover`) is Shared and asked directly. The iOS wiring
/// cannot compile in this macOS-built target, so it is read from source.
@MainActor
struct CadenceTimelineTaskDropHoverTests {
    private let hourHeight: CGFloat = 60
    private let timelineFile = "Cadence/iOS/iOSCalendarTimelineViews.swift"

    private func y(forMinute minute: Int) -> CGFloat {
        CGFloat(minute - CadenceScheduleSupport.calendarStartHour * 60) / 60 * hourHeight
    }

    // MARK: - The rule

    /// Away from the edges the plate starts on exactly the quarter-hour the column's own tap would
    /// name, whatever the task's length -- the hover adds a clamp, never a second arithmetic.
    @Test func awayFromTheEdgesTheHoverStartsOnTheColumnsOwnTapMinute() {
        var checked = 0
        for minute in stride(from: 8 * 60, through: 18 * 60, by: 7) {
            let point = y(forMinute: minute) + 3
            let tap = CadenceScheduleSupport.timelineMinute(atY: point, hourHeight: hourHeight)
            for duration in [nil, 5, 30, 90] as [Int?] {
                let hover = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: duration)
                #expect(hover.startMinute == tap, "a \(String(describing: duration))-minute hover at \(minute) left the tap's minute")
                checked += 1
            }
        }
        #expect(checked > 100, "non-vacuity: \(checked) points checked")
    }

    /// Until the payload names a task, the plate claims the start and one touch-grid step, not an
    /// invented length; once it does, the plate is the task's own length.
    @Test func thePlateIsOneGridStepUntilTheTaskIsKnownAndItsOwnLengthAfter() {
        let point = y(forMinute: 10 * 60 + 30)
        let unknown = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: nil)
        #expect(unknown.durationMinutes == nil)
        #expect(unknown.drawnRange.end - unknown.drawnRange.start == CadenceScheduleSupport.touchTimeGridMinutes)

        let known = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: 90)
        #expect(known.startMinute == unknown.startMinute)
        #expect(known.drawnRange.start == known.startMinute)
        #expect(known.drawnRange.end - known.drawnRange.start == 90)
    }

    /// The Mac's [[T-5370]] clamp, read for touch: a known task hovered at the bottom of the day
    /// lands where the whole block still fits, not where it would run past the last hour. A
    /// relation, not a pinned minute.
    @Test func aKnownTaskAtTheBottomOfTheDayIsHeldWhereTheWholeBlockFits() {
        let dayEnd = CadenceScheduleSupport.calendarEndHour * 60
        let point = y(forMinute: dayEnd - 10)
        let tap = CadenceScheduleSupport.timelineMinute(atY: point, hourHeight: hourHeight)
        for duration in [30, 60, 120] {
            let hover = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: duration)
            #expect(hover.startMinute + duration <= dayEnd, "a \(duration)-minute hover runs past the drawn day")
            #expect(hover.startMinute < tap, "non-vacuity: the \(duration)-minute clamp moved nothing")
            #expect(hover.drawnRange.end <= dayEnd)
        }
        // An unknown length keeps the start-only clamp the tap already has.
        let unknown = CadenceTimelineTaskDropHover.resolve(atY: point, hourHeight: hourHeight, durationMinutes: nil)
        #expect(unknown.startMinute == tap)
    }

    // MARK: - The wiring

    /// The column answers a hovering task, through a delegate that computes the hover and the
    /// release with the same call, and puts the plate away when the finger leaves or lets go.
    @Test func theIOSColumnDrawsTheHoverPlateAndClearsItOnExitAndRelease() throws {
        let source = try CadenceSourceScan.sourceFile(timelineFile)
        let code = CadenceSourceScan.strippingComments(source)
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: code)
        )
        #expect(column.count > 1_000, "non-vacuity: the day column read as \(column.count) characters")
        #expect(CadenceSourceScan.matchCount(#"\n\s*taskDropHoverLayer\s*\n\s*\.zIndex\("#, in: column) == 1,
                "the column no longer draws the hovering task's plate")
        #expect(CadenceSourceScan.matchCount(#"hover: \$taskDropHover,"#, in: column) == 1)
        let layer = try #require(column.range(of: "private var taskDropHoverLayer: some View").map { String(column[$0.lowerBound...]) })
        #expect(CadenceSourceScan.matchCount(#"if let taskDropHover \{"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineTaskDropHover\.fillOpacity"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineTaskDropHover\.strokeOpacity"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"\.allowsHitTesting\(false\)"#, in: layer) >= 1,
                "the plate takes the hit and swallows the drop it is previewing")

        let delegate = try #require(
            CadenceSourceScan.declarationBody("private struct iOSTimelineTaskDropDelegate: DropDelegate", in: code)
        )
        let exited = try #require(CadenceSourceScan.declarationBody("func dropExited(info: DropInfo)", in: delegate))
        #expect(CadenceSourceScan.matchCount(#"hover = nil"#, in: exited) == 1, "the plate outlives the finger leaving")
        let perform = try #require(CadenceSourceScan.declarationBody("func performDrop(info: DropInfo) -> Bool", in: delegate))
        #expect(CadenceSourceScan.matchCount(#"hover = nil"#, in: perform) == 1, "the plate outlives the release")
        #expect(CadenceSourceScan.matchCount(#"_ = onDrop\(id, minute\)"#, in: perform) == 1)
        // The release measures with the task's own length, as the hover did, so the minute the
        // plate showed is the minute written.
        #expect(CadenceSourceScan.matchCount(#"durationMinutes: resolveTask\(id\)\?\.timelineDurationMinutes"#, in: perform) == 1,
                "the release resolves its minute without the task's length, so it can land off the plate")
        let updated = try #require(CadenceSourceScan.declarationBody("func dropUpdated(info: DropInfo) -> DropProposal?", in: delegate))
        #expect(CadenceSourceScan.matchCount(#"updateHover\(with: info\)"#, in: updated) == 1,
                "the plate no longer follows the finger")
    }

    /// One plate on both platforms: the Mac preview reads its two figures from the same place.
    @Test func theMacPreviewReadsTheSamePlateFigures() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift")
        )
        let preview = try #require(CadenceSourceScan.declarationBody("struct TimelineDraggedTaskPreview: View", in: mac))
        #expect(CadenceSourceScan.matchCount(#"Theme\.blue\.opacity\(CadenceTimelineTaskDropHover\.fillOpacity\)"#, in: preview) == 1)
        #expect(CadenceSourceScan.matchCount(#"Theme\.blue\.opacity\(CadenceTimelineTaskDropHover\.strokeOpacity\)"#, in: preview) == 1)
    }

    /// Both hosts resolve the hovering task through the lookup their commit makes.
    @Test func bothHostsResolveTheHoveringTaskThroughTheCommitsLookup() throws {
        for file in ["Cadence/iOS/iOSTodaySchedulePanel.swift", "Cadence/iOS/iOSCalendarView.swift"] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(file))
            #expect(
                CadenceSourceScan.matchCount(#"resolveDroppedTask: \{ CadenceTimelineBlockEdit\.droppedTask\(\$0, among: allTasks\) \}"#, in: source) == 1,
                "\(file) resolves a hovering task some other way than its commit does"
            )
        }
        let shared = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTimelineBlockEditSupport.swift")
        )
        #expect(CadenceSourceScan.matchCount(#"guard let task = droppedTask\(taskID, among: tasks\)"#, in: shared) == 1)
    }

    // MARK: - [[T-8451]]: the length at HOVER time, from the item the lift named

    /// **The defect this half fixes.** UIKit withholds the payload for the whole hover, so the plate
    /// was one grid step tall and untitled until the release: a 60-minute task hovered `7 PM - 7:15
    /// PM` and landed `7 PM - 8 PM` ([[T-8302]], on `Cadence-iPadPro11`). The lift now NAMES its task
    /// on the item it hands over, which a hovering column reads synchronously, so the plate's own end
    /// is the end the drop writes. Asked as a relation between the two, not as a pinned clock
    /// reading.
    @Test func theHoverPlateIsTheNamedTasksOwnLengthBeforeTheReleaseWrites() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = AppTask(title: "Prep slides for review")
        task.estimatedMinutes = 60
        task.scheduledDate = "2026-06-01"
        task.scheduledStartMin = -1
        modelContext.insert(task)
        try modelContext.save()
        let universe = [task]

        let point = y(forMinute: 19 * 60)
        func plate(named name: String?) -> CadenceTimelineTaskDropHover {
            CadenceTimelineTaskDropHover.resolve(
                atY: point,
                hourHeight: hourHeight,
                durationMinutes: CadenceTimelineTaskDrag.taskID(itemNamed: name)
                    .flatMap { CadenceTimelineBlockEdit.droppedTask($0, among: universe) }?.timelineDurationMinutes
            )
        }

        // An item that names no task -- text dragged in from elsewhere, and the pre-[[T-8451]] state
        // of every task drag -- leaves the plate claiming one grid step.
        for unnamed in [nil, "", "not a uuid"] as [String?] {
            let fallback = plate(named: unnamed)
            #expect(fallback.durationMinutes == nil)
            #expect(fallback.drawnRange.end - fallback.drawnRange.start
                    == CadenceScheduleSupport.touchTimeGridMinutes)
        }

        // The named item. No payload read is awaited, and on this surface none answers during the
        // hover at all.
        let hovered = plate(named: CadenceTimelineTaskDrag.itemName(for: task.id))
        #expect(hovered.durationMinutes == task.timelineDurationMinutes)
        #expect(hovered.drawnRange.end - hovered.drawnRange.start == task.timelineDurationMinutes)
        #expect(hovered.drawnRange.end - hovered.drawnRange.start
                > CadenceScheduleSupport.touchTimeGridMinutes,
                "non-vacuity: the name changed nothing about the plate's height")

        // The release writes the block the plate was drawn as: same start, same length.
        #expect(
            CadenceTimelineBlockEdit.commitDrop(
                taskID: task.id, among: universe,
                dateKey: "2026-06-02", startMin: hovered.startMinute, in: modelContext, reconciler: .inert
            )
        )
        #expect(task.scheduledStartMin == hovered.drawnRange.start)
        #expect(task.scheduledEndMin == hovered.drawnRange.end,
                "the block landed at an end the hover plate did not name")
    }

    /// A 15-minute task is the case that was already right, and stays right: one grid step, which
    /// is its own length. The 60-minute reading above is what separates the two.
    @Test func aOneGridStepTaskIsDrawnTheSameWayItWasBeforeTheName() {
        let point = y(forMinute: 16 * 60)
        let step = CadenceScheduleSupport.touchTimeGridMinutes
        let named = CadenceTimelineTaskDropHover.resolve(
            atY: point, hourHeight: hourHeight, durationMinutes: step
        )
        let unnamed = CadenceTimelineTaskDropHover.resolve(
            atY: point, hourHeight: hourHeight, durationMinutes: nil
        )
        #expect(named.drawnRange == unnamed.drawnRange)
    }

    /// **One item, two channels, one spelling.** The name is additional metadata on the provider the
    /// drag has always carried: the payload string is untouched, so every drop target that decodes
    /// it keeps working, and the type it is registered under is the one a `String` drop destination
    /// ingests.
    @Test func theLiftedItemCarriesBothTheOldPayloadAndTheTasksName() async throws {
        let taskID = UUID()
        let provider = CadenceTimelineTaskDrag.itemProvider(for: taskID)

        #expect(provider.suggestedName == taskID.uuidString)
        #expect(CadenceTimelineTaskDrag.taskID(itemNamed: provider.suggestedName) == taskID)
        #expect(CadenceTimelineTaskDrag.hoveringTaskID(in: [provider]) == taskID)
        #expect(CadenceTimelineTaskDrag.hoveringTaskID(in: []) == nil)
        #expect(
            provider.registeredTypeIdentifiers.contains(UTType.utf8PlainText.identifier),
            "the lifted item stopped registering the type every text drop destination reads"
        )
        #expect(
            provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
            "the lifted item no longer conforms to the type the day column validates against"
        )

        // The payload itself, loaded back the way both platforms' delegates load it.
        let loaded = try #require(
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    continuation.resume(returning: (object as? NSString) as String?)
                }
            }
        )
        #expect(loaded == TaskDragPayload.string(for: taskID))
        #expect(TaskDragPayload.taskID(from: loaded) == taskID)
    }

    /// The wiring: the lift builds the named item, and the column's delegate reads the name
    /// **before** it sizes the plate rather than waiting on a payload that never answers.
    @Test func theLiftNamesTheTaskAndTheHoverReadsItBeforeItSizesThePlate() throws {
        let sharedSource = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTimelineTaskDragSource.swift")
        )
        #expect(CadenceSourceScan.matchCount(#"#if os\("#, in: sharedSource) == 0,
                "the shared drag source fenced itself to one platform")
        let modifier = try #require(
            CadenceSourceScan.declarationBody("private struct TimelineTaskDragSourceModifier: ViewModifier", in: sharedSource)
        )
        // `.onDrag` and not `.draggable`: `draggable(_:)`'s payload autoclosure is evaluated on a
        // view's FIRST lift and the item is reused after that, so a row's second drag named nothing
        // (measured on `Cadence-iPadPro11` 2026-10-29). `onDrag` builds the item the drag carries.
        #expect(CadenceSourceScan.matchCount(#"content\.onDrag \{ CadenceTimelineTaskDrag\.itemProvider\(for: taskID\) \}"#, in: modifier) == 1,
                "the lift stopped building the item that names its task")
        #expect(CadenceSourceScan.matchCount(#"\.draggable\("#, in: modifier) == 0,
                "the lift is back on .draggable, whose payload a second drag never re-evaluates")

        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(timelineFile))
        let delegate = try #require(
            CadenceSourceScan.declarationBody("private struct iOSTimelineTaskDropDelegate: DropDelegate", in: code)
        )
        // Read BEFORE the plate is sized, in both callbacks, or the first frames of the hover are
        // the one-step plate this ticket is about.
        for callback in [
            "func dropEntered(info: DropInfo)",
            "func dropUpdated(info: DropInfo) -> DropProposal?"
        ] {
            let body = try #require(CadenceSourceScan.declarationBody(callback, in: delegate))
            let adopt = try #require(body.range(of: "adoptNamedTaskID(from: info)"),
                                     "\(callback) sizes the plate without reading the item's name")
            let update = try #require(body.range(of: "updateHover(with: info)"))
            #expect(adopt.lowerBound < update.lowerBound,
                    "\(callback) sizes the plate before it reads the item's name")
        }
        let adopt = try #require(CadenceSourceScan.declarationBody("private func adoptNamedTaskID(from info: DropInfo)", in: delegate))
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineTaskDrag\.hoveringTaskID\(in: info\.itemProviders\(for: \[UTType\.text\]\)\)"#, in: adopt) == 1,
                "the column reads the hovering task some other way than off the item")
        #expect(CadenceSourceScan.matchCount(#"resolveTask\(taskID\) != nil"#, in: adopt) == 1,
                "the plate titles itself from a name this column cannot resolve")
    }

    /// Both iOS surfaces that can hand a timeline a task lift through the one shared source, so
    /// neither can grow a bare `.draggable` whose item names nothing.
    @Test func theRowAndTheBandChipBothLiftThroughTheSharedDragSource() throws {
        for (file, declaration) in [
            ("Cadence/iOS/iOSTaskViews.swift", "struct iOSTaskRow: View"),
            (timelineFile, "private struct iOSCalendarAllDayBandChips: View")
        ] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(file))
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: code))
            #expect(CadenceSourceScan.matchCount(#"\.timelineTaskDragSource\(taskID: task\.id\)"#, in: body) == 1,
                    "\(declaration) no longer lifts through the shared drag source")
            #expect(CadenceSourceScan.matchCount(#"\.draggable\("#, in: body) == 0,
                    "\(declaration) lifts through a bare .draggable again, so its item names no task")
        }
    }

    /// [[T-8143]]: the Calendar page's unscheduled chips drag as their task, and a tap on one still
    /// selects the day, as it did when the chip let the tap fall through.
    @Test func theUnscheduledBandChipDragsAsItsTaskAndStillSelectsTheDay() throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(timelineFile))
        let chips = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarAllDayBandChips: View", in: code)
        )
        let tasks = try #require(chips.range(of: "ForEach(unscheduledTasks.prefix(split.tasks))"))
        let overflow = try #require(chips.range(of: "if split.hidden > 0"))
        let taskStack = String(chips[tasks.lowerBound..<overflow.lowerBound])
        #expect(CadenceSourceScan.matchCount(#"\.timelineTaskDragSource\(taskID: task\.id\)"#, in: taskStack) == 1,
                "the unscheduled chip no longer offers its task to the grid")
        #expect(CadenceSourceScan.matchCount(#"\.allowsHitTesting\(false\)"#, in: taskStack) == 0,
                "the unscheduled chip takes no hit again, so it cannot start a drag")
        #expect(CadenceSourceScan.matchCount(#"\.onTapGesture \{ onSelectDay\?\(\) \}"#, in: taskStack) == 1,
                "a tap on the chip no longer selects the day")

        let header = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayHeader: View", in: code)
        )
        #expect(CadenceSourceScan.matchCount(#"onSelectDay: action"#, in: header) == 1,
                "the week header no longer hands its select-the-day action to the chips it draws over")
    }

    // MARK: - [[T-8455]]: at one grid step the plate still states its time

    /// **The defect.** [[T-8451]] gave the plate the dragged task's title, and a plate one grid
    /// step tall has room for exactly one row, so the title took it: a 15-minute task hovered down
    /// `Cadence-iPadPro11`'s timeline read `[Sample] Completed sync smoke test` and no time at all,
    /// where before it read `4 PM - 4:15 PM`. The fix is one row carrying both when two will not
    /// fit, and the decision is `CadenceTimelineTaskDropHover.labelLayout`.
    ///
    /// Pinned at a 15-minute length, which is the only height where the two cannot both fit, and
    /// asked as a RELATION against the rows' own cost rather than against a remembered threshold.
    @Test func atOneGridStepThePlatePutsItsTitleAndItsTimeOnOneRow() {
        let step = CadenceScheduleSupport.touchTimeGridMinutes
        let stacked = CadenceTimelineTaskDropHover.stackedLabelHeight(
            verticalPadding: plateVerticalPadding,
            rowSpacing: plateRowSpacing,
            titleFontSize: plateTitleFontSize,
            timeFontSize: plateTimeFontSize
        )

        // One grid step: two rows do not fit, one row does, so the plate says both on that row
        // rather than dropping either.
        let oneStep = plateHeight(forMinutes: step)
        #expect(oneStep < stacked, "non-vacuity: a one-grid-step plate now has room for two rows")
        #expect(
            oneStep >= plateVerticalPadding * 2
                + CadenceCalendarOverlapLayout.lineHeight(forSystemFontSize: plateTitleFontSize),
            "the inline row does not fit either, so the plate is clipped whichever way it is drawn"
        )
        #expect(plateLabelLayout(forMinutes: step) == .inline)

        // An hour: unchanged, the two stacked rows [[T-8451]] was verified with.
        #expect(plateHeight(forMinutes: 60) >= stacked, "non-vacuity: an hour lost room for two rows")
        #expect(plateLabelLayout(forMinutes: 60) == .stacked)

        // Across every length the column draws, the arrangement is exactly "do two rows fit", and
        // it never goes back to one once it has room for two.
        var sawInline = 0
        var sawStacked = 0
        var lastStacked = false
        for minutes in stride(from: step, through: 8 * 60, by: step) {
            let height = plateHeight(forMinutes: minutes)
            let layout = plateLabelLayout(forMinutes: minutes)
            #expect(layout == (height >= stacked ? .stacked : .inline),
                    "a \(minutes)-minute plate chose an arrangement its height does not justify")
            if layout == .stacked { sawStacked += 1; lastStacked = true } else {
                sawInline += 1
                #expect(!lastStacked, "a \(minutes)-minute plate dropped back to one row after gaining two")
            }
        }
        #expect(sawInline > 0 && sawStacked > 0, "non-vacuity: \(sawInline) inline, \(sawStacked) stacked")
    }

    /// The column draws the time in BOTH arrangements, and takes the arrangement from the shared
    /// decision rather than from a height gate of its own.
    @Test func theColumnDrawsThePlatesTimeAtEveryHeight() throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(timelineFile))
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: code)
        )
        let layer = try #require(
            CadenceSourceScan.declarationBody("private var taskDropHoverLayer: some View", in: column)
        )
        #expect(layer.count > 400, "non-vacuity: the plate layer read as \(layer.count) characters")
        #expect(
            CadenceSourceScan.matchCount(#"CadenceTimelineTaskDropHover\.labelLayout\("#, in: layer) == 1,
            "the plate picks its arrangement somewhere other than the shared decision"
        )
        #expect(CadenceSourceScan.matchCount(#"case \.stacked:"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"case \.inline:"#, in: layer) == 1)
        // The time is drawn in both arms. If it were gated on height here instead, this is the
        // count that would be 1.
        #expect(CadenceSourceScan.matchCount(#"taskDropHoverTime\(taskDropHover\)"#, in: layer) == 2,
                "the plate's time is not drawn in both arrangements")
        #expect(CadenceSourceScan.matchCount(#"taskDropHoverTitle\(task\)"#, in: layer) == 2,
                "the plate's title is not drawn in both arrangements")
        // And it is the CLOCK RANGE. The Mac preview's always-visible label is a *duration*
        // capsule -- "1h" -- which says a different fact from the one this plate lost ([[T-8456]]).
        let time = try #require(
            CadenceSourceScan.declarationBody("private func taskDropHoverTime(_ hover: CadenceTimelineTaskDropHover) -> some View", in: column)
        )
        #expect(CadenceSourceScan.matchCount(#"TimeFormatters\.timeRange\("#, in: time) == 1,
                "the plate's time label no longer states the range the release will write")
    }

    // The plate's own figures, mirrored from `iOSCalendarTimelineDayColumn` because a
    // macOS-built target cannot call into `Cadence/iOS/`, and pinned to that file by
    // `thePlateFiguresMirrorTheColumnsOwn` below.
    private var plateVerticalPadding: CGFloat { 4 }
    private var plateRowSpacing: CGFloat { 2 }
    private var plateTitleFontSize: CGFloat { 12 }
    private var plateTimeFontSize: CGFloat { 11 }

    /// Not mirrored any more: the column's `blockHeight` reads this nonisolated seam ([[T-8477]]),
    /// so the plate is measured with the very function that draws it.
    private func plateHeight(forMinutes minutes: Int) -> CGFloat {
        iOSCalendarTimelineBlockLayout.blockHeight(start: 0, end: minutes, hourHeight: hourHeight)
    }

    private func plateLabelLayout(forMinutes minutes: Int) -> CadenceTimelineTaskDropHover.LabelLayout {
        CadenceTimelineTaskDropHover.labelLayout(
            plateHeight: plateHeight(forMinutes: minutes),
            verticalPadding: plateVerticalPadding,
            rowSpacing: plateRowSpacing,
            titleFontSize: plateTitleFontSize,
            timeFontSize: plateTimeFontSize
        )
    }

    /// The mirror above is only worth anything while it still matches the column. Each figure is
    /// pinned to the literal in the view file, so a column that repaints its plate fails here
    /// rather than leaving the 15-minute reading measured against a plate that no longer exists.
    @Test func thePlateFiguresMirrorTheColumnsOwn() throws {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(timelineFile))
        let column = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarTimelineDayColumn: View", in: code)
        )
        let height = try #require(
            CadenceSourceScan.declarationBody("private func blockHeight(start: Int, end: Int) -> CGFloat", in: column)
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"iOSCalendarTimelineBlockLayout\.blockHeight\(start: start, end: end, hourHeight: hourHeight\)"#,
                in: height
            ) == 1,
            "the column's block height no longer reads the seam this suite measures the plate with"
        )
        let layer = try #require(
            CadenceSourceScan.declarationBody("private var taskDropHoverLayer: some View", in: column)
        )
        #expect(CadenceSourceScan.matchCount(#"verticalPadding: 4,"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"rowSpacing: 2,"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"base: 12, at: dynamicTypeSize, scaling: scaling\)"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"base: 11, at: dynamicTypeSize, scaling: scaling\)"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"\.padding\(\.vertical, 4\)"#, in: layer) == 1)
        #expect(CadenceSourceScan.matchCount(#"VStack\(alignment: \.leading, spacing: 2\)"#, in: layer) == 1)
    }

    // MARK: - [[T-8456]]: the Mac's dragged plate says what the iOS plate says

    /// **The defect.** `TimelineDraggedTaskPreview` drew the live block's body, whose height gates
    /// hide the clock range below 58 pt, so a 15-minute task dragged down the Mac canvas -- a plate
    /// floored at `minHeight` at every zoom -- stated its title and its duration capsule and never
    /// the range the drop would write. It now asks `CadenceTimelineTaskDropHover.labelLayout`, the
    /// decision the iOS plate asks ([[T-8455]]), so both platforms say the same thing at a height.
    ///
    /// Measured with the canvas's own `TimelineMetrics` and frame arithmetic at every zoom level,
    /// for both block styles, as a RELATION against the rows' own cost.
    @Test func atFifteenMinutesTheMacPlatePutsItsTitleAndItsTimeOnOneRow() {
        var sawInline = 0
        var sawStacked = 0
        for style in [TimelineBlockStyle.schedule, TimelineBlockStyle.calendar] {
            let stacked = CadenceTimelineTaskDropHover.stackedLabelHeight(
                verticalPadding: style.verticalPadding,
                rowSpacing: TimelineDraggedTaskPreview.plateRowSpacing,
                titleFontSize: TimelineDraggedTaskPreview.plateTitleFontSize,
                timeFontSize: TimelineDraggedTaskPreview.plateTimeFontSize
            )
            for viewport: CGFloat in [600, 900] {
                for level in TimelineZoom.levels {
                    let metrics = TimelineMetrics(
                        startHour: 0,
                        endHour: 24,
                        hourHeight: TimelineZoom.hourHeight(viewportHeight: viewport, level: level)
                    )
                    func frameHeight(_ minutes: Int) -> CGFloat {
                        computeTimelineBlockFrame(
                            startMinute: 9 * 60, durationMinutes: minutes, column: 0, totalColumns: 1,
                            totalWidth: 600, metrics: metrics, style: style
                        ).height
                    }
                    func layout(_ minutes: Int) -> CadenceTimelineTaskDropHover.LabelLayout {
                        TimelineDraggedTaskPreview.labelLayout(frameHeight: frameHeight(minutes), style: style)
                    }
                    let label = "viewport \(viewport), zoom \(level), hour \(metrics.hourHeight)"
                    if frameHeight(15) < stacked {
                        // The ticket's height: under the old 58 pt gate, and under two rows.
                        #expect(frameHeight(15) < 58, "non-vacuity: \(label)")
                        #expect(layout(15) == .inline, "a 15-minute plate dropped a row at \(label)")
                        #expect(
                            frameHeight(15) >= style.verticalPadding * 2
                                + CadenceCalendarOverlapLayout.lineHeight(forSystemFontSize: TimelineDraggedTaskPreview.plateTitleFontSize),
                            "the inline row does not fit a 15-minute plate either at \(label)"
                        )
                    }
                    var lastStacked = false
                    for minutes in stride(from: CadenceScheduleSupport.pointerTimeGridMinutes, through: 8 * 60, by: CadenceScheduleSupport.pointerTimeGridMinutes) {
                        let height = frameHeight(minutes)
                        let chosen = layout(minutes)
                        #expect(chosen == (height >= stacked ? .stacked : .inline),
                                "a \(minutes)-minute plate chose an arrangement its height does not justify at \(label)")
                        if chosen == .stacked { sawStacked += 1; lastStacked = true } else {
                            sawInline += 1
                            #expect(!lastStacked, "a \(minutes)-minute plate went back to one row at \(label)")
                        }
                    }
                }
            }
            // The ticket's own reading: at the deepest-out zoom on a short window a 15-minute
            // plate is the 24 pt floor, which cannot stack.
            let floor = TimelineMetrics(startHour: 0, endHour: 24, hourHeight: TimelineZoom.hourHeight(viewportHeight: 600, level: 1))
            let fifteen = computeTimelineBlockFrame(
                startMinute: 9 * 60, durationMinutes: 15, column: 0, totalColumns: 1,
                totalWidth: 600, metrics: floor, style: style
            )
            #expect(fifteen.height < stacked, "non-vacuity: a 15-minute plate now has room for two rows")
            #expect(TimelineDraggedTaskPreview.labelLayout(frameHeight: fifteen.height, style: style) == .inline)
        }
        #expect(sawInline > 0 && sawStacked > 0, "non-vacuity: \(sawInline) inline, \(sawStacked) stacked")
    }

    /// The preview hands the body the Shared decision, and the body's plate arm draws the title and
    /// the clock range in BOTH arrangements, with no height gate of its own.
    @Test func theMacPlateDrawsItsTitleAndRangeThroughTheSharedDecision() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift")
        )
        let preview = try #require(CadenceSourceScan.declarationBody("struct TimelineDraggedTaskPreview: View", in: mac))
        #expect(CadenceSourceScan.matchCount(#"CadenceTimelineTaskDropHover\.labelLayout\("#, in: preview) == 1)
        #expect(CadenceSourceScan.matchCount(#"dropPlateLabels: Self\.labelLayout\(frameHeight: frame\.height, style: style\)"#, in: preview) == 1,
                "the preview no longer hands its body the Shared arrangement")
        #expect(CadenceSourceScan.matchCount(#"verticalPadding: style\.verticalPadding,"#, in: preview) == 1)

        let body = try #require(CadenceSourceScan.functionBody(named: "timelineBlockBody", in: mac))
        let start = try #require(body.range(of: "if let dropPlateLabels {"), "the body has no plate arm")
        let end = try #require(body.range(of: "} else {", range: start.upperBound..<body.endIndex))
        let arm = String(body[start.lowerBound..<end.lowerBound])
        #expect(arm.count > 400, "non-vacuity: the plate arm read as \(arm.count) characters")
        #expect(CadenceSourceScan.matchCount(#"let plateRange = Text\(timeRangeLabel\)"#, in: arm) == 1,
                "the plate's time label no longer states the range the drop will write")
        #expect(CadenceSourceScan.matchCount(#"case \.stacked:"#, in: arm) == 1)
        #expect(CadenceSourceScan.matchCount(#"case \.inline:"#, in: arm) == 1)
        // Drawn in both arms. Gated on height here instead, these would be 1.
        #expect(CadenceSourceScan.matchCount(#"\bplateRange\b"#, in: arm) == 3,
                "the plate's range is not drawn in both arrangements")
        #expect(CadenceSourceScan.matchCount(#"\bplateTitle\b"#, in: arm) == 3,
                "the plate's title is not drawn in both arrangements")
        #expect(CadenceSourceScan.matchCount(#"frame\.height"#, in: arm) == 0,
                "the plate arm gates a label on height instead of on the Shared decision")
        // The rows drawn are the rows the decision costs.
        #expect(CadenceSourceScan.matchCount(#"TimelineDraggedTaskPreview\.plateTitleFontSize"#, in: arm) == 1)
        #expect(CadenceSourceScan.matchCount(#"TimelineDraggedTaskPreview\.plateTimeFontSize"#, in: arm) == 1)
        #expect(CadenceSourceScan.matchCount(#"spacing: TimelineDraggedTaskPreview\.plateRowSpacing"#, in: arm) == 1)
    }
}
#endif
