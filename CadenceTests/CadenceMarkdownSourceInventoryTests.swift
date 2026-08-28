import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-411.** `deleteUnreferencedMarkdownImageAssets` defined "referenced" as `Note.content` and
/// nothing else, while the markdown editor that *creates* `MarkdownImageAsset` rows is bound to
/// several fields — `AppTask.notes` among them, from `FocusNotesPanel`,
/// `TaskInspectorContentSupportViews` and `iOSTaskDetailSheetSections`. An image pasted into a
/// task's notes was therefore unreferenced by definition, and the next note delete or list cascade
/// collected its `.externalStorage` bytes while the task kept a reference that no longer resolved.
/// Paste is the ordinary path, and the bytes do not come back.
///
/// **Three kinds of test here.**
///
/// The two behavioural halves pin the loss itself: an image referenced *only* from a task's notes
/// survives both a `deleteNote` and a list cascade, asserted by identity rather than by a count.
///
/// The per-source half walks `CadenceMarkdownSourceInventory.Source.allCases` and proves each case
/// is genuinely read — deleting a case and its switch arm compiles, so only a store round trip
/// catches it.
///
/// The inventory half is the durable part: a source scan of `Cadence/Models/` that fails when any
/// stored `String` property is neither in the inventory nor explicitly declared plain. A future
/// model gaining a markdown field is then a red test rather than a silent deletion — which is the
/// only reason this file is worth its length.
@MainActor
struct CadenceMarkdownSourceInventoryTests {

    // MARK: - Fixtures

    private func imageAsset(_ byte: UInt8) -> MarkdownImageAsset {
        MarkdownImageAsset(
            data: Data([byte]),
            mimeType: "image/png",
            pixelWidth: 20,
            pixelHeight: 20,
            displayWidth: 20
        )
    }

    private func imageLine(_ asset: MarkdownImageAsset) -> String {
        "![shot](cadence-image://\(asset.id.uuidString))"
    }

    // MARK: - The loss, from both delete paths

    /// An image pasted into a task's notes, and an unrelated note deleted. The image stays.
    ///
    /// Asserted by identity — the asset row is still there and the task's own reference still
    /// resolves to it — because "the count went down by one" is equally true of the run that
    /// deleted the wrong asset.
    @Test func anImageOnlyATaskNotesReferencesSurvivesANoteDelete() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let taskImage = imageAsset(1)
        let noteImage = imageAsset(2)
        let task = AppTask(title: "Ship the release")
        task.notes = "Checklist\n\n\(imageLine(taskImage))"
        let note = Note(kind: .list, title: "Scratch", content: imageLine(noteImage))

        modelContext.insert(taskImage)
        modelContext.insert(noteImage)
        modelContext.insert(task)
        modelContext.insert(note)
        try modelContext.save()

        modelContext.deleteNote(note)
        try modelContext.save()

