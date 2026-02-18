//
//  QuranSplitVC.swift
//  maktab
//
//  Created by MacBook on 23/12/25.
//

import Cocoa

class QuranSplitVC: NSSplitViewController {

    lazy var sidebarSurah: QuranSidebarVC = {
        QuranSidebarVC()
    }()

    lazy var tafseerVC: QuranTafseerVC = {
        QuranTafseerVC()
    }()

    lazy var textVC: QuranNashVC = {
        QuranNashVC()
    }()

    lazy var sidebarSurahItem: NSSplitViewItem = {
        NSSplitViewItem(viewController: sidebarSurah)
    }()

    lazy var textVCItem: NSSplitViewItem = {
        NSSplitViewItem(viewController: textVC)
    }()

    lazy var tafseerItem: NSSplitViewItem = {
        NSSplitViewItem(viewController: tafseerVC)
    }()

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setupLayout() {
        sidebarSurahItem.minimumThickness = 115
        sidebarSurahItem.holdingPriority = NSLayoutConstraint.Priority(260)
        tafseerItem.minimumThickness = 150
        tafseerItem.holdingPriority = NSLayoutConstraint.Priority(260)

        let rtl = view.userInterfaceLayoutDirection == .rightToLeft

        if rtl {
            addSplitViewItem(sidebarSurahItem)
            addSplitViewItem(tafseerItem)
            addSplitViewItem(textVCItem)
        } else {
            addSplitViewItem(textVCItem)
            addSplitViewItem(tafseerItem)
            addSplitViewItem(sidebarSurahItem)
        }

        sidebarSurah.delegate = textVC
        splitView.autosaveName = "QuranSplitView"
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setupClosure()
        DispatchQueue.main.async { [weak textVC, weak sidebarSurah, weak tafseerVC] in
            guard let textVC, let sidebarSurah, let tafseerVC else { return }
            Self.addNSView(to: textVC.view)
            Self.addNSView(to: tafseerVC.view)
            Self.addNSView(to: sidebarSurah.view)
        }
    }

    func setupClosure() {
        tafseerVC.didSelectBook = { [weak self] book in
            guard let self else { return }
            let manager = QuranDataManager.shared
            manager.connect(to: book)
            if let (aya, surah) = manager.selectedQuran,
               let surahNode = manager.surahNodes.first(where: { $0.id == surah }),
               let ayatQuran = sidebarSurah.ayaLookup[surah]?[aya] {
                textVC.didSelectAya(surahNode, aya: ayatQuran)
            }
        }

        textVC.didNavigateContent = { [weak self] bookContent in
            guard let self, let aya = bookContent.aya,
                  let surah = bookContent.surah else {
                return
            }

            sidebarSurah.selectNode(aya: aya, surah: surah)
        }
    }

    static func addNSView(to view: NSView) {
        guard let window = view.window,
              let guide = window.contentLayoutGuide as? NSLayoutGuide
        else { return }
        let ve = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.bgSepia.cgColor

        ve.wantsLayer = true
        ve.layer?.backgroundColor = NSColor.bgSepia.cgColor
        ve.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ve, positioned: .above, relativeTo: nil)

        NSLayoutConstraint.activate([
            ve.topAnchor.constraint(equalTo: view.topAnchor),
            ve.bottomAnchor.constraint(equalTo: guide.topAnchor),
            ve.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ve.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }


    deinit {
        #if DEBUG
        print("QuranSplitVC deinit")
        #endif
    }
}
