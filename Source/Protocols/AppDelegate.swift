//
//  AppDelegate.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//  Restorable state saat membuka jendela baru
//

import Cocoa
import SwiftUI
import CloudKit
import UniformTypeIdentifiers
#if DIRECT_DISTRIBUTION
import Sparkle
#endif

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var menu: NSMenu!
    @IBOutlet weak var viewMenu: NSMenu!
    @IBOutlet weak var appUpdatesMenuItem: NSMenuItem!
    @IBOutlet weak var showDiacriticMenuItem: NSMenuItem!

    @IBOutlet weak var controlMenu: NSMenu!
    @IBOutlet weak var clickEditAnnotationMenuItem: NSMenuItem!
    @IBOutlet weak var screenTimeMenuItem: NSMenuItem!
    
    fileprivate var mainWindowController: NSWindowController!

    fileprivate weak var quranWindow: NSWindow?
    fileprivate weak var settingsWindow: NSWindow?

    fileprivate var keyWindow: MainWindow? {
        NSApp.keyWindow as? MainWindow
    }

    fileprivate var windowObserver: NSObjectProtocol?

    #if DIRECT_DISTRIBUTION
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    #endif

    // Core Update Properties
    var coreUpdateAlertWindow: NSWindow?
    var coreDownloadProgressWindow: NSWindow?
    var coreDownloadProgressState: CoreDownloadProgressState?
    var coreDownloadProgressView: CoreDownloadProgressView?
    var coreDownloader: CoreDatabaseDownloader?

    override init() {
        super.init()
        registerCustomFonts()
        AppConfig.initializeMode()
        CoreDatabaseBootstrap.run()

        UserDefaults.standard.register(defaults: ["AplFirstLaunch": true])
        let wc = WindowController()
        mainWindowController = wc
        guard let window = wc.window else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        restorePersistedState(mainWindowController.window as? MainWindow)
        buildViewMenu()

        BookConnection.tocTreeCache.countLimit = 20
        BookConnection.tocTreeCache.totalCostLimit = 50 * 1024 * 1024

        setupWindowObserver()

        controlMenu.delegate = self
        _ = ScreenTimeManager.shared // untuk init supaya pengaturan diload.

        UserDefaults.standard.register(defaults: [UserDefaults.TextViewKeys.lineHeight : 1.0])
        UserDefaults.standard.register(defaults: [UserDefaults.TextViewKeys.backgroundColorDark : 3])
        UserDefaults.standard.register(defaults: [UserDefaults.TextViewKeys.backgroundColorLight : 0])
        UserDefaults.standard.register(defaults: ["annotationsLayoutDirection": 1])

        if UserDefaults.standard.data(forKey: AppConfig.annotationsAndResultsFolder) == nil {
            UserDefaults.standard.register(defaults: [AppConfig.useICloudKey: true])
        }

        #if DIRECT_DISTRIBUTION
        UserDefaults.standard.register(
            defaults: [UserDefaults.autoCheckAppUpdatesKey : true]
        )
        Task.detached(priority: .low) { [unowned self] in
            if !UserDefaults.standard.autoCheckAppUpdates { return }
            await Task.yield()
            await checkAppUpdates(true)
        }
        #else
        appUpdatesMenuItem.isHidden = true
        #endif

        AppConfig.setupAnnotationsAndResults()
        CloudKitSyncManager.shared.initializeOnLaunch()
        // Register for CloudKit remote notifications
        NSApplication.shared.registerForRemoteNotifications()

        /*
        showWelcomeScreenIfNeeded()
         */

        // Check for core database updates (blocking, throttled 6 months)
        checkCoreDatabaseUpdate()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        Task {
            try await Task.sleep(for: .seconds(5))
            CloudKitSyncManager.shared.fetchChanges()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        CloudKitSyncManager.shared.fetchChanges()
    }

    /*
    func showWelcomeScreenIfNeeded() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let lastVersion = UserDefaults.standard.string(forKey: "lastVersionPrompted") ?? ""

        if lastVersion != currentVersion {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
                styleMask: [.fullSizeContentView, .titled],
                backing: .buffered,
                defer: false
            )

            let contentView = WelcomeScreenView { [weak self, weak window] in
                guard let window else { return }
                UserDefaults.standard.set(currentVersion, forKey: "lastVersionPrompted")

                if let mainWin = self?.mainWindowController?.window, mainWin.sheets.contains(window) {
                    mainWin.endSheet(window)
                } else {
                    window.close()
                }
            }

            let hostingView = NSHostingView(rootView: contentView)
            window.contentView = hostingView
            window.title = "What's New"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false

            if let mainWin = mainWindowController?.window {
                mainWin.beginSheet(window)
            } else {
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
     */

    func applicationWillTerminate(_ aNotification: Notification) {
        CloudKitCoreManager.shared.syncWorker()
        CloudKitSyncManager.shared.resetSyncingKey(syncing: false)
        ScreenTimeManager.shared.cancel()
        BookArchiveIntegrator.shared.vacuumPendingArchives()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        mainWindowController = nil
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            newWindow(sender)
        }
        return true
    }

    // MARK: - Window Management

    func setupWindowObserver() {
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .current,
            using: { [unowned self] notif in
                guard let window = notif.object as? MainWindow,
                      let windowController = window.windowController as? WindowController
                else {
                    return
                }

                if mainWindowController != windowController {
                    mainWindowController = windowController
                }
            }
        )

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .current
        ) { [unowned self] notif in
            guard let window = notif.object as? MainWindow else {
                return
            }

            window.splitVC.persistCurrentStateToDisk()
            if mainWindowController?.window === window {
                mainWindowController = nil
            }
        }
    }

    // MARK: - App Launch

    func restorePersistedState(_ window: MainWindow?) {
        guard let window else {
            #if DEBUG
                print("mainWindowController window nil")
            #endif
            return
        }

        window.setupContentView()

        guard let splitVC = window.contentViewController as? SplitVC else {
            #if DEBUG
                print("Cannot restore state: SplitVC not found")
            #endif
            return
        }
        
        // Get last active mode
        let lastMode = window.currentMode

        #if DEBUG
            print("Restoring app to last mode: \(lastMode)")
        #endif

        splitVC.setupForMode(lastMode)
        splitVC.setupAutoSave()

        // Ini baru load state yang dibutuhkan
        splitVC.stateManager.restoreState(
            for: lastMode,
            components: splitVC.components(for: lastMode)
        )

        // Switch to last mode (this will restore the state)
        window.setupView()
        window.displayIfNeeded()
    }

    @IBAction func openSettings(_ sender: Any?) {
        if let settingsWindow {
            settingsWindow.center()
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = SettingsView()
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 520)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = String(localized: "Settings")
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(sender)

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @IBAction func downloadLibrary(_ sender: Any?) {
        SettingsActions.downloadSelectiveLibrary()
    }

    @IBAction fileprivate func checkUpdatesClicked(_ sender: Any?) {
        #if DIRECT_DISTRIBUTION
        Task.detached { [unowned self] in
            await checkAppUpdates(false)
        }
        #endif
    }

    @IBAction fileprivate func checkBooksUpdates(_ sender: Any?) {
        // 1. Inisialisasi SwiftUI View
        let contentView = UpdateView()

        // 2. Bungkus dalam NSHostingView
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)

        // 3. Buat Window baru dengan style mask yang sudah benar dari awal
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.fullSizeContentView, .titled, .resizable], // ← Langsung pakai di sini
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "Books Updates".localized
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.contentView = hostingView
        window.isReleasedWhenClosed = false

        // 4. Jalankan sebagai Modal
        NSApp.runModal(for: window)
    }

    @IBAction func importOfflineBook(_ sender: Any?) {
        showOfflineImportWindow()
    }

    private func showOfflineImportWindow() {
        let contentView = OfflineImportFormView(onImport: { [unowned self]
            (url: URL, metadata: BookMetadata, authorRow: [String: Any]?) async in
            await performCustomImport(
                url: url,
                metadata: metadata,
                authorRow: authorRow
            )
        })

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 600)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.fullSizeContentView, .titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.titleVisibility = .hidden
        window.title = "Import Offline Book"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil as Any?)
    }

    @MainActor
    private func performCustomImport(url: URL, metadata: BookMetadata, authorRow: [String: Any]?) async {
        do {
            let result = try await BookUpdateManager
                .shared.importOfflineUpdate (
                    from: url,
                    providedMetadata: metadata,
                    authorRow: authorRow
                )

            try? await LibraryDataManager.shared.processBookUpdates([result])
            BookUpdateManager.shared.integrateBooks(metadata: metadata)

            ReusableFunc.showAlert(
                title: String(localized: .importSuccessTitle),
                message: String(localized: .importSuccessDesc)
            )
        } catch {
            ReusableFunc.showAlert(
                title: "Import Error",
                message: error.localizedDescription
            )

            #if DEBUG
                print("[Offline Import] Failed to import book from \(url.lastPathComponent): \(error)")
            #endif
        }
    }

    fileprivate func registerCustomFonts() {
        let fontFiles = [
            "UthmanTN1-Ver10.otf",
            "Lateef-Regular.ttf",
            "Lateef-Bold.ttf",
            "ScheherazadeNew-Regular.ttf",
        ]

        for fontFile in fontFiles {
            // Buat URL sementara dari String
            let tempURL = URL(fileURLWithPath: fontFile)

            // Ambil nama tanpa ekstensi dan ekstensinya
            let fileNameWithoutExtension = tempURL.deletingPathExtension().lastPathComponent
            let fileExtension = tempURL.pathExtension

            guard let fontURL = Bundle.main.url(forResource: fileNameWithoutExtension,
                                                withExtension: fileExtension) else {
                print("Font file tidak ditemukan: \(fontFile)")
                continue
            }

            guard let fontDataProvider = CGDataProvider(url: fontURL as CFURL) else {
                print("Tidak bisa load font data: \(fontFile)")
                continue
            }

            guard let font = CGFont(fontDataProvider) else {
                print("Tidak bisa create CGFont: \(fontFile)")
                continue
            }

            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterGraphicsFont(font, &error) {
                print("Error registering font: \(fontFile)")
                if let error = error?.takeRetainedValue() {
                    print("Error detail: \(error)")
                }
            } else {
                if let postScriptName = font.postScriptName {
                    print("✅ Font berhasil diregister: \(postScriptName)")
                }
            }
        }
    }

    fileprivate func buildMenu(_ title: String, image: String, representedObject: AppMode? = nil, keyEquivalent: String) -> NSMenuItem {
        let menu = NSMenuItem()
        menu.representedObject = representedObject
        menu.keyEquivalent = keyEquivalent
        menu.title = title
        menu.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        menu.target = self
        menu.isEnabled = true
        return menu
    }

    fileprivate func buildViewMenu() {
        let reader = buildMenu(
            NSLocalizedString("Reader", comment: ""),  image: "book.fill",
            representedObject: .viewer, keyEquivalent: "1"
        )

        let search = buildMenu(
            NSLocalizedString("Finder", comment: ""), image: "text.viewfinder",
            representedObject: .search, keyEquivalent: "2"
        )

        let author = buildMenu(
            NSLocalizedString("Rowi", comment: ""), image: "person.text.rectangle.fill",
            representedObject: .narrator, keyEquivalent: "3"
        )

        let annotations = buildMenu(
            NSLocalizedString("Annotations", comment: ""),
            image: "quote.closing", keyEquivalent: "p"
        )

        let daftarIsi = buildMenu(
            NSLocalizedString("toggleTableOfContents", comment: ""),
            image: "doc.append.fill", keyEquivalent: "l"
        )

        let viewOpt = buildMenu(
            NSLocalizedString("ViewOptions", comment: ""),
            image: "textformat.size.ar", keyEquivalent: "o"
        )

        let pageSlider = buildMenu(
            NSLocalizedString("PageSlider", comment: ""),
            image: "slider.horizontal.below.square.filled.and.square", keyEquivalent: "p"
        )

        let quranWindow = buildMenu(NSLocalizedString("QuranMenuBar", comment: ""), image: "character.book.closed.ar", keyEquivalent: "u")
        
        let bookInfoImage: String
        
        if #available(macOS 15.4, *) {
            bookInfoImage = "info.circle.text.page.rtl"
        } else {
            bookInfoImage = "info.circle"
        }
        
        let bookInfo = buildMenu(NSLocalizedString("BookInfo", comment: ""), image: bookInfoImage, keyEquivalent: "i")

        let resetCurrentView = buildMenu(
            NSLocalizedString("ResetCurrentView", comment: ""),
            image: "arrow.counterclockwise",
            keyEquivalent: "r"
        )

        bookInfo.keyEquivalentModifierMask = [.control]
        resetCurrentView.keyEquivalentModifierMask = [.control, .option]
        annotations.keyEquivalentModifierMask = [.control]
        daftarIsi.keyEquivalentModifierMask = [.control, .option]
        pageSlider.keyEquivalentModifierMask = [.control, .option]
        viewOpt.keyEquivalentModifierMask = [.control, .option]
        quranWindow.keyEquivalentModifierMask = [.control]

        reader.action = #selector(switchMode(_:))
        search.action = #selector(switchMode(_:))
        author.action = #selector(switchMode(_:))

        annotations.action = #selector(showAnnotations)
        bookInfo.action = #selector(showCurrentBookInfo(_:))
        daftarIsi.action = #selector(showTOC)
        viewOpt.action = #selector(viewOptions)
        pageSlider.action = #selector(navigationSlider)
        quranWindow.action = #selector(displayQuranWindow(_:))
        resetCurrentView.action = #selector(resetCurrentViewState)

        viewMenu.insertItem(.separator(), at: viewMenu.items.count - 1)
        viewMenu.insertItem(resetCurrentView, at: viewMenu.items.count - 1)
        viewMenu.insertItem(.separator(), at: viewMenu.items.count - 1)
        viewMenu.insertItem(quranWindow, at: viewMenu.items.count - 1)
        viewMenu.insertItem(annotations, at: viewMenu.items.count - 1)
        viewMenu.insertItem(bookInfo, at: viewMenu.items.count - 1)
        viewMenu.insertItem(viewOpt, at: viewMenu.items.count - 1)
        viewMenu.insertItem(pageSlider, at: viewMenu.items.count - 1)
        viewMenu.insertItem(daftarIsi, at: viewMenu.items.count - 1)
        viewMenu.insertItem(.separator(), at: viewMenu.items.count - 1)
        viewMenu.insertItem(reader, at: viewMenu.items.count - 1)
        viewMenu.insertItem(search, at: viewMenu.items.count - 1)
        viewMenu.insertItem(author, at: viewMenu.items.count - 1)
        viewMenu.insertItem(.separator(), at: viewMenu.items.count - 1)
    }

    @objc private func resetCurrentViewState() {
        guard let keyWindow else { return }
        let splitVC = keyWindow.splitVC
        let mode = UserDefaults.standard.lastAppMode
        splitVC.stateManager.cleanUpState(
            for: mode,
            components: splitVC.components(for: mode)
        )
    }

    @objc private func viewOptions() {
        guard let keyWindow else { return }
        keyWindow.viewOptions(self)
    }

    @objc private func navigationSlider() {
        guard let keyWindow else { return }
        keyWindow.navigationPage(self)
    }

    @objc private func showTOC() {
        guard let keyWindow else { return }
        keyWindow.sidebarTrailing(self)
    }

    @objc private func showAnnotations() {
        guard let keyWindow else { return }
        keyWindow.displayAllNotations(nil)
    }

    @objc private func switchMode(_ sender: NSMenuItem) {
        guard let keyWindow else { return }
        keyWindow.switchMode(sender)
    }

    @objc private func displayQuranWindow(_ sender: Any) {
        if let window = quranWindow {
            window.makeKeyAndOrderFront(sender)
            return
        }
        let rect = NSRect(x: 196, y: 240, width: 480, height: 270)
        let style: NSWindow.StyleMask = [
            .titled,
            .closable,
            .resizable,
            .miniaturizable,
            .fullSizeContentView,
            .utilityWindow
        ]

        let window = QuranWindow(
            contentRect: rect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = "القرآن الكريم"
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: .vibrantLight)

        quranWindow = window

        let vc = QuranSplitVC()
        window.contentViewController = vc
        window.splitView = vc.splitView
        window.setFrameAutosaveName("QuranWindowFrame")

        window.makeKeyAndOrderFront(sender)
        window.isReleasedWhenClosed = false
    }

    @IBAction private func extendScreenTime(_ sender: NSMenuItem) {
        let screenTime = ScreenTimeManager.shared
        sender.state == .off ? screenTime.extend() : screenTime.cancel()
    }

    @IBAction private func clickableAnnotation(_ sender: NSMenuItem) {
        let shouldEnable = sender.state == .off
        TextViewState.shared.setClickableAnnotation(shouldEnable)
    }

    @IBAction func showDiacritics(_ sender: NSMenuItem) {
        TextViewState.shared.toggleHarakat()
    }
    
    @objc private func showCurrentBookInfo(_ sender: NSMenuItem) {
        keyWindow?.splitVC.bookInfo(sender)
    }

    @IBAction func decreaseFontSize(_ sender: NSMenuItem) {
        TextViewState.shared.changeFontSize(by: -2)
    }

    @IBAction func increaseFontSize(_ sender: NSMenuItem) {
        TextViewState.shared.changeFontSize(by: 2)
    }
    
    @IBAction func newWindow(_ sender: Any) {
        let wc = WindowController()
        wc.window?.setFrameAutosaveName("MainWindow")

        guard let w = wc.window as? MainWindow else { return }

        if mainWindowController == nil {
            restorePersistedState(w)
        } else {
            w.setupContentView(restoreState: false)
        }

        mainWindowController = wc

        w.makeKeyAndOrderFront(sender)
        w.displayIfNeeded()
    }

    deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === controlMenu else { return }

        showDiacriticMenuItem.state = TextViewState.shared
            .showHarakat ? .on : .off

        clickEditAnnotationMenuItem.state = TextViewState.shared
            .clickableAnnotation ? .on : .off

        screenTimeMenuItem.state = ScreenTimeManager.shared
            .isExtended() ? .on : .off
    }
}
