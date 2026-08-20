import SwiftUI

/// Which kind of surface an inline empty is sitting on.
///
/// Two cases, not three. `CadencePageHeaderSurface` needs `.compact` / `.regular` / `.desktop`
/// because a page header scales with the pane containing it, and an iPad pane is not an iPhone
/// screen. This is a row among rows: it takes its size from the rows beside it, and iPhone and iPad
/// draw the same rows. Splitting it further would be inventing a difference the app does not have.
nonisolated enum CadenceInlineEmptySurface: String, CaseIterable, Sendable {
    case desktop
    case touch
}

/// The figures behind `CadenceInlineEmpty`, in a value type outside every platform conditional so
/// `CadenceTests` can pin them.
nonisolated struct CadenceInlineEmptyMetrics: Equatable, Sendable {
    let textSize: CGFloat
    let padding: CGFloat

    /// **The size difference is kept, and it is the one thing here that was not drift.**
    ///
    /// macOS drew 12 and iOS drew 13. That looks like a fork until you put each next to the rows it
    /// sits among: Cadence's desktop body is 13pt and its touch body is 14, so both platforms had
    /// this line exactly one point under the rows it is standing in for — the same relationship,
    /// twice, with different inputs. Flattening it to one number would have made the empty line
    /// louder than the content on one platform or quieter on the other, which is the mistake
    /// `5aa11dc` avoided by giving macOS a third page-header tier instead of folding it into
    /// `.regular`.
    ///
    /// The padding follows for the same reason: a touch surface spends more space around the same
    /// line of text.
    static func metrics(for surface: CadenceInlineEmptySurface) -> CadenceInlineEmptyMetrics {
        switch surface {
        case .desktop: return CadenceInlineEmptyMetrics(textSize: 12, padding: 12)
        case .touch: return CadenceInlineEmptyMetrics(textSize: 13, padding: 14)
        }
    }

    /// **`Theme.radiusControl` wins, and only iOS had it.** macOS's copy was a bare `9`, which is
    /// on no scale in `Theme` — the radius ramp is 10 / 18 / 22. A named token beats a literal that
    /// happens to be a point off one.
    static let cornerRadius: CGFloat = Theme.radiusControl

    /// The wash behind it, as an opacity of `Theme.surfaceElevated`. Both copies already drew this;
    /// it is here so the next change lands once.
    static let backgroundOpacity: Double = 0.38
}

/// The one-line "nothing here" that sits *inside* a section, on both platforms — as opposed to
/// `EmptyStateView` / `iOSEmptyPanel`, which own a whole pane.
///
/// This was `CommitmentInlineEmpty` and `iOSInlineEmpty`. The first already lived in
/// `Shared/Components/`, which is the sharpest version of what T-136 is about: the shared folder is
/// not a shared *component* when the file around it opens `#if os(macOS)`, so iOS could not use it
/// and wrote its own — under an `iOS` prefix, with a doc comment reading "iOS counterpart of
/// `CommitmentInlineEmpty`", and nothing in the diff to say a component had just been duplicated.
struct CadenceInlineEmpty: View {
    let text: String
    let surface: CadenceInlineEmptySurface

    private var metrics: CadenceInlineEmptyMetrics {
        CadenceInlineEmptyMetrics.metrics(for: surface)
    }

    var body: some View {
        Text(text)
            .font(.system(size: metrics.textSize))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(metrics.padding)
            .background(Theme.surfaceElevated.opacity(CadenceInlineEmptyMetrics.backgroundOpacity))
            .clipShape(
                RoundedRectangle(cornerRadius: CadenceInlineEmptyMetrics.cornerRadius, style: .continuous)
            )
    }
}
