import Foundation

nonisolated struct CadenceMCPAuditEntry: Codable, Sendable {
    let timestamp: String
    let tool: String
    let entityType: String
    let entityId: String
    let summary: String
}

nonisolated struct CadenceMCPAuditLogger: Sendable {
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

    /// The audit log newest-first, paged rather than silently windowed.
    ///
    /// The window itself is unchanged — newest `limit` entries, newest first. What is new is that
    /// the response says how many entries the log actually holds, so a caller that asked for 50
    /// and received 50 can tell a complete log from a tail. Lines are counted before any decoding
    /// and only the paged slice is decoded, so the total costs a scan, not a parse.
    static func recentEntries(limit: Int, offset: Int = 0, logURL: URL) throws -> CadencePage<CadenceMCPAuditEntry> {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return .empty(offset: max(offset, 0)) }
        let content = try String(contentsOf: logURL, encoding: .utf8)
        let decoder = JSONDecoder()
        let newestFirst = Array(content.split(separator: "\n").reversed())
        return try CadencePage.paging(newestFirst, offset: offset, limit: limit) { line in
            try decoder.decode(CadenceMCPAuditEntry.self, from: Data(line.utf8))
        }
    }
}
