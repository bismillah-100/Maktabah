//
//  BookInfo.swift
//  maktab
//
//  Created by MacBook on 09/12/25.
//

import Cocoa

class BookInfo: NSViewController {
    @IBOutlet var textView: IbarotTextView!
    @IBOutlet weak var xBtn: NSButton!
    @IBOutlet weak var stackView: NSStackView!
    @IBOutlet weak var segmentedControl: NSSegmentedControl!
    
    var bookData: BooksData?

    let db: DatabaseManager = .shared
    
    var popOver = true

    override func viewDidLoad() {
        super.viewDidLoad()
        xBtn.isHidden = popOver
        if #available(macOS 26.0, *) {
            segmentedControl.borderShape = .circle
        } else {
            // Fallback on earlier versions
        }
        // Do view setup here.
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let bookData else { return }
        loadText(bookData.bithoqoh)
    }

    @IBAction func bookSegment(_ sender: NSSegmentedControl) {
        guard let bookData else { return }
        switch sender.selectedSegment {
        case 0: displayAuthor(bookData.muallif)
        case 1: loadText(bookData.bithoqoh)
        case 2: loadText(bookData.info)
        default: break
        }
    }

    func loadText(_ string: String) {
        textView.loadText(string)
    }

    func displayAuthor(_ id: Int) {
        guard let author = db.getAuthor(id) else {
            return
        }

        let namaLengkap = author.namaLengkap
        let info = author.info

        let string = namaLengkap + "\n" + info

        loadText(string)
    }
}
