//
//  ReusableFunc.swift
//  maktab
//
//  Created by MacBook on 09/12/25.
//

import Cocoa

class ReusableFunc {
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
        searchField.focusRingType = .none
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

    // MARK: - OTHERS
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

    /// Menampilkan jendela peringatan (`NSAlert`) standar kepada pengguna.
    ///
    /// Fungsi ini bersifat modal, yang berarti pengguna harus menutup peringatan sebelum melanjutkan interaksi dengan aplikasi.
    /// Ini ideal untuk notifikasi penting atau kesalahan yang memerlukan perhatian segera dari pengguna.
    ///
    /// - Parameters:
    ///   - title: Judul yang akan ditampilkan di jendela peringatan.
    ///   - message: Pesan informatif yang lebih detail di bawah judul.
    static func showAlert(title: String, message: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.alertStyle = style // Mengatur gaya peringatan, default adalah .warning
        alert.messageText = title // Mengatur judul peringatan
        alert.informativeText = message // Mengatur pesan detail peringatan
        alert.runModal() // Menampilkan peringatan secara modal
    }

    // MARK: - Fungsi Pemeriksaan Koneksi Internet Langsung

    /// Fungsi ini akan memeriksa ketersediaan internet secara asinkron.
    /// - Returns: `true` jika internet tersedia, `false` jika internet offline.
    static func checkInternetConnectivityDirectly() async throws -> Bool {
        // Pilih URL yang Anda yakin selalu online, misal Google atau API server Anda.
        let url = URL(string: "https://www.google.com")!
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD" // Minta hanya header, lebih cepat dan hemat bandwidth.
        request.timeoutInterval = 5.0 // Batasi waktu respons menjadi 5 detik.

        do {
            let (_, response) = try await URLSession.shared.data(for: request) // Gunakan async data(for:)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                #if DEBUG
                    print("Internet tersedia melalui koneksi langsung.")
                #endif
                return true
            } else {
                #if DEBUG
                    print("Internet tidak tersedia melalui koneksi langsung. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                #endif
                return false
            }
        } catch {
            #if DEBUG
                print("Gagal memeriksa koneksi internet. Error: \(error.localizedDescription)")
            #endif
            // Jika ada error (misal, tidak ada koneksi sama sekali, timeout), anggap tidak ada internet
            return false
        }
    }

    static func decompressData(_ data: Data?) -> String {
        guard let compressed = data, !compressed.isEmpty else { return "" }

        return compressed.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> String in
            // 1. Ambil ukuran asli dari frame ZSTD
            let expectedSize = ZSTD_getFrameContentSize(ptr.baseAddress, compressed.count)

            // Cek jika ukuran tidak valid atau error
            if expectedSize == ZSTD_CONTENTSIZE_ERROR || expectedSize == ZSTD_CONTENTSIZE_UNKNOWN {
                // Jika tidak diketahui, gunakan fallback manual yang lebih besar (misal * 10) atau return empty
                #if DEBUG
                print("❌ Ukuran konten tidak diketahui")
                #endif
                return ""
            }

            var outputBuffer = Data(count: Int(expectedSize))
            let decompressedSize = outputBuffer.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) -> Int in
                return ZSTD_decompress(
                    outPtr.baseAddress,
                    Int(expectedSize),
                    ptr.baseAddress,
                    compressed.count
                )
            }

            if ZSTD_isError(decompressedSize) != 0 {
                let errorName = String(cString: ZSTD_getErrorName(decompressedSize))
                print("❌ Zstd Error: \(errorName)")
                return ""
            }

            return String(data: outputBuffer, encoding: .utf8) ?? ""
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

        // 5. Tambahkan Konten ke StackView
        stackView.addArrangedSubview(option1Label)
        stackView.addArrangedSubview(option1Desc)

        stackView.addArrangedSubview(createSeparator())

        stackView.addArrangedSubview(option2Label)
        stackView.addArrangedSubview(option2Desc)

        // 6. Konfigurasi dan Tampilkan Popover
        searchHelpPopover.contentViewController = contentVC
        searchHelpPopover.behavior = .transient // Popover menutup ketika fokus hilang

        // Tampilkan popover, relatif terhadap tombol (sender)
        searchHelpPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minX)
    }
}