        let remaining = try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>())
        #expect(remaining.contains { $0.id == taskImage.id })
        // The note's own image is still collected: nothing else referenced it.
        #expect(!remaining.contains { $0.id == noteImage.id })

        let survivingTask = try modelContext.fetch(FetchDescriptor<AppTask>()).first
        #expect(survivingTask != nil)
        #expect(MarkdownImageAssetService.referencedIDs(in: survivingTask?.notes ?? "") == [taskImage.id])
    }

    /// The same image, and this time a whole list is deleted out from under it.
    ///
    /// The task lives in the Inbox, not in the deleted area — that is the point. A task inside the
    /// list goes with the list, and its images *should* be reclaimed; a task outside it is
    /// untouched by the cascade and its picture must be too.
    @Test func anImageOnlyATaskNotesReferencesSurvivesAListCascade() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let keptImage = imageAsset(3)
        let doomedImage = imageAsset(4)

        let context = Context(name: "Work")
        let area = Area(name: "Launch", context: context)
        let areaNote = Note(kind: .list, title: "Area note", content: imageLine(doomedImage))
        areaNote.area = area
        let inboxTask = AppTask(title: "Inbox task")
        inboxTask.notes = "Reference\n\n\(imageLine(keptImage))"

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(keptImage)
        modelContext.insert(doomedImage)
        modelContext.insert(areaNote)
        modelContext.insert(inboxTask)
        try modelContext.save()

        #expect(modelContext.deleteArea(area))
        try modelContext.save()

        let remaining = try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>())
        #expect(remaining.contains { $0.id == keptImage.id })
        #expect(!remaining.contains { $0.id == doomedImage.id })

        let survivingTask = try modelContext.fetch(FetchDescriptor<AppTask>()).first
        #expect(survivingTask?.id == inboxTask.id)
    }

    /// The other direction: a task *inside* the deleted list still takes its images with it.
    ///
    /// Widening the scan to `AppTask.notes` risks trading a data loss for a storage leak — every
    /// list delete keeping the images of the tasks it just deleted. It does not, and this pins that.
    ///
    /// **What it does not prove:** the `isDeleted` filter in `CadenceMarkdownSourceInventory` is not
    /// what makes it pass. Removing that filter leaves this test green, because SwiftData does not
    /// hand back the cascade's deleted-but-unsaved rows. The filter is insurance for a window the
    /// sweep genuinely runs in, and it is unpinnable from here; see the note on `texts(of:in:at:)`.
    @Test func anImageOnlyADeletedListsTaskReferencedIsStillReclaimed() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let image = imageAsset(7)
        let context = Context(name: "Work")
        let area = Area(name: "Launch", context: context)
        let areaTask = AppTask(title: "Area task")
        areaTask.area = area
        areaTask.notes = imageLine(image)

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(image)
        modelContext.insert(areaTask)
        try modelContext.save()

        #expect(modelContext.deleteArea(area))
        try modelContext.save()

        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).isEmpty)
    }

    // MARK: - Every case in the inventory is actually read

    /// One store per case: seed exactly one row of that model holding the only reference to an
    /// image, sweep, and require the image to survive while an unreferenced one goes.
    ///
    /// **Why a round trip and not an equality check on `allCases`.** Removing a case *and* its
    /// switch arm compiles cleanly and silently narrows the scan back down — the exact shape of the
    /// original defect. Only reading the store proves the case does something.
    @Test func everySourceInTheInventoryKeepsItsOwnImageAlive() throws {
        for source in CadenceMarkdownSourceInventory.Source.allCases {
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let modelContext = ModelContext(container)

            let referenced = imageAsset(5)
            let orphan = imageAsset(6)
            modelContext.insert(referenced)
            modelContext.insert(orphan)
            seedRow(for: source, referencing: referenced, in: modelContext)
            try modelContext.save()

            modelContext.deleteUnreferencedMarkdownImageAssets()
            try modelContext.save()

            let remaining = try modelContext.fetch(FetchDescriptor<MarkdownImageAsset>()).map(\.id)
            #expect(
                remaining.contains(referenced.id),
                "\(source.entityName).\(source.propertyName) is in the inventory but its text was not read"
            )
            #expect(
                !remaining.contains(orphan.id),
                "\(source.entityName).\(source.propertyName) left a genuinely unreferenced asset behind"
            )
        }
    }

    /// Exhaustive on purpose: a new case is a compile error here as well as in the reader.
    private func seedRow(
        for source: CadenceMarkdownSourceInventory.Source,
        referencing asset: MarkdownImageAsset,
        in modelContext: ModelContext
    ) {
        let body = imageLine(asset)
        switch source {
        case .noteContent:
            modelContext.insert(Note(kind: .list, title: "Note", content: body))
        case .taskNotes:
            let task = AppTask(title: "Task")
            task.notes = body
            modelContext.insert(task)
        case .documentContent:
            let document = Document(title: "Doc")
            document.content = body
            modelContext.insert(document)
        case .dailyNoteContent:
            let daily = DailyNote(date: "2026-08-29")
            daily.content = body
            modelContext.insert(daily)
        case .weeklyNoteContent:
            let weekly = WeeklyNote(weekKey: "2026-W35")
            weekly.content = body
            modelContext.insert(weekly)
        case .permNoteContent:
            let notepad = PermNote()
            notepad.content = body
            modelContext.insert(notepad)
        case .eventNoteContent:
            let eventNote = EventNote(calendarEventID: "evt-1", eventTitle: "Standup")
            eventNote.content = body
            modelContext.insert(eventNote)
        }
    }

    // MARK: - The inventory against the schema and against the model sources

    /// Every entity in `CadenceSchema` is classified: either it carries markdown and appears in the
    /// inventory, or it is named below as carrying none. Adding a `@Model` to the schema and
    /// deciding nothing fails here — the same arrangement `CadencePrivacyDataResetSurfaceTests` and
    /// `CadenceDataExportSurfaceTests` use for their own standing obligations.
    @Test func everySchemaEntityIsClassifiedByTheInventory() {
        let schemaNames = Set(CadenceSchema.schema.entities.map(\.name))
        let markdownNames = Set(CadenceMarkdownSourceInventory.Source.allCases.map(\.entityName))
        let classified = markdownNames.union(Self.entitiesWithoutMarkdown)

        #expect(
            schemaNames.subtracting(classified).isEmpty,
            "unclassified schema entities: \(schemaNames.subtracting(classified).sorted())"
        )
        #expect(
            classified.subtracting(schemaNames).isEmpty,
            "classified names that are not in the schema: \(classified.subtracting(schemaNames).sorted())"
        )
        // The two halves must not overlap, or an entity could be "no markdown" and read anyway.
        #expect(markdownNames.intersection(Self.entitiesWithoutMarkdown).isEmpty)
    }

    /// Every stored `String` on every `@Model` is either in the inventory or declared plain.
    ///
    /// This is the one that catches the *next* T-411: a new markdown-bearing field on an existing
    /// model. The scan cannot tell markdown from a colour hex, so the classification is written
    /// down and the scan pins that nothing escapes it — in both directions, because a stale entry
    /// here would otherwise hide a renamed field.
    @Test func everyStoredStringOnEveryModelIsClassified() throws {
        let scan = try scanModelStoredStringProperties()
        let inventory = Set(CadenceMarkdownSourceInventory.Source.allCases.map {
            ModelStringProperty(entityName: $0.entityName, propertyName: $0.propertyName)
        })
        let plain = Set(Self.plainStringProperties.flatMap { entity, properties in
            properties.map { ModelStringProperty(entityName: entity, propertyName: $0) }
        })
        let classified = inventory.union(plain)

        let unclassified = scan.properties.subtracting(classified)
        #expect(
            unclassified.isEmpty,
            "stored String properties that are neither markdown nor declared plain: \(described(unclassified))"
        )
        let stale = classified.subtracting(scan.properties)
        #expect(
            stale.isEmpty,
            "classified properties that no longer exist in Cadence/Models: \(described(stale))"
        )
        #expect(inventory.intersection(plain).isEmpty)
    }

    /// Non-vacuity. A reader that returned nothing would make both assertions above pass, so this
    /// pins that the scan read real files and found the fields the other tests reason about.
    @Test func theModelScanActuallyReadTheModelSources() throws {
        let scan = try scanModelStoredStringProperties()

        #expect(scan.filesRead >= 20, "only \(scan.filesRead) files under Cadence/Models were read")
        #expect(scan.shortestFileLength > 200, "a model file came back suspiciously short")
        #expect(scan.properties.count >= 80, "only \(scan.properties.count) stored String properties found")
        // Three controls: the field this ticket is about, the field it used to be alone, and one
        // that must never be treated as markdown.
        #expect(scan.properties.contains(ModelStringProperty(entityName: "AppTask", propertyName: "notes")))
        #expect(scan.properties.contains(ModelStringProperty(entityName: "Note", propertyName: "content")))
        #expect(scan.properties.contains(ModelStringProperty(entityName: "Area", propertyName: "colorHex")))
        // Computed properties are not stored, and must not be demanded of the classification.
        #expect(!scan.properties.contains(ModelStringProperty(entityName: "AppTask", propertyName: "containerName")))
        // Non-`@Model` types in the same folder are out of scope for a store scan.
        #expect(!scan.properties.contains(ModelStringProperty(entityName: "TaskSectionConfig", propertyName: "colorHex")))
    }

    // MARK: - Classification

    /// Schema entities with no markdown-bearing field at all.
    ///
    /// `MarkdownImageAsset` is here deliberately: `altText` is the accessibility caption, not a
    /// body, and treating it as markdown would let an asset keep *itself* alive.
    private static let entitiesWithoutMarkdown: Set<String> = [
        "Area",
        "Context",
        "Goal",
        "GoalListLink",
        "Habit",
        "HabitCompletion",
        "MarkdownImageAsset",
        "Project",
        "Pursuit",
        "SavedLink",
        "Subtask",
        "Tag",
        "TaskBundle"
    ]

    /// Every stored `String` that is *not* markdown, by model.
    ///
    /// Long on purpose. The alternative — listing only the markdown fields — is the definition that
    /// caused T-411: it is silent about anything it has not been told, and silence there deletes
    /// pictures. A description field is a plausible future markdown surface; if one of these is
    /// ever bound to the editor, moving its name from here into `Source` is the whole fix.
    private static let plainStringProperties: [String: [String]] = [
        "AppTask": [
            "title", "priorityRaw", "statusRaw", "dueDate", "scheduledDate", "calendarEventID",
            "recurrenceRaw", "recurrenceSpawnedTaskIDRaw", "recurrenceSeriesIDRaw",
            "recurrenceSourceTaskIDRaw", "recurrenceEndModeRaw", "recurrenceEndDate", "sectionName"
        ],
        "Area": [
            "name", "desc", "statusRaw", "colorHex", "icon", "linkedCalendarID",
            "sectionNamesRaw", "sectionConfigsRaw"
        ],
        "Context": ["name", "colorHex", "icon"],
        "DailyNote": ["date"],
        "Document": ["title"],
        "EventNote": ["calendarEventID", "calendarID", "title", "eventDateKey"],
        "Goal": [
            "title", "desc", "startDate", "endDate", "progressTypeRaw", "colorHex", "icon",
            "statusRaw", "kindRaw", "dependsOnGoalIDsJSON"
        ],
        "Habit": ["title", "icon", "colorHex", "frequencyTypeRaw", "frequencyDaysRaw"],
        "HabitCompletion": ["date"],
        "MarkdownImageAsset": ["mimeType", "originalFilename", "altText"],
        "Note": [
            "kindRaw", "title", "dateKey", "weekKey", "calendarEventID", "calendarID",
            "eventDateKey", "legacySourceKindRaw", "legacySourceID", "folderPath"
        ],
        "Project": [
            "name", "desc", "statusRaw", "colorHex", "icon", "dueDate", "linkedCalendarID",
            "sectionNamesRaw", "sectionConfigsRaw"
        ],
        "Pursuit": ["title", "desc", "icon", "colorHex", "kindRaw", "statusRaw"],
        "SavedLink": ["title", "url"],
        "Subtask": ["title"],
        "Tag": ["slug", "name", "desc", "colorHex"],
        "TaskBundle": ["title", "dateKey"],
        "WeeklyNote": ["weekKey"]
    ]

    private func described(_ properties: Set<ModelStringProperty>) -> String {
        properties.map { "\($0.entityName).\($0.propertyName)" }.sorted().joined(separator: ", ")
    }
}

