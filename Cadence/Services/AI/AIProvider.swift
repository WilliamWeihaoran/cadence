import Foundation

struct AITextNoteContext: Codable, Equatable, Sendable {
    var title: String
    var content: String
    var containerName: String?
}

struct AITaskDraft: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var title: String
    var notes: String
    var priority: String
    var dueDate: String
    var scheduledDate: String
    var scheduledStartMin: Int?
    var estimatedMinutes: Int?
    var sectionName: String
    var subtaskTitles: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case notes
        case priority
        case dueDate
        case scheduledDate
        case scheduledStartMin
        case estimatedMinutes
        case sectionName
        case subtaskTitles
    }

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        priority: String = "none",
        dueDate: String = "",
        scheduledDate: String = "",
        scheduledStartMin: Int? = nil,
        estimatedMinutes: Int? = nil,
        sectionName: String = TaskSectionDefaults.defaultName,
        subtaskTitles: [String] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.dueDate = dueDate
        self.scheduledDate = scheduledDate
        self.scheduledStartMin = scheduledStartMin
        self.estimatedMinutes = estimatedMinutes
        self.sectionName = sectionName
        self.subtaskTitles = subtaskTitles
    }
}

struct AITaskDraftResponse: Codable, Equatable, Sendable {
    var tasks: [AITaskDraft]
}

protocol AIProvider {
    func summarizeNote(_ context: AITextNoteContext) async throws -> String
    func extractTasks(from context: AITextNoteContext) async throws -> [AITaskDraft]
}

enum AIProviderError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case emptyResponse
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an OpenAI API key in Settings → AI first."
        case .invalidURL:
            return "The OpenAI endpoint URL is invalid."
        case .emptyResponse:
            return "The model returned an empty response."
        case .invalidResponse:
            return "OpenAI returned a response Cadence could not read."
        case .apiError(let statusCode, let message):
            return "OpenAI request failed (\(statusCode)): \(message)"
        case .decodingFailed(let message):
            return "Could not decode the AI response: \(message)"
        }
    }
}

final class OpenAIResponsesProvider: AIProvider {
    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let endpoint: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        apiKey: String,
        model: String,
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.endpoint = endpoint
    }

    func summarizeNote(_ context: AITextNoteContext) async throws -> String {
        let request = OpenAIResponseRequest(
            model: model,
            instructions: """
            You are helping inside Cadence, a local personal planning app.
            Summarize the selected note in concise markdown. Preserve concrete decisions, dates, tasks, and names.
            Do not invent details and do not ask follow-up questions.
            """,
            input: prompt(for: context),
            text: nil,
            maxOutputTokens: 700
        )
        return try await send(request).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractTasks(from context: AITextNoteContext) async throws -> [AITaskDraft] {
        let request = OpenAIResponseRequest(
            model: model,
            instructions: """
            Extract actionable Cadence task drafts from the selected note.
            Return only tasks that are clearly implied by the note.
            Use ISO yyyy-MM-dd for dueDate and scheduledDate when explicit; otherwise use an empty string.
            Use scheduledStartMin as minutes from midnight only when explicit; otherwise null.
            Use priority as one of: none, low, medium, high.
            Keep notes concise and cite useful source context from the note.
            """,
            input: prompt(for: context),
            text: .init(format: .taskDraftsSchema),
            maxOutputTokens: 1_600
        )
        let output = try await send(request)
        guard let data = output.data(using: .utf8) else {
            throw AIProviderError.decodingFailed("The JSON output was not UTF-8.")
        }
        do {
            return try decoder.decode(AITaskDraftResponse.self, from: data).tasks
        } catch {
            throw AIProviderError.decodingFailed(error.localizedDescription)
        }
    }

    func makeURLRequest(for requestBody: OpenAIResponseRequest) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestBody)
        return request
    }

    private func send(_ requestBody: OpenAIResponseRequest) async throws -> String {
        let request = try makeURLRequest(for: requestBody)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIProviderError.apiError(
                statusCode: httpResponse.statusCode,
                message: OpenAIErrorPayload.message(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        let decoded = try decoder.decode(OpenAIResponsePayload.self, from: data)
        guard let text = decoded.outputText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw AIProviderError.emptyResponse
        }
        return text
    }

    private func prompt(for context: AITextNoteContext) -> String {
        """
        Note title: \(context.title)
        Container: \(context.containerName ?? "None")

        Note content:
        \(context.content)
        """
    }
}

struct OpenAIResponseRequest: Codable, Equatable {
    var model: String
    var instructions: String
    var input: String
    var text: OpenAITextConfig?
    var maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case text
        case maxOutputTokens = "max_output_tokens"
    }
}

struct OpenAITextConfig: Codable, Equatable {
    var format: OpenAITextFormat
}

struct OpenAITextFormat: Codable, Equatable {
    var type: String
    var name: String?
    var strict: Bool?
    var schema: JSONValue?

    static let taskDraftsSchema = OpenAITextFormat(
        type: "json_schema",
        name: "cadence_task_drafts",
        strict: true,
        schema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("tasks")]),
            "properties": .object([
                "tasks": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "required": .array([
                            .string("title"),
                            .string("notes"),
                            .string("priority"),
                            .string("dueDate"),
                            .string("scheduledDate"),
                            .string("scheduledStartMin"),
                            .string("estimatedMinutes"),
                            .string("sectionName"),
                            .string("subtaskTitles"),
                        ]),
                        "properties": .object([
                            "title": .object(["type": .string("string")]),
                            "notes": .object(["type": .string("string")]),
                            "priority": .object([
                                "type": .string("string"),
                                "enum": .array(["none", "low", "medium", "high"].map(JSONValue.string)),
                            ]),
                            "dueDate": .object(["type": .string("string")]),
                            "scheduledDate": .object(["type": .string("string")]),
                            "scheduledStartMin": .object([
                                "type": .array([.string("integer"), .string("null")]),
                            ]),
                            "estimatedMinutes": .object([
                                "type": .array([.string("integer"), .string("null")]),
                            ]),
                            "sectionName": .object(["type": .string("string")]),
                            "subtaskTitles": .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("string")]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ])
    )
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
}

private struct OpenAIResponsePayload: Decodable {
    var outputText: String?
    var output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var resolvedText: String? {
        if let outputText { return outputText }
        return output?
            .flatMap(\.content)
            .compactMap(\.text)
            .joined(separator: "\n")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        output = try container.decodeIfPresent([OutputItem].self, forKey: .output)
        if outputText == nil {
            outputText = output?
                .flatMap(\.content)
                .compactMap(\.text)
                .joined(separator: "\n")
        }
    }

    struct OutputItem: Decodable {
        var content: [ContentItem]
    }

    struct ContentItem: Decodable {
        var text: String?
    }
}

private struct OpenAIErrorPayload: Decodable {
    struct ErrorBody: Decodable {
        var message: String?
    }

    var error: ErrorBody?

    static func message(from data: Data) -> String? {
        try? JSONDecoder().decode(OpenAIErrorPayload.self, from: data).error?.message
    }
}
