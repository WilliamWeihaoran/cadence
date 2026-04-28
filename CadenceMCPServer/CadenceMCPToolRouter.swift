import Foundation
import MCP

struct CadenceMCPToolRouter {
    private let service: CadenceReadService
    private let encoder: JSONEncoder

    init(service: CadenceReadService) {
        self.service = service
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
        case "get_today_brief":
            return try encode(service.todayBrief(dateKey: arguments.string("date")))

        case "list_tasks":
            let options = CadenceTaskListOptions(
                statuses: arguments.stringArray("status"),
                includeCompleted: arguments.bool("includeCompleted") ?? false,
                dueDateFrom: arguments.string("dueDateFrom"),
                dueDateTo: arguments.string("dueDateTo"),
                scheduledDate: arguments.string("scheduledDate"),
                containerKind: arguments.string("containerKind"),
                containerId: arguments.string("containerId"),
                textQuery: arguments.string("textQuery"),
                limit: arguments.int("limit") ?? 50
            )
            return try encode(service.listTasks(options: options))

        case "get_task":
            return try encode(service.getTask(taskID: try arguments.requiredString("taskId")))

        case "list_containers":
            return try encode(service.listContainers(
                kind: arguments.string("kind"),
                status: arguments.string("status"),
                contextID: arguments.string("contextId"),
                limit: arguments.int("limit") ?? 50
            ))

        case "get_container_summary":
            return try encode(service.containerSummary(
                kind: try arguments.requiredString("containerKind"),
                id: try arguments.requiredString("containerId")
            ))

        case "get_core_notes":
            return try encode(service.coreNotes(dateKey: arguments.string("date")))

        case "list_documents":
            return try encode(service.listDocuments(
                containerKind: arguments.string("containerKind"),
                containerID: arguments.string("containerId"),
                query: arguments.string("query"),
                limit: arguments.int("limit") ?? 50
            ))

        case "get_document":
            return try encode(service.getDocument(documentID: try arguments.requiredString("documentId")))

        case "search_cadence":
            return try encode(service.search(
                query: try arguments.requiredString("query"),
                scopes: arguments.stringArray("scopes"),
                limit: arguments.int("limit") ?? 50
            ))

        case "get_blocked_tasks":
            return try encode(service.blockedTasks(
                containerKind: arguments.string("containerKind"),
                containerID: arguments.string("containerId"),
                limit: arguments.int("limit") ?? 50
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
            Tool(name: "get_today_brief", description: "Return a read-only Cadence dashboard summary for a date.", inputSchema: schema(["date": "Optional yyyy-MM-dd date key. Defaults to today."])),
            Tool(name: "list_tasks", description: "List Cadence tasks with read-only filters.", inputSchema: schema([
                "status": "Optional array of raw task statuses.",
                "includeCompleted": "Include completed tasks when status is not specified.",
                "dueDateFrom": "Optional lower yyyy-MM-dd due date.",
                "dueDateTo": "Optional upper yyyy-MM-dd due date.",
                "scheduledDate": "Optional yyyy-MM-dd scheduled date.",
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
            Tool(name: "get_core_notes", description: "Read daily, weekly, and permanent Cadence notes without creating missing notes.", inputSchema: schema(["date": "Optional yyyy-MM-dd date key. Defaults to today."])),
            Tool(name: "list_documents", description: "List Cadence markdown documents.", inputSchema: schema([
                "containerKind": "Optional area or project.",
                "containerId": "Optional area/project UUID.",
                "query": "Optional document search.",
                "limit": "Optional result limit, capped at 200.",
            ])),
            Tool(name: "get_document", description: "Get full markdown content for one Cadence document.", inputSchema: schema(["documentId": "Document UUID."])),
            Tool(name: "search_cadence", description: "Search Cadence tasks, containers, documents, and core notes.", inputSchema: schema([
                "query": "Search query.",
                "scopes": "Optional scopes: tasks, containers, documents, core_notes.",
                "limit": "Optional result limit, capped at 200.",
            ])),
            Tool(name: "get_blocked_tasks", description: "List active Cadence tasks blocked by unresolved dependencies.", inputSchema: schema([
                "containerKind": "Optional area or project.",
                "containerId": "Optional area/project UUID.",
                "limit": "Optional result limit, capped at 200.",
            ])),
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
        return nil
    }

    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values)? = self[key] else { return nil }
        return values.compactMap(\.stringValue)
    }
}
