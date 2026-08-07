//
//  ReusableFunc.swift
//  maktab
//
//  Created by MacBook on 09/12/25.
//

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

class ReusableFunc {
    static func bundledArabicFont(ofSize size: CGFloat) -> PlatformFont {
        PlatformFont(name: "KFGQPCUthmanTahaNaskh", size: size)
            ?? PlatformFont.systemFont(ofSize: size)
    }

    #if os(macOS)
    static func setupSearchField(
        _ searchField: NSSearchField,
        systemSymbolName: String = "line.3.horizontal.decrease.circle"
    ) {
        // Asumsikan 'searchField' adalah instance dari NSSearchField Anda
        if let searchFieldCell = searchField.cell as? NSSearchFieldCell {
            if let searchButton = searchFieldCell.searchButtonCell {
                // 1. Buat NSImage baru untuk ikon yang diinginkan
                let customImage = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: .none)

                // 2. Setel NSImage baru ke searchButtonCell
                searchButton.image = customImage

                // Pilihan: Jika Anda ingin gambar yang sama untuk status alternatif (misalnya, saat ditekan),
                // Anda juga dapat menyetel properti alternateImage.
                searchButton.alternateImage = customImage
            }
        }
    }

    static func updateBuiltInRecents(with newQuery: String, in searchField: NSSearchField) {
        if newQuery.isEmpty { return }
        let maxRecents = 10
        let trimmedQuery = newQuery

        // 1. Akses properti recentSearches bawaan
        var recents = searchField.recentSearches

        // 2. Terapkan Logika Penimpaan (LIFO - Last In, First Out)

        // Hapus duplikat
        if let existingIndex = recents.firstIndex(of: trimmedQuery) {
            recents.remove(at: existingIndex)
        }

        // Masukkan item baru di awal
        recents.insert(trimmedQuery, at: 0)

        // Batasi jumlah entri (Penimpaan item terlama)
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }

        // 3. Simpan kembali ke properti, yang akan memicu penyimpanan di UserDefaults
        searchField.recentSearches = recents
    }


    /// Fungsi untuk membuka jendela ketika salah satu view di Sidebar pertama kali ditampilkan. Yaitu ketika view sedang memproses pemuatan data dari Data Base.
    /// - Parameters:
    ///   - view: view yang akan bertindak sebagai induk untuk jendela yang akan ditambahkan sebagai child window.
    static func showProgressWindow(_ parentView: NSView) {
        // 1. Cek apakah view sudah ada untuk menghindari duplikasi
        if  parentView.subviews.first(where: { $0.identifier?.rawValue == "ProgressOverlay" }) != nil {
            return
        }

        // 2. Muat view controller dari XIB
        let progressVC = InitProgress(nibName: "InitProgress", bundle: nil)
        let progressView = progressVC.view

        // Set identifier agar mudah ditemukan saat mau menghapus nanti
        progressView.identifier = NSUserInterfaceItemIdentifier("ProgressOverlay")

        // 4. Atur Frame agar berada di tengah parentView
        progressView.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(progressView)

        // 5. Gunakan Auto Layout agar tetap di tengah meskipun window di-resize
        NSLayoutConstraint.activate([
            progressView.centerXAnchor.constraint(equalTo: parentView.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: parentView.centerYAnchor),
            // Jika InitProgress punya size tetap di XIB, gunakan itu:
            progressView.widthAnchor.constraint(equalToConstant: progressView.frame.width),
            progressView.heightAnchor.constraint(equalToConstant: progressView.frame.height)
        ])
    }

    /// Fungsi untuk menutup jendela progress pemuatan atau pembaruan data.
    /// - Parameter parentWindow: Jendela induk (`NSWindow`) tempat jendela progres ditampilkan sebagai child window.
    static func closeProgressWindow(_ parentView: NSView) {
        // Cari progressView di dalam parentView menggunakan identifier
        guard let progressView = parentView.subviews.first(where: { $0.identifier?.rawValue == "ProgressOverlay" }) else {
            return
        }

        // Atur NSAnimationContext untuk fade out view
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            // Mengurangi alphaValue view menjadi 0
            progressView.animator().alphaValue = 0
        }) {
            // Setelah animasi selesai, hapus dari superview
            progressView.removeFromSuperview()
            #if DEBUG
                print("Progress view removed from parent view")
            #endif
        }
    }

    // MARK: - TABLEVIEW
    static func registerNib(tableView: NSTableView, nibName: CellIViewIdentifier, cellIdentifier: CellIViewIdentifier) {
        if let folderNib = NSNib(nibNamed: nibName.rawValue, bundle: nil) {
            tableView.register(folderNib, forIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdentifier.rawValue))
        } else {
            #if DEBUG
            print("couldnt register Nib", "\(cellIdentifier)")
            #endif
        }
    }

    // MARK: - WINDOW
    static func makeTitlelessWindow(contentView: NSView, size: NSSize) -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.contentView = contentView
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.standardWindowButton(.closeButton)?.isHidden = true
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        return w
    }

    static func makeWindow(
        contentView: NSView,
        styleMask: NSWindow.StyleMask,
        size: NSSize? = nil,
        title: String = "",
        centered: Bool = true
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        window.title = title
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        if centered { window.center() }

        return window
    }

    // MARK: - OTHERS
    static func resolveRowsToProcess(selectedRows: IndexSet, clickedRow: Int) -> IndexSet {
        if selectedRows.contains(clickedRow), selectedRows.count > 1 {
            return selectedRows
        }
        if !selectedRows.isEmpty, clickedRow < 0 {
            return selectedRows
        }
        if clickedRow >= 0 {
            return IndexSet(integer: clickedRow)
        }
        return selectedRows
    }

    static func unhideSearchField(
        searchFieldIsHidden: Bool,
        searchField: NSSearchField,
        scrollViewTopConstraint: NSLayoutConstraint
    ) {
        let hide = searchFieldIsHidden

        searchField.isHidden = hide

        // 3. Buat Constraint yang Baru
        if !hide {
            // KONDISI 1: TIDAK TERSEMBUNYI (Unhide)
            scrollViewTopConstraint.constant = 92
            searchField.becomeFirstResponder()
        } else {
            // KONDISI 2: TERSEMBUNYI (Hide)
            // Hubungkan scrollView top ke superview top dengan constant 0
            // Asumsi superview dari scrollView adalah view utama ViewController
            scrollViewTopConstraint.constant = 0
        }
    }
    #endif

    /// Menampilkan jendela peringatan standar kepada pengguna.
    #if os(macOS)
    static func showAlert(title: String, message: String, style: NSAlert.Style = .warning) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = style
            alert.messageText = title
            alert.informativeText = message
            alert.runModal()
        }
    }
    #else
    static func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            guard let topVC = getTopViewController() else { return }
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            topVC.present(alert, animated: true)
        }
    }

    static func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var topVC = rootVC
        while let presentedVC = topVC.presentedViewController {
            topVC = presentedVC
        }
        return topVC
    }
    #endif


    static func decompressData(_ data: Data?) -> String {
        guard let compressed = data, !compressed.isEmpty else { return "" }
        return compressed.withUnsafeBytes { ptr in decompressData(from: ptr) }
    }

    static func decompressData(from ptr: UnsafeRawBufferPointer?) -> String {
        guard let ptr = ptr, ptr.count > 0 else { return "" }

        // 1. Ambil ukuran asli dari frame ZSTD
        let expectedSize = ZSTD_getFrameContentSize(ptr.baseAddress, ptr.count)

            // Cek jika ukuran tidak valid atau error
            if expectedSize == ZSTD_CONTENTSIZE_ERROR || expectedSize == ZSTD_CONTENTSIZE_UNKNOWN {
                // Jika tidak diketahui, gunakan fallback manual yang lebih besar (misal * 10) atau return empty
                #if DEBUG
                print("❌ Ukuran konten tidak diketahui")
                #endif
                return ""
            }

            let expectedSizeInt = Int(expectedSize)
            return String(unsafeUninitializedCapacity: expectedSizeInt) { outBuffer in
                let dict = Thread.current.threadDictionary
                let dctx: OpaquePointer
                if let wrapper = dict["Maktabah.ZSTDDCtx"] as? ZSTDContextWrapper {
                    dctx = wrapper.dctx
                } else {
                    let wrapper = ZSTDContextWrapper()
                    dict["Maktabah.ZSTDDCtx"] = wrapper
                    dctx = wrapper.dctx
                }

                let decompressedSize = ZSTD_decompressDCtx(
                    dctx,
                    outBuffer.baseAddress,
                    expectedSizeInt,
                    ptr.baseAddress,
                    ptr.count
                )

                if ZSTD_isError(decompressedSize) != 0 {
                    let errorName = String(cString: ZSTD_getErrorName(decompressedSize))
                    #if DEBUG
                    print("❌ Zstd Error: \(errorName)")
                    #endif
                    return 0
                }

                return decompressedSize
            }
    }

    static func compressData(_ text: String, level: Int32 = 10) -> Data? {
        let inputData = Data(text.utf8)
        guard !inputData.isEmpty else { return Data() }

        let bound = ZSTD_compressBound(inputData.count)
        var output = Data(count: Int(bound))

        let compressedSize = output.withUnsafeMutableBytes { outPtr -> Int in
            return inputData.withUnsafeBytes { inPtr in
                return ZSTD_compress(
                    outPtr.baseAddress,
                    bound,
                    inPtr.baseAddress,
                    inputData.count,
                    level
                )
            }
        }

        if ZSTD_isError(compressedSize) != 0 {
            let errorName = String(cString: ZSTD_getErrorName(compressedSize))
            #if DEBUG
                print("❌ Zstd Compress Error: \(errorName)")
            #endif
            return nil
        }

        output.count = compressedSize
        return output
    }

    #if os(macOS)
    static func helpSearchOpt(_ sender: NSButton) {
        let searchHelpPopover: NSPopover = NSPopover()

        // 1. Cek dan Tutup Popover jika sudah terbuka
        if searchHelpPopover.isShown {
            searchHelpPopover.close()
            return
        }

        // 2. Buat NSViewController (kecil-kecilan) secara in-place
        let contentVC = NSViewController()

        // Atur ukuran konten yang diinginkan untuk Popover
        let preferredWidth: CGFloat = 250
        let preferredHeight: CGFloat = 250
        contentVC.preferredContentSize = NSSize(width: preferredWidth, height: preferredHeight)

        // 3. Buat View Utama dan StackView
        let mainView = NSView(frame: NSRect(x: 0, y: 0, width: preferredWidth, height: preferredHeight))
        contentVC.view = mainView

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.edgeInsets = NSEdgeInsetsZero
        stackView.translatesAutoresizingMaskIntoConstraints = false

        mainView.addSubview(stackView)

        let constant: CGFloat = 20

        // Atur constraints agar StackView mengisi View Controller
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: mainView.topAnchor, constant: constant),
            stackView.bottomAnchor.constraint(equalTo: mainView.bottomAnchor, constant: -constant),
            stackView.leadingAnchor.constraint(equalTo: mainView.leadingAnchor, constant: constant),
            stackView.trailingAnchor.constraint(equalTo: mainView.trailingAnchor, constant: -constant)
        ])

        // --- 4. Definisi Konten Bantuan ---

        // Judul Utama
        let titleLabel = NSTextField(labelWithString: NSLocalizedString("searchOptionsHelp", comment: ""))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        stackView.addArrangedSubview(titleLabel)

        // Fungsi pembantu lokal (didefinisikan di dalam func ini)
        func createTitleLabel(text: String) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            return label
        }

        func createDescLabel(text: String) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = NSFont.systemFont(ofSize: 13)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return label
        }

        func createSeparator() -> NSView {
            let separator = NSBox()
            separator.boxType = .separator
            return separator
        }

        stackView.addArrangedSubview(createSeparator())

        // Option 1
        let option1Label = createTitleLabel(text: NSLocalizedString("exactSearchTitle", comment: ""))
        let option1Desc = createDescLabel(text: NSLocalizedString("exactSearchDesc", comment: ""))

        // Option 2
        let option2Label = createTitleLabel(text: NSLocalizedString("separateWordsSearchTitle", comment: ""))
        let option2Desc = createDescLabel(text: NSLocalizedString("separateWordsSearchDesc", comment: ""))

        let option3Label = createTitleLabel(text: String(localized: "anyWordsSearchTitle"))
        let option3Desc = createDescLabel(text: String(localized: "anyWordsSearchDesc"))

        let option4Label = createTitleLabel(text: String(localized: "nearSearchTitle"))
        let option4Desc = createDescLabel(text: String(localized: "nearSearchDesc"))

        // 5. Tambahkan Konten ke StackView
        stackView.addArrangedSubview(option1Label)
        stackView.addArrangedSubview(option1Desc)

        stackView.addArrangedSubview(createSeparator())

        stackView.addArrangedSubview(option2Label)
        stackView.addArrangedSubview(option2Desc)

        stackView.addArrangedSubview(createSeparator())

        stackView.addArrangedSubview(option3Label)
        stackView.addArrangedSubview(option3Desc)

        stackView.addArrangedSubview(createSeparator())

        stackView.addArrangedSubview(option4Label)
        stackView.addArrangedSubview(option4Desc)

        // 6. Konfigurasi dan Tampilkan Popover
        searchHelpPopover.contentViewController = contentVC
        searchHelpPopover.behavior = .transient // Popover menutup ketika fokus hilang

        // Tampilkan popover, relatif terhadap tombol (sender)
        searchHelpPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minX)
    }

    // MARK: - NSIMAGE
    static func systemImage(named name: String) -> NSImage {
        guard let image = NSImage(systemSymbolName: name,
                                  accessibilityDescription: nil)
        else { return NSImage() }
        return image
    }
    #endif
}

#if os(macOS)
extension NSOutlineView {
    func effectiveRows() -> IndexSet {
        if clickedRow == -1 { return selectedRowIndexes }
        return selectedRowIndexes.contains(clickedRow)
            ? selectedRowIndexes
            : IndexSet(integer: clickedRow)
    }

    func contextMenuAnchorRect() -> NSRect {
        let anchorRow = clickedRow >= 0 ? clickedRow : selectedRow
        guard anchorRow >= 0 else { return bounds }
        return rect(ofRow: anchorRow)
    }
}
#endif
