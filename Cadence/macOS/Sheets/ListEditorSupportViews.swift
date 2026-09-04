#if os(macOS)
import SwiftUI
import EventKit

// MARK: - Sheet shell

/// Eyebrow + content + footer, shared by the three list sheets.
///
/// Deliberately has **no** `ScrollView` and **no** fixed height: colour and icon are always-visible
/// strips rather than expanding rows, so the sheet's height is constant and can size to content.
///
/// The footer has a leading slot for whole-list lifecycle actions (Archive, Delete). Those live
/// here, not in the field well, so a destructive action never shares a surface with a routine one.
///
/// **The eyebrow has no right-hand note any more (T-559).** It carried one string, `CreateListSheet`'s
/// "in Work", back when the context a list was being made in was fixed by whichever "+" you clicked
/// and the sheet had no way to say otherwise. Every list sheet now draws `ListEditorContextRow`, so
/// the context is stated by the control that sets it. Keeping the note would have meant answering
/// "what does it say when there is no context", and the honest answer is that the eyebrow should
/// never have been the thing saying it.
struct ListEditorSheetShell<Content: View, FooterLeading: View>: View {
    let title: String
    let confirmTitle: String
    let isConfirmDisabled: Bool
    let onConfirm: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footerLeading: FooterLeading

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The sheet's own name is an eyebrow, not a heading: the thing you actually read at the
            // top is the list you are editing, typed into the header below.
            SectionEyebrowLabel(text: title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            Divider().background(Theme.borderSubtle)

            HStack(spacing: 8) {
                footerLeading
                Spacer(minLength: 12)
                CadenceActionButton(title: "Cancel", role: .ghost, size: .compact) {
                    dismiss()
                }
                CadenceActionButton(
                    title: confirmTitle,
                    role: .primary,
                    size: .compact,
                    isDisabled: isConfirmDisabled
                ) {
                    onConfirm()
                }
            }
            .padding(16)
        }
        .frame(width: 420)
        .background(Theme.surface)
    }
}

extension ListEditorSheetShell where FooterLeading == EmptyView {
    init(
        title: String,
        confirmTitle: String,
        isConfirmDisabled: Bool,
        onConfirm: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            confirmTitle: confirmTitle,
            isConfirmDisabled: isConfirmDisabled,
            onConfirm: onConfirm,
            content: content,
            footerLeading: { EmptyView() }
        )
    }
}

// MARK: - Identity header

/// Colour/icon tile beside an inline-editable name, then colour and icon as always-visible strips.
///
/// The name is a title you type into rather than a bordered form field, and appearance is chosen in
/// place: no rows, no disclosure, no chevron, so the sheet never changes height while you use it.
///
/// `details` is the list's `desc`, and it is optional because `CreateContextSheet` uses this header
/// for a model that has no such field. Where it is passed it sits directly under the name and above
/// the appearance strips, which is where iOS's list editor puts it (T-330): before that, `Area.desc`
/// and `Project.desc` could be written on iPhone, were indexed by *both* platforms' search, and
/// could not be read or edited anywhere on the Mac.
///
/// One line, not iOS's `2...5`. That is the shell's own constraint rather than a style choice —
/// `ListEditorSheetShell` has no `ScrollView` and no fixed height, so a field that grows as you type
/// would make the sheet grow with it, which is exactly what the strips above exist to avoid.
struct ListEditorIdentityHeader: View {
    @Binding var name: String
    @Binding var colorHex: String
    @Binding var icon: String
    var placeholder: String = "List name…"
    var details: Binding<String>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    ListEditorIdentityTile(colorHex: colorHex, icon: icon)

                    TextField(placeholder, text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }

                if let details {
                    TextField("Description", text: details)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }

            ListEditorColorStrip(selected: $colorHex)
            ListEditorIconStrip(selected: $icon, colorHex: colorHex)
        }
    }
}

/// Live preview of the two choices below it. Not itself a control — the strips are the controls.
private struct ListEditorIdentityTile: View {
    let colorHex: String
    let icon: String

    var body: some View {
        let tint = Color(hex: colorHex)
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)

        shape
            .fill(tint.opacity(0.16))
            .overlay(shape.strokeBorder(tint.opacity(0.32), lineWidth: 1))
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
            )
            .frame(width: 38, height: 38)
    }
}

// MARK: - Colour strip

