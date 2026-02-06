//
//  ResultsSplitVC.swift
//  maktab
//
//  Created by MacBook on 07/12/25.
//

import Cocoa

class ResultsSplitVC: NSSplitViewController {

    weak var rootSplitView: NSSplitViewController?

    weak var viewerItem: NSSplitViewItem?
    weak var resultsItem: NSSplitViewItem?

    lazy var viewerVC: ViewerSplitVC = {
        ViewerSplitVC(nibName: "ViewerSplitVC", bundle: nil)
    }()

    lazy var resultsVC: OptionSearchVC = {
        OptionSearchVC()
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        print("viewDidLoad ResultsSplitVC")
        #endif
        
        splitView.isVertical = false

        let vi = NSSplitViewItem(viewController: viewerVC)
        vi.allowsFullHeightLayout = true
        vi.titlebarSeparatorStyle = .automatic

        viewerVC.rootSplitView = self
        viewerItem = vi

        let rvc = NSSplitViewItem(viewController: resultsVC)
        rvc.minimumThickness = 100  // ← Tambahkan ini
        rvc.holdingPriority = NSLayoutConstraint.Priority(260)
        resultsItem = rvc

        guard let viewerItem, let resultsItem else { return}

        addSplitViewItem(viewerItem)
        addSplitViewItem(resultsItem)

        let ibarotTextVC = viewerVC.ibarotVC
        resultsVC.delegate = ibarotTextVC
        resultsVC.itemDelegate = ibarotTextVC
        splitView.autosaveName = "ResultsSplitVC_autoSaveFrame"
    }

    override func toggleSidebar(_ sender: Any?) {
        rootSplitView?.toggleSidebar(sender)
    }
}
