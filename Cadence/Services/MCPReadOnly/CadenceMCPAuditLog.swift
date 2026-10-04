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

    /// Exact totals still cost a scan, but memory is bounded by a chunk, one line and the page.
    /// Capture EOF once so an append between the count and page passes cannot shift the page.
    static func recentEntries(limit: Int, offset: Int = 0, logURL: URL) throws -> CadencePage<CadenceMCPAuditEntry> {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return .empty(offset: max(offset, 0)) }
        let handle = try FileHandle(forReadingFrom: logURL)
        defer { try? handle.close() }
        let endOfFile = try handle.seekToEnd()
        var totalCount = 0
        try scanLines(in: handle, through: endOfFile) { line in
            guard String(data: line, encoding: .utf8) != nil else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            totalCount += 1
        }

        let start = min(max(offset, 0), totalCount)
        let end = start + min(CadenceMCPServiceSupport.cappedLimit(limit), totalCount - start)
        let selected = (totalCount - end)..<(totalCount - start)
        let decoder = JSONDecoder()
        var items: [CadenceMCPAuditEntry] = []
        if !selected.isEmpty {
            var index = 0
            try scanLines(in: handle, through: endOfFile) { line in
                if selected.contains(index) {
                    items.append(try decoder.decode(CadenceMCPAuditEntry.self, from: line))
                }
                index += 1
            }
        }
        return CadencePage(
            items: items.reversed(), offset: start, returnedCount: items.count,
            totalCount: totalCount, hasMore: end < totalCount,
            nextOffset: end < totalCount ? end : nil
        )
    }

    private static func scanLines(
        in handle: FileHandle,
        through endOfFile: UInt64,
        visit: (Data) throws -> Void
    ) throws {
        try handle.seek(toOffset: 0)
        var remaining = endOfFile
        var line = Data()
        while remaining > 0 {
            var chunk = try handle.read(upToCount: Int(min(remaining, 64 * 1024))) ?? Data()
            guard !chunk.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            let firstChunk = remaining == endOfFile
            remaining -= UInt64(chunk.count)
            // Foundation's UTF-8 file reader consumes an initial BOM, including a BOM-only file.
            if firstChunk, chunk.starts(with: [0xEF, 0xBB, 0xBF]) { chunk.removeFirst(3) }
            var fragmentStart = chunk.startIndex
            for index in chunk.indices where chunk[index] == 0x0A {
                // String.split on a newline Character does not split the CRLF grapheme.
                let previous = index == chunk.startIndex ? line.last : chunk[index - 1]
                if previous == 0x0D { continue }
                line.append(chunk[fragmentStart..<index])
                if !line.isEmpty { try visit(line) }
                line.removeAll(keepingCapacity: true)
                fragmentStart = index + 1
            }
            line.append(chunk[fragmentStart..<chunk.endIndex])
        }
        if !line.isEmpty { try visit(line) }
    }
}
