//
//  RowiSplitVC.swift
//  maktab
//
//  Created by MacBook on 10/12/25.
//

import Cocoa

class RowiSplitVC: NSSplitViewController, RootSplitView {
    weak var ibarotTextVC: IbarotTextVC?
    weak var viewerSplitVC: ViewerSplitVC?

    var optSearch: OptionSearchVC?
    var optSearchPopover: NSPopover?

    lazy var sidebarVC: RowiSidebarVC = {
        RowiSidebarVC()
    }()

    lazy var resultsSplitVC: RowiResultsSplitVC = {
        RowiResultsSplitVC(nibName: "RowiResultsSplitVC", bundle: nil)
    }()

    override var nibName: NSNib.Name? {
        "SplitView"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let sidebar = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebar.titlebarSeparatorStyle = .automatic
        sidebar.allowsFullHeightLayout = true
        sidebar.minimumThickness = 180
        addSplitViewItem(sidebar)

        let results = NSSplitViewItem(viewController: resultsSplitVC)
        results.titlebarSeparatorStyle = .line
        addSplitViewItem(results)
        if #available(macOS 26.0, *) {
            results.automaticallyAdjustsSafeAreaInsets = true
        }

        sidebarVC.delegate = resultsSplitVC.rowiResultsVC
        ibarotTextVC = resultsSplitVC.viewerSplitVC.ibarotVC
        viewerSplitVC = resultsSplitVC.viewerSplitVC
        viewerSplitVC?.splitView.autosaveName = "AuthorViewerSplitView"
        splitView.autosaveName = "RowiSplitVC_autoSaveSplitView"
        // Do view setup here.
    }
}

extension RowiSplitVC: ToolbarActionDelegate {}
