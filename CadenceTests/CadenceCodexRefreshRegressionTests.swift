import Foundation
import Testing
import SwiftData
@testable import Cadence

@MainActor
struct CadenceCodexRefreshRegressionTests {
    private func readCode(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    @Test func codexForegroundSnapshotReadsTheOtherContextsCommittedCompletion() throws {
        let container = try CadenceTestStore.container()
        let original = ModelContext(container)
        let task = AppTask(title: "External completion")
        original.insert(task)
        try original.save()
        let writer = ModelContext(container)
        let changed = try #require(writer.fetch(FetchDescriptor<AppTask>()).first)
        changed.statusRaw = "done"
        try writer.save()
        #expect(task.statusRaw == "todo", "non-vacuity: the original registered model must be stale")
        let snapshot = try CadenceForegroundNotificationSnapshot(container: container)
        let read = try #require(snapshot.tasks.first)
        #expect(read.id == task.id)
        #expect(read.statusRaw == "done")
        #expect(read.modelContext === snapshot.context)
        #expect(snapshot.context !== original)
    }

    @Test func codexForegroundSnapshotPropagatesFetchFailureInsteadOfReturningNoTasks() throws {
        enum FetchFailure: Error { case refused }
        let container = try CadenceTestStore.container()
        #expect(throws: FetchFailure.self) {
            try CadenceForegroundNotificationSnapshot(container: container, fetch: { _ in
                throw FetchFailure.refused
            })
        }
    }

    @Test func codexForegroundReconcileUsesTheSnapshotAndKeepsItAliveWithoutReplacingUIState() throws {
        let source = try readCode("Cadence/iOS/iOSRootView.swift")
        let scene = try #require(CadenceSourceScan.declarationBody(".onChange(of: scenePhase)", in: source))
        let active = try #require(CadenceSourceScan.declarationBody("if phase == .active", in: scene))
        #expect(active.contains("let container = modelContext.container"))
        #expect(active.contains("try CadenceForegroundNotificationSnapshot(container: container)"))
        let reconcile = try #require(active.range(of: "await NotificationManager.shared.reconcile(tasks: snapshot.tasks)"))
        let lifetime = try #require(active.range(of: "withExtendedLifetime(snapshot) {}"))
        #expect(reconcile.upperBound <= lifetime.lowerBound)
        #expect(!active.contains("allTasksForNotifications"))
        #expect(!active.contains("tasks: []"))
        #expect(!active.contains(".id("))
        #expect(!active.contains("modelContext ="))
        #expect(scene.contains("let tasks = allTasksForNotifications"), "Leaving active still includes pending in-process edits")
    }

