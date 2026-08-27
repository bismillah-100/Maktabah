//
//  ViewOptions.swift
//  maktab
//
//  Created by MacBook on 30/11/25.
//

import Cocoa

@MainActor
class ViewOptions: NSViewController {

    @IBOutlet weak var fontSmaller: NSButton!
    @IBOutlet weak var fontLarger: NSButton!
    @IBOutlet weak var fontOptions: NSPopUpButton!
    @IBOutlet weak var hStack: NSStackView!
    @IBOutlet weak var harakatCheckbox: NSButton!
    @IBOutlet weak var screenTimeCheckbox: NSButton!
    @IBOutlet weak var xBtn: NSButton!
    @IBOutlet weak var lineHeightOptions: NSPopUpButton!
    @IBOutlet weak var annSetButton: NSButton!
    
    // State
    private let state = TextViewState.shared

    let defaults = UserDefaults.standard

    var isDarkMode: Bool {
            let appearance = NSApp.effectiveAppearance
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

    var popover: Bool = true

    let screenTimeManager = ScreenTimeManager.shared
    private let fontPanelItemTitle = "Font Panel..."

    override func viewDidLoad() {
        super.viewDidLoad()
        xBtn.isHidden = popover
        setupFontOptions()
        loadSettings()
        setupBackgroundOptions()
        loadHarakatSetting()
        screenTimeCheckbox.state = screenTimeManager.isExtended() ? .on : .off
        loadAnnotationSetting()
        fontOptions.userInterfaceLayoutDirection = .leftToRight
        fontOptions.menu?.userInterfaceLayoutDirection = .leftToRight
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setupLineHeightPopUpButton()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        if NSFontManager.shared.target === self {
            NSFontManager.shared.target = nil
        }
    }

    private func loadHarakatSetting() {
        let showHarakat = UserDefaults.standard.textViewShowHarakat

        harakatCheckbox.state = showHarakat ? .on : .off
    }
    
    private func loadAnnotationSetting() {
        let enable = UserDefaults.standard.enableAnnotationClick
        
        annSetButton.state = enable ? .on : .off
    }

    @IBAction func displayTasykil(_ sender: NSButton) {
        state.toggleHarakat()  // ← simpel!
    }

    @IBAction func extendScreenTime(_ sender: NSButton) {
        let on = sender.state == .on
        on ? ScreenTimeManager.shared.extend() : ScreenTimeManager.shared.cancel()
        UserDefaults.standard.extendScreenTime = on ? true : false
    }
    
    private func saveColor(_ color: BackgroundColor) {
        let key = isDarkMode ? UserDefaults.TextViewKeys.backgroundColorDark : UserDefaults.TextViewKeys.backgroundColorLight
        UserDefaults.standard.set(color.rawValue, forKey: key)
    }

    /// Mendapatkan warna tersimpan sesuai mode saat ini untuk update UI (lingkaran terpilih)
    private func getSavedColorTag() -> Int {
        if isDarkMode {
            // Cek apakah user pernah set, jika belum (nil), default ke Black (tag 3)
            if UserDefaults.standard.object(forKey: UserDefaults.TextViewKeys.backgroundColorDark) == nil {
                return BackgroundColor.black.rawValue
            }
            return UserDefaults.standard.integer(forKey: UserDefaults.TextViewKeys.backgroundColorDark)
        } else {
            // Default Light mode adalah White (tag 0)
            return UserDefaults.standard.integer(forKey: UserDefaults.TextViewKeys.backgroundColorLight)
        }
    }

    @IBAction func annSetBtnDidClick(_ sender: NSButton) {
        let enable = sender.state == .on
        state.setClickableAnnotation(enable)
    }
    
    private func setupFontOptions() {
        // 2. Kosongkan semua item yang mungkin ada sebelumnya
        fontOptions.removeAllItems()

        // 3. Tambahkan semua nama font ke NSComboBox
        for font in ArabicFont.allCases {
            fontOptions.addItem(withTitle: font.rawValue)
        }

        let savedFontName = UserDefaults.standard.string(forKey: UserDefaults.TextViewKeys.fontName)
            ?? state.defaultFontName

        ensureCustomFontItemIfNeeded(fontName: savedFontName)

        if let menu = fontOptions.menu {
            menu.addItem(.separator())
            let fontPanelItem = NSMenuItem(
                title: fontPanelItemTitle,
                action: #selector(openFontPanel(_:)),
                keyEquivalent: ""
            )
            fontPanelItem.target = self
            menu.addItem(fontPanelItem)
        }

        selectFontItem(for: savedFontName)

        // 5. Penting: Setel target dan action untuk menangani pilihan baru
        // Action ini akan dipanggil saat pengguna memilih item dari daftar
        fontOptions.target = self
        fontOptions.action = #selector(fontSelected(_:))
    }

    private func loadSettings() {
        // Load font name
        let fontName = defaults.string(forKey: UserDefaults.TextViewKeys.fontName) ?? state.defaultFontName
        selectFontItem(for: fontName)
    }

    private func setupLineHeightPopUpButton() {
        for i in 0..<6 {
            let double = "1." + String(i)
            let count = lineHeightOptions.numberOfItems
            lineHeightOptions.insertItem(withTitle: double, at: count)
        }
        
        #if DEBUG
        print("lineHeight", UserDefaults.standard.lineHeight)
        #endif

        lineHeightOptions.selectItem(withTitle: String(UserDefaults.standard.lineHeight))
        lineHeightOptions.selectedItem?.state = .on
    }

    // MARK: - Actions
    @IBAction func fontSmaller(_ sender: NSButton) {
        state.changeFontSize(by: -2)
    }

    @IBAction func fontLarger(_ sender: NSButton) {
        state.changeFontSize(by: 2)
    }

    @objc private func fontSelected(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        if item.title == fontPanelItemTitle {
            openFontPanel(sender)
            selectFontItem(for: state.fontName)
            return
        }
        let fontName = (item.representedObject as? String) ?? item.title
        state.setFont(fontName)  // ← simpel!
    }

    @IBAction func lineHeightDidChange(_ sender: NSPopUpButton) {
        guard let selected = sender.titleOfSelectedItem,
              let selectedDouble = Double(selected)
        else { return }

        state.setLineHeight(selectedDouble)  // ← simpel!

        sender.menu?.items.forEach { $0.state = .off }
        sender.selectedItem?.state = .on
    }

    // MARK: - Helper Methods
    private func setupBackgroundOptions() {
        let savedTag = getSavedColorTag()
        // Pastikan stackview bersih sebelum menambahkan (opsional)
        hStack.subviews.forEach { $0.removeFromSuperview() }

        // Konfigurasi Spacing StackView
        hStack.spacing = 12
        hStack.orientation = .horizontal
        hStack.distribution = .equalCentering // Menggunakan .equalCentering

        let colors: [NSColor] = [
            .white,
            .bgSepia,
            .bgGray,
            .bgSepiaDark,
            .black          // 3: Hitam Pekat
        ]

        // Ukuran untuk setiap lingkaran
        let itemSize = NSRect(x: 0, y: 0, width: 28, height: 28)

        for (idx, color) in colors.enumerated() {
            let borderOpt: BorderOptions = idx > 2 ? .brighter : .darken
            let optionView = BackgroundOptions(color, frame: itemSize, border: borderOpt)

            // MENAMBAHKAN TAG
            if idx == savedTag {
                optionView.isSelected = true
            }

            optionView.tag = idx

            // Tambahkan constraint ukuran agar lingkaran tidak gepeng di stackview
            optionView.translatesAutoresizingMaskIntoConstraints = false
            optionView.widthAnchor.constraint(equalToConstant: 28).isActive = true
            optionView.heightAnchor.constraint(equalToConstant: 28).isActive = true

            // Setup Action (Opsional: agar bisa di-klik)
            optionView.target = self
            optionView.action = #selector(backgroundOptionClicked(_:))

            hStack.addArrangedSubview(optionView)
        }
    }

    // MARK: - Font Panel
    @objc private func openFontPanel(_ sender: Any?) {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(state.currentFont, isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: NSFontManager) {
        let newFont = sender.convert(state.currentFont)
        let fontName = newFont.fontName
        state.setFont(fontName)
        ensureCustomFontItemIfNeeded(fontName: fontName)
        selectFontItem(for: fontName)
    }

    private func selectFontItem(for fontName: String) {
        if let item = fontOptions.item(withTitle: fontName) {
            fontOptions.select(item)
            return
        }
        if let item = fontOptions.menu?.items.first(where: { ($0.representedObject as? String) == fontName }) {
            fontOptions.select(item)
        }
    }

    private func ensureCustomFontItemIfNeeded(fontName: String) {
        if fontOptions.item(withTitle: fontName) != nil {
            return
        }
        if fontOptions.menu?.items.first(where: { ($0.representedObject as? String) == fontName }) != nil {
            return
        }
        let displayTitle = displayNameForFont(fontName)
        let customItem = NSMenuItem(title: displayTitle, action: nil, keyEquivalent: "")
        customItem.representedObject = fontName

        if let menu = fontOptions.menu,
           let insertIndex = menu.items.firstIndex(where: { $0.isSeparatorItem }) {
            menu.insertItem(customItem, at: insertIndex)
        } else {
            fontOptions.menu?.addItem(customItem)
        }
    }

    private func displayNameForFont(_ fontName: String) -> String {
        let rawName = NSFont(name: fontName, size: 12.0)?.displayName
            ?? NSFont(name: fontName, size: 12.0)?.familyName
            ?? fontName
        let trimmed = stripRegular(from: rawName)
        return trimmed.isEmpty ? fontName : trimmed
    }

    private func stripRegular(from name: String) -> String {
        if name.hasSuffix(" Regular") {
            return String(name.dropLast(" Regular".count))
        }
        if name.hasSuffix("-Regular") {
            return String(name.dropLast("-Regular".count))
        }
        return name
    }

    // Handler ketika salah satu opsi diklik
    @objc private func backgroundOptionClicked(_ sender: BackgroundOptions) {
        // Reset semua seleksi visual di stackview
        for case let view as BackgroundOptions in hStack.arrangedSubviews {
            view.isSelected = false
        }

        // Set yang diklik menjadi selected
        sender.isSelected = true

        guard let bg = BackgroundColor(rawValue: sender.tag) else { return }
        saveColor(bg)

        NotificationCenter.default.post(name: .didChangeBackground, object: nil)
    }
}
