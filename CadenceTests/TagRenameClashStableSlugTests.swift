import Foundation
import Testing
@testable import Cadence

/// [[T-14772]]: the rename-clash checks compare `TagSupport.stableSlug`, not the stored slug, so a
/// row stored as `"tag"` before [[T-14761]] under the name `工作` still blocks renaming another tag
/// to `工作`. Every site asks `TagSupport.slugIsTaken`; the two Mac edit views and the Mac title
/// field are private view state, so those three are read from source.
@MainActor
struct TagRenameClashStableSlugTests {
    private func legacyWork() -> Cadence.Tag {
        let tag = Cadence.Tag(name: "工作")
        tag.slug = "tag"
        return tag
    }

    @Test func aLegacyRowBlocksTheNameItStillResolvesTo() {
        let legacy = legacyWork()
        let other = Cadence.Tag(name: "home")
        let all = [legacy, other]
        let slug = TagSupport.slug(for: "工作")
        #expect(slug != "tag", "non-vacuity: the name's own slug is not the stored fallback")
        #expect(TagSupport.slugIsTaken(slug, in: all, except: other))
        #expect(!TagSupport.slugIsTaken(slug, in: all, except: legacy), "a tag never clashes with itself")
        #expect(TagSupport.slugIsTaken(slug, in: all), "the title field's inline create")
        #expect(!TagSupport.slugIsTaken(TagSupport.slug(for: "学习"), in: all))
    }

    @Test func theIOSEditCardRefusesTheLegacyName() {
        let legacy = legacyWork()
        let other = Cadence.Tag(name: "home")
        let all = [legacy, other]
        #expect(iOSTagSettingsEdit.hasDuplicate(name: "工作", tag: other, allTags: all))
        #expect(!iOSTagSettingsEdit.canSave(name: "工作", tag: other, allTags: all))
        #expect(iOSTagSettingsEdit.canSave(name: "学习", tag: other, allTags: all))
    }

    /// The file with comments blanked and whitespace squeezed out. `SettingsTagsSection` declares
    /// `hasDuplicateSlug` twice (the create card's reads `creationDecision`), so each needle names
    /// the whole one-line declaration rather than its first occurrence.
    private static func squeezed(_ file: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(file))
        return String(source.filter { !$0.isWhitespace })
    }

    @Test func theMacSettingsEditRowAsksTheStableSlug() throws {
        let source = try Self.squeezed("Cadence/macOS/Views/SettingsTagsSection.swift")
        #expect(source.contains("privatevarhasDuplicateSlug:Bool{TagSupport.slugIsTaken(draftSlug,in:allTags,except:tag)}"))
        #expect(!source.contains("$0.slug==draftSlug"))
    }

    @Test func theMacPickerEditSheetAsksTheStableSlug() throws {
        let source = try Self.squeezed("Cadence/macOS/Views/TagPickerPopoverViews.swift")
        #expect(source.contains("privatevarhasDuplicateSlug:Bool{TagSupport.slugIsTaken(normalizedSlug,in:allTags,except:tag)}"))
        #expect(!source.contains("$0.slug==normalizedSlug"))
    }

    /// [[T-15801]]: a rename to a name with no letter or digit is refused, as Create Tag refuses
    /// it (`creationDecision` answers `.unusableName`); an unchanged name still saves.
    @Test func aRenameToANameWithNoAlphanumericIsRefused() {
        let work = Cadence.Tag(name: "Work")
        let all = [work, Cadence.Tag(name: "home")]
        for name in ["--", "!!", " #-# ", "…"] {
            #expect(TagSupport.creationDecision(for: name, in: all).isCreatable == false, "non-vacuity: create refuses \(name)")
            #expect(!TagSupport.canRename(work, to: name, in: all), "rename refuses \(name)")
            #expect(!iOSTagSettingsEdit.canSave(name: name, tag: work, allTags: all), "iOS card refuses \(name)")
        }
        #expect(TagSupport.canRename(work, to: "Job", in: all))
        #expect(TagSupport.canRename(work, to: "学习", in: all))
        #expect(!TagSupport.canRename(work, to: "Home", in: all), "the clash clause is kept")

        let legacy = Cadence.Tag(name: "--")
        #expect(TagSupport.canRename(legacy, to: "--", in: [legacy]), "an unchanged name is not a rename")
        #expect(TagSupport.canRename(legacy, to: "Errands", in: [legacy]))
    }

    @Test func bothMacEditorsSaveThroughTheSharedRenameRule() throws {
        let row = try Self.squeezed("Cadence/macOS/Views/SettingsTagsSection.swift")
        #expect(row.contains("privatevarcanSave:Bool{TagSupport.canRename(tag,to:draftName,in:allTags)}"))
        let sheet = try Self.squeezed("Cadence/macOS/Views/TagPickerPopoverViews.swift")
        #expect(sheet.contains("privatevarcanSave:Bool{TagSupport.canRename(tag,to:name,in:allTags)}"))
    }

    @Test func theMacTitleFieldInlineCreateAsksTheStableSlug() throws {
        let source = try Self.squeezed("Cadence/macOS/Views/TaskTitleEntryField.swift")
        // [[T-16583]]: it reads `pickerQuery`, whose `creationDecision` compares `stableSlug`.
        #expect(source.contains("privatevarcanCreateInlineTag:Bool{tagQuery.canCreate}"))
        #expect(source.contains("TagSupport.pickerQuery(tagSearchQuery,in:allTags)"))
        #expect(!source.contains("$0.slug==slug"))
    }
}
