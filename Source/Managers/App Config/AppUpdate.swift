//
//  AppUpdate.swift
//  Maktabah
//
//  Created by MacBook on 21/01/26.
//

import AppKit

private var tempFilePath: URL {
    // Mendapatkan URL Application Support untuk user saat ini
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

    return appSupport.appendingPathComponent("AppUpdate.csv")
}

extension AppDelegate {

    /**
     Memeriksa pembaruan aplikasi dengan membandingkan versi dan build aplikasi saat ini dengan data yang diambil dari file CSV.
     
     Fungsi ini melakukan langkah-langkah berikut:
     1. Memeriksa apakah pembaruan telah diunduh sebelumnya dan menunggu untuk diinstal ulang saat aplikasi ditutup. Jika ya, tampilkan pemberitahuan dan keluar dari fungsi.
     2. Mengambil data pembaruan dari file CSV yang terletak di URL yang ditentukan.
     3. Membandingkan versi dan build aplikasi saat ini dengan versi dan build terbaru yang tersedia dari data CSV.
     4. Jika versi atau build terbaru lebih tinggi dari versi atau build saat ini, fungsi akan:
     - Menampilkan `NSAlert` untuk opsi membuka link download.
     5. Jika pemeriksaan dilakukan saat peluncuran aplikasi dan versi/build terbaru tidak lebih tinggi dari versi/build yang disimpan untuk dilewati, fungsi akan keluar.
     6. Jika pemeriksaan dilakukan saat peluncuran aplikasi dan ada pembaruan yang tersedia, fungsi akan menampilkan pemberitahuan tentang pembaruan yang tersedia.
     7. Jika pemeriksaan tidak dilakukan saat peluncuran aplikasi dan tidak ada pembaruan yang tersedia, fungsi akan menampilkan pemberitahuan bahwa tidak ada pembaruan.
     8. Jika pemeriksaan tidak dilakukan saat peluncuran aplikasi dan ada pembaruan yang tersedia, fungsi akan:
     - Menyimpan versi dan build aplikasi saat ini ke dalam UserDefaults.
     - Menyimpan URL pembaruan ke dalam UserDefaults.
     - Membuka aplikasi agen untuk melakukan pembaruan.
     9. Menghapus file sementara jika ada.
     - Parameter atLaunch: Tidak menampilkan `NSAlert` jika tidak ada pembaruan dan bernilai `true`.
     */
    func checkAppUpdates(_ atLaunch: Bool = true) async {
        let checkAtStart = UserDefaults.standard.bool(forKey: "SuppressUpdateCheck")

        if !checkAtStart, atLaunch {
            return
        }

        guard let isConnected = try? await ReusableFunc.checkInternetConnectivityDirectly(), isConnected 
        else { return }

        fetchCSVData(from: "https://drive.google.com/uc?export=download&id=1mITjjMwdPE6DFaZPvizq6crMBqbQxfNt") { updates in
            guard let (version, build, link) = updates else { return }
            // Versi aplikasi saat ini
            let currentVersion = Double(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") ?? 0
            let currentBuild = Double(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0

            // Gabungkan semua release notes
            if version > currentVersion || (version == currentVersion && build > currentBuild) {

                // Jalankan UI di Main Thread
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Application Update", comment: "Judul NSAlert untuk update aplikasi")
                    let infoFormat = NSLocalizedString("New Version %@ (%d) available", comment: "Pesan versi baru")
                    alert.informativeText = String(format: infoFormat, "\(version)", Int(build))
                    alert.alertStyle = .informational

                    // Tombol pertama (index 1000)
                    alert.addButton(withTitle: NSLocalizedString("Download Update", comment: ""))
                    // Tombol kedua (index 1001)
                    alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))

                    // --- TAMBAHKAN SUPPRESS BUTTON DISINI ---
                    alert.showsSuppressionButton = true
                    alert.suppressionButton?.title = NSLocalizedString("Check at Start", comment: "")
                    alert.suppressionButton?.state = checkAtStart ? .on : .off
                    // ----------------------------------------

                    // Menampilkan alert secara modal
                    let response = alert.runModal()

                    // Simpan status suppress jika dicentang
                    if alert.suppressionButton?.state == .on {
                        UserDefaults.standard.set(true, forKey: "SuppressUpdateCheck")
                    } else {
                        UserDefaults.standard.set(false, forKey: "SuppressUpdateCheck")
                    }

                    if response == .alertFirstButtonReturn {
                        // Jika user klik "Download Update"
                        NSWorkspace.shared.open(link)
                    }
                }
            } else {
                if !atLaunch {
                    DispatchQueue.main.async {
                        ReusableFunc.showAlert(title: NSLocalizedString("This is the latest version", comment: "Aplikasi sudah versi terbaru"), message: "")
                    }
                }
                #if DEBUG
                    print("currentVersion: \(currentVersion), currentBuild: (\(currentBuild)). newVersion: \(version) (\(build))")
                #endif
            }

            do {
                if FileManager.default.fileExists(atPath: tempFilePath.path) {
                    try FileManager.default.removeItem(at: tempFilePath)
                }
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    /// Mengunduh data CSV dari URL yang diberikan dan memprosesnya untuk mendapatkan informasi versi, build, dan tautan.
    ///
    ///
    /// - Parameter:
    ///     - urlString: String representasi dari URL tempat file CSV akan diunduh.
    ///     - completion:
    ///         - Closure yang dipanggil setelah proses pengunduhan dan parsing selesai. Closure ini menerima sebuah tuple opsional `(Double, URL)?`.
    ///             - Double pertama adalah versi yang diekstrak dari file CSV.
    ///             - URL adalah tautan yang diekstrak dari file CSV.
    ///   Jika terjadi kesalahan selama proses, closure akan dipanggil dengan nilai `nil`.
    ///
    /// - Note: Fungsi ini mengunduh file ke lokasi sementara, memprosesnya, dan kemudian menghapus file sementara tersebut.
    func fetchCSVData(from urlString: String, completion: @escaping ((Double, Double, URL)?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        // Mulai download file
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            if let error {
                #if DEBUG
                    print("Error downloading file: \(error)")
                #endif
                completion(nil)
                return
            }

            guard let tempURL else {
                #if DEBUG
                    print("Temp URL is nil")
                #endif
                completion(nil)
                return
            }

            do {
                if FileManager.default.fileExists(atPath: tempFilePath.path) {
                    try FileManager.default.removeItem(at: tempFilePath)
                }
                // Pindahkan file dari URL temporary ke tempFilePath
                try FileManager.default.moveItem(at: tempURL, to: tempFilePath)

                // Baca file CSV dari tempFilePath
                let content = try String(contentsOf: tempFilePath, encoding: .utf8)

                // Normalisasi newline: ganti semua `\r\n` (Windows-style) menjadi `\n` (Unix-style)
                let normalizedContent = content.replacingOccurrences(of: "\r\n", with: "\n")

                // Parsing CSV
                let rows = normalizedContent.split(separator: "\n")
                guard let firstRow = rows.first else {
                    completion(nil)
                    return
                }

                let columns = firstRow.split(separator: ";")
                if let version = Double(columns[0]),
                   let build = Double(columns[1]),
                   let link = URL(string: String(columns[2]))
                {
                    completion((version, build, link))
                } else {
                    completion(nil)
                }
            } catch {
                #if DEBUG
                    print("Error reading file: \(error)")
                #endif
                completion(nil)
            }
        }
        task.resume()
    }
}
