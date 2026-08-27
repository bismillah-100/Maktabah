//
//  BackgroundOptions.swift
//  maktab
//
//  Created by MacBook on 09/12/25.
//

import Cocoa

enum BorderOptions {
    case brighter
    case darken
}

enum BackgroundColor: Int {
    case white
    case sepia
    case gray
    case darkSepia
    case black

    /// NSColor yang otomatis menyesuaikan mode terang/gelap sistem
    /// berdasarkan definisi di Assets.xcassets.
    var nsColor: NSColor {
        return switch self {
        case .white: .white
        case .sepia: .bgSepia
        case .gray: .bgGray
        case .darkSepia: .bgSepiaDark
        case .black: .bgDark
        }
    }
}

class BackgroundOptions: NSControl {

    // MARK: - Properties

    override var intrinsicContentSize: NSSize {
        NSSize(width: 28, height: 28)
    }

    var isSelected: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    let color: NSColor

    var mouseInside: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    var border: BorderOptions!

    // MARK: - Initializers

    init(_ color: NSColor, frame: NSRect, border: BorderOptions) {
        self.color = color
        self.border = border
        super.init(frame: frame)
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        self.color = .clear
        super.init(coder: coder)
        setupTrackingArea()
    }

    // MARK: - Mouse Tracking

    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .assumeInside, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
    }

    override func mouseExited(with event: NSEvent) {
        mouseInside = false
    }

    override func mouseDown(with event: NSEvent) {
        // Mengirimkan aksi ke target (Controller) saat diklik
        if let action = action {
            NSApp.sendAction(action, to: target, from: self)
        }

        // Opsional: Langsung ubah state selected saat diklik (toggle)
        // isSelected.toggle()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect) // Pastikan call super

        // Pastikan tidak draw di luar bounds
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip() // Clip ke bounds

        let highlightColor: NSColor
        if border == .brighter {
            highlightColor = color.highlight(withLevel: 0.3) ?? color
        } else {
            highlightColor = color.shadow(withLevel: 0.3) ?? color
        }

        let innerPadding: CGFloat = 0
        let outerBorderWidth: CGFloat = 0.5

        let outerRect = bounds.insetBy(dx: innerPadding, dy: innerPadding)
        let outerPath = NSBezierPath(ovalIn: outerRect)

        highlightColor.setFill()
        outerPath.fill()

        let innerRect = outerRect.insetBy(dx: outerBorderWidth, dy: outerBorderWidth)
        let innerPath = NSBezierPath(ovalIn: innerRect)

        color.setFill()
        innerPath.fill()

        if isSelected {
            let maxIconSize = min(innerRect.width, innerRect.height)
            let iconSize = min(18.0, maxIconSize * 0.65)

            let iconOrigin = NSPoint(x: innerRect.midX - iconSize / 2.0,
                                     y: innerRect.midY - iconSize / 2.0)
            let iconRect = NSRect(origin: iconOrigin, size: NSSize(width: iconSize, height: iconSize))

            let iconPath = tickPath(iconRect)
            if tag > 1 {
                color.highlight(withLevel: 0.9)?.setFill()
            } else {
                color.shadow(withLevel: 0.9)?.setFill()
            }
            iconPath.fill()
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// Membuat dan mengembalikan `NSBezierPath` yang menggambarkan simbol "centang" (tick/check mark).
    ///
    /// Jalur ini digambar relatif terhadap titik asal (*origin*) dari `rect` yang diberikan,
    /// menggunakan koordinat `minX` dan `minY` dari *rect* sebagai acuan.
    /// Bentuk yang dihasilkan adalah tanda centang, sering digunakan untuk menunjukkan konfirmasi
    /// atau penyelesaian.
    ///
    /// - Parameter rect: `NSRect` yang digunakan untuk menentukan titik acuan `minX` dan `minY`
    ///                   untuk menggambar jalur. Lebar dan tinggi `rect` tidak secara langsung
    ///                   memengaruhi ukuran jalur, tetapi lebih pada posisi relatifnya.
    /// - Returns: Sebuah `NSBezierPath` yang merepresentasikan simbol "centang".
    func tickPath(_ rect: NSRect) -> NSBezierPath {
        // Buat centang sebagai polygon relatif ke rect sehingga selalu skalabel dan terpusat.
        let minX = rect.minX
        let minY = rect.minY
        let w = rect.width
        let h = rect.height

        let path = NSBezierPath()
        // Titik-titik relatif membentuk tanda centang yang proporsional
        path.move(to: NSPoint(x: minX + 0.12 * w, y: minY + 0.52 * h)) // kiri tengah
        path.line(to: NSPoint(x: minX + 0.40 * w, y: minY + 0.20 * h)) // ke bawah
        path.line(to: NSPoint(x: minX + 0.47 * w, y: minY + 0.27 * h)) // sedikit balik
        path.line(to: NSPoint(x: minX + 0.88 * w, y: minY + 0.80 * h)) // puncak kanan atas
        path.line(to: NSPoint(x: minX + 0.78 * w, y: minY + 0.90 * h)) // smoothing
        path.line(to: NSPoint(x: minX + 0.41 * w, y: minY + 0.38 * h)) // kembali ke tengah
        path.line(to: NSPoint(x: minX + 0.28 * w, y: minY + 0.52 * h)) // penghubung
        path.close()

        return path
    }
}
