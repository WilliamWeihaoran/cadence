#if os(macOS)
import SwiftUI

struct GlobalSearchSectionsList: View {
    let sections: [GlobalSearchVisibleSection]
    let query: String
    /// Completed tasks the query matches that the Completed filter holds back ([[T-6971]]).
    var withheldCompletedTaskCount: Int = 0
    let highlightedResultID: String?
    let onSelect: (GlobalSearchResult) -> Void
    let onHover: (String) -> Void
    /// Reveals one section's withheld matches in place, keyed by `GlobalSearchVisibleSection.id`.
    let onReveal: (String) -> Void

    var body: some View {
        if sections.isEmpty {
            GlobalSearchEmptyState(query: query, withheldCompletedTaskCount: withheldCompletedTaskCount)
        } else {
            // [[T-8063]]: the palette is a fixed 760x620 card and `onMoveCommand` only rewrites
            // `highlightedResultID`, so Down walked the highlight off the bottom edge within about
            // ten presses and Return opened a row the user never saw. The list now follows the
            // highlight — every arrow move, hover and reveal (a reveal moves it to the section's
            // first new row) — as the editor's slash-command menu does ([[T-7233]]). `scrollTo`
            // with no anchor moves the least distance, so a row already on screen stays put.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                SectionEyebrowLabel(text: section.category.rawValue)
                                    .padding(.horizontal, 16)

                                VStack(spacing: 4) {
                                    ForEach(section.results) { result in
                                        GlobalSearchResultRow(
                                            result: result,
                                            isHighlighted: highlightedResultID == result.id,
                                            onSelect: { onSelect(result) },
                                            onHover: { onHover(result.id) }
                                        )
                                        .id(result.id)
                                    }

                                    // No row when nothing is withheld: `continuationLabel` returns
                                    // `nil` at zero, so "0 more results" cannot be drawn.
                                    if let hidden = section.hidden,
                                       let label = CadenceSearchResultCap.continuationLabel(hidden: hidden) {
                                        let continuationID = GlobalSearchKeyboardRow.continuationID(forSection: section.id)
                                        GlobalSearchMoreResultsRow(
                                            continuation: GlobalSearchResultContinuation(
                                                label: label,
                                                reveal: { onReveal(section.id) }
                                            ),
                                            isHighlighted: highlightedResultID == continuationID,
                                            onHover: { onHover(continuationID) }
                                        )
                                        .id(continuationID)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.hidden)
                .onAppear { scrollToHighlighted(proxy) }
                .onChange(of: highlightedResultID) { _, _ in scrollToHighlighted(proxy) }
            }
        }
    }

    /// The highlight's id is a result's id or a section's continuation id
    /// (`GlobalSearchKeyboardRow`), and each row is tagged with exactly that id above.
    private func scrollToHighlighted(_ proxy: ScrollViewProxy) {
        guard let highlightedResultID else { return }
        proxy.scrollTo(highlightedResultID)
    }
}

struct GlobalSearchOverlayShell<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Theme.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            content()
                .frame(width: 760, height: 620)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusPanel, style: .continuous)
                        .strokeBorder(Theme.borderSubtle.opacity(0.4), lineWidth: 1)
                }
                .shadow(color: Theme.overlayCardShadow, radius: 36, x: 0, y: 20)
        }
    }
}
#endif
