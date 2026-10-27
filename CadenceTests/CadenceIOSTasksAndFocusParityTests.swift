import Foundation
import Testing
@testable import Cadence

/// T-7014: the merged Tasks page's header badge — one number for both shells.
///
/// macOS spelled the arithmetic inline and the iOS header passed no count at all. The rule is a
/// function now, and the iOS half is pinned by reading the source, because `Cadence/iOS/` is
/// inside `#if os(iOS)` and invisible to this macOS-built target.
struct CadenceTasksPageHeaderCountTests {
    private func task(done: Bool = false, cancelled: Bool = false, area: Area? = nil) -> AppTask {
        let task = AppTask(title: "Task")
        if done { task.status = .done }
        if cancelled { task.status = .cancelled }
        task.area = area
        return task
    }

    private var fixture: [AppTask] {
        let active = Area(name: "Work")
        let archived = Area(name: "Old")
        archived.statusRaw = "archived"
        return [
            task(),                      // open, inbox
            task(),                      // open, inbox
            task(done: true),            // finished, inbox
            task(cancelled: true),       // cancelled, inbox
            task(area: active),          // open, filed in an active list
            task(area: archived),        // open, filed in an archived list
        ]
    }

    @Test func allTasksCountsOpenWorkInActiveListsAndIgnoresReminders() {
        let count = CadenceTaskQuerySupport.tasksPageHeaderCount(scope: .all, tasks: fixture, reminderCount: 5)
        // Two open inbox tasks and the one in the active area; the archived area's is not counted,
        // and Apple Reminders belong to the Inbox only.
        #expect(count == 3)
    }

    @Test func inboxCountsOpenUnfiledTasksPlusTheAppleReminders() {
        #expect(CadenceTaskQuerySupport.tasksPageHeaderCount(scope: .inbox, tasks: fixture, reminderCount: 0) == 2)
        #expect(CadenceTaskQuerySupport.tasksPageHeaderCount(scope: .inbox, tasks: fixture, reminderCount: 4) == 6)
    }

    @Test func theIOSTasksPageHeaderPassesTheSharedCount() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTasksPageView.swift")
        )
        let row = try #require(
            CadenceSourceScan.declarationBody("private func headerRow(", in: source),
            "the header row has moved — this pin is unanchored"
        )
        #expect(row.contains("iOSPageHeader("), "non-vacuity: wrong declaration")
        #expect(row.contains("count: count"), "the iOS Tasks header draws no count badge again")

        let reader = try #require(
            CadenceSourceScan.declarationBody("private struct iOSTasksPageHeaderCount", in: source)
        )
        #expect(reader.contains("CadenceTaskQuerySupport.tasksPageHeaderCount("))
        #expect(reader.contains("reminderCount: remindersManager.reminders.count"))

        let header = try #require(CadenceSourceScan.declarationBody("private var header: some View", in: source))
        #expect(header.contains("iOSTasksPageHeaderCount(scope: scope)"))
        #expect(header.contains("headerRow(count: count"))
    }

    /// T-7021: macOS's header reads the same function rather than its own copy of the arithmetic.
    @Test func theMacTasksPageHeaderPassesTheSharedCount() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/macOSRootSupportViews.swift")
        )
        let count = try #require(
            CadenceSourceScan.declarationBody("private var headerCount: Int", in: source),
            "the Mac header count has moved — this pin is unanchored"
        )
        #expect(count.contains("CadenceTaskQuerySupport.tasksPageHeaderCount("), "got: \(count)")
        #expect(count.contains("reminderCount: remindersManager.reminders.count"))
        #expect(!count.contains("openTaskCount("), "macOS spells the header arithmetic inline again")
        #expect(source.contains("count: headerCount"), "the Mac Tasks header no longer draws this count")
    }
}

/// T-7015: iOS Inbox draws its Apple Reminders between the open tasks and the Completed logbook,
/// the order macOS's `TasksListView` draws — not under the finished work.
struct CadenceIOSInboxRemindersOrderTests {
    @Test func remindersSitBetweenActiveAndCompleted() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskCollectionPage.swift")
        )
        let groupStack = try #require(
            CadenceSourceScan.declarationBody("private var groupStack: some View", in: source)
        )
        let active = try #require(groupStack.range(of: "iOSTaskGroupSection("), "non-vacuity: no Active section")
        let reminders = try #require(
            groupStack.range(of: "iOSInboxRemindersSection(remindersManager: remindersManager)"),
            "the Reminders section is no longer placed by the group stack"
        )
        let completed = try #require(groupStack.range(of: "iOSCompletedTasksSection("), "non-vacuity: no Completed section")
        #expect(active.upperBound <= reminders.lowerBound, "Reminders drawn above the open tasks")
        #expect(reminders.upperBound <= completed.lowerBound, "Reminders drawn below the Completed logbook")
        #expect(groupStack.contains("if showsRemindersSection"), "the section is no longer gated")

        // Exactly one placement in the file: a second call left in `scrollBody` would draw the
        // section twice, once in each order.
        #expect(CadenceSourceScan.matchCount(#"iOSInboxRemindersSection\("#, in: source) == 1)

        let scrollBody = try #require(
            CadenceSourceScan.declarationBody("private func scrollBody(proxy: ScrollViewProxy) -> some View", in: source)
        )
        #expect(scrollBody.contains("showsRemindersSection: showsRemindersSection"), "the page stopped handing the gate down")
    }
}

