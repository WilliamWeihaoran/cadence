import Foundation
import Testing

/// `CadenceMCPServer/` has no unit coverage at all — the router, the tool definitions and the
/// argument parsing are exercised only by `plugins/cadence-mcp/scripts/smoke-test.py`, and none of
/// those three files is compiled into the `Cadence` app target, so `CadenceTests` cannot reference
/// a symbol from any of them. These are therefore source-scanning tests by necessity, not by
/// laziness (see "Source-Scanning Tests: The Two Ways They Go Wrong" in `Cadence/Shared/AGENTS.md`).
///
/// What they pin is the failure `CadenceMCPServer/AGENTS.md` calls out by name: "the 30 tool names
/// are a contract in three places at once — the advertised schema, the router's `case` arms, and
/// the smoke test's expectations — and the definitions/router pair will compile perfectly while
/// disagreeing." A tool advertised but not routed is a runtime "Unknown tool"; a tool routed but
/// not advertised is unreachable; and a write tool missing from `writeToolNames` is advertised
/// *and* executable in the default read-only mode, which is a data-safety hole rather than a typo.
struct CadenceMCPToolContractTests {

    // MARK: - The three-way name contract

    @Test func advertisedToolsAndRouterArmsNameTheSameTools() throws {
        let advertised = try advertisedToolNames()
        let routed = try Set(routerArms().keys)

        #expect(advertised == routed)
        #expect(advertised.subtracting(routed).isEmpty)
        #expect(routed.subtracting(advertised).isEmpty)
    }

    @Test func smokeTestExpectsExactlyTheToolsTheServerAdvertises() throws {
        let advertised = try advertisedToolNames()
        let expected = try pythonSetLiteral(named: "EXPECTED_TOOLS")
        let writes = try pythonSetLiteral(named: "WRITE_TOOLS")

        // `EXPECTED_TOOLS = { ...read-only... } | WRITE_TOOLS`, so the literal block holds only the
        // read-only half; the union is what the smoke test actually asserts against `tools/list`.
        #expect(expected.union(writes) == advertised)
    }

    /// The one with teeth. `CadenceMCPToolDefinitions.writeToolNames` decides what
    /// `tools(writesEnabled: false)` filters out of the advertised schema;
    /// `requireWriteService(for:)` decides what actually refuses to run. A tool present in the
    /// second set and absent from the first is still gated at execution — but a tool present in
    /// the router as a mutation and absent from *both* is a write that runs in read-only mode.
    @Test func writeGatingAgreesAcrossDefinitionsRouterAndSmokeTest() throws {
        let declaredWrites = try declaredWriteToolNames()
        let arms = try routerArms()
        let gatedArms = Set(arms.filter { $0.value.contains("requireWriteService") }.keys)
        let smokeWrites = try pythonSetLiteral(named: "WRITE_TOOLS")

        #expect(declaredWrites == gatedArms)
        #expect(declaredWrites == smokeWrites)
    }

    /// Every router arm that reaches `CadenceWriteService` must be gated. This is the assertion
    /// that survives someone adding a mutation to an existing read arm rather than a new tool.
    @Test func everyRouterArmTouchingTheWriteServiceIsGated() throws {
        let arms = try routerArms()
        let touchesWriteService = arms.filter { $0.value.contains("writeService.") }
        let ungated = touchesWriteService.filter { !$0.value.contains("requireWriteService") }

        let declaredWrites = try declaredWriteToolNames()

        #expect(ungated.isEmpty, "ungated write arms: \(ungated.keys.sorted())")
        #expect(Set(touchesWriteService.keys) == declaredWrites)
    }

    // MARK: - Non-vacuity and regex self-checks
    //
    // Every zero-count assertion above passes against an empty string, which is what a `/tmp`
    // against `/private/tmp` path mismatch produces on an isolated build tree.

    @Test func sourceScansActuallyReadTheFiles() throws {
        let definitions = try sourceFile(Self.definitionsPath)
        let router = try sourceFile(Self.routerPath)
        let smoke = try sourceFile(Self.smokeTestPath)
        let advertised = try advertisedToolNames()
        let arms = try routerArms()
        let writes = try declaredWriteToolNames()

        #expect(definitions.count > 5_000)
        #expect(router.count > 5_000)
        #expect(smoke.count > 5_000)

        #expect(advertised.count >= 25)
        #expect(arms.count >= 25)
        #expect(writes.count >= 5)
        #expect(advertised.contains("mcp_diagnostics"))
        #expect(writes.contains("create_task"))
        #expect(writes.contains("list_tasks") == false)
    }

