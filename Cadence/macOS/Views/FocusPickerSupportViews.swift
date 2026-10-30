#if os(macOS)
import SwiftUI

/// The picker's row model lives in `Shared/CadenceFocusBundleSupport.swift` since T-242: it is
/// date-key arithmetic and string matching, and it sat inside `#if os(macOS)` where the iPhone's
/// focus picker could not reach it. The Mac keeps the shorter spelling the views below read better
/// with; there is no second body.
typealias FocusPickItem = CadenceFocusPickItem

struct FocusPickSessionCard: View {
    let title: String
    let subtitle: String
    let clockDisplay: String
    @Binding var searchText: String
    let items: [FocusPickItem]
    let onSelectTask: (AppTask) -> Void
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionEyebrowLabel(text: CadenceFocusSupport.pickListEyebrow)

                    Text(title)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                FocusIdleClockBadge(clockDisplay: clockDisplay)
            }

            searchBar

            HStack(spacing: 10) {
                Text(resultSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)

                Spacer(minLength: 12)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in
                            FocusPickItemRow(item: item) {
                                switch item {
                                case .task(let task):
                                    onSelectTask(task)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.borderSubtle.opacity(0.9), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.blue.opacity(searchFieldFocused ? 0.55 : 0.22))
                .frame(height: 2)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(searchFieldFocused ? Theme.blue : Theme.dim)
            TextField(CadenceFocusSupport.pickSearchPrompt, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($searchFieldFocused)
            CadenceSearchFieldClearButton(text: $searchText, glyphSize: 12, focus: $searchFieldFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Theme.surfaceElevated.opacity(searchFieldFocused ? 0.94 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(searchFieldFocused ? Theme.blue.opacity(0.42) : Theme.borderSubtle.opacity(0.85), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: isSearching ? "magnifyingglass" : "checkmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSearching ? Theme.dim : Theme.green)

            Text(isSearching ? CadenceEmptyStateCopy.focusSearchTitle : CadenceEmptyStateCopy.focusTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text(isSearching ? CadenceEmptyStateCopy.focusSearchSubtitle : CadenceEmptyStateCopy.focusSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surfaceElevated.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resultSummary: String {
        if items.isEmpty {
            return isSearching ? "No matches" : "No ready sessions"
        }

        if isSearching {
            return "\(items.count) match\(items.count == 1 ? "" : "es")"
        }

        return "Best matches / \(items.count) task\(items.count == 1 ? "" : "s")"
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct FocusPickItemRow: View {
    let item: FocusPickItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leadingIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    detailLine
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(isHovered ? 0.16 : 0.09))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Theme.surfaceElevated.opacity(isHovered ? 0.88 : 0.58))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isHovered ? tint.opacity(0.2) : Theme.borderSubtle.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
        .help(helpText)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch item {
        case .task(let task):
            ZStack {
                Circle()
                    .fill(Color(hex: task.containerColor).opacity(0.16))
                Circle()
                    .fill(Color(hex: task.containerColor))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 24, height: 24)
        }
    }

    private var title: String {
        switch item {
        case .task(let task):
            return TaskTitleSupport.displayTitle(task.title)
        }
    }

    @ViewBuilder
    private var detailLine: some View {
        switch item {
        case .task(let task):
            CadenceTaskDetailLineLabel(task: task, fallback: CadenceFocusSupport.pickRowFallback, fontSize: 11)
        }
    }

    private var tint: Color {
        switch item {
        case .task:
            return Theme.blue
        }
    }

    private var helpText: String {
        switch item {
        case .task:
            return "Focus this task"
        }
    }
}

private struct FocusIdleClockBadge: View {
    let clockDisplay: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.blue)

            Text(clockDisplay)
                .font(.system(size: 24, weight: .light, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surfaceElevated.opacity(0.58))
        .clipShape(Capsule())
    }
}
#endif