/// The twelve palette colours on one line, current selection ringed.
///
/// Shares `ColorGrid`'s palette and its stored-colour rule, so a list holding a hex the palette no
/// longer offers still shows a ringed swatch and is never silently re-coloured on open.
struct ListEditorColorStrip: View {
    @Binding var selected: String

    private let swatchSize: CGFloat = 20
    private let rowHeight: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CadenceColorPalette.offeredColors(for: selected), id: \.self) { hex in
                let isSelected = CadenceColorPalette.matches(hex, selected)
                Button {
                    selected = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: swatchSize, height: swatchSize)
                        .overlay(
                            Circle()
                                .strokeBorder(Theme.text, lineWidth: 1.5)
                                .padding(-4)
                                .opacity(isSelected ? 1 : 0)
                        )
                        .frame(maxWidth: .infinity, minHeight: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cadenceControlLabel(isSelected ? "Selected colour" : "Use this colour")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Icon strip

/// The icons people actually pick, on one line, with the full set one click away.
struct ListEditorIconStrip: View {
    @Binding var selected: String
    let colorHex: String

    @State private var showAll = false

    /// Eight glyphs that cover most lists. The current icon is prepended when it is not one of
    /// them, so the strip always shows what is selected instead of hiding it behind "More…".
    static let common = [
        "folder.fill", "checklist", "briefcase.fill", "graduationcap.fill",
        "house.fill", "heart.fill", "star.fill", "flag.fill",
    ]

    private var offered: [String] {
        guard !selected.isEmpty, !Self.common.contains(selected) else { return Self.common }
        return [selected] + Self.common
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(offered, id: \.self) { icon in
                ListEditorIconCell(
                    icon: icon,
                    isSelected: icon == selected,
                    tint: Color(hex: colorHex),
                    accessibilityLabel: icon
                ) {
                    selected = icon
                }
            }

            ListEditorIconCell(
                icon: "ellipsis",
                isSelected: false,
                tint: Color(hex: colorHex),
                accessibilityLabel: "More icons"
            ) {
                showAll.toggle()
            }
            .popover(isPresented: $showAll, arrowEdge: .bottom) {
                ScrollView {
                    IconGrid(selected: $selected)
                        .padding(12)
                }
                .frame(maxHeight: 320)
                .background(Theme.surfaceElevated)
                .onChange(of: selected) { _, _ in showAll = false }
            }

            Spacer(minLength: 0)
        }
    }
}

/// One icon cell. Hover and selection share a single fill on a single shape — never two layers.
///
/// **`accessibilityLabel` has no default (T-674).** It used to default to `nil`, so the "More
/// icons" cell got a name and the plain glyph cells silently did not — a name nobody adds. The
/// next icon cell now fails to build instead of failing a sweep.
private struct ListEditorIconCell: View {
    let icon: String
    let isSelected: Bool
    let tint: Color
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? tint : Theme.muted)
                .frame(width: 28, height: 28)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(isSelected ? tint.opacity(0.35) : Color.clear, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .cadenceControlLabel(accessibilityLabel)
    }

    private var fill: Color {
        if isSelected { return tint.opacity(0.16) }
        return isHovered ? Theme.surfaceHover : Theme.surfaceElevated
    }
}

// MARK: - Check row

/// A boolean field row. The mark is right-aligned and reads as "on", so a setting that is off
/// leaves nothing behind — a switch would have been the loudest thing in the sheet.
struct ListEditorCheckRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            TaskInspectorFieldRow(label: label, reservesIconSlot: false) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .opacity(isOn ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: TaskInspectorFieldRowMetrics.hoverCornerRadius))
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Context row

/// **T-559.** Which context a list is filed in, as a field row in every macOS list sheet.
///
/// Before this row existed the Mac could not put a list in "no context" and could not take one out
/// of a context either: `CreateListSheet` took a non-optional `Context` decided by whichever
/// sidebar "+" opened it, and the two edit sheets had no context control at all. iOS's list editor
/// offers a "None" row in new and edit mode alike, so a context-less list arrives on the Mac by
/// sync — and after T-534, T-538 and T-558 the Mac can finally *see* every one of them under
/// "Other". This is the other half: seeing a row you cannot correct is not much better than not
/// seeing it.
///
/// The list under the popover is `CadenceContextPickerList`, unchanged — the archive rule, the
/// "show the assigned one even when it is no longer offerable" rule, the sort and the untitled
/// fallback are `CadenceContextPickerSupport`'s and are not respelled here. The row's *value* is
/// read from the same helper as the popover's rows, which is the agreement T-446 exists to keep:
/// a trigger and a menu that resolve the selection separately are how a picker comes to show
/// "None" over a context it is about to save.
struct ListEditorContextRow: View {
    let contexts: [Context]
    @Binding var selectedID: UUID?

