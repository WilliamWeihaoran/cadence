import Foundation

struct CadenceContainerRef: Codable, Sendable {
    let kind: String
    let id: String
    let name: String
    let contextId: String?
    let contextName: String?
    let status: String
    let colorHex: String
    let icon: String
}

struct CadenceGoalRef: Codable, Sendable {
    let id: String
    let title: String
    let status: String
    let progress: Double
}

struct CadenceSubtaskSummary: Codable, Sendable {
    let id: String
    let title: String
    let isDone: Bool
    let order: Int
}

struct CadenceTagSummary: Codable, Sendable {
    let id: String
    let slug: String
    let name: String
    let colorHex: String
    let description: String
    let isArchived: Bool
}

struct CadenceTaskSummary: Codable, Sendable {
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

struct CadenceTaskBundleSummary: Codable, Sendable {
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

struct CadenceTaskBundleDetail: Codable, Sendable {
    let summary: CadenceTaskBundleSummary
    let tasks: [CadenceTaskSummary]
}

struct CadenceTaskDetail: Codable, Sendable {
    let summary: CadenceTaskSummary
    let notes: String
    let actualMinutes: Int
    let subtasks: [CadenceSubtaskSummary]
    let createdAt: String
    let completedAt: String?
}

struct CadenceDocumentSummary: Codable, Sendable {
    let id: String
    let title: String
    let container: CadenceContainerRef?
    let updatedAt: String
    let excerpt: String
    let tags: [CadenceTagSummary]
}

struct CadenceTagDetail: Codable, Sendable {
    let summary: CadenceTagSummary
    let taskCount: Int
    let noteCount: Int
    let createdAt: String
    let updatedAt: String
}

struct CadenceNoteSummary: Codable, Sendable {
    let id: String
    let kind: String
    let title: String
    let key: String?
    let container: CadenceContainerRef?
    let updatedAt: String
    let excerpt: String
    let tags: [CadenceTagSummary]
}

struct CadenceNoteDetail: Codable, Sendable {
    let summary: CadenceNoteSummary
    let content: String
    let order: Int
    let createdAt: String
    let updatedAt: String
    let linkedNotes: [CadenceNoteSummary]
    let backlinks: [CadenceNoteSummary]
    let linkedTasks: [CadenceTaskSummary]
}

struct CadenceNotePayload: Codable, Sendable {
    let id: String
    let kind: String
    let key: String?
    let content: String
    let updatedAt: String
    let excerpt: String
    let tags: [CadenceTagSummary]
}

struct CadenceCoreNotesSnapshot: Codable, Sendable {
    let dateKey: String
    let weekKey: String
    let dailyNote: CadenceNotePayload?
    let weeklyNote: CadenceNotePayload?
    let permanentNote: CadenceNotePayload?
}

struct CadenceSearchHit: Codable, Sendable {
    let entityType: String
    let entityId: String
    let title: String
    let subtitle: String
    let excerpt: String
    let score: Int
}

struct CadenceTodayBrief: Codable, Sendable {
    let dateKey: String
    let scheduledTasks: [CadenceTaskSummary]
    let dueToday: [CadenceTaskSummary]
    let overdue: [CadenceTaskSummary]
    let inbox: [CadenceTaskSummary]
    let noteSnippets: [CadenceNotePayload]
}

struct CadenceSectionSummary: Codable, Sendable {
    let name: String
    let colorHex: String
    let dueDate: String
    let isCompleted: Bool
    let isArchived: Bool
    let taskCount: Int
    let activeTaskCount: Int
    let completedTaskCount: Int
}

struct CadenceContainerSummary: Codable, Sendable {
    let container: CadenceContainerRef
    let activeTaskCount: Int
    let completedTaskCount: Int
    let overdueTaskCount: Int
    let sections: [CadenceSectionSummary]
    let documents: [CadenceDocumentSummary]
    let links: [CadenceSavedLinkSummary]
}

struct CadenceDocumentDetail: Codable, Sendable {
    let id: String
    let title: String
    let container: CadenceContainerRef?
    let content: String
    let order: Int
    let createdAt: String
    let updatedAt: String
    let tags: [CadenceTagSummary]
}

struct CadenceGoalContributionSnapshot: Codable, Sendable {
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

struct CadenceGoalHabitMomentumSnapshot: Codable, Sendable {
    let linkedHabitCount: Int
    let dueTodayCount: Int
    let doneTodayCount: Int
    let thisWeekCount: Int
    let last7DayCount: Int
}

struct CadenceGoalSummary: Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let startDate: String
    let endDate: String
    let progressType: String
    let targetHours: Double
    let loggedHours: Double
    let colorHex: String
    let status: String
    let progress: Double
    let contextId: String?
    let contextName: String?
    let parentGoalId: String?
    let parentGoalTitle: String?
    let linkedListCount: Int
    let taskCount: Int
    let habitCount: Int
    let createdAt: String
}

struct CadenceGoalDetail: Codable, Sendable {
    let summary: CadenceGoalSummary
    let contribution: CadenceGoalContributionSnapshot
    let habitMomentum: CadenceGoalHabitMomentumSnapshot
    let linkedContainers: [CadenceContainerRef]
    let directTasks: [CadenceTaskSummary]
    let subGoals: [CadenceGoalSummary]
    let habits: [CadenceHabitSummary]
}

struct CadenceHabitSummary: Codable, Sendable {
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

struct CadenceSavedLinkSummary: Codable, Sendable {
    let id: String
    let title: String
    let url: String
    let container: CadenceContainerRef?
    let order: Int
    let createdAt: String
}

struct CadenceCompleteTaskResult: Codable, Sendable {
    let task: CadenceTaskDetail
    let spawnedRecurringTask: CadenceTaskDetail?
}

struct CadenceBulkCancelResult: Codable, Sendable {
    let cancelledTasks: [CadenceTaskSummary]
}
