//
//  Protocols.swift
//  maktab
//
//  Created by MacBook on 29/11/25.
//

import Cocoa

protocol SidebarDelegate: AnyObject {
    func didSelectItem(_ id: Int)
}

protocol LibraryDelegate: AnyObject {
    func didSelectBook(for book: BooksData) async
}

protocol NavigationDelegate: AnyObject {
    func sliderDidNavigateInto(content: BookContent)
}

protocol ResultsDelegate: AnyObject {
    func didSelect(savedResults: [SavedResultsItem])
}

protocol TarjamahBDelegate: AnyObject {
    func didSelectRowi()
    func didSelect(tarjamahB: TarjamahMen, query: String?) async
}

protocol LibraryViewDelegate: AnyObject {
    func didSelectItem(_ row: Int) async
}

protocol OptionSearchDelegate: AnyObject {
    func didSelectResult(for id: Int, highlightText: String) async
}


protocol ToolbarActionDelegate: AnyObject {
    // Viewer
    func prevPage()
    func nextPage()
    func viewOptions(_ sender: Any)
    func bookInfo(_ sender: Any)
    func navigationPage(_ sender: Any)
    func copyDetails(_ sender: NSButton) // hanya viewer
    func sidebarLeadingToggle()
    func sidebarTrailing()
    func searchSidebarTrailing()

    // Search
    func searchCurrentBook(_ sender: NSButton)

    // Annotations
    func displayAnnotations(_ sender: Any?)
}

protocol RootSplitView: AnyObject {
    var ibarotTextVC: IbarotTextVC? { get set }
    var viewerSplitVC: ViewerSplitVC? { get set }
    var optSearch: OptionSearchVC? { get set }
    var optSearchPopover: NSPopover? { get set }

}

extension ToolbarActionDelegate where Self: RootSplitView {
    func sidebarLeadingToggle() {
        // Asumsi 'toggleSidebar' tersedia di Self (yaitu SearchSplitView/SplitView)
        (self as? NSSplitViewController)?.toggleSidebar(nil)
    }

    func sidebarTrailing() {
        viewerSplitVC?.hideTableOfContents(nil)
    }

    func prevPage() {
        // Mengakses properti ibarotTextVC dari RootSplitView
        ibarotTextVC?.previousPage(nil)
    }
    
    func nextPage() {
        ibarotTextVC?.nextPage(nil)
    }
    
    func viewOptions(_ sender: Any) {
        viewerSplitVC?.viewOptions(sender)
    }
    
    func bookInfo(_ sender: Any) {
        ibarotTextVC?.bookInfo(sender)
    }

    func navigationPage(_ sender: Any) {
        ibarotTextVC?.navigationPage(sender)
    }

    func copyDetails(_ sender: NSButton) {
        ibarotTextVC?.copyWith()
    }

    func searchSidebarTrailing() {
        viewerSplitVC?.sidebarVC.unhideSearchField()
    }

    func displayAnnotations(_ sender: Any?) {
        if let panel = AnnotationsVC.panel {
            panel.makeKeyAndOrderFront(sender)
            return
        }

        let vc: AnnotationsVC

        if SharedPopover.annotationsVC == nil {
            vc = AnnotationsVC()
            SharedPopover.annotationsVC = vc
        } else {
            vc = SharedPopover.annotationsVC!
        }

        vc.dataSource.delegate = ibarotTextVC

        if sender as? NSButton == nil,
           AnnotationsVC.panel == nil {
            let panel = NSPanel()
            panel.styleMask.insert([.utilityWindow, .resizable, .closable])
            panel.isFloatingPanel = true
            panel.title = "Annotations".localized
            panel.delegate = vc
            panel.contentViewController = vc
            panel.makeKeyAndOrderFront(sender)
            vc.shareBtn.isHidden = false
            vc.windowBtn.isHidden = true
            vc.setting.isHidden = false
            panel.setFrameAutosaveName("AnnotationsPanel")
            AnnotationsVC.panel = panel
            return
        } else if let panel = AnnotationsVC.panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        guard let button = sender as? NSButton else {
            return
        }

        let popover = SharedPopover.annotationsPopover
        popover.contentViewController = vc
        popover.show(relativeTo: button.frame, of: button, preferredEdge: .minY)
    }

    func searchCurrentBook(_ sender: NSButton) {
        if optSearchPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            optSearchPopover = popover
        }

        guard let optSearchPopover else { return }

        if optSearch == nil {
            let vc = OptionSearchVC()
            vc.view.frame = NSRect(x: 0, y: 0, width: 350, height: 300)
            optSearch = vc
        }

        guard let optSearch,
              let bkId = ibarotTextVC?.textView.bkId
        else {
            ReusableFunc.showAlert(
                title: NSLocalizedString("noBookSelectedTitle", comment: ""),
                message: NSLocalizedString("noBookSelectedDesc", comment: "")
            )
            return
        }

        optSearch.bkId = "b\(bkId)"

        optSearchPopover.contentViewController = optSearch

        optSearchPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        optSearch.compactButton()

        optSearch.onSelectedItem = { id, query in
            Task.detached { [weak self] in
                await self?.ibarotTextVC?.didSelectResult(for: id, highlightText: query)
            }
        }

        optSearch.onCleanUp = { [weak self] in
            self?.optSearchPopover?.performClose(sender)
            self?.optSearch = nil
            self?.optSearchPopover = nil
        }
    }
}
