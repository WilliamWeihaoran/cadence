import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-8761]] — the iOS note chrome's tag control, and the one choice list both platforms draw.**
///
/// The write is `CadenceNoteTagEditing` (Shared, so it is reachable from this macOS target) and is
/// asserted against a real in-memory container. The control itself, `iOSNoteTagControl`, and the
/// four places it is drawn are `#if os(iOS)`, so those halves are source scans over `codeOnly`.
struct CadenceNoteTagEditingTests {

    private struct CommitRefused: Error {}

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        return (container, ModelContext(container))
    }

    // MARK: - One choice list

    /// Active tags only, one per slug — the rule both popovers used to spell inline.
    @Test func noteTagPickerChoicesDropArchivedTagsAndKeepOnePerSlug() throws {
        let (_, context) = try makeContext()
        let roadmap = Tag(name: "roadmap", slug: "roadmap")
        let roadmapTwin = Tag(name: "Roadmap", slug: "roadmap")
        let archived = Tag(name: "old", slug: "old")
        archived.isArchived = true
        let brand = Tag(name: "brand", slug: "brand")
        for tag in [roadmap, roadmapTwin, archived, brand] { context.insert(tag) }

        let choices = TagSupport.pickerChoices(from: [roadmap, roadmapTwin, archived, brand])

        #expect(choices.count == 2, "one row per slug, no archived row")
        #expect(Set(choices.map(\.slug)) == ["roadmap", "brand"])
        #expect(choices.map(\.slug) == TagSupport.uniqueBySlug([roadmap, roadmapTwin, brand]).map(\.slug))
    }

    /// Both popovers a note's tag control presents — macOS's `TagPickerPopover` and the iOS
    /// `iOSTaskTagPickerPopover` the new note control reuses — list from `pickerChoices`, so one
    /// note offers the same tags on both platforms.
    @Test func bothNoteTagPopoversListFromTheOneSharedChoiceFunction() throws {
        let mac = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TagPickerPopoverViews.swift")
        )
        let iOS = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailComponents.swift")
        )
        #expect(mac.contains("struct TagPickerPopover: View"), "non-vacuity: wrong macOS file read")
        #expect(iOS.contains("struct iOSTaskTagPickerPopover: View"), "non-vacuity: wrong iOS file read")

        for (name, source) in [("macOS", mac), ("iOS", iOS)] {
            #expect(
                CadenceSourceScan.matchCount(#"TagSupport\.pickerChoices\(from: allTags\)"#, in: source) == 1,
                "\(name)'s tag popover should list from TagSupport.pickerChoices"
            )
            #expect(
                CadenceSourceScan.matchCount(#"uniqueBySlug\(allTags\.filter"#, in: source) == 0,
                "\(name)'s tag popover spells its own choice list again"
            )
        }
    }

    // MARK: - The write

    @Test func settingANotesTagsFromTheIOSChromeWritesTheTagsAndTheFrontmatter() throws {
        let (container, context) = try makeContext()
        let roadmap = Tag(name: "roadmap", slug: "roadmap")
        let note = Note(kind: .permanent, title: "Kickoff", content: "Body")
        context.insert(roadmap)
        context.insert(note)
        try context.save()

        let wrote = CadenceNoteTagEditing.setTags([roadmap], on: note, in: context)

        #expect(wrote)
        #expect(note.tags?.map(\.slug) == ["roadmap"])
        #expect(
            MarkdownMetadataParser.content(note.content, replacingFrontmatterTags: ["roadmap"]) == note.content,
            "the frontmatter carries exactly the picked tag, the Mac's writeFrontmatter: true"
        )
        #expect(note.content.contains("roadmap"))
        #expect(note.content.contains("Body"), "the body survived the frontmatter rewrite")
        try context.save()
        #expect(try ModelContext(container).fetch(FetchDescriptor<Cadence.Tag>()).count == 1, "no second row minted")
    }

    /// A chip's `x` drops that tag from `note.tags` and from the frontmatter, and — the Mac's rule —
    /// leaves a tag the body still mentions inline.
    @Test func removingANoteTagChipDropsItFromTheTagsAndTheFrontmatterButKeepsInlineTags() throws {
        let (_, context) = try makeContext()
        let alpha = Tag(name: "alpha", slug: "alpha")
        let beta = Tag(name: "beta", slug: "beta")
        let gamma = Tag(name: "gamma", slug: "gamma")
        let note = Note(kind: .permanent, title: "Kickoff", content: "Body #gamma")
        for tag in [alpha, beta, gamma] { context.insert(tag) }
        context.insert(note)
        try context.save()
        #expect(CadenceNoteTagEditing.setTags([alpha, beta], on: note, in: context))
        #expect(Set(note.tags?.map(\.slug) ?? []) == ["alpha", "beta", "gamma"], "precondition: inline #gamma folded in")
        #expect(note.content.contains("beta"), "precondition: beta is in the frontmatter")

        let wrote = CadenceNoteTagEditing.remove(beta, from: note, in: context)

        #expect(wrote)
        #expect(Set(note.tags?.map(\.slug) ?? []) == ["alpha", "gamma"])
        #expect(!note.content.contains("beta"), "the removed tag is gone from the frontmatter")
        #expect(note.content.contains("Body #gamma"))
    }

    /// A refused mint writes nothing, which is what lets the popover's `onCommit` answer `false`
    /// with nothing to restore.
    @Test func aRefusedMintFromTheIOSNoteChromeLeavesTheNoteUntouched() throws {
        let (_, context) = try makeContext()
        let note = Note(kind: .permanent, title: "Kickoff", content: "Body")
        let fresh = Tag(name: "fresh", slug: "fresh")
        context.insert(note)
        try context.save()

        let wrote = CadenceNoteTagEditing.setTags(
            [fresh], on: note, in: context, commit: { _ in throw CommitRefused() }
        )

        #expect(wrote == false)
        #expect((note.tags ?? []).isEmpty)
        #expect(note.content == "Body")
    }

    // MARK: - The iOS chrome

    /// The control writes only through `CadenceNoteTagEditing`, and resigns the editor before it
    /// opens the picker (the surface commits its own draft over an external write while focused).
    @Test func theIOSNoteTagControlWritesThroughTheSharedDoorAndDropsFocusFirst() throws {
        let control = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNoteTagControl.swift")
        )
        #expect(control.contains("struct iOSNoteTagControl: View"), "non-vacuity: wrong file read")
        #expect(CadenceSourceScan.matchCount(#"CadenceNoteTagEditing\.setTags\("#, in: control) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceNoteTagEditing\.remove\("#, in: control) == 1)
        #expect(CadenceSourceScan.matchCount(#"iOSTaskTagPickerPopover\("#, in: control) == 1)
        #expect(
            CadenceSourceScan.matchCount(#"note\.tags\s*=|setTagsCommittingInsertions|\.save\(\)"#, in: control) == 0,
            "the control writes the note some other way"
        )
        #expect(
            CadenceSourceScan.matchCount(#"isEditorFocused = false\s*isPickerPresented = true"#, in: control) == 1,
            "the trigger must resign the editor before presenting the picker"
        )
    }

    /// Header where the layout has two columns, format row everywhere else — the template menu's
    /// gate, at each of the four hosts.
    @Test func theIOSNoteTagControlIsDrawnInTheHeaderAtRegularWidthAndTheFormatRowOtherwise() throws {
        let notes = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNotesView.swift"))
        let listNotes = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListNotesView.swift"))
        let toolbar = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownAccessoryViews.swift"))
        let surface = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift"))
        #expect(notes.contains("struct iOSNoteEditorCover: View"), "non-vacuity: wrong notes file read")

        // Notes header: gated on the template menu's own flag.
        #expect(
            CadenceSourceScan.matchCount(
                #"if showsHeaderTemplateMenu, let note = selectedNote \{\s*iOSNoteTagControl\(note: note, isEditorFocused: \$isEditorFocused\)"#,
                in: notes
            ) == 1
        )
        // Its inline editor takes the format-row control exactly when the header does not.
        #expect(CadenceSourceScan.matchCount(#"tagNote: showsHeaderTemplateMenu \? nil : note,"#, in: notes) == 1)
        // The one-column cover always carries it.
        let cover = try #require(CadenceSourceScan.declarationBody("struct iOSNoteEditorCover: View", in: notes))
        #expect(CadenceSourceScan.matchCount(#"tagNote: note,"#, in: cover) == 1)

        // A list's Notes control row, two-column only.
        let controlRow = try #require(CadenceSourceScan.declarationBody("private var controlRow: some View", in: listNotes))
        #expect(CadenceSourceScan.matchCount(#"if layout == \.twoColumn, let note = selectedNote"#, in: controlRow) == 1)
        #expect(CadenceSourceScan.matchCount(#"iOSNoteTagControl\(note: note, isEditorFocused: \$isEditorFocused\)"#, in: controlRow) == 1)

        // The format row draws it, and the surface hands it the note and its focus.
        #expect(CadenceSourceScan.matchCount(#"if let tagNote \{\s*iOSNoteTagControl\("#, in: toolbar) == 1)
        #expect(CadenceSourceScan.matchCount(#"placement: \.formatRow"#, in: toolbar) == 1)
        #expect(CadenceSourceScan.matchCount(#"tagNote: tagNote,\s*isEditorFocused: \$isFocused,"#, in: surface) == 1)
    }
}
