#if os(iOS)
import SwiftUI

/// The circular add affordance itself — the glyph, the fill, the shadow and the touch target, and
/// nothing else. No `Button`, and no gesture.
///
/// It is deliberately split from the page-level wiring below, and from the gesture in
/// `iOSCaptureRadialMenuButton`. Both placements draw this and neither owns it, so the drag
/// behaviour (drag the button onto a section, a list or a date and the created task picks that
/// destination up) and the hold-for-palette behaviour attach *outside* it rather than to inlined
/// copies that would each need the same gestures bolted on and would drift apart the moment one of
/// them did.
///
/// **Both capture buttons in the app are this one, and since T-282 that is true of the gesture as
/// well as the look.** The iPad's corner `+` and the iPhone tab bar's centre `+` are the same
/// control in deliberately different *places*, which is a layout difference the rules allow. They
/// had drifted into different *looks* — 56pt/22pt semibold/shadow r16 y7 against 44pt/19pt
/// **bold**/shadow r10 y4 — and then, under T-171, into different *capabilities*: the phone's held
/// open a palette of Task / Event / Note and the iPad's could capture nothing but a task. Neither
/// is a placement consequence. The size is: a 56pt circle does not fit inside a 46pt tab-bar row
/// between four tab items, while a button floating over a page has nothing to fit inside. So
/// `diameter` is the one parameter, the glyph and the shadow are **derived** from it rather than
/// passed, at the ratios the 56pt button already used, and the one thing the two placements still
/// choose for themselves is which way the palette's arc opens — see
/// `CadenceCapturePalettePlacement`.
///
/// This used to be two types: a `Button` wrapper called `iOSCircularAddButton` and the bare circle
/// beside it. The wrapper is gone rather than left unused, because a `Button` competes for the raw
/// touch the gesture needs and a type that still compiles while nothing calls it is exactly how the
/// page header's `subtitle` parameter survived three deletions. The name moved down to the circle,
/// which is what it always described.
///
/// The macOS counterpart is `FloatingNewTaskButton`; same shape, same job, same reasoning about why
/// a page — unlike a board column — opens the full composer rather than an inline row.
struct iOSCircularAddButton: View {
    let diameter: CGFloat

    /// 56pt, comfortably over the 44pt floor, and the diameter the trailing/bottom padding of the
    /// floating placement is measured against.
    static let floatingDiameter: CGFloat = 56
    /// Clearance from the page's trailing and bottom edges.
    static let edgeInset: CGFloat = 22
    /// What a scroll view under the button has to keep free so its last row is never buried.
    static var scrollClearance: CGFloat { floatingDiameter + edgeInset * 2 }

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: diameter * 0.39, weight: .semibold))
            .foregroundStyle(Theme.onColor)
            .frame(width: diameter, height: diameter)
            .background(Theme.blue)
            .clipShape(Circle())
            .shadow(color: Theme.blue.opacity(0.3), radius: diameter * 0.29, x: 0, y: diameter * 0.125)
            .contentShape(Circle())
    }
}

/// Pins the capture `+` to a page's bottom-trailing corner at **regular width only**, and gives it
/// the same three things the tab bar's centre `+` has: a tap that opens `iOSCreateTaskSheet` seeded
/// for that page, a hold that opens the capture palette, and a drag onto a row that seeds the
/// composer from wherever it lands.
///
/// **Regular width only, on purpose.** On compact width the tab bar already carries a centre `+`
/// that does the same three things, and a corner button beside it would be the second affordance
/// for one action on one screen — the duplication this app has removed repeatedly. Compact surfaces lost
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
    /// One live touch on this page's `+`, and the mailbox the host presents from. Per page rather
    /// than per app: several pages can be alive at once on iPad, and only the one under the finger
    /// may open a composer — which is what the old `CadenceTaskDropCoordinator` routing existed to
    /// arrange, and what separate state gives for free.
    @State private var interaction = iOSCaptureInteraction(placement: .bottomTrailing)

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, isRegularWidth ? iOSCircularAddButton.scrollClearance : 0, for: .scrollContent)
            .overlay(alignment: .bottomTrailing) {
                if isRegularWidth {
                    iOSCaptureRadialMenuButton(
                        diameter: iOSCircularAddButton.floatingDiameter,
                        interaction: interaction,
                        baseSeed: seed
                    )
                    // The corner inset belongs to the placement, not to the button: the tab
                    // bar's copy is centred in a row and must not carry it.
                    .padding(.trailing, iOSCircularAddButton.edgeInset)
                    .padding(.bottom, iOSCircularAddButton.edgeInset)
                }
            }
            .iOSCaptureHost(interaction, onCreated: onCreated)
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

