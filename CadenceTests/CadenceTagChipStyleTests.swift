import Foundation
import Testing
@testable import Cadence

/// Pins the tag chip's state → appearance decision.
///
/// The chip is one component on both platforms, but the *reason* it is shared is that iOS was
/// silently missing three behaviours macOS had — the label width cap, the remove control, and any
/// rendering of `Tag.isArchived` at all. The first and the third are decided here, in
/// `CadenceTagChipStyle`, precisely so a call site cannot forget them; the second is a control the
/// chip draws itself. These tests are what stop any of the three drifting back out.
struct CadenceTagChipStyleTests {

    // MARK: Archived is a visible state, not a call-site convention

    /// **The bug this whole component exists to fix.** An archived tag drew identically to a live
    /// one on iPhone and iPad. Every channel the chip has must differ, so no single call site can
    /// flatten it back by overriding one of them.
    @Test func archivedChipDiffersFromLiveOnEveryChannel() {
        for size in CadenceTagChipSize.allCases {
            for input in CadenceTagChipInput.allCases {
                let live = CadenceTagChipStyle(size: size, isArchived: false, input: input)
                let archived = CadenceTagChipStyle(size: size, isArchived: true, input: input)

                #expect(live.usesTagColor)
                #expect(!archived.usesTagColor)
                #expect(archived.labelInk != live.labelInk)
                #expect(archived.fillOpacity != live.fillOpacity)
                #expect(archived.strokeOpacity != live.strokeOpacity)
                #expect(archived.chipOpacity < live.chipOpacity)
            }
        }
    }

    /// Archived wins over every selection state. The tag filter bar drives `selection`, and an
    /// archived tag that happened to be filtered on must still read as archived.
    @Test func archivedOverridesSelection() {
        for selection in CadenceTagChipSelection.allCases {
            let archived = CadenceTagChipStyle(selection: selection, isArchived: true)
            #expect(!archived.usesTagColor)
            #expect(archived.labelInk == .dimmed)
            #expect(archived.chipOpacity < 1)
        }
    }

    /// A live chip never dims its label, so "dimmed" stays unambiguous as the archived signal —
    /// except on a filter chip that is explicitly switched off, which is the one other thing
    /// "receded" can mean here.
    @Test func liveDisplayChipIsNotDimmed() {
        #expect(CadenceTagChipStyle(selection: .none, isArchived: false).labelInk == .muted)
        #expect(CadenceTagChipStyle(selection: .on, isArchived: false).labelInk == .emphasized)
        #expect(CadenceTagChipStyle(selection: .off, isArchived: false).labelInk == .dimmed)
    }

    // MARK: The truncation rule

    /// The cap exists so one long tag name cannot push a row's other metadata out of reach. Both
    /// sizes must have a finite one, and the dense size must be the tighter of the two.
    @Test func labelWidthIsCappedAndDenserSizeIsTighter() {
        let regular = CadenceTagChipStyle(size: .regular, isArchived: false)
        let compact = CadenceTagChipStyle(size: .compact, isArchived: false)

        #expect(regular.maximumLabelWidth.isFinite)
        #expect(compact.maximumLabelWidth.isFinite)
        #expect(compact.maximumLabelWidth < regular.maximumLabelWidth)
        #expect(compact.fontSize < regular.fontSize)
        #expect(compact.cornerRadius < regular.cornerRadius)
    }

    /// The cap does not depend on archived-ness or selection: chips in one strip have to line up.
    @Test func labelWidthDoesNotVaryWithState() {
        for size in CadenceTagChipSize.allCases {
            let widths = Set(
                CadenceTagChipSelection.allCases.flatMap { selection in
                    [true, false].map {
                        CadenceTagChipStyle(size: size, selection: selection, isArchived: $0).maximumLabelWidth
                    }
                }
            )
            #expect(widths.count == 1)
        }
    }

    // MARK: The remove control, and the platform difference that is deliberate

    /// A finger gets 44pt; a pointer gets the drawn control and nothing more. This is the one
    /// difference between the platforms that is kept on purpose rather than flattened.
    @Test func touchRemoveControlReaches44AndPointerDoesNotGrow() {
        for size in CadenceTagChipSize.allCases {
            let touch = CadenceTagChipStyle(size: size, isArchived: false, input: .touch)
            #expect(touch.removeHitTargetSize == 44)
            #expect(touch.removeControlSize + touch.removeHitInset * 2 == 44)
            #expect(touch.removeControlSize > CadenceTagChipStyle(size: size, isArchived: false, input: .pointer).removeControlSize)

            let pointer = CadenceTagChipStyle(size: size, isArchived: false, input: .pointer)
            #expect(pointer.removeHitInset == 0)
            #expect(pointer.removeHitTargetSize == pointer.removeControlSize)
        }
    }

    /// The hazard the expansion creates: a hit area grown past its chip reaches into the chip next
    /// to it, and an expanded filled shape eating a neighbour's tap is a failure this repo has
    /// shipped before. The strip spacing must cover the spill in both axes — the editable strips on
    /// both platforms read these numbers rather than picking their own.
    @Test func editableStripSpacingCoversTheHitAreaSpill() {
        for size in CadenceTagChipSize.allCases {
            for input in CadenceTagChipInput.allCases {
                let style = CadenceTagChipStyle(size: size, isArchived: false, input: input)
                let overhang = style.removeHitOverhang()

                let spacing = CadenceTagChipStyle.editableStripSpacing(for: size, input: input)
                let lineSpacing = CadenceTagChipStyle.editableStripLineSpacing(for: size, input: input)

                // Two adjacent chips each spill `overhang` toward each other.
                #expect(spacing >= overhang.horizontal * 2)
                #expect(lineSpacing >= overhang.vertical * 2)
                #expect(spacing > 0)
                #expect(lineSpacing > 0)
            }
        }
    }

    /// A pointer chip has no expansion at all, so it must not be paying for touch's clearance.
    @Test func pointerStripsAreNotSpacedForTouch() {
        for size in CadenceTagChipSize.allCases {
            #expect(
                CadenceTagChipStyle.editableStripLineSpacing(for: size, input: .pointer)
                    <= CadenceTagChipStyle.editableStripLineSpacing(for: size, input: .touch)
            )
        }
    }

    // MARK: The label itself

    /// `Tag.name` is free text and may be blank. iOS fell back to the slug and macOS did not, so an
    /// unnamed tag drew as a bare dot on one platform and a named chip on the other.
    @Test func blankNameFallsBackToSlugThenToAWord() {
        #expect(CadenceTagChipStyle.displayName(name: "bug", slug: "bug") == "bug")
        #expect(CadenceTagChipStyle.displayName(name: "  ", slug: "deep-work") == "deep-work")
        #expect(CadenceTagChipStyle.displayName(name: "", slug: "") == "tag")
        #expect(CadenceTagChipStyle.displayName(name: "  Deep Work  ", slug: "deep-work") == "Deep Work")
    }

    /// Dimming is invisible to VoiceOver, so archived has to be spoken as well as drawn.
    @Test func archivedIsSpokenNotOnlyDrawn() {
        #expect(CadenceTagChipStyle.accessibilityLabel(name: "bug", slug: "bug", isArchived: false) == "bug")
        #expect(CadenceTagChipStyle.accessibilityLabel(name: "bug", slug: "bug", isArchived: true) == "bug (archived)")
        #expect(CadenceTagChipStyle.accessibilityLabel(name: "", slug: "old-tag", isArchived: true) == "old-tag (archived)")
    }
}
