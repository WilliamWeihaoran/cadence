#if os(macOS)
import SwiftUI
import AppKit
import Observation

@Observable
final class GlobalSearchManager {
    static let shared = GlobalSearchManager()

    var isPresented: Bool = false
    var query: String = ""

    private init() {}

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        query = ""
    }
}
#endif
