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

    // MARK: - Dead argument-parsing helpers

    /// T-260: `Dictionary.int(_:)` and `Dictionary.stringArray(_:)` sat in
    /// `CadenceMCPArgumentParsing.swift` with zero call sites, one keystroke away from the two
    /// helpers that *are* wired up and with quietly different semantics — `int` returns `nil`
    /// where `strictInt` throws, `stringArray` drops non-strings where `flexibleStringArray`
    /// throws. Picking the wrong one turns a tool error into a silently ignored argument, in the
    /// one folder with no unit *execution* at all. Deleting them fixed it once; this keeps it.
    ///
    /// The needle is `arguments.<name>(`, deliberately not `.<name>(`, and that is the whole
    /// point: the ticket had to warn that a scan for `.int(` reports the dead helper as live,
    /// because the tool definitions build JSON-schema payloads with `MCP.Value.int(...)`.
    @Test func everyArgumentParsingHelperIsCalledByTheRouter() throws {
        let helpers = try argumentParsingHelperNames()
        let router = strippingComments(try sourceFile(Self.routerPath))
        let uncalled = helpers.filter { !router.contains("arguments.\($0)(") }

        #expect(uncalled.isEmpty, "argument-parsing helpers with no router call site: \(uncalled.sorted())")
    }

    /// The smoke test is the only thing that *executes* the router, and it dispatched 21 of its
    /// 30 arms when T-259 was filed — a gap nothing reported, because coverage was a property of
    /// what someone had remembered to write rather than something checked. It now records every
    /// `tools/call` it sends and compares that set against the server's own `tools/list` before
    /// printing OK. Deleting those few lines of Python restores the silent gap and breaks no
    /// build, so it is pinned here.
    @Test func theSmokeTestStillChecksItDispatchesEveryAdvertisedTool() throws {
        let smoke = strippingPythonComments(try sourceFile(Self.smokeTestPath))

        #expect(smoke.contains("DISPATCHED.add("))
        #expect(smoke.contains("tool_names - DISPATCHED"))
        #expect(smoke.contains("tools advertised but never dispatched"))
    }

    // MARK: - List-tool DTO shapes (T-269)

    /// Six `list_*` tools — `list_task_bundles`, `list_goals`, `list_habits`, `list_links`,
    /// `list_contexts`, `list_containers` — are dispatched by the smoke test only against a fresh
    /// fixture store, because MCP has no write tool that can put a bundle, a goal, a habit, a
    /// link, a context or a container into one. `create_task` and `append_core_note` are the only
    /// constructors on the surface. So the smoke test can exercise the argument wiring and the
    /// empty-result path for all six, but never observes one row of `CadenceTaskBundleSummary`,
    /// `CadenceGoalSummary`, `CadenceHabitSummary`, `CadenceSavedLinkSummary`, `CadenceContextRef`
    /// or `CadenceContainerRef` coming back over the wire — a renamed or dropped field on any of
    /// them reaches a user's editor with nothing red anywhere.
    ///
    /// T-269 weighed seeding a fixture store out-of-band (a second process opening the same
    /// SwiftData store the server is about to open, with a fixture that has to be hand-kept in
    /// step with `CadenceSchema`) against pinning the DTOs' declared stored-property lists as a
    /// source scan. The scan is what ships: it is cheap, deterministic, needs no store, and this
    /// file is already source-scanning by necessity (see the header comment above) — a seeded
    /// fixture would be the first thing in this target that opens a real `ModelContainer`, which
    /// is a materially different kind of test with its own migration/CloudKit-shape hazards. What
    /// it gives up is real: this cannot catch a *runtime* encoding difference (a custom
    /// `encode(to:)`, a `CodingKeys` remap, or a computed property masquerading as stored). None of
    /// the six DTOs below has one today — plain `nonisolated struct ...: Codable, Sendable` with
    /// only stored `let` properties — so synthesized `Codable` is exactly the declared property
    /// list, which is what makes the scan sound for as long as that stays true.
    ///
    /// One more thing this scan does *not* need, on purpose: the smoke test's `check_keys` takes
    /// optional field names separately because Swift's synthesized `Codable` uses
    /// `encodeIfPresent`, so a `nil` optional is an *absent* key in the actual JSON rather than a
    /// present-but-null one — a runtime key-set comparison that doesn't account for that fails on
    /// correct code. That subtlety is about the wire format of a specific value at a specific
    /// moment; it does not apply to a compile-time scan of the struct's *declaration*, which lists
    /// every stored property — `String?` included — regardless of what any instance happens to
    /// hold. So the assertion below is exact-set equality against the full declared field list, not
    /// a subset-with-named-optionals comparison; optionality is irrelevant to what this test reads.
    @Test func listToolDTOsDeclareTheirEstablishedStoredProperties() throws {
        let source = strippingComments(try sourceFile(Self.readDTOsPath))
        for spec in Self.listToolDTOSpecs {
            let fields = structStoredPropertyNames(spec.structName, in: source)
            #expect(
                fields == spec.expectedFields,
                "\(spec.structName): declared \(fields.sorted()), expected \(spec.expectedFields.sorted())"
            )
        }
    }

    @Test func listToolDTOScanIsNotVacuous() throws {
        let source = strippingComments(try sourceFile(Self.readDTOsPath))
        #expect(source.count > 3_000)
        #expect(Self.listToolDTOSpecs.count == 6)
        for spec in Self.listToolDTOSpecs {
            #expect(spec.expectedFields.isEmpty == false)
            #expect(structStoredPropertyNames(spec.structName, in: source).isEmpty == false)
        }
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

        // The helper scan reads a real extension, and its needle really is discriminating: the
        // definitions file does contain `.int(` while nothing calls the deleted `int` helper, so
        // a receiver-less needle would be unfailable here rather than merely imprecise.
        let helpers = try argumentParsingHelperNames()
        #expect(helpers.count >= 8)
        #expect(helpers.contains("strictInt"))
        #expect(helpers.contains("flexibleStringArray"))
        #expect(helpers.contains("int") == false)
        #expect(helpers.contains("stringArray") == false)
        #expect(definitions.contains(".int("))
        #expect(definitions.contains("arguments.int(") == false)
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

        // The Python stripper has to be quote-aware or it truncates every line holding a `#`
        // inside a string literal — and the markers above live in string literals, so a naive
        // stripper would make that whole test vacuous rather than merely wrong.
        let python = "value = \"a#b\"  # trailing note\n# whole line\nkeep = 1"
        #expect(strippingPythonComments(python).contains("a#b"))
        #expect(strippingPythonComments(python).contains("trailing note") == false)
        #expect(strippingPythonComments(python).contains("whole line") == false)
        #expect(strippingPythonComments(python).contains("keep = 1"))

        // Helper-name extraction takes the extension's own funcs and not the private statics
        // beside them, which are called from inside the same file and have no router call site.
        let helperFixture = """
        extension Dictionary where Key == String, Value == MCP.Value {
            func alpha(_ key: String) -> String? { nil }

            private static func beta(_ value: String) -> Int? { nil }
        }
        """
        #expect(helperNames(inSwift: helperFixture) == ["alpha"])

        // DTO stored-property needle (T-269): must stop at its own struct's closing brace rather
        // than bleeding into the next declaration, must ignore a doc comment that mentions a
        // plausible-looking field name in prose, and must not be fooled by a second struct whose
        // name is the first's with a suffix appended — `Alpha` vs `AlphaSummary` mirrors
        // `CadenceContainerRef` vs `CadenceContainerSummary` in the real file.
        let dtoFixture = strippingComments("""
        nonisolated struct Alpha: Codable, Sendable {
            let id: String
            /// mentions let bogusField: Int only in prose, never as a declaration
            let name: String?
        }

        nonisolated struct AlphaSummary: Codable, Sendable {
            let id: String
            let alpha: Alpha?
            let title: String
        }
        """)
        #expect(structStoredPropertyNames("Alpha", in: dtoFixture) == ["id", "name"])
        #expect(structStoredPropertyNames("AlphaSummary", in: dtoFixture) == ["id", "alpha", "title"])
        #expect(structStoredPropertyNames("Alpha", in: dtoFixture).contains("bogusField") == false)
        #expect(structStoredPropertyNames("Alpha", in: dtoFixture).contains("title") == false)
        #expect(structStoredPropertyNames("Missing", in: dtoFixture).isEmpty)
    }
}

