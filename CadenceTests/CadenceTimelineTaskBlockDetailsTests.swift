import Foundation
import Testing
@testable import Cadence

/// [[T-13141]]: a scheduled task's timeline block prints one details line -- actual/estimate and
/// the deadline -- on both platforms, from one value. iOS's block printed neither, so an overdue
/// task in today's timeline read as overdue on a Mac and as on track on an iPhone.
@MainActor
struct CadenceTimelineTaskBlockDetailsTests {
    private let today = "2026-11-07"

    @Test func anOverdueTaskCarriesItsDeadlineInThePrimaryTier() {
        let details = CadenceTimelineTaskBlockDetails.resolve(
            actualMinutes: 0, durationMinutes: 30, dueDateKey: "2026-11-05", isDone: false, todayKey: today
        )
        #expect(details.durationLabel == "-/30m")
        #expect(details.dueLabel?.hasPrefix("Overdue ") == true)
        #expect(details.dueIsUrgent)
        #expect(!details.isEmpty)
    }

    @Test func aTaskDueTodayIsUrgentAndOneDueLaterIsNot() {
        let dueToday = CadenceTimelineTaskBlockDetails.resolve(
            actualMinutes: 15, durationMinutes: 60, dueDateKey: today, isDone: false, todayKey: today
        )
        #expect(dueToday.dueLabel == "Due today")
        #expect(dueToday.dueIsUrgent)
        #expect(dueToday.durationLabel == "15m/1h")

        let later = CadenceTimelineTaskBlockDetails.resolve(
            actualMinutes: 0, durationMinutes: 60, dueDateKey: "2026-11-20", isDone: false, todayKey: today
        )
        #expect(later.dueLabel != nil)
        #expect(!later.dueIsUrgent)
    }

    /// A finished block stops shouting: `CadenceDueUrgency` collapses a done task to `.later`, and
    /// [[T-15522]] its words stop claiming lateness too -- "Due Nov 5", not "Overdue Nov 5".
    @Test func aFinishedOverdueTaskSaysDueAndLeavesThePrimaryTier() {
        let details = CadenceTimelineTaskBlockDetails.resolve(
            actualMinutes: 0, durationMinutes: 30, dueDateKey: "2026-11-05", isDone: true, todayKey: today
        )
        #expect(details.dueLabel?.hasPrefix("Due ") == true)
        #expect(details.dueLabel?.hasPrefix("Overdue ") == false)
        #expect(!details.dueIsUrgent)
    }

    @Test func noDeadlineAndNoKnownDurationPrintsNoLine() {
        let details = CadenceTimelineTaskBlockDetails.resolve(
            actualMinutes: 0, durationMinutes: 0, dueDateKey: "", isDone: false, todayKey: today
        )
        #expect(details.durationLabel == nil)
        #expect(details.dueLabel == nil)
        #expect(!details.dueIsUrgent)
        #expect(details.isEmpty)
    }

    /// Both blocks read the one value. iOS sits behind `#if os(iOS)`, which this target does not
    /// compile, so its half is a source pin; the Mac half is too, for symmetry and so neither can
    /// drift back to a private copy of the facts.
    @Test func bothTimelineTaskBlocksReadTheSharedDetails() throws {
        let ios = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarTimelineViews.swift")
        let iosFace = try #require(CadenceSourceScan.declarationBody("private var blockFace: some View", in: ios))
        #expect(iosFace.contains("CadenceTimelineTaskBlockDetails.resolve("))
        #expect(iosFace.contains("titleAndRange(details: details)"))
        let iosLine = try #require(CadenceSourceScan.functionBody(named: "titleAndRange", in: ios))
        #expect(iosLine.contains("details.dueLabel"))
        #expect(iosLine.contains("details.durationLabel"))
        #expect(iosLine.contains("details.dueIsUrgent ? primaryInk : secondaryInk"))

        let mac = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift")
        let macBody = try #require(CadenceSourceScan.functionBody(named: "timelineBlockBody", in: mac))
        #expect(macBody.contains("CadenceTimelineTaskBlockDetails.resolve("))
        #expect(!macBody.contains("CadenceDueUrgency.evaluate("))
    }
}
