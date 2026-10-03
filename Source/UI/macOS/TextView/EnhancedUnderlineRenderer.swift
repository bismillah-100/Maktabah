//
//  EnhancedUnderlineRenderer.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 03/10/26.
//

import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(Cocoa)
import Cocoa
#endif

enum EnhancedUnderlineRenderer {
    /// Metrik proporsional stabil (satuan: em, dikali font.pointSize)
    enum Metrics {
        static let offsetEm: CGFloat = 0.32 // pas di bawah kasrah normal
        static let thicknessEm: CGFloat = 0.05
        static let minSkipInkGap: CGFloat = 1.5 // pt minimal agar bernapas di font kecil
        static let skipInkGapEm: CGFloat = 0.05
        static let yOffsetDivisor: CGFloat = 1.5
    }

    private struct UnderlineSpan {
        let rect: CGRect
        let color: CGColor
        let baseline: CGFloat
        let gap: CGFloat
    }

    private struct SkipInkContext {
        let line: NSTextLineFragment
        let ctLine: CTLine
        let span: UnderlineSpan
        let drawPoint: CGPoint
    }

    static func drawUnderlines(
        for element: NSTextElement,
        lineFragments: [NSTextLineFragment],
        drawPoint: CGPoint,
        in context: CGContext
    ) {
        guard let paragraph = element as? NSTextParagraph else { return }
        let attrString = paragraph.attributedString
        guard attrString.length > 0, hasEnhancedUnderline(in: attrString) else { return }

        for line in lineFragments {
            let lineRange = line.characterRange
            guard lineRange.length > 0 else { continue }

            let spans = resolveSpans(for: line, attrString: attrString, drawPoint: drawPoint)
            guard !spans.isEmpty else { continue }

            let ctLine = CTLineCreateWithAttributedString(attrString.attributedSubstring(from: lineRange))

            for span in spans {
                context.saveGState()
                context.setFillColor(span.color)
                context.fill(span.rect)
                context.restoreGState()

                let skipContext = SkipInkContext(
                    line: line,
                    ctLine: ctLine,
                    span: span,
                    drawPoint: drawPoint
                )
                applySkipInk(context: skipContext, in: context)
            }
        }
    }

    private static func hasEnhancedUnderline(in attrString: NSAttributedString) -> Bool {
        var found = false
        attrString.enumerateAttribute(
            .enhancedUnderline,
            in: NSRange(location: 0, length: attrString.length),
            options: []
        ) { val, _, stop in
            if val != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private static func resolveSpans(
        for line: NSTextLineFragment,
        attrString: NSAttributedString,
        drawPoint: CGPoint
    ) -> [UnderlineSpan] {
        var spans: [UnderlineSpan] = []
        let lineRange = line.characterRange

        attrString.enumerateAttribute(.enhancedUnderline, in: lineRange) { underlineVal, underRange, _ in
            guard underlineVal != nil else { return }

            attrString.enumerateAttribute(.font, in: underRange) { fontVal, fontRange, _ in
                guard let font = (fontVal as? PlatformFont) ??
                        (attrString.attribute(.font, at: fontRange.location, effectiveRange: nil) as? PlatformFont)
                else { return }

                if let span = createSpan(
                    font: font,
                    fontRange: fontRange,
                    line: line,
                    attrString: attrString,
                    drawPoint: drawPoint
                ) {
                    spans.append(span)
                }
            }
        }
        return spans
    }

    private static func createSpan(
        font: PlatformFont,
        fontRange: NSRange,
        line: NSTextLineFragment,
        attrString: NSAttributedString,
        drawPoint: CGPoint
    ) -> UnderlineSpan? {
        let nsStr = attrString.string as NSString
        let size = font.pointSize
        let ctFont = font as CTFont
        let rawThickness = CTFontGetUnderlineThickness(ctFont)

        #if os(macOS)
        let defaultColor = PlatformColor.labelColor
        #else
        let defaultColor = PlatformColor.label
        #endif
        let color = (attrString.attribute(.underlineColor, at: fontRange.location, effectiveRange: nil) as? PlatformColor)
            ?? (attrString.attribute(.foregroundColor, at: fontRange.location, effectiveRange: nil) as? PlatformColor)
            ?? defaultColor

        let thickness = max(rawThickness, max(1.0, size * Metrics.thicknessEm))
        let offsetBelowBaseline = size * Metrics.offsetEm
        let baseline = drawPoint.y + line.typographicBounds.origin.y + line.glyphOrigin.y
        let underlineY = baseline + offsetBelowBaseline - (thickness / Metrics.yOffsetDivisor)

        var start = fontRange.location
        var end = fontRange.location + fontRange.length
        while start < end, isWhitespace(char: nsStr.character(at: start)) { start += 1 }
        while end > start, isWhitespace(char: nsStr.character(at: end - 1)) { end -= 1 }
        guard end > start else { return nil }

        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        for i in start...end {
            let pt = line.locationForCharacter(at: i)
            minX = min(minX, pt.x)
            maxX = max(maxX, pt.x)
        }

        let width = maxX - minX
        guard width > 0, minX.isFinite, maxX.isFinite else { return nil }

        let rect = CGRect(
            x: drawPoint.x + line.typographicBounds.origin.x + minX,
            y: underlineY,
            width: width,
            height: thickness
        )
        let gap = max(Metrics.minSkipInkGap, size * Metrics.skipInkGapEm)

        return UnderlineSpan(rect: rect, color: color.cgColor, baseline: baseline, gap: gap)
    }

    private static func applySkipInk(context: SkipInkContext, in cgContext: CGContext) {
        let range = context.line.characterRange
        guard range.length > 0 else { return }

        let delta = context.line.locationForCharacter(at: range.location).x
            - CTLineGetOffsetForStringIndex(context.ctLine, 0, nil)
        let baseX = context.drawPoint.x + context.line.typographicBounds.origin.x + delta
        let span = context.span
        let bandTopBelowBaseline = span.rect.minY - span.baseline

        cgContext.saveGState()
        cgContext.clip(to: [span.rect.insetBy(dx: -span.gap, dy: -span.gap)])
        cgContext.setBlendMode(.clear)

        guard let runs = CTLineGetGlyphRuns(context.ctLine) as? [CTRun] else {
            cgContext.restoreGState()
            return
        }

        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            guard let fontAny = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName],
                  let font = fontAny as? PlatformFont else { continue }
            let ctFont = font as CTFont

            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var rects = [CGRect](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, glyphs, &rects, count)

            for i in 0..<count {
                let r = rects[i]
                guard r.width > 0, r.height > 0 else { continue }

                let glyphMinX = baseX + positions[i].x + r.minX
                let glyphMaxX = baseX + positions[i].x + r.maxX
                guard glyphMaxX > span.rect.minX - span.gap && glyphMinX < span.rect.maxX + span.gap else { continue }

                let descent = -(positions[i].y + r.minY)
                guard descent > bandTopBelowBaseline - span.gap else { continue }

                var t = CGAffineTransform(translationX: baseX + positions[i].x, y: span.baseline).scaledBy(x: 1, y: -1)
                if let path = CTFontCreatePathForGlyph(ctFont, glyphs[i], &t) {
                    let stroked = path.copy(
                        strokingWithWidth: span.gap * 2,
                        lineCap: .round,
                        lineJoin: .round,
                        miterLimit: 10
                    )
                    cgContext.addPath(stroked)
                    cgContext.fillPath()
                }
            }
        }
        cgContext.restoreGState()
    }

    private static func isWhitespace(char: unichar) -> Bool {
        char <= 0x20 || char == 0x00A0 || char == 0x200B
    }
}
