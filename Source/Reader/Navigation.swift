//
//  Navigation.swift
//  maktab
//
//  Created by MacBook on 30/11/25.
//

import Cocoa

class Navigation: NSViewController {

    @IBOutlet weak var juzCurrent: NSTextField!
    @IBOutlet weak var juzMax: NSTextField!
    @IBOutlet weak var juzSlider: NSSlider!
    @IBOutlet weak var juzTextVStack: NSStackView!
    @IBOutlet weak var juzSliderVStack: NSStackView!
    @IBOutlet weak var hLine: NSBox!
    @IBOutlet weak var rootStackView: NSStackView!

    @IBOutlet weak var pageCurrent: NSTextField!
    @IBOutlet weak var pageMax: NSTextField!
    @IBOutlet weak var pageSlider: NSSlider!

    @IBOutlet weak var xBtn: NSButton!

    weak var delegate: NavigationDelegate?

    var bookDB: BookConnection?
    var currentBook: BooksData?
    var popover: Bool = true

    var workItem: DispatchWorkItem?
    var juzWorkItem: DispatchWorkItem?

    var currentJuz: Int = 0 {
        didSet {
            juzSlider.integerValue = currentJuz
            juzCurrent.stringValue = "\(currentJuz)"
        }
    }

    var currentPage: Int = 0 {
        didSet {
            pageSlider.integerValue = currentPage
            pageCurrent.stringValue = "\(currentPage)"
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        xBtn.isHidden = popover
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.setupSliders()
        }
    }

    func setupSliders() async {
        guard let currentBook = currentBook,
            let bookDB = bookDB
        else { return }

        // Ambil total juz dari database
        let totalJuz = bookDB.getTotalParts(bkid: "\(currentBook.id)")

        #if DEBUG
            print(
                "totalJuz:",
                totalJuz,
                "currentBook:",
                currentBook.id,
                "archive:",
                currentBook.archive
            )
        #endif

        await MainActor.run {
            // Setup juz slider
            juzMax.stringValue = "\(totalJuz)"
            juzSlider.minValue = 1
            juzSlider.maxValue = Double(totalJuz)
            juzSlider.numberOfTickMarks = totalJuz
            juzSlider.allowsTickMarkValuesOnly = true
            let shouldHide = juzSlider.minValue == juzSlider.maxValue
            juzTextVStack.isHidden = shouldHide
            juzSliderVStack.isHidden = shouldHide
            hLine.isHidden = shouldHide
            juzSlider.integerValue = currentJuz
            rootStackView.layoutSubtreeIfNeeded()
        }

        // Setup page slider berdasarkan juz saat ini
        await updatePageSlider(forJuz: currentJuz)
    }

    func updatePageSlider(forJuz juz: Int) async {
        guard let currentBook = currentBook,
            let bookDB = bookDB
        else { return }

        // Ambil total halaman untuk juz tertentu
        let pagesInJuz = bookDB.getPagesInPart(
            bkid: "\(currentBook.id)",
            part: juz
        )

        await MainActor.run {
            // Setup page slider
            pageMax.stringValue = "\(pagesInJuz)"
            getMinpage(juzNumber: juz)
            pageSlider.isContinuous = true
        }
    }

    @IBAction func pageSliderChanged(_ sender: NSSlider) {
        guard sender.integerValue != Int(pageCurrent.stringValue) else {
            return
        }
        let pageNumber = sender.integerValue
        pageCurrent.stringValue = "\(pageNumber)"
        let juz = juzSlider.integerValue == 0 ? 1 : juzSlider.integerValue
        navigateToPage(pageNumber, juzNumber: juz, debounced: false)
    }

    @IBAction func juzSliderChanged(_ sender: NSSlider) {
        guard sender.integerValue != Int(juzCurrent.stringValue) else { return }
        let juzNumber = sender.integerValue
        juzCurrent.stringValue = "\(juzNumber)"

        juzWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            getMinpage(juzNumber: juzNumber, initial: false)
            navigateToPage(pageSlider.integerValue, juzNumber: juzNumber)
        }

        juzWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func getMinpage(juzNumber: Int, initial: Bool = true) {
        if currentBook == nil {
            if !initial { currentPage = -1 }
            return
        }

        getMinpageAsync(juzNumber: juzNumber) { [weak self] minPage, maxPage in
            guard let self else { return }
            pageSlider.minValue = Double(minPage)
            pageSlider.maxValue = Double(maxPage)
            if !initial {
                let clamped = max(minPage, min(currentPage, maxPage))
                if clamped != currentPage {
                    currentPage = clamped
                }
            }
            if currentPage == 0 { currentPage = minPage }
            pageMax.stringValue = String(maxPage)
        }
    }

    func getMinpageAsync(
        juzNumber: Int,
        completion: @escaping (Int, Int) -> Void
    ) {
        guard let bookDB, let currentBook else {
            completion(0, 0)
            return
        }

        let juz = juzNumber == 0 ? 1 : juzNumber
        let minPage = bookDB.getMinPagesInPart(
            bkid: String(currentBook.id),
            part: juz
        )

        let maxPage = bookDB.getPagesInPart(
            bkid: String(currentBook.id),
            part: juz
        )

        completion(minPage, maxPage)

    }

    func navigateToPage(
        _ pageNumber: Int,
        juzNumber: Int,
        debounced: Bool = true
    ) {
        workItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }

            guard let currentBook = currentBook,
                let bookDB = bookDB,
                let content = bookDB.getContent(
                    bkid: "\(currentBook.id)",
                    part: juzNumber,
                    page: pageNumber
                )
            else { return }

            delegate?.sliderDidNavigateInto(content: content)
        }

        workItem = item

        if !debounced {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(
                deadline: .now() + 0.2,
                execute: item
            )
        } else {
            DispatchQueue.global(qos: .userInteractive).async(execute: item)
        }
    }
}
