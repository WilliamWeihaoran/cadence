import Foundation
import Testing

/// T-409. `aaa0064` routed `CadenceWriteService` — a file in the `CadenceMCPServer` target's
/// explicit source list — through `CadenceTaskMutationSupport`, which is in no target's Sources
/// phase at all. The app still built, because the app target reaches `Cadence/` by folder
/// membership (`PBXFileSystemSynchronizedRootGroup`) and so compiles every file under it. The
/// command-line target cannot: it names its sources one by one. `CadenceMCPServer` stayed broken
/// for four commits while `-scheme Cadence` stayed green.
///
/// The asymmetry is the whole point, so this guard encodes it rather than assuming one shape:
///
/// - `Cadence` (app) — synchronized folder. Every `.swift` under `Cadence/` is a member. Nothing
///   to check; that target cannot have this break.
/// - `CadenceMCPServer` — fully explicit. Members are exactly the paths in its Sources phase.
/// - `CadenceWidgets` — *both*. `CadenceWidgets/` is a synchronized folder, and the phase
///   additionally names individual files under `Cadence/`.
///
/// For each explicit-list target the check is: no member source may reference a type declared
/// only in a non-member file. That is `aaa0064` mechanised for every symbol instead of one.
///
/// Phases are located by a file only that target compiles, never by object id, so the guard
/// survives Xcode renumbering `project.pbxproj`.
struct CadenceTargetSourceMembershipTests {

    /// The break that actually shipped. `CadenceWriteService.swift` is in this list; the support
    /// type it started calling was not, and nothing in the app scheme could tell.
    @Test func mcpServerSourcesOnlyReferenceTypesThatTargetCompiles() throws {
        let target = try TargetSourceGraph(
            name: "CadenceMCPServer",
            // MCP-only file: the router exists for no other target.
            phaseAnchor: "CadenceMCPToolRouter.swift",
            synchronizedRoots: [],
            ownFolder: "CadenceMCPServer"
        )

        // Non-vacuity: the scan has to have found a real, resolved source list.
        #expect(target.memberFiles.count >= 40, "only \(target.memberFiles.count) member files parsed")
        #expect(target.unresolvedPaths.isEmpty, "listed but missing on disk: \(target.unresolvedPaths)")
        #expect(target.declarations.count >= 500, "only \(target.declarations.count) declarations parsed")
        #expect(!target.unreachableTypes.isEmpty, "nothing was classified as outside the target")

        #expect(target.violations.isEmpty, target.violationReport)
    }

    /// The widget target has the same explicit-list exposure for its `Cadence/` sources, and it is
    /// already the blocker named in T-404. Its own folder is synchronized, so files there are
    /// members without being listed — a guard that read only the phase would report every widget
    /// view as a violation.
    @Test func widgetSourcesOnlyReferenceTypesThatTargetCompiles() throws {
        let target = try TargetSourceGraph(
            name: "CadenceWidgets",
            // Widget-only file: no other target builds the intents.
            phaseAnchor: "Cadence/Services/CadenceWidgetIntents.swift",
            synchronizedRoots: ["CadenceWidgets"],
            ownFolder: "CadenceWidgets"
        )

        #expect(target.memberFiles.count >= 40, "only \(target.memberFiles.count) member files parsed")
        #expect(target.unresolvedPaths.isEmpty, "listed but missing on disk: \(target.unresolvedPaths)")
        #expect(!target.unreachableTypes.isEmpty, "nothing was classified as outside the target")

        // The synchronized half has to be in the member set, or this test is checking the wrong
        // thing quietly: the widget views are members by folder, not by listing.
        #expect(target.memberFiles.contains("CadenceWidgets/TodayTasksWidget.swift"))
        #expect(!target.listedPaths.contains("CadenceWidgets/TodayTasksWidget.swift"))

        #expect(target.violations.isEmpty, target.violationReport)
    }

