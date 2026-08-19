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
    weak var textDelegate: TextViewRenderable?

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.backgroundColor = .bgSepia
        textDelegate = textView
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

        optSearch.onSelectedItem = { id, query, mode, nearDistance in
            Task.detached { [weak self] in
                await self?.didSelectResult(
                    for: id,
                    highlightText: query,
                    mode: mode,
                    nearDistance: Int(nearDistance) ?? 10
                )
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

        loadText(content.nash, content: content)
    }

    @IBAction func previousPage(_ sender: Any?) {
        guard let content = manager.prevPage() else {
            updateNotFoundString()
            return
        }

        loadText(content.nash, content: content)
    }

    private func loadText(
        _ text: String,
        content: BookContent? = nil,
        navigateToContent: Bool = false
    ) {
        textDelegate?.loadIbarotText(
            text, content: content, color: .header,
            isMultiLanguage: false, isImported: false,
            keepScrollPosition: false
        )

        if navigateToContent, let content {
            didNavigateContent?(content)
        }
    }

}

extension QuranNashVC: QuranDelegate {
    func didSelectAya(_ surah: SurahNode, aya: Quran) {
        ayahTextField.stringValue = aya.nass

        if let nash = manager.loadTafseer(for: aya.aya, in: surah.id) {
            loadText(nash)
        } else {
            #if DEBUG
            print("error load nash to textview")
            #endif
            updateNotFoundString()
        }
    }
}

extension QuranNashVC: OptionSearchDelegate {
    func didSelectResult(
        for id: Int,
        highlightText: String,
        mode: SearchMode?,
        nearDistance: Int
    ) async {
        guard let selectedBook = manager.selectedBook,
              let content = manager.bkConn.getContent(bkid: String(selectedBook.id), contentId: id, quran: true) else {
            return
        }

        loadText(content.nash)

        try? await Task.sleep(nanoseconds: 3_000_000)

        await textDelegate?.highlightAndScrollToText(highlightText, mode: mode, nearDistance: nearDistance)
        await MainActor.run {
            didNavigateContent?(content)
        }
    }
}
