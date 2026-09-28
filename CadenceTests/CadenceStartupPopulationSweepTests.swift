import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1366 step two, the startup half: which population a launch's maintenance actually pays for,
/// and the one thing the answer named.**
///
/// [[T-1366]]'s first measurement (agent `widgetcost`) reported one fixture's launch as a total.
/// That is a number, not an answer. The ticket's own hypothesis, inherited from [[T-1329]], was
/// that *"tag bytes and duplicate density dominate the recorded pass time"*, and this sweep was
/// written to test it. **It is wrong in both halves, and that is the first finding.**
///
/// So this varies one population at a time and holds the rest still, timing the five maintenance
/// passes through the shipping `CadenceStartupCostRecorder` — the production body, not a replay of
/// it. Each cohort is run `repetitions` times against a disk-backed fixture in a temporary
/// directory (never the app group, never the owner's store): the **first** run is reported as
/// `cold`, because it is the launch that repairs whatever the store needs repairing, and the rest
/// as `warm`, which is the steady state every subsequent launch actually pays.
///
/// **Measured: Apple M3 Pro / Mac15,6, 11 cores, 18 GB, macOS 27.0, Xcode 27.0, warm medians of 6,
/// spread in the log.** Milliseconds, `tagSync` / `integrityRepair` / whole maintenance:
///
///     cohort                      tagSync           integrityRepair   whole maintenance
///                                 before -> after   (after; unmoved)  before -> after
///     baseline 240 notes/tasks     34.86 ->  16.91       13.00          50.17 ->  32.48
///     notes=1,000                 138.39 ->  62.76       29.51         172.69 ->  94.70
///     notes=5,000                 696.41 -> 313.45      120.49         825.73 -> 439.22
///     notes=5,000, no tags/body   467.51 -> 131.38      119.36         581.40 -> 253.14
///     bodyBytes=4,000/note         46.54 ->  27.24       13.91          63.50 ->  43.55
///     bodyBytes=40,000/note       136.47 -> 116.80       16.80         158.50 -> 136.06
///     tagsPerNote=12               55.51 ->  38.07       14.76          73.28 ->  55.59
///     tagsPerNote=48              125.24 -> 104.28       15.38         145.11 -> 122.01
///     bodyLines=50 (4,000 bytes)   85.39 ->  45.20       13.98         102.30 ->  61.84
///     bodyLines=400 (4,000 bytes) 397.26 -> 193.30       15.19         414.19 -> 211.02
///     duplicateNotes=5,000 warm    35.88 ->  16.68       12.70          52.48 ->  31.68
///     duplicateNotes=5,000 COLD  1085.55 -> 685.10      363.76        5781.78 -> 5108.59
///     tasks=5,000                  34.92 ->  16.75      144.24         184.07 -> 163.46
///     tasks=20,000                 35.13 ->  16.75      558.59         602.44 -> 578.07
///     control notes=0               0.05 ->   0.04        8.07          10.57 ->   9.37
///
/// Every row but the last is one before/after pair taken on one tree back to back; the control row
/// is a second such pair, taken over the cohort sizes this file actually ships with, which is why
/// its neighbours' absolute numbers differ from it by a few percent of machine mood.
///
/// The last row is the **control**: a store with no notes, where `syncAllNoteTagsFromMarkdown`
/// returns `.nothingToDo` before it reads a pattern. It is the one cohort this change cannot have
/// moved, and it did not move — 0.05 -> 0.04ms is the floor and the noise, against 36.00 -> 16.80ms
/// for the baseline measured in the same two runs. The `tasks=` rows are the control in the other
/// direction: a population that costs one pass 43x and the other nothing at all.
///
/// **What the sweep says, in order.**
///
/// 1. **Duplicate density is not a launch cost; it is a once-ever cost.** 5,000 duplicate notes
///    make the *cold* launch 5,782ms (of which 4,291ms is the one save that commits the merges) —
///    and the very next launch over the same store is **52.48ms, which is the baseline**. The pass
///    fixed them, they are gone, and no later launch pays for them again. A store's duplicate
///    density cannot be a steady-state term, and the `warm` column is the control that shows it:
///    the same fixture, the same code, one launch later, back at the baseline.
/// 2. **Tag bytes are not it either.** Multiplying a note's body by 200 (200 -> 40,000 bytes) moves
///    `tagSync` 34.86 -> 136.47ms, and most of *that* is per **line**, not per byte: at a fixed
///    4,000 bytes per note, going from 3 lines to 400 moves it 46.54 -> 397.26ms. Tag *density*
///    is the same story — 3 -> 48 tags per note is 34.86 -> 125.24ms, on notes 240 bytes long.
/// 3. **The expensive population is the number of notes, and within a note the number of lines** —
///    and it was mostly not the parsing. With 5,000 notes holding **no tags and no body at all**,
///    `tagSync` still cost 467.51ms, i.e. **93.5µs per note that cannot be about tag content**.
///    That is a constant, and the constant was an `NSRegularExpression` being compiled: `inlineTags`
///    built the inline-tag pattern once per note and `isMarkdownHeading` built its own once per
///    line, both from string literals that never vary. Compiling that pattern measures ~100µs here.
/// 4. **The launch's other scaling term is not on this path at all.** `integrityRepair` is linear
///    in the `AppTask` table and pays it on *every* launch — 13.00 / 144.24 / 558.59ms at 240 /
///    5,000 / 20,000 tasks — while `tagSync` over the same stores never moves (34.92 / 35.13ms
///    before this ticket's change, 16.75ms after both).
///    That is this sweep's **negative control in the other direction**: a population that makes one
///    pass 43x more expensive and leaves the other exactly where it was, which is what
///    makes "the notes are what the tag sweep costs" mean something. It is also a real finding, and
///    it was *not* optimised here: filed as [[T-1443]], which **closed by refuting this
///    paragraph's own reason for leaving it**. "All twelve `RepairStore` fetches are read by the
///    pass" is true of the file and false of a **warm** launch, which is the launch the half-second
///    is paid on: eight of the twelve tables are reached only from `mergeContext`, i.e. only when
///    two active contexts share a name, and the ninth is read through a filter that discards every
///    task that is not a spawned recurrence occurrence. The rows above are now 6.07 / 6.41 / 7.45ms
///    — the population is gone rather than the answer.
///
/// **The optimisation, and nothing else**: the two constant patterns are now stored properties, the
/// spelling `nonProseRegex` in the same file has always had. After, per-note cost falls 93.5µs ->
/// 26.3µs and per-line cost 3.68µs -> 1.74µs; the owner-scale baseline launch's maintenance goes
/// 50.17 -> 32.48ms and a 5,000-note store's 825.73 -> 439.22ms.
///
/// **The bound a test holds is a count, not a duration** ([[T-1279]]/[[T-1296]]):
/// `theMetadataParserCompilesNoRegularExpressionPerNoteOrPerLine` counts the construction sites the
/// launch's parse reaches — **2 before, 0 after**, with the stored-pattern count going 1 -> 3 as
/// the non-vacuity leg. `theSharedPatternsFindTheTagsThePerCallOnesFound` is the output-equivalence
/// oracle, and its expectations were *recorded from the pre-change implementation* rather than
/// reasoned about.
///
/// **The cohorts are two literals and run small by default.** Widening `noteCounts` to
/// `[1_000, 5_000]`, `bodyLineCounts` to `[50, 400]` and so on reproduces the table above; that is
/// the whole interface, and it is deliberately not an environment variable for the reason
/// `CadenceWidgetPopulationSweepTests` records. What runs unconditionally is the shape check and
/// the bound, and neither needs a big store to hold.
///
/// **What this does NOT measure, said plainly.** Cold launch on the owner's real store (never
/// pointed at, by rule); the backup/restore preflight and first usable frame, which are still out
/// of a `CadenceTests` seat; and `MarkdownOutlineParser.items`, which compiles the same heading
/// pattern once per line in the same file but is not on the launch path and was not swept — filed
/// as [[T-1444]] rather than changed on a hunch.
@Suite(.preservesTheStoredLaunchReports, .serialized)
@MainActor
struct CadenceStartupPopulationSweepTests {
    nonisolated static let repetitions = 7

