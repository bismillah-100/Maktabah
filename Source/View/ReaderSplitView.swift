//
//  ReaderSplitView.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 26/08/26.
//

import Cocoa

class ReaderSplitVC: NSSplitViewController {
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupLayout() {}
}
