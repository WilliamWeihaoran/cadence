import Foundation

struct CadenceMCPAuditEntry: Codable, Sendable {
    let timestamp: String
    let tool: String
    let entityType: String
    let entityId: String
    let summary: String
}

struct CadenceMCPAuditLogger: Sendable {
    let logURL: URL
    private let clock: @Sendable () -> Date

    init(logURL: URL, clock: @escaping @Sendable () -> Date = Date.init) {
        self.logURL = logURL
        self.clock = clock
    }

    static func defaultLogger() throws -> CadenceMCPAuditLogger {
        try CadenceMCPAuditLogger(logURL: CadenceModelContainerFactory.auditLogURL())
    }

    func record(tool: String, entityType: String, entityId: String, summary: String) throws {
        let entry = CadenceMCPAuditEntry(
            timestamp: ISO8601DateFormatter().string(from: clock()),
            tool: tool,
            entityType: entityType,
            entityId: entityId,
            summary: summary
        )
        var data = try JSONEncoder().encode(entry)
        data.append(0x0A)

        let directoryURL = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: logURL, options: .atomic)
        }
    }

    static func recentEntries(limit: Int, logURL: URL) throws -> [CadenceMCPAuditEntry] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let content = try String(contentsOf: logURL, encoding: .utf8)
        let decoder = JSONDecoder()
        let entries = try content
            .split(separator: "\n")
            .suffix(CadenceMCPServiceSupport.cappedLimit(limit))
            .map { line in
                try decoder.decode(CadenceMCPAuditEntry.self, from: Data(line.utf8))
            }
        return Array(entries.reversed())
    }
}
