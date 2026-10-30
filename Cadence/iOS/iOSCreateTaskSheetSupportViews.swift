#if os(iOS)
import SwiftData
import SwiftUI

// Capture's inline title-marker suggestions; fields and pickers live in CadenceSchedulePanel.

enum iOSTaskComposerMarkerKind {
    case list
    case tag
}

/// The row of suggestions a `~` or `#` in the title raises.
///
/// Hands are already on the keyboard here, which is exactly where the markers pay off — so the
/// suggestions sit under the title rather than in a popover that would need a second tap to reach.
/// Accepting one consumes the marker and its query out of the title
/// (`CadenceTaskComposerSupport.title(removingShortcut:)`); ignoring it and carrying on typing
/// leaves the text alone, so `~` is never a trap.
struct iOSTaskComposerMarkerSuggestions: View {
    let kind: iOSTaskComposerMarkerKind
    let shortcut: TaskTitleInlineShortcut
    /// Every list. A suggestion strip is a picker, so it narrows to the active ones itself through
    /// `CadenceTaskComposerSupport.pickable*` — the sheet hands every control the same two arrays
    /// rather than a differently-filtered copy each (T-318).
    let areas: [Area]
    let projects: [Project]
    let allTags: [Tag]
    let onPickContainer: (TaskContainerSelection) -> Void
    let onPickTag: (Tag) -> Void
    let onCreateTag: (String) -> Void

    /// Read out of the environment here, unlike in the sheet: the strip is *inside*
    /// `.cadenceScaledTypography()`, so it sees what the sheet installed. Anywhere else it is
    /// `.fixed` and the strip is the 34pt control it has always been.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.cadenceTypographyScaling) private var scaling

    private var trimmedQuery: String {
        shortcut.query.trimmingCharacters(in: .whitespaces)
    }

    private var matchingAreas: [Area] {
        CadenceTaskComposerSupport.pickableAreas(areas)
            // [[T-8551]]: matched on the name the chip draws, so `~untitled` finds a blank list.
            .filter { CadenceTaskComposerSupport.matchesQuery(CadenceAreaPickerSupport.title(for: $0), query: shortcut.query) }
    }

    private var matchingProjects: [Project] {
        CadenceTaskComposerSupport.pickableProjects(projects)
            .filter { CadenceTaskComposerSupport.matchesQuery(CadenceProjectPickerSupport.title(for: $0), query: shortcut.query) }
    }

    private var matchingTags: [Tag] {
        TagSupport.uniqueBySlug(allTags.filter { !$0.isArchived })
            .filter { CadenceTaskComposerSupport.matchesQuery($0.name.isEmpty ? $0.slug : $0.name, query: shortcut.query) }
    }

    private var showsInbox: Bool {
        CadenceTaskComposerSupport.matchesQuery(CadenceTaskInspectorSupport.inboxSegmentTitle, query: shortcut.query)
    }

    private var canCreateTag: Bool {
        guard kind == .tag, !trimmedQuery.isEmpty else { return false }
        return !matchingTags.contains { ($0.name.isEmpty ? $0.slug : $0.name).caseInsensitiveCompare(trimmedQuery) == .orderedSame }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                switch kind {
                case .list:
                    listSuggestions
                case .tag:
                    tagSuggestions
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var listSuggestions: some View {
        if showsInbox {
            suggestion(
                title: CadenceTaskInspectorSupport.inboxSegmentTitle,
                systemImage: "tray.full.fill",
                tint: Theme.blue
            ) {
                onPickContainer(.inbox)
            }
        }

        ForEach(matchingAreas) { area in
            suggestion(
                title: CadenceAreaPickerSupport.title(for: area),
                systemImage: "tray.full.fill",
                tint: Color(hex: area.colorHex)
            ) {
                onPickContainer(.area(area.id))
            }
        }

        ForEach(matchingProjects) { project in
            suggestion(
                title: CadenceProjectPickerSupport.title(for: project),
                systemImage: "checklist",
                tint: Color(hex: project.colorHex)
            ) {
                onPickContainer(.project(project.id))
            }
        }

        if !showsInbox && matchingAreas.isEmpty && matchingProjects.isEmpty {
            emptyHint("No list matches “\(trimmedQuery)”")
        }
    }

    @ViewBuilder
    private var tagSuggestions: some View {
        if canCreateTag {
            suggestion(title: "Create “\(trimmedQuery)”", systemImage: "plus", tint: Theme.blue) {
                onCreateTag(trimmedQuery)
            }
        }

        ForEach(matchingTags) { tag in
            suggestion(
                title: tag.name.isEmpty ? tag.slug : tag.name,
                systemImage: "number",
                tint: Color(hex: tag.colorHex)
            ) {
                onPickTag(tag)
            }
        }

        if !canCreateTag && matchingTags.isEmpty {
            emptyHint("No tag matches “\(trimmedQuery)”")
        }
    }

    private func suggestion(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    // The glyph follows the label's role, not a curve of its own: a 13pt label at
                    // 38pt beside an 11pt glyph still at 11 is a chip whose two halves have come
                    // apart.
                    .cadenceFont(.controlLabel, base: 11)
                    .foregroundStyle(tint)
                Text(title)
                    .cadenceFont(.controlLabel)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: CadenceTaskComposerLayout.suggestionHeight(at: dynamicTypeSize, scaling: scaling))
            .background(tint.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .iOSExpandedHitArea(5)
        }
        .buttonStyle(.iosPressable)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .cadenceFont(.metadata)
            .foregroundStyle(Theme.dim)
            .lineLimit(CadenceTypeScale.isAccessibilitySize(dynamicTypeSize) && scaling == .enabled ? 2 : 1)
            .padding(.horizontal, 4)
            .frame(minHeight: CadenceTaskComposerLayout.suggestionHeight(at: dynamicTypeSize, scaling: scaling))
    }
}
#endif
