import SwiftUI

/// The checklist / tag glyphs a task row draws — after the title on macOS, beneath the notes
/// preview on iOS (T-2058, the iOS position from [[T-3196]]).
///
/// One component, both platforms, for the reason `CadenceTaskRowIndicator`'s doc comment gives: the
/// questions are facts about an `AppTask`, and only the row around them is per-platform.
///
/// **There were three glyphs until [[T-3231]].** The `note.text` reading came off both rows at
/// once, because both rows now print the notes themselves — iOS always did, and macOS gained the
/// excerpt in [[T-1467]]. Nothing here changed to do it: the strip draws whatever
/// `CadenceTaskRowIndicator.allCases` holds, so dropping the case dropped the glyph on both
/// platforms in one edit, which is also why neither could drift away from the other.
///
/// **It is never in macOS's shedding metadata strip, and that is the design.** That
/// `metadataStrip` is a
/// `ViewThatFits` that sheds chips as the window narrows — which is right for chips that restate
/// information the row gives elsewhere, and wrong for these: a glyph that comes and goes with the
/// window width is worse than no glyph, because the row then says a different thing about the same
/// task depending on how wide the pane is. Two glyphs are a constant 31pt (three were 48pt before
/// [[T-3231]]); the three tag chips they replaced were ~150pt of name-length-dependent width, so
/// the title has *more* room than it did, not less.
///
/// **Colour is reserved for the exceptional.** Everything here is `Theme.dim`, which is the
/// standing row rule and is also what the owner's reference shot shows — the only coloured things
/// on a row are an overdue deadline, a do date already past, and a task actively In Progress.
///
/// **Fixed point size, deliberately.** The row surfaces do not declare
/// `.cadenceScaledTypography()` — `CadenceTagChipScaleTests` pins `iOSTaskDetailComponents` as the
/// one tag surface that does — so these glyphs render exactly as the chips they replace did, and
/// `maximumIntrinsicWidth` below stays a figure a test can read rather than a claim.
struct CadenceTaskRowIndicatorStrip: View {
    let indicators: [CadenceTaskRowIndicator]

    init(indicators: [CadenceTaskRowIndicator]) {
        self.indicators = indicators
    }

    init(task: AppTask) {
        self.init(indicators: CadenceTaskRowIndicatorSupport.indicators(for: task))
    }

    /// `secondaryFontSize` on both `CadenceTaskRowMetrics.desktop` and `.compact`, so the glyphs
    /// read as the same weight of chrome as the date chips beside them.
    static let glyphPointSize: CGFloat = 11

    /// Each glyph takes a fixed box rather than its own symbol width. `checklist` is wider than
    /// `tag`, so natural widths would make the strip's total depend on *which* indicators a task
    /// earned — and `maximumIntrinsicWidth` would then be an estimate. That is still true of the
    /// two that remain, and is why [[T-3231]] shrank the total without touching this figure.
    static let glyphWidth: CGFloat = 14

    static let spacing: CGFloat = 3

    /// The widest this component can ever be: every indicator lit. Published so
    /// `CadenceTaskRowIndicatorTests` can hold the title's share of its own row against a number
    /// instead of against an assurance (T-1720).
    static var maximumIntrinsicWidth: CGFloat {
        let count = CGFloat(CadenceTaskRowIndicator.allCases.count)
        return count * glyphWidth + max(0, count - 1) * spacing
    }

    var body: some View {
        if !indicators.isEmpty {
            HStack(spacing: Self.spacing) {
                ForEach(indicators, id: \.self) { indicator in
                    Image(systemName: indicator.symbolName)
                        .font(.system(size: Self.glyphPointSize))
                        .foregroundStyle(Theme.dim)
                        .frame(width: Self.glyphWidth)
                }
            }
            // Default layout priority, under the title's `.layoutPriority(1)`: the title is the
            // only part of a row that identifies its task, so it is laid out first and this takes
            // what it needs out of what is left. `fixedSize` horizontally because 31pt is the whole
            // of what it needs — there is no "narrower" rendering of two glyphs worth having.
            .fixedSize(horizontal: true, vertical: false)
            // One element, however many glyphs. Bare `Image`s are one stop each that a screen
            // reader lands on and reads nothing at; `CadenceSidebarLayout.rowAccessibilityLabel`
            // folds its phrases the same way, with the same `", "`.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CadenceTaskRowIndicatorSupport.accessibilityLabel(for: indicators) ?? "")
        }
    }
}
