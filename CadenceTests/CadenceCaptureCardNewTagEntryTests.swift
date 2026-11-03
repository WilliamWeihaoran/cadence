import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-10028]]: the capture card's "New tag" field types and submits like every other tag-name
/// field on iOS.**
///
/// The card is what iOS's New Task sheet draws (`iOSCreateTaskSheet` -> `.capturePresentation`).
/// Its Tags editor ended in a bare `TextField("New tag", ...)` beside an Add button: Return only
/// dropped the keyboard and left the name sitting in the field, and the keyboard capitalised and
/// autocorrected the name. The task sheet's own tag picker (`iOSTaskTagPickerPopover`) and both
/// Settings tag fields submit on Return and type the name as written, so the same act behaved two
/// ways inside one app on one device.
///
/// The card is a SwiftUI view whose iOS-only modifier sits under `#if os(iOS)`, which this
/// macOS-built target cannot render, so the field's chain is pinned from source; the blank-name
/// rule both doors share is a value and is asserted directly.
struct CadenceCaptureCardNewTagEntryTests {

    private static let cardPath = "Cadence/Shared/Components/CadenceScheduleCaptureCard.swift"

    /// **Behavioural.** One rule for "is there a name to add": trimmed, and nothing for blank.
    @Test func captureTagEntryTrimsAndRefusesABlankName() {
        #expect(CadenceCaptureTagEntry.submittableName("") == nil)
        #expect(CadenceCaptureTagEntry.submittableName("   ") == nil)
        #expect(CadenceCaptureTagEntry.submittableName(" \n\t ") == nil)
        #expect(CadenceCaptureTagEntry.submittableName("  urgent \n") == "urgent")
        #expect(CadenceCaptureTagEntry.submittableName("deep work") == "deep work")
    }