// MARK: - Where a create-task drag can land

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
/// It lights up for a create-task drag and for nothing else, because the only thing that can point
/// at it is `iOSCaptureInteraction`'s own hit test against `iOSNewTaskDropFrameRegistry` — a
/// task-reorder or bundle drag is a `Transferable` string travelling through SwiftUI's own
/// machinery and never touches this registry at all.
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

    /// Separate from `isCustomDragTarget` so the open/close is driven by an explicit
    /// `withAnimation(.spring(…))`, the same way reorder moves are animated everywhere else.
    @State private var showsGhost = false
    /// This target's name in `iOSNewTaskDropFrameRegistry`, stable for the view's lifetime.
    @State private var registrationID = UUID()
    /// See `iOSNewTaskDropTargetsAreLive`. A tab the compact shell is keeping alive at zero opacity
    /// still lays its rows out, so without this every hidden task surface would publish frames that
    /// overlap the visible one and a drag could land on a row nobody can see.
    @Environment(\.iOSNewTaskDropTargetsAreLive) private var isLive

    func body(content: Content) -> some View {
        // Read once per render rather than per event: the drag hit-tests against a registry, so
        // the registry has to have been *told* what this row would seed. SwiftUI re-runs this body
        // when the row's model changes, so the published answer is the same one the row is drawing.
        let placementKey = dropKey()
        let placementListName = listName()
        let isCustomDragTarget = iOSCaptureDragTargeting.shared.currentTargetID == registrationID

        return VStack(spacing: 0) {
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
        // **The target is the whole block, not the glyphs inside it.** Without this a stack only
        // hit-tests where it actually drew something — so `iOSTaskGroupHeader`, an `HStack` of an
        // eyebrow label, a `Spacer` and a count badge, accepted a dropped `+` on the two ends of
        // the row and refused the ~250pt of empty header between them. A task row was unaffected
        // only because it already carries its own `contentShape(Rectangle())`; the header, having
        // no tap of its own, had nothing to make it whole. Declared here rather than at each host
        // so the answer cannot differ by call site — and so the ghost's own strip is part of the
        // target while it is open.
        .contentShape(Rectangle())
        // **One mechanism reaches this target, since T-282.** Both `+`s now carry T-171's custom
        // gesture, which cannot ask UIKit to hit-test for it and so hit-tests against published
        // frames instead. The iPad's corner button used `.onDrag` until the palette arrived there;
        // `UIDragInteraction`'s lift *is* a ~350ms long press, so it wants the same window the
        // palette does and the two cannot share a touch. The `.onDrop` half went with it rather
        // than being left as a second, sourceless path into the same ghost.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            iOSNewTaskDropFrameRegistry.shared.setFrame(frame, for: registrationID)
        }
        .onChange(of: [placementKey, placementListName], initial: true) { _, _ in
            iOSNewTaskDropFrameRegistry.shared.setPlacement(
                dropKey: placementKey,
                listName: placementListName,
                for: registrationID
            )
        }
        // Liveness is a flag on the entry rather than a gate on registration, because a tab
        // becoming visible again produces no geometry change — the row never moved — so a target
        // that had skipped publishing its frame would stay unreachable for the rest of the session.
        .onChange(of: isLive, initial: true) { _, live in
            iOSNewTaskDropFrameRegistry.shared.setLive(live, for: registrationID)
        }
        .onDisappear {
            iOSNewTaskDropFrameRegistry.shared.unregister(registrationID)
        }
        .onChange(of: isCustomDragTarget) { _, targeted in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                showsGhost = targeted
            }
        }
    }
}

extension View {
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

    /// The group-header flavour: offers this view as a destination **only** when the group has
    /// something to hand over.
    ///
    /// A `nil` identity, or one `CadenceTaskDropSupport.dropKey(forGroup:)` resolves to nothing —
    /// Overdue, Past Do, Active, Completed — registers no target at all, so the header does not
    /// light up rather than lighting up and seeding nothing. That is the deliberate difference from
    /// the row target, which always has a list to give; see `dropKey(forGroup:)`.
    @ViewBuilder
    func iOSNewTaskDropTarget(
        group identity: CadenceTaskGroupDropIdentity?,
        horizontalInset: CGFloat = 0
    ) -> some View {
        if let identity, let key = CadenceTaskDropSupport.dropKey(forGroup: identity) {
            iOSNewTaskDropTarget(
                horizontalInset: horizontalInset,
                listName: { CadenceTaskDropSupport.listName(forGroup: identity) },
                dropKey: { key }
            )
        } else {
            self
        }
    }
}
#endif
