//
//  AppDelegate.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var menu: NSMenu!
    @IBOutlet weak var viewMenu: NSMenu!
    @IBOutlet weak var showDiacriticMenuItem: NSMenuItem!

    fileprivate var mainWindowController: NSWindowController!

    fileprivate weak var quranWindow: NSWindow?

    fileprivate var keyWindow: MainWindow? {
        NSApp.keyWindow as? MainWindow
    }

    fileprivate var windowObserver: NSObjectProtocol?

    override init() {
        super.init()
        registerCustomFonts()
        // 1. Cek apakah path sudah diset
        if AppConfig.basePath == nil {
            // Jika belum ada, paksa user pilih folder
            selectFolder(nil)
        } else {
            // Inisiasi singleton main.db special.db
            _ = DatabaseManager.shared
        }

        UserDefaults.standard.register(defaults: ["AplFirstLaunch": true])
        let wc = WindowController(windowNibName: "WindowController")
        mainWindowController = wc
        guard let window = wc.window else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        buildViewMenu()

        BookConnection.tocTreeCache.countLimit = 20
        BookConnection.tocTreeCache.totalCostLimit = 50 * 1024 * 1024

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .current,
            using: { notif in
                guard let window = notif.object as? MainWindow else {
                    return
                }

                window.setAnnotationsPanelDelegate()
            })

        showDiacriticMenuItem.state = UserDefaults.standard.textViewShowHarakat ? .on : .off
        _ = ScreenTimeManager.shared // untuk init supaya pengaturan diload.

        UserDefaults.standard.register(defaults: [UserDefaults.TextViewKeys.lineHeight : 1.0])
        UserDefaults.standard.register(defaults: [UserDefaults.TextViewKeys.backgroundColorDark : 3])
        UserDefaults.standard.register(defaults: [UserDefaults.TextViewKeys.backgroundColorLight : 0])
        UserDefaults.standard.register(defaults: ["annotationsLayoutDirection": 1])
        // AppUpdate UserDefaults
        UserDefaults.standard.register(defaults: ["SuppressUpdateCheck": true])
        // Insert code here to initialize your application
        Task.detached(priority: .low) { [unowned self] in
            await Task.yield()
            await checkAppUpdates(true)
        }

        do {
            if let annotationsFolder = AppConfig.folder(
                for: AppConfig.annotationsAndResultsFolder
            ) {
                try AnnotationManager.shared.setupAnnotations(at: annotationsFolder)
            }
        } catch {
            ReusableFunc.showAlert(title: NSLocalizedString("errorFolderAnnotations", comment: error.localizedDescription), message: "")
        }
        
        do {
            if let resultsFolder = AppConfig.folder(
                for: AppConfig.annotationsAndResultsFolder
            ) {
                try ResultsHandler.shared.setupResultDatabase(at: resultsFolder)
            }
        } catch {
            ReusableFunc.showAlert(title: NSLocalizedString("errorFolderSearchResults", comment: error.localizedDescription), message: "")
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        ScreenTimeManager.shared.cancel()
        // Insert code here to tear down your application
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
    
    func changeBaseUrl(to newURL: URL) throws {

        let fm = FileManager.default

        // 1. Ambil base lama SEBELUM apa pun
        let oldURL = AppConfig.folder(
            for: AppConfig.annotationsAndResultsFolder
        )

        // 2. Validasi folder baru
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: newURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw StorageError.invalidDirectory
        }

        // 3. Tutup DB lama dulu
        // db = nil

        // 4. Security scope
        guard newURL.startAccessingSecurityScopedResource() else {
            throw StorageError.cannotAccessSecurityScope
        }

        defer {
            newURL.stopAccessingSecurityScopedResource()
        }

        // 5. Pindahkan data (kalau ada base lama)
        if let oldURL, fm.fileExists(atPath: oldURL.path) {
            let filesToMove = ["Annotations.sqlite", "SearchResults.sqlite"]
            
            for fileName in filesToMove {
                let sourceFile = oldURL.appendingPathComponent(fileName)
                let destFile = newURL.appendingPathComponent(fileName)
                
                // Cek apakah file sumber ada dan file tujuan belum ada
                if fm.fileExists(atPath: sourceFile.path) && !fm.fileExists(atPath: destFile.path) {
                    try fm.moveItem(at: sourceFile, to: destFile)
                } else {
                    try fm.removeItem(at: sourceFile)
                }
            }
        }

        // 6. SIMPAN bookmark TERAKHIR (commit)
        AppConfig.saveBookmark(url: newURL, key: AppConfig.annotationsAndResultsFolder)

        // 7. Re-init DB
        try AnnotationManager.shared.setupAnnotations(at: newURL)
        try ResultsHandler.shared.setupResultDatabase(at: newURL)
    }
    
    @IBAction func changeBaseFolder(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("personalFolder", comment: "")
        panel.prompt = NSLocalizedString("Choose Folder", comment: "")
        
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        panel.level = .floating
        
        let response = panel.runModal()

        if response == .OK, let url = panel.url {
            do {
                try changeBaseUrl(to: url)
            } catch {
                ReusableFunc.showAlert(title: "errorFolderAnnotations".localized, message: error.localizedDescription)
            }
        }
    }

    @IBAction fileprivate func checkUpdatesClicked(_ sender: Any?) {
        Task.detached { [unowned self] in
            await checkAppUpdates(false)
        }
    }

    @IBAction fileprivate func selectFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("appNeedAccess", comment: "")
        panel.prompt = NSLocalizedString("Choose Folder", comment: "")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        // Memastikan panel muncul di paling depan
        panel.level = .floating

        let response = panel.runModal()

        if response == .OK, let url = panel.url {
            // Simpan path
            AppConfig.saveBookmark(url: url, key: AppConfig.storageKey)
            if sender is NSMenuItem {
                ReusableFunc.showAlert(title: "masterFolderRenewed".localized, message: "masterFolderRenewedInfo".localized)
                NSApp.terminate(nil)
            }
            #if DEBUG
            print("Path disimpan: \(url.path)")
            #endif
        } else {
            // Jika user klik 'Cancel' atau menutup dialog tanpa memilih
            if sender is NSMenuItem {
                return
            }
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("AccessNeeded", comment: "Alert Memilih Folder Master")
            alert.informativeText = NSLocalizedString("FolderMasterPenjelasan", comment: "Informasi Alert Memilih Folder Master")
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            // Tutup aplikasi
            NSApplication.shared.terminate(nil)
        }
    }

    fileprivate func registerCustomFonts() {
        let fontFiles = [
            "KFGQPC Uthman Taha Naskh Bold.ttf",
            "KFGQPC Uthman Taha Naskh Regular.ttf",
            "Lateef-Regular.ttf",
            "Lateef-Bold.ttf",
            "Arabic Typesetting Regular.ttf",
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
            representedObject: .author, keyEquivalent: "3"
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
        bookInfo.keyEquivalentModifierMask = [.control]

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

        var topLevel: NSArray?

        Bundle.main.loadNibNamed(
            "QuranWindow",
            owner: self,
            topLevelObjects: &topLevel
        )

        guard
            let objects = topLevel as? [Any],
            let window = objects.first(where: { $0 is NSWindow }) as? QuranWindow
        else {
            return
        }

        quranWindow = window

        // optional: style mask tambahan
        window.styleMask.insert([
            .titled,
            .closable,
            .resizable,
            .miniaturizable,
            .utilityWindow
        ])

        let vc = QuranSplitVC()
        window.contentViewController = vc
        window.splitView = vc.splitView
        window.setFrameAutosaveName("QuranWindowFrame")

        window.makeKeyAndOrderFront(sender)
        window.isReleasedWhenClosed = false
    }

    @IBAction func showDiacritics(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on

        let isChecked = sender.state == .on
        UserDefaults.standard.textViewShowHarakat = isChecked

        NotificationCenter.default.post(
            name: .didChangeHarakat,
            object: nil,
            userInfo: ["on": isChecked,
                       "appDelegate": true
                      ]
        )
    }
    
    @objc private func showCurrentBookInfo(_ sender: NSMenuItem) {
        keyWindow?.currentSplitVC?.bookInfo(sender)
    }

    @IBAction func decreaseFontSize(_ sender: NSMenuItem) {
        TextViewState.shared.changeFontSize(by: -2)
    }

    @IBAction func increaseFontSize(_ sender: NSMenuItem) {
        TextViewState.shared.changeFontSize(by: 2)
    }
    
    @IBAction func newWindow(_ sender: Any) {
        let wc = WindowController(windowNibName: "WindowController")
        wc.window?.setFrameAutosaveName("MainWindow")
        if mainWindowController == nil {
         mainWindowController = wc
        }
        wc.showWindow(nil)
    }

    deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
        windowObserver = nil
    }
}
