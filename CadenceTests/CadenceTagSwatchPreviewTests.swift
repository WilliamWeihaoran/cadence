import Testing
@testable import Cadence

/// T-4113 (b): a half-typed Hex draft must preview as the colour the save would keep, never as
/// `Color(hex:)`'s black. iOS's `iOSSettingsColorSwatchRow` resolves its trailing "current colour"
/// swatch through these two helpers; macOS's edit row already resolved its dot through
/// `normalizedColorHex(_:fallback:)` and has no trailing swatch.
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
}
