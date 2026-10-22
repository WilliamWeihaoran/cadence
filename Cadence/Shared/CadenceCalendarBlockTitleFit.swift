import CoreGraphics
import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// How many lines a timed calendar block's title may take, on **both** platforms (T-3315, T-3323).
///
/// A two-line `Text` wraps on word boundaries only while every word fits its line. A word wider
/// than the line makes the text system break it between characters — "Fron" / "t e…" on a cascaded
/// Mac block 55pt wide (T-3315), and the same construction on the iOS event and task blocks
/// (T-3323). Apple Calendar never splits a word there; it ends the title in an ellipsis. So a title
/// holding a word that cannot fit gets **one** line, tail-truncated, and every other title keeps
/// the block's own wrap limit. One line is never more than the wrap limit, so neither platform's
/// cascade threshold (`CadenceCalendarOverlapLayout.iOSEventHeaderHeight`, T-3193) nor the Mac's
/// covered-row rule (T-3166) can be moved by it.
///
/// It lives in Shared so the Mac and iOS blocks measure with one implementation, and so the iOS
/// geometry below — which no macOS test can render — is still arithmetic the macOS test target can
/// evaluate.
enum CadenceCalendarBlockTitleFit {

    // MARK: The rule

    /// The widest single word of `title` in the system font at `fontSize`, semibold — the weight
    /// both platforms' block titles draw at.
    static func widestWordWidth(_ title: String, fontSize: CGFloat) -> CGFloat {
        #if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        #elseif canImport(UIKit)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        #endif
        return title.split(whereSeparator: \.isWhitespace)
            .map { ceil((String($0) as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
    }

    /// The title's `.lineLimit`: 1 when its widest word is wider than `availableWidth`, otherwise
    /// `wrapLimit`. Pair it with `.truncationMode(.tail)`.
    static func titleLineLimit(for title: String, fontSize: CGFloat, availableWidth: CGFloat, wrapLimit: Int) -> Int {
        widestWordWidth(title, fontSize: fontSize) > availableWidth ? 1 : wrapLimit
    }

    /// The laid-out width of an SF Symbol at `pointSize`, for a glyph that shares the title's row.
    /// A missing symbol must not widen the title past its column, so the fallback is generous.
    static func symbolWidth(_ name: String, pointSize: CGFloat, bold: Bool = false) -> CGFloat {
        #if canImport(AppKit)
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: bold ? .bold : .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        #elseif canImport(UIKit)
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: bold ? .bold : .semibold)
        let image = UIImage(systemName: name, withConfiguration: configuration)
        #endif
        return ceil(image?.size.width ?? pointSize * 1.5)
    }

    // MARK: The iOS blocks' title row (T-3323)

    // Mirrored from `iOSCalendarEventBlock` and `iOSTimelineTaskBlock` in
    // `Cadence/iOS/iOSCalendarTimelineViews.swift`, the same way `CadenceCalendarOverlapLayout`
    // mirrors their row heights; `CadenceCalendarOverlapLayoutTests` pins each to its literal.

    /// Both blocks: `.padding(.horizontal, 7)` around the row.
    static let iOSHorizontalPadding: CGFloat = 7
    /// Both blocks: `HStack(alignment: .top, spacing: 6)` between the leading glyph and the title.
    static let iOSLeadingGlyphSpacing: CGFloat = 6
    /// The event block's leading glyph: `Image(systemName: "calendar")` at metadata base 10.
    static let iOSEventGlyphSymbolName = "calendar"
    static let iOSEventGlyphBaseSize: CGFloat = 10
    /// The task block's completion circle sits in a frame of metadata base 11.
    static let iOSTaskCircleFrameBaseSize: CGFloat = 11
    /// The task block clears the trailing "back to Today's tasks" control by 26pt when it has one.
    static let iOSClearTimeTrailingInset: CGFloat = 26
    /// Both blocks' title: metadata base 11, semibold — `CadenceCalendarOverlapLayout.eventTitleFontSize`.
    static let iOSTitleBaseSize: CGFloat = CadenceCalendarOverlapLayout.eventTitleFontSize

    /// The width the iOS event block's title is laid out in: the block less the rail, the padding,
    /// the calendar glyph and the row's spacing.
    static func iOSEventTitleWidth(blockWidth: CGFloat, glyphWidth: CGFloat) -> CGFloat {
        max(
            0,
            blockWidth - CadenceCalendarEventStyle.railWidth - iOSHorizontalPadding * 2
                - glyphWidth - iOSLeadingGlyphSpacing
        )
    }

    /// The width the iOS task block's title is laid out in: the block (which has no rail) less the
    /// padding, the completion circle's frame, the row's spacing and, when the block carries one,
    /// the trailing control's inset.
    static func iOSTaskTitleWidth(blockWidth: CGFloat, circleFrameWidth: CGFloat, hasClearTimeControl: Bool) -> CGFloat {
        max(
            0,
            blockWidth - iOSHorizontalPadding * 2 - circleFrameWidth - iOSLeadingGlyphSpacing
                - (hasClearTimeControl ? iOSClearTimeTrailingInset : 0)
        )
    }
}
