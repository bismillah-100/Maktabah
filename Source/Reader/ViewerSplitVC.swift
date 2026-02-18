//
//  ContainerVC.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

import Cocoa
import SQLite

class ViewerSplitVC: NSSplitViewController {
    weak var ibarotTextItem: NSSplitViewItem?
    /// Sidebar item yang berisi sidebar view controller.
    weak var sidebarItem: NSSplitViewItem?

    weak var rootSplitView: NSSplitViewController?

    lazy var sidebarVC: SidebarVC = {
        SidebarVC(nibName: "SidebarVC", bundle: nil)
    }()

    lazy var ibarotVC: IbarotTextVC = {
        IbarotTextVC()
    }()

    var bgObserver: NSObjectProtocol?
    var tasykilObserver: NSObjectProtocol?
    var fontObserver: NSObjectProtocol?

    var workItemAppereance: DispatchWorkItem?

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setupLayout() {
        let ltr = !MainWindow.rtl

        splitView = CustomSplitView(frame: .zero)
        splitView.isVertical = true

        ibarotVC = IbarotTextVC()
        let ibarot: NSSplitViewItem
        let sidebar: NSSplitViewItem

        if #available(macOS 26, *) {
            ibarot = NSSplitViewItem(viewController: ibarotVC)
            if ltr {
                sidebar = NSSplitViewItem(inspectorWithViewController: sidebarVC)
            } else {
                sidebar = NSSplitViewItem(viewController: sidebarVC)
            }
        } else {
            sidebar = NSSplitViewItem(viewController: sidebarVC)
            ibarot = NSSplitViewItem(viewController: ibarotVC)
        }

        ibarotTextItem = ibarot
        sidebarItem = sidebar

