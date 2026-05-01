import Foundation
import MCP

struct CadenceMCPToolRouter {
    private let readService: CadenceReadService
    private let writeService: CadenceWriteService
    private let encoder: JSONEncoder

    init(readService: CadenceReadService, writeService: CadenceWriteService) {
        self.readService = readService
        self.writeService = writeService
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func register(on server: Server) async {
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: CadenceMCPToolDefinitions.tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let payload = try await callTool(name: params.name, arguments: params.arguments ?? [:])
                return .init(content: [.text(text: payload, annotations: nil, _meta: nil)], isError: false)
            } catch {
                return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
            }
        }
    }

    @MainActor
    private func callTool(name: String, arguments: [String: Value]) throws -> String {
        switch name {
        case "mcp_diagnostics":
            let health = try? readService.noteMigrationHealth()
            return try encode(CadenceMCPToolDefinitions.diagnostics(
                auditLogPath: try? CadenceModelContainerFactory.auditLogURL().path,
                noteMigrationHealthReport: health
            ))

        case "get_today_brief":
            return try encode(readService.todayBrief(dateKey: try arguments.dateKey("date")))

        case "list_tasks":
            let options = CadenceTaskListOptions(
                statuses: arguments.stringArray("status"),
                includeCompleted: arguments.bool("includeCompleted") ?? false,
                dueDateFrom: try arguments.dateKey("dueDateFrom"),
                dueDateTo: try arguments.dateKey("dueDateTo"),
                scheduledDate: try arguments.dateKey("scheduledDate"),
                containerKind: arguments.string("containerKind"),
                containerId: arguments.string("containerId"),
                textQuery: arguments.string("textQuery"),
                tagSlugs: arguments.stringArray("tagSlugs"),
                limit: arguments.int("limit") ?? 50
            )
            return try encode(readService.listTasks(options: options))

        case "get_task":
            return try encode(readService.getTask(taskID: try arguments.requiredString("taskId")))

        case "list_containers":
            return try encode(readService.listContainers(
                kind: arguments.string("kind"),
                status: arguments.string("status"),
                contextID: arguments.string("contextId"),
                limit: arguments.int("limit") ?? 50
            ))

        case "get_container_summary":
            return try encode(readService.containerSummary(
                kind: try arguments.requiredString("containerKind"),
                id: try arguments.requiredString("containerId")
            ))

        case "get_core_notes":
            return try encode(readService.coreNotes(dateKey: try arguments.dateKey("date")))

        case "list_documents":
            return try encode(readService.listDocuments(
                containerKind: arguments.string("containerKind"),
                containerID: arguments.string("containerId"),
                query: arguments.string("query"),
                limit: arguments.int("limit") ?? 50
            ))

        case "get_document":
            return try encode(readService.getDocument(documentID: try arguments.requiredString("documentId")))

        case "search_cadence":
            return try encode(readService.search(
                query: try arguments.requiredString("query"),
                scopes: arguments.stringArray("scopes"),
                limit: arguments.int("limit") ?? 50
            ))

        case "get_recent_mcp_writes":
            return try encode(readService.recentMCPWrites(limit: arguments.int("limit") ?? 50))

        case "create_task":
            return try encode(writeService.createTask(options: CadenceCreateTaskOptions(
                title: try arguments.requiredString("title"),
                notes: arguments.string("notes"),
                priority: arguments.string("priority"),
                dueDate: try arguments.dateKey("dueDate"),
                scheduledDate: try arguments.dateKey("scheduledDate"),
                scheduledStartMin: try arguments.minuteOfDay("scheduledStartMin"),
                estimatedMinutes: try arguments.durationMinutes("estimatedMinutes"),
                containerKind: arguments.string("containerKind"),
                containerId: arguments.string("containerId"),
                sectionName: arguments.string("sectionName"),
                subtaskTitles: arguments.stringArray("subtaskTitles"),
                tagNames: arguments.stringArray("tagNames")
            )))

        case "update_task":
            return try encode(writeService.updateTask(options: CadenceUpdateTaskOptions(
                taskId: try arguments.requiredString("taskId"),
                title: arguments.string("title"),
                notes: arguments.string("notes"),
                priority: arguments.string("priority"),
                dueDate: try arguments.dateKey("dueDate"),
                clearDueDate: arguments.bool("clearDueDate") ?? false,
                estimatedMinutes: try arguments.durationMinutes("estimatedMinutes"),
                containerKind: arguments.string("containerKind"),
                containerId: arguments.string("containerId"),
                clearContainer: arguments.bool("clearContainer") ?? false,
                sectionName: arguments.string("sectionName"),
                tagNames: arguments.stringArray("tagNames")
            )))

        case "schedule_task":
            return try encode(writeService.scheduleTask(options: CadenceScheduleTaskOptions(
                taskId: try arguments.requiredString("taskId"),
                scheduledDate: try arguments.dateKey("scheduledDate"),
                scheduledStartMin: try arguments.minuteOfDay("scheduledStartMin"),
                estimatedMinutes: try arguments.durationMinutes("estimatedMinutes"),
                clearScheduledDate: arguments.bool("clearScheduledDate") ?? false
            )))

        case "complete_task":
            return try encode(writeService.completeTask(taskID: try arguments.requiredString("taskId")))

        case "reopen_task":
            return try encode(writeService.reopenTask(taskID: try arguments.requiredString("taskId")))

        case "cancel_task":
            return try encode(writeService.cancelTask(taskID: try arguments.requiredString("taskId")))

        case "bulk_cancel_tasks":
            return try encode(writeService.bulkCancelTasks(options: CadenceBulkCancelTaskOptions(
                taskIds: arguments.stringArray("taskIds"),
                titlePrefix: arguments.string("titlePrefix")
            )))

        case "append_core_note":
            return try encode(writeService.appendCoreNote(
                kind: try arguments.requiredString("kind"),
                content: try arguments.requiredString("content"),
                dateKey: try arguments.dateKey("date"),
                separator: arguments.string("separator")
            ))

        default:
            throw ToolArgumentError.invalid("Unknown tool: \(name)")
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

}
