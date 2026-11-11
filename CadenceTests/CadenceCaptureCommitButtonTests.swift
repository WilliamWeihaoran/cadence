import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-16042]]: the capture card's Add button looks disabled when it is.**
///
/// The card paints `Theme.text` from its root and wears `.cadencePlain`, which never reads
/// `isEnabled`, so `.disabled` alone left the Add arrow the same white with an empty title, a
/// marker-only title, or an event with no calendar -- identical pixels on the Mac while the AX
/// state flipped underneath. The tint is now chosen from the same gate `.disabled` reads. The card
/// is shared by the Mac composer and iOS's New Task sheet, so one fix covers both.
@MainActor
@Suite("Capture card commit button")
struct CadenceCaptureCommitButtonTests {

    private static let cardPath = "Cadence/Shared/Components/CadenceScheduleCaptureCard.swift"

    private func draft(_ title: String, kind: CadenceScheduleDraftKind = .task) -> CadenceScheduleDraft {
        var draft = CadenceScheduleDraft(dateKey: "2026-11-10", startMin: 9 * 60, kind: kind)
        draft.title = title
        return draft
    }

    /// **Behavioural.** A disabled button is drawn in the app's disabled stop, an enabled one is not.
    @Test("A disabled commit button is tinted dim, an enabled one is not")
    func disabledCommitButtonIsTintedDim() {
        #expect(CadenceCaptureCommitButton.tint(isEnabled: false) == Theme.dim)
        #expect(CadenceCaptureCommitButton.tint(isEnabled: true) == Theme.text)
        #expect(
            CadenceCaptureCommitButton.tint(isEnabled: false) != CadenceCaptureCommitButton.tint(isEnabled: true),
            "the enabled and disabled Add buttons draw the same colour"
        )
    }

    /// **Behavioural.** The three sighted dead states are disabled, and a real title is not.
    @Test("Empty, marker-only and calendar-less drafts disable the commit button")
    func sightedDeadStatesAreDisabled() {
        #expect(!CadenceCaptureCommitButton.isEnabled(canCommit: true, draft: draft("")), "empty title")
        #expect(!CadenceCaptureCommitButton.isEnabled(canCommit: true, draft: draft("!!!")), "marker-only title")
        #expect(
            !CadenceCaptureCommitButton.isEnabled(canCommit: false, draft: draft("Standup", kind: .event)),
            "an event the host cannot write"
        )
        #expect(CadenceCaptureCommitButton.isEnabled(canCommit: true, draft: draft("Sight composer one")))
    }

    /// **Source shape.** The button's tint and its `.disabled` read one value, so the two cannot
    /// drift apart again.
    @Test("The commit button's tint and disabled state read one value")
    func tintAndDisabledReadOneValue() throws {
        let card = try CadenceCommitSurfaceScan.scanned(Self.cardPath)
        #expect(card.contains("let commitEnabled = CadenceCaptureCommitButton.isEnabled(canCommit: canCommit, draft: draft)"))
        #expect(card.contains(".foregroundStyle(CadenceCaptureCommitButton.tint(isEnabled: commitEnabled))"))
        #expect(card.contains(".disabled(!commitEnabled)"))
    }

    /// **[[T-16071]], source shape.** On a read-only card the `capture-set-*` icon buttons and the
    /// `capture-more` menu are `.disabled(isReadOnly)`; their tint reads the same value, so they
    /// draw `Theme.dim` instead of the card's live `Theme.text`.
    @Test("Read-only set-field buttons and the More menu are tinted from isReadOnly")
    func readOnlySetFieldControlsAreTintedDim() throws {
        let card = try CadenceCommitSurfaceScan.scanned(Self.cardPath)
        let tint = ".foregroundStyle(CadenceCaptureCommitButton.tint(isEnabled: !isReadOnly))"
        func block(after anchor: String, until end: String) -> String? {
            guard let start = card.range(of: anchor),
                  let stop = card.range(of: end, range: start.upperBound..<card.endIndex) else { return nil }
            return String(card[start.lowerBound..<stop.upperBound])
        }
        let setButton = try #require(
            block(after: ".accessibilityIdentifier(\"capture-set-", until: ".disabled(isReadOnly)"),
            "the capture-set-* button no longer ends in .disabled(isReadOnly)"
        )
        #expect(setButton.contains(tint), "the set-field buttons draw Theme.text while disabled")
        let moreMenu = try #require(
            block(after: "Image(systemName: \"ellipsis\")", until: ".accessibilityIdentifier(\"capture-more\")"),
            "the capture-more menu label moved"
        )
        #expect(moreMenu.contains(tint), "the More menu draws Theme.text while disabled")
    }
}
