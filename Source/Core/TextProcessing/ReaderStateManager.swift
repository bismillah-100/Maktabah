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
    private var lifecycleToken: NotificationToken?

    init() {
        lifecycleToken = NotificationToken(
            token: NotificationCenter.default.addObserver(
                forName: .bookLifecycleDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let event = notification.bookLifecycleEvent else { return }
                MainActor.assumeIsolated { [weak self] in
                    self?.applyLifecycleEvent(event)
                }
            }
        )
    }

    private func applyLifecycleEvent(_ event: BookLifecycleEvent) {
        viewerModeState = Self.sanitizedState(viewerModeState, for: event)
        searchModeState = Self.sanitizedState(searchModeState, for: event)
        authorModeState = Self.sanitizedState(authorModeState, for: event)

        if case .libraryFolderChanged = event {
            try? Self.fileManager.removeItem(at: Self.tabsSessionFileURL)
        } else if case .bundledDataCleaned = event {
            try? Self.fileManager.removeItem(at: Self.tabsSessionFileURL)
        }
    }

    private static func sanitizedState(_ state: ReaderState, for event: BookLifecycleEvent) -> ReaderState {
        var next = state
        switch event {
        case let .deleted(bookIds, _, removedFromCatalog):
            let deletedTables = Set(bookIds.map { "b\($0)" })
            if let book = next.currentBook, bookIds.contains(book.id) {
                let isRemoved = removedFromCatalog.contains(book.id) || (AppConfig.isUsingBundleMode && !BookArchiveIntegrator.shared.isBookIntegrated(book))
                if isRemoved {
                    clearBookFields(&next)
                }
            }
            if let results = next.searchResults {
                next.searchResults = results.filter { !deletedTables.contains($0.tableName) }
            }

        case let .idChanged(oldId, newId, _, _):
            if next.currentBook?.id == oldId, let fresh = LibraryDataManager.shared.booksById[newId] {
                next.currentBook = fresh
            }
            if let results = next.searchResults {
                let oldTable = "b\(oldId)"
                let newTable = "b\(newId)"
                let newTitle = LibraryDataManager.shared.booksById[newId]?.book
                next.searchResults = results.map { item in
                    guard item.tableName == oldTable else { return item }
                    return SearchResultItem(
                        archive: item.archive,
                        tableName: newTable,
                        bookId: item.bookId,
                        bookTitle: newTitle ?? item.bookTitle,
                        page: item.page,
                        part: item.part,
                        attributedText: item.attributedText
                    )
                }
            }

        case let .updated(bookIds, _, _), let .integrated(bookIds, _):
            if let currentId = next.currentBook?.id, bookIds.contains(currentId),
               let fresh = LibraryDataManager.shared.booksById[currentId]
            {
                next.currentBook = fresh
            }

        case .libraryFolderChanged, .bundledDataCleaned:
            next = ReaderState()
        }
        return next
    }

    private static func clearBookFields(_ state: inout ReaderState) {
        state.currentBook = nil
        state.currentPage = nil
        state.currentID = nil
        state.currentPart = nil
        state.expandedNodeIDs = []
        state.sidebarScrollPosition = nil
        state.scrollPosition = nil
        state.selectedRange = nil
    }

    private static let fileManager = FileManager.default

    private static var customStatesDirectory: URL?

    private static let defaultStatesDirectory: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let maktabahDir = appSupport.appendingPathComponent("Maktabah/States")
        if !fileManager.fileExists(atPath: maktabahDir.path) {
            try? fileManager.createDirectory(at: maktabahDir, withIntermediateDirectories: true)
        }
        return maktabahDir
    }()

    static var statesDirectory: URL {
        customStatesDirectory ?? defaultStatesDirectory
    }

    #if DEBUG
    static func setCustomStatesDirectoryForTesting(_ url: URL?) {
        customStatesDirectory = url
    }
    #endif

    static var tabsSessionFileURL: URL {
        statesDirectory.appendingPathComponent("tabs_session.json")
    }

    static func legacyStateFileURL(for mode: AppMode) -> URL {
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