    nonisolated static let baselineNotes = 240
    nonisolated static let baselineTasks = 240
    nonisolated static let baselineBodyBytes = 200
    nonisolated static let baselineTagsPerNote = 3

    nonisolated static let noteCounts = [1_000]
    nonisolated static let bodyByteSizes = [4_000]
    nonisolated static let tagDensities = [12]
    nonisolated static let duplicateCounts = [1_000]
    nonisolated static let taskBallast = [5_000]
    nonisolated static let bodyLineCounts = [50]

    /// **The sweep, and the shape every cohort has to have for its numbers to mean anything.**
    ///
    /// No duration is asserted here — the table lives in this file's doc comment and in the log.
    /// What is asserted per cohort is that all five passes were timed, that none of them refused
    /// over a fixture nothing should refuse on, that nothing claims to have cost less than nothing,
    /// that the parts never sum past the whole, and that the fixture really holds the population
    /// the cohort is named after. A sweep whose stores were empty would print the same flat table.
    @Test func theStartupSweep() throws {
        try withTemporaryDefaults("CadenceTests.startupSweep") { defaults in
            CadenceStartupCostLedger.setEnabled(true, defaults: defaults)
            var lines: [String] = []

            func run(_ label: String, _ shape: SweepStore.Shape) throws {
                let store = try SweepStore(shape)
                defer { store.tearDown() }
                let reading = try measure(store: store, defaults: defaults)

                for stage in Self.maintenanceStages {
                    let record = try #require(reading.lastReport?.stage(stage), "\(label): \(stage.rawValue) was not timed")
                    #expect(record.outcome != .indeterminate, "\(label): \(stage.rawValue) could not say what it did")
                    #expect(record.outcome != .refused, "\(label): \(stage.rawValue) refused on a clean fixture")
                }
                for stage in try #require(reading.lastReport).stages {
                    #expect(stage.duration.isFinite && stage.duration >= 0, "\(label): \(stage.stage.rawValue)")
                }
                let report = try #require(reading.lastReport)
                let accounted = report.stages.reduce(0) { $0 + $1.duration }
                #expect(accounted <= report.totalDuration + 0.000_001, "\(label): the parts outrun the whole")

                // Non-vacuity: this cohort's store really holds the rows it is named after.
                let counts = try store.rowCounts()
                #expect(counts.tasks == shape.tasks, "\(label): the fixture's tasks read as \(counts.tasks)")
                #expect(
                    counts.notes == shape.notes + (shape.duplicateNotes > 0 ? 1 : 0),
                    "\(label): the fixture's notes read as \(counts.notes)"
                )

                lines.append(label.padding(toLength: 26, withPad: " ", startingAt: 0) + " " + reading.described)
            }