        if let sidebarItem, let ibarotTextItem {
            ibarotTextItem.allowsFullHeightLayout = true
            ibarotTextItem.titlebarSeparatorStyle = .automatic
            sidebarItem.allowsFullHeightLayout = true
            sidebarItem.titlebarSeparatorStyle = .automatic
            sidebarItem.minimumThickness = 135

            if ltr {
                sidebarItem.holdingPriority = NSLayoutConstraint.Priority(251)
            } else {
                sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
                ibarotTextItem.holdingPriority = NSLayoutConstraint.Priority(250)
            }

            if #available(macOS 26, *) {
                if ltr {
                    addSplitViewItem(ibarotTextItem)
                    addSplitViewItem(sidebarItem)
                } else {
                    addSplitViewItem(sidebarItem)
                    addSplitViewItem(ibarotTextItem)
                }
            } else if ltr {
                addSplitViewItem(ibarotTextItem)
                addSplitViewItem(sidebarItem)
            } else {
                addSplitViewItem(sidebarItem)
                addSplitViewItem(ibarotTextItem)
            }
        }

        // Set sidebar delegate
        if let sidebarViewController = sidebarItem?.viewController as? SidebarVC {
            sidebarViewController.db = ibarotVC.bookDB
            sidebarViewController.delegate = ibarotVC
        }

        ibarotVC.sidebarVC = sidebarVC
        applyThemeBasedOnSystem()
        startObservingAppearance()
        startObservingBgColor()
        startObservingTasykil()
        startObservingFont()
        startObservingLineHeight()
    }

    /// Oberservasi line height
    var lineHeightObservation: NSObjectProtocol?

    private func startObservingLineHeight() {
        lineHeightObservation = NotificationCenter.default.addObserver(
            forName: .didChangeLineHeight, object: nil,
            queue: .main, using: { [weak self] _ in
                self?.ibarotVC.textView.updateLineHeight()
        })
    }

    /// Observasi tampilan sistem
    var appearanceObservation: NSObjectProtocol?

    /// Untuk monitoring perubahan tampilan dark-light sistem.
    private func startObservingAppearance() {
        appearanceObservation = splitView.observe(
            \.effectiveAppearance,
             options: [.new]
        ) { [weak self] _, _ in
            self?.applyThemeBasedOnSystem()
        }
    }

    private func startObservingBgColor() {
        bgObserver = NotificationCenter.default.addObserver(
            forName: .didChangeBackground, object: nil,
            queue: .main, using: { [weak self] _ in
            guard let self else { return }
            let bg = getBgColor()
            applyBackgroundColorToUI(bg)
        })
    }

    private func startObservingTasykil() {
        tasykilObserver = NotificationCenter.default.addObserver(
            forName: .didChangeHarakat, object: nil,
            queue: .main, using: { [weak self] notif in
            guard let userInfo = notif.userInfo,
                  let on = userInfo["on"] as? Bool
            else { return }
            self?.ibarotVC.toggleHarakat(on)

            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.showDiacriticMenuItem.state = on ? .on : .off
            }
        })
    }

    private func startObservingFont() {
        fontObserver = NotificationCenter.default.addObserver(
            forName: .didChangeFont, object: nil,
            queue: .main, using: { [weak self] notif in
            guard let userInfo = notif.userInfo,
                  let redraw = userInfo["redraw"] as? Bool
            else { return }
            self?.ibarotVC.applyFont(redraw)
        })
    }

    @IBAction func hideTableOfContents(_ sender: Any?) {
        if sidebarItem?.isCollapsed == true {
            sidebarItem?.isCollapsed = false
            updateDivider(for: getBgColor())
        } else {
            sidebarItem?.isCollapsed = true
        }
    }

    override func toggleSidebar(_ sender: Any?) {
        rootSplitView?.toggleSidebar(sender)
        return
    }

    @IBAction func viewOptions(_ sender: Any) {
        let viewOpt = ViewOptions(nibName: "ViewOptions", bundle: nil)
        if let button = sender as? NSButton {
            WindowController.showPopOver(sender: button, viewController: viewOpt)
        } else {
            viewOpt.popover = false
            presentAsSheet(viewOpt)
        }
    }

    private func updateWindowColors(for backgroundColor: BackgroundColor) {
        guard let window = view.window else { return }

        // Update appearance untuk sistem controls (traffic lights, dll)
        switch backgroundColor {
        case .white, .sepia:
            window.appearance = NSAppearance(named: .aqua)
        case .gray, .black, .darkSepia:
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func getBgColor() -> BackgroundColor {
        let appearance = NSApp.effectiveAppearance
        let isDarkAqua = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let isDarkVibrant = appearance.bestMatch(from: [.vibrantDark, .vibrantLight]) == .vibrantDark

        let isDark = isDarkAqua || isDarkVibrant

        let colorEnum: BackgroundColor

        if isDark {
            // Load preferensi Dark Mode
            // Cek apakah user sudah pernah simpan, jika belum default ke Black (3)
            let tag = UserDefaults.standard.textViewBackgroundColorDark
            colorEnum = BackgroundColor(rawValue: tag) ?? .black
        } else {
            // Load preferensi Light Mode (Default White/0)
            let tag = UserDefaults.standard.textViewBackgroundColorLight
            colorEnum = BackgroundColor(rawValue: tag) ?? .white
        }

        return colorEnum
    }

    private func applyThemeBasedOnSystem() {
        workItemAppereance?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            appearanceObservation = nil
            applyBackgroundColorToUI(getBgColor())
            startObservingAppearance()
        }

        workItemAppereance = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func applyBackgroundColorToUI(_ bg: BackgroundColor) {
        let sv = splitView

        // Gunakan dark appearance untuk gray dan black
        let appearance: NSAppearance = (bg.rawValue > 1)
        ? NSAppearance(named: .darkAqua)!
        : NSAppearance(named: .aqua)!

        #if DEBUG
        print("DEBUG: Applying bg=\(bg), rawValue=\(bg.rawValue), appearance=\(appearance)")
        #endif

        sv.appearance = appearance
        sv.subviews.forEach { $0.appearance = appearance }

        sidebarVC.applyBackgroundColor(bg)
        ibarotVC.applyBackgroundColor(bg.nsColor)
        updateWindowColors(for: bg)
        updateDivider(for: bg)
    }

    private func updateDivider(for bg: BackgroundColor) {
        if #available(macOS 26, *), !MainWindow.rtl {
            return
        } else if let splitView = splitView as? CustomSplitView {
            // Update warna divider
            splitView.updateDividerColor(to: bg)
        }
    }

    deinit {
        if let bgObserver,
           let appearanceObservation,
           let fontObserver,
           let tasykilObserver,
           let lineHeightObservation {
            NotificationCenter.default.removeObserver(bgObserver)
            NotificationCenter.default.removeObserver(appearanceObservation)
            NotificationCenter.default.removeObserver(lineHeightObservation)
            NotificationCenter.default.removeObserver(fontObserver)
            NotificationCenter.default.removeObserver(tasykilObserver)
        }
        bgObserver = nil
        appearanceObservation = nil
        fontObserver = nil
        tasykilObserver = nil
        lineHeightObservation = nil
    }
}
