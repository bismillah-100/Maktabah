//
//  SearchSplitView.swift
//  maktab
//
//  Created by MacBook on 03/12/25.
//

import Cocoa

class SearchSplitView: NSSplitViewController, RootSplitView, ToolbarActionDelegate {
    
    weak var ibarotTextVC: IbarotTextVC?
    weak var viewerSplitVC: ViewerSplitVC?

    weak var optionSearchVC: OptionSearchVC?

    lazy var resultsSplitVC: ResultsSplitVC = {
        ResultsSplitVC()
    }()
    
    lazy var searchSidebarVC: SearchSidebarVC = {
        SearchSidebarVC(nibName: "SearchSidebarVC", bundle: nil)
    }()

    var optSearchPopover: NSPopover?

    /* MARK: biarkan duplikat, ini untuk popover.
     optionSearchVC untuk item di splitView.
     */
    var optSearch: OptionSearchVC?

    static var query: String = .init()

    override var nibName: NSNib.Name? {
        "SplitView"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let sidebar = NSSplitViewItem(sidebarWithViewController: searchSidebarVC)
        sidebar.allowsFullHeightLayout = true
        sidebar.titlebarSeparatorStyle = .automatic
        sidebar.minimumThickness = 180
        addSplitViewItem(sidebar)

        resultsSplitVC.rootSplitView = self
        let results = NSSplitViewItem(viewController: resultsSplitVC)
        results.allowsFullHeightLayout = true
        results.titlebarSeparatorStyle = .automatic
        addSplitViewItem(results)
        
        if #available(macOS 26.0, *) {
            results.automaticallyAdjustsSafeAreaInsets = true
        }

        ibarotTextVC = resultsSplitVC.viewerVC.ibarotVC
        optionSearchVC = resultsSplitVC.resultsVC
        optionSearchVC?.searchSplitVC = self
        viewerSplitVC = resultsSplitVC.viewerVC
        optionSearchVC?.libraryViewManager = searchSidebarVC.dataVM
        if !MainWindow.rtl {
            viewerSplitVC?.splitView.autosaveName = "SearchViewerSplitView"
        }
        splitView.autosaveName = "SearchSplitView_autoSaveSplitviews"
    }
}