    @Test func extractorsMatchWhatTheyClaimAndRejectWhatTheyShould() throws {
        // Tool-name needle: must find a real declaration, must not find a mention in prose.
        #expect(toolNames(inSwift: #"Tool(name: "alpha_tool", description: "x")"#) == ["alpha_tool"])
        #expect(toolNames(inSwift: #"// see Tool name alpha_tool for details"#).isEmpty)

        // Case-arm needle: line-anchored, so a `case "x":` inside a string or a trailing comment
        // is not a router arm.
        let armFixture = """
        switch name {
        case "read_thing":
            return try encode(readService.thing())

        case "write_thing":
            let writeService = try requireWriteService(for: name)
            return try encode(writeService.thing())

        default:
            throw ToolArgumentError.invalid("Unknown tool: \\(name)")
        }
        """
        let fixtureArms = armsSplittingCases(in: armFixture)
        #expect(Set(fixtureArms.keys) == ["read_thing", "write_thing"])
        #expect(fixtureArms["write_thing"]?.contains("requireWriteService") == true)
        #expect(fixtureArms["read_thing"]?.contains("requireWriteService") == false)
        #expect(fixtureArms["read_thing"]?.contains("Unknown tool") == false)

        // Python set-literal needle: must stop at the closing brace, not run into the next set.
        let pyFixture = """
        FIRST = {
            "a",
            "b",
        }
        SECOND = {
            "c",
        } | FIRST
        """
        #expect(setLiteral(named: "FIRST", inPython: pyFixture) == ["a", "b"])
        #expect(setLiteral(named: "SECOND", inPython: pyFixture) == ["c"])
        #expect(setLiteral(named: "THIRD", inPython: pyFixture).isEmpty)

        // Comment stripper: prove it strips, on a literal, since the two MCP server files happen
        // to contain no comments at all today and an "it stripped something" check would be
        // vacuous against them.
        #expect(strippingComments("let a = 1 // note\n/* block */let b = 2").contains("note") == false)
        #expect(strippingComments("let a = 1 // note\n/* block */let b = 2").contains("let b = 2"))
    }
}

// MARK: - Extraction

private extension CadenceMCPToolContractTests {
    static let definitionsPath = "CadenceMCPServer/CadenceMCPToolDefinitions.swift"
    static let routerPath = "CadenceMCPServer/CadenceMCPToolRouter.swift"
    static let smokeTestPath = "plugins/cadence-mcp/scripts/smoke-test.py"

    func advertisedToolNames() throws -> Set<String> {
        toolNames(inSwift: strippingComments(try sourceFile(Self.definitionsPath)))
    }

    func declaredWriteToolNames() throws -> Set<String> {
        let source = strippingComments(try sourceFile(Self.definitionsPath))
        guard let start = source.range(of: "writeToolNames: Set<String> = ["),
              let end = source.range(of: "]", range: start.upperBound..<source.endIndex) else {
            return []
        }
        return quotedIdentifiers(in: String(source[start.upperBound..<end.lowerBound]))
    }

    func routerArms() throws -> [String: String] {
        armsSplittingCases(in: strippingComments(try sourceFile(Self.routerPath)))
    }

    func pythonSetLiteral(named name: String) throws -> Set<String> {
        setLiteral(named: name, inPython: try sourceFile(Self.smokeTestPath))
    }

    func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    func toolNames(inSwift source: String) -> Set<String> {
        matches(of: #"Tool\(name: "([a-z_]+)""#, in: source)
    }

    /// Line-anchored so that only a real `case "name":` arm counts. Bodies run to the next arm or
    /// to `default:`, which keeps the router's fallthrough error text out of every arm's body.
    func armsSplittingCases(in source: String) -> [String: String] {
        var arms: [String: String] = [:]
        var current: String?
        var body: [String] = []

        func flush() {
            if let current { arms[current] = body.joined(separator: "\n") }
            current = nil
            body = []
        }

        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("case \""), trimmed.hasSuffix("\":"),
               let name = matches(of: #"^case "([a-z_]+)":$"#, in: trimmed).first {
                flush()
                current = name
                continue
            }
            if trimmed == "default:" {
                flush()
                continue
            }
            if current != nil { body.append(line) }
        }
        flush()
        return arms
    }

    func setLiteral(named name: String, inPython source: String) -> Set<String> {
        guard let start = source.range(of: "\(name) = {"),
              let end = source.range(of: "\n}", range: start.upperBound..<source.endIndex) else {
            return []
        }
        return quotedIdentifiers(in: String(source[start.upperBound..<end.lowerBound]))
    }

    func quotedIdentifiers(in block: String) -> Set<String> {
        matches(of: #""([a-z_]+)""#, in: block)
    }

    func matches(of pattern: String, in source: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let range = NSRange(source.startIndex..., in: source)
        var found: Set<String> = []
        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match, let captured = Range(match.range(at: 1), in: source) else { return }
            found.insert(String(source[captured]))
        }
        return found
    }

    func strippingComments(_ source: String) -> String {
        var result = source
        for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
            while let range = result.range(of: pattern, options: .regularExpression) {
                result.replaceSubrange(
                    range,
                    with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
                )
            }
        }
        return result
    }
}