// MARK: - Extraction

private extension CadenceMCPToolContractTests {
    static let definitionsPath = "CadenceMCPServer/CadenceMCPToolDefinitions.swift"
    static let routerPath = "CadenceMCPServer/CadenceMCPToolRouter.swift"
    static let smokeTestPath = "plugins/cadence-mcp/scripts/smoke-test.py"
    static let argumentParsingPath = "CadenceMCPServer/CadenceMCPArgumentParsing.swift"
    static let readDTOsPath = "Cadence/Services/MCPReadOnly/CadenceReadDTOs.swift"

    /// The six `list_*` result-element DTOs `CadenceReadService` returns that T-269 found with no
    /// runtime coverage: `listTaskBundles` -> `CadenceTaskBundleSummary`, `listGoals` ->
    /// `CadenceGoalSummary`, `listHabits` -> `CadenceHabitSummary`, `listLinks` ->
    /// `CadenceSavedLinkSummary`, `listContexts` -> `CadenceContextRef`, `listContainers` ->
    /// `CadenceContainerRef` (`CadenceReadService.swift`). `list_tasks`, `list_tags` and
    /// `list_notes` are excluded on purpose — the smoke test already asserts their DTOs
    /// (`TASK_SUMMARY_KEYS`, `TAG_SUMMARY_KEYS`/`TAG_DETAIL_KEYS`, `NOTE_SUMMARY_KEYS`) against real
    /// rows created through `create_task` and `append_core_note`, which is stronger than a scan.
    struct DTOFieldSpec {
        let structName: String
        let expectedFields: Set<String>
    }

