#if os(macOS)
import SwiftUI

struct macOSRootMainShell<Content: View>: View {
    let columnVisibility: NavigationSplitViewVisibility
    @Binding var selection: SidebarItem?
    let showTimelineSidebar: Bool
    let timelineSidebarOverlay: AnyView
    @ViewBuilder let detailContent: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            if columnVisibility != .detailOnly {
                SidebarView(selection: $selection)
                    .frame(width: 264)
                    .background(
                        LinearGradient(
                            colors: [Theme.surface.opacity(0.98), Theme.surfaceElevated.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Theme.borderSubtle.opacity(0.85))
                            .frame(width: 1)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            ZStack(alignment: .trailing) {
                detailContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)

                if showTimelineSidebar {
                    timelineSidebarOverlay
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct macOSRootOverlayStack: View {
    let handleSearchSelection: (GlobalSearchResult) -> Void

    var body: some View {
        TaskCreationLayerView()
        SuccessToastLayerView()
        DeleteConfirmationLayerView()
        DatePickerLayerView()
        GlobalSearchLayerView(onSelect: handleSearchSelection)
    }
}
#endif
