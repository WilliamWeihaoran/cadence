import Foundation
import SQLite3
import Testing

/// A `default.store` that is a real, closed SQLite database holding one marker string (T-3044 (c)).
///
/// The restore gate refuses a store file without SQLite's 16-byte header, so restore fixtures can
/// no longer stand up `Data(marker.utf8)` as a store. This writes a one-table database instead and
/// reads the marker back through a read-only `immutable=1` connection, which ignores whatever
/// synthetic `-wal` text a fixture keeps beside it (the database is in rollback mode, so SQLite
/// never treats those bytes as a WAL). Every path is the calling test's own temp directory.
enum CadenceSQLiteMarkerStoreFixture {
    /// Replace the file at `url` with a database whose `fixture_marker` table holds `marker`.
    static func write(_ marker: String, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
        try #require(sqlite3_exec(database, "CREATE TABLE fixture_marker (value TEXT NOT NULL)", nil, nil, nil) == SQLITE_OK)
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(database, "INSERT INTO fixture_marker VALUES (?1)", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        try #require(sqlite3_bind_text(statement, 1, marker, -1, transient) == SQLITE_OK)
        try #require(sqlite3_step(statement) == SQLITE_DONE)
    }

    /// The marker in the database at `url`, or `nil` when the file is missing or is not one of
    /// these databases.
    static func marker(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "file"
        components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        guard let uri = components.string else { return nil }
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            return nil
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM fixture_marker", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }
}
