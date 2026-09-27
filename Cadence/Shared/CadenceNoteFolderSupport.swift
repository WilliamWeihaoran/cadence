import SwiftData
import SwiftUI

// The **drawing** half of the note-folder convention: the grouping a column reads and the four
// rows that draw it. The path rule itself — `CadenceNoteFolderPath`, `CadenceListNoteFiling` and
// `CadenceListNoteSupport` — is in `CadenceListNoteFiling.swift`, which imports no SwiftUI so
// `CadenceMCPServer` can compile it ([[T-1122]]). Read that file's header before moving anything
// back across the line.

// MARK: - Grouping

/// One folder heading and the notes filed under it.
struct CadenceNoteFolderGroup: Identifiable {
    /// Already normalized. `""` for the root.
    let folderPath: String
    let notes: [Note]

    var id: String { CadenceNoteFolderPath.id(for: folderPath) }
    var displayName: String { CadenceNoteFolderPath.displayName(for: folderPath) }
    /// Reads the shared predicate rather than re-spelling it as `folderPath.isEmpty`.
    ///
    /// `folderPath` is already normalized here, so the two are equivalent today and the
    /// re-normalization is redundant — which is exactly why the near-copy was easy to write. It was
    /// also the only thing keeping `CadenceNoteFolderPath.isRoot` at zero production readers, so a
    /// dead-code pass found a shared predicate unused while a duplicate of it shipped. Calling it is
    /// the fix; deleting it would have been the wrong half of the same observation.
    var isRoot: Bool { CadenceNoteFolderPath.isRoot(folderPath) }

    /// The root group draws no heading, on both platforms. Its notes are the ones that were never
    /// filed, and a heading reading "Notes" inside a column already headed "Notes" would be the
    /// page describing the page you are on.
    var showsHeader: Bool { !isRoot }
}

enum CadenceNoteFolderGrouping {
    /// Groups list notes by normalized folder path: real folders first in case-insensitive order,
    /// the unfiled notes last.
    ///
    /// A folder with nothing in it never becomes a group — there is no folder *record* to keep, so
    /// an empty folder does not exist. Emptying one is how you delete it.
    static func groups(for notes: [Note]) -> [CadenceNoteFolderGroup] {
        let grouped = Dictionary(grouping: notes) { CadenceNoteFolderPath.normalized($0.folderPath) }
        return grouped.keys
            .sorted(by: CadenceNoteFolderPath.precedes)
            .map { path in
                CadenceNoteFolderGroup(
                    folderPath: path,
                    // A closure literal rather than `sorted(by: precedes)`. `precedes` reads
                    // `Note` stored properties, so it is main-actor isolated in a module that
                    // defaults to `MainActor`, and `sorted(by:)` wants a nonisolated function
                    // *reference* — which is a warning, and the warning baseline is zero. The
                    // literal inherits this function's isolation instead.
                    notes: (grouped[path] ?? []).sorted { precedes($0, $1) }
                )
            }
    }

    /// The folders a "move to folder" menu offers, for one list's notes.
    static func folderNames(in notes: [Note]) -> [String] {
        CadenceNoteFolderPath.names(in: notes.map(\.folderPath))
    }

    /// Row order inside a folder, and it is **total**: `order`, then title, then `id`.
    ///
    /// `order` is assigned per list and two notes routinely share one, and the title tie-break is
    /// case-insensitive so two notes can compare equal on both. `sorted(by:)` is not a stable sort,
    /// so a partial order there reshuffles rows between renders. Same reasoning as
    /// `TaskOrdering.fallbackPrecedes`.
    static func precedes(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        let comparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

// MARK: - Heading

/// One folder heading in a folder-grouped note list. Both platforms, one component.
///
/// Quieter than `NotesMonthHeader` on purpose and it is not a fold control: a month heading is the
/// only handle on a decade of daily notes, where a folder heading stands over a handful of notes in
/// a column that is already scoped to one list. It takes its figures from the same
/// `CadenceNotesListMetrics` the rows below it do, so the heading's left edge and the rows' glyph
/// column line up on every tier.
struct NoteFolderSectionHeader: View {
    let title: String
    var metrics: CadenceNotesListMetrics = .desktop

    var body: some View {
        Text(title)
            .font(.system(size: metrics.headerLabelSize, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, metrics.headerHorizontalPadding)
            .accessibilityLabel("Folder \(title)")
    }
}

// MARK: - Column

/// The folder-grouped run of headings and rows.
///
/// **Not a `ScrollView`.** macOS places this inside its own collapsible "Notes" section, iOS makes
/// it the scrolling column — which container it sits in is the one axis the two platforms are
/// allowed to differ on here, exactly as `NotesGroupedListColumn` records for the month-grouped
/// list. The rows are the caller's, because a row carries platform affordances (a macOS
/// double-click rename, an iOS tap-to-present) that the grouping has no opinion about.
struct NoteFolderGroupList<Row: View>: View {
    let groups: [CadenceNoteFolderGroup]
    var metrics: CadenceNotesListMetrics = .desktop
    @ViewBuilder let row: (Note) -> Row

    var body: some View {
        LazyVStack(alignment: .leading, spacing: metrics.groupSpacing) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    if group.showsHeader {
                        NoteFolderSectionHeader(title: group.displayName, metrics: metrics)
                    }
                    ForEach(group.notes) { note in
                        row(note)
                    }
                }
            }
        }
    }
}