            try run("baseline", .init())
            for value in Self.noteCounts { try run("notes=\(value)", .init(notes: value)) }
            for value in Self.bodyByteSizes { try run("bodyBytes=\(value)", .init(bodyBytes: value)) }
            for value in Self.tagDensities { try run("tagsPerNote=\(value)", .init(tagsPerNote: value)) }
            for value in Self.duplicateCounts { try run("duplicateNotes=\(value)", .init(duplicateNotes: value)) }
            for value in Self.taskBallast { try run("tasks=\(value)", .init(tasks: value)) }
            for value in Self.bodyLineCounts { try run("bodyLines=\(value)", .init(bodyBytes: 4_000, bodyLines: value)) }
            try run("notes=1000 bare", .init(notes: 1_000, bodyBytes: 0, tagsPerNote: 0, bodyLines: 1))
            // **The control.** `syncAllNoteTagsFromMarkdown` returns `.nothingToDo` before it reads
            // a single pattern when the note table is empty, so this cohort is the one the whole
            // optimisation cannot have touched. Its numbers must be the same before and after, and
            // its `tagSync` must be the floor every other cohort is measured against.
            try run("control notes=0", .init(notes: 0))

            print("""
                T-1366 startup population sweep (cold = first launch, warm = median of \(Self.repetitions - 1))
                  cores=\(ProcessInfo.processInfo.processorCount) \
                ram=\(ProcessInfo.processInfo.physicalMemory / 1_048_576)MB
                \(lines.joined(separator: "\n"))
                """)
        }
    }

    nonisolated static let maintenanceStages: [CadenceStartupStage] = [
        .pursuitMigration, .noteMigration, .tagSync, .integrityRepair, .focusReconciliation,
    ]

    // MARK: - The bound

    /// **The count the optimisation is accountable to: how many regular expressions a note parse
    /// compiles.** It is zero, and it was `1 + one per line` before.
    ///
    /// A count and not a duration, for the [[T-1279]]/[[T-1296]] reason — compiling an
    /// `NSRegularExpression` is ~100µs on the machine that measured this and some other number on
    /// CI's, but *how many times the launch does it* is the same integer everywhere.
    ///
    /// The reading is structural because there is nothing else to read: unlike the widget half's
    /// `rowsFetched`, no instrument on this path can see an `NSRegularExpression` being built, and
    /// `Foundation` exposes no compile counter. So what is counted is the construction sites the
    /// launch's parse reaches, which is the thing the change moved.
    @Test func theMetadataParserCompilesNoRegularExpressionPerNoteOrPerLine() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/MarkdownMetadataSupport.swift")
        )
        let parser = try #require(
            CadenceSourceScan.declarationBody("nonisolated enum MarkdownMetadataParser", in: source),
            "MarkdownMetadataParser is gone or its braces do not balance, so this reads nothing"
        )
        #expect(parser.count > 2_000, "the stripped parser body is too small to be the real one")

        let (stored, inBody) = Self.regexConstructionCounts(in: parser)
        #expect(
            inBody == 0,
            "the parser compiles \(inBody) pattern(s) inside a function body, so a launch rebuilds them per note or per line"
        )
        // Non-vacuity, and the count itself: the three constant patterns are all still there as
        // stored properties, so `inBody == 0` is not a parser that lost its regexes.
        #expect(stored == 3, "the parser holds \(stored) stored patterns, not the expected 3")

        // The two bodies the measurement named, by name, so a hoist that put the compile back into
        // only one of them still fails.
        for function in ["inlineTags", "isMarkdownHeading"] {
            let body = try #require(
                CadenceSourceScan.functionBody(named: function, in: parser),
                "\(function) is gone"
            )
            #expect(!body.contains("NSRegularExpression("), "\(function) compiles its pattern per call again")
        }
        #expect(try #require(CadenceSourceScan.functionBody(named: "inlineTags", in: parser)).contains("inlineTagRegex"))
        #expect(
            try #require(CadenceSourceScan.functionBody(named: "isMarkdownHeading", in: parser))
                .contains("headingPrefixRegex")
        )

        // And the counter itself can see an in-body construction — over a snippet rather than over
        // a neighbouring type, so this leg cannot be turned vacuous by someone fixing that type.
        let regressed = """
            nonisolated enum Sample {
                nonisolated private static let kept = try? NSRegularExpression(pattern: #"a"#)
                nonisolated static func scan(_ line: String) -> Bool {
                    guard let regex = try? NSRegularExpression(pattern: #"b"#) else { return false }
                    return regex.firstMatch(in: line, range: NSRange(location: 0, length: 1)) != nil
                }
            }
            """
        let control = Self.regexConstructionCounts(in: regressed)
        #expect(control.stored == 1)
        #expect(control.inBody == 1, "the counter cannot see an in-body compile, so the zero above means nothing")
    }

    /// Splits `NSRegularExpression(` constructions into the ones bound to a stored property — paid
    /// once per process — and the ones inside a function body, paid once per call.
    nonisolated static func regexConstructionCounts(in source: String) -> (stored: Int, inBody: Int) {
        var stored = 0
        var inBody = 0
        for line in source.components(separatedBy: "\n") {
            let occurrences = line.components(separatedBy: "NSRegularExpression(").count - 1
            guard occurrences > 0 else { continue }
            if line.contains("static let") {
                stored += occurrences
            } else {
                inBody += occurrences
            }
        }
        return (stored, inBody)
    }

    /// **The equivalence oracle: the shared patterns find exactly what the per-call ones found.**
    ///
    /// The expectations below are not guesses about what the pattern *should* match — they are the
    /// output of the pre-[[T-1366]] implementation, recorded by running this corpus against it
    /// before the patterns were hoisted. A character lost while moving a `#"..."#` literal from a
    /// function body to a stored property therefore fails here, rather than silently changing
    /// which `#` in a note becomes a `Tag` row at the next launch — which is a write, not a
    /// rendering, and would arrive as tags the user never created.
    ///
    /// The corpus covers every branch the two hoisted patterns sit in: headings (the one the
    /// per-line compile served), code fences, frontmatter, the non-prose mask, and the unicode
    /// lookbehind that keeps `café#notatag` from being a tag.
    @Test func theSharedPatternsFindTheTagsThePerCallOnesFound() {
        for (content, expected) in Self.tagOracle {
            #expect(
                MarkdownMetadataParser.metadata(in: content).tags == expected,
                "the hoisted patterns changed the tags of \(content.debugDescription)"
            )
        }
        // Non-vacuity: the corpus is not a list of empty answers, and it does drop things.
        #expect(Self.tagOracle.contains { !$0.expected.isEmpty })
        #expect(Self.tagOracle.contains { $0.expected.isEmpty })
        #expect(Self.tagOracle.reduce(0) { $0 + $1.expected.count } == 12)
    }

    /// Corpus and recorded pre-change output. See the test above.
    nonisolated static let tagOracle: [(content: String, expected: [String])] = [
        ("#alpha and #beta", ["alpha", "beta"]),
        ("---\ntags: [front, matter]\n---\n\nbody #inline", ["front", "matter", "inline"]),
        ("# Heading #nottag\n\nprose #real", ["real"]),
        ("```\n#fenced\n```\n#after", ["after"]),
        ("`#code` and [link](#anchor) and <a href=\"#quickstart\">x</a> and https://e.com/#frag and #kept", ["kept"]),
        ("café#notatag but #yes", ["yes"]),
        ("###### deep heading\n#tail", ["tail"]),
        ("#Dash-1 #under_score", ["Dash-1", "under_score"]),
        ("no tags at all", []),
        ("", []),
    ]

    // MARK: - Measurement

    private nonisolated func measure(store: SweepStore, defaults: UserDefaults) throws -> Reading {
        var reading = Reading()
        for index in 0..<Self.repetitions {
            let recorder = try #require(CadenceStartupCostLedger.begin(defaults: defaults))
            let opened = DispatchTime.now().uptimeNanoseconds
            let container = try store.openWritableContainer()
            let context = ModelContext(container)
            recorder.finished(.containerOpen, .completed)
            _ = Double(DispatchTime.now().uptimeNanoseconds - opened) / 1_000_000_000

            // The suite is `@MainActor` and `withTemporaryDefaults` takes a synchronous,
            // non-escaping closure, so this body really does run on the main actor — but the
            // closure's own type is nonisolated and cannot say so. `assumeIsolated` is the
            // assertion of what is already true, not a hop.
            MainActor.assumeIsolated {
                PersistenceController.performStartupMaintenance(in: context, defaults: defaults, recorder: recorder)
            }
            _ = recorder.commit()
            let report = try #require(CadenceStartupCostLedger.lastReport(defaults: defaults).report)
            reading.add(report, cold: index == 0)
        }
        return reading
    }

    struct Reading {
        /// The last report the cohort produced — a warm one, so the assertions above are about the
        /// steady state rather than about the launch that did the repairing.
        var lastReport: CadenceStartupCostReport?
        var cold: [CadenceStartupStage: TimeInterval] = [:]
        var coldTotal: TimeInterval = 0
        var warm: [CadenceStartupStage: [TimeInterval]] = [:]
        var warmTotals: [TimeInterval] = []

        mutating func add(_ report: CadenceStartupCostReport, cold isCold: Bool) {
            lastReport = report
            if isCold {
                for stage in report.stages { cold[stage.stage] = stage.duration }
                coldTotal = report.totalDuration
            } else {
                for stage in report.stages { warm[stage.stage, default: []].append(stage.duration) }
                warmTotals.append(report.totalDuration)
            }
        }

        var described: String {
            let order: [CadenceStartupStage] = [
                .pursuitMigration, .noteMigration, .tagSync, .integrityRepair, .focusReconciliation, .maintenanceSave,
            ]
            let coldParts = order.map { "\($0.rawValue)=\(Self.ms([cold[$0] ?? 0]))" }.joined(separator: " ")
            let warmParts = order.map { "\($0.rawValue)=\(Self.ms(warm[$0] ?? []))" }.joined(separator: " ")
            return """
                cold total=\(Self.ms([coldTotal])) \(coldParts)
                                           warm total=\(Self.ms(warmTotals)) spread=[\(Self.ms([warmTotals.min() ?? 0]))..\(Self.ms([warmTotals.max() ?? 0]))] \(warmParts)
                """
        }

        static func ms(_ samples: [TimeInterval]) -> String {
            guard !samples.isEmpty else { return "-" }
            let sorted = samples.sorted()
            return String(format: "%.2fms", sorted[sorted.count / 2] * 1_000)
        }
    }

    // MARK: - Fixture

    struct SweepStore {
        struct Shape {
            var notes: Int = baselineNotes
            var tasks: Int = baselineTasks
            var bodyBytes: Int = baselineBodyBytes
            var tagsPerNote: Int = baselineTagsPerNote
            var duplicateNotes: Int = 0
            var bodyLines: Int = 3
        }

        let directory: URL
        let storeURL: URL

        init(_ shape: Shape) throws {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cadence-startup-sweep-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            storeURL = directory.appendingPathComponent("fixture.store")

            let context = ModelContext(try openWritableContainer())
            let todayKey = DateFormatters.dateKey(from: Date(), calendar: .current)
            for index in 0..<shape.tasks {
                let task = AppTask(title: "Task \(index)")
                if index.isMultiple(of: 2) { task.dueDate = todayKey }
                context.insert(task)
            }
            let perLine = max(1, shape.bodyBytes / max(1, shape.bodyLines) / 39)
            let line = String(repeating: "lorem ipsum dolor sit amet consectetur ", count: perLine)
            let filler = Array(repeating: line, count: max(1, shape.bodyLines)).joined(separator: "\n")
            for index in 0..<shape.notes {
                let tags = (0..<shape.tagsPerNote).map { "#tag\((index + $0) % 40)" }.joined(separator: " ")
                context.insert(
                    Note(kind: .list, title: "Note \(index)", content: "\(tags)\n\n\(filler)")
                )
            }
            // Duplicate density: daily notes sharing one `dateKey` all carry canonical key
            // `daily:<key>`, which is what `repairDuplicateNotes` groups on.
            for index in 0..<shape.duplicateNotes {
                let note = Note(kind: .daily, title: "Daily \(index)", content: "#dup body")
                note.dateKey = todayKey
                context.insert(note)
            }
            try context.save()
        }

        func openWritableContainer() throws -> ModelContainer {
            try ModelContainer(
                for: CadenceSchema.schema,
                configurations: ModelConfiguration(
                    "CadenceStartupSweepFixture",
                    schema: CadenceSchema.schema,
                    url: storeURL,
                    cloudKitDatabase: .none
                )
            )
        }

        /// What the store holds now — read after a cohort has run, so a merged duplicate really
        /// reads as merged rather than as the count it was seeded with.
        func rowCounts() throws -> (tasks: Int, notes: Int) {
            let context = ModelContext(try openWritableContainer())
            return (
                try context.fetchCount(FetchDescriptor<AppTask>()),
                try context.fetchCount(FetchDescriptor<Note>())
            )
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
