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
        // [[T-15486]]: the unfiltered read is the one that proves completeness.
        #expect(snapshot.completeStore == NotificationCompleteStoreRead(
            storeIdentity: ObjectIdentifier(container), taskIDs: [task.id]
        ))
        let injected = try CadenceForegroundNotificationSnapshot(container: container, fetch: { context in
            try context.fetch(FetchDescriptor<AppTask>())
        })
        #expect(injected.completeStore == nil, "an injected fetch may filter, so it proves nothing")
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
        let reconcile = try #require(active.range(of: "await NotificationManager.shared.reconcile(tasks: snapshot.tasks, completeStore: snapshot.completeStore)"))
        let lifetime = try #require(active.range(of: "withExtendedLifetime(snapshot) {}"))
        #expect(reconcile.upperBound <= lifetime.lowerBound)
        #expect(!active.contains("allTasksForNotifications"))
        #expect(!active.contains("tasks: []"))
        #expect(!active.contains(".id("))
        #expect(!active.contains("modelContext ="))
        // [[T-15462]] re-briefed this pin: leaving active used to read the root's notification
        // task query, which held pre-widget models, and re-armed a widget-completed reminder.
        #expect(!scene.contains("allTasksForNotifications"))
        let leaving = try #require(scene.range(of: "try? CadenceLeavingActiveNotificationInput(sceneContext: modelContext)"))
        let flush = try #require(scene.range(of: "flushPendingEditorContentOnLeavingActive("))
        #expect(flush.upperBound <= leaving.lowerBound, "the read must follow the flush that commits pending edits")
        #expect(scene.contains("await NotificationManager.shared.reconcile(tasks: input.tasks, completeStore: input.completeStore)"))
        #expect(!source.contains("@Query private var allTasksForNotifications"))
    }

    /// [[T-15461]] / [[T-15462]]: the leaving-active read must not reuse the scene context's
    /// registered models when another context over the same container has committed since.
    @Test func leavingActiveInputReadsTheOtherContextsCommittedCompletion() throws {
        let container = try CadenceTestStore.container()
        let scene = ModelContext(container)
        let task = AppTask(title: "Widget completion")
        scene.insert(task)
        try scene.save()
        let writer = ModelContext(container)
        let changed = try #require(writer.fetch(FetchDescriptor<AppTask>()).first)
        changed.statusRaw = "done"
        try writer.save()
        #expect(task.statusRaw == "todo", "non-vacuity: the scene's registered model must be stale")
        #expect(!scene.hasChanges)
        let input = try CadenceLeavingActiveNotificationInput(sceneContext: scene)
        let read = try #require(input.tasks.first)
        #expect(input.tasks.count == 1)
        #expect(read.id == task.id)
        #expect(read.statusRaw == "done")
        #expect(input.context !== scene)
        #expect(input.completeStore?.taskIDs == [task.id], "[[T-15486]]: the fresh path carries the proof")
    }

    /// A commit that failed leaves edits pending; dropping them from the diff would withdraw a
    /// reminder the user just set, so the scene's own context is read instead.
    @Test func leavingActiveInputKeepsTheSceneContextsUnsavedEdits() throws {
        let container = try CadenceTestStore.container()
        let scene = ModelContext(container)
        scene.autosaveEnabled = false
        let pending = AppTask(title: "Unsaved edit")
        scene.insert(pending)
        #expect(scene.hasChanges)
        let input = try CadenceLeavingActiveNotificationInput(sceneContext: scene)
        #expect(input.tasks.map(\.id) == [pending.id])
        #expect(input.context === scene)
        #expect(input.completeStore == nil, "[[T-15486]]: unsaved deletes may roll back, so this read proves nothing")
    }

    @Test func leavingActiveInputPropagatesFetchFailureOnBothPaths() throws {
        enum FetchFailure: Error { case refused }
        let container = try CadenceTestStore.container()
        let clean = ModelContext(container)
        #expect(throws: FetchFailure.self) {
            try CadenceLeavingActiveNotificationInput(sceneContext: clean, fetch: { _ in throw FetchFailure.refused })
        }
        let dirty = ModelContext(container)
        dirty.autosaveEnabled = false
        dirty.insert(AppTask(title: "Pending"))
        #expect(throws: FetchFailure.self) {
            try CadenceLeavingActiveNotificationInput(sceneContext: dirty, fetch: { _ in throw FetchFailure.refused })
        }
    }

    /// [[T-15461]]: the macOS observer reads through the context the window uses, on both arms.
    @Test func macOSNotificationObserverReadsTheWindowsCurrentContextFresh() throws {
        let source = try readCode("Cadence/macOS/macOSRootView.swift")
        #expect(source.contains(".background { NotificationReconcileObserver(sceneContext: currentModelContext) }"))
        let observer = try #require(CadenceSourceScan.declarationBody(
            "private struct NotificationReconcileObserver: View", in: source
        ))
        #expect(!observer.contains("@Query"), "a query here resolves against the window's original context")
        #expect(observer.contains("let sceneContext: ModelContext"))
        let scene = try #require(CadenceSourceScan.declarationBody(".onChange(of: scenePhase)", in: observer))
        let active = try #require(CadenceSourceScan.declarationBody("if phase == .active", in: scene))
        #expect(active.contains("try? CadenceForegroundNotificationSnapshot(container: container)"))
        #expect(active.contains("await NotificationManager.shared.reconcile(tasks: snapshot.tasks, completeStore: snapshot.completeStore)"))
        #expect(scene.contains("try? CadenceLeavingActiveNotificationInput(sceneContext: sceneContext)"))
        #expect(scene.contains("await NotificationManager.shared.reconcile(tasks: input.tasks, completeStore: input.completeStore)"))
        #expect(!scene.contains("tasks: []"))
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
            // The claim is the OBSERVED day, not the spelling: since [[T-8243]] the chip asks
            // `CadenceCalendarTaskDoneStyle.chipGlyphTint` for the whole ladder and hands it the
            // grid's `todayKey`, where it used to call `CadenceDueUrgency.evaluate` itself.
            let dense = chip.filter { !$0.isWhitespace }
            #expect(dense.contains("dueDateKey:task.dueDate,todayKey:todayKey"))
            #expect(chip.contains("CalendarChipDueMarker(dueDateKey: task.dueDate, dayKey: dayKey, todayKey: todayKey, isDone: task.isDone)"))
        }
        // [[T-10821]] moved the marker to `Shared/` so the iPad chip draws the same one.
        let sharedMarker = try read("Cadence/Shared/CadenceCalendarChipDueMarker.swift")
        let marker = try #require(CadenceSourceScan.declarationBody("struct CalendarChipDueMarker", in: sharedMarker))
        #expect(marker.contains("CadenceDueUrgency.evaluate(dueDateKey: dueDateKey, isDone: isDone, todayKey: todayKey)"))
        for file in ["TimelineDayCanvas.swift", "TimelineDayCanvasSupportLayers.swift", "TimelineTaskBlock.swift"] {
            let source = try read(prefix + file)
            #expect(source.contains("todayKey: todayKey,"), Comment(rawValue: file))
        }
        let block = try read(prefix + "TimelineTaskBlockSupportViews.swift")
        let rendering = try #require(CadenceSourceScan.functionBody(named: "timelineBlockBody", in: block))
        #expect(!rendering.contains("DateFormatters.todayKey()"))
        // [[T-13141]]: both due readings come from the one shared details value, handed the
        // observed day; iOS's block is handed its grid's `todayKey` the same way.
        #expect(rendering.contains("CadenceTimelineTaskBlockDetails.resolve(task: task, durationMinutes: durationMinutes, todayKey: todayKey)"))
        let details = try read("Cadence/Shared/CadenceTimelineTaskBlockDetails.swift")
        #expect(details.contains("CadenceDueUrgency.evaluate(dueDateKey: dueDateKey, isDone: isDone, todayKey: todayKey)"))
        #expect(details.contains("dueLabel(forDueDateKey: dueDateKey, todayKey: todayKey)"))
        let phone = try read("Cadence/iOS/iOSCalendarTimelineViews.swift")
        let phoneBlock = try #require(CadenceSourceScan.declarationBody("struct iOSTimelineTaskBlock: View", in: phone))
        #expect(phoneBlock.contains("CadenceTimelineTaskBlockDetails.resolve("))
        #expect(!phoneBlock.contains("DateFormatters.todayKey()"))
    }
}
