#if os(iOS)
import SwiftUI

// MARK: - Live state

/// One touch on the blue `+`, while it is happening.
///
/// **The decisions are not in here.** Everything this object does when an event arrives is ask
/// `CadenceCapturePressResolver` or `CadenceCapturePaletteGeometry` and store the answer, so the
/// three-way disambiguation T-171 specifies is a value with tests rather than a gesture closure
/// nobody can mutate. What is genuinely stateful — where the finger is, which segment is lit,
/// whether the hold timer is still armed — lives here and nowhere else.
///
/// Coordinates are **global**. The button, the finger and every drop target report in the same
/// space, and the one view that has to draw in its own space converts once, at the edge.
@Observable
final class iOSCaptureInteraction {
    private(set) var phase: CadenceCapturePressPhase = .idle
    /// The button's centre, in global coordinates. The palette is anchored here rather than at the
    /// touch point so the arc does not shift under a thumb that landed off-centre.
    var anchor: CGPoint = .zero
    private(set) var finger: CGPoint = .zero
    private(set) var selection: CadenceCaptureAction?
    /// Which registered drop target the finger is over, while dragging.
    private(set) var dropTargetID: UUID?

    private var origin: CGPoint = .zero
    private var holdTask: Task<Void, Never>?

    var isPressing: Bool { phase != .idle }
    var showsPalette: Bool { phase == .palette }
    var isDragging: Bool { phase == .dragging }

    /// The offset of the finger from the button, which is what the geometry speaks in.
    var paletteOffset: CGSize {
        CGSize(width: finger.x - anchor.x, height: finger.y - anchor.y)
    }

    private var travel: CGFloat {
        hypot(finger.x - origin.x, finger.y - origin.y)
    }

    // MARK: Events

    func began(at location: CGPoint) {
        origin = location
        finger = location
        selection = nil
        dropTargetID = nil
        phase = .pressing
        armHold()
    }

    func moved(to location: CGPoint) {
        guard phase != .idle else { return }
        finger = location
        let next = CadenceCapturePressResolver.phase(afterMovingTo: travel, from: phase)
        if next != phase {
            phase = next
            // A press that became a drag has nothing left for the timer to do, and leaving it armed
            // is how a palette blooms mid-drag. The resolver refuses that transition anyway — this
            // is the belt beside that brace, not the rule itself.
            if next == .dragging { cancelHold() }
        }
        refreshDerivedState()
    }

    func ended() -> CadenceCapturePressOutcome {
        cancelHold()
        let outcome = CadenceCapturePressResolver.outcome(atEndOf: phase, selection: selection)
        reset()
        return outcome
    }

    func cancel() {
        cancelHold()
        reset()
    }

    // MARK: Internals

    private func reset() {
        phase = .idle
        selection = nil
        iOSCaptureDragTargeting.shared.currentTargetID = nil
        dropTargetID = nil
    }

    private func armHold() {
        cancelHold()
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(CadenceCapturePaletteMetrics.holdDelay))
            guard !Task.isCancelled, let self else { return }
            let next = CadenceCapturePressResolver.phase(afterHoldFrom: self.phase, distance: self.travel)
            guard next != self.phase else { return }
            self.phase = next
            self.refreshDerivedState()
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
    }

    /// Which segment is lit, or which row a drag is over — both are functions of the phase and the
    /// finger, so they are recomputed rather than tracked.
    private func refreshDerivedState() {
        switch phase {
        case .palette:
            selection = CadenceCapturePaletteGeometry.action(atOffset: paletteOffset)
            dropTargetID = nil
            iOSCaptureDragTargeting.shared.currentTargetID = nil
        case .dragging:
            selection = nil
            let target = CadenceCaptureDropHitTest.target(
                at: finger,
                among: iOSNewTaskDropFrameRegistry.shared.candidates()
            )
            dropTargetID = target
            iOSCaptureDragTargeting.shared.currentTargetID = target
        case .idle, .pressing:
            selection = nil
            dropTargetID = nil
            iOSCaptureDragTargeting.shared.currentTargetID = nil
        }
    }
}

/// Which drop target the custom drag is over, and nothing else.
///
/// Split from `iOSNewTaskDropFrameRegistry` deliberately, because the two have opposite observation
/// needs. Frames churn on every scrolled frame and **must not** be observed — a registry every task
/// row watched would re-render the list continuously. The targeted id changes only when the finger
/// crosses a row boundary, and every drop target *has* to watch it to draw its own insertion ghost.
/// One `@Observable` holding both would have given the churn to the watchers.
@Observable
final class iOSCaptureDragTargeting {
    static let shared = iOSCaptureDragTargeting()

    var currentTargetID: UUID?

    private init() {}
}

/// Where every create-task drop target is on screen, and what it would seed.
///
/// The system drag resolves its own hit-testing; a custom one cannot, so the targets publish
/// themselves here. Deliberately **not** `@Observable` — see `iOSCaptureDragTargeting`. It is a
/// plain shared class for the same reason `SidebarDragContext` is: a drag source and its targets are
/// arbitrarily far apart in the tree and have nothing to pass between them.
@MainActor
final class iOSNewTaskDropFrameRegistry {
    static let shared = iOSNewTaskDropFrameRegistry()