    /// The "New tag" field's own modifier chain, up to the Add button beside it.
    private func newTagFieldChain() throws -> String {
        let card = try CadenceCommitSurfaceScan.scanned(Self.cardPath)
        let start = try #require(card.range(of: "TextField(\"New tag\""), "the New tag field is gone")
        let end = try #require(
            card.range(of: "Button(\"Add\"", range: start.upperBound..<card.endIndex),
            "no Add button follows the New tag field"
        )
        let chain = String(card[start.lowerBound..<end.lowerBound])
        #expect(chain.count < 600, "the slice ran past the field: \(chain.count) characters")
        return chain
    }

    /// **Source shape.** Return adds the tag, and the keyboard leaves the name alone.
    @Test func captureNewTagFieldSubmitsOnReturnWithoutAutocapitalising() throws {
        let chain = try newTagFieldChain()
        #expect(chain.contains(".onSubmit(addNewTag)"), "Return in the New tag field does nothing")
        #expect(chain.contains(".autocorrectionDisabled()"), "autocorrect can rewrite a typed tag name")
        #expect(
            chain.contains(".textInputAutocapitalization(.never)"),
            "the keyboard capitalises the first letter of a new tag"
        )
    }

    /// **Source shape.** The button and Return are one path, and that path holds the blank-name
    /// guard the button's greyed state promises.
    @Test func captureAddButtonAndReturnShareOneGuardedTagPath() throws {
        let card = try CadenceCommitSurfaceScan.scanned(Self.cardPath)
        #expect(card.contains("Button(\"Add\", action: addNewTag)"))
        #expect(card.contains(".disabled(CadenceCaptureTagEntry.submittableName(newTagName) == nil)"))

        let body = try CadenceCommitSurfaceScan.declarationBody(named: "addNewTag", in: card)
        let guardRange = try #require(body.range(of: "CadenceCaptureTagEntry.submittableName(newTagName)"))
        let call = try #require(body.range(of: "createTag(name)"), "addNewTag does not hand on the trimmed name")
        #expect(guardRange.lowerBound < call.lowerBound, "the tag is created before the blank-name guard")
    }

    // MARK: - [[T-10029]]: one heading, one Clear, one Done per estimate panel

    /// **Behavioural.** The panel keeps its Done everywhere unless a caller opts out, so no other
    /// estimate popover in the app loses its only way to close.
    @MainActor
    @Test func estimatePanelDrawsItsDoneUnlessACallerOptsOut() {
        #expect(EstimatePickerPopoverContent(value: .constant(0)).showsDone)
        #expect(EstimatePickerPopoverContent(value: 0, onCommit: { _ in true }).showsDone)
        #expect(!EstimatePickerPopoverContent(value: .constant(0), showsDone: false).showsDone)
    }

    /// **Source shape.** The footer's Done is drawn only behind `showsDone`.
    @Test func estimatePanelFooterGatesItsDoneOnShowsDone() throws {
        let picker = try CadenceCommitSurfaceScan.scanned("Cadence/Shared/Components/EstimatePickerControl.swift")
        let start = try #require(picker.range(of: "private var footer: some View {"), "the footer is gone")
        let end = try #require(
            picker.range(of: "private func doneButton(", range: start.upperBound..<picker.endIndex),
            "no doneButton follows the footer"
        )
        let footer = String(picker[start.upperBound..<end.lowerBound])
        #expect(footer.contains("Text(\"Clear\")"), "the slice is not the footer")
        #expect(footer.contains("if showsDone {\n                    doneButton(plateHeight: plateHeight)"))
        #expect(!footer.contains("Text(\"Done\")"), "the footer draws a Done outside the showsDone gate")
        #expect(picker.components(separatedBy: "Text(\"Done\")").count - 1 == 1)
    }

    /// **Source shape.** The capture card's Do editor embeds the panel without its Done and without
    /// a second "Estimate" heading over the panel's eyebrow, and the Estimate editor draws no second
    /// Clear under the panel's own.
    @Test func captureCardEstimateEditorsDrawOneHeadingOneClearOneDone() throws {
        let card = try CadenceCommitSurfaceScan.scanned(Self.cardPath)
        #expect(card.contains(
            "EstimatePickerPopoverContent(value: estimateBinding, showsDone: false)"
        ), "the Do editor's embedded panel draws a Done with nothing to close")
        #expect(!card.contains("onClose: {})"), "an estimate panel is handed a close that does nothing")
        #expect(!card.contains("Text(CadenceCaptureField.estimate.title)"),
                "the Do editor heads the panel's ESTIMATE eyebrow with a second Estimate")
        #expect(card.contains("field != .calendar, field != .estimate,"),
                "the Estimate editor draws Clear Estimate under the panel's own Clear")
        // The standalone Estimate editor still closes from its panel.
        #expect(card.contains("value: estimateBinding, onClose: { activeField = nil }"))
    }

    // MARK: - [[T-10060]]: Return in the capture card's time rollers closes the panel

    /// **Source shape.** `CadenceTimeRoller` answers Return with `.handled` and calls `onSubmit`,
    /// so a roller handed `{}` swallows the key and does nothing. The schedule panel's Do time row,
    /// `CadenceTimeRollerFieldRow` and the Mac Kanban card each close on Return; the capture card's
    /// two rollers (the Do start and an event's End) were the only ones handed an empty closure.
    @Test func captureCardTimeRollersCloseThePanelOnReturn() throws {
        let card = try CadenceCommitSurfaceScan.scanned(Self.cardPath)
        let lines = card.components(separatedBy: "\n").filter { $0.contains("CadenceTimeRoller(minutes:") }
        #expect(lines.count == 2, "expected the Do start and event End rollers, found \(lines.count)")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            #expect(trimmed.hasSuffix("{ activeField = nil }"), "a capture-card roller ignores Return: \(trimmed)")
            #expect(!trimmed.hasSuffix("{}"), "a capture-card roller swallows Return: \(trimmed)")
        }
    }

    /// **Source shape.** The Location panel's one field closes the panel on Return too; it had no
    /// submit at all, so Return on a hardware keyboard left the panel open over a typed place.
    @Test func captureCardLocationFieldClosesThePanelOnReturn() throws {
        let card = try CadenceCommitSurfaceScan.scanned(Self.cardPath)
        let start = try #require(card.range(of: "TextField(\"Location\""), "the Location field is gone")
        let end = try #require(
            card.range(of: "private var customRepeat", range: start.upperBound..<card.endIndex),
            "customRepeat no longer follows the Location field"
        )
        let chain = String(card[start.lowerBound..<end.lowerBound])
        // Counted over CODE, not over the raw slice ([[T-10121]]). `scanned` blanks comments to
        // spaces of equal width rather than deleting them, so this length also measured whatever
        // doc comment happened to sit between the Location field and the next declaration — and a
        // paragraph added above `customRepeat` took the slice from ~150 to 1596 characters without
        // a line of code moving. Dropping whitespace measures the thing the guard is actually for:
        // that the slice did not run past the field's own modifier chain.
        let code = chain.filter { !$0.isWhitespace }
        #expect(code.count < 400, "the slice ran past the field: \(code.count) code characters")
        #expect(chain.contains(".onSubmit { activeField = nil }"), "Return in the Location field does nothing")
    }
}