    /// A guard that reports "no violations" because it never detects anything is worse than none.
    /// This drives the same detector with a synthetic source that references a type the real graph
    /// says the MCP target cannot compile, and requires it to fire. The name is taken from the
    /// live unreachable set rather than written as a literal, so the control keeps working when
    /// the file that broke `aaa0064` is eventually added to the target.
    @Test func theMembershipDetectorFiresOnAReferenceItShouldReject() throws {
        let target = try TargetSourceGraph(
            name: "CadenceMCPServer",
            phaseAnchor: "CadenceMCPToolRouter.swift",
            synchronizedRoots: [],
            ownFolder: "CadenceMCPServer"
        )

        let unreachable = try #require(target.unreachableTypes.keys.sorted().first)
        let synthetic = """
        func broken(context: ModelContext) {
            \(unreachable).doSomething(in: context)
        }
        """
        #expect(target.unreachableReferences(in: synthetic) == [unreachable])

        // ...and stays quiet on a source that only names things the target does compile, so the
        // detector is not simply flagging every capitalised word.
        let clean = "func fine(context: ModelContext) -> String { String(describing: context) }"
        #expect(target.unreachableReferences(in: clean).isEmpty)

        // Comments and string literals are not references. `aaa0064` would have been caught by a
        // cruder scan too, but a cruder scan would also fail on every doc comment that names a
        // shared type, and a guard nobody can keep green gets deleted.
        let commented = """
        /// See \(unreachable) for the app-side rule.
        let note = "\(unreachable) is not available here"
        """
        #expect(target.unreachableReferences(in: commented).isEmpty)

        // A name inside a `\(...)` interpolation is a reference: the compiler resolves it, so the
        // scan has to keep it even though the surrounding literal is dropped.
        let interpolated = ##"""
        let label = "\(\##(unreachable).description)"
        """##
        #expect(target.unreachableReferences(in: interpolated) == [unreachable])

        // A raw string has no escapes, so its contents stay text — and the `#` delimiters have to
        // be counted, or the scan loses its place and stops reading the rest of the file.
        let rawLiteral = ##"""
        let pattern = #"\##(unreachable)"# + suffix
        let after = 1
        """##
        #expect(target.unreachableReferences(in: rawLiteral).isEmpty)
    }
}

// MARK: - Target source graph

/// Reads one target's Sources phase out of `project.pbxproj`, resolves it against the synchronized
/// folders that target also gets for free, and works out which repository types that target
/// therefore cannot see.
private struct TargetSourceGraph {
    let name: String
    /// Paths written into the Sources phase, verbatim.
    let listedPaths: Set<String>
    /// Repository-relative paths of every `.swift` the target compiles, listed or synchronized.
    let memberFiles: Set<String>
    /// Listed paths that resolve to no file on disk.
    let unresolvedPaths: [String]
    /// Every top-level type declared anywhere the guard scanned, mapped to its declaring file.
    let declarations: [String: String]
    /// Declarations the target cannot compile, mapped to the file that declares them.
    let unreachableTypes: [String: String]

    /// `file -> (type, declaring file)` for every reference a member makes to something the target
    /// cannot compile.
    let violations: [(member: String, type: String, declaredIn: String)]

    init(name: String, phaseAnchor: String, synchronizedRoots: [String], ownFolder: String) throws {
        self.name = name

        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Cadence.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let listed = try TargetSourceGraph.sourcesPhasePaths(in: project, anchoredBy: phaseAnchor)
        listedPaths = listed

        // A listed path is written relative to the repository root when it reaches into `Cadence/`,
        // and relative to the target's own group when it is one of the target's own files.
        var members: Set<String> = []
        var unresolved: [String] = []
        for path in listed {
            if TargetSourceGraph.fileExists(path) {
                members.insert(path)
            } else if TargetSourceGraph.fileExists("\(ownFolder)/\(path)") {
                members.insert("\(ownFolder)/\(path)")
            } else {
                unresolved.append(path)
            }
        }
        for root in synchronizedRoots {
            members.formUnion(TargetSourceGraph.swiftFiles(under: root))
        }
        memberFiles = members
        unresolvedPaths = unresolved.sorted()

        // Scan the shared code plus every explicit-list target's own folder. Anything declared
        // there and not compiled by this target is out of reach for it.
        var scanRoots = ["Cadence"]
        scanRoots.append(ownFolder)
        scanRoots.append(contentsOf: synchronizedRoots)
        var declared: [String: String] = [:]
        var declaringFilesByType: [String: Set<String>] = [:]
        for root in Set(scanRoots) {
            for file in TargetSourceGraph.swiftFiles(under: root) {
                guard let source = try? String(
                    contentsOf: repositoryRoot.appendingPathComponent(file),
                    encoding: .utf8
                ) else { continue }
                for type in TargetSourceGraph.topLevelTypeNames(in: TargetSourceGraph.stripped(source)) {
                    declared[type] = file
                    declaringFilesByType[type, default: []].insert(file)
                }
            }
        }
        declarations = declared

        // A type is reachable if *any* file declaring it is a member, so this is a set of
        // declaring files rather than one file: a name can legitimately be declared in more than
        // one place, and the target only needs to compile one of them.
        unreachableTypes = declaringFilesByType
            .filter { $0.value.isDisjoint(with: members) }
            .compactMapValues { $0.sorted().first }

        let unreachable = unreachableTypes
        var found: [(member: String, type: String, declaredIn: String)] = []
        for file in members.sorted() {
            guard let source = try? String(
                contentsOf: repositoryRoot.appendingPathComponent(file),
                encoding: .utf8
            ) else { continue }
            for type in TargetSourceGraph.referencedTypeNames(in: source).sorted()
            where unreachable[type] != nil {
                found.append((member: file, type: type, declaredIn: unreachable[type]!))
            }
        }
        violations = found
    }

    /// Runs the detector over an arbitrary source string. Used by the positive-control test.
    func unreachableReferences(in source: String) -> [String] {
        TargetSourceGraph.referencedTypeNames(in: source)
            .filter { unreachableTypes[$0] != nil }
            .sorted()
    }

    var violationReport: Comment {
        guard !violations.isEmpty else { return "" }
        let lines = violations.map {
            "  \($0.member) references \($0.type), declared in \($0.declaredIn)"
        }
        return Comment(rawValue: """
        \(name) compiles an explicit source list; these references are to files it does not compile, \
        so `-scheme Cadence` will stay green while `-scheme \(name)` does not build:
        \(lines.joined(separator: "\n"))
        Either add the declaring file to the \(name) Sources phase (and every file it pulls in), or \
        keep the call on the app side.
        """)
    }

    // MARK: Project file

    /// Finds the `PBXSourcesBuildPhase` whose file list mentions `anchor`, and returns every path
    /// it names. Located by content, never by object id: Xcode rewrites ids, and a guard pinned to
    /// one would go quiet rather than red.
    private static func sourcesPhasePaths(in project: String, anchoredBy anchor: String) throws -> Set<String> {
        let blocks = project.components(separatedBy: "isa = PBXSourcesBuildPhase;").dropFirst()
        let suffix = " in Sources */"
        for block in blocks {
            guard let end = block.range(of: "runOnlyForDeploymentPostprocessing") else { continue }
            let body = String(block[block.startIndex..<end.lowerBound])

            var paths: Set<String> = []
            var cursor = body.startIndex
            while let hit = body.range(of: suffix, range: cursor..<body.endIndex) {
                if let open = body.range(of: "/* ", options: .backwards, range: cursor..<hit.lowerBound) {
                    paths.insert(String(body[open.upperBound..<hit.lowerBound]))
                }
                cursor = hit.upperBound
            }
            if paths.contains(anchor) { return paths }
        }
        throw MembershipScanError.noSourcesPhase(anchor: anchor)
    }

    // MARK: Swift parsing

    /// Top-level declarations only. A nested type is reached through its parent's name, which the
    /// scan already sees.
    static func topLevelTypeNames(in source: String) -> [String] {
        let keywords: Set<String> = ["struct", "class", "enum", "actor", "protocol", "typealias"]
        var names: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let first = line.first, !first.isWhitespace else { continue }
            let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            for (index, word) in words.enumerated() where keywords.contains(String(word)) {
                guard index + 1 < words.count else { break }
                let name = words[index + 1].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if let initial = name.first, initial.isUppercase { names.append(String(name)) }
                break
            }
        }
        return names
    }

    /// Capitalised identifiers, with comments and string literals removed first. Framework and
    /// standard-library names fall out for free: they are not declared in this repository, so they
    /// are not in the declaration map.
    static func referencedTypeNames(in source: String) -> Set<String> {
        var names: Set<String> = []
        var current = ""
        for character in stripped(source) {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
            } else {
                if let initial = current.first, initial.isUppercase { names.insert(current) }
                current = ""
            }
        }
        if let initial = current.first, initial.isUppercase { names.insert(current) }
        return names
    }

    /// Removes `//` and `/* */` comments and the literal text of string literals, and keeps the
    /// contents of `\(...)` interpolations, which *are* real references. Raw-string delimiters are
    /// counted, because `#"...\"..."#` has no escapes and a stripper that assumed otherwise would
    /// desynchronise and swallow the code after it — a guard that reads less than it claims to.
    static func stripped(_ source: String) -> String {
        let characters = Array(source)
        var output = ""
        var index = 0

        /// Number of `#` immediately at `index`, as used by raw-string delimiters.
        func hashRun(from start: Int) -> Int {
            var count = 0
            while start + count < characters.count, characters[start + count] == "#" { count += 1 }
            return count
        }

        /// True when `"` * `quotes` followed by `#` * `hashes` sits at `index`.
        func matchesDelimiter(at start: Int, quotes: Int, hashes: Int) -> Bool {
            guard start + quotes + hashes <= characters.count else { return false }
            for offset in 0..<quotes where characters[start + offset] != "\"" { return false }
            for offset in 0..<hashes where characters[start + quotes + offset] != "#" { return false }
            return true
        }

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if character == "/", next == "/" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            }
            if character == "/", next == "*" {
                var depth = 1
                index += 2
                while index < characters.count, depth > 0 {
                    if characters[index] == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                        depth += 1
                        index += 2
                    } else if characters[index] == "*", index + 1 < characters.count, characters[index + 1] == "/" {
                        depth -= 1
                        index += 2
                    } else {
                        if characters[index] == "\n" { output.append("\n") }
                        index += 1
                    }
                }
                output.append(" ")
                continue
            }

            let hashes = character == "#" ? hashRun(from: index) : 0
            let quoteIndex = index + hashes
            guard quoteIndex < characters.count, characters[quoteIndex] == "\"" else {
                output.append(character)
                index += 1
                continue
            }

            let quotes = matchesDelimiter(at: quoteIndex, quotes: 3, hashes: 0) ? 3 : 1
            index = quoteIndex + quotes
            output.append(" ")

            while index < characters.count {
                if matchesDelimiter(at: index, quotes: quotes, hashes: hashes) {
                    index += quotes + hashes
                    break
                }
                // `\` + the raw-string hashes introduces an escape or an interpolation.
                if characters[index] == "\\", matchesHashes(characters, at: index + 1, count: hashes) {
                    let after = index + 1 + hashes
                    if after < characters.count, characters[after] == "(" {
                        var depth = 0
                        var cursor = after
                        while cursor < characters.count {
                            if characters[cursor] == "(" { depth += 1 }
                            if characters[cursor] == ")" {
                                depth -= 1
                                if depth == 0 { cursor += 1; break }
                            }
                            output.append(characters[cursor])
                            cursor += 1
                        }
                        output.append(" ")
                        index = cursor
                        continue
                    }
                    index = after + 1
                    continue
                }
                if characters[index] == "\n" { output.append("\n") }
                index += 1
            }
        }
        return output
    }

    // MARK: Filesystem

    private static func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(relativePath).path)
    }

    static func swiftFiles(under relativeRoot: String) -> Set<String> {
        let root = repositoryRoot.appendingPathComponent(relativeRoot)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var files: Set<String> = []
        for case let entry as String in walker where entry.hasSuffix(".swift") {
            files.insert("\(relativeRoot)/\(entry)")
        }
        return files
    }
}

/// `count` consecutive `#` starting at `start`. Zero always matches, which is what makes an
/// ordinary (non-raw) string literal fall out of the same code path.
private func matchesHashes(_ characters: [Character], at start: Int, count: Int) -> Bool {
    guard start + count <= characters.count else { return false }
    for offset in 0..<count where characters[start + offset] != "#" { return false }
    return true
}

private enum MembershipScanError: Error, CustomStringConvertible {
    case noSourcesPhase(anchor: String)

    var description: String {
        switch self {
        case .noSourcesPhase(let anchor):
            return "no PBXSourcesBuildPhase names \(anchor); the target or the file was renamed"
        }
    }
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
