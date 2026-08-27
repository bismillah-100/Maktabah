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
        OptionSearchPopover.present(
            popover: &optSearchPopover,
            searchVC: &optSearch,
            bookID: manager.selectedBook?.id,
            from: sender,
            delegate: self
        )
    }

    @IBAction func navigationSegmentDidClick(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: nextPage(nil)
        case 1: previousPage(nil)
        default: break
        }
    }

    @IBAction func nextPage(_ sender: Any?) {
        navigatePage(manager.nextPage())
    }

    @IBAction func previousPage(_ sender: Any?) {
        navigatePage(manager.prevPage())
    }

    private func navigatePage(_ content: BookContent?) {
        loadText(content?.nash, content: content, navigateToContent: true)
    }

    private func loadText(
        _ text: String?,
        content: BookContent? = nil,
        navigateToContent: Bool = false
    ) {
        guard let text else {
            updateNotFoundString()
            return
        }
        let options = IbarotTextOptions(
            content: content,
            color: .header,
            isMultiLanguage: false,
            isImported: false,
            keepScrollPosition: false
        )

        textDelegate?.loadIbarotText(text, options: options)

        if navigateToContent, let content {
            didNavigateContent?(content)
        }
    }
}

extension QuranNashVC: QuranDelegate {
    func didSelectAya(_ surah: SurahNode, aya: Quran) {
        let nash = manager.loadTafseer(for: aya.aya, in: surah.id)
        loadText(nash)
        ayahTextField.stringValue = aya.nass
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
              let content = manager.bkConn.getContent(bkid: String(selectedBook.id), contentId: id, quran: true)
        else { return }

        loadText(content.nash, content: content, navigateToContent: true)
        await textDelegate?.highlightAndScrollToText(highlightText, mode: mode, nearDistance: nearDistance)
    }
}
