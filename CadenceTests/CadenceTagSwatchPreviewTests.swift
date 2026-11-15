import SwiftUI
import Testing
@testable import Cadence

/// T-4113 (b): a half-typed Hex draft must preview as the colour the save would keep, never as
/// `Color(hex:)`'s black. iOS's `iOSSettingsColorSwatchRow` resolves its trailing "current colour"
/// swatch through these two helpers, and since [[T-17936]] so does the Mac's `TagColorSwatches`,
/// whose ring had followed `normalizedColorHex`'s grey default instead.
struct CadenceTagSwatchPreviewTests {
    private let saved = "#6b7a99"

    @Test func anInvalidDraftPreviewsAsTheSavedColourNotTheRawDraft() {
        for junk in ["zz", "#12", "not a colour", "#1234567", "#ggg000"] {
            #expect(TagSupport.swatchPreviewHex(junk, fallback: saved) == saved)
            let strip = TagSupport.swatchStripOptions(TagSupport.colorOptions, draft: junk, fallback: saved)
            #expect(strip == TagSupport.colorOptions + [saved])
            #expect(!strip.contains(junk))
        }
    }

    @Test func aValidDraftPreviewsAsItselfNormalised() {
        #expect(TagSupport.swatchPreviewHex(" 00AAFF ", fallback: saved) == "#00aaff")
        #expect(TagSupport.swatchStripOptions(TagSupport.colorOptions, draft: "00AAFF", fallback: saved)
                == TagSupport.colorOptions + ["#00aaff"])
        // An offered colour is not appended a second time.
        #expect(TagSupport.swatchStripOptions(TagSupport.colorOptions, draft: "#FF6B6B", fallback: saved)
                == TagSupport.colorOptions)
    }

    @Test func withoutAFallbackTheStoredValueIsShownAsIs() {
        #expect(TagSupport.swatchStripOptions(["#111111"], draft: " #abcdef ", fallback: nil)
                == ["#111111", "#abcdef"])
        #expect(TagSupport.swatchStripOptions(["#111111"], draft: "  ", fallback: nil) == ["#111111"])
    }

    /// [[T-17936]]: the ring follows the preview, so a half-typed draft rings the saved colour
    /// rather than `normalizedColorHex`'s grey default (`#7b8492`, the eighth swatch).
    @Test func theRingFollowsThePreviewNotTheGreyDefault() {
        let grey = TagSupport.normalizedColorHex("")
        for junk in ["", "#1", "#12a"] {
            #expect(TagSupport.swatchIsSelected(saved, draft: junk, fallback: saved))
            #expect(!TagSupport.swatchIsSelected(grey, draft: junk, fallback: saved))
            // No Hex field, no saved colour: the default still rings, as before.
            #expect(TagSupport.swatchIsSelected(grey, draft: junk, fallback: nil))
        }
        #expect(TagSupport.swatchIsSelected("#FF6B6B", draft: "ff6b6b", fallback: saved))
    }

    #if os(macOS)
    /// [[T-17936]]: the Mac's `TagColorSwatches` (Settings > Tags and the picker's Edit Tag sheet)
    /// rang grey for an empty or half-typed `#hex` and rang nothing for a saved custom colour.
    @Test func theMacStripRingsTheSavedColourForAHalfTypedDraft() {
        let grey = TagSupport.normalizedColorHex("")
        for junk in ["", "#1", "#12a"] {
            let strip = TagColorSwatches(selectedHex: .constant(junk), fallbackHex: saved)
            #expect(strip.offered == TagSupport.colorOptions + [saved])
            #expect(strip.offered.filter(strip.rings) == [saved])
            #expect(!strip.rings(grey))
        }
        let offeredColour = TagColorSwatches(selectedHex: .constant("#12a"), fallbackHex: TagSupport.colorOptions[0])
        #expect(offeredColour.offered == TagSupport.colorOptions)
        #expect(offeredColour.offered.filter(offeredColour.rings) == [TagSupport.colorOptions[0]])

        // The create card has no Hex field and passes no fallback: it is unchanged.
        let create = TagColorSwatches(selectedHex: .constant(TagSupport.colorOptions[2]))
        #expect(create.offered == TagSupport.colorOptions)
        #expect(create.offered.filter(create.rings) == [TagSupport.colorOptions[2]])
    }
    #endif
}
