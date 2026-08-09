import Testing
@testable import Cadence

/// `sidebarDetail` feeds the focus "next up" rows and the focus picker. A due date must never be
/// silently dropped there — the old implementation returned the container name for an overdue task
/// and lost "due today" entirely whenever the task was also scheduled today.
struct FocusTaskDetailLineTests {
    private let todayKey = "2026-08-09"

    private func task(scheduled: String = "", due: String = "", container: String? = nil) -> AppTask {
        let task = AppTask(title: "Task")
        task.scheduledDate = scheduled
        task.dueDate = due
        if let container {
            task.area = Area(name: container)
        }
        return task
    }

    @Test func noDatesFallsBackToContainerThenFallbackText() {
        #expect(CadenceFocusSupport.sidebarDetail(for: task(container: "Roadmap"), todayKey: todayKey) == "Roadmap")
        #expect(CadenceFocusSupport.sidebarDetail(for: task(), todayKey: todayKey) == "Ready")
    }

    @Test func scheduledTodayWithoutDueDateKeepsSchedulingSignal() {
        let detail = CadenceFocusSupport.sidebarDetailParts(for: task(scheduled: todayKey, container: "Roadmap"), todayKey: todayKey)

        #expect(detail.text == "Scheduled today")
        #expect(detail.due == nil)
        #expect(detail.isOverdue == false)
    }

    @Test func dueTodaySurvivesAlongsideScheduledToday() {
        #expect(CadenceFocusSupport.sidebarDetail(for: task(due: todayKey), todayKey: todayKey) == "Due today")
        #expect(
            CadenceFocusSupport.sidebarDetail(for: task(scheduled: todayKey, due: todayKey), todayKey: todayKey)
                == "Scheduled today / Due today"
        )
    }

    @Test func overdueWinsOverContainerNameAndIsFlaggedForTinting() {
        let detail = CadenceFocusSupport.sidebarDetailParts(for: task(due: "2026-08-02", container: "Roadmap"), todayKey: todayKey)

        #expect(detail.text == "Overdue Aug 2")
        #expect(detail.isOverdue)

        let scheduledToo = CadenceFocusSupport.sidebarDetailParts(for: task(scheduled: todayKey, due: "2026-08-02"), todayKey: todayKey)

        #expect(scheduledToo.text == "Scheduled today / Overdue Aug 2")
        #expect(scheduledToo.isOverdue)
    }

    @Test func futureDueDateShowsTheRealDateInsteadOfTheContainerName() {
        #expect(
            CadenceFocusSupport.sidebarDetail(for: task(due: "2026-08-10", container: "Roadmap"), todayKey: todayKey)
                == "Due tomorrow"
        )
        #expect(
            CadenceFocusSupport.sidebarDetail(for: task(due: "2026-08-14", container: "Roadmap"), todayKey: todayKey)
                == "Due Aug 14"
        )
        #expect(
            CadenceFocusSupport.sidebarDetail(for: task(due: "2026-09-30", container: "Roadmap"), todayKey: todayKey)
                == "Due Sep 30"
        )
    }

    @Test func dueLabelReturnsNilOnlyWhenThereIsNoDueDate() {
        #expect(CadenceFocusSupport.dueLabel(forDueDateKey: "", todayKey: todayKey) == nil)
        #expect(CadenceFocusSupport.dueLabel(forDueDateKey: todayKey, todayKey: todayKey) == "Due today")
        #expect(CadenceFocusSupport.isOverdue(dueDateKey: "", todayKey: todayKey) == false)
    }
}
