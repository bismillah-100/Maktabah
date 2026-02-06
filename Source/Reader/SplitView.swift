//
//  SplitView.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

import Cocoa

class SplitView: NSSplitViewController, RootSplitView {
    /// Kontainer view yang berisi konten utama aplikasi.
    weak var contentContainerView: NSSplitViewItem?
    weak var libraryItem: NSSplitViewItem?

    weak var ibarotTextVC: IbarotTextVC?
    weak var viewerSplitVC: ViewerSplitVC?

    var optSearch: OptionSearchVC?
    var optSearchPopover: NSPopover?

    lazy var libraryVC: LibraryVC = {
        LibraryVC(nibName: "LibraryVC", bundle: nil)
    }()

    override var nibName: NSNib.Name? {
        "SplitView"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let library = NSSplitViewItem(sidebarWithViewController: libraryVC)
        libraryItem = library

        if let libraryItem {
            addSplitViewItem(libraryItem)
            libraryItem.allowsFullHeightLayout = true
            libraryItem.titlebarSeparatorStyle = .automatic
            libraryItem.minimumThickness = 180
        }

        let containerVC = ViewerSplitVC(nibName: "ViewerSplitVC", bundle: nil)
        let splitViewItem = NSSplitViewItem(contentListWithViewController: containerVC)
        containerVC.rootSplitView = self
        contentContainerView = splitViewItem

        if let contentContainerView {
            contentContainerView.allowsFullHeightLayout = true
            contentContainerView.titlebarSeparatorStyle = .automatic
            if #available(macOS 26.0, *) {
                contentContainerView.automaticallyAdjustsSafeAreaInsets = true
            }
            addSplitViewItem(contentContainerView)
        }

        if let libraryViewController = libraryItem?.viewController as? LibraryVC {
            libraryViewController.delegate = containerVC.ibarotTextItem?.viewController as? IbarotTextVC
        }

        if let containerVC = contentContainerView?.viewController as? ViewerSplitVC,
           let ibarotVC = containerVC.ibarotTextItem?.viewController as? IbarotTextVC {
            ibarotTextVC = ibarotVC
        }

        if let containerVC = contentContainerView?.viewController as? ViewerSplitVC {
            viewerSplitVC = containerVC
        }

        viewerSplitVC?.splitView.autosaveName = "LibraryViewerSplitView"
        splitView.autosaveName = "ReaderSplitView"
    }
}

extension SplitView: ToolbarActionDelegate {}
