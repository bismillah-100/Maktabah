//
//  CachedArabicLayoutFragment.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 01/07/26.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(Cocoa)
import Cocoa
#endif

class CachedArabicLayoutFragment: NSTextLayoutFragment {
    /// Cache level grafis
    private var cachedLayer: CGLayer?

    override func draw(at point: CGPoint, in context: CGContext) {
        let bounds = renderingSurfaceBounds
        guard bounds.width > 0, bounds.height > 0 else {
            super.draw(at: point, in: context)
            return
        }

        if cachedLayer == nil {
            cachedLayer = CGLayer(context, size: bounds.size, auxiliaryInfo: nil)

            if let layerContext = cachedLayer?.context {
                let drawPoint = CGPoint(x: -bounds.minX, y: -bounds.minY)

                super.draw(at: drawPoint, in: layerContext)
            }
        }

        if let layer = cachedLayer {
            let targetPoint = CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY)
            context.draw(layer, at: targetPoint)
        }
    }

    /// Hapus cache jika paragraf ini diedit, di-highlight, atau berubah font
    override func invalidateLayout() {
        super.invalidateLayout()
        cachedLayer = nil
    }
}

#if os(macOS)
extension IbarotTextView: NSTextLayoutManagerDelegate {
    /// Fungsi ini akan dipanggil otomatis oleh TextKit 2 setiap kali ia butuh merender paragraf baru
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        return CachedArabicLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
#else
extension iOSCustomIbarotTextView: NSTextLayoutManagerDelegate {
    /// Fungsi ini akan dipanggil otomatis oleh TextKit 2 setiap kali ia butuh merender paragraf baru
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        return CachedArabicLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
#endif

extension NSTextLayoutManager {
    func ensureFullDocumentLayout() {
        enumerateTextLayoutFragments(
            from: documentRange.location,
            options: [.ensuresLayout]
        ) { _ in true }
    }
}

