//
//  QuranNashVC.swift
//  maktab
//
//  Created by MacBook on 23/12/25.
//

import Cocoa

class QuranNashVC: NSViewController {
    @IBOutlet weak var stackView: NSStackView!
    @IBOutlet weak var ayahTextField: NSTextField!
    @IBOutlet weak var textView: IbarotTextView!
    @IBOutlet weak var hLine: NSBox!

    var didNavigateContent: ((BookContent) -> Void)?

    let manager = QuranDataManager.shared

    let notFoundString = String("-")

    var optSearchPopover: NSPopover?
    var optSearch: OptionSearchVC?

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.backgroundColor = .bgSepia
        stackView.setCustomSpacing(0, after: hLine)
        // Do view setup here.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setupToolbar()
    }

    func setupToolbar() {
        guard let window = view.window as? QuranWindow,
              let navSegment = window.navSegment,
              let searchCurrent = window.searchCurrent.view as? NSButton
        else { return }

        navSegment.target = self
        navSegment.action = #selector(navigationSegmentDidClick(_:))

        searchCurrent.target = self
        searchCurrent.action = #selector(searchCurrentBook(_:))
    }

    func updateNotFoundString() {
        textView.string = notFoundString
    }

    @IBAction func searchCurrentBook(_ sender: NSButton) {
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
              let bkId = QuranDataManager.shared.selectedBook?.id
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
                await self?.didSelectResult(for: id, highlightText: query)
            }
        }

        optSearch.onCleanUp = { [weak self] in
            self?.optSearchPopover?.performClose(sender)
            self?.optSearch = nil
            self?.optSearchPopover = nil
        }
    }

    @IBAction func navigationSegmentDidClick(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: nextPage(nil)
        case 1: previousPage(nil)
        default: break
        }
    }

    @IBAction func nextPage(_ sender: Any?) {
        guard let content = manager.nextPage() else {
            updateNotFoundString()
            return
        }
        textView.loadIbarotText(content.nash)
        didNavigateContent?(content)
    }

    @IBAction func previousPage(_ sender: Any?) {
        guard let content = manager.prevPage() else {
            updateNotFoundString()
            return
        }
        textView.loadIbarotText(content.nash)
        didNavigateContent?(content)
    }

    @MainActor
    func highlightAndScrollToText(_ searchText: String) {
        guard let textStorage = textView.textStorage else { return }

        let fullText = textStorage.string
            .normalizeArabic(false)
            .replacingOccurrences(of: "\\n", with: "\n")

        // Reset highlight
        // let fullRange = NSRange(location: 0, length: textStorage.length)
        // textStorage.removeAttribute(.backgroundColor, range: fullRange)

        // Cari teks (case insensitive, diacritic insensitive untuk Arab)
        let lowerFullText = fullText.lowercased()
        let lowerSearchText = searchText.lowercased()

        var searchRange = lowerFullText.startIndex..<lowerFullText.endIndex
        var firstMatchRange: NSRange?

        while let found = lowerFullText.range(of: lowerSearchText, options: [.diacriticInsensitive], range: searchRange) {
            let nsRange = NSRange(found, in: fullText)

            if firstMatchRange == nil {
                firstMatchRange = nsRange
            }

            // Highlight
            var hasBackground = false
            textStorage.enumerateAttribute(.backgroundColor, in: nsRange, options: []) { value, _, stop in
                if value != nil {
                    hasBackground = true
                    stop.pointee = true
                }
            }

            // Tambah highlight hanya jika belum ada
            if !hasBackground {
                textStorage.addAttribute(.backgroundColor, value: NSColor.highlightText, range: nsRange)
            }

            searchRange = found.upperBound..<lowerFullText.endIndex
        }

        // Scroll ke match pertama
        if let firstRange = firstMatchRange {
            Task { @MainActor [weak self, firstRange] in
                self?.textView.scrollRangeToVisible(firstRange)
                self?.textView.showFindIndicator(for: firstRange) // Animasi indicator (opsional)
            }
        }
    }

}

extension QuranNashVC: QuranDelegate {
    func didSelectAya(_ surah: SurahNode, aya: Quran) {
        ayahTextField.stringValue = aya.nass

        if let nash = manager.loadTafseer(for: aya.aya, in: surah.id) {
            textView.loadIbarotText(nash)
        } else {
            #if DEBUG
            print("error load nash to textview")
            #endif
            updateNotFoundString()
        }
    }
}

extension QuranNashVC: OptionSearchDelegate {
    func didSelectResult(for id: Int, highlightText: String) async {
        guard let selectedBook = manager.selectedBook,
              let content = manager.bkConn.getContent(bkid: String(selectedBook.id), contentId: id, quran: true) else {
            return
        }

        await MainActor.run {
            textView.loadIbarotText(content.nash)
        }

        try? await Task.sleep(nanoseconds: 3_000_000)

        await MainActor.run {
            highlightAndScrollToText(highlightText)
            didNavigateContent?(content)
        }
    }
}