/// T-7017: the Focus picker row's detail line — "Ready to focus" when there is nothing else to say,
/// and drawn by the shared label that tints an overdue date red.
struct CadenceFocusPickRowDetailTests {
    private let todayKey = "2026-08-09"

    @Test func anUndatedUnfiledTaskSaysReadyToFocus() {
        let parts = CadenceFocusSupport.pickRowDetailParts(for: AppTask(title: "Task"), todayKey: todayKey)
        #expect(parts.text == "Ready to focus")
        #expect(parts.isOverdue == false)
    }

    @Test func anOverdueTaskIsFlaggedForTheRedSegment() {
        let task = AppTask(title: "Task")
        task.dueDate = "2026-08-02"
        let parts = CadenceFocusSupport.pickRowDetailParts(for: task, todayKey: todayKey)
        #expect(parts.due == "Overdue Aug 2")
        #expect(parts.isOverdue)
    }

    @Test func bothPickerRowsDrawTheSharedLabel() throws {
        let ios = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift"))
        let row = try #require(CadenceSourceScan.declarationBody("private struct iOSFocusPickRow: View", in: ios))
        #expect(row.contains("let detail: CadenceTaskDetailLine"))
        #expect(row.contains("CadenceTaskDetailLineLabel(parts: detail, fontSize: 11)"), "the iOS pick row prints plain text again")
        #expect(!row.contains("Text(detail"))
        let detail = try #require(CadenceSourceScan.declarationBody("private func detail(of item: CadenceFocusPickItem)", in: ios))
        #expect(detail.contains("CadenceFocusSupport.pickRowDetailParts(for: task, todayKey: todayKey)"))

        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusPickerSupportViews.swift")
        )
        #expect(mac.contains("CadenceTaskDetailLineLabel(task: task, fallback: CadenceFocusSupport.pickRowFallback, fontSize: 11)"))
    }
}

/// T-7018: the Focus timer card names three states, not two. A session nobody has started reads
/// "Ready" over `00:00`, matching the "N ready" eyebrow above it, instead of "Paused".
struct CadenceFocusTimerPhaseTests {
    @Test func aNeverStartedSessionIsReadyNotPaused() {
        let phase = CadenceFocusTimerPhase(isRunning: false, elapsedSeconds: 0)
        #expect(phase == .ready)
        #expect(phase.label == "Ready")
        #expect(phase.systemImage == "play.circle")
    }

    @Test func aStoppedSessionThatHasCountedIsPaused() {
        let phase = CadenceFocusTimerPhase(isRunning: false, elapsedSeconds: 1)
        #expect(phase == .paused)
        #expect(phase.label == "Paused")
        #expect(phase.systemImage == "pause.circle")
    }

    @Test func aRunningSessionIsRunningEvenAtZero() {
        #expect(CadenceFocusTimerPhase(isRunning: true, elapsedSeconds: 0) == .running)
        #expect(CadenceFocusTimerPhase(isRunning: true, elapsedSeconds: 90).label == "Running")
        #expect(CadenceFocusTimerPhase(isRunning: true, elapsedSeconds: 90).systemImage == "timer")
    }

    @Test func bothTimerCardsAndTheEyebrowReadTheSharedPhase() throws {
        let ios = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift"))
        let panel = try #require(CadenceSourceScan.declarationBody("private struct iOSFocusTimerPanel<Clock: View, Controls: View>: View", in: ios))
        #expect(panel.contains("Text(phase.label)"), "the iOS card spells its own state words again")
        #expect(!panel.contains("\"Paused\""))
        let eyebrow = try #require(CadenceSourceScan.declarationBody("private var statusEyebrow: String", in: ios))
        #expect(eyebrow.contains("CadenceFocusTimerPhase(isRunning: timerState.isRunning, elapsedSeconds: elapsedSeconds)"))
        #expect(ios.contains("phase: CadenceFocusTimerPhase(isRunning: timerState.isRunning, elapsedSeconds: elapsedSeconds)"))

        let mac = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusChromeSupportViews.swift"))
        let macPanel = try #require(CadenceSourceScan.declarationBody("struct FocusTimerPanel<Controls: View>: View", in: mac))
        #expect(macPanel.contains("Label(phase.label, systemImage: phase.systemImage)"))
        #expect(!macPanel.contains("\"Paused\""))
    }
}

/// T-7089: the iPhone Focus picker row lets a long task title take two lines, the task-row title
/// rule, instead of cutting it at ~30 characters on a 393 pt phone.
struct CadenceFocusPickRowTitleTests {
    @Test func theIOSPickRowTitleWrapsToTwoLeadingLines() throws {
        let ios = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift"))
        let row = try #require(CadenceSourceScan.declarationBody("private struct iOSFocusPickRow: View", in: ios))
        // Bounded by the detail label below it, not a character count: comments are blanked to
        // equal-width spaces, so a prefix length would count the comment explaining the rule.
        let title = try #require(row.range(of: "Text(title)"))
        let detail = try #require(row.range(of: "CadenceTaskDetailLineLabel(", range: title.upperBound..<row.endIndex))
        let afterTitle = String(row[title.upperBound..<detail.lowerBound])
        #expect(afterTitle.contains(".lineLimit(2)"), "the pick row cuts a title at one line again")
        #expect(afterTitle.contains(".multilineTextAlignment(.leading)"))
        #expect(!afterTitle.contains(".lineLimit(1)"))
    }
}
