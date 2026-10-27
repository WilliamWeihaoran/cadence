import Foundation
import Testing
@testable import Cadence

/// VoiceOver names that used to read as developer strings or name nothing.
///
/// - **T-7270.** Every icon picker passed the raw SF Symbol as its label, so VoiceOver said
///   "folder.fill". `CadenceIconPalette.accessibilityName(for:)` is the one table all four pickers
///   read; the value tests pin the words and the fallback, the scans pin that each picker reads it.
/// - **T-7294.** The AI draft approve/reject control named no draft ("Include this task" on the
///   Mac, "Approved, tap to reject" on iOS). The label now names the draft, the state is the value,
///   the outcome is the hint.
///
/// `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS, so the iOS half is read
/// as source text — comment-stripped, with a non-vacuity anchor per file.
struct CadenceVoiceOverNamingTests {

    // MARK: - T-7270: icon names

    @Test func everyOfferedIconHasAHumanName() {
        let palette = CadenceIconPalette.icons
        #expect(palette.count >= 40, "non-vacuity: the palette shrank to \(palette.count)")
        let unnamed = palette.filter { CadenceIconPalette.accessibilityNames[$0] == nil }
        #expect(unnamed.isEmpty, "offered icons with no spoken name: \(unnamed)")
        // A table entry for a symbol nobody offers is a word nobody hears.
        let orphaned = CadenceIconPalette.accessibilityNames.keys.filter { !palette.contains($0) }
        #expect(orphaned.isEmpty, "names for icons the palette no longer offers: \(orphaned)")
        for icon in palette {
            let name = CadenceIconPalette.accessibilityName(for: icon)
            #expect(!name.contains("."), "\(icon) reads as \(name)")
            #expect(name != icon, "\(icon) reads its own symbol name")
        }
    }

    @Test func theTicketsTwoExamplesReadAsWords() {
        #expect(CadenceIconPalette.accessibilityName(for: "folder.fill") == "Folder")
        #expect(CadenceIconPalette.accessibilityName(for: "graduationcap.fill") == "Graduation cap")
        #expect(CadenceIconPalette.accessibilityName(for: "square.stack.fill") == "Stack")
    }

    /// A stored symbol the palette no longer offers is still shown (`offeredIcons(for:)` appends it),
    /// so it still needs a name — spelled from its parts, never read raw.
    @Test func anUnmappedSymbolIsSpelledOutNeverReadRaw() {
        #expect(CadenceIconPalette.accessibilityNames["dollarsign.circle.fill"] == nil, "non-vacuity")
        #expect(CadenceIconPalette.accessibilityName(for: "dollarsign.circle.fill") == "Dollarsign")
        #expect(CadenceIconPalette.accessibilityName(for: "figure.run") == "Figure run")
        #expect(CadenceIconPalette.accessibilityName(for: "brain.head.profile") == "Brain head profile")
        #expect(CadenceIconPalette.accessibilityName(for: "person.3.fill") == "Person")
        #expect(CadenceIconPalette.accessibilityName(for: "") == "Icon")
        #expect(CadenceIconPalette.accessibilityName(for: "circle.fill") == "Icon")
        #expect(CadenceIconPalette.accessibilityName(for: " folder.fill ") == "Folder")
    }

    /// Each picker, by file, with the call that names its cells. A revert to the raw symbol — or to
    /// the Mac grid's old "Select \(icon) icon" — leaves the expected call missing or the raw one
    /// present.
    @Test func everyIconPickerSpeaksTheSharedName() throws {
        let pickers = [
            "Cadence/macOS/Sheets/ListEditorSupportViews.swift":
                "accessibilityLabel: CadenceIconPalette.accessibilityName(for: icon)",
            "Cadence/macOS/Sheets/CreateContextSheet.swift":
                ".cadenceControlLabel(CadenceIconPalette.accessibilityName(for: icon))",
            "Cadence/iOS/iOSListEditorViews.swift":
                ".accessibilityLabel(CadenceIconPalette.accessibilityName(for: icon))",
            "Cadence/iOS/iOSTrackingEditorComponents.swift":
                ".accessibilityLabel(CadenceIconPalette.accessibilityName(for: icon))",
        ]
        let raw = ["accessibilityLabel: icon\n", ".accessibilityLabel(icon)", #"Select \(icon) icon"#]
        for (path, call) in pickers {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("Image(systemName: icon)"), "non-vacuity: \(path) draws no icon cell")
            #expect(code.contains(call), "\(path) no longer names its icons through the shared table")
            for needle in raw {
                #expect(!code.contains(needle), "\(path) reads a raw symbol name: \(needle)")
            }
        }
    }

    // MARK: - T-7294: AI draft approval control

    @Test func theApprovalLabelNamesTheDraft() {
        #expect(CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: "Email Dana") == "Include Email Dana")
        #expect(CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: "  Email Dana\n") == "Include Email Dana")
        // Two drafts are two different names — the defect was five identical checkboxes.
        #expect(
            CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: "A")
                != CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: "B")
        )
    }

    @Test func aBlankTitleReadsAsAnUntitledDraft() {
        #expect(CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: "") == "Include untitled draft")
        #expect(CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: " \n ") == "Include untitled draft")
    }

    @Test func stateIsTheValueAndTheOutcomeIsTheHint() {
        #expect(CadenceAIDraftReview.approvalAccessibilityValue(isApproved: true) == "Included")
        #expect(CadenceAIDraftReview.approvalAccessibilityValue(isApproved: false) == "Not included")
        let on = CadenceAIDraftReview.approvalAccessibilityHint(isApproved: true)
        let off = CadenceAIDraftReview.approvalAccessibilityHint(isApproved: false)
        #expect(on != off)
        // T-521: a hint states an outcome, never a gesture.
        for hint in [on, off] {
            #expect(!hint.lowercased().contains("tap"), "\(hint)")
        }
        // The label carries neither the state nor the hint.
        let label = CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: "Approved")
        #expect(!label.lowercased().contains("tap"))
    }

    @Test func bothDraftCardsReadTheSharedNameValueAndHint() throws {
        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NoteActionReviewSheets.swift")
        )
        #expect(mac.contains("struct AITaskDraftRow"), "non-vacuity: the Mac row moved")
        #expect(mac.contains("Toggle(CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: draft.title), isOn: $isSelected)"))
        #expect(mac.contains(".accessibilityHint(CadenceAIDraftReview.approvalAccessibilityHint(isApproved: isSelected))"))
        #expect(!mac.contains(#"Toggle("Include this task""#))

        let iOS = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSAINoteActionsViews.swift")
        )
        #expect(iOS.contains("private var titleRow"), "non-vacuity: the iOS card moved")
        #expect(iOS.contains(".accessibilityLabel(CadenceAIDraftReview.approvalAccessibilityLabel(forTitle: draft.title))"))
        #expect(iOS.contains(".accessibilityValue(CadenceAIDraftReview.approvalAccessibilityValue(isApproved: isApproved))"))
        #expect(iOS.contains(".accessibilityHint(CadenceAIDraftReview.approvalAccessibilityHint(isApproved: isApproved))"))
        #expect(!iOS.contains("tap to reject"))
        #expect(!iOS.contains("tap to approve"))
    }
}