    @Test func codexCompactNavigationBindingsProjectThroughWritableKeyPaths() throws {
        let read = readCode
        let shell = try read("Cadence/iOS/iOSCompactTabShell.swift")
        let root = try read("Cadence/iOS/iOSRootView.swift")
        let path = try #require(CadenceSourceScan.functionBody(named: "pathBinding", in: shell))
        #expect(path.contains("$paths[dynamicMember: \\.[tab]]"))
        #expect(!path.contains("Binding("))
        #expect(root.contains("tasksSection: $tasksSectionRaw.compactTasksSection"))
        let projection = try #require(CadenceSourceScan.declarationBody(
            "var compactTasksSection: CadenceTasksSection", in: root
        ))
        #expect(projection.contains("CadenceTasksSection.resolved(self)"))
        #expect(projection.contains("self = newValue.rawValue"))
        #expect(!projection.contains("Binding("))
    }

    @Test func codexTodayOwnsNoDismissEnvironmentAndPassesTheReadersBackAction() throws {
        let source = try readCode("Cadence/iOS/iOSTodayCompactViews.swift")
        let view = try #require(CadenceSourceScan.declarationBody("struct iOSCompactTodayView", in: source))
        #expect(!view.contains("@Environment(\\.dismiss)"))
        let header = try #require(CadenceSourceScan.declarationBody("var header: some View", in: view))
        #expect(header.contains("iOSCompactBackActionReader { onBack in"))
        #expect(header.contains("iOSCompactPageHeader("))
        #expect(header.contains("onBack: onBack"))
        #expect(!header.contains("dismiss()"))
    }

    @Test nonisolated func codexSavedLinkNormalizationIsCallableOffTheMainActor() async {
        let values = await Task.detached {
            [" HTTPS://Example.com ", "example.com", "   "].map(CadenceSavedLinkURL.normalized)
        }.value
        #expect(values == ["HTTPS://Example.com", "https://example.com", nil])
    }

    @Test func codexCalendarObservesTheDayInlineWithoutRemountingItsPage() throws {
        let source = try readCode("Cadence/macOS/Views/CalendarPageView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct CalendarPageView", in: source))
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: page))
        #expect(page.contains("@State private var observedDay = CadenceObservedDay()"))
        #expect(body.components(separatedBy: ".cadenceTracksDayChanges($observedDay)").count == 2)
        #expect(body.contains("MonthGridView(\n                    todayKey: observedDay.todayKey,"))
        #expect(body.contains("CalendarTimelineViewport(\n                        todayKey: observedDay.todayKey,"))
        #expect(!body.contains(".id(observedDay"))
    }

    @Test func codexCalendarMonthAndTimelineForwardTheObservedDayToTheirLeaves() throws {
        let read = readCode
        let prefix = "Cadence/macOS/Views/"
        let components = try read(prefix + "CalendarPageComponents.swift")
        let month = try read(prefix + "CalendarPageMonthSupportViews.swift")
        let support = try read(prefix + "CalendarPageSupportViews.swift")
        let scroller = try read(prefix + "CalendarTimelineViewportSupportViews.swift")
        for (source, declarations) in [
            (components, ["struct MonthGridView", "struct MonthWeeksView"]),
            (support, ["struct CalendarTimelineHeaderStrip", "struct CalendarTimelineViewport"]),
            (scroller, ["struct CalendarTimelineDayScroller"]),
            (month, ["struct CalDayColumn"]),
        ] {
            for declaration in declarations {
                let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
                #expect(body.contains("let todayKey: String"))
                #expect(body.contains("todayKey: todayKey,"))
            }
        }
        let cell = try #require(CadenceSourceScan.declarationBody("struct MonthDayCell", in: month))
        #expect(cell.contains("today: DateFormatters.date(from: todayKey) ?? Date()"))
        let header = try #require(CadenceSourceScan.declarationBody("struct CalDayHeaderView", in: month))
        #expect(header.contains("DateFormatters.dateKey(from: date) == todayKey"))
        #expect(!header.contains("isDateInToday("))
        #expect(cell.contains("MonthTaskChip(task: task, dayKey: dateKey, todayKey: todayKey)"))
        #expect(header.contains("AllDayTaskChip(task: task, dayKey: DateFormatters.dateKey(from: date), todayKey: todayKey)"))
        for declaration in ["struct MonthTaskChip", "struct AllDayTaskChip"] {
            let chip = try #require(CadenceSourceScan.declarationBody(declaration, in: month))
            #expect(chip.contains("dueDateKey: task.dueDate, isDone: task.isDone, todayKey: todayKey"))
            #expect(chip.contains("CalendarChipDueMarker(dueDateKey: task.dueDate, dayKey: dayKey, todayKey: todayKey, isDone: task.isDone)"))
        }
        let marker = try #require(CadenceSourceScan.declarationBody("struct CalendarChipDueMarker", in: month))
        #expect(marker.contains("CadenceDueUrgency.evaluate(dueDateKey: dueDateKey, isDone: isDone, todayKey: todayKey)"))
        for file in ["TimelineDayCanvas.swift", "TimelineDayCanvasSupportLayers.swift", "TimelineTaskBlock.swift"] {
            let source = try read(prefix + file)
            #expect(source.contains("todayKey: todayKey,"), Comment(rawValue: file))
        }
        let block = try read(prefix + "TimelineTaskBlockSupportViews.swift")
        let rendering = try #require(CadenceSourceScan.functionBody(named: "timelineBlockBody", in: block))
        #expect(!rendering.contains("DateFormatters.todayKey()"))
        #expect(rendering.contains("dueDateKey: task.dueDate, isDone: task.isDone, todayKey: todayKey"))
        #expect(rendering.contains("dueLabel(forDueDateKey: task.dueDate, todayKey: todayKey)"))
    }
}
