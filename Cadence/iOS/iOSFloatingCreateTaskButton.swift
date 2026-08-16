#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// The circular add affordance itself — the glyph, the fill, the shadow and the touch target, and
/// nothing else.
///
/// It is deliberately split from the page-level wiring below. The button takes a bare `action`
/// closure and knows nothing about seeds, sheets or which screen it is on, so the drag behaviour
/// planned for it (drag the button onto a section, a list or a date and the created task picks that
/// destination up) attaches *here*, once, rather than to four inlined `Button`s that would each need
/// the same gestures bolted on and would drift apart the moment one of them did.
///
/// The macOS counterpart is `FloatingNewTaskButton`; same shape, same job, same reasoning about why
/// a page — unlike a board column — opens the full composer rather than an inline row.
struct iOSFloatingAddButton: View {
    let action: () -> Void
    var accessibilityLabel: String = "New Task"

    /// 56pt, comfortably over the 44pt floor, and the diameter the trailing/bottom padding below is
    /// measured against.
    static let diameter: CGFloat = 56
    /// Clearance from the page's trailing and bottom edges.
    static let edgeInset: CGFloat = 22
    /// What a scroll view under the button has to keep free so its last row is never buried.
    static var scrollClearance: CGFloat { diameter + edgeInset * 2 }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.onColor)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Theme.blue)
                .clipShape(Circle())
                .shadow(color: Theme.blue.opacity(0.3), radius: 16, x: 0, y: 7)
        }
        .buttonStyle(.iosPressable)
        .padding(.trailing, Self.edgeInset)
        .padding(.bottom, Self.edgeInset)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Pins `iOSFloatingAddButton` to a page's bottom-trailing corner at **regular width only**, and
/// opens `iOSCreateTaskSheet` seeded for that page.
///
/// **Regular width only, on purpose.** On compact width the tab bar already carries a centre `+`
/// that opens the same sheet, and a corner button beside it would be the second affordance for one
/// action on one screen — the duplication this app has removed repeatedly. Compact surfaces lost
/// their inline capture bar and gained nothing; the bar's job moved to the bar that was already
/// there. The size-class check lives in here rather than at the four call sites so no page can
/// forget it.
///
/// **The seed is a value in.** Inbox seeds nothing, a list detail seeds its own list, Today seeds
/// today's do date. Keeping it a plain `CadenceTaskComposerSeed` parameter is also what lets a
/// future drop target hand one in — the destination the button is dropped on simply produces a
/// different seed, and nothing about the presentation has to change.
///
/// **Nothing hides under it.** `contentMargins(.bottom:for: .scrollContent)` insets the scrollable
/// content of the page's scroll views by the button's whole footprint, so the last row can always be
/// brought out from under it. It is done here, once, rather than as per-screen bottom padding —
/// which is what would silently break the next time the button changed size.
private struct iOSFloatingCreateTaskLayer: ViewModifier {
    let seed: CadenceTaskComposerSeed
    let onCreated: ((AppTask) -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isPresented = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, isRegularWidth ? iOSFloatingAddButton.scrollClearance : 0, for: .scrollContent)
            .overlay(alignment: .bottomTrailing) {
                if isRegularWidth {
                    iOSFloatingAddButton { isPresented = true }
                        .iOSNewTaskDragSource(onCreated: onCreated)
                }
            }
            .sheet(isPresented: $isPresented) {
                iOSCreateTaskSheet(seed: seed, onCreated: onCreated)
            }
    }
}

extension View {
    /// Overlays the page-level task-creation button in the bottom-trailing corner. See
    /// `iOSFloatingCreateTaskLayer` for why it is regular-width only and why the seed is a value.
    func iOSFloatingCreateTaskButton(
        seed: CadenceTaskComposerSeed = CadenceTaskComposerSeed(),
        onCreated: ((AppTask) -> Void)? = nil
    ) -> some View {
        modifier(iOSFloatingCreateTaskLayer(seed: seed, onCreated: onCreated))
    }
}

// MARK: - Drag to create

