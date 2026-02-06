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

    override func viewDidLoad() {
        super.viewDidLoad()
        xBtn.isHidden = popover
        setupFontOptions()
        loadSettings()
        setupBackgroundOptions()
        loadHarakatSetting()
        screenTimeCheckbox.state = screenTimeManager.isExtended() ? .on : .off
        loadAnnotationSetting()
        view.layoutSubtreeIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setupLineHeightPopUpButton()
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

        // 4. Atur item yang saat ini dipilih atau ditampilkan (opsional)
        // Jika Anda ingin menampilkan nilai yang sudah disimpan di UserDefaults saat startup:
        if let savedFontName = UserDefaults.standard.string(forKey: UserDefaults.TextViewKeys.fontName) {
            // Coba pilih item yang namanya sama.
            // Jika tidak ada, nilainya akan tetap menjadi yang pertama atau kosong.
            fontOptions.selectItem(withTitle: savedFontName)
        } else {
            // Jika belum ada yang tersimpan, pilih item pertama sebagai default
            fontOptions.selectItem(withTitle: state.defaultFontName)
        }

        // 5. Penting: Setel target dan action untuk menangani pilihan baru
        // Action ini akan dipanggil saat pengguna memilih item dari daftar
        fontOptions.target = self
        fontOptions.action = #selector(fontSelected(_:))
    }

    private func loadSettings() {
        // Load font name
        let fontName = defaults.string(forKey: UserDefaults.TextViewKeys.fontName) ?? state.defaultFontName
        fontOptions.selectItem(withTitle: fontName)
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
        guard let fontName = sender.titleOfSelectedItem else { return }
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

        hStack.needsLayout = true
        hStack.layoutSubtreeIfNeeded()
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

extension Notification.Name {
    // static let backgroundDidChange = Notification.Name("backgroundDidChange")
    static let didChangeClickableAnnotation = Notification.Name("didChangeClickableAnnotation")
    static let didChangeHarakat = Notification.Name("didChangeHarakat")
    static let didChangeBackground = Notification.Name("didChangeBackground")
    static let didChangeFont = Notification.Name("didChangeFont")
    static let didChangeLineHeight = Notification.Name("didChangeLineHeight")
}
