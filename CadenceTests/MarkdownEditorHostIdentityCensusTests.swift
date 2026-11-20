import Foundation
import Testing

/// **[[T-18593]], [[T-18595]] — a Mac `MarkdownEditor` whose document can change under it is keyed
/// by that document's id.**
///
/// The editor's coordinator owns its own undo history ([[T-17182]]) and records a non-load rewrite
/// of a non-empty view as an undoable step ([[T-17181]]). Both are right for one document and wrong
/// across two: a host that hands the SAME editor a different document gets the incoming text as an
/// undoable rewrite on top of the outgoing document's typing, so Cmd+Z writes the previous document
/// into the new one through the binding's setter. The Settings > Templates body editor did it on a
/// row click; the Today notes panel did it when the day turned. The behaviour of a fresh editor is
/// `MarkdownEditorUndoHistoryTests.anotherNotesEditorStartsWithNoUndoHistory`; what has to stay
/// true here is that each host actually builds a fresh one, which is a property of where `.id`
/// sits and so a source scan.
///
/// The denominator is read off disk: every file under `Cadence/macOS/` outside the editor itself
/// that constructs a `MarkdownEditor`. A new host fails `everyMacMarkdownEditorHostIsClassified`
/// until someone decides which of the two ways below it is keyed.
@Suite("Mac markdown editor host identity")
struct MarkdownEditorHostIdentityCensusTests {
    enum Keying {
        /// The document changes while the host stays on screen, so the host keys the editor
        /// itself: `declaration`'s body carries `key` in the `MarkdownEditor(...)` modifier chain.
        case inPlace(declaration: String, key: String)
        /// The host type is built once per document; `callerKeyedSites` or the reason says how its
        /// callers keep that true.
        case perDocument(reason: String)
    }

    static let hosts: [String: Keying] = [
        "Cadence/macOS/Views/SettingsTemplatesSection.swift": .inPlace(
            declaration: "private var templateEditor: some View",
            key: ".id(selectedTemplate.id)"
        ),
        "Cadence/macOS/Views/NotePanel.swift": .inPlace(
            declaration: "private func noteEditor(for note: Note)",
            key: ".id(note.id)"
        ),
        "Cadence/macOS/Views/NoteEditorPane.swift": .perDocument(
            reason: "NoteEditorPane: Notes and list-notes callers key it (callerKeyedSites); the event-note sheet is one sheet per note"
        ),
        "Cadence/macOS/Views/ListNotesSupportViews.swift": .perDocument(
            reason: "TaskNoteEditorPane: list notes keys it (callerKeyedSites); the expanded task-notes panel builds a new hosting view per show"
        ),
        "Cadence/macOS/Views/FocusNotesPanel.swift": .perDocument(
            reason: "FocusNotesPanel: FocusView keys it by task (callerKeyedSites, T-17043)"
        ),
        "Cadence/macOS/Views/TaskInspectorContentSupportViews.swift": .perDocument(
            reason: "TaskDetailNotesSection: drawn inside a TaskDetailPopover presented per task; the global inspector layer can swap its task in place, T-18600"
        ),
        "Cadence/macOS/Views/TimelineEventBlockSupportViews.swift": .perDocument(
            reason: "CalendarEventEditPopover: presented per event"
        ),
    ]

    /// Callers that keep a per-document host per document. Each construction of `type` in `file`
    /// must carry an `.id(` whose argument starts with one of `keys`, and there are `count` of them.
    static let callerKeyedSites: [(file: String, type: String, keys: [String], count: Int)] = [
        ("Cadence/macOS/Views/FocusView.swift", "FocusNotesPanel", [".id(task.id)"], 1),
        ("Cadence/macOS/Views/NotesView.swift", "NoteEditorPane", [".id(note.id)"], 4),
        ("Cadence/macOS/Views/ListNotesView.swift", "NoteEditorPane", [".id(eventNote.id)", ".id(note.id)"], 2),
        ("Cadence/macOS/Views/ListNotesView.swift", "TaskNoteEditorPane", [".id(task.id)"], 1),
    ]

    // MARK: - Scanning