/// Makes a create-task button draggable, and presents the composer seeded from wherever it lands.
///
/// **`.onDrag`/`.onDrop`, not `.draggable`/`.dropDestination`, and the choice is not cosmetic.**
/// The `.draggable` family installs gesture recognizers that delay tap recognition across the
/// whole enclosing `ScrollView`; that is why the sidebar's drag was rewritten onto
/// `.onDrag`/`.onDrop` with a `DropDelegate` after it killed the sidebar cards' taps. The control
/// this attaches to is a **button whose tap is the affordance nearly every use reaches for**, so a
/// mechanism that can blunt a tap is disqualified before anything else is weighed. `.onDrag` is a
/// `UIDragInteraction`: its long-press recognizer fails the instant the finger lifts, so the
/// `Button` underneath still fires immediately. Drag is an addition here, not a replacement.
///
/// The sheet is presented by the *source*, not by the target. A drop can land on a row inside a
/// list inside a tab, none of which owns task creation; routing the resolved seed back through
/// `CadenceTaskDropCoordinator` to the button that started the drag keeps one presentation site
/// per button and means a drop-created task goes through exactly the same `iOSCreateTaskSheet` —
/// and so the same `TaskCreationService` — as a tap-created one.
private struct iOSNewTaskDragSourceModifier: ViewModifier {
    let onCreated: ((AppTask) -> Void)?

    /// Identifies this button for the lifetime of the view, so a drop can find its way home.
    @State private var sourceID = UUID()
    @State private var request: CadenceTaskDropCoordinator.Request?

    func body(content: Content) -> some View {
        content
            .onDrag {
                CadenceTaskDropPayload.itemProvider(sourceID: sourceID)
            }
            .onChange(of: CadenceTaskDropCoordinator.shared.pending?.id) { _, _ in
                if let delivered = CadenceTaskDropCoordinator.shared.consume(for: sourceID) {
                    request = delivered
                }
            }
            .sheet(item: $request) { pending in
                iOSCreateTaskSheet(seed: pending.seed, onCreated: onCreated)
            }
    }
}

/// Makes a view a destination for a create-task drag.
///
/// The fill is the view's **only** hover layer — the rows this lands on carry no background of
/// their own — and it is drawn at `Theme.radiusControl`, so nothing stacks a second highlight at a
/// second radius on top of it.
///
/// `onDrop(of:)` filters by content type synchronously, so this lights up for a create-task drag
/// and for nothing else: a task-reorder or bundle drag is plain text and never reaches it. See
/// `UTType.cadenceNewTaskDrag`.
private struct iOSNewTaskDropTargetModifier: ViewModifier {
    /// Evaluated at drop time, not at layout time, so a row whose list or date changed while the
    /// drag was in flight seeds what it now says rather than what it said when it last rendered.
    let dropKey: () -> String

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(Theme.blue.opacity(isTargeted ? 0.16 : 0))
            }
            .onDrop(of: [.cadenceNewTaskDrag], isTargeted: $isTargeted) { providers in
                handleDrop(providers, dropKey: dropKey())
            }
            .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private func handleDrop(_ providers: [NSItemProvider], dropKey: String) -> Bool {
        let identifier = UTType.cadenceNewTaskDrag.identifier
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(identifier)
        }) else { return false }

        let todayKey = DateFormatters.todayKey()
        provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
            guard let data, let payload = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                CadenceTaskDropCoordinator.shared.deliver(
                    payload: payload,
                    dropKey: dropKey,
                    todayKey: todayKey
                )
            }
        }
        return true
    }
}

extension View {
    /// See `iOSNewTaskDragSourceModifier` — including why this is `.onDrag` and not `.draggable`.
    func iOSNewTaskDragSource(onCreated: ((AppTask) -> Void)? = nil) -> some View {
        modifier(iOSNewTaskDragSourceModifier(onCreated: onCreated))
    }

    /// Offers this view as a destination for a create-task drag. `dropKey` speaks the vocabulary
    /// in `CadenceTaskDropSupport`.
    func iOSNewTaskDropTarget(dropKey: @escaping () -> String) -> some View {
        modifier(iOSNewTaskDropTargetModifier(dropKey: dropKey))
    }
}
#endif
