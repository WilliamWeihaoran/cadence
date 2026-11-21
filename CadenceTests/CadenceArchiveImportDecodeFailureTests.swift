import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-18924]] -- a file that is not a Cadence archive said only Foundation's "couldn't be read".**
///
/// Choosing another app's JSON, or a truncated archive, in Import Archive failed at the decode
/// step with a bare `DecodingError`, so the card read "Import failed: The data couldn't be read
/// because it is missing." -- true, and no help. Every *validation* refusal already had a plain
/// sentence in `CadenceArchiveImportFailure`; the decode step, which is the one a wrong-file pick
/// actually hits, now has one too.
@Suite(.preservesTheStoredLaunchReports)
@MainActor
struct CadenceArchiveImportDecodeFailureTests {
    /// Valid JSON of the wrong shape, an array, a truncated document and bytes that are not JSON.
    static let wrongFiles: [String] = ["{}", "{\"hello\":\"world\"}", "[1,2]", "{\"formatVersion\": 1, \"tasks\": [", "not json at all"]

    @Test func everyWrongFileIsRefusedAsNotACadenceArchive() throws {
        let destination = ModelContext(try CadenceTestStore.container())
        for text in Self.wrongFiles {
            #expect(throws: CadenceArchiveImportFailure.notACadenceArchive, "\(text)") {
                try CadenceArchiveImportService.plan(Data(text.utf8), in: destination)
            }
            #expect(throws: CadenceArchiveImportFailure.notACadenceArchive, "\(text)") {
                try CadenceArchiveImportService.decodeArchive(Data(text.utf8))
            }
        }
    }

    /// A real archive still decodes: the translation is for `DecodingError` only.
    @Test func aRealArchiveStillPlans() throws {
        let source = ModelContext(try CadenceTestStore.container())
        source.insert(AppTask(title: "Buy milk"))
        try source.save()
        let data = try CadenceDataExportService.encode(try CadenceDataExportService.makeArchive(in: source))

        let plan = try CadenceArchiveImportService.plan(data, in: ModelContext(try CadenceTestStore.container()))
        #expect(plan.changesAnything)
    }

    @Test func theSentenceSaysWhatTheFileIsAndThatNothingChanged() {
        let failure = CadenceArchiveImportFailure.notACadenceArchive
        #expect(failure.message == "This file isn't a Cadence archive, or it is damaged, so it cannot be imported. Nothing was changed.")
        #expect(failure.errorDescription == failure.message)
    }

    /// The card a user reads, through the shared flow both platforms mount.
    @Test func theImportCardNoLongerSaysCouldNotBeRead() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-T-18924-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("someone-elses-export.json")
        try Data("[1,2]".utf8).write(to: url)

        let flow = CadenceArchiveImportFlow()
        flow.preview(.success(url), in: try CadenceTestStore.container())

        #expect(flow.plan == nil)
        #expect(flow.statusMessage == CadenceArchiveImportPresentation.failureMessage(
            CadenceArchiveImportFailure.notACadenceArchive.message
        ))
        #expect(flow.statusMessage?.contains("couldn't be read") == false)
    }
}
