#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-7259]]: a saved link can be edited -- title and URL -- through the Links tab's own add
/// form, reopened prefilled, on both platforms. Until then a typo in a URL could only be fixed by
/// deleting and re-adding the link, which also sent it to the bottom of the list.
///
/// Store assertions are fetches from a second context on the same container, so "saved" means
/// committed rather than pending in the app's single `ModelContext`.
@MainActor
struct CadenceSavedLinkEditTests {
    private struct Refused: Error {}

    private func seeded(title: String = "Spec", url: String = "https://example.com/spec") throws
        -> (container: ModelContainer, context: ModelContext, link: SavedLink) {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let area = Area(name: "Links area")
        let link = SavedLink(title: title, url: url)
        link.area = area
        link.order = 3
        context.insert(area)
        context.insert(link)
        try context.save()
        return (container, context, link)
    }

    private func stored(_ id: UUID, in container: ModelContainer) throws -> SavedLink? {
        try ModelContext(container).fetch(FetchDescriptor<SavedLink>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - The form

    @Test func editingOpensTheFormPrefilledAndCancelForgetsTheLink() {
        let id = UUID()
        var form = SavedLinkAddForm()
        form.beginEditing(id: id, title: "Spec", url: "https://example.com/spec")
        #expect(form.isOpen)
        #expect(form.isEditing)
        #expect(form.editingLinkID == id)
        #expect(form.title == "Spec")
        #expect(form.url == "https://example.com/spec")
        #expect(form.headerTitle == "Cancel")
        #expect(form.headerLabel == "Cancel editing this link")

        form.cancel()
        #expect(form == SavedLinkAddForm(), "a cancelled edit left state behind")

        // The header's close is the same cancel, so a later "Add Link" adds rather than edits.
        form.beginEditing(id: id, title: "Spec", url: "https://example.com/spec")
        #expect(form.toggle() == true)
        #expect(!form.isEditing)
        form.toggle()
        #expect(form.isOpen && !form.isEditing && form.title.isEmpty && form.url.isEmpty)
    }

    /// A title that is only the URL fallback ([[T-509]]) opens blank, so correcting the URL
    /// re-derives the title instead of keeping the typo as one.
    @Test func aFallbackTitleOpensBlank() {
        var form = SavedLinkAddForm()
        form.beginEditing(id: UUID(), title: "https://exmaple.com", url: "https://exmaple.com")
        #expect(form.title.isEmpty)
        #expect(form.url == "https://exmaple.com")
    }

    // MARK: - The write

    @Test func anEditCommitsTheNormalisedTitleAndURLAndKeepsThePosition() throws {
        let seed = try seeded()
        let landed = try CadenceSavedLinkPersistence.update(
            seed.link,
            typedTitle: "  Spec v2  ",
            typedURL: " HTTPS://example.com/spec-v2 ",
            in: seed.context
        )
        #expect(landed)
        let row = try #require(try stored(seed.link.id, in: seed.container))
        #expect(row.title == "Spec v2")
        #expect(row.url == "HTTPS://example.com/spec-v2", "the edit skipped the add path's URL rule")
        #expect(row.order == 3, "an edit moved the link, which is what delete-and-re-add did")

        // A blank title falls back to the URL, as a new link's does.
        #expect(try CadenceSavedLinkPersistence.update(seed.link, typedTitle: "  ", typedURL: "example.com", in: seed.context))
        let fallback = try #require(try stored(seed.link.id, in: seed.container))
        #expect(fallback.url == "https://example.com")
        #expect(fallback.title == "https://example.com")
    }

    @Test func aBlankURLWritesNothing() throws {
        let seed = try seeded()
        let landed = try CadenceSavedLinkPersistence.update(seed.link, typedTitle: "New", typedURL: "   ", in: seed.context)
        #expect(!landed)
        #expect(seed.link.title == "Spec")
        #expect(seed.link.url == "https://example.com/spec")
        #expect(!seed.context.hasChanges)
    }

    @Test func aRefusedEditPutsBothFieldsBack() throws {
        let seed = try seeded()
        #expect(throws: Refused.self) {
            try CadenceSavedLinkPersistence.update(
                seed.link,
                typedTitle: "New",
                typedURL: "https://example.com/new",
                in: seed.context,
                commit: { _ in throw Refused() }
            )
        }
        #expect(seed.link.title == "Spec", "a refused edit left the new title on screen")
        #expect(seed.link.url == "https://example.com/spec", "a refused edit left the new URL on screen")
    }

    // MARK: - The form's Save, shared by both tabs

    @Test func theEditSaveClosesOnSuccessAndStaysOpenOnARefusal() throws {
        let seed = try seeded()
        var form = SavedLinkAddForm()
        form.beginEditing(id: seed.link.id, title: seed.link.title, url: seed.link.url)
        form.url = "https://example.com/fixed"

        let refused = CadenceSavedLinkPersistence.saveEdit(
            &form, among: [seed.link], in: seed.context, commit: { _ in throw Refused() }
        )
        #expect(refused == CadenceSavedLinkPersistence.saveFailureNotice)
        #expect(form.isEditing, "a refused edit closed the form over what was typed")
        #expect(form.url == "https://example.com/fixed")
        #expect(seed.link.url == "https://example.com/spec")

        let landed = CadenceSavedLinkPersistence.saveEdit(&form, among: [seed.link], in: seed.context)
        #expect(landed == nil)
        #expect(form == SavedLinkAddForm(), "a landed edit left the form open")
        #expect(try stored(seed.link.id, in: seed.container)?.url == "https://example.com/fixed")
    }

    /// A link gone while the form was open closes the form and inserts nothing.
    @Test func anEditOfALinkThatIsGoneClosesTheFormAndInsertsNothing() throws {
        let seed = try seeded()
        var form = SavedLinkAddForm()
        form.beginEditing(id: UUID(), title: "Ghost", url: "https://example.com/ghost")
        #expect(CadenceSavedLinkPersistence.saveEdit(&form, among: [seed.link], in: seed.context) == nil)
        #expect(!form.isOpen)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<SavedLink>()) == 1)
        #expect(seed.link.url == "https://example.com/spec")
    }

    // MARK: - Both tabs reach it

    /// Source shape, because this target does not compile `Cadence/iOS/` and the two views'
    /// functions are private. What they reach is pinned behaviourally above.
    @Test func bothLinksTabsOfferEditAndSaveThroughTheSharedForm() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        )
        let ios = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListSupportViews.swift")
        )
        let view = try #require(CadenceSourceScan.declarationBody("struct LinksView: View", in: mac))
        let panel = try #require(CadenceSourceScan.declarationBody("struct iOSListLinksPanel: View", in: ios))

        for (name, body) in [("LinksView", view), ("iOSListLinksPanel", panel)] {
            let save = try #require(CadenceSourceScan.functionBody(named: "saveForm", in: body), "\(name) has no saveForm()")
            #expect(save.contains("actionError = CadenceSavedLinkPersistence.saveEdit(&addForm, among: links, in: modelContext)"),
                    "\(name)'s Save does not route an edit through the shared helper")
            #expect(save.contains("addLink()"), "\(name)'s Save no longer adds")
            #expect(body.contains("addForm.beginEditing(id: link.id, title: link.title, url: link.url)"),
                    "\(name) has no way to open the form on a link")
        }
        #expect(view.contains("onSave: { saveForm() }"))
        #expect(panel.contains("save: saveForm"))

        // The Mac row: a menu item and a named accessibility action, both the row's `onEdit`.
        let row = try #require(CadenceSourceScan.declarationBody("private struct LinkRow: View", in: mac))
        let menu = try #require(CadenceSourceScan.declarationBody(".contextMenu", in: row))
        #expect(menu.contains("Button(action: onEdit)"))
        #expect(row.contains(".accessibilityAction(named: MacSavedLinkRowActions.editActionName, onEdit)"))
        #expect(MacSavedLinkRowActions.editMenuTitle == CadenceSavedLinkRowMenu.editTitle)

        // iOS: the long-press menu and the swipe both open the form.
        let iosMenu = try #require(CadenceSourceScan.declarationBody(".contextMenu", in: panel))
        #expect(iosMenu.contains("beginEditing(link)"))
        let swipe = try #require(CadenceSourceScan.declarationBody(".swipeActions(edge: .trailing, allowsFullSwipe: false)", in: panel))
        #expect(swipe.contains("beginEditing(link)"), "the iOS swipe offers no Edit")
        #expect(CadenceSavedLinkRowMenu.editTitle == "Edit Link")
    }

    // MARK: - Both rows draw the same title

    /// [[T-12793]]: the Mac row drew `link.title` raw while iOS's drew it through
    /// `CadenceTitleNormalization.display(_:fallback:)`, so a blank title written outside the add
    /// form was an empty row on the Mac and the URL on iOS ([[T-8201]]). Source shape, because
    /// both rows are private views; the helper's answer for that title is pinned alongside.
    @Test func bothLinkRowsDrawABlankTitleAsTheURL() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        )
        let ios = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListSupportViews.swift")
        )
        let macRow = try #require(CadenceSourceScan.declarationBody("private struct LinkRow: View", in: mac))
        let iosRow = try #require(CadenceSourceScan.declarationBody("private struct iOSLinkRow: View", in: ios))
        let spelling = "Text(CadenceTitleNormalization.display(link.title, fallback: link.url))"
        for (name, row) in [("LinkRow", macRow), ("iOSLinkRow", iosRow)] {
            #expect(row.contains(spelling), "\(name) does not draw its title through display(_:fallback:)")
            #expect(!row.contains("Text(link.title)"), "\(name) still draws the raw title")
        }
        #expect(CadenceTitleNormalization.display("  \n", fallback: "https://example.com") == "https://example.com")
        #expect(CadenceTitleNormalization.display(" Spec ", fallback: "https://example.com") == "Spec")
    }

    /// [[T-17125]]: both rows draw their URL line through the one rule that drops it when it repeats
    /// the title line; neither draws `link.url` unconditionally. The rule is pinned behaviourally in
    /// `CadenceSavedLinkPersistenceTests.aLinkRowDrawsItsURLLineOnlyWhenItDiffersFromTheTitleLine`.
    @Test func bothLinkRowsDropAURLLineThatRepeatsTheTitle() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        )
        let ios = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListSupportViews.swift")
        )
        let macRow = try #require(CadenceSourceScan.declarationBody("private struct LinkRow: View", in: mac))
        let iosRow = try #require(CadenceSourceScan.declarationBody("private struct iOSLinkRow: View", in: ios))
        for (name, row) in [("LinkRow", macRow), ("iOSLinkRow", iosRow)] {
            #expect(row.contains("if let detail = CadenceSavedLinkRowText.detail(title: link.title, url: link.url)"),
                    "\(name) does not draw its URL line through the shared rule")
            #expect(row.contains("Text(detail)"), "\(name) does not draw the line the rule returned")
            #expect(!row.contains("Text(link.url)"), "\(name) still draws the URL line unconditionally")
        }
    }
}
#endif
