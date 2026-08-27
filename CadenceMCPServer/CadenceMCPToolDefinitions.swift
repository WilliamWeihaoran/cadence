import Foundation
import MCP

enum CadenceMCPToolDefinitions {
    // 0.3.0, not 0.2.1: every `list_*` tool, `search_cadence` and `get_recent_mcp_writes` now answer
    // with a `CadencePage` object instead of a bare array (T-382). A client that indexes the
    // response breaks, so the advertised version has to say so — it is the only signal an already
    // installed client gets.
    private static let serverVersion = "0.3.0"
    private static let writeToolNames: Set<String> = [
        "create_task",
        "update_task",
        "schedule_task",
        "complete_task",
        "reopen_task",
        "cancel_task",
        "bulk_cancel_tasks",
        "append_core_note",
    ]

    static var tools: [Tool] {
        tools(writesEnabled: false)
    }

    static func tools(writesEnabled: Bool) -> [Tool] {
        guard writesEnabled else {
            return allTools.filter { !writeToolNames.contains($0.name) }
        }
        return allTools
    }

    static func isWriteTool(_ name: String) -> Bool {
        writeToolNames.contains(name)
    }

    private static var allTools: [Tool] {
        [
            Tool(name: "mcp_diagnostics", description: "Return Cadence MCP server version, capabilities, and store metadata.", inputSchema: schema([:])),
            Tool(name: "get_today_brief", description: "Return a read-only Cadence dashboard summary for a date.", inputSchema: schema([
                "date": dateProperty("Optional yyyy-MM-dd date key or natural day such as today, tomorrow, yesterday, in 3 days, or 2 days ago. Defaults to today."),
            ])),
            Tool(name: "list_tasks", description: "List Cadence tasks with read-only filters.", inputSchema: schema([
                "status": flexibleStringArrayProperty("Optional raw task statuses.", enumValues: TaskStatus.allCases.map(\.rawValue)),
                "includeCompleted": booleanProperty("Include completed tasks when status is not specified."),
                "dueDateFrom": dateProperty("Optional lower due date, yyyy-MM-dd or natural day."),
                "dueDateTo": dateProperty("Optional upper due date, yyyy-MM-dd or natural day."),
                "scheduledDate": dateProperty("Optional scheduled date, yyyy-MM-dd or natural day."),
                "containerKind": stringProperty("Optional area or project.", enumValues: ["area", "project"]),
                "containerId": uuidProperty("Optional area/project UUID."),
                "textQuery": stringProperty("Optional task text search."),
                "tagSlugs": flexibleStringArrayProperty("Optional array of tag names/slugs. Tasks must have every requested tag."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "get_task", description: "Get full read-only detail for one Cadence task.", inputSchema: schema([
                "taskId": uuidProperty("Task UUID."),
            ], required: ["taskId"])),
            Tool(name: "list_task_bundles", description: "List scheduled Cadence task bundles.", inputSchema: schema([
                "date": dateProperty("Optional bundle date, yyyy-MM-dd or natural day."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "get_task_bundle", description: "Get read-only detail for one Cadence task bundle.", inputSchema: schema([
                "bundleId": uuidProperty("Task bundle UUID."),
            ], required: ["bundleId"])),
            Tool(name: "list_contexts", description: "List Cadence contexts with summary counts.", inputSchema: schema([
                "includeArchived": booleanProperty("Include archived contexts."),
                "query": stringProperty("Optional context search."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "get_context_summary", description: "Summarize one Cadence context, including its areas and projects.", inputSchema: schema([
                "contextId": uuidProperty("Context UUID."),
            ], required: ["contextId"])),
            Tool(name: "list_containers", description: "List Cadence areas and projects.", inputSchema: schema([
                "kind": stringProperty("Optional area or project.", enumValues: ["area", "project"]),
                "status": stringProperty("Optional raw status."),
                "contextId": uuidProperty("Optional context UUID."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "get_container_summary", description: "Summarize one Cadence area or project.", inputSchema: schema([
                "containerKind": stringProperty("area or project.", enumValues: ["area", "project"]),
                "containerId": uuidProperty("Area/project UUID."),
            ], required: ["containerKind", "containerId"])),
            Tool(name: "list_tags", description: "List Cadence tags with task and note counts.", inputSchema: schema([
                "includeArchived": booleanProperty("Include archived tags."),
                "query": stringProperty("Optional tag search."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "get_core_notes", description: "Read daily, weekly, and permanent Cadence notes without creating missing notes.", inputSchema: schema([
                "date": dateProperty("Optional yyyy-MM-dd date key or natural day. Defaults to today."),
            ])),
            Tool(name: "list_notes", description: "List Cadence notes across daily, weekly, permanent, list, and meeting kinds.", inputSchema: schema([
                "kind": stringProperty("Optional note kind: daily, weekly, permanent, list, or meeting.", enumValues: ["daily", "weekly", "permanent", "list", "meeting"]),
                "containerKind": stringProperty("Optional area or project for list notes.", enumValues: ["area", "project"]),
                "containerId": uuidProperty("Optional area/project UUID."),
                "query": stringProperty("Optional note search."),
                "tagSlugs": flexibleStringArrayProperty("Optional array of tag names/slugs. Notes must have every requested tag."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "get_note", description: "Get full Cadence note content plus note/task references and backlinks.", inputSchema: schema([
                "noteId": uuidProperty("Note UUID."),
            ], required: ["noteId"])),
            Tool(name: "list_documents", description: "List Cadence markdown documents.", inputSchema: schema([
                "containerKind": stringProperty("Optional area or project.", enumValues: ["area", "project"]),
                "containerId": uuidProperty("Optional area/project UUID."),
                "query": stringProperty("Optional document search."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "get_document", description: "Get full markdown content for one Cadence document.", inputSchema: schema([
                "documentId": uuidProperty("Document UUID."),
            ], required: ["documentId"])),
            Tool(name: "list_goals", description: "List Cadence goals with progress and relationship counts.", inputSchema: schema([
                "status": stringProperty("Optional goal status: active, done, or paused.", enumValues: GoalStatus.allCases.map(\.rawValue)),
                "contextId": uuidProperty("Optional context UUID."),
                "query": stringProperty("Optional goal search."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "get_goal", description: "Get full read-only detail for one Cadence goal.", inputSchema: schema([
                "goalId": uuidProperty("Goal UUID."),
            ], required: ["goalId"])),
            Tool(name: "list_habits", description: "List Cadence habits with streak and goal metadata.", inputSchema: schema([
                "contextId": uuidProperty("Optional context UUID."),
                "goalId": uuidProperty("Optional goal UUID."),
                "query": stringProperty("Optional habit search."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "list_links", description: "List saved links attached to Cadence areas or projects.", inputSchema: schema([
                "containerKind": stringProperty("Optional area or project.", enumValues: ["area", "project"]),
                "containerId": uuidProperty("Optional area/project UUID."),
                "query": stringProperty("Optional link search."),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "search_cadence", description: "Search Cadence tasks, containers, contexts, documents, notes, goals, habits, links, and tags.", inputSchema: schema([
                "query": stringProperty("Search query.", minLength: 1),
                "scopes": flexibleStringArrayProperty("Optional scopes: tasks, containers, contexts, documents, notes, core_notes, event_notes, goals, habits, links, tags.", enumValues: ["tasks", "containers", "contexts", "documents", "notes", "core_notes", "event_notes", "goals", "habits", "links", "tags"]),
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ], required: ["query"])),
            Tool(name: "get_recent_mcp_writes", description: "Read recent Cadence MCP write audit log entries.", inputSchema: schema([
                "limit": integerProperty("Optional page size, capped at 200. The response is a page envelope — items, offset, returnedCount, totalCount, hasMore, nextOffset — so 0 is a valid request for totalCount alone.", minimum: 0, maximum: 200),
                "offset": integerProperty("Optional zero-based offset into the totally ordered result. Pass the previous response's nextOffset to continue; hasMore says whether one exists.", minimum: 0),
            ])),
            Tool(name: "create_task", description: "Create a Cadence task without Calendar side effects.", inputSchema: schema([
                "title": stringProperty("Task title.", minLength: 1),
                "notes": stringProperty("Optional notes."),
                "priority": stringProperty("Optional priority: none, low, medium, high.", enumValues: TaskPriority.allCases.map(\.rawValue)),
                "dueDate": dateProperty("Optional due date, yyyy-MM-dd or natural day."),
                "scheduledDate": dateProperty("Optional do date, yyyy-MM-dd or natural day."),
                "scheduledStartMin": integerOrStringProperty("Optional minutes from midnight, 0...1439, or time like 4 PM.", minimum: 0, maximum: 1439),
                "estimatedMinutes": integerOrStringProperty("Optional estimate, 1...1440 minutes, or duration like 30m, 1h, 1.5h, or three hours.", minimum: 1, maximum: 1440),
                "containerKind": stringProperty("Optional area or project.", enumValues: ["area", "project"]),
                "containerId": uuidProperty("Optional area/project UUID."),
                "sectionName": stringProperty("Optional section name. Must match a section that already exists on the target list; an unknown name is rejected rather than redirected."),
                "subtaskTitles": flexibleStringArrayProperty("Optional array of subtask titles."),
                "tagNames": flexibleStringArrayProperty("Optional array of tag names/slugs to assign."),
            ], required: ["title"])),
            Tool(name: "update_task", description: "Safely update editable fields on one Cadence task.", inputSchema: schema([
                "taskId": uuidProperty("Task UUID."),
                "title": stringProperty("Optional new task title.", minLength: 1),
                "notes": stringProperty("Optional replacement notes."),
                "priority": stringProperty("Optional priority: none, low, medium, high.", enumValues: TaskPriority.allCases.map(\.rawValue)),
                "dueDate": dateProperty("Optional due date, yyyy-MM-dd or natural day."),
                "clearDueDate": booleanProperty("Set true to clear dueDate."),
                "estimatedMinutes": integerOrStringProperty("Optional estimate, 1...1440 minutes, or duration like 30m, 1h, 1.5h, or three hours.", minimum: 1, maximum: 1440),
                "containerKind": stringProperty("Optional area or project.", enumValues: ["area", "project"]),
                "containerId": uuidProperty("Optional area/project UUID."),
                "clearContainer": booleanProperty("Set true to move task to inbox."),
                "sectionName": stringProperty("Optional section name. Must match a section that already exists on the target list; an unknown name is rejected rather than redirected."),
                "tagNames": flexibleStringArrayProperty("Optional replacement array of tag names/slugs. Pass an empty array to clear tags."),
            ], required: ["taskId"])),
            Tool(name: "schedule_task", description: "Set or clear a Cadence task do-date/time without Calendar side effects.", inputSchema: schema([
                "taskId": uuidProperty("Task UUID."),
                "scheduledDate": dateProperty("Optional do date, yyyy-MM-dd or natural day."),
                "scheduledStartMin": integerOrStringProperty("Optional minutes from midnight, 0...1439, or time like 4 PM.", minimum: 0, maximum: 1439),
                "estimatedMinutes": integerOrStringProperty("Optional estimate, 1...1440 minutes, or duration like 30m, 1h, 1.5h, or three hours.", minimum: 1, maximum: 1440),
                "clearScheduledDate": booleanProperty("Set true to clear scheduled date and time."),
            ], required: ["taskId"])),
            Tool(name: "complete_task", description: "Mark a Cadence task done and spawn a recurring follow-up when applicable.", inputSchema: schema([
                "taskId": uuidProperty("Task UUID."),
            ], required: ["taskId"])),
            Tool(name: "reopen_task", description: "Reopen a Cadence task as todo.", inputSchema: schema([
                "taskId": uuidProperty("Task UUID."),
            ], required: ["taskId"])),
            Tool(name: "cancel_task", description: "Cancel a Cadence task without deleting it.", inputSchema: schema([
                "taskId": uuidProperty("Task UUID."),
            ], required: ["taskId"])),
            Tool(name: "bulk_cancel_tasks", description: "Cancel multiple Cadence tasks without deleting them. Requires exact taskIds or a titlePrefix of at least 8 characters.", inputSchema: schema([
                "taskIds": flexibleStringArrayProperty("Optional array of exact task UUIDs. Cannot be combined with titlePrefix."),
                "titlePrefix": stringProperty("Optional title prefix, minimum 8 characters. Cannot be combined with taskIds.", minLength: 8),
            ])),
            Tool(name: "append_core_note", description: "Append text to a daily, weekly, or permanent Cadence note, creating it if needed.", inputSchema: schema([
                "kind": stringProperty("daily, weekly, or permanent.", enumValues: ["daily", "weekly", "permanent"]),
                "content": stringProperty("Text to append.", minLength: 1),
                "date": dateProperty("Optional yyyy-MM-dd date or natural day. Defaults to today."),
                "separator": stringProperty("Optional separator inserted before appended text when note already has content."),
            ], required: ["kind", "content"])),
        ]
    }

    static func diagnostics(
        auditLogPath: String?,
        refreshMarkerPath: String?,
        storePath: String?,
        writesEnabled: Bool = false,
        noteMigrationReport: NoteMigrationReport? = NoteMigrationService.lastReport(),
        noteMigrationHealthReport: NoteMigrationHealthReport? = nil
    ) -> [String: String] {
        let visibleTools = tools(writesEnabled: writesEnabled)
        let writeTools = visibleTools.filter { writeToolNames.contains($0.name) }.map(\.name).sorted()
        let readTools = visibleTools.filter { !writeToolNames.contains($0.name) }.map(\.name).sorted()
        var payload = [
            "name": "cadence-mcp",
            "version": serverVersion,
            "mode": writesEnabled ? "read-write" : "read-only",
            "toolCount": "\(visibleTools.count)",
            "readToolCount": "\(readTools.count)",
            "writeToolCount": "\(writeTools.count)",
            "supportsNaturalLanguageDates": "true",
            "supportsFlexibleStringArrays": "true",
            "supportsStringDurations": "true",
            "supportsStringTimes": "true",
            "readTools": readTools.joined(separator: ","),
            "writeTools": writeTools.joined(separator: ","),
        ]
        if let storePath {
            payload["storePath"] = storePath
        }
        if let auditLogPath {
            payload["auditLogPath"] = auditLogPath
        }
        if let refreshMarkerPath {
            payload["refreshMarkerPath"] = refreshMarkerPath
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
        if let noteMigrationHealthReport {
            payload["noteMigrationHealthIssues"] = "\(noteMigrationHealthReport.issueCount)"
            payload["noteMigrationHealthLegacyWithoutCanonical"] = "\(noteMigrationHealthReport.legacyWithoutCanonicalCount)"
            payload["noteMigrationHealthOrphanedListNotes"] = "\(noteMigrationHealthReport.orphanedListNoteCount)"
            payload["noteMigrationHealthMeetingNotesMissingCalendar"] = "\(noteMigrationHealthReport.meetingNoteMissingCalendarIDCount)"
        }
        return payload
    }

    private static func schema(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(Value.string))
        }
        return .object(schema)
    }

    private static func stringProperty(_ description: String, enumValues: [String] = [], minLength: Int? = nil) -> Value {
        var payload: [String: Value] = [
            "type": .string("string"),
            "description": .string(description),
        ]
        if !enumValues.isEmpty {
            payload["enum"] = .array(enumValues.map(Value.string))
        }
        if let minLength {
            payload["minLength"] = .int(minLength)
        }
        return .object(payload)
    }

    private static func uuidProperty(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
            "format": .string("uuid"),
        ])
    }

    private static func dateProperty(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
        ])
    }

    private static func booleanProperty(_ description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description),
        ])
    }

    private static func integerProperty(_ description: String, minimum: Int? = nil, maximum: Int? = nil) -> Value {
        var payload: [String: Value] = [
            "type": .string("integer"),
            "description": .string(description),
        ]
        if let minimum {
            payload["minimum"] = .int(minimum)
        }
        if let maximum {
            payload["maximum"] = .int(maximum)
        }
        return .object(payload)
    }

    private static func stringArrayProperty(_ description: String, enumValues: [String] = []) -> Value {
        var itemPayload: [String: Value] = ["type": .string("string")]
        if !enumValues.isEmpty {
            itemPayload["enum"] = .array(enumValues.map(Value.string))
        }
        return .object([
            "type": .string("array"),
            "description": .string(description),
            "items": .object(itemPayload),
        ])
    }

    private static func flexibleStringArrayProperty(_ description: String, enumValues: [String] = []) -> Value {
        .object([
            "description": .string(description),
            "anyOf": .array([
                stringArrayProperty(description, enumValues: enumValues),
                stringProperty(description),
            ]),
        ])
    }

    private static func integerOrStringProperty(_ description: String, minimum: Int? = nil, maximum: Int? = nil) -> Value {
        .object([
            "description": .string(description),
            "anyOf": .array([
                integerProperty(description, minimum: minimum, maximum: maximum),
                stringProperty(description),
            ]),
        ])
    }
}