// MARK: - Source-reading helpers

private struct ModelStringProperty: Hashable {
    let entityName: String
    let propertyName: String
}

private struct ModelStringPropertyScan {
    var properties: Set<ModelStringProperty> = []
    var filesRead = 0
    var shortestFileLength = Int.max
}

/// Reads `Cadence/Models/` and returns the stored `String` properties of every `@Model` type.
///
/// Deliberately literal-minded: only top-level declarations set the current type, only a
/// `@Model`-marked one counts, only properties at the model's own indentation are collected, and a
/// declaration whose line ends in `{` is a computed property rather than storage. Anything this
/// reader is unsure of, it drops — and a dropped stored field would show up as an *unclassified*
/// entry rather than as silence, because the classification is checked in both directions.
private func scanModelStoredStringProperties() throws -> ModelStringPropertyScan {
    let declaration = try NSRegularExpression(
        pattern: "^(@Model\\s+)?(?:nonisolated\\s+)?(?:public\\s+)?(?:final\\s+)?(?:class|struct|enum|extension|protocol)\\s+(\\w+)"
    )
    let property = try NSRegularExpression(
        pattern: "^\\s{4}(?:@\\w+(?:\\([^)]*\\))?\\s+)*var\\s+(\\w+):\\s*String\\b"
    )

    var scan = ModelStringPropertyScan()
    for path in try modelSourcePaths() {
        let source = try sourceFile(path)
        scan.filesRead += 1
        scan.shortestFileLength = min(scan.shortestFileLength, source.count)

        var currentModel: String?
        for line in strippingComments(source).components(separatedBy: "\n") {
            let range = NSRange(location: 0, length: (line as NSString).length)
            if let match = declaration.firstMatch(in: line, range: range) {
                let isModel = match.range(at: 1).location != NSNotFound
                currentModel = isModel ? (line as NSString).substring(with: match.range(at: 2)) : nil
                continue
            }
            guard let entityName = currentModel,
                  !line.trimmingCharacters(in: .whitespaces).hasSuffix("{"),
                  let match = property.firstMatch(in: line, range: range)
            else { continue }
            scan.properties.insert(ModelStringProperty(
                entityName: entityName,
                propertyName: (line as NSString).substring(with: match.range(at: 1))
            ))
        }
    }
    return scan
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func modelSourcePaths() throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent("Cadence/Models")
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "Cadence/Models/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the scan reads code rather than
/// prose. Crude on purpose: a `//` inside a string literal is blanked too, which can only make the
/// reader stricter about what counts as a comment, never looser about live code.
private func strippingComments(_ source: String) -> String {
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
