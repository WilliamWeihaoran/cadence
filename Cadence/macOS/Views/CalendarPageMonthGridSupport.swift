#if os(macOS)
import SwiftUI
import Foundation

func agentDebugLogMonthGrid(runId: String, hypothesisId: String, location: String, message: String, data: [String: Any]) {
    guard let endpoint = ProcessInfo.processInfo.environment["CADENCE_MONTH_GRID_DEBUG_URL"],
          let url = URL(string: endpoint) else { return }

    func sanitize(_ value: Any) -> Any {
        switch value {
        case let v as CGFloat: return Double(v)
        case let v as Float: return Double(v)
        case let v as Int: return v
        case let v as Double: return v
        case let v as Bool: return v
        case let v as String: return v
        case let v as [String: Any]:
            return v.mapValues { sanitize($0) }
        case let v as [Any]:
            return v.map { sanitize($0) }
        default:
            return String(describing: value)
        }
    }
    var payload: [String: Any] = [
        "sessionId": "2fa876",
        "runId": runId,
        "hypothesisId": hypothesisId,
        "location": location,
        "message": message,
        "data": sanitize(data),
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    if payload["id"] == nil {
        payload["id"] = "log_\(UUID().uuidString)"
    }
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          !json.isEmpty else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("2fa876", forHTTPHeaderField: "X-Debug-Session-Id")
    request.httpBody = json
    URLSession.shared.dataTask(with: request).resume()
}

func monthStart(for date: Date, calendar: Calendar) -> Date {
    let comps = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: comps) ?? date
}

func monthIndex(for date: Date, currentMonthStart: Date, todayMonthIdx: Int, calendar: Calendar) -> Int {
    let targetMonthStart = monthStart(for: date, calendar: calendar)
    let delta = calendar.dateComponents([.month], from: currentMonthStart, to: targetMonthStart).month ?? 0
    return min(max(todayMonthIdx + delta, 0), 119)
}

func monthIndexForOffset(y: CGFloat, offsets: [CGFloat], totalMonths: Int) -> Int {
    let monthCount = min(offsets.count, max(totalMonths, 0))
    guard monthCount > 0 else { return 0 }

    var lo = 0
    var hi = monthCount - 1
    while lo < hi {
        let mid = (lo + hi + 1) / 2
        if offsets[mid] <= y { lo = mid } else { hi = mid - 1 }
    }
    return lo
}

struct MonthGridWeekdayHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                Text(day)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .background(Theme.surface)
    }
}
#endif
