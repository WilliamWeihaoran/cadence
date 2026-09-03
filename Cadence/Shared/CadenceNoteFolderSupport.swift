import SwiftData
import SwiftUI

// A note folder is a **convention over a string**, not a model. `Note.folderPath` is a plain
// `String` with a default of `""`, exactly as `TaskSectionConfig` is a convention over JSON in a
// raw column — so the convention only exists as long as every reader and writer agrees on it, and
// until T-193 the only agreement was four macOS call sites that happened to share one private
// helper.
//
// **The convention, read off `NoteFolderSheet.normalizedFolderPath` and its three co-readers rather
// than invented here:**
//
// - The separator is `/`.
// - A path carries **no leading and no trailing separator**, and no empty components: the writer
//   splits on `/`, trims each component, drops the empties and rejoins.
// - The **root is the empty string**, and so is a path that normalizes to nothing (`"/"`, `"  "`,
//   `"//"`). There is no `nil` — `Note.folderPath` is non-optional.
// - **Nesting is representable and is not a tree.** `"Planning/Research"` is a legal path (it is
//   the macOS sheet's own placeholder) but every surface groups on the *whole* normalized string,
//   so `Planning` and `Planning/Research` are two sibling groups rather than a parent and a child.
//   That is what macOS does today; `components(_:)` and `depth(_:)` exist so a future tree can be
//   built without re-deciding the storage format, and nothing reads them yet.
// - Folders apply to **`.list` notes only**. Nothing writes `folderPath` on a daily, weekly,
//   notepad or event note, and the four-tab Notes page never reads it. The callers here all pass
//   `CadenceListNoteSupport.notes(for:project:in:)`, which already filters on the kind.
//
// **Normalization happens on read as well as on write, and that is load-bearing.**
// `DataIntegrityRepairService.mergeNoteFields` copies `folderPath` from a merged duplicate with
// `fillEmptyString`, which trims to decide "unset" and then assigns the source's value **raw** —
// so a path that was never normalized can arrive from a merge, from CloudKit, or from a build
// older than the convention. `groups(for:)` normalizes every path it reads for exactly that
// reason. (In practice that merge cannot reach a list note at all: `Note.canonicalKey` is
// `"list:\(id)"`, unique per note, so two list notes are never duplicates. The read-side
// normalization is what makes that a nice-to-have rather than the thing holding the invariant up.)

// MARK: - The path convention

nonisolated enum CadenceNoteFolderPath {
    static let separator = "/"

    /// The root folder. **Exactly the empty string** — `DataIntegrityRepairService.fillEmptyString`
    /// treats a whitespace-trimmed-empty `folderPath` as "unset", so any other sentinel (`"/"`,
    /// `"Notes"`) would read as a real folder to the merge pass.
    static let root = ""

    /// What the root group is called where it has to be named. The grouped column deliberately
    /// draws **no** heading over it — see `CadenceNoteFolderGroup.showsHeader`.
    static let rootDisplayName = "Notes"

    /// Stable identity for a path, so a `ForEach` over groups has something non-empty to key on.
    static let rootID = "__root__"

    /// The one normalizer. Split on the separator, trim each component, drop the empties, rejoin.
    ///
    /// This is byte-for-byte the algorithm `ListNotesView` carried privately; it is out here so the
    /// second platform cannot arrive at a second spelling of it, and so it can be tested.
    static func normalized(_ raw: String) -> String {
        raw
            .split(separator: Character(separator))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    static func isRoot(_ path: String) -> Bool {
        normalized(path).isEmpty
    }

    /// The path's segments, outermost first. Nothing renders a tree today; this exists so the
    /// storage format does not have to be re-decided when something does.
    static func components(_ path: String) -> [String] {
        let normalized = normalized(path)
        return normalized.isEmpty ? [] : normalized.components(separatedBy: separator)
    }

    /// 0 for the root, 1 for `"Planning"`, 2 for `"Planning/Research"`.
    static func depth(_ path: String) -> Int {
        components(path).count
    }

    /// The whole path, which is what a heading shows — not the leaf. A group keyed on the whole
    /// string must be labelled with the whole string or `Planning/Research` and `Admin/Research`
    /// would draw two headings reading "Research".
    static func displayName(for path: String) -> String {
        let normalized = normalized(path)
        return normalized.isEmpty ? rootDisplayName : normalized
    }

    static func id(for path: String) -> String {
        let normalized = normalized(path)
        return normalized.isEmpty ? rootID : normalized
    }

    /// Folder order: **the root sorts last**, everything else case-insensitively ascending.
    ///
    /// Root-last is macOS's rule and it is the right way round — a heading-less run of notes reads
    /// as "the rest" at the bottom of a column and as an unlabelled mystery at the top.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        if left.isEmpty { return false }
        if right.isEmpty { return true }
        if left.caseInsensitiveCompare(right) == .orderedSame { return left < right }
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
    }

    /// Every distinct real folder in a set of raw paths, normalized and ordered — what a
    /// "move to folder" menu lists. The root is **not** in it: "No Folder" is its own item, not a
    /// folder you move into.
    static func names(in rawPaths: [String]) -> [String] {
        Array(Set(rawPaths.map(normalized).filter { !$0.isEmpty })).sorted(by: precedes)
    }
}

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

