#if os(macOS)
import SwiftUI

/// The picker's row model moved to `Shared/CadenceFocusBundleSupport.swift` under T-242: it was
/// date-key arithmetic and string matching sitting inside `#if os(macOS)`, and that guard is why
/// the iPhone's focus picker could list tasks but never a block. The Mac keeps the shorter
/// spelling the views below read better with; there is no second body.
typealias FocusPickItem = CadenceFocusPickItem

struct FocusPickSessionCard: View {
    let title: String
    let subtitle: String
    let clockDisplay: String
    @Binding var searchText: String
    let items: [FocusPickItem]
    let onSelectTask: (AppTask) -> Void
    let onSelectBundle: (TaskBundle) -> Void
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionEyebrowLabel(text: "Ready to focus")

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
                                case .bundle(let bundle):
                                    onSelectBundle(bundle)
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
            TextField("Search tasks and bundles", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($searchFieldFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel("Clear search")
            }
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

            Text(isSearching ? "No matching tasks or bundles" : "Nothing ready right now")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text(isSearching ? "Try a project, bundle title, task title, priority, or date." : "When a task is ready, it will appear here.")
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

        let counts = itemCounts
        if isSearching {
            return "\(items.count) match\(items.count == 1 ? "" : "es")"
        }

        var parts: [String] = []
        if counts.tasks > 0 {
            parts.append("\(counts.tasks) task\(counts.tasks == 1 ? "" : "s")")
        }
        if counts.bundles > 0 {
            parts.append("\(counts.bundles) bundle\(counts.bundles == 1 ? "" : "s")")
        }
        return "Best matches / \(parts.joined(separator: " / "))"
    }

    private var itemCounts: (tasks: Int, bundles: Int) {
        var taskCount = 0
        var bundleCount = 0
        for item in items {
            switch item {
            case .task:
                taskCount += 1
            case .bundle:
                bundleCount += 1
            }
        }
        return (taskCount, bundleCount)
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
        case .bundle:
            Image(systemName: "tray.full")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 24, height: 24)
                .background(Theme.amber.opacity(0.12))
                .clipShape(Circle())
        }
    }

    private var title: String {
        switch item {
        case .task(let task):
            return TaskTitleSupport.displayTitle(task.title)
        case .bundle(let bundle):
            return bundle.displayTitle
        }
    }

    @ViewBuilder
    private var detailLine: some View {
        switch item {
        case .task(let task):
            CadenceTaskDetailLineLabel(task: task, fallback: "Ready to focus", fontSize: 11)
        case .bundle(let bundle):
            Text(bundleDetail(bundle))
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
    }

    private func bundleDetail(_ bundle: TaskBundle) -> String {
        CadenceFocusBundlePresentation.summaryLine(for: bundle)
    }

    private var tint: Color {
        switch item {
        case .task:
            return Theme.blue
        case .bundle:
            return Theme.amber
        }
    }

    private var helpText: String {
        switch item {
        case .task:
            return "Focus this task"
        case .bundle:
            return "Focus this bundle"
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
