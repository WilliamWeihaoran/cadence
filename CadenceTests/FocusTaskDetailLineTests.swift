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

    /// **[[T-17044]].** A blank-named list is named, as its list chip, the sidebar and Search
    /// ([[T-16940]]) name it -- not dropped to "Ready" in the row and to no chip in the header.
    @Test func aBlankNamedListIsNamedTheWayEverySurfaceNamesIt() {
        #expect(CadenceFocusSupport.sidebarDetail(for: task(container: ""), todayKey: todayKey) == "Untitled Area")
        #expect(CadenceFocusSupport.sidebarDetail(for: task(container: "   "), todayKey: todayKey) == "Untitled Area")
        #expect(CadenceFocusSupport.listName(for: task(container: "")) == CadenceTitleNormalization.defaultAreaName)

        let inProject = AppTask(title: "Task")
        inProject.project = Project(name: "")
        #expect(CadenceFocusSupport.listName(for: inProject) == CadenceTitleNormalization.defaultProjectName)
        #expect(CadenceFocusSupport.pickRowDetailParts(for: inProject, todayKey: todayKey).text == "Untitled Project")

        // Project before area, the filing rule `containerName` reads.
        let dualFiled = AppTask(title: "Task")
        dualFiled.area = Area(name: "Home")
        dualFiled.project = Project(name: "Roadmap")
        #expect(CadenceFocusSupport.listName(for: dualFiled) == "Roadmap")
    }

    /// An Inbox task names no list: the header draws no chip and the row keeps its fallback.
    @Test func anInboxTaskNamesNoList() {
        #expect(CadenceFocusSupport.listName(for: task()) == nil)
        #expect(CadenceFocusSupport.pickRowDetailParts(for: task(), todayKey: todayKey).text == CadenceFocusSupport.pickRowFallback)
    }

    /// Both session headers read the shared name rather than the raw `containerName`. A scan: the
    /// headers are views, and the iOS one is behind `#if os(iOS)`.
    @Test func bothFocusSessionHeadersReadTheSharedListName() throws {
        for (path, declaration) in [
            ("Cadence/macOS/Views/FocusChromeSupportViews.swift", "struct FocusSessionHeader: View"),
            ("Cadence/iOS/iOSFocusView.swift", "private func selectedTaskHeader(_ task: AppTask) -> some View"),
        ] {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            let header = try #require(CadenceSourceScan.declarationBody(declaration, in: source), "\(path)")
            #expect(header.contains("CadenceFocusSupport.listName(for: task)"), "\(path)")
            #expect(!header.contains("containerName"), "\(path) names the list from the raw containerName again")
        }
    }

    @Test func dueLabelReturnsNilOnlyWhenThereIsNoDueDate() {
        #expect(CadenceFocusSupport.dueLabel(forDueDateKey: "", todayKey: todayKey) == nil)
        #expect(CadenceFocusSupport.dueLabel(forDueDateKey: todayKey, todayKey: todayKey) == "Due today")
        #expect(CadenceFocusSupport.isOverdue(dueDateKey: "", todayKey: todayKey) == false)
    }
}
