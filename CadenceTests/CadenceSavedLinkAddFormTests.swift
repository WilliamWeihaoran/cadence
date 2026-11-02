#if os(macOS)
import Testing
@testable import Cadence

/// The Mac Links tab's add form (T-7256). Its header button is a second Cancel while the form is
/// open; it used to stay a "+" and only hide the form, so reopening brought back the abandoned
/// draft.
struct CadenceSavedLinkAddFormTests {
    @Test func theHeaderButtonClosesTheFormTheWayCancelDoes() {
        var viaHeader = SavedLinkAddForm()
        #expect(viaHeader.toggle() == false, "opening the form is not a cancel")
        #expect(viaHeader.isOpen)
        viaHeader.title = "Spec"
        viaHeader.url = "example.com/spec"

        var viaCancel = viaHeader
        viaCancel.cancel()

        #expect(viaHeader.toggle() == true, "closing from the header must clear the notice too")
        #expect(viaHeader == viaCancel)
        #expect(viaHeader == SavedLinkAddForm(), "the abandoned draft survived the header close")

        viaHeader.toggle()
        #expect(viaHeader.isOpen)
        #expect(viaHeader.title.isEmpty)
        #expect(viaHeader.url.isEmpty)
    }

    @Test func theHeaderButtonDrawsAndNamesWhatItDoes() {
        var form = SavedLinkAddForm()
        #expect(form.headerSymbol == "plus")
        #expect(form.headerLabel == "Add link")
        form.toggle()
        #expect(form.headerSymbol == "xmark")
        #expect(form.headerLabel == "Cancel adding a link")
    }

    /// [[T-10056]]: iOS's Links tab closes its add form through the same `SavedLinkAddForm` the
    /// Mac does. It kept three loose `@State`s, and its header "Cancel" only flipped the open flag, so
    /// reopening the form brought back the abandoned title and URL -- T-7256's defect, on iOS.
    /// Source shape, because this macOS target does not compile `Cadence/iOS/`; the behaviour the
    /// two calls reach is pinned by `theHeaderButtonClosesTheFormTheWayCancelDoes` above.
    @Test func theIOSLinksTabClosesItsFormThroughTheSharedFormState() throws {
        let ios = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListSupportViews.swift")
        )
        let panel = try #require(CadenceSourceScan.declarationBody("struct iOSListLinksPanel: View", in: ios))
        #expect(panel.contains("@State private var addForm = SavedLinkAddForm()"))
        #expect(
            CadenceSourceScan.matchCount(#"\bisAdding\b|\bnewTitle\b|\bnewURL\b"#, in: panel) == 0,
            "a second copy of the form state is back beside SavedLinkAddForm"
        )
        let header = try #require(CadenceSourceScan.declarationBody("withAnimation(.easeInOut(duration: 0.18))", in: panel))
        #expect(header.contains("addForm.toggle()"), "the header close no longer discards the draft")
        let add = try #require(CadenceSourceScan.functionBody(named: "addLink", in: panel))
        #expect(add.contains("addForm.cancel()"), "a successful save no longer clears the form")
    }

    /// [[T-10057]]: an iOS saved-link row answers a long-press with the Mac row's right-click menu
    /// (T-7258) -- Open Link, Copy Link, Delete, in that order, from the one shared set of words --
    /// and its Delete asks first, through the swipe's own `linkToDelete`.
    @Test func theIOSLinkRowLongPressOffersTheMacRowMenu() throws {
        let ios = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListSupportViews.swift")
        )
        let panel = try #require(CadenceSourceScan.declarationBody("struct iOSListLinksPanel: View", in: ios))
        let menu = try #require(CadenceSourceScan.declarationBody(".contextMenu", in: panel), "the iOS link row has no long-press menu")
        let titles = CadenceSourceScan.captures(#"Label\(CadenceSavedLinkRowMenu\.(\w+)"#, in: menu, group: 1).map(\.text)
        #expect(titles == ["openTitle", "copyTitle", "deleteTitle"], "measured: \(titles)")
        #expect(menu.contains("open(link)"))
        #expect(menu.contains("UIPasteboard.general.string = link.url"))
        #expect(menu.contains("linkToDelete = link"), "the menu's Delete must ask first, as the swipe does")
        #expect(!menu.contains("delete(link)"), "the menu's Delete skips the confirmation")

        #expect(MacSavedLinkRowActions.openMenuTitle == CadenceSavedLinkRowMenu.openTitle)
        #expect(MacSavedLinkRowActions.copyMenuTitle == CadenceSavedLinkRowMenu.copyTitle)
        #expect(MacSavedLinkRowActions.deleteMenuTitle == CadenceSavedLinkRowMenu.deleteTitle)
    }

    /// [[T-9972]]: the form's Save is the filled `.primary` commit beside a `.ghost` Cancel -- the
    /// pair every other Mac inline editor draws, and the role iOS's `iOSAddLinkForm` saves with.
    /// It was `.secondary`, so the one action the form exists for read as the lesser button.
    @Test func theAddFormCommitsWithThePrimaryButtonBesideAGhostCancel() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        )
        guard let bar = CadenceSourceScan.declarationBody("private struct AddLinkBar: View", in: mac) else {
            Issue.record("no AddLinkBar in LinksView.swift")
            return
        }
        let pattern = #"title:\s*"(\w+)",\s*role:\s*\.(\w+)"#
        let titles = CadenceSourceScan.captures(pattern, in: bar, group: 1).map(\.text)
        let roles = CadenceSourceScan.captures(pattern, in: bar, group: 2).map(\.text)
        #expect(titles == ["Cancel", "Save"], "measured: \(titles)")
        #expect(roles == ["ghost", "primary"], "measured: \(roles)")

        let ios = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListSupportViews.swift")
        )
        guard let form = CadenceSourceScan.declarationBody("private struct iOSAddLinkForm: View", in: ios) else {
            Issue.record("no iOSAddLinkForm in iOSListSupportViews.swift")
            return
        }
        #expect(form.contains("role: .primary"), "iOS's add-link commit is no longer .primary")
    }
}
#endif
