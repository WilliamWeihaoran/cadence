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
/// For each explicit-list target the check is: no member source may reference a type declared only
/// in a non-member file, and no member source may call a **top-level function** declared only in a
/// non-member file. That is `aaa0064` mechanised for every symbol instead of one.
///
/// Phases are located by a file only that target compiles, never by object id, so the guard
/// survives Xcode renumbering `project.pbxproj`.
///
/// # Why the free-function half exists (T-435)
///
/// The original guard read *capitalised identifiers* on the reference side and
/// `struct`/`class`/`enum`/`actor`/`protocol`/`typealias` on the declaration side. That is the
/// shape `aaa0064` had, and it is blind to the other way a target boundary gets crossed: a
/// **top-level `func`**. `Cadence/macOS/Views/TaskSortHelpers.swift` declares
/// `taskPriorityRank(_:)` and `taskSortPrecedes(_:_:field:direction:)` at file scope;
/// `CalendarPageMonthGridSupport.swift` declares `monthStart(for:calendar:)` and three more. None
/// of those files is in the MCP or widget source list, and a member calling `monthStart(...)`
/// produced no capitalised token at all, so the sweep read the call and saw nothing.
///
/// `mcpSourcesOnlyCallTopLevelFunctionsThatTargetCompiles` closes it, and it goes through
/// `CadenceScanInstrument` rather than sweeping directly: the positive witness is a synthetic call
/// to a real free function this target genuinely cannot compile, so a detector that has stopped
/// seeing free functions cannot be constructed, let alone swept with. That matters more here than
/// usual — the repo has **zero** violations of this rule today, which is exactly the state in
/// which a blind detector and a clean repo are indistinguishable.
///
/// # This guard and T-406's are not duplicates (T-436)
///
/// `WidgetSupportTests.theTitleTrimRuleIsDeclaredOnceInAFileTheWidgetTargetCompiles` also reads the
/// widget target's Sources phase out of `project.pbxproj`, and at a glance it looks like a
/// one-symbol special case of the sweep below. **It is not, and deleting either loses real
/// coverage.** They ask different questions of the same file:
///
/// - This guard asks **reachability**: for every symbol a member file names, is it declared in some
///   file the target compiles? That is a whole-graph question, and it knows nothing about how many
///   times a rule is spelled, nor about which file a *reachable* declaration lives in. A second
///   declaration of a type in a non-member file leaves it reachable, so this guard stays silent.
/// - T-406's asks **singularity and placement**: is `CadenceTitleNormalization` declared in exactly
///   one file, is that file `Cadence/Models/ModelEnums.swift`, is the trim expression spelled
///   exactly once inside it, and is that file in the widget phase? Counting is outside this guard's
///   vocabulary entirely.
///
/// A change only **T-406's** guard fails: give `TaskTitleShortcutParsing.normalized` its own
/// `title.trimmingCharacters(in: .whitespacesAndNewlines)` again instead of delegating to
/// `CadenceTitleNormalization` — the exact defect T-406 fixed. Nothing becomes unreachable (the
/// copy is *more* reachable than the call it replaced), so every test here stays green; and the
/// behavioural pin `taskTitleShortcutTrimAgreesWithTheSharedTitleTrim` stays green too, because two
/// correct copies of a trim agree on every sample. Only the spelling count sees it.
///
/// A change only **this** guard fails: route a `CadenceMCPServer` member through any shared symbol
/// outside its explicit source list — the `aaa0064` shape, or the free-function shape T-435 added.
/// T-406's guard names one type and one target, so it cannot see any of it.
///
/// One asymmetry worth recording rather than rediscovering: **the widget half below is a coverage
/// demonstration, not a kill.** `-scheme Cadence` builds `CadenceWidgets`, so a widget member that
/// names a non-member symbol is a compile failure before any test runs, and no compiling mutation
/// can turn `widgetSourcesOnlyReferenceTypesThatTargetCompiles` red. It earns its place by proving
/// the detector handles the mixed synchronized/explicit shape — which is what makes the MCP half
/// trustworthy, since `CadenceMCPServer` is built by no scheme here and has nothing else watching
/// it.
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

    /// T-435. The reference scan above reads *capitalised* identifiers, so a call to a top-level
    /// `func` crosses a target boundary without producing a single token it looks at.
    /// `Cadence/macOS/Views/CalendarPageMonthGridSupport.swift` declares `monthStart(for:calendar:)`
    /// at file scope and `TaskSortHelpers.swift` declares `taskPriorityRank(_:)`; neither file is in
    /// the MCP source list, and `monthStart(for: date, calendar: .current)` in a member read as
    /// nothing at all. This is that hole closed, for the target where it can actually ship broken.
    ///
    /// It runs through `CadenceScanInstrument` rather than sweeping directly, because the repo has
    /// **no** violations of this rule today: "no member calls an unreachable free function" is what
    /// a working repo and a detector that never fires both look like, and the constructor is the
    /// only thing that tells them apart. The witness is drawn from the live unreachable set rather
    /// than written as a literal name, so adding `TaskSortHelpers.swift` to this target retunes the
    /// control instead of breaking it.
    @Test func mcpSourcesOnlyCallTopLevelFunctionsThatTargetCompiles() throws {
        let target = try TargetSourceGraph(
            name: "CadenceMCPServer",
            phaseAnchor: "CadenceMCPToolRouter.swift",
            synchronizedRoots: [],
            ownFolder: "CadenceMCPServer"
        )

        // Non-vacuity: free functions were parsed at all, and some are out of this target's reach.
        // A declaration side that returned nothing would make every call below trivially clean.
        #expect(
            target.functionDeclarations.count >= 10,
            "only \(target.functionDeclarations.count) top-level funcs parsed"
        )
        #expect(
            target.unreachableFunctions.count >= 10,
            "only \(target.unreachableFunctions.count) top-level funcs classified as out of reach"
        )

        let instrument = try target.freeFunctionCallInstrument()
        let hits = try instrument.sweep(
            target.memberFiles.sorted(),
            atLeast: 40,
            including: "Cadence/Services/MCPReadOnly/CadenceWriteService.swift",
            read: { try TargetSourceGraph.sourceText($0) }
        )
        #expect(hits.isEmpty, target.freeFunctionViolationReport(for: hits))
    }

    /// The widget target has the same explicit-list exposure for its `Cadence/` sources. Like its
    /// type-side twin above this half is a coverage demonstration rather than a kill — `-scheme
    /// Cadence` builds `CadenceWidgets`, so a real violation is a compile failure before any test
    /// runs. What it proves is that the free-function detector handles the mixed
    /// synchronized/explicit membership shape, which is the part the MCP half cannot show.
    @Test func widgetSourcesOnlyCallTopLevelFunctionsThatTargetCompiles() throws {
        let target = try TargetSourceGraph(
            name: "CadenceWidgets",
            phaseAnchor: "Cadence/Services/CadenceWidgetIntents.swift",
            synchronizedRoots: ["CadenceWidgets"],
            ownFolder: "CadenceWidgets"
        )

        #expect(target.unreachableFunctions.count >= 10)

        let instrument = try target.freeFunctionCallInstrument()
        let hits = try instrument.sweep(
            target.memberFiles.sorted(),
            atLeast: 40,
            including: "CadenceWidgets/TodayTasksWidget.swift",
            read: { try TargetSourceGraph.sourceText($0) }
        )
        #expect(hits.isEmpty, target.freeFunctionViolationReport(for: hits))
    }

    /// The free-function detector's near misses, spelled out.
    ///
    /// `CadenceScanInstrument` already refuses to build a detector that fails its positive witness
    /// or fires on its one negative. This pins the rest of the family, because a widening written
    /// as "does this file contain the name" passes the constructor and then reports every doc
    /// comment that mentions a helper. Each fixture below is one plausible spelling of the same
    /// name that is **not** a call to that function.
    @Test func theFreeFunctionDetectorSeparatesACallFromItsNearMisses() throws {
        let target = try TargetSourceGraph(
            name: "CadenceMCPServer",
            phaseAnchor: "CadenceMCPToolRouter.swift",
            synchronizedRoots: [],
            ownFolder: "CadenceMCPServer"
        )
        let instrument = try target.freeFunctionCallInstrument()
        let witness = try #require(target.unreachableFunctions.keys.sorted().first)

        // A bare call is the violation.
        #expect(instrument.fires(on: "let value = \(witness)(input)"))

        // A method reached through a value only shares the spelling.
        #expect(!instrument.fires(on: "let value = payload.\(witness)(input)"))

        // Prose and literals name symbols constantly; neither is a reference the compiler resolves.
        #expect(!instrument.fires(on: "// call \(witness)(input) on the app side instead"))
        #expect(!instrument.fires(on: #"let note = "\#(witness)(input) is macOS-only""#))

        // A same-named function declared in this file is the one being called, not the far one.
        #expect(!instrument.fires(on: """
        func \(witness)(_ input: Int) -> Int { input }
        let value = \(witness)(1)
        """))

        // ...and so is a closure bound to that name.
        #expect(!instrument.fires(on: """
        let \(witness): (Int) -> Int = { $0 }
        let value = \(witness)(1)
        """))

        // The name appearing without a call is a mention, not a call — `map(monthStart)` is a real
        // Swift spelling this deliberately does not chase, and the report says so rather than
        // pretending the coverage is total.
        #expect(!instrument.fires(on: "let transform = \(witness)"))
    }
}

// MARK: - Target source graph

/// Reads one target's Sources phase out of `project.pbxproj`, resolves it against the synchronized
/// folders that target also gets for free, and works out which repository types that target
/// therefore cannot see.
/// **T-374.** Internal rather than private: `CadenceSharedConstantReuseSweepTests` needs the same
/// answer -- which files a target actually compiles -- and re-deriving it there would be this
/// repo's most common defect shape committed inside the test that enforces it.
struct TargetSourceGraph {
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
    /// Every non-private top-level `func` declared anywhere the guard scanned (T-435), mapped to
    /// its declaring file. Free functions are the half the capitalised-identifier scan cannot see.
    let functionDeclarations: [String: String]
    /// Top-level functions the target cannot compile, mapped to the file that declares them.
    let unreachableFunctions: [String: String]

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
        var declaredFunctions: [String: String] = [:]
        var declaringFilesByFunction: [String: Set<String>] = [:]
        for root in Set(scanRoots) {
            for file in TargetSourceGraph.swiftFiles(under: root) {
                guard let source = try? String(
                    contentsOf: repositoryRoot.appendingPathComponent(file),
                    encoding: .utf8
                ) else { continue }
                let code = TargetSourceGraph.stripped(source)
                for type in TargetSourceGraph.topLevelTypeNames(in: code) {
                    declared[type] = file
                    declaringFilesByType[type, default: []].insert(file)
                }
                for function in TargetSourceGraph.topLevelFunctionNames(in: code) {
                    declaredFunctions[function] = file
                    declaringFilesByFunction[function, default: []].insert(file)
                }
            }
        }
        declarations = declared
        functionDeclarations = declaredFunctions

        // A type is reachable if *any* file declaring it is a member, so this is a set of
        // declaring files rather than one file: a name can legitimately be declared in more than
        // one place, and the target only needs to compile one of them.
        unreachableTypes = declaringFilesByType
            .filter { $0.value.isDisjoint(with: members) }
            .compactMapValues { $0.sorted().first }
        unreachableFunctions = declaringFilesByFunction
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

    /// The top-level functions `source` calls that this target cannot compile (T-435).
    ///
    /// A name is discounted when the same source binds it — a method or nested `func` of that name,
    /// or a closure held in a `let`/`var`. Those are what the call resolves to, and the far
    /// declaration is irrelevant. Discounting per *file* rather than per target is deliberate: it
    /// is the scope Swift resolves an unqualified call in, and it keeps the check strict.
    func unreachableFunctionCalls(in source: String) -> [String] {
        let bound = TargetSourceGraph.locallyBoundNames(in: source)
        return TargetSourceGraph.calledFunctionNames(in: source)
            .filter { unreachableFunctions[$0] != nil && !bound.contains($0) }
            .sorted()
    }

    /// A `CadenceScanInstrument` for "this source calls a top-level function the target cannot
    /// compile", carrying the two witnesses that prove it can still tell the difference.
    ///
    /// The positive fixture is a call to a real free function this target's source list genuinely
    /// does not reach — the shape T-435 is about — inside a literal call site. The negative is the
    /// nearest miss: the same spelling reached through a value, which is a method call on something
    /// else entirely. A widening written as a bare name search passes the positive and fails here,
    /// which is the whole reason the pair is checked in the constructor.
    ///
    /// The witness name is read from the live graph instead of hardcoded. A literal would be the
    /// stronger fixture per `CadenceScanInstrument`'s own guidance, but the thing it guards against
    /// — a fixture retuned by the same edit that breaks the rule — does not apply to a name this
    /// file never writes down: the only edit that changes it is adding the declaring file to the
    /// target, which *legitimately* makes that function reachable and should pick the next one.
    func freeFunctionCallInstrument() throws -> CadenceScanInstrument {
        guard let witness = unreachableFunctions.keys.sorted().first else {
            throw MembershipScanError.noUnreachableFunctions(target: name)
        }
        let positive = """
        func routeCreateTask(dateKey: String) -> Int {
            \(witness)(dateKey)
        }
        """
        let negative = """
        func routeCreateTask(dateKey: String) -> Int {
            dateKey.\(witness)()
        }
        """
        return try CadenceScanInstrument(
            "\(name) calls a top-level func outside its source list",
            fires: positive,
            andNotOn: negative,
            by: { !self.unreachableFunctionCalls(in: $0).isEmpty }
        )
    }

    func freeFunctionViolationReport(for hits: [String]) -> Comment {
        guard !hits.isEmpty else { return "" }
        let lines = hits.map { path -> String in
            let calls = (try? TargetSourceGraph.sourceText(path))
                .map { self.unreachableFunctionCalls(in: $0) } ?? []
            let detail = calls
                .map { "\($0), declared in \(unreachableFunctions[$0] ?? "an unlisted file")" }
                .joined(separator: "; ")
            return "  \(path) calls \(detail)"
        }
        return Comment(rawValue: """
        \(name) compiles an explicit source list; these calls reach top-level functions it does not \
        compile, so `-scheme Cadence` will stay green while `-scheme \(name)` does not build:
        \(lines.joined(separator: "\n"))
        Either add the declaring file to the \(name) Sources phase (and every file it pulls in), or \
        keep the call on the app side.
        """)
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

    /// Non-private top-level `func` declarations (T-435). Same column-zero rule as the type scan:
    /// a method is reached through its type's name, which the type scan already sees, so only file
    /// scope matters here.
    ///
    /// `private` and `fileprivate` are skipped because they are unreachable *from any other file*,
    /// in or out of the target. A member file that spells one of those names is naming something
    /// else by definition, so counting them could only produce false accusations.
    static func topLevelFunctionNames(in source: String) -> [String] {
        var names: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let first = line.first, !first.isWhitespace else { continue }
            let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let index = words.firstIndex(where: { $0 == "func" }), index + 1 < words.count else {
                continue
            }
            let modifiers = words[..<index].map(String.init)
            if modifiers.contains("private") || modifiers.contains("fileprivate") { continue }
            let name = words[index + 1].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty { names.append(String(name)) }
        }
        return names
    }

    /// Identifiers in call position: `name(`, with no `.` in front and no `func` keyword behind.
    ///
    /// Call position rather than every identifier, because a free function's name is lowercase and
    /// the lowercase namespace is full of locals, labels and parameters — a bare name scan would
    /// accuse a file every time a variable happened to share a name with a helper in `macOS/`.
    /// The cost of the narrower rule is that a function passed as a value, `map(monthStart)`, is
    /// not seen; that is a real gap, and `theFreeFunctionDetectorSeparatesACallFromItsNearMisses`
    /// pins it as a known one rather than leaving it to be met as a surprise.
    static func calledFunctionNames(in source: String) -> Set<String> {
        let characters = Array(stripped(source))
        var names: Set<String> = []
        var previousWord = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character.isLetter || character.isNumber || character == "_" else {
                if !character.isWhitespace { previousWord = "" }
                index += 1
                continue
            }
            let start = index
            while index < characters.count,
                  characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
                index += 1
            }
            let word = String(characters[start..<index])
            let qualified = start > 0 && characters[start - 1] == "."
            let called = index < characters.count && characters[index] == "("
            if called, !qualified, previousWord != "func" { names.insert(word) }
            previousWord = word
        }
        return names
    }

    /// Names this source binds itself: `func`, `let` and `var` declarations at any depth. An
    /// unqualified call resolves to one of these before it resolves to anything in another file,
    /// so a name in this set is not evidence of a target-boundary crossing.
    static func locallyBoundNames(in source: String) -> Set<String> {
        let binders: Set<String> = ["func", "let", "var"]
        var names: Set<String> = []
        var previous = ""
        var current = ""
        for character in stripped(source) {
            if character.isLetter || character.isNumber || character == "_" {
                current.append(character)
                continue
            }
            if !current.isEmpty {
                if binders.contains(previous) { names.insert(current) }
                previous = current
                current = ""
            } else if !character.isWhitespace {
                previous = ""
            }
        }
        if !current.isEmpty, binders.contains(previous) { names.insert(current) }
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

    static func sourceText(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

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
    case noUnreachableFunctions(target: String)

    var description: String {
        switch self {
        case .noSourcesPhase(let anchor):
            return "no PBXSourcesBuildPhase names \(anchor); the target or the file was renamed"
        case .noUnreachableFunctions(let target):
            return "every top-level func in the repository is reachable from \(target); "
                + "either the free-function parse went blind or the source list grew"
        }
    }
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
