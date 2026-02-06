//
//  RowiResultsSplitVC.swift
//  maktab
//
//  Created by MacBook on 10/12/25.
//

import Cocoa

class RowiResultsSplitVC: NSSplitViewController {
    lazy var viewerSplitVC: ViewerSplitVC = {
        ViewerSplitVC(nibName: "ViewerSplitVC", bundle: nil)
    }()

    lazy var rowiResultsVC: RowiResultsVC = {
        RowiResultsVC(nibName: "RowiResultsVC", bundle: nil)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = false

        let ibarotItem = NSSplitViewItem(viewController: viewerSplitVC)
        ibarotItem.allowsFullHeightLayout = true
        addSplitViewItem(ibarotItem)

        let resultItem = NSSplitViewItem(viewController: rowiResultsVC)
        resultItem.minimumThickness = 100  // ← Tambahkan ini
        resultItem.holdingPriority = NSLayoutConstraint.Priority(260)
        addSplitViewItem(resultItem)
        rowiResultsVC.delegate = viewerSplitVC.ibarotVC
        rowiResultsVC.textView = viewerSplitVC.ibarotVC.textView
        rowiResultsVC.viewerSplitVC = viewerSplitVC
        
        splitView.autosaveName = "RowiResultsSplitVC_frameAutoSave"
        // Do view setup here.
    }
}
