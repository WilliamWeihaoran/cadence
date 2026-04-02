#if os(macOS)
import SwiftUI

@Observable
final class TodayTimelineFocusManager {
    static let shared = TodayTimelineFocusManager()

    var focusRequestID: Int = 0

    private init() {}

    func requestFocus() {
        focusRequestID &+= 1
    }
}
#endif
