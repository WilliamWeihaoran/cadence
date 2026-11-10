import SwiftUI

// MARK: - Sections

/// The three sections a list's Notes tab draws, in column order: the list's own notes, the linked
/// calendar's upcoming event notes, and the list's open tasks that carry notes.
///
/// **[[T-15433]]: one heading on both platforms.** The Mac headed each with a count and a fold
/// (`CollapsibleNoteSection`, then macOS-only) while iOS drew the list notes with no heading at all
/// and the other two under a bare title, with no count and no fold. Nothing about touch or width
/// separates them ([[T-8201]]), so both tabs now build their headings here and draw them with the
/// one view below.
enum CadenceListNotesSection: CaseIterable, Hashable {
    case notes
    case events
    case taskNotes

    var title: String {
        switch self {
        case .notes: "Notes"
        // The Events tab's own word, as the Mac's heading already read it (T-7031).
        case .events: CadenceNotesTabVocabulary.events.columnTitle
        case .taskNotes: "Task Notes"
        }
    }

    /// What the count counts, for VoiceOver.
    fileprivate var rowNoun: (singular: String, plural: String) {
        switch self {
        case .notes, .events: ("note", "notes")
        case .taskNotes: ("task", "tasks")
        }
    }
}

/// One drawn heading: which section, and how many rows sit under it.
///
/// **The count and the heading's existence are one input.** A caller hands over the count of the
/// same filtered array its rows `ForEach`, and gets `nil` back when that array is empty — so a
/// section can neither draw a heading over nothing nor show a figure that disagrees with its rows.
struct CadenceListNotesSectionHeading: Equatable {
    let section: CadenceListNotesSection
    let count: Int

    static func heading(_ section: CadenceListNotesSection, count: Int) -> CadenceListNotesSectionHeading? {
        count > 0 ? CadenceListNotesSectionHeading(section: section, count: count) : nil
    }

    var title: String { section.title }

    var countText: String { "\(count)" }

    func accessibilityValue(isCollapsed: Bool) -> String {
        let noun = section.rowNoun
        let phrase = CadencePluralization.phrase(count, singular: noun.singular, plural: noun.plural)
        return isCollapsed ? "Collapsed, \(phrase)" : "Expanded, \(phrase)"
    }
}

// MARK: - Collapsible section

/// A list Notes-tab section: a fold-control heading (chevron, eyebrow title, count capsule) over
/// its rows. Both platforms, one component — it was the Mac's alone before [[T-15433]].
///
/// The figures that differ are the tier's, read from `CadenceNotesListMetrics`: the touch tiers
/// give the heading the 44pt floor every tappable row there sets, and the desktop leaves it
/// intrinsic. The anatomy does not differ.
struct CollapsibleNoteSection<Content: View>: View {
    let heading: CadenceListNotesSectionHeading
    var metrics: CadenceNotesListMetrics = .desktop
    @Binding var isCollapsed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isCollapsed.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 12)
                    // `Theme.muted` rather than the eyebrow's default `Theme.dim`: this header is
                    // a *control* — the whole row toggles the section — so it sits a step brighter
                    // than the inert eyebrows around it.
                    SectionEyebrowLabel(text: heading.title, tint: Theme.muted)
                    Spacer()
                    Text(heading.countText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surfaceElevated.opacity(0.75))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: metrics.headerMinHeight)
                .contentShape(Rectangle())
            }
            // `.plain`: the highlight below is the one hover layer ([[T-9465]]).
            .buttonStyle(.plain)
            .cadenceHoverHighlight(
                cornerRadius: Theme.radiusControlCompact,
                fillColor: Theme.surfaceElevated.opacity(0.55),
                strokeColor: Theme.borderSubtle.opacity(0.8)
            )
            .accessibilityLabel(heading.title)
            .accessibilityValue(heading.accessibilityValue(isCollapsed: isCollapsed))
            .accessibilityAddTraits([.isButton, .isHeader])

            if !isCollapsed {
                content
            }
        }
    }
}
