#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// The circular add affordance itself — the glyph, the fill, the shadow and the touch target, and
/// nothing else.
///
/// It is deliberately split from the page-level wiring below. The button takes a bare `action`
/// closure and knows nothing about seeds, sheets or which screen it is on, so the drag behaviour
/// (drag the button onto a section, a list or a date and the created task picks that destination up)
/// attaches *outside* it, rather than to inlined `Button`s that would each need the same gestures
/// bolted on and would drift apart the moment one of them did.
///
/// **Both capture buttons in the app are this one.** The iPad's corner `+` and the iPhone tab bar's
/// centre `+` are the same action in deliberately different *places*, which is a layout difference
/// the rules allow; they had also drifted into different *looks* — 56pt/22pt semibold/shadow r16 y7
/// against 44pt/19pt **bold**/shadow r10 y4 — which is not a placement consequence of anything. The
/// size is: a 56pt circle does not fit inside a 46pt tab-bar row between four tab items, while a
/// button floating over a page has nothing to fit inside. So `diameter` is the one parameter, and
/// the glyph and the shadow are **derived** from it rather than passed, at the ratios the 56pt
/// button already used — which is what stops the next size from becoming the next look.
///
/// The macOS counterpart is `FloatingNewTaskButton`; same shape, same job, same reasoning about why
/// a page — unlike a board column — opens the full composer rather than an inline row.
struct iOSCircularAddButton: View {
    let action: () -> Void
    /// Defaults to the floating size; the tab bar passes its own. See `floatingDiameter`.
    var diameter: CGFloat = iOSCircularAddButton.floatingDiameter
    var accessibilityLabel: String = "New Task"

    /// 56pt, comfortably over the 44pt floor, and the diameter the trailing/bottom padding of the
    /// floating placement is measured against.
    static let floatingDiameter: CGFloat = 56
    /// Clearance from the page's trailing and bottom edges.
    static let edgeInset: CGFloat = 22
    /// What a scroll view under the button has to keep free so its last row is never buried.
    static var scrollClearance: CGFloat { floatingDiameter + edgeInset * 2 }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: diameter * 0.39, weight: .semibold))
                .foregroundStyle(Theme.onColor)
                .frame(width: diameter, height: diameter)
                .background(Theme.blue)
                .clipShape(Circle())
                .shadow(color: Theme.blue.opacity(0.3), radius: diameter * 0.29, x: 0, y: diameter * 0.125)
                .contentShape(Circle())
        }
        .buttonStyle(.iosPressable)
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
            .contentMargins(.bottom, isRegularWidth ? iOSCircularAddButton.scrollClearance : 0, for: .scrollContent)
            .overlay(alignment: .bottomTrailing) {
                if isRegularWidth {
                    iOSCircularAddButton { isPresented = true }
                        .iOSNewTaskDragSource(onCreated: onCreated)
                        // The corner inset belongs to the placement, not to the button: the tab
                        // bar's copy is centred in a row and must not carry it.
                        .padding(.trailing, iOSCircularAddButton.edgeInset)
                        .padding(.bottom, iOSCircularAddButton.edgeInset)
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

/// The gap a create-task drag opens: a dashed placeholder that says a new task lands here, and
/// names the placement it will inherit.
///
/// It is **not** a selection fill on the row underneath. The row is read for its coordinates —
/// list, section, dates — and nothing is done to it, so lighting it up the way a tap-to-select
/// lights a row up says the wrong thing about the wrong object. What is actually about to happen
/// is an insertion, so what the drag shows is an insertion.
///
/// The caption is the honest half. See `CadenceTaskDropSupport.placementCaption(forDropKey:…)` for
/// why the *position* of this block promises nothing and the words have to carry the claim.
private struct iOSNewTaskGhostRow: View {
    let caption: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text("New task")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                if !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.subdued)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 44, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                .fill(Theme.blue.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                        .strokeBorder(
                            Theme.blue.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                }
        }
        .accessibilityLabel(caption.isEmpty ? "New task" : "New task, \(caption)")
    }
}

/// Makes a view a destination for a create-task drag.
///
/// **The feedback is an insertion, not a highlight.** The row this attaches to used to take a blue
/// fill while targeted, which read as "this task is the subject" when the row is only a source of
/// coordinates — nothing is done to it. Instead a ghost block opens *below* the row and the rows
/// under it part to make room, which is the shape of what is actually about to happen.
///
/// **The gap opens below the pointed row, always — there is no upper-half/lower-half split.** Two
/// reasons, and the first is the binding one: a drop seeds *placement*, never `order`.
/// `TaskCreationService` appends and the surface's own sort decides the final index, so "above this
/// one" and "below this one" is a distinction the code cannot honour, and drawing it would be a
/// promise broken the moment the sheet closes. One gap in one place keeps the claim at the level
/// the code can keep — "a new task joins this neighbourhood, with these attributes", which the
/// ghost's caption states in words. Second, below is the stable choice: the ghost grows *away* from
/// the finger, so nothing moves under the pointer and the target cannot oscillate between two rows
/// the way a mid-row split would.
///
/// The ghost is also the view's **only** added layer, at one radius — the rows this lands on carry
/// no background of their own, and the fill that used to sit under them is gone rather than joined.
///
/// `onDrop(of:)` filters by content type synchronously, so this lights up for a create-task drag
/// and for nothing else: a task-reorder or bundle drag is plain text and never reaches it. See
/// `UTType.cadenceNewTaskDrag`.
private struct iOSNewTaskDropTargetModifier: ViewModifier {
    /// Evaluated at drop time, not at layout time, so a row whose list or date changed while the
    /// drag was in flight seeds what it now says rather than what it said when it last rendered.
    /// Read once more while targeted, to caption the ghost with the same answer.
    let dropKey: () -> String
    /// The destination list's display name. A `list:` key carries a UUID; only the call site can
    /// turn that into something a person reads.
    let listName: () -> String
    /// Aligns the ghost with the host row's own content inset, so the gap looks like part of the
    /// list rather than a floating card.
    let horizontalInset: CGFloat

    @State private var isTargeted = false
    /// Separate from `isTargeted` so the open/close is driven by an explicit
    /// `withAnimation(.spring(…))`, the same way reorder moves are animated everywhere else.
    @State private var showsGhost = false

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            if showsGhost {
                iOSNewTaskGhostRow(
                    caption: CadenceTaskDropSupport.placementCaption(
                        forDropKey: dropKey(),
                        todayKey: DateFormatters.todayKey(),
                        listName: listName()
                    )
                )
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 6)
                .transition(.opacity)
            }
        }
        .onDrop(of: [.cadenceNewTaskDrag], isTargeted: $isTargeted) { providers in
            handleDrop(providers, dropKey: dropKey())
        }
        .onChange(of: isTargeted) { _, targeted in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                showsGhost = targeted
            }
        }
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
    /// in `CadenceTaskDropSupport`; `listName` resolves the one thing that vocabulary cannot carry.
    func iOSNewTaskDropTarget(
        horizontalInset: CGFloat = 11,
        listName: @escaping () -> String = { "" },
        dropKey: @escaping () -> String
    ) -> some View {
        modifier(
            iOSNewTaskDropTargetModifier(
                dropKey: dropKey,
                listName: listName,
                horizontalInset: horizontalInset
            )
        )
    }
}
#endif
