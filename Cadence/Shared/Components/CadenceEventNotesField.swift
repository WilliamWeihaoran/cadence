import SwiftUI

/// **[[T-8161]] — the event editor's one Notes field, drawn the same way on both platforms.**
///
/// It replaces two surfaces per platform: the "Event Note" Create/Open card and the separate
/// "Apple Calendar note" well on iOS, and the Mac's own card offering to create or open that note
/// beside the panel's plain notes row. The field *is* the rich Cadence `Note`; what reaches
/// `EKEvent.notes` is a flattened copy
/// (`CadenceEventNotesMerge`), which is why there is nothing here for the user to keep in sync.
///
/// **The editor is the host's, the chrome is this view's.** macOS edits markdown through an
/// AppKit `MarkdownEditor` and iOS through `iOSMarkdownEditingSurface`; those are two platforms'
/// implementations of one control, not two designs, and neither type is visible from the other's
/// build. Everything that *is* a design decision — the label, the read-only sentence, where the
/// failure notice sits, the control that opens the full editor — is here once, so the two surfaces
/// cannot drift the way the two they replaced did (`AGENTS.md`, "macOS and iOS are one app").
struct CadenceEventNotesField<Editor: View>: View {
    /// Whether a flattened copy can reach Apple Calendar at all. `false` on a read-only calendar,
    /// where rule (5) keeps the note editable and says so quietly instead of disabling the field.
    var mirrorsToCalendar: Bool
    /// What the last commit could not do — a refused local save, or a mirror Apple Calendar
    /// rejected. `CadenceEventNoteCommitOutcome.notice` writes this sentence.
    var failureNotice: String?
    /// Opens the note's full editor. The field is the note, so this is a zoom rather than a second
    /// place to type; absent when the host has no editor to open.
    var onOpenFullEditor: (() -> Void)?
    @ViewBuilder var editor: () -> Editor

    var body: some View {
        CadenceFieldSection(title: CadenceEventNotesMerge.fieldTitle, style: .ruled) {
            VStack(alignment: .leading, spacing: 8) {
                editor()
                footer
                if let failureNotice {
                    CadenceInlineFailureNotice(text: failureNotice)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !mirrorsToCalendar || onOpenFullEditor != nil {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !mirrorsToCalendar {
                    Text(CadenceEventNotesMerge.readOnlyNotice)
                        .cadenceFont(.metadata)
                        .foregroundStyle(Theme.subdued)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if let onOpenFullEditor {
                    Button("Open", action: onOpenFullEditor)
                        .buttonStyle(.cadencePlain)
                        .cadenceFont(.controlLabel, weight: .semibold)
                        .foregroundStyle(Theme.blue)
                }
            }
        }
    }
}

/// The merged field's figures, stated once because the two platforms host two different editors
/// inside it and a height typed twice is a height that drifts.
enum CadenceEventNotesFieldMetrics {
    /// The resting height of the Mac's editor inside the event popover.
    ///
    /// `MarkdownEditor` has no intrinsic content size — it fills exactly what it is given — so
    /// this **is** the box, not a floor it grows from, which is the measurement
    /// `TaskInspectorContentSupportViews` already records for its own 120. The popover is 372pt
    /// wide and carries a dozen rows above this one, so it reads the same number: enough for a
    /// paragraph and its divider without the field becoming the popover.
    static let deskEditorHeight: CGFloat = 120
}
