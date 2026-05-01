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

struct CadenceContainerSummary: Codable, Sendable {
    let container: CadenceContainerRef
    let activeTaskCount: Int
    let completedTaskCount: Int
    let overdueTaskCount: Int
    let documents: [CadenceDocumentSummary]
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

struct CadenceCompleteTaskResult: Codable, Sendable {
    let task: CadenceTaskDetail
    let spawnedRecurringTask: CadenceTaskDetail?
}

struct CadenceBulkCancelResult: Codable, Sendable {
    let cancelledTasks: [CadenceTaskSummary]
}
