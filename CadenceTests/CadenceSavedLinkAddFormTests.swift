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
}
#endif
