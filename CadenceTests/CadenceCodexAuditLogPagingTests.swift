import Foundation
import Testing
@testable import Cadence

struct CadenceCodexAuditLogPagingTests {
    @Test func codexAuditReaderKeepsItsChunkBoundAndAvoidsWholeFileMaterialization() throws {
        let bounded = try CadenceScanInstrument(
            "bounded audit-log read",
            fires: "handle.read(upToCount: Int(min(remaining, 64 * 1024)))",
            andNotOn: "// handle.read(upToCount: Int(min(remaining, 64 * 1024)))\nString(contentsOf: logURL, encoding: .utf8)",
            by: { CadenceSourceScan.codeOnly($0).contains("read(upToCount: Int(min(remaining, 64 * 1024)))") }
        )
        let paths = ["Cadence/Services/MCPReadOnly/CadenceMCPAuditLog.swift"]
        #expect(try bounded.sweep(paths, atLeast: 1, including: paths[0], read: CadenceSourceScan.strippedSourceReader()) == paths)
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(paths[0]))
        #expect(!code.contains("String(contentsOf:"))
        #expect(code.contains("let endOfFile = try handle.seekToEnd()"))
        #expect(code.contains("selected.contains(index)"))
    }

    @Test func codexChunkedAuditPagesMatchTheWholeLogOracle() throws {
        let entries = (0..<205).map { entry($0, summary: $0 == 111 ? String(repeating: "\u{00e9}", count: 40_000) : "record \($0)") }
        var bytes = Data()
        for (index, item) in entries.enumerated() {
            bytes.append(try JSONEncoder().encode(item))
            bytes.append(contentsOf: index == entries.count - 1 ? [] : [0x0A, 0x0A])
        }
        try withLog(bytes) { url in
            for (offset, limit) in [(-1, 3), (0, 1), (7, 15), (93, 0), (120, 500), (300, 9), (2, -1)] {
                let actual = try CadenceMCPAuditLogger.recentEntries(limit: limit, offset: offset, logURL: url)
                let oldContent = try String(contentsOf: url, encoding: .utf8)
                let expected = try CadencePage<CadenceMCPAuditEntry>.paging(
                    Array(oldContent.split(separator: "\n").reversed()), offset: offset, limit: limit
                ) { try JSONDecoder().decode(CadenceMCPAuditEntry.self, from: Data($0.utf8)) }
                #expect(actual.items.map(\.entityId) == expected.items.map(\.entityId))
                #expect(actual.items.map(\.summary) == expected.items.map(\.summary))
                #expect(actual.offset == expected.offset)
                #expect(actual.totalCount == expected.totalCount)
                #expect(actual.returnedCount == expected.returnedCount)
                #expect(actual.hasMore == expected.hasMore)
                #expect(actual.nextOffset == expected.nextOffset)
            }
        }
    }

    @Test func codexAuditReaderDecodesOnlyTheSelectedJSONButValidatesAllUTF8() throws {
        var bytes = Data("not JSON\n".utf8)
        bytes.append(try JSONEncoder().encode(entry(1)))
        try withLog(bytes) { url in
            let page = try CadenceMCPAuditLogger.recentEntries(limit: 1, logURL: url)
            #expect(page.totalCount == 2)
            #expect(page.items.map(\.entityId) == ["1"])
            #expect(throws: (any Error).self) {
                try CadenceMCPAuditLogger.recentEntries(limit: 1, offset: 1, logURL: url)
            }
        }
        var invalidUTF8 = Data([0xFF, 0x0A])
        invalidUTF8.append(try JSONEncoder().encode(entry(2)))
        try withLog(invalidUTF8) { url in
            #expect(throws: (any Error).self) {
                try CadenceMCPAuditLogger.recentEntries(limit: 1, logURL: url)
            }
        }
    }

    @Test func codexAuditReaderPreservesMissingAndEmptyFileOffsets() throws {
        try withLog(Data("\n\n".utf8)) { url in
            let page = try CadenceMCPAuditLogger.recentEntries(limit: 20, offset: 10, logURL: url)
            #expect(page.totalCount == 0)
            #expect(page.offset == 0)
            try FileManager.default.removeItem(at: url)
            #expect(try CadenceMCPAuditLogger.recentEntries(limit: 20, offset: 10, logURL: url).offset == 10)
        }
    }

    @Test func codexAuditReaderKeepsFoundationNewlineAndBOMSemantics() throws {
        let encoded = try JSONEncoder().encode(entry(1))
        for bytes in [Data([0xEF, 0xBB, 0xBF]), Data([0xEF, 0xBB, 0xBF]) + encoded, encoded + Data("\r\n".utf8) + encoded] {
            try withLog(bytes) { url in
                let content = try String(contentsOf: url, encoding: .utf8)
                let lines = Array(content.split(separator: "\n").reversed())
                if lines.isEmpty {
                    #expect(try CadenceMCPAuditLogger.recentEntries(limit: 1, logURL: url).totalCount == 0)
                } else if (try? JSONDecoder().decode(CadenceMCPAuditEntry.self, from: Data(lines[0].utf8))) != nil {
                    #expect(try CadenceMCPAuditLogger.recentEntries(limit: 1, logURL: url).items.map(\.entityId) == ["1"])
                } else {
                    #expect(throws: (any Error).self) { try CadenceMCPAuditLogger.recentEntries(limit: 1, logURL: url) }
                }
            }
        }
    }

    private func entry(_ id: Int, summary: String = "Entry") -> CadenceMCPAuditEntry {
        CadenceMCPAuditEntry(timestamp: "2026-10-04T12:00:00Z", tool: "fixture", entityType: "task", entityId: String(id), summary: summary)
    }

    private func withLog(_ bytes: Data, body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cadence-codex-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("audit.jsonl")
        try bytes.write(to: url)
        try body(url)
    }
}
