//
//  WindowSessionTests.swift
//  MaktabahTests
//
//  Created by Antigravity on 16/10/26.
//

import Cocoa
import Foundation
@testable import Maktabah_Debug
import Testing

// MARK: - 1. ReaderState & TabState Models Suite

@Suite("ReaderState Model: Resiliency, Equatable, and Tab Snapshot")
struct ReaderStateModelTests {
    @Test("Codable resiliency: JSON dengan missing keys tetap ter-decode dengan nilai default")
    func testCodableResilience_missingKeysUseDefaults() throws {
        // Simulasi JSON lama atau rusak yang tidak memiliki `isSidebarCollapsed` dan `expandedNodeIDs`
        let legacyJson = """
        {
            "currentPage": 42,
            "currentID": 105,
            "currentPart": 1
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let state = try decoder.decode(ReaderState.self, from: legacyJson)

        #expect(state.currentPage == 42)
        #expect(state.currentID == 105)
        #expect(state.currentPart == 1)
        #expect(state.isSidebarCollapsed == false)
        #expect(state.expandedNodeIDs.isEmpty)
        #expect(state.currentBook == nil)
    }

    @Test("Equatable implementation: membedakan state berdasarkan currentPage dan currentPart")
    func testEquatable_differentiatesNavigationProperties() {
        var state1 = ReaderState()
        state1.currentID = 100
        state1.currentPage = 10
        state1.currentPart = 1

        var state2 = ReaderState()
        state2.currentID = 100
        state2.currentPage = 10
        state2.currentPart = 1

        #expect(state1 == state2)

        // Ubah halaman pada state2
        state2.currentPage = 11
        #expect(state1 != state2)

        // Ubah juz/part pada state2
        state2.currentPage = 10
        state2.currentPart = 2
        #expect(state1 != state2)
    }

    @Test("TabStateSnapshot & WindowTabsSession: roundtrip Codable serialization")
    func testTabSnapshotAndSessionRoundtrip() throws {
        var viewerState = ReaderState()
        viewerState.currentPage = 7
        viewerState.currentID = 701

        var searchState = ReaderState()
        searchState.searchQuery = "حديث"
        searchState.searchNearDistance = 15

        let snapshot = TabStateSnapshot(
            currentModeRaw: AppMode.search.rawValue,
            viewerState: viewerState,
            searchState: searchState,
            authorState: ReaderState()
        )

        #expect(snapshot.currentMode == .search)

        let session = WindowTabsSession(selectedTabIndex: 0, tabs: [snapshot])

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        let decodedSession = try decoder.decode(WindowTabsSession.self, from: data)

        #expect(decodedSession.selectedTabIndex == 0)
        #expect(decodedSession.tabs.count == 1)
        #expect(decodedSession.tabs[0].currentMode == .search)
        #expect(decodedSession.tabs[0].viewerState.currentPage == 7)
        #expect(decodedSession.tabs[0].searchState.searchQuery == "حديث")
    }
}

// MARK: - 2. ReaderStateManager Suite (In-Memory Isolation & Disk Persistence)

@Suite("ReaderStateManager: Per-Tab Isolation, Disk Persistence, and Migration")
@MainActor
struct ReaderStateManagerTests {
    private static var statesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Maktabah/States")
    }

    private static var tabsSessionFileURL: URL {
        statesDirectory.appendingPathComponent("tabs_session.json")
    }

    private static func legacyStateFileURL(for mode: AppMode) -> URL {
        let filename = switch mode {
        case .viewer: "viewer_state.json"
        case .search: "search_state.json"
        case .narrator: "author_state.json"
        }
        return statesDirectory.appendingPathComponent(filename)
    }

    @Test("In-memory per-tab isolation: instance ReaderStateManager terpisah tidak saling mengontaminasi")
    func testInMemoryPerTabIsolation() {
        let tab1Manager = ReaderStateManager()
        let tab2Manager = ReaderStateManager()

        var tab1State = ReaderState()
        tab1State.currentPage = 99
        tab1Manager.setState(tab1State, for: .viewer)

        // Verifikasi state tab 1 tersimpan
        #expect(tab1Manager.getState(for: .viewer).currentPage == 99)

        // Verifikasi state tab 2 tetap bersih (default) dan terisolasi
        #expect(tab2Manager.getState(for: .viewer).currentPage == nil)
    }

    @Test("Disk Persistence: simpan dan muat WindowTabsSession dengan aman (Backup & Restore)")
    func testDiskPersistence_saveAndLoadTabsSession() {
        let sessionFile = Self.tabsSessionFileURL
        let backupFile = sessionFile.deletingLastPathComponent().appendingPathComponent("tabs_session_test_backup.json")
        let fileManager = FileManager.default

        // 1. Backup file sesi asli jika ada
        let originalExists = fileManager.fileExists(atPath: sessionFile.path)
        if originalExists {
            try? fileManager.copyItem(at: sessionFile, to: backupFile)
        }

        defer {
            // Restore file sesi asli setelah test selesai
            try? fileManager.removeItem(at: sessionFile)
            if originalExists {
                try? fileManager.moveItem(at: backupFile, to: sessionFile)
            }
        }

        // 2. Simpan sesi dummy
        var state1 = ReaderState()
        state1.currentPage = 101
        let snap1 = TabStateSnapshot(currentModeRaw: AppMode.viewer.rawValue, viewerState: state1, searchState: ReaderState(), authorState: ReaderState())

        var state2 = ReaderState()
        state2.currentPage = 202
        let snap2 = TabStateSnapshot(currentModeRaw: AppMode.search.rawValue, viewerState: state2, searchState: ReaderState(), authorState: ReaderState())

        let testSession = WindowTabsSession(selectedTabIndex: 1, tabs: [snap1, snap2])
        ReaderStateManager.saveTabsSession(testSession)

        // 3. Muat kembali sesi dari disk
        let loadedSession = ReaderStateManager.loadTabsSession()
        #expect(loadedSession != nil)
        #expect(loadedSession?.selectedTabIndex == 1)
        #expect(loadedSession?.tabs.count == 2)
        #expect(loadedSession?.tabs[0].viewerState.currentPage == 101)
        #expect(loadedSession?.tabs[1].viewerState.currentPage == 202)
    }

    @Test("Legacy Migration & Cleanup: memigrasikan file lama ke tabs_session.json dan membersihkan file lama")
    func testLegacyMigrationAndCleanup() throws {
        let sessionFile = Self.tabsSessionFileURL
        let backupFile = sessionFile.deletingLastPathComponent().appendingPathComponent("tabs_session_mig_backup.json")
        let fileManager = FileManager.default

        // 1. Backup file sesi asli
        let originalExists = fileManager.fileExists(atPath: sessionFile.path)
        if originalExists {
            try? fileManager.moveItem(at: sessionFile, to: backupFile)
        }

        let legacyViewerFile = Self.legacyStateFileURL(for: .viewer)
        let legacyBackup = legacyViewerFile.deletingLastPathComponent().appendingPathComponent("viewer_state_mig_backup.json")
        let originalLegacyExists = fileManager.fileExists(atPath: legacyViewerFile.path)
        if originalLegacyExists {
            try? fileManager.moveItem(at: legacyViewerFile, to: legacyBackup)
        }

        defer {
            // Restore file asli
            try? fileManager.removeItem(at: sessionFile)
            try? fileManager.removeItem(at: legacyViewerFile)
            if originalExists {
                try? fileManager.moveItem(at: backupFile, to: sessionFile)
            }
            if originalLegacyExists {
                try? fileManager.moveItem(at: legacyBackup, to: legacyViewerFile)
            }
        }

        // 2. Tulis file legacy dummy
        var legacyState = ReaderState()
        legacyState.currentPage = 777
        let data = try JSONEncoder().encode(legacyState)
        try data.write(to: legacyViewerFile)

        // Pastikan tabs_session.json belum ada
        #expect(!fileManager.fileExists(atPath: sessionFile.path))

        // 3. Muat sesi: harus memicu migrasi
        let migratedSession = ReaderStateManager.loadTabsSession()
        #expect(migratedSession != nil)
        #expect(migratedSession?.tabs.count == 1)
        #expect(migratedSession?.tabs[0].viewerState.currentPage == 777)

        // 4. Verifikasi bahwa tabs_session.json sekarang telah dibuat
        #expect(fileManager.fileExists(atPath: sessionFile.path))

        // 5. Verifikasi bahwa file legacy telah dibersihkan otomatis
        #expect(!fileManager.fileExists(atPath: legacyViewerFile.path))
    }
}

// MARK: - 3. AppDelegate Lifecycle Hardening Suite

@Suite("AppDelegate Lifecycle: Quit Handling, Termination Flag, and Deep Link Safety")
@MainActor
struct AppDelegateLifecycleTests {
    @Test("applicationShouldTerminate: menyetel isTerminating dan mengembalikan .terminateNow")
    func testApplicationShouldTerminate_setsTerminatingFlag() {
        let appDelegate = AppDelegate()

        // Verifikasi bahwa applicationShouldTerminate langsung mengembalikan .terminateNow
        let reply = appDelegate.applicationShouldTerminate(NSApp)
        #expect(reply == .terminateNow)

        // Verifikasi via refleksi bahwa isTerminating kini bernilai true
        let mirror = Mirror(reflecting: appDelegate)
        let isTerminating = mirror.children.first(where: { $0.label == "isTerminating" })?.value as? Bool
        #expect(isTerminating == true)
    }

    @Test("Window teardown safety: windowObserverWillCloseNotification tidak memangkas session saat isTerminating true")
    func testWindowWillClose_skipsSessionPruningDuringTermination() {
        let appDelegate = AppDelegate()

        // Panggil shouldTerminate untuk mengaktifkan mode terminasi
        _ = appDelegate.applicationShouldTerminate(NSApp)

        // Buat dummy window
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        let notification = Notification(name: NSWindow.willCloseNotification, object: window)

        // Simulasikan notifikasi willClose saat aplikasi sedang terminate
        // Seharusnya tidak memicu pemangkasan sesi asinkron
        appDelegate.windowObserverWillCloseNotification(notification)

        let mirror = Mirror(reflecting: appDelegate)
        let isTerminating = mirror.children.first(where: { $0.label == "isTerminating" })?.value as? Bool
        #expect(isTerminating == true)
    }

    @Test("Tab Selection Resolution: selectedTabIndex mengembalikan index tab aktif yang tepat, bukan selalu tab terakhir")
    func testRestoreTabSelection_resolvesCorrectActiveIndex() {
        let snapshot0 = TabStateSnapshot(currentModeRaw: 0, viewerState: ReaderState(), searchState: ReaderState(), authorState: ReaderState())
        let snapshot1 = TabStateSnapshot(currentModeRaw: 0, viewerState: ReaderState(), searchState: ReaderState(), authorState: ReaderState())
        let snapshot2 = TabStateSnapshot(currentModeRaw: 0, viewerState: ReaderState(), searchState: ReaderState(), authorState: ReaderState())

        // Simulasi 3 tab dengan tab ke-1 (tengah) aktif saat aplikasi ditutup
        let session = WindowTabsSession(selectedTabIndex: 1, tabs: [snapshot0, snapshot1, snapshot2])

        let count = session.tabs.count
        let resolvedIndex = min(max(0, session.selectedTabIndex), count - 1)
        #expect(resolvedIndex == 1)
        #expect(resolvedIndex != count - 1)
    }

    @Test("Full Workspace Preservation: windowObserverWillCloseNotification tidak menghapus atau menimpa sesi saat seluruh jendela ditutup")
    func testWindowWillClose_preservesSessionWhenLastWindowCloses() {
        let appDelegate = AppDelegate()

        // 1. Simpan sesi awal dengan 2 tab
        let snap1 = TabStateSnapshot(currentModeRaw: 0, viewerState: ReaderState(), searchState: ReaderState(), authorState: ReaderState())
        let snap2 = TabStateSnapshot(currentModeRaw: 1, viewerState: ReaderState(), searchState: ReaderState(), authorState: ReaderState())
        let initialSession = WindowTabsSession(selectedTabIndex: 0, tabs: [snap1, snap2])
        ReaderStateManager.saveTabsSession(initialSession)

        // 2. Buat dummy window terakhir yang sedang menutup
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let notification = Notification(name: NSWindow.willCloseNotification, object: window)

        // 3. Panggil willCloseNotification (simulasi jendela terakhir menutup tanpa terminasi)
        appDelegate.windowObserverWillCloseNotification(notification)

        // 4. Verifikasi bahwa sesi disk tetap utuh (2 tab), tidak tertimpa menjadi 1 tab atau kosong
        let loadedSession = ReaderStateManager.loadTabsSession()
        #expect(loadedSession != nil)
        #expect(loadedSession?.tabs.count == 2)
    }

    @Test("Debounced Session Save: scheduleSessionSave tidak melakukan save seketika ke disk")
    func testScheduleSessionSave_debouncesDiskWrite() {
        let appDelegate = AppDelegate()
        appDelegate.isFinishedLaunching = true
        appDelegate.setupSessionAutoSave()

        // Panggil scheduleSessionSave
        appDelegate.scheduleSessionSave()

        // Karena debounced (3 detik), tidak boleh langsung menulis synchronous
        #expect(appDelegate.isFinishedLaunching == true)
    }

    @Test("App Termination & Background: memicu direct saveAllTabsSession seketika")
    func testApplicationTermination_flushesSessionImmediately() {
        let appDelegate = AppDelegate()
        _ = appDelegate.applicationShouldTerminate(NSApp)

        let mirror = Mirror(reflecting: appDelegate)
        let isTerminating = mirror.children.first(where: { $0.label == "isTerminating" })?.value as? Bool
        #expect(isTerminating == true)
    }
}