    @State private var showPicker = false

    /// The same words the picker's own "none" row uses, so the row does not rename the thing the
    /// user is about to tap.
    static let noneTitle = "No context"

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: "Context",
            reservesIconSlot: false,
            valueText: CadenceContextPickerSupport.selectionTitle(
                from: contexts,
                selectedID: selectedID,
                noneTitle: Self.noneTitle
            ),
            isSet: selectedID != nil
        ) {
            showPicker.toggle()
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            ScrollView {
                CadenceContextPickerList(
                    contexts: contexts,
                    selectedID: $selectedID,
                    onPick: { showPicker = false }
                )
            }
            .frame(width: 260)
            .frame(maxHeight: 320)
            .background(Theme.surface)
        }
    }
}

// MARK: - Apple Calendar row

/// **T-441.** The row asks `CadenceCalendarLink` what the link is, rather than looking one title up
/// in the pickable calendars and calling everything it misses "None".
///
/// It used to render `selectedTitle ?? "None"` over `calendars` alone — which is
/// `CalendarManager.availableCalendars`, the visible subset — so a link to a calendar the user had
/// merely hidden from Cadence was indistinguishable from no link at all, and so was a link whose
/// calendar Apple Calendar had deleted. See that type for why the two lists are both parameters.
///
/// **T-464.** The value and the menu are now one decision instead of two. T-441 fixed the value and
/// left the popover offering `calendars`, so the row could say "Team (Hidden)" over a menu with no
/// Team in it: the user could read the state and could not act on it, and the only reachable move
/// was "None" — the overwrite T-441 exists to prevent, performed by the user instead of by the
/// code. Both halves now come off one `CadenceCalendarLink`, which is also what stops the two from
/// forming separate opinions about which calendars are hidden.
struct ListEditorCalendarRow: View {
    /// The calendars Cadence is showing — `CalendarManager.availableCalendars`, the same visible
    /// subset every other calendar affordance in Settings offers.
    let calendars: [EKCalendar]
    /// Every calendar EventKit has, hidden ones included. The row's value needs it to tell hidden
    /// from missing, and the picker's offer needs it to hand back the hidden calendar already
    /// linked. Feeding this the visible subset is the T-441 bug.
    let allCalendars: [EKCalendar]
    @Binding var selectedID: String

    @State private var showPicker = false
    /// **T-624.** Device-local, never synced: the identifiers this Mac has seen EventKit carry.
    /// Read here rather than passed in because both edit sheets host this row and neither has any
    /// other use for the record.
    @AppStorage(CadenceCalendarLinkObservations.observedCalendarIDsKey) private var observedCalendarIDsRaw = ""

    /// **T-624.** `.synced`, because `selectedID` starts life as `Area.linkedCalendarID` or
    /// `Project.linkedCalendarID` — a CloudKit-synced property holding an identifier Apple
    /// documents as local to one device. Without this the row read "no calendar here carries it" as
    /// a deletion and printed `CadenceCalendarLinkHealth.missingLinkTitle` over a picker whose every
    /// option overwrites the link the device that made it is still using. Settings' broken-links
    /// card was taught this and this row was not, so the false alarm had simply moved here.
    private var link: CadenceCalendarLink {
        CadenceCalendarLink(
            linkedCalendarID: selectedID,
            allCalendars: allCalendars,
            visibleCalendars: calendars,
            evidence: .synced(
                observedCalendarIDs: CadenceCalendarLinkObservations.observedCalendarIDs(
                    from: observedCalendarIDsRaw
                )
            )
        )
    }

    private var linkState: CadenceCalendarLinkRowState { link.rowState }

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: CadenceAppleCalendarNaming.integrationSectionTitle,
            reservesIconSlot: false,
            valueText: linkState.valueText,
            isSet: linkState.isSet
        ) {
            showPicker.toggle()
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            ScrollView {
                CadenceCalendarPickerList(
                    calendars: link.pickableCalendars(from: allCalendars),
                    selectedID: $selectedID,
                    link: link,
                    onPick: { showPicker = false }
                )
            }
            .frame(width: 260)
            .frame(maxHeight: 320)
            .background(Theme.surface)
        }
    }
}

