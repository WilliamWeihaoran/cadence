#if os(macOS)
import Foundation
import Observation

@Observable
final class CalendarNavigationManager {
    struct Request: Equatable {
        var dateKey: String
        var preferredHour: Int
        var token: UUID = UUID()
    }

    static let shared = CalendarNavigationManager()

    var request: Request?

    private init() {}

    func open(date: Date) {
        let hour = Calendar.current.component(.hour, from: date)
        request = Request(
            dateKey: DateFormatters.dateKey(from: date),
            preferredHour: hour
        )
    }

    func clear() {
        request = nil
    }
}
#endif
