import Foundation

nonisolated struct CadenceContextRef: Codable, Sendable {
    let id: String
    let name: String
    let colorHex: String
    let icon: String
    let order: Int
    let isArchived: Bool
    let areaCount: Int
    let projectCount: Int
    let activeTaskCount: Int
    let goalCount: Int
    let habitCount: Int
}

nonisolated struct CadenceContainerRef: Codable, Sendable {
    let kind: String
    let id: String
    let name: String
    let contextId: String?
    let contextName: String?
    let status: String
    let colorHex: String
    let icon: String
}

nonisolated struct CadenceGoalRef: Codable, Sendable {
    let id: String
    let title: String
    let status: String
    let progress: Double
}

nonisolated struct CadenceSubtaskSummary: Codable, Sendable {
    let id: String
    let title: String
    let isDone: Bool
    let order: Int
}

nonisolated struct CadenceTagSummary: Codable, Sendable {
    let id: String
    let slug: String
    let name: String
    let colorHex: String
    let description: String
    let isArchived: Bool
}

nonisolated struct CadenceTaskSummary: Codable, Sendable {
    let id: String
    let title: String
    let status: String
    let priority: String
    let dueDate: String
    let scheduledDate: String
    let scheduledStartMin: Int
    let estimatedMinutes: Int
    let container: CadenceContainerRef?
    let goal: CadenceGoalRef?
    let sectionName: String
    let tags: [CadenceTagSummary]
    let isDone: Bool
    let isCancelled: Bool
}

nonisolated struct CadenceTaskBundleSummary: Codable, Sendable {
    let id: String
    let title: String
    let dateKey: String
    let startMin: Int
    let durationMinutes: Int
    let endMin: Int
    let totalEstimatedMinutes: Int
    let taskCount: Int
    let activeTaskCount: Int
    let createdAt: String
}

nonisolated struct CadenceTaskBundleDetail: Codable, Sendable {
    let summary: CadenceTaskBundleSummary
    let tasks: [CadenceTaskSummary]
}

nonisolated struct CadenceTaskDetail: Codable, Sendable {
    let summary: CadenceTaskSummary
    let notes: String
    let actualMinutes: Int
    let subtasks: [CadenceSubtaskSummary]
    let createdAt: String
    let completedAt: String?
}

nonisolated struct CadenceDocumentSummary: Codable, Sendable {
    let id: String
    let title: String
    let container: CadenceContainerRef?
    let updatedAt: String
    let excerpt: String
    let tags: [CadenceTagSummary]
}

nonisolated struct CadenceTagDetail: Codable, Sendable {
    let summary: CadenceTagSummary
    let taskCount: Int
    let noteCount: Int
    let createdAt: String
    let updatedAt: String
}

nonisolated struct CadenceNoteSummary: Codable, Sendable {
    let id: String
    let kind: String
    let title: String
    let key: String?
    let container: CadenceContainerRef?
    let updatedAt: String
    let excerpt: String
    let tags: [CadenceTagSummary]
}

nonisolated struct CadenceNoteDetail: Codable, Sendable {
    let summary: CadenceNoteSummary
    let content: String
    let order: Int
    let createdAt: String
    let updatedAt: String
    let linkedNotes: [CadenceNoteSummary]
    let backlinks: [CadenceNoteSummary]
    let linkedTasks: [CadenceTaskSummary]
}

nonisolated struct CadenceNotePayload: Codable, Sendable {
    let id: String
    let kind: String
    let key: String?
    let content: String
    let updatedAt: String
    let excerpt: String
    let tags: [CadenceTagSummary]
}

nonisolated struct CadenceCoreNotesSnapshot: Codable, Sendable {
    let dateKey: String
    let weekKey: String
    let dailyNote: CadenceNotePayload?
    let weeklyNote: CadenceNotePayload?
    let permanentNote: CadenceNotePayload?
}

nonisolated struct CadenceSearchHit: Codable, Sendable {
    let entityType: String
    let entityId: String
    let title: String
    let subtitle: String
    let excerpt: String
    let score: Int
}