    struct Placement {
        var dropKey: String
        var listName: String
    }

    private var frames: [UUID: CGRect] = [:]
    private var placements: [UUID: Placement] = [:]
    /// Ids whose surface is currently the one on screen. See `iOSNewTaskDropTargetsAreLive`.
    private var live: Set<UUID> = []
    /// Registration order, so `CadenceCaptureDropHitTest`'s tie-break resolves to the later one.
    private var order: [UUID] = []

    private init() {}

    func setFrame(_ frame: CGRect, for id: UUID) {
        if frames[id] == nil { order.append(id) }
        frames[id] = frame
    }

    func setPlacement(dropKey: String, listName: String, for id: UUID) {
        placements[id] = Placement(dropKey: dropKey, listName: listName)
    }

    func setLive(_ isLive: Bool, for id: UUID) {
        if isLive { live.insert(id) } else { live.remove(id) }
    }

    func unregister(_ id: UUID) {
        frames[id] = nil
        placements[id] = nil
        live.remove(id)
        order.removeAll { $0 == id }
    }

    func candidates() -> [CadenceCaptureDropHitTest.Candidate] {
        order.compactMap { id in
            guard live.contains(id), let frame = frames[id] else { return nil }
            return CadenceCaptureDropHitTest.Candidate(id: id, frame: frame)
        }
    }

    func placement(for id: UUID) -> Placement? { placements[id] }
}

extension EnvironmentValues {
    /// Whether create-task drop targets under this subtree are the ones a finger can actually reach.
    ///
    /// **The compact shell keeps every visited tab alive at zero opacity**, which is what preserves
    /// scroll position and in-progress edits across a tab switch — and it means All Tasks is still
    /// laying its rows out while you are looking at a list detail in More. A system drag never
    /// noticed, because UIKit hit-tests the real view hierarchy and a hidden tab is
    /// `allowsHitTesting(false)`. A custom drag hit-tests *published frames*, so without this every
    /// hidden surface would be a live target sitting exactly on top of the visible one.
    ///
    /// Defaults to `true`, so iPad and every other host stays correct without opting in.
    @Entry var iOSNewTaskDropTargetsAreLive: Bool = true
}

// MARK: - What a released press asks the shell for

/// The one thing a finished press hands back. The gesture never presents anything itself: a palette
/// segment can open a sheet, a full-screen cover, or a composer seeded by whatever the drag landed
/// on, and those are the host's business.
struct iOSCaptureRequest: Identifiable {
    enum Kind {
        case task(CadenceTaskComposerSeed)
        case event
        case note
    }

    let id = UUID()
    let kind: Kind
}

// MARK: - The button

/// The blue `+`, carrying the whole T-171 gesture.
///
/// **Why this is not a `Button` with `.onDrag` bolted on, which is what it replaced.** The two
/// behaviours the ticket asks for both want the same first 350ms, and `UIDragInteraction` cannot
/// share it. Its lift *is* a long press — 326–349ms of stillness, measured — so a palette opening at
/// the same moment would open on top of a lifted drag preview; and it flatly refuses to lift when
/// the finger moves first, which is exactly the "quick press then move → a drag immediately" case.
/// You also cannot hand a live touch to UIKit's drag machinery halfway through a gesture you are
/// already tracking, so "the palette gives up and it becomes a drag" has no system spelling at all.
/// One `DragGesture(minimumDistance: 0)` that decides for itself is the only shape that can hold
/// all three, and the deciding is `CadenceCapturePressResolver`'s.
///
/// The tap survives because it is synthesised: a press that neither escaped the slop nor outlived
/// the hold resolves to `.tap` and opens unscoped capture, exactly as the `Button` did.
///
/// **It is still not a tab.** No `CadenceCompactTab` case, no selected state, no label — the same
/// three absences the `Button` had, which is what stops the centre control ever reading as a fifth
/// destination.
struct iOSCaptureRadialMenuButton: View {
    let diameter: CGFloat
    let interaction: iOSCaptureInteraction
    let onRequest: (iOSCaptureRequest) -> Void

    var body: some View {
        iOSCircularAddButtonFace(diameter: diameter)
            .scaleEffect(interaction.isPressing ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: interaction.isPressing)
            .contentShape(Circle())
            .onGeometryChange(for: CGPoint.self) { proxy in
                let frame = proxy.frame(in: .global)
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { interaction.anchor = $0 }
            .gesture(press)
            // The palette's arrival, and each segment it slides onto. T-171 asks for the first by
            // name; the second is what makes sliding legible when a thumb is covering the tile it
            // just reached.
            .sensoryFeedback(trigger: interaction.showsPalette) { was, now in
                (now && !was) ? .impact(weight: .medium) : nil
            }
            .sensoryFeedback(.selection, trigger: interaction.selection)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("New Task")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double tap to capture a task. Touch and hold for event and note.")
            // VoiceOver cannot slide around a radial menu, so the segments are also plain actions.
            // Same three commitments, reached without the gesture.
            .accessibilityAction(named: Text(CadenceCaptureAction.event.title)) {
                onRequest(iOSCaptureRequest(kind: .event))
            }
            .accessibilityAction(named: Text(CadenceCaptureAction.note.title)) {
                onRequest(iOSCaptureRequest(kind: .note))
            }
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if interaction.phase == .idle {
                    interaction.began(at: value.location)
                } else {
                    interaction.moved(to: value.location)
                }
            }
            .onEnded { value in
                interaction.moved(to: value.location)
                let target = interaction.dropTargetID
                commit(interaction.ended(), droppedOn: target)
            }
    }

