import Foundation
import Testing

struct AgentContextBudgetTests {
    @Test func claudeStartupGuideStaysCompactAndRoutesToReference() throws {
        let guide = try repositoryFile("CLAUDE.md")

        #expect(guide.contains("# Cadence Claude Guide"))
        #expect(guide.contains("docs/CLAUDE_REFERENCE.md"))
        #expect(guide.contains("docs/CONTEXT_INDEX.md"))
        try expectLineCount("CLAUDE.md", isAtMost: 200)
    }

    @Test func activeAgentGuidesStayCompactAndRouteToReferences() throws {
        try expectLineCount("AGENTS.md", isAtMost: 180)
        try expectLineCount("Cadence/Shared/AGENTS.md", isAtMost: 160)
        try expectLineCount("Cadence/iOS/AGENTS.md", isAtMost: 160)

        #expect(try repositoryFile("AGENTS.md").contains("docs/AGENTS_REFERENCE.md"))
        #expect(try repositoryFile("AGENTS.md").contains("docs/CONTEXT_INDEX.md"))
        #expect(try repositoryFile("Cadence/Shared/AGENTS.md").contains("../../docs/SHARED_AGENTS_REFERENCE.md"))
        #expect(try repositoryFile("Cadence/iOS/AGENTS.md").contains("../../docs/IOS_AGENTS_REFERENCE.md"))
    }

    @Test func longClaudeReferenceRemainsExplicitlyArchived() throws {
        let reference = try repositoryFile("docs/CLAUDE_REFERENCE.md")

        #expect(reference.contains("Long Claude Reference"))
        #expect(reference.contains("former long `CLAUDE.md`"))
        #expect(reference.contains("Do not load"))
        #expect(reference.contains("## Calendar / Events"))
    }

    @Test func longAgentReferencesRemainExplicitlyArchived() throws {
        let root = try repositoryFile("docs/AGENTS_REFERENCE.md")
        let shared = try repositoryFile("docs/SHARED_AGENTS_REFERENCE.md")
        let iOS = try repositoryFile("docs/IOS_AGENTS_REFERENCE.md")

        #expect(root.contains("former long root `AGENTS.md`"))
        #expect(shared.contains("former long `Cadence/Shared/AGENTS.md`"))
        #expect(iOS.contains("former long `Cadence/iOS/AGENTS.md`"))
        #expect(root.contains("## Red Runs That Are Not Regressions"))
        #expect(shared.contains("## Source-Scanning Tests"))
        #expect(iOS.contains("## The Task Inspector Is Presented By A Host"))
    }

    @Test func contextIndexRoutesByChangeType() throws {
        let index = try repositoryFile("docs/CONTEXT_INDEX.md")

        #expect(index.contains("SwiftData model"))
        #expect(index.contains("Shared UI/component/theme/date logic"))
        #expect(index.contains("iOS/iPadOS UI"))
        #expect(index.contains("MCP server/plugin"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

private func repositoryFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func expectLineCount(_ relativePath: String, isAtMost limit: Int) throws {
    let lineCount = try repositoryFile(relativePath)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .count
    #expect(lineCount <= limit, "\(relativePath) has \(lineCount) lines; keep active agent context compact.")
}