nonisolated struct CadenceTodayBrief: Codable, Sendable {
    let dateKey: String
    let scheduledTasks: [CadenceTaskSummary]
    let dueToday: [CadenceTaskSummary]
    let overdue: [CadenceTaskSummary]
    let inbox: [CadenceTaskSummary]
    let noteSnippets: [CadenceNotePayload]
}

nonisolated struct CadenceSectionSummary: Codable, Sendable {
    let name: String
    let colorHex: String
    let dueDate: String
    let isCompleted: Bool
    let isArchived: Bool
    let taskCount: Int
    let activeTaskCount: Int
    let completedTaskCount: Int
}

nonisolated struct CadenceContainerSummary: Codable, Sendable {
    let container: CadenceContainerRef
    let activeTaskCount: Int
    let completedTaskCount: Int
    let overdueTaskCount: Int
    let sections: [CadenceSectionSummary]
    let documents: [CadenceDocumentSummary]
    let links: [CadenceSavedLinkSummary]
}

nonisolated struct CadenceContextSummary: Codable, Sendable {
    let context: CadenceContextRef
    let inboxTaskCount: Int
    let activeTaskCount: Int
    let completedTaskCount: Int
    let scheduledTaskCount: Int
    let overdueTaskCount: Int
    let activeGoalCount: Int
    let documentCount: Int
    let linkCount: Int
    let areas: [CadenceContainerRef]
    let projects: [CadenceContainerRef]
}

nonisolated struct CadenceDocumentDetail: Codable, Sendable {
    let id: String
    let title: String
    let container: CadenceContainerRef?
    let content: String
    let order: Int
    let createdAt: String
    let updatedAt: String
    let tags: [CadenceTagSummary]
}

nonisolated struct CadenceGoalContributionSnapshot: Codable, Sendable {
    let totalTasks: Int
    let completedTasks: Int
    let directTaskCount: Int
    let linkedListCount: Int
    let focusMinutes: Int
    let overdueTaskCount: Int
    let recentCompletedCount: Int
    let nextActionTitle: String?
    let progress: Double
}

nonisolated struct CadenceGoalHabitMomentumSnapshot: Codable, Sendable {
    let linkedHabitCount: Int
    let dueTodayCount: Int
    let doneTodayCount: Int
    let thisWeekCount: Int
    let last7DayCount: Int
}

nonisolated struct CadenceGoalSummary: Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let startDate: String
    let endDate: String
    let progressType: String
    let targetHours: Double
    let loggedHours: Double
    let colorHex: String
    let icon: String
    /// `ongoing` / `completable` / `maintenance` — top-level ongoing goals are what used to be pursuits.
    let kind: String
    let status: String
    let progress: Double
    let contextId: String?
    let contextName: String?
    let parentGoalId: String?
    let parentGoalTitle: String?
    let isTopLevel: Bool
    let linkedListCount: Int
    let taskCount: Int
    let subGoalCount: Int
    let habitCount: Int
    let createdAt: String
}

nonisolated struct CadenceGoalDetail: Codable, Sendable {
    let summary: CadenceGoalSummary
    let contribution: CadenceGoalContributionSnapshot
    let habitMomentum: CadenceGoalHabitMomentumSnapshot
    let linkedContainers: [CadenceContainerRef]
    let directTasks: [CadenceTaskSummary]
    let subGoals: [CadenceGoalSummary]
    let habits: [CadenceHabitSummary]
}

nonisolated struct CadenceHabitSummary: Codable, Sendable {
    let id: String
    let title: String
    let icon: String
    let colorHex: String
    let frequencyType: String
    let frequencyDays: [Int]
    let targetCount: Int
    let order: Int
    let contextId: String?
    let contextName: String?
    let goal: CadenceGoalRef?
    let currentStreak: Int
    let completionCount: Int
    let completedToday: Bool
    let createdAt: String
}

nonisolated struct CadenceSavedLinkSummary: Codable, Sendable {
    let id: String
    let title: String
    let url: String
    let container: CadenceContainerRef?
    let order: Int
    let createdAt: String
}

nonisolated struct CadenceCompleteTaskResult: Codable, Sendable {
    let task: CadenceTaskDetail
    let spawnedRecurringTask: CadenceTaskDetail?
}

nonisolated struct CadenceBulkCancelResult: Codable, Sendable {
    let cancelledTasks: [CadenceTaskSummary]
}