    static let listToolDTOSpecs: [DTOFieldSpec] = [
        DTOFieldSpec(structName: "CadenceTaskBundleSummary", expectedFields: [
            "id", "title", "dateKey", "startMin", "durationMinutes", "endMin",
            "totalEstimatedMinutes", "taskCount", "activeTaskCount", "createdAt",
        ]),
        DTOFieldSpec(structName: "CadenceGoalSummary", expectedFields: [
            "id", "title", "description", "startDate", "endDate", "progressType", "targetHours",
            "loggedHours", "colorHex", "icon", "kind", "status", "progress", "contextId",
            "contextName", "parentGoalId", "parentGoalTitle", "isTopLevel", "linkedListCount",
            "taskCount", "subGoalCount", "habitCount", "createdAt",
        ]),
        DTOFieldSpec(structName: "CadenceHabitSummary", expectedFields: [
            "id", "title", "icon", "colorHex", "frequencyType", "frequencyDays", "targetCount",
            "order", "contextId", "contextName", "goal", "currentStreak", "completionCount",
            "completedToday", "createdAt",
        ]),
        DTOFieldSpec(structName: "CadenceSavedLinkSummary", expectedFields: [
            "id", "title", "url", "container", "order", "createdAt",
        ]),
        DTOFieldSpec(structName: "CadenceContextRef", expectedFields: [
            "id", "name", "colorHex", "icon", "order", "isArchived", "areaCount", "projectCount",
            "activeTaskCount", "goalCount", "habitCount",
        ]),
        DTOFieldSpec(structName: "CadenceContainerRef", expectedFields: [
            "kind", "id", "name", "contextId", "contextName", "status", "colorHex", "icon",
        ]),
    ]

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

    func argumentParsingHelperNames() throws -> Set<String> {
        helperNames(inSwift: strippingComments(try sourceFile(Self.argumentParsingPath)))
    }

    /// Four-space-indented `func` only, so the `private static func` parsers beside them are
    /// excluded — those are implementation detail of the eight the router calls.
    func helperNames(inSwift source: String) -> Set<String> {
        matches(of: #"^    func ([a-zA-Z]+)\("#, in: source)
    }

    func toolNames(inSwift source: String) -> Set<String> {
        matches(of: #"Tool\(name: "([a-z_]+)""#, in: source)
    }

    /// Every stored `let` property of one exact-named `struct ...: Codable, Sendable { ... }`
    /// declaration. `source` must already be comment-stripped by the caller, matching every other
    /// extractor in this file. The search string includes `: Codable, Sendable {` so a struct name
    /// that is a prefix of another's (`CadenceContainerRef` / `CadenceContainerSummary`) cannot
    /// cross-match, and the scan stops at the first bare `}` line after the declaration, so a
    /// field on a later, unrelated struct is never counted. Returns an empty set — not a thrown
    /// error — for a struct name that no longer exists, exactly like `armsSplittingCases` returning
    /// nothing for a deleted arm: the caller's `#expect(fields == expected)` is what turns that
    /// into a readable failure instead of a bare crash.
    func structStoredPropertyNames(_ structName: String, in source: String) -> Set<String> {
        guard let declRange = source.range(of: "struct \(structName): Codable, Sendable {"),
              let closeRange = source.range(of: "\n}", range: declRange.upperBound..<source.endIndex)
        else {
            return []
        }
        let body = String(source[declRange.upperBound..<closeRange.lowerBound])
        return matches(of: #"^    let ([a-zA-Z]+):"#, in: body)
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

    /// Python has no block comments, so this is a line scan — but a naive one deletes the tail of
    /// any line with a `#` inside a string literal, and the markers this file looks for are in
    /// string literals.
    func strippingPythonComments(_ source: String) -> String {
        source.components(separatedBy: "\n").map { line -> String in
            var quote: Character?
            var escaped = false
            var result = ""
            for character in line {
                if let open = quote {
                    result.append(character)
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == open {
                        quote = nil
                    }
                    continue
                }
                if character == "\"" || character == "'" {
                    quote = character
                    result.append(character)
                    continue
                }
                if character == "#" { break }
                result.append(character)
            }
            return result
        }.joined(separator: "\n")
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