// MARK: - Lifecycle

enum ListEditorLifecycleChoice: CaseIterable {
    case active, completed, archived

    /// What this choice does to the work still open in the list, as a value rather than as a branch
    /// inside a sheet's `apply(_:)`.
    ///
    /// Both edit sheets used to switch on the choice and call
    /// `completeRemainingActiveTasks` / `cancelRemainingActiveTasks` by hand. Swapping those two
    /// calls — so that archiving a list marked its leftovers *done* and completing one cancelled
    /// them — kept every test green, because the only assertion counted both names over the whole
    /// file and both counts were unchanged (`docs/TODO.md` T-161). The mapping is here, and
    /// `CadenceListWindDownSurfaceTests` states it as an equality.
    ///
    /// `nil` for `.active`: reopening a list settles nothing. That is deliberately not
    /// `.done`-with-an-empty-set, because "there is no wind-down" and "wind down zero tasks" are
    /// different sentences and only the first one is true here.
    var windDownOutcome: CadenceWindDownOutcome? {
        switch self {
        case .active: return nil
        case .completed: return .done
        case .archived: return .cancelled
        }
    }
}

/// Status as one field row plus a picker.
///
/// The picker carries the active/completed axis only. Archiving is a footer button, and offering it
/// here as well would be two routes to one state — the row reports where the list is (including
/// paused, cancelled, or archived, which the picker never sets), the buttons move it.
struct ListEditorStatusRow: View {
    /// "Area" or "Project" — the picker explains what happens to *this* kind of list.
    let noun: String
    /// Shown as the row value. Not derived from the choices: a project can also be paused or
    /// cancelled, and the row must not claim otherwise.
    let statusLabel: String
    let onSelect: (ListEditorLifecycleChoice) -> Void

    @State private var showPicker = false

    var body: some View {
        TaskInspectorFieldButtonRow(
            label: "Status",
            reservesIconSlot: false,
            valueText: statusLabel,
            isSet: true
        ) {
            showPicker.toggle()
        }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                choiceRow(
                    .active,
                    title: "Active",
                    subtitle: "Show \(noun.lowercased()) in the sidebar."
                )
                choiceRow(
                    .completed,
                    title: "Completed",
                    subtitle: "Hide it from the active sidebar but keep it restorable."
                )
            }
            .padding(6)
            .frame(width: 300)
            .background(Theme.surface)
        }
    }

    @ViewBuilder
    private func choiceRow(_ choice: ListEditorLifecycleChoice, title: String, subtitle: String) -> some View {
        Button {
            showPicker = false
            onSelect(choice)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .modifier(InspectorPickerHover(cornerRadius: TaskInspectorFieldRowMetrics.hoverCornerRadius))
    }
}

/// Footer archive/unarchive button. Archiving is recoverable from Settings → Lists, so this is a
/// neutral action button — it must not borrow Delete's red.
struct ListEditorArchiveButton: View {
    let isArchived: Bool
    /// "Area" or "Project", used for the help text only.
    let noun: String
    let action: () -> Void

    var body: some View {
        CadenceActionButton(
            title: isArchived ? "Unarchive" : "Archive",
            // Deliberately not `arrow.up.bin`: a bin glyph next to a red Delete would read as
            // undoing a deletion rather than returning a list to the sidebar.
            systemImage: isArchived ? "tray.and.arrow.up" : "archivebox",
            role: .secondary,
            size: .compact,
            tint: Theme.muted,
            action: action
        )
        .accessibilityLabel(isArchived ? "Unarchive" : "Archive")
        .help(
            isArchived
                ? "Return this \(noun.lowercased()) to the sidebar."
                : "Store this \(noun.lowercased()) away and cancel its remaining tasks. Recoverable from Settings → Lists."
        )
    }
}

/// Footer delete button. Sits opposite Cancel/Save, away from both the field well and the confirm
/// button.
struct ListEditorDeleteButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        CadenceActionButton(
            title: title,
            systemImage: "trash",
            role: .destructive,
            size: .compact,
            action: action
        )
    }
}
#endif
