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
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
        }
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
