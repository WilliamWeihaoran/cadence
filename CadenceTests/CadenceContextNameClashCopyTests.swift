import Foundation
import Testing
@testable import Cadence

/// [[T-5808]]: the four duplicate-name refusals for a context say "context", from one copy.
///
/// iOS's context editor called a context a "list" — a different object in this app — while the
/// Mac's create sheet and settings row said "context". The Mac half is called directly; the iOS
/// half is inside `#if os(iOS)` and this target builds for macOS, so it is read as source text.
@MainActor
struct CadenceContextNameClashCopyTests {
    @Test func bothRefusalsNameAContextAndTheContextInTheWay() {
        let created = CadenceContextNameClashCopy.notCreated("Work")
        let renamed = CadenceContextNameClashCopy.notRenamed("Work")

        for sentence in [created, renamed] {
            #expect(sentence.hasPrefix(#"A context named "Work" already exists."#))
            #expect(!sentence.lowercased().contains("list"), "a context refusal calls it a list: \(sentence)")
        }
        #expect(created.contains("was not created"))
        #expect(renamed.contains("was not renamed"))
        #expect(created != renamed)
    }

    @Test func theMacRefusalsReadTheSharedCopy() {
        #expect(CreateContextSheet.duplicateNameNotice("Home") == CadenceContextNameClashCopy.notCreated("Home"))
        #expect(ContextSettingsRow.duplicateRenameNotice("Home") == CadenceContextNameClashCopy.notRenamed("Home"))
    }

    @Test func theIOSRefusalsReadTheSharedCopyAndNeverSayList() throws {
        let path = "Cadence/iOS/iOSSettingsContextSection.swift"
        let code = CadenceSourceScan.strippingComments(
            try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
        )
        #expect(code.contains("struct iOSContextEditorSheet"), "non-vacuity: wrong file")

        let created = try body(of: "static func duplicateNameNotice", in: code)
        let renamed = try body(of: "static func duplicateRenameNotice", in: code)
        #expect(created.contains("CadenceContextNameClashCopy.notCreated("), "iOS create refusal: \(created)")
        #expect(renamed.contains("CadenceContextNameClashCopy.notRenamed("), "iOS rename refusal: \(renamed)")
        #expect(!code.contains("A list named"), "the iOS context editor says \"list\" again (T-5808)")
    }

    /// The text between a function's opening brace and the next line that closes at its indent.
    private func body(of signature: String, in code: String) throws -> Substring {
        let start = try #require(code.range(of: signature))
        let open = try #require(code.range(of: "{", range: start.upperBound..<code.endIndex))
        let close = try #require(code.range(of: "\n    }", range: open.upperBound..<code.endIndex))
        return code[open.upperBound..<close.lowerBound]
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
