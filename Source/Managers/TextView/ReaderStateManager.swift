//
//  ReaderStateManager.swift
//  Maktabah
//

import Cocoa
import Foundation

/// Protokol untuk komponen UI yang bisa menyimpan dan memulihkan state ke ReaderState
protocol ReaderStateComponent: AnyObject {
    /// Memperbarui nilai pada `ReaderState` berdasarkan kondisi UI komponen ini.
    /// - Parameter state: Referensi inout ke objek `ReaderState` yang akan diperbarui.
    func updateState(_ state: inout ReaderState)
    /// Memulihkan UI komponen ini dari data yang tersimpan pada `ReaderState`.
    /// - Parameter state: Objek `ReaderState` sumber data untuk pemulihan.
    func restore(from state: ReaderState)
    /// Membersihkan state/UI komponen saat reset. Opsional untuk diimplementasikan.
    func cleanUpState() 
}

class ReaderStateManager {

    // MARK: - State Storage
    private var viewerModeState: ReaderState? = nil
    private var searchModeState: ReaderState? = nil
    private var authorModeState: ReaderState? = nil

    private let fileManager = FileManager.default

    private var statesDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let maktabahDir = appSupport.appendingPathComponent("Maktabah/States")
        if !fileManager.fileExists(atPath: maktabahDir.path) {
            try? fileManager.createDirectory(at: maktabahDir, withIntermediateDirectories: true)
        }
        return maktabahDir
    }

    /// Menghasilkan lokasi file di disk untuk menyimpan state pada mode tertentu.
    /// - Parameter mode: Mode aplikasi yang menentukan nama file state.
    /// - Returns: URL file untuk state pada mode tersebut.
    private func stateFileURL(for mode: AppMode) -> URL {
        let filename: String
        switch mode {
        case .viewer: filename = "viewer_state.json"
        case .search: filename = "search_state.json"
        case .author: filename = "author_state.json"
        }
        return statesDirectory.appendingPathComponent(filename)
    }

    /// Mengambil state untuk mode tertentu dengan lazy loading dari disk jika belum ada di memori.
    /// - Parameter mode: Mode aplikasi yang ingin diambil state-nya.
    /// - Returns: Objek `ReaderState` untuk mode tersebut.
    func getState(for mode: AppMode) -> ReaderState {
        switch mode {
        case .viewer:
            if viewerModeState == nil {  // Cek dulu
                viewerModeState = loadStateFromFile(for: .viewer) ?? ReaderState()
            }
            return viewerModeState!
        case .search:
            if searchModeState == nil {
                searchModeState = loadStateFromFile(for: .search) ?? ReaderState()
            }
            return searchModeState!
        case .author:
            if authorModeState == nil {
                authorModeState = loadStateFromFile(for: .author) ?? ReaderState()
            }
            return authorModeState!
        }
    }

    /// Menetapkan state di memori untuk mode tertentu.
    /// - Parameters:
    ///   - state: Objek `ReaderState` yang akan disimpan.
    ///   - mode: Mode aplikasi yang dikaitkan dengan state tersebut.
    func setState(_ state: ReaderState, for mode: AppMode) {
        switch mode {
        case .viewer: viewerModeState = state
        case .search: searchModeState = state
        case .author: authorModeState = state
        }
    }

    /// Menyimpan seluruh state yang saat ini ada di memori ke disk per mode terkait.
    func persistToDisk() {
        if viewerModeState != nil { saveStateToFile(viewerModeState!, for: .viewer) }
        if searchModeState != nil { saveStateToFile(searchModeState!, for: .search) }
        if authorModeState != nil { saveStateToFile(authorModeState!, for: .author) }
    }
    
    /// Menyimpan state ke disk untuk mode tertentu.
    /// - Parameter for: Mode yang sesuai component yang akan disimpan state nya.
    func persisToDisk(for mode: AppMode) {
        let state = getState(for: mode)
        saveStateToFile(state, for: mode)
    }

    /// Menyimpan state tertentu ke file JSON pada direktori Application Support.
    /// - Parameters:
    ///   - state: Objek `ReaderState` yang akan diserialisasi.
    ///   - mode: Mode aplikasi yang menentukan file tujuan penyimpanan.
    private func saveStateToFile(_ state: ReaderState, for mode: AppMode) {
        let fileURL = stateFileURL(for: mode)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to save \(mode) state: \(error.localizedDescription)")
        }
    }

    /// Memuat state dari file JSON untuk mode tertentu jika file tersedia.
    /// - Parameter mode: Mode aplikasi yang state-nya ingin dimuat.
    /// - Returns: `ReaderState` hasil decoding atau `nil` bila tidak tersedia/terjadi error.
    private func loadStateFromFile(for mode: AppMode) -> ReaderState? {
        let fileURL = stateFileURL(for: mode)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ReaderState.self, from: data)
        } catch {
            print("Failed to load \(mode) state: \(error)")
            return nil
        }
    }

    /*
    func getLastMode() -> AppMode {
        UserDefaults.standard.lastAppMode
    }
    
    func clearAllStates() {
        try? fileManager.removeItem(at: statesDirectory)
    }
     */

    // MARK: - Simplified Persistence Logic

    /// Mengumpulkan data dari kumpulan komponen UI untuk memperbarui state pada mode tertentu.
    /// Hanya menyimpan di memori; pemanggil dapat memanggil `persistToDisk()` untuk menulis ke disk.
    /// - Parameters:
    ///   - mode: Mode aplikasi yang ingin diperbarui state-nya.
    ///   - components: Array komponen yang akan mengisi/menimpa bagian state sesuai kebutuhan mereka.
    func saveState(for mode: AppMode, components: [ReaderStateComponent?]) {
        var state = getState(for: mode)

        // Setiap komponen mengupdate bagian state yang relevan bagi mereka
        for component in components {
            component?.updateState(&state)
        }

        setState(state, for: mode)
    }

    /// Memulihkan UI komponen berdasarkan state yang tersimpan untuk mode tertentu.
    /// - Parameters:
    ///   - mode: Mode aplikasi yang state-nya akan digunakan.
    ///   - components: Array komponen yang akan membaca data dari state.
    func restoreState(for mode: AppMode, components: [ReaderStateComponent?]) {
        let state = getState(for: mode)

        // Setiap komponen mengambil apa yang mereka butuhkan dari state
        for component in components {
            component?.restore(from: state)
        }
    }

    /// Mereset state ke nilai default untuk mode tertentu dan meminta setiap komponen membersihkan UI-nya.
    /// - Parameters:
    ///   - mode: Mode aplikasi yang ingin direset.
    ///   - components: Array komponen yang akan dipanggil `cleanUpState()`.
    func cleanUpState(for mode: AppMode, components: [ReaderStateComponent?]) {
        // Opsional: Bersihkan state di memori
        var state = getState(for: mode)
        state = ReaderState() // Reset ke default
        setState(state, for: mode)

        // Beritahu setiap komponen untuk membersihkan UI mereka
        for component in components {
            component?.cleanUpState()
        }
    }
}

