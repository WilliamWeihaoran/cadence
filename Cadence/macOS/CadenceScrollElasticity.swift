#if os(macOS)
import SwiftUI
import AppKit

// Moved out of `Shared/Components/` by T-288. This one was never arguably shared: it is an
// `NSViewRepresentable` reaching for `NSScrollView.Elasticity`, and all four callers
// (`SettingsView`, `ListDetailComponents`, `TasksListView`, `TasksPanel`) are macOS pages. It sits
// beside `macOSRootView.swift` rather than under `Views/` because it is a view *modifier* on the
// AppKit boundary, not a screen.

@MainActor
private struct CadenceScrollElasticityConfigurator: NSViewRepresentable {
    typealias NSViewType = NSView
    typealias Coordinator = Void

    let vertical: NSScrollView.Elasticity
    let horizontal: NSScrollView.Elasticity

    func makeNSView(context: NSViewRepresentableContext<CadenceScrollElasticityConfigurator>) -> NSViewType {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            apply(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSViewType, context: NSViewRepresentableContext<CadenceScrollElasticityConfigurator>) {
        DispatchQueue.main.async {
            apply(from: nsView)
        }
    }

    private func apply(from view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        if scrollView.verticalScrollElasticity != vertical {
            scrollView.verticalScrollElasticity = vertical
        }
        if scrollView.horizontalScrollElasticity != horizontal {
            scrollView.horizontalScrollElasticity = horizontal
        }
    }
}

extension View {
    func cadenceSoftPageBounce() -> some View {
        background(
            CadenceScrollElasticityConfigurator(
                vertical: .none,
                horizontal: .automatic
            )
            .allowsHitTesting(false)
        )
    }
}
#endif
