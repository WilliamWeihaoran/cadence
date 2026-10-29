import SwiftUI

/// What one completion circle draws for one glyph and one fill reading — the decision, with no
/// view attached, so a test host on either platform can read it ([[T-8411]]).
///
/// Three faces and only three: an open ring, a settled disc, and a ring filling clockwise. A
/// pending glyph handed no progress — the frame before the first tick, or any frame under Reduce
/// Motion ([[T-8412]]) — is an open ring carrying the glyph's own mark (the green dot, the grey
/// cross), which is how "pending" reads still.
nonisolated struct CadenceTaskCompletionCircleFace: Equatable {
    enum Ring: Equatable {
        /// The 1.6pt `strokeBorder` ring, no fill.
        case open
        /// A solid disc in the tint, its mark knocked out in `Theme.onColor(for:)`.
        case filled
        /// A faint track with the tint revealed clockwise from twelve o'clock, `0...1`.
        case filling(Double)
    }

    let ring: Ring
    let mark: CadenceTaskCompletionGlyph.Mark
    /// Only a filling ring hides its mark: it lands when `CadenceTaskCompletionTiming` says so.
    let showsMark: Bool

    static func resolve(glyph: CadenceTaskCompletionGlyph, progress: Double?) -> Self {
        let isPending = glyph.state == .pendingCompletion || glyph.state == .pendingCancellation
        if let progress, isPending {
            let fill = min(max(progress, 0), 1)
            return Self(
                ring: .filling(fill),
                mark: glyph.state == .pendingCancellation ? .cross : .checkmark,
                showsMark: CadenceTaskCompletionTiming.showsConfirmation(at: fill)
            )
        }
        return Self(ring: glyph.isFilled ? .filled : .open, mark: glyph.mark, showsMark: true)
    }
}

/// **The** task completion circle, on both platforms ([[T-8411]]).
///
/// macOS drew the resting circle as an SF Symbol and its fill as a trimmed, centred `.stroke`
/// (`TaskCompletionProgressGlyph`); iOS drew both as inset `strokeBorder` primitives with the fill
/// masked by a wedge (the iOS circle view this replaces). Both asked `CadenceTaskCompletionTiming`, so only
/// the pixels differed — and no hardware or input constraint names that difference, so under
/// [[T-8201]] it was drift. This is iOS's drawing, now the only one: the macOS task row, Kanban
/// card, board column header and timeline block draw it, as does every iOS circle.
///
/// The fill is the same inset ring as the resting one, masked by a wedge rather than trimmed, so
/// it cannot sit half a line outside the track it traces ([[T-489]]) — which is what retired the
/// last two `.stroke(` carve-outs `CadenceStrokeBorderSweepTests` kept.
///
/// What may differ per platform is the **diameter**, which each host passes from its own type
/// ramp (a 15pt macOS row title against a 13pt iOS one); the line, the marks and the faces do not.
/// The hit area is the host's, and is where pointer and touch legitimately differ.
struct CadenceTaskCompletionCircle: View {
    /// One line weight at every diameter, as iOS has always drawn it. macOS's four call sites had
    /// passed 1.5 / 1.6 / 1.8 / 2 for the fill alone, against an SF Symbol ring of its own weight.
    static let lineWidth: CGFloat = 1.6

    let glyph: CadenceTaskCompletionGlyph
    var diameter: CGFloat = 13
    /// How far a deferred completion (or cancellation) has run, `0...1`, or `nil` for a still
    /// circle. Only a pending glyph reads it.
    var progress: Double? = nil

    init(glyph: CadenceTaskCompletionGlyph, diameter: CGFloat = 13, progress: Double? = nil) {
        self.glyph = glyph
        self.diameter = diameter
        self.progress = progress
    }

    /// For the controls with no `AppTask` behind them — a `Subtask`'s tick, and the decorative
    /// circles in the swipe tray and the schedule placeholder row.
    init(isDone: Bool, tint: Color, diameter: CGFloat = 13) {
        self.init(glyph: .binary(isDone: isDone, tint: tint), diameter: diameter)
    }

    private var face: CadenceTaskCompletionCircleFace {
        .resolve(glyph: glyph, progress: progress)
    }

    var body: some View {
        let face = face
        ZStack {
            switch face.ring {
            case .open:
                Circle()
                    .strokeBorder(glyph.tint, lineWidth: Self.lineWidth)
                markView(face.mark)
            case .filled:
                Circle()
                    .fill(glyph.tint)
                markView(face.mark)
            case .filling(let fill):
                Circle()
                    .strokeBorder(glyph.tint.opacity(0.18), lineWidth: Self.lineWidth)
                Circle()
                    .strokeBorder(glyph.tint, lineWidth: Self.lineWidth)
                    .mask(CadenceTaskCompletionWedge(fraction: fill))
                markView(face.mark)
                    .opacity(face.showsMark ? 1 : 0)
                    .scaleEffect(face.showsMark ? 1 : 0.65)
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: face.showsMark)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// The mark is drawn, never stamped as a symbol's knockout: on a filled disc that means
    /// `Theme.onColor(for:)` against the tint that fills it (T-855 — white on `Theme.green` reads
    /// 2.08:1, under even the 3:1 non-text floor).
    @ViewBuilder
    private func markView(_ mark: CadenceTaskCompletionGlyph.Mark) -> some View {
        switch mark {
        case .none:
            EmptyView()
        case .dot:
            Circle()
                .fill(glyph.tint)
                .frame(width: diameter * 0.44, height: diameter * 0.44)
        case .checkmark:
            markSymbol("checkmark", scale: 0.6)
        case .cross:
            markSymbol("xmark", scale: 0.55)
        }
    }

    private func markSymbol(_ name: String, scale: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: diameter * scale, weight: .bold))
            .foregroundStyle(glyph.isFilled ? Theme.onColor(for: glyph.tint) : glyph.tint)
    }
}

/// The swept part of a completion fill: a pie slice from twelve o'clock, clockwise, `fraction` of
/// the way round. Used only as a mask over `CadenceTaskCompletionCircle`'s ring.
private struct CadenceTaskCompletionWedge: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * min(max(fraction, 0), 1)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
