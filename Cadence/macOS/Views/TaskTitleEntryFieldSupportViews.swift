#if os(macOS)
import AppKit
import SwiftUI

enum TaskTitleTildeMode {
    case none
    case list
}

struct TaskTitleTildeContainerItem: Identifiable {
    let tag: TaskContainerSelection
    let icon: String
    let name: String
    let color: Color

    var id: TaskContainerSelection { tag }
}

struct TaskTitleInitialSelectionSuppressor: NSViewRepresentable {
    let expectedText: String
    @Binding var shouldCollapseSelection: Bool

    func makeNSView(context: NSViewRepresentableContext<TaskTitleInitialSelectionSuppressor>) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(
        _ nsView: NSView,
        context: NSViewRepresentableContext<TaskTitleInitialSelectionSuppressor>
    ) {
        guard shouldCollapseSelection else { return }
        collapseSelection(in: nsView, remainingAttempts: 4)
    }

    private func collapseSelection(in nsView: NSView, remainingAttempts: Int) {
        DispatchQueue.main.async {
            guard shouldCollapseSelection else { return }
            guard let editor = nsView.window?.firstResponder as? NSTextView,
                  editor.string == expectedText else {
                guard remainingAttempts > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    collapseSelection(in: nsView, remainingAttempts: remainingAttempts - 1)
                }
                return
            }

            let length = (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: length, length: 0))
            shouldCollapseSelection = false
        }
    }
}

#endif
