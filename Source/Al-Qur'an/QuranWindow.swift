//
//  QuranWindow.swift
//  maktab
//
//  Created by MacBook on 24/12/25.
//

import Cocoa

class QuranWindow: NSWindow {
    @IBOutlet weak var navSegment: NSToolbarItem!
    @IBOutlet weak var searchCurrent: NSToolbarItem!
    @IBOutlet weak var searchQuran: NSToolbarItem!
    @IBOutlet weak var searchTafseer: NSToolbarItem!

    weak var splitView: NSSplitView! {
        didSet {
            // Panggil setup toolbar di sini setelah splitView tersedia
            setupToolbar()
        }
    }

    var rtl: Bool {
        MainWindow.rtl
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        
        titleVisibility = rtl ? .hidden : .visible

        guard let toolbar else { return }

        // 1. Hapus semua item yang ada saat ini
        while toolbar.items.count > 0 {
            toolbar.removeItem(at: 0)
        }

        // 2. Set delegate (pastikan delegate sudah siap memberikan item)
        toolbar.delegate = self
    }

    func setupToolbar() {
        guard let toolbar else { return }
        // 1. Tambahkan item default secara manual berdasarkan urutan identifier
        // Kita mengambil list identifier dari fungsi delegate yang sudah Anda buat
        let defaultIdentifiers = self.toolbarDefaultItemIdentifiers(toolbar)

        for (index, identifier) in defaultIdentifiers.enumerated() {
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }

        // 2. Sisipkan Tracking Separators di posisi yang diinginkan
        // Pastikan index-nya sesuai dengan jumlah item yang baru saja dimasukkan

        if let index = toolbar.items.firstIndex(of: searchQuran) {
            let index = rtl ? index + 1 : index
            toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier("trackingSeparatorQuran"), at: index)
        }
        
        if let index = toolbar.items.firstIndex(of: searchTafseer) {
            let index = rtl ? index + 1 : index
            toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier("trackingSeparatorTafseer"), at: index)
        }
    }
    
}

extension QuranWindow: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if rtl {
            return [
                searchQuran.itemIdentifier,
                searchTafseer.itemIdentifier,
                navSegment.itemIdentifier,
                searchCurrent.itemIdentifier,
            ]
        } else {
            return [
                searchCurrent.itemIdentifier,
                navSegment.itemIdentifier,
                searchTafseer.itemIdentifier,
                searchQuran.itemIdentifier,
            ]
        }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier.rawValue {
        case "trackingSeparatorQuran":
            let index = rtl ? 0 : 1
            return createTrackingSeparator(splitView, itemIdentifier: itemIdentifier, dividerIndex: index)
        case "trackingSeparatorTafseer":
            let index = rtl ? 1 : 0
            return createTrackingSeparator(splitView, itemIdentifier: itemIdentifier, dividerIndex: index)
        default:
            break
        }

        return item
    }

    private func createTrackingSeparator(_ splitView: NSSplitView, itemIdentifier: NSToolbarItem.Identifier, dividerIndex: Int) -> NSTrackingSeparatorToolbarItem {
        // ViewerSplitVC punya 2 items (IbarotTextVC dan SidebarVC)
        // Jadi hanya ada 1 divider di index 0
        let trackingSeparator = NSTrackingSeparatorToolbarItem(
            identifier: itemIdentifier,
            splitView: splitView,
            dividerIndex: dividerIndex // Index 0 untuk divider antara item pertama dan kedua
        )

        return trackingSeparator
    }

}
