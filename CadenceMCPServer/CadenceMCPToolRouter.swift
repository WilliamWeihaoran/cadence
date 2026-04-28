import Foundation
import MCP

struct CadenceMCPToolRouter {
    private static let serverVersion = "0.1.0"
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
            .init(tools: Self.tools)
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
            return try encode(Self.diagnostics)

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

        case "get_blocked_tasks":
            return try encode(readService.blockedTasks(
                containerKind: arguments.string("containerKind"),
                containerID: arguments.string("containerId"),
                limit: arguments.int("limit") ?? 50
            ))

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
                dependencyTaskIds: arguments.stringArray("dependencyTaskIds"),
                subtaskTitles: arguments.stringArray("subtaskTitles")
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
                dependencyTaskIds: arguments.stringArray("dependencyTaskIds")
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

    private static var tools: [Tool] {
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
            Tool(name: "get_blocked_tasks", description: "List active Cadence tasks blocked by unresolved dependencies.", inputSchema: schema([
                "containerKind": "Optional area or project.",
                "containerId": "Optional area/project UUID.",
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
                "dependencyTaskIds": "Optional array of dependency task UUIDs.",
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
                "dependencyTaskIds": "Optional replacement array of dependency task UUIDs.",
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
            Tool(name: "append_core_note", description: "Append text to a daily, weekly, or permanent Cadence note, creating it if needed.", inputSchema: schema([
                "kind": "daily, weekly, or permanent.",
                "content": "Text to append.",
                "date": "Optional yyyy-MM-dd date or natural day. Defaults to today.",
                "separator": "Optional separator inserted before appended text when note already has content.",
            ])),
        ]
    }

    private static var diagnostics: [String: String] {
        [
            "name": "cadence-mcp",
            "version": serverVersion,
            "mode": "read-write",
            "toolCount": "\(tools.count)",
        ]
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

enum ToolArgumentError: Error, LocalizedError {
    case invalid(String)
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        case .missing(let key):
            return "Missing required argument: \(key)"
        }
    }
}

private extension Dictionary where Key == String, Value == MCP.Value {
    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = string(key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolArgumentError.missing(key)
        }
        return value
    }

    func bool(_ key: String) -> Bool? {
        self[key]?.boolValue
    }

    func int(_ key: String) -> Int? {
        if let intValue = self[key]?.intValue {
            return intValue
        }
        if let doubleValue = self[key]?.doubleValue {
            return Int(doubleValue)
        }
        if let stringValue = self[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           let intValue = Int(stringValue) {
            return intValue
        }
        return nil
    }

    func dateKey(_ key: String) throws -> String? {
        guard let raw = string(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if DateFormatters.date(from: raw) != nil { return raw }
        let normalized = raw.lowercased()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let resolved: Date?

        switch normalized {
        case "today":
            resolved = today
        case "tomorrow":
            resolved = calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday":
            resolved = calendar.date(byAdding: .day, value: -1, to: today)
        default:
            if let match = Self.parseRelativeDay(normalized, calendar: calendar, today: today) {
                resolved = match
            } else {
                resolved = nil
            }
        }

        guard let resolved else {
            throw ToolArgumentError.invalid("Invalid \(key): \(raw). Expected yyyy-MM-dd, today, tomorrow, yesterday, or in N days.")
        }
        return DateFormatters.dateKey(from: resolved)
    }

    func durationMinutes(_ key: String) throws -> Int? {
        guard let value = self[key] else { return nil }
        if let intValue = value.intValue { return intValue }
        if let doubleValue = value.doubleValue { return Int(doubleValue) }
        guard let raw = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let intValue = Int(raw) { return intValue }
        if let parsed = Self.parseDuration(raw) { return parsed }
        throw ToolArgumentError.invalid("Invalid \(key): \(raw). Expected minutes, 30m, 1h, 1.5h, or three hours.")
    }

    func minuteOfDay(_ key: String) throws -> Int? {
        guard let value = self[key] else { return nil }
        if let intValue = value.intValue { return intValue }
        if let doubleValue = value.doubleValue { return Int(doubleValue) }
        guard let raw = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let intValue = Int(raw) { return intValue }
        if let parsed = Self.parseMinuteOfDay(raw) { return parsed }
        throw ToolArgumentError.invalid("Invalid \(key): \(raw). Expected minutes from midnight or a time like 4 PM.")
    }

    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values)? = self[key] else { return nil }
        return values.compactMap(\.stringValue)
    }

    private static func parseRelativeDay(_ value: String, calendar: Calendar, today: Date) -> Date? {
        let patterns = [
            #"^in\s+(\d+)\s+days?$"#,
            #"^\+(\d+)\s+days?$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let range = Range(match.range(at: 1), in: value),
                  let days = Int(value[range]) else {
                continue
            }
            return calendar.date(byAdding: .day, value: days, to: today)
        }

        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)\s+days?\s+ago$"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value),
              let days = Int(value[range]) else {
            return nil
        }
        return calendar.date(byAdding: .day, value: -days, to: today)
    }

    private static func parseDuration(_ value: String) -> Int? {
        let spaced = value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let compact = spaced.replacingOccurrences(of: " ", with: "")

        if let regex = try? NSRegularExpression(pattern: #"^(\d+)(?:m|min|mins|minute|minutes)$"#),
           let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
           let range = Range(match.range(at: 1), in: compact),
           let minutes = Int(compact[range]) {
            return minutes
        }

        if let regex = try? NSRegularExpression(pattern: #"^(\d+(?:\.\d+)?)(?:h|hr|hrs|hour|hours)$"#),
           let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
           let range = Range(match.range(at: 1), in: compact),
           let hours = Double(compact[range]) {
            return Int((hours * 60).rounded())
        }

        if let wordDuration = parseWordDuration(spaced) {
            return wordDuration
        }

        return nil
    }

    private static func parseWordDuration(_ value: String) -> Int? {
        let numberWords: [String: Double] = [
            "a": 1,
            "an": 1,
            "one": 1,
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5,
            "six": 6,
            "seven": 7,
            "eight": 8,
            "nine": 9,
            "ten": 10,
            "eleven": 11,
            "twelve": 12,
        ]
        let units = #"hours?|hrs?|h|minutes?|mins?|m"#
        let pattern = #"^(a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?: and a half)?\s+(\#(units))$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let amountRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              var amount = numberWords[String(value[amountRange])] else {
            return nil
        }

        if value.contains(" and a half") {
            amount += 0.5
        }

        let unit = value[unitRange]
        if unit.hasPrefix("h") {
            return Int((amount * 60).rounded())
        }
        return Int(amount.rounded())
    }

    private static func parseMinuteOfDay(_ value: String) -> Int? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let hourRange = Range(match.range(at: 1), in: normalized),
              let hour = Int(normalized[hourRange]) else {
            return nil
        }

        let minute: Int
        if let minuteRange = Range(match.range(at: 2), in: normalized) {
            guard let parsedMinute = Int(normalized[minuteRange]) else { return nil }
            minute = parsedMinute
        } else {
            minute = 0
        }

        guard (1...12).contains(hour), (0...59).contains(minute),
              let meridiemRange = Range(match.range(at: 3), in: normalized) else {
            return nil
        }

        let meridiem = normalized[meridiemRange]
        var resolvedHour = hour % 12
        if meridiem == "pm" { resolvedHour += 12 }
        return resolvedHour * 60 + minute
    }
}