// MARK: - Row

/// One list note's row. Both platforms.
///
/// It is `NoteListDayRow`'s shape with a glyph where the day number goes: a list note has no date
/// of its own to file under, which is the whole reason this column groups by folder instead of by
/// month.
///
/// **One fill at one radius, three states** — the same `Theme.blue.opacity(0.16)` selection and
/// `Theme.surfaceHover` hover `NoteListDayRow` settled on. macOS's row used to draw
/// `Theme.blue.opacity(0.15)` *and* a `cadenceHoverHighlight` fill and stroke on top of it, at the
/// same radius: two layers for one job. Do not add a second `.background()` here.
struct NoteFolderListRow: View {
    let title: String
    var detail: String?
    var tags: [Tag] = []
    let isSelected: Bool
    var metrics: CadenceNotesListMetrics = .desktop
    /// Non-nil while the row is being renamed in place — macOS's double-click rename. The text
    /// field takes the title's own slot rather than the row drawing a second form of itself, and it
    /// claims focus on appear because it only exists while editing.
    var editingTitle: Binding<String>?
    var onSubmitTitle: (() -> Void)?

    @State private var isHovered = false
    @FocusState private var isTitleFocused: Bool

    /// The glyph sits in a fixed slot the width of the day number's, so a folder column and a month
    /// column put their titles on the same line. The 8pt gap after it is **not**
    /// `metrics.dayNumberSpacing`: 14 is a word-space between a number and text, and a glyph
    /// reads as attached to the title it labels.
    private static let glyphSpacing: CGFloat = 8

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
    }

    private var fill: Color {
        if isSelected { return Theme.blue.opacity(0.16) }
        return isHovered ? Theme.surfaceHover : .clear
    }

    private var foreground: Color {
        isSelected ? Theme.text : Theme.muted
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.glyphSpacing) {
            Image(systemName: "doc.text")
                .font(.system(size: metrics.dayNumberSize))
                .foregroundStyle(isSelected ? Theme.text : Theme.dim)
                .frame(width: metrics.dayNumberWidth)

            VStack(alignment: .leading, spacing: 3) {
                if let editingTitle {
                    TextField("", text: editingTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: metrics.titleSize))
                        .foregroundStyle(Theme.text)
                        .focused($isTitleFocused)
                        .onAppear { isTitleFocused = true }
                        .onSubmit { onSubmitTitle?() }
                } else {
                    Text(title)
                        .font(.system(size: metrics.titleSize, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: metrics.detailSize))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                CompactTagStrip(tags: tags, limit: 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.rowMinHeight, alignment: .leading)
        .background(shape.fill(fill))
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Move menu

/// The "Move to Folder" submenu, one spelling for both platforms: out of every folder, into any
/// folder this list already has, or into a new one.
///
/// No checkmark and no disabled current folder, deliberately — the heading the row sits under
/// already says where it is, and greying out the answer to "where is this note" is how a menu
/// stops being readable as a list of destinations.
struct NoteFolderMoveMenu: View {
    let folderNames: [String]
    let move: (String) -> Void
    let newFolder: () -> Void

    var body: some View {
        Menu("Move to Folder") {
            Button("No Folder") { move(CadenceNoteFolderPath.root) }
            ForEach(folderNames, id: \.self) { name in
                Button(name) { move(name) }
            }
            Button("New Folder...") { newFolder() }
        }
    }
}
