import SwiftUI

struct EstimatePickerControl: View {
    @Binding var value: Int
    var compact: Bool = false
    @State private var showPicker = false

    private let options: [(Int, String)] = [
        (0, "No estimate"),
        (5, "5 min"),
        (15, "15 min"),
        (30, "30 min"),
        (45, "45 min"),
        (60, "1 hour"),
        (90, "1.5 hrs"),
    ]

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: compact ? 9 : 12))
                    .foregroundStyle(value > 0 ? Theme.blue : Theme.dim)
                Text(label)
                    .font(.system(size: compact ? 10 : 13))
                    .foregroundStyle(value > 0 ? Theme.text : Theme.dim)
                Image(systemName: "chevron.down")
                    .font(.system(size: compact ? 7 : 8, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 3 : 6)
            .frame(minHeight: compact ? 21 : 30)
            .contentShape(Rectangle())
            .background(Theme.surface.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 8))
        }
        .buttonStyle(.cadencePlain)
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options, id: \.0) { mins, title in
                    Button {
                        value = mins
                        showPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .font(.system(size: 12))
                                .foregroundStyle(value == mins ? Theme.blue : Theme.dim)
                                .frame(width: 16)
                            Text(title)
                                .font(.system(size: 13))
                                .foregroundStyle(value == mins ? Theme.text : Theme.muted)
                            Spacer()
                            if value == mins {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(value == mins ? Theme.blue.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.cadencePlain)
                    .cadenceHoverHighlight(cornerRadius: 6, fillColor: Theme.blue.opacity(0.08), strokeColor: .clear)
                }
            }
            .padding(6)
            .frame(minWidth: 160)
            .background(Theme.surfaceElevated)
        }
    }

    private var label: String {
        switch value {
        case ..<1: return "No estimate"
        case 5: return "5m"
        case 15: return "15m"
        case 30: return "30m"
        case 45: return "45m"
        case 60: return "1h"
        case 90: return "1.5h"
        default: return "\(value)m"
        }
    }
}
