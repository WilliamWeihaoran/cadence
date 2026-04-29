import Foundation
import MCP

enum CadenceMCPToolDefinitions {
    private static let serverVersion = "0.1.0"

    static var tools: [Tool] {
        [
            Tool(name: "mcp_diagnostics", description: "Return Cadence MCP server version and tool metadata.", inputSchema: schema([:])),
            Tool(name: "get_today_brief", description: "Return a read-only Cadence dashboard summary for a date.", inputSchema: schema(["date": "Optional yyyy-MM-dd date key or natural day such as today, tomorrow, yesterday, in 3 days, or 2 days ago. Defaults to today."])),
            Tool(name: "list_tasks", description: "List Cadence tasks with read-only filters.", inputSchema: schema([
                "status": "Optional array of raw task statuses.",
                "includeCompleted": "Include completed tasks when status is not specified.",
                "dueDateFrom": "Optional lower due date, yyyy-MM-dd or natural day.",
                "dueDateTo": "Optional upper due date, yyyy-MM-dd or natural day.",
                "scheduledDate": "Optional scheduled date, yyyy-MM-dd or natural day.",
                "containerKind": "Optional area or project.",
                "containerId": "Optional area/project UUID.",
                "textQuery": "Optional task text search.",
                "limit": "Optional result limit, capped at 200.",
            ])),
            Tool(name: "get_task", description: "Get full read-only detail for one Cadence task.", inputSchema: schema(["taskId": "Task UUID."])),
            Tool(name: "list_containers", description: "List Cadence areas and projects.", inputSchema: schema([
                "kind": "Optional area or project.",
                "status": "Optional raw status.",
                "contextId": "Optional context UUID.",
                "limit": "Optional result limit, capped at 200.",
            ])),
            Tool(name: "get_container_summary", description: "Summarize one Cadence area or project.", inputSchema: schema([
                "containerKind": "area or project.",
                "containerId": "Area/project UUID.",
            ])),
            Tool(name: "get_core_notes", description: "Read daily, weekly, and permanent Cadence notes without creating missing notes.", inputSchema: schema(["date": "Optional yyyy-MM-dd date key or natural day. Defaults to today."])),
            Tool(name: "list_documents", description: "List Cadence markdown documents.", inputSchema: schema([
                "containerKind": "Optional area or project.",
                "containerId": "Optional area/project UUID.",
                "query": "Optional document search.",
                "limit": "Optional result limit, capped at 200.",
            ])),
            Tool(name: "get_document", description: "Get full markdown content for one Cadence document.", inputSchema: schema(["documentId": "Document UUID."])),
            Tool(name: "search_cadence", description: "Search Cadence tasks, containers, documents, core notes, and event-linked meeting notes.", inputSchema: schema([
                "query": "Search query.",
                "scopes": "Optional scopes: tasks, containers, documents, core_notes, event_notes.",
                "limit": "Optional result limit, capped at 200.",
            ])),
            Tool(name: "get_recent_mcp_writes", description: "Read recent Cadence MCP write audit log entries.", inputSchema: schema([
                "limit": "Optional result limit, capped at 200.",
            ])),
            Tool(name: "create_task", description: "Create a Cadence task without Calendar side effects.", inputSchema: schema([
                "title": "Task title.",
                "notes": "Optional notes.",
                "priority": "Optional priority: none, low, medium, high.",
                "dueDate": "Optional due date, yyyy-MM-dd or natural day.",
                "scheduledDate": "Optional do date, yyyy-MM-dd or natural day.",
                "scheduledStartMin": "Optional minutes from midnight, 0...1439, or time like 4 PM. Requires scheduledDate.",
                "estimatedMinutes": "Optional estimate, 1...1440 minutes, or duration like 30m, 1h, 1.5h, or three hours.",
                "containerKind": "Optional area or project.",
                "containerId": "Optional area/project UUID.",
                "sectionName": "Optional container section name.",
                "subtaskTitles": "Optional array of subtask titles.",
            ])),
            Tool(name: "update_task", description: "Safely update editable fields on one Cadence task.", inputSchema: schema([
                "taskId": "Task UUID.",
                "title": "Optional new task title.",
                "notes": "Optional replacement notes.",
                "priority": "Optional priority: none, low, medium, high.",
                "dueDate": "Optional due date, yyyy-MM-dd or natural day.",
                "clearDueDate": "Set true to clear dueDate.",
                "estimatedMinutes": "Optional estimate, 1...1440 minutes, or duration like 30m, 1h, 1.5h, or three hours.",
                "containerKind": "Optional area or project.",
                "containerId": "Optional area/project UUID.",
                "clearContainer": "Set true to move task to inbox.",
                "sectionName": "Optional container section name.",
            ])),
            Tool(name: "schedule_task", description: "Set or clear a Cadence task do-date/time without Calendar side effects.", inputSchema: schema([
                "taskId": "Task UUID.",
                "scheduledDate": "Optional do date, yyyy-MM-dd or natural day.",
                "scheduledStartMin": "Optional minutes from midnight, 0...1439, or time like 4 PM. Requires scheduledDate.",
                "estimatedMinutes": "Optional estimate, 1...1440 minutes, or duration like 30m, 1h, 1.5h, or three hours.",
                "clearScheduledDate": "Set true to clear scheduled date and time.",
            ])),
            Tool(name: "complete_task", description: "Mark a Cadence task done and spawn a recurring follow-up when applicable.", inputSchema: schema(["taskId": "Task UUID."])),
            Tool(name: "reopen_task", description: "Reopen a Cadence task as todo.", inputSchema: schema(["taskId": "Task UUID."])),
            Tool(name: "cancel_task", description: "Cancel a Cadence task without deleting it.", inputSchema: schema(["taskId": "Task UUID."])),
            Tool(name: "bulk_cancel_tasks", description: "Cancel multiple Cadence tasks without deleting them. Requires exact taskIds or a titlePrefix of at least 8 characters.", inputSchema: schema([
                "taskIds": "Optional array of exact task UUIDs. Cannot be combined with titlePrefix.",
                "titlePrefix": "Optional title prefix, minimum 8 characters. Cannot be combined with taskIds.",
            ])),
            Tool(name: "append_core_note", description: "Append text to a daily, weekly, or permanent Cadence note, creating it if needed.", inputSchema: schema([
                "kind": "daily, weekly, or permanent.",
                "content": "Text to append.",
                "date": "Optional yyyy-MM-dd date or natural day. Defaults to today.",
                "separator": "Optional separator inserted before appended text when note already has content.",
            ])),
        ]
    }

