import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexInlineTagEditingTests {
    private struct Refused: Error {}

    @Test func mobileTagEditUsesMacValidationIncludingArchivedCollisions() throws {
        let tag = Cadence.Tag(name: "Work")
        let archived = Cadence.Tag(name: "Café", isArchived: true)
        let all = [tag, archived]
        #expect(iOSTagSettingsEdit.canSave(name: " #Work# ", tag: tag, allTags: all))
        for name in ["", " \n ", "###", "cafe", "CAFÉ"] {
            #expect(!iOSTagSettingsEdit.canSave(name: name, tag: tag, allTags: all))
        }
        #expect(iOSTagSettingsEdit.hasDuplicate(name: "cafe", tag: tag, allTags: all))
    }

    @Test func mobileTagEditPersistsIdentityMetadataAndLinkedNoteFrontmatter() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tag = Cadence.Tag(name: "Work", desc: "Old", colorHex: Theme.blueHex)
        let task = AppTask(title: "Linked task")
        let note = Note(kind: .daily, title: "Linked note", content: "---\ntags: [Work]\n---\n\nBody")
        context.insert(tag)
        context.insert(task)
        context.insert(note)
        task.tags = [tag]
        note.tags = [tag]
        try context.save()
        let id = tag.id
        try iOSTagSettingsEdit.save(tag: tag, name: " #Job# ", description: " Revised \n",
                                    colorHex: "ABCDEF", allTags: [tag], in: context,
                                    rewritingInlineMentions: false)
        let reader = ModelContext(container)
        let stored = try #require(reader.fetch(FetchDescriptor<Cadence.Tag>()).first)
        #expect(stored.id == id)
        #expect(stored.name == "Job")
        #expect(stored.slug == "job")
        #expect(stored.desc == "Revised")
        #expect(stored.colorHex == "#abcdef")
        #expect(try reader.fetch(FetchDescriptor<Cadence.Tag>()).count == 1)
        let storedTask = try #require(reader.fetch(FetchDescriptor<AppTask>()).first)
        let storedNote = try #require(reader.fetch(FetchDescriptor<Note>()).first)
        #expect(storedTask.tags?.first?.id == id)
        #expect(storedTask.tags?.first?.name == "Job")
        #expect(storedNote.tags?.first?.id == id)
        #expect(MarkdownMetadataParser.frontmatterTagNames(in: storedNote.content) == ["Job"])
        #expect(storedNote.content.hasSuffix("\n\nBody"))
    }

    @Test func mobileTagEditRefusalRestoresFieldsAndNotesWithoutDiscardingOtherWork() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tag = Cadence.Tag(name: "Work", desc: "Old", colorHex: Theme.blueHex)
        let note = Note(kind: .daily, title: "Note", content: "---\ntags: [Work]\n---\n\nBody")
        let task = AppTask(title: "Before")
        context.insert(tag)
        context.insert(note)
        context.insert(task)
        note.tags = [tag]
        try context.save()
        let timestamp = tag.updatedAt
        let content = note.content
        let noteTimestamp = note.updatedAt
        task.title = "Other pending edit"
        #expect(throws: Refused.self) {
            try iOSTagSettingsEdit.save(tag: tag, name: "Job", description: "New",
                                        colorHex: Theme.redHex, allTags: [tag], in: context,
                                        rewritingInlineMentions: false,
                                        commit: { _ in throw Refused() })
        }
        #expect(tag.name == "Work")
        #expect(tag.slug == "work")
        #expect(tag.desc == "Old")
        #expect(tag.colorHex == Theme.blueHex)
        #expect(tag.updatedAt == timestamp)
        #expect(note.content == content)
        #expect(note.updatedAt == noteTimestamp)
        #expect(task.title == "Other pending edit")
        try context.save()
        let stored = try #require(ModelContext(container).fetch(FetchDescriptor<Cadence.Tag>()).first)
        #expect(stored.name == "Work")
    }

    @Test func mobileTagEditInvalidDraftNeverCommitsAndInvalidHexKeepsPreviousColor() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tag = Cadence.Tag(name: "Work", colorHex: Theme.blueHex)
        let other = Cadence.Tag(name: "Job", isArchived: true)
        context.insert(tag)
        context.insert(other)
        try context.save()
        var attempts = 0
        for name in ["###", "Job"] {
            try iOSTagSettingsEdit.save(tag: tag, name: name, description: "Changed",
                                        colorHex: Theme.redHex, allTags: [tag, other], in: context,
                                        rewritingInlineMentions: false,
                                        commit: { _ in attempts += 1 })
        }
        #expect(attempts == 0)
        #expect(tag.name == "Work")
        #expect(tag.desc.isEmpty)
        try iOSTagSettingsEdit.save(tag: tag, name: "Work", description: "Changed",
                                    colorHex: "invalid", allTags: [tag, other], in: context,
                                    rewritingInlineMentions: false)
        #expect(tag.colorHex == Theme.blueHex)
        #expect(tag.desc == "Changed")
    }

    @Test func mobileTagRowOffersInlineDraftAndClosesOnlyAfterCommit() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSettingsTagsSection.swift"))
        #expect(source.contains("iOSTagList(tags: activeTags, allTags: tags,"))
        #expect(source.contains("iOSTagList(tags: archivedTags, allTags: tags,"))
        #expect(source.contains("accessibilityLabel: \"Edit tag\""))
        #expect(source.contains("TextField(\"Tag name\", text: $draftName)"))
        #expect(source.contains("TextField(\"Optional description\", text: $draftDescription, axis: .vertical)"))
        #expect(source.contains("iOSSettingsColorSwatchRow(selectedHex: $draftColorHex, fallbackHex: tag.colorHex)"))
        #expect(source.contains("A tag with this name already exists."))
        #expect(source.contains("CadenceInlineFailureNotice(text: saveFailureNotice)"))
        let body = try #require(CadenceSourceScan.functionBody(named: "saveEdits", in: source))
        #expect(body.contains("try iOSTagSettingsEdit.save("))
        #expect(body.contains("guard canSave else { return }"))
        #expect(body.contains("rewritingInlineMentions: rewritingInlineMentions"),
                "the phone passes the user's answer down rather than deciding for them (T-6261)")
        #expect(body.contains("catch {\n            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice\n            return\n        }\n        saveFailureNotice = nil\n        isEditing = false"))
        #expect(!CadenceSourceScan.codeOnly(source).contains(".sheet("))

        // T-6261: Save asks first, and the question comes from the one shared modifier rather
        // than a phone-shaped copy of it.
        #expect(source.contains("isDisabled: !canSave, action: requestSave)"))
        #expect(source.contains(".cadenceTagRenameInlineConfirmation($inlineMentionPrompt)"))
        let request = try #require(CadenceSourceScan.functionBody(named: "requestSave", in: source))
        #expect(request.contains("CadenceTagRenameInlineMentions.prompt(for: tag, renamedTo: draftName)"))
        #expect(request.contains("saveEdits(rewritingInlineMentions: false)"),
                "no mentions in anybody's prose means no dialog and a straight save")
    }

    /// **T-6261 on the phone, both branches.** The editor is a caller of the shared rename, and a
    /// rename that warns in macOS Settings and splits silently here would be worse than the
    /// consistent split it replaces.
    @Test func mobileTagEditRewritesInlineMentionsOnlyWhenTheUserConfirms() throws {
        for confirmed in [false, true] {
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let context = ModelContext(container)
            let tag = Cadence.Tag(name: "Work")
            let note = Note(kind: .daily, title: "Note", content: "---\ntags: [Work]\n---\n\nFollow up on #work today")
            context.insert(tag)
            context.insert(note)
            note.tags = [tag]
            try context.save()

            #expect(TagSupport.inlineMentionCount(of: tag, renamedTo: "Job") == 1)
            try iOSTagSettingsEdit.save(tag: tag, name: "Job", description: "", colorHex: tag.colorHex,
                                        allTags: [tag], in: context,
                                        rewritingInlineMentions: confirmed)

            #expect(MarkdownMetadataParser.frontmatterTagNames(in: note.content) == ["Job"])
            #expect(note.content.hasSuffix(confirmed ? "Follow up on #Job today" : "Follow up on #work today"))

            // The split is the declined branch's actual outcome, not a description of one.
            TagSupport.syncNoteTagsFromMarkdown(note, in: context)
            try context.save()
            let slugs = try context.fetch(FetchDescriptor<Cadence.Tag>()).map(\.slug).sorted()
            #expect(slugs == (confirmed ? ["job"] : ["job", "work"]))
        }
    }
}
