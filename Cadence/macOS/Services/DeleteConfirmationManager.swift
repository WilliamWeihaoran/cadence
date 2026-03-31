#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class DeleteConfirmationManager {
    struct Request: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirmLabel: String
        let action: () -> Void
    }

    static let shared = DeleteConfirmationManager()

    var request: Request?

    private init() {}

    var isPresented: Bool { request != nil }

    func present(
        title: String,
        message: String,
        confirmLabel: String = "Delete",
        action: @escaping () -> Void
    ) {
        request = Request(title: title, message: message, confirmLabel: confirmLabel, action: action)
    }

    func confirm() {
        guard let request else { return }
        self.request = nil
        request.action()
    }

    func cancel() {
        request = nil
    }
}
#endif
