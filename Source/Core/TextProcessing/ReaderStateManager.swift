//
//  ReaderStateManager.swift
//  Maktabah
//

#if os(macOS)
import Cocoa
#endif
import Foundation
import OSLog

@MainActor
class ReaderStateManager {
    // MARK: - State Storage (In-Memory per Tab/SplitVC)

    private var viewerModeState: ReaderState = .init()
    private var searchModeState: ReaderState = .init()
    private var authorModeState: ReaderState = .init()

    private static let fileManager = FileManager.default

    private static let statesDirectory: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let maktabahDir = appSupport.appendingPathComponent("Maktabah/States")
        if !fileManager.fileExists(atPath: maktabahDir.path) {
            try? fileManager.createDirectory(at: maktabahDir, withIntermediateDirectories: true)
        }
        return maktabahDir
    }()

    private static var tabsSessionFileURL: URL {
        statesDirectory.appendingPathComponent("tabs_session.json")
    }

    private static func legacyStateFileURL(for mode: AppMode) -> URL {
        let filename: String
        switch mode {
        case .viewer: filename = "viewer_state.json"
        case .search: filename = "search_state.json"
        case .narrator: filename = "author_state.json"
        #if os(iOS)
        default: filename = "viewer_state.json"
        #endif
        }
        return statesDirectory.appendingPathComponent(filename)
    }

    // MARK: - Per-Tab State Access

    /// Mengambil state di memori untuk mode tertentu pada tab ini.
    func getState(for mode: AppMode) -> ReaderState {
        switch mode {
        case .viewer: return viewerModeState
        case .search: return searchModeState
        case .narrator: return authorModeState
        #if os(iOS)
        default: return viewerModeState
        #endif
        }
    }

    /// Menetapkan state di memori untuk mode tertentu.
    func setState(_ state: ReaderState, for mode: AppMode) {
        switch mode {
        case .viewer: viewerModeState = state
        case .search: searchModeState = state
        case .narrator: authorModeState = state
        #if os(iOS)
        default: break
        #endif
        }
    }

    // MARK: - Snapshot Export & Import (Per-Tab)

    func exportTabSnapshot(currentMode: AppMode, components: [ReaderStateComponent?]) -> TabStateSnapshot {
        saveState(for: currentMode, components: components)
        return TabStateSnapshot(
            currentModeRaw: currentMode.rawValue,
            viewerState: viewerModeState,
            searchState: searchModeState,
            authorState: authorModeState
        )
    }

    func importTabSnapshot(_ snapshot: TabStateSnapshot) {
        viewerModeState = snapshot.viewerState
        searchModeState = snapshot.searchState
        authorModeState = snapshot.authorState
    }

    // MARK: - Multi-Tab Disk Persistence

    static func saveTabsSession(_ session: WindowTabsSession) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(session)
            try data.write(to: tabsSessionFileURL, options: [.atomic])
        } catch {
            Logger.reader.error("Failed to save tabs session: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func loadTabsSession() -> WindowTabsSession? {
        if fileManager.fileExists(atPath: tabsSessionFileURL.path) {
            do {
                let data = try Data(contentsOf: tabsSessionFileURL)
                let session = try JSONDecoder().decode(WindowTabsSession.self, from: data)
                if !session.tabs.isEmpty {
                    return session
                }
            } catch {
                Logger.reader.error("Failed to load tabs session: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Fallback migrasi dari file single-window lama
        let viewer = loadLegacyStateFromFile(for: .viewer)
        let search = loadLegacyStateFromFile(for: .search)
        let author = loadLegacyStateFromFile(for: .narrator)

        if viewer != nil || search != nil || author != nil {
            let lastMode = UserDefaults.standard.lastAppMode
            let migratedTab = TabStateSnapshot(
                currentModeRaw: lastMode.rawValue,
                viewerState: viewer ?? ReaderState(),
                searchState: search ?? ReaderState(),
                authorState: author ?? ReaderState()
            )
            let session = WindowTabsSession(selectedTabIndex: 0, tabs: [migratedTab])
            saveTabsSession(session)
            cleanupLegacyStateFiles()
            return session
        }

        return nil
    }

    private static func cleanupLegacyStateFiles() {
        for mode in [AppMode.viewer, AppMode.search, AppMode.narrator] {
            let fileURL = legacyStateFileURL(for: mode)
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func loadLegacyStateFromFile(for mode: AppMode) -> ReaderState? {
        let fileURL = legacyStateFileURL(for: mode)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ReaderState.self, from: data)
    }

    func persistToDisk() {
        #if os(macOS)
        (NSApp.delegate as? AppDelegate)?.scheduleSessionSave()
        #endif
    }

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
