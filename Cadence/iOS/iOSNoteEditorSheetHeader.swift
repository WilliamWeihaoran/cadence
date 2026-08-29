#if os(iOS)
import SwiftUI

/// The title block above a note editor's writing surface, in the one place both sheets read it.
///
/// `iOSEventNoteEditorSheet` and `iOSLinkedNoteEditorSheet` each spelled this out. `af03fb1` made
/// the two spellings identical and deferred the extraction until "a third near-copy appears", but
/// the reason it recorded — that the two sheets' surrounding chrome differs (toolbar items, AI
/// actions, calendar sync) — is about the chrome, not about this block. Two identical bodies is the
/// state the event sheet's header was already in once before, and it drifted: a 12pt hand-rolled
/// caption where the other used `SectionEyebrowLabel`, a title fixed at 24pt against the other's
/// `isRegularWidth ? 24 : 22` ramp, 4pt of spacing against its 8. That drift is only re-spellable
/// while there are two spellings.
///
/// The width ramp is read here rather than passed in, so neither sheet names those numbers again.
/// `horizontalSizeClass` is a scene trait, so the value is the same one the sheets branch their own
/// layouts on — the regular layout's `.frame(width: 320)` around this view does not change it.
///
/// `accessory` is the one thing the two sheets genuinely differ on: the event sheet puts its
/// commit-failure notice inside the block, under the title. A sheet without one passes nothing.
struct iOSNoteEditorSheetHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder let accessory: Accessory

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrowLabel(text: eyebrow)

            Text(title)
                .font(.system(size: isRegularWidth ? 24 : 22, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)

            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: isRegularWidth ? .infinity : nil, alignment: .topLeading)
        .padding(.horizontal, isRegularWidth ? 20 : 18)
        .padding(.vertical, isRegularWidth ? 20 : 14)
        .background(Theme.surface)
    }
}

extension iOSNoteEditorSheetHeader where Accessory == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}
#endif
