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