    static func diagnostics(auditLogPath: String?, noteMigrationReport: NoteMigrationReport? = NoteMigrationService.lastReport()) -> [String: String] {
        var payload = [
            "name": "cadence-mcp",
            "version": serverVersion,
            "mode": "read-write",
            "toolCount": "\(tools.count)",
        ]
        if let auditLogPath {
            payload["auditLogPath"] = auditLogPath
        }
        if let noteMigrationReport {
            payload["noteMigrationSuccess"] = "\(noteMigrationReport.success)"
            payload["noteMigrationSource"] = noteMigrationReport.source
            payload["noteMigrationInserted"] = "\(noteMigrationReport.insertedTotal)"
            payload["noteMigrationScanned"] = "\(noteMigrationReport.legacyScannedTotal)"
            payload["noteMigrationExistingNotes"] = "\(noteMigrationReport.existingNoteCount)"
            payload["noteMigrationCanonicalDuplicates"] = "\(noteMigrationReport.canonicalDuplicateCount)"
            payload["noteMigrationSkippedCanonical"] = "\(noteMigrationReport.skippedCanonicalDuplicate)"
            if let errorMessage = noteMigrationReport.errorMessage {
                payload["noteMigrationError"] = errorMessage
            }
        }
        return payload
    }

    private static func schema(_ properties: [String: String]) -> Value {
        .object([
            "type": .string("object"),
            "properties": .object(
                Dictionary(uniqueKeysWithValues: properties.map { key, description in
                    (key, Value.object([
                        "description": .string(description),
                    ]))
                })
            ),
        ])
    }
}