// MARK: - Filing

/// Creating a list note and moving one between folders — **the** two writers of `folderPath`.
///
/// Both platforms call these, so normalization on write has exactly one owner. macOS carried
/// `addNote(folderPath:)`, `applyFolderRequest` and `defaultNoteContent` privately; iOS would
/// otherwise have had to copy all three, and the copy is where the separator, the trimming or the
/// seeded heading drifts.
enum CadenceListNoteFiling {
    /// A new list note, filed where it was asked for.
    ///
    /// `order` is the list's current note count, which is what macOS passed — it puts a new note at
    /// the end of whichever folder it lands in, because `CadenceNoteFolderGrouping.precedes` sorts
    /// on `order` inside a group.
    ///
    /// **T-497, the existence half of the `try? save()` rule.** This inserted a note, swallowed the
    /// save and handed the note back, and both callers then *selected* it — so the editor opened on
    /// a note the store may never have taken. There is no halfway reading of that: the note either
    /// exists or it does not, and a re-render cannot repair the difference the way it repairs a
    /// field edit. `commitInsert` deletes the note again when the commit is refused, so the caller
    /// gets an error instead of a selection pointing at nothing.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitInsert(of:in:commit:)`.
    @discardableResult
    static func createNote(
        in modelContext: ModelContext,
        area: Area?,
        project: Project?,
        folderPath: String = CadenceNoteFolderPath.root,
        order: Int,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Note {
        let note = Note(kind: .list)
        CadenceListNoteSupport.attach(note, to: area, project: project)
        note.order = order
        note.folderPath = CadenceNoteFolderPath.normalized(folderPath)
        note.content = seededContent(for: note.title)
        modelContext.insert(note)
        try CadencePendingChangePersistence.commitInsert(of: note, in: modelContext, commit: commit)
        return note
    }

    /// Moves a note into a folder, or out of every folder when handed anything that normalizes to
    /// the root.
    static func move(_ note: Note, toFolder rawPath: String) {
        note.folderPath = CadenceNoteFolderPath.normalized(rawPath)
    }

    /// A new note opens onto its own title as an H1, which is what the markdown editor keeps in
    /// step with `note.title`.
    ///
    /// **A nameless note gets an empty heading, not the word (T-733).** This used to substitute
    /// `"Untitled"` for a blank title, which was harmless only while `Note.title` defaulted to that
    /// same word: every new list note was born titled, so the branch never fired. With the stored
    /// default gone the branch became the thing that put it back — `MarkdownNoteTitleSync` reads
    /// the first line of the body and writes it to `title`, so a body seeded `# Untitled` renames
    /// the note to `Untitled` on its first commit and the repair pass clears it again on the next
    /// launch. `"# \n\n"` is still an H1, so it is still the rename control from the first
    /// keystroke; it is just empty, and an empty H1 is the one case `MarkdownNoteTitleSync`
    /// deliberately says nothing about.
    static func seededContent(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "# \(trimmed)\n\n"
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
