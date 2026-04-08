#if os(macOS)
import SwiftUI

struct GlobalSearchSectionsList: View {
    let sections: [GlobalSearchSection]
    let query: String
    let highlightedResultID: String?
    let onSelect: (GlobalSearchResult) -> Void
    let onHover: (String) -> Void

    var body: some View {
        if sections.isEmpty {
            GlobalSearchEmptyState(query: query)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.category.rawValue.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                                .kerning(0.8)
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
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            content()
                .frame(width: 760, height: 620)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Theme.borderSubtle.opacity(0.95), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.32), radius: 36, x: 0, y: 20)
        }
    }
}
#endif
