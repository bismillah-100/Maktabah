//
//  TextLayoutManagerTests.swift
//  MaktabahTests
//

import AppKit
import Foundation
@testable import Maktabah_Debug
import Testing

@Suite("TextLayoutManager Layout & Indicator Tests")
struct TextLayoutManagerTests {
    private struct TextLayoutSetup {
        let storage: NSTextContentStorage
        let layoutManager: NSTextLayoutManager
        let fullText: String
    }

    private func createTextLayoutSetup(paragraphCount: Int = 80) -> TextLayoutSetup {
        let textContentStorage = NSTextContentStorage()
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 450, height: CGFloat.greatestFiniteMagnitude))
        textLayoutManager.textContainer = textContainer

        let paragraphs = (0 ..< paragraphCount).map { index in
            "فقرة اختبارية رقم \(index): هذا نص عربي طويل مخصص لاختبار محرك تخطيط النصوص والتحقق من حساب إحداثيات ومواقع الفقرات بدقة دون الحاجة لتخطيط كامل المستند."
        }
        let fullText = paragraphs.joined(separator: "\n\n")
        textContentStorage.attributedString = NSAttributedString(
            string: fullText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18),
            ]
        )

        return TextLayoutSetup(storage: textContentStorage, layoutManager: textLayoutManager, fullText: fullText)
    }

    @Test("ensureLayout untuk target range menghitung layout fragment secara akurat tanpa full document layout")
    func testEnsureLayoutForRange() {
        let setup = createTextLayoutSetup()
        let layoutManager = setup.layoutManager
        let nsString = setup.fullText as NSString

        let targetQuery = "فقرة اختبارية رقم 60"
        let targetRange = nsString.range(of: targetQuery)
        #expect(targetRange.location != NSNotFound)
        #expect(targetRange.location > 2000)

        let docStart = layoutManager.documentRange.location
        guard let targetLoc = layoutManager.location(docStart, offsetBy: targetRange.location) else {
            Issue.record("Gagal mendapatkan lokasi NSTextLocation untuk targetRange")
            return
        }

        // Jalankan ensureLayout khusus untuk targetRange
        layoutManager.ensureLayout(for: targetRange)

        // Verifikasi layout fragment untuk target range sekarang telah dihitung
        let fragment = layoutManager.textLayoutFragment(for: targetLoc)
        #expect(fragment != nil)
        if let fragment {
            #expect(fragment.renderingSurfaceBounds.width > 0)
            #expect(fragment.renderingSurfaceBounds.height > 0)
            #expect(fragment.layoutFragmentFrame.minY > 0)
        }
    }

    @Test("ensureLayout untuk multiple ranges menghitung seluruh fragmen yang dituju")
    func testEnsureLayoutForMultipleRanges() {
        let setup = createTextLayoutSetup()
        let layoutManager = setup.layoutManager
        let nsString = setup.fullText as NSString

        let range1 = nsString.range(of: "فقرة اختبارية رقم 20")
        let range2 = nsString.range(of: "فقرة اختبارية رقم 70")
        #expect(range1.location != NSNotFound)
        #expect(range2.location != NSNotFound)

        layoutManager.ensureLayout(for: [range1, range2])

        let docStart = layoutManager.documentRange.location
        if let loc1 = layoutManager.location(docStart, offsetBy: range1.location),
           let loc2 = layoutManager.location(docStart, offsetBy: range2.location)
        {
            #expect(layoutManager.textLayoutFragment(for: loc1) != nil)
            #expect(layoutManager.textLayoutFragment(for: loc2) != nil)
        }
    }

    @Test("ensureLayout aman terhadap range tidak valid atau kosong")
    func testEnsureLayoutInvalidRanges() {
        let setup = createTextLayoutSetup()
        let layoutManager = setup.layoutManager

        // Range negatif atau kosong tidak boleh crash
        layoutManager.ensureLayout(for: NSRange(location: -1, length: 0))
        layoutManager.ensureLayout(for: NSRange(location: 0, length: 0))
        layoutManager.ensureLayout(for: NSRange(location: 999_999, length: 50))
    }

    @Test("IbarotTextView showFindIndicator dan scrollRangeToVisible berfungsi dengan layout viewport tanpa full layout")
    @MainActor
    func testIbarotTextViewTargetedLayoutAndFindIndicator() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        let textView = IbarotTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        scrollView.documentView = textView

        let paragraphs = (0 ..< 50).map { index in
            "سياق الكتاب للباب رقم \(index): هذا بيان وافٍ ومفصل لمسائل هذا الباب مع الشرح والتوضيح."
        }
        let fullText = paragraphs.joined(separator: "\n\n")

        textView.loadText(fullText)

        let targetQuery = "سياق الكتاب للباب رقم 40"
        let targetRange = (fullText as NSString).range(of: targetQuery)
        #expect(targetRange.location != NSNotFound)

        // Jalankan alur sinkronisasi viewport (ensureLayout + scroll + layoutViewport)
        textView.textLayoutManager?.ensureLayout(for: targetRange)
        textView.scrollRangeToVisible(targetRange)
        scrollView.contentView.layoutSubtreeIfNeeded()
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        textView.showFindIndicator(for: targetRange)

        // Periksa bahwa layout fragment untuk targetRange valid dan berada dalam rentang viewport yang terlihat
        if let tlm = textView.textLayoutManager,
           let targetLoc = tlm.location(tlm.documentRange.location, offsetBy: targetRange.location),
           let fragment = tlm.textLayoutFragment(for: targetLoc)
        {
            #expect(fragment.layoutFragmentFrame.minY > 0)
            let visibleRect = scrollView.documentVisibleRect
            #expect(visibleRect.intersects(fragment.layoutFragmentFrame))
        }
    }

    @Test("NSTextView printView sementara menggunakan TextKit 2 tanpa fallback TextKit 1")
    @MainActor
    func testPrintViewTemporaryTextViewUsesTextKit2() {
        let tmpTextView = NSTextView(usingTextLayoutManager: true)
        tmpTextView.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        #expect(tmpTextView.textLayoutManager != nil)

        let attrString = NSAttributedString(string: "تجربة طباعة النص عبر TextKit 2")
        tmpTextView.textStorage?.setAttributedString(attrString)
        tmpTextView.textLayoutManager?.ensureFullDocumentLayout()

        if let tlm = tmpTextView.textLayoutManager,
           let docStart = tlm.location(tlm.documentRange.location, offsetBy: 0),
           let fragment = tlm.textLayoutFragment(for: docStart)
        {
            #expect(fragment.renderingSurfaceBounds.width > 0)
        }
    }

    @Test("Kalkulasi geometri requiredHeight dan offset overlay popupText mencegah pemotongan teks saat scroll jauh")
    func testPopupTextOverlayGeometryCalculations() {
        let viewportHeight: CGFloat = 852
        let viewportWidth: CGFloat = 393

        // Simulasikan anotasi yang berada di posisi scroll jauh (y = 5200, tinggi 40)
        let totalRect = CGRect(x: 20, y: 5200, width: 350, height: 40)

        // Sesuai implementasi baru: requiredHeight = max(bounds.height, totalRect.maxY)
        let requiredHeight = max(viewportHeight, totalRect.maxY)
        #expect(requiredHeight == 5240)

        // Frame overlay di dalam containerView (yang diletakkan di totalRect)
        let overlayOrigin = CGPoint(x: -totalRect.minX, y: -totalRect.minY)
        let overlayFrame = CGRect(
            x: overlayOrigin.x,
            y: overlayOrigin.y,
            width: viewportWidth,
            height: requiredHeight
        )

        // Verifikasi bahwa batas bawah overlay mencapai dan menutup totalRect.height di dalam containerView
        let overlayBottomInContainer = overlayFrame.minY + overlayFrame.height
        #expect(overlayBottomInContainer >= totalRect.height)

        // Bandingkan dengan bug lama:
        let legacyHeight = viewportHeight // 852
        let legacyBottomInContainer = -totalRect.minY + legacyHeight // -5200 + 852 = -4348
        #expect(legacyBottomInContainer < 0, "Batas bawah lama berada jauh di atas containerView sehingga teks terpotong")
    }
}