    /// Start offsets of every construction `Type(` in comment- and string-blanked `code`, with no
    /// identifier character before it (so `NoteEditorPane(` does not match `TaskNoteEditorPane(`).
    static func constructions(of type: String, in code: String) -> [String.Index] {
        let pattern = "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: type) + "\\("
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(code.startIndex..., in: code)
        return regex.matches(in: code, range: range).compactMap { Range($0.range, in: code)?.lowerBound }
    }

    /// The modifier chain hung off the call that opens at `start`: everything after its matching
    /// `)` that is a run of `.modifier(...)` / `.modifier { ... }` lines. It stops at the first
    /// line that does not start with `.`, so a sibling view's `.id` is never credited to this one.
    static func modifierChain(ofCallAt start: String.Index, in code: String) -> String? {
        guard let arguments = CadenceSourceScan.matchedRange(after: start, in: code, open: "(", close: ")") else {
            return nil
        }
        var index = code.index(after: arguments.upperBound)
        var chain = ""
        while index < code.endIndex {
            while index < code.endIndex, code[index].isWhitespace { index = code.index(after: index) }
            guard index < code.endIndex, code[index] == "." else { break }
            var depth = 0
            while index < code.endIndex {
                let character = code[index]
                if "({[".contains(character) { depth += 1 }
                if ")}]".contains(character) { depth -= 1 }
                if character.isNewline, depth <= 0 { break }
                chain.append(character)
                index = code.index(after: index)
            }
            chain.append("\n")
        }
        return chain
    }

    // MARK: - Tests

    @Test func theChainScannerStopsAtASiblingView() throws {
        let code = """
            VStack {
                Editor(text: x)
                    .frame(minHeight: 280)
                    .onAppear {
                        load()
                    }
                Sibling()
                    .id(other.id)
            }
            """
        let start = try #require(Self.constructions(of: "Editor", in: code).first)
        let chain = try #require(Self.modifierChain(ofCallAt: start, in: code))
        #expect(chain.contains(".frame(minHeight: 280)"))
        #expect(chain.contains("load()"))
        #expect(!chain.contains(".id("))
        #expect(Self.constructions(of: "Editor", in: "OtherEditor(a) Editor(b)").count == 1)
    }

    @Test func everyMacMarkdownEditorHostIsClassified() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence/macOS")
            .filter { !$0.hasPrefix("Cadence/macOS/Editor/") }
        var found: Set<String> = []
        for file in files {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(file))
            if !Self.constructions(of: "MarkdownEditor", in: code).isEmpty { found.insert(file) }
        }
        #expect(found.count >= 2, "the scan found \(found.count) hosts; it is not reading the tree")
        let unclassified = found.subtracting(Self.hosts.keys).sorted()
        let stale = Set(Self.hosts.keys).subtracting(found).sorted()
        #expect(
            unclassified.isEmpty,
            "a new MarkdownEditor host: key it by its document's id where the document can change under it, then list it here: \(unclassified)"
        )
        #expect(stale.isEmpty, "listed hosts that no longer construct a MarkdownEditor: \(stale)")
    }

    @Test func aHostWhoseDocumentChangesInPlaceKeysTheEditorByTheDocumentID() throws {
        var checked = 0
        for (file, keying) in Self.hosts.sorted(by: { $0.key < $1.key }) {
            guard case let .inPlace(declaration, key) = keying else { continue }
            let source = try CadenceSourceScan.sourceFile(file)
            let body = try #require(
                CadenceSourceScan.declarationBody(declaration, in: source),
                "\(file): no `\(declaration)`"
            )
            let code = CadenceSourceScan.codeOnly(body)
            let calls = Self.constructions(of: "MarkdownEditor", in: code)
            #expect(calls.count == 1, "\(file): \(calls.count) MarkdownEditor calls in \(declaration)")
            let start = try #require(calls.first, "\(file): no MarkdownEditor in \(declaration)")
            let chain = try #require(Self.modifierChain(ofCallAt: start, in: code))
            #expect(chain.contains(key), "\(file): the MarkdownEditor in \(declaration) is not keyed by `\(key)`")
            checked += 1
        }
        #expect(checked == 2)
    }

    @Test func aPerDocumentHostIsKeyedByItsCaller() throws {
        for site in Self.callerKeyedSites {
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(site.file))
            let calls = Self.constructions(of: site.type, in: code)
            #expect(calls.count == site.count, "\(site.file): \(calls.count) \(site.type) constructions, expected \(site.count)")
            for start in calls {
                let chain = try #require(Self.modifierChain(ofCallAt: start, in: code))
                #expect(
                    site.keys.contains { chain.contains($0) },
                    "\(site.file): a \(site.type) is not keyed by one of \(site.keys)"
                )
            }
        }
    }
}
