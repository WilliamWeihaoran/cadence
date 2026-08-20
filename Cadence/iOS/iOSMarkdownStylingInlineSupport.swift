#if os(iOS)
import SwiftUI
import UIKit

/// **Inline styling: emphasis spans, links, wiki/task references, image references and hashtags.**
///
/// A document-wide sweep, run after every line and block pass so it can read the ambient font a
/// heading or list line already set. Which runs it may touch is `MarkdownStyleRanges`' answer, which
/// spans exist is `MarkdownInlineSpanSupport`'s, and which marker characters disappear is
/// `MarkdownInlineMarkerRanges`' — all three in `Services/`. What is left here is the attributes.
extension iOSMarkdownStyler {
    static func styleInline(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange]
    ) {
        let inlineCodeRanges = MarkdownInlineSpanSupport.codeRanges(in: markdown)

        // Which runs get styled, in what order, and which markers disappear is
        // `MarkdownInlineSpanSupport`'s decision — a platform-free one the macOS test target can
        // actually run. This method is only the drawing half of it.
        for span in MarkdownInlineSpanSupport.spans(in: markdown, excluding: excludedRanges) {
            apply(span, to: storage)
        }

        styleImageLink(storage, markdown: markdown, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleMarkdownLinks(storage, markdown: markdown, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleWikiReferences(storage, markdown: markdown, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
        styleHashtags(storage, markdown: markdown, excludedRanges: excludedRanges, inlineCodeRanges: inlineCodeRanges)
    }

    private static func apply(_ span: MarkdownInlineSpan, to storage: NSMutableAttributedString) {
        let content = span.contentRange
        switch span.kind {
        case .boldItalic:
            storage.addAttribute(.font, value: italicFont(from: boldFont(at: content.location, in: storage)), range: content)

        case .bold:
            storage.addAttribute(.font, value: boldFont(at: content.location, in: storage), range: content)

        case .italic:
            storage.addAttribute(.font, value: italicFont(from: font(at: content.location, in: storage)), range: content)

        case .strikethrough:
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.dim),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ], range: content)

        case .code:
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: UIColor(Theme.amberLight),
                .backgroundColor: UIColor(Theme.surfaceElevated).withAlphaComponent(0.65),
                .cadenceMarkdownInlineCode: true
            ], range: content)

        case .highlight:
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.amberLight),
                .backgroundColor: UIColor(Theme.amber).withAlphaComponent(0.18)
            ], range: content)
        }

        for markerRange in span.markerRanges {
            hide(storage, markerRange)
        }
    }

    private static func styleImageLink(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        for reference in MarkdownInlineMarkerRanges.imageReferences(in: markdown) {
            let full = reference.fullRange
            guard shouldStyleInline(full, excluding: excludedRanges, protecting: inlineCodeRanges) else { continue }

            storage.addAttributes([
                .foregroundColor: UIColor(Theme.blueLight),
                .backgroundColor: UIColor(Theme.blue).withAlphaComponent(0.12),
                .font: UIFont.systemFont(ofSize: font(at: full.location, in: storage).pointSize, weight: .semibold)
            ], range: reference.hasLabel ? reference.labelRange : full)

            if reference.hasLabel {
                MarkdownInlineMarkerRanges.hiddenRanges(for: reference).forEach { hide(storage, $0) }
            } else {
                storage.addAttributes([
                    .foregroundColor: UIColor(Theme.dim),
                    .font: monoFont
                ], range: reference.idRange)
            }
        }
    }

    private static func styleMarkdownLinks(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        for link in MarkdownLinkSupport.linkRanges(in: markdown) {
            guard shouldStyleInline(link.fullRange, excluding: excludedRanges, protecting: inlineCodeRanges) else { continue }
            let label = link.labelRange
            let url = link.urlRange
            let full = link.fullRange
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.blueLight),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: label)
            if let linkURL = link.url {
                storage.addAttribute(.link, value: linkURL, range: label)
            }
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.dim),
                .font: monoFont
            ], range: url)
            MarkdownInlineMarkerRanges.hiddenRanges(forLink: full, label: label, url: url)
                .forEach { hide(storage, $0) }
        }
    }

    private static func styleWikiReferences(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        for referenceRange in MarkdownReferenceDisplaySupport.referenceRanges(in: markdown) {
            let full = referenceRange.fullRange
            guard shouldStyleInline(full, excluding: excludedRanges, protecting: inlineCodeRanges) else { continue }
            guard full.location != NSNotFound, full.length >= 4 else { continue }
            if storage.attribute(.cadenceMarkdownTaskEmbed, at: full.location, effectiveRange: nil) is MarkdownTaskEmbedLayoutInfo {
                continue
            }

            let reference = referenceRange.display
            let styledRange = referenceRange.displayRange
            let referenceColor = reference.kind == .task ? UIColor(Theme.greenLight) : UIColor(Theme.blueLight)
            let referenceBackground = reference.kind == .task
                ? UIColor(Theme.green).withAlphaComponent(0.10)
                : UIColor(Theme.blue).withAlphaComponent(0.10)
            storage.addAttributes([
                .foregroundColor: referenceColor,
                .backgroundColor: referenceBackground,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: styledRange)
            if let referenceURL = MarkdownReferenceDisplaySupport.url(for: reference.target) {
                storage.addAttribute(.link, value: referenceURL, range: styledRange)
            }
            if reference.kind == .task {
                storage.addAttribute(
                    .font,
                    value: UIFont.systemFont(ofSize: font(at: styledRange.location, in: storage).pointSize, weight: .semibold),
                    range: styledRange
                )
            }
            MarkdownInlineMarkerRanges.hiddenRanges(
                forReference: full,
                hiddenPrefixUTF16Length: reference.hiddenPrefixUTF16Length
            ).forEach { hide(storage, $0) }
        }
    }

    private static func styleHashtags(
        _ storage: NSMutableAttributedString,
        markdown: String,
        excludedRanges: [NSRange],
        inlineCodeRanges: [NSRange]
    ) {
        for range in MarkdownInlineMarkerRanges.hashtagRanges(in: markdown) {
            guard shouldStyleInline(range, excluding: excludedRanges, protecting: inlineCodeRanges) else { continue }
            storage.addAttributes([
                .foregroundColor: UIColor(Theme.greenLight),
                .backgroundColor: UIColor(Theme.green).withAlphaComponent(0.10)
            ], range: range)
        }
    }

    private static func shouldStyleInline(
        _ range: NSRange,
        excluding excludedRanges: [NSRange],
        protecting protectedRanges: [NSRange] = []
    ) -> Bool {
        MarkdownInlineSpanSupport.shouldStyle(range, excluding: excludedRanges, protecting: protectedRanges)
    }
}
#endif
