#if os(macOS)
import Foundation
import SwiftUI
import SwiftData

/// Global planning surface. Unlike the retired per-list planning tab, this page spans
/// every active list and buckets open work by date: Overdue / Today / This Week /
/// Later / Unscheduled. Cards are draggable between buckets to reschedule.
struct PlanningPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    @State private var targetedBucket: PlanningBucket?

    private var todayKey: String { DateFormatters.todayKey() }

    private var weekEndKey: String {
        PlanningBucket.weekEndKey(from: todayKey)
    }

    /// Tasks that are open and live inside a list the user still cares about.
    /// Mirrors the All Tasks universe so archived/completed lists stay out of the way.
    private var openTasks: [AppTask] {
        CadenceTaskQuerySupport.openTasks(from: allTasks.filter(isTaskInActiveContainer))
    }

    private var bucketedTasks: [PlanningBucket: [AppTask]] {
        let todayKey = todayKey
        let weekEndKey = weekEndKey
        var buckets: [PlanningBucket: [AppTask]] = [:]
        for task in openTasks {
            let bucket = PlanningBucket.bucket(for: task, todayKey: todayKey, weekEndKey: weekEndKey)
            buckets[bucket, default: []].append(task)
        }
        return buckets.mapValues { $0.sorted(by: planningTaskSort) }
    }

    var body: some View {
        let buckets = bucketedTasks

        VStack(alignment: .leading, spacing: 0) {
            header(buckets: buckets)

            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(PlanningBucket.allCases) { bucket in
                        PlanningBucketColumn(
                            bucket: bucket,
                            tasks: buckets[bucket] ?? [],
                            isTargeted: targetedBucket == bucket,
                            onAddTask: { presentTaskCreation(in: bucket) }
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .modifier(PlanningBucketDropModifier(
                            bucket: bucket,
                            onDrop: { items in reschedule(items: items, into: bucket) },
                            onTargetChange: { isTargeted in
                                if isTargeted {
                                    targetedBucket = bucket
                                } else if targetedBucket == bucket {
                                    targetedBucket = nil
                                }
                            }
                        ))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .cadenceSoftPageBounce()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
        .background(Theme.bg)
    }

    private func header(buckets: [PlanningBucket: [AppTask]]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Planning")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.text)

            Text(summaryLine(buckets: buckets))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func summaryLine(buckets: [PlanningBucket: [AppTask]]) -> String {
        let unscheduled = buckets[.unscheduled]?.count ?? 0
        let overdue = buckets[.overdue]?.count ?? 0
        return "\(unscheduled) unscheduled · \(overdue) overdue"
    }

    // MARK: - Drag / drop

    /// Every accepted drop writes the task's do date — the only field the page buckets on —
    /// so the card always lands in the column it was dropped on.
    private func reschedule(items: [String], into bucket: PlanningBucket) -> Bool {
        guard let action = bucket.dropAction(todayKey: todayKey),
              let task = task(from: items) else { return false }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            switch action {
            case .setDoDate(let dateKey):
                task.scheduledDate = dateKey
            case .clearDoDate:
                task.scheduledDate = ""
                task.scheduledStartMin = -1
            }
        }
        try? modelContext.save()
        return true
    }

    private func task(from items: [String]) -> AppTask? {
        guard let payload = items.first,
              let taskID = TasksPanelSupport.taskID(from: payload) else { return nil }
        return openTasks.first { $0.id == taskID }
    }

    // MARK: - Creation

    private func presentTaskCreation(in bucket: PlanningBucket) {
        taskCreationManager.present(doDateKey: bucket.seedDoDateKey(todayKey: todayKey))
    }

    // MARK: - Helpers

    private func isTaskInActiveContainer(_ task: AppTask) -> Bool {
        if let project = task.project { return project.isActive }
        if let area = task.area { return area.isActive }
        return true
    }

    /// Carried over from the retired per-list planning view: order by the task's date
    /// anchor, then its timeline slot, then priority, then manual order.
    private func planningTaskSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        let lhsKey = planningAnchorKey(for: lhs)
        let rhsKey = planningAnchorKey(for: rhs)
        if lhsKey != rhsKey { return lhsKey < rhsKey }

        if lhs.scheduledStartMin != rhs.scheduledStartMin {
            if lhs.scheduledStartMin < 0 { return false }
            if rhs.scheduledStartMin < 0 { return true }
            return lhs.scheduledStartMin < rhs.scheduledStartMin
        }

        let lhsPriority = taskPriorityRank(lhs.priority)
        let rhsPriority = taskPriorityRank(rhs.priority)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }

        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func planningAnchorKey(for task: AppTask) -> String {
        PlanningBucket.anchorKey(for: task) ?? "9999-99-99"
    }
}

/// Applies the drop destination only to buckets that can accept one. Overdue is a
/// derived state — dropping a task "into overdue" has no sensible meaning — so it is
/// intentionally not a drop target.
private struct PlanningBucketDropModifier: ViewModifier {
    let bucket: PlanningBucket
    let onDrop: ([String]) -> Bool
    let onTargetChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if bucket.acceptsDrops {
            content
                .dropDestination(for: String.self) { items, _ in
                    onDrop(items)
                } isTargeted: { isTargeted in
                    onTargetChange(isTargeted)
                }
        } else {
            content
        }
    }
}
#endif
