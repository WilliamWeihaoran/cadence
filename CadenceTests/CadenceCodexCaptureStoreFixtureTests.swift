import Foundation
import SwiftData
import SQLite3
import Testing
@testable import Cadence

/// Offline fixtures for the T-3147 UI measurement, never the app-group store.
@MainActor
struct CadenceCodexCaptureStoreFixtureTests {
    @Test func codexCaptureFixturesPersistTheirMeasuredTaskPopulations() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-capture-fixtures-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for count in [0, 100, 2_000] {
            let directory = root.appendingPathComponent("tasks-\(count)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("default.store")
            try writeFixture(count: count, to: url)
            let container = try openFixture(at: url)
            let stored = try ModelContext(container).fetchCount(FetchDescriptor<AppTask>())
            #expect(stored == count)
            let exported = directory.appendingPathComponent("export.store")
            try exportFixture(from: url, to: exported)
            let copied = try ModelContext(openFixture(at: exported)).fetchCount(FetchDescriptor<AppTask>())
            #expect(copied == count, "The exported fixture must include the committed WAL rows")
            Attachment.record(Array(try Data(contentsOf: exported)), named: "capture-tasks-\(count).store")
            print("CAPTURE-FIXTURE count=\(stored) directory=\(directory.path)")
        }
    }

    private func writeFixture(count: Int, to url: URL) throws {
        let container = try openFixture(at: url)
        let context = ModelContext(container)
        for index in 0..<count {
            context.insert(AppTask(title: "Capture load task \(index)"))
        }
        try context.save()
    }

    private func openFixture(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(
                "CodexCaptureFixture", schema: CadenceSchema.schema,
                url: url, cloudKitDatabase: .none
            )
        )
    }

    /// SQLite backup includes committed WAL contents in one coherent attachment.
    private func exportFixture(from source: URL, to destination: URL) throws {
        var reader: OpaquePointer?
        var writer: OpaquePointer?
        defer { sqlite3_close(reader); sqlite3_close(writer) }
        guard sqlite3_open_v2(source.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open(destination.path, &writer) == SQLITE_OK,
              let backup = sqlite3_backup_init(writer, "main", reader, "main") else {
            throw NSError(domain: "CodexCaptureFixture", code: 1)
        }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else {
            throw NSError(domain: "CodexCaptureFixture", code: Int(result))
        }
    }
}