    private func commit(_ outcome: CadenceCapturePressOutcome, droppedOn target: UUID?) {
        switch outcome {
        case .tap:
            onRequest(iOSCaptureRequest(kind: .task(CadenceTaskComposerSeed())))
        case .action(let action):
            onRequest(iOSCaptureRequest(kind: request(for: action)))
        case .drop:
            onRequest(iOSCaptureRequest(kind: .task(seed(forTarget: target))))
        case .dismissed, .none:
            break
        }
    }

    private func request(for action: CadenceCaptureAction) -> iOSCaptureRequest.Kind {
        switch action {
        case .task: return .task(CadenceTaskComposerSeed())
        case .event: return .event
        case .note: return .note
        }
    }

    /// A drop that landed on nothing seeds nothing, which is the same composer a tap opens. That is
    /// the degrade-to-the-tap rule `CadenceTaskDropSupport.dropKey(for:)` already applies to a row
    /// with nothing to inherit, applied one level up.
    private func seed(forTarget target: UUID?) -> CadenceTaskComposerSeed {
        guard
            let target,
            let placement = iOSNewTaskDropFrameRegistry.shared.placement(for: target)
        else { return CadenceTaskComposerSeed() }
        return CadenceTaskDropSupport.seed(
            forDropKey: placement.dropKey,
            todayKey: DateFormatters.todayKey()
        )
    }
}

// MARK: - The palette and the drag preview

/// Everything the gesture draws away from the button: the semicircle of segments, and the puck a
/// drag carries.
///
/// It sits at the **shell's** level rather than on the button, because both of them have to be able
/// to leave the tab bar — a palette drawn inside a 46pt bar row would be clipped to it, and a drag
/// preview has the whole screen to cross. It hit-tests nothing; the gesture that owns the touch is
/// still the button's.
struct iOSCaptureRadialMenuOverlay: View {
    let interaction: iOSCaptureInteraction
    @State private var originInGlobal: CGPoint = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            if interaction.showsPalette {
                scrim
                palette
            }
            if interaction.isDragging {
                dragPuck
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: {
            originInGlobal = $0
        }
    }

    /// Dims the page under an open palette. It is the only thing here that is not a segment: a
    /// radial menu drawn over a bright task list is unreadable, and the scrim is also what says the
    /// screen is waiting on this choice.
    private var scrim: some View {
        Theme.scrim
            .ignoresSafeArea()
            .transition(.opacity)
    }

    private var palette: some View {
        ZStack {
            ForEach(Array(CadenceCaptureAction.allCases.enumerated()), id: \.element.id) { index, action in
                segment(action, at: index)
            }
        }
        .position(local(interaction.anchor))
    }

    private func segment(_ action: CadenceCaptureAction, at index: Int) -> some View {
        let isSelected = interaction.selection == action
        return VStack(spacing: 5) {
            Image(systemName: action.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.onColor : action.tint)
                .frame(width: 52, height: 52)
                .background {
                    Circle()
                        .fill(isSelected ? action.tint : Theme.surfaceElevated)
                        .overlay {
                            Circle().strokeBorder(
                                isSelected ? action.tint : Theme.borderSubtle,
                                lineWidth: 1
                            )
                        }
                }
                .shadow(color: Theme.overlayCardShadow, radius: 8, y: 3)

            Text(action.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
        }
        .scaleEffect(isSelected ? 1.12 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isSelected)
        .offset(CadenceCapturePaletteGeometry.offset(forSegment: index))
    }

    /// What a drag carries. The insertion ghost on the row underneath is the other half of the
    /// feedback and is drawn by the target, so this stays a puck rather than restating the
    /// placement the target is already naming.
    private var dragPuck: some View {
        iOSCircularAddButtonFace(diameter: 44)
            .opacity(0.92)
            .position(local(interaction.finger))
    }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - originInGlobal.x, y: point.y - originInGlobal.y)
    }
}

extension View {
    /// Installs the palette and drag preview above a shell's content. One call, above everything,
    /// for the same reason `iOSTaskInspectorHost()` is one call: a control that has to draw outside
    /// its own container cannot be hosted by that container.
    func iOSCaptureRadialMenuLayer(_ interaction: iOSCaptureInteraction) -> some View {
        overlay {
            iOSCaptureRadialMenuOverlay(interaction: interaction)
        }
    }
}
#endif
