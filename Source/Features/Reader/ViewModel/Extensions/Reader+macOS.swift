//
//  Reader+macOS.swift
//  Maktabah
//

import Foundation

struct ContentRenderPayload: Equatable {
    let text: String
    let content: BookContent?
    let keepScrollPosition: Bool

    init(text: String, content: BookContent? = nil, keepScrollPosition: Bool = false) {
        self.text = text
        self.content = content
        self.keepScrollPosition = keepScrollPosition
    }

    static func == (lhs: ContentRenderPayload, rhs: ContentRenderPayload) -> Bool {
        lhs.text == rhs.text && lhs.content === rhs.content && lhs.keepScrollPosition == rhs.keepScrollPosition
    }
}

extension ReaderViewModel {
    // MARK: - State Management

    func updateState(_ state: inout ReaderState) {
        state.edit {
            $0.currentBook = currentBook
            $0.currentPage = currentPage
            $0.currentID = currentID
            $0.currentPart = currentPart
        }
    }

    @discardableResult
    func restore(from state: ReaderState) -> BookContent? {
        guard state.hasContent else {
            cleanUpState()
            return nil
        }

        guard let book = state.currentBook else { return nil }

        do {
            try bookConnection.connect(archive: book.archive)
            if AppConfig.isUsingBundleMode,
               !BookArchiveIntegrator.shared.isBookIntegrated(book)
            {
                currentBook = nil
                return nil
            } else if currentBook?.id != book.id {
                currentBook = book
            }

            tocViewModel.loadTOC(book: book)

            if let id = state.currentID,
               let content = bookConnection.getContent(bkid: String(book.id), contentId: id)
            {
                updateContentState(with: content)
                return content
            }
        } catch {
            onError?(error)
        }

        return nil
    }

    func resetContentState() {
        contentText = ""
        currentPage = nil
        currentPart = nil
        currentID = nil
        currentContentId = 0
    }

    func cleanUpState() {
        resetContentState()
        currentBook = nil
        windowTitle = ""
        windowSubtitle = ""
        bookConnection = .init()
    }

    func refreshCurrentPage(keepScrollPosition: Bool = true) {
        guard let currentBook, let currentID,
              let content = bookConnection.getContent(
                  bkid: "\(currentBook.id)",
                  contentId: currentID
              )
        else { return }

        contentPayload = ContentRenderPayload(text: content.nash, content: content, keepScrollPosition: keepScrollPosition)
        onPayloadChanged?(contentPayload)
        onContentChanged?(content)
    }

    // MARK: - macOS: Window Title

    func updateWindowTitle(book: BooksData?, page: Int?, part: Int?) {
        guard let book else {
            windowTitle = ""
            windowSubtitle = ""
            onWindowTitleChanged?("", "")
            return
        }

        let title = book.book
        let muallif = DatabaseManager.shared.getAuthor(book.muallif)

        if let page {
            let pageArb = String(page).convertToArabicDigits()
            if let part {
                let partArb = String(part).convertToArabicDigits()
                let subtitle = "\(muallif?.nama ?? "") ・ الصفحة \(pageArb) ・ الجزء \(partArb)"
                windowTitle = title
                windowSubtitle = subtitle
                onWindowTitleChanged?(title, subtitle)
            } else {
                let subtitle = "\(muallif?.nama ?? "") ・ الصفحة \(pageArb)"
                windowTitle = title
                windowSubtitle = subtitle
                onWindowTitleChanged?(title, subtitle)
            }
        } else {
            windowTitle = title
            windowSubtitle = muallif?.nama ?? ""
            onWindowTitleChanged?(title, muallif?.nama ?? "")
        }
    }

    /// Connects to book archive with bundle fallback (macOS only)
    func connectBookWithBundleFallback(_ book: BooksData) async throws {
        try await BookIntegrateModalCenter.shared.ensureIntegrated(book: book)
        try bookConnection.connect(archive: book.archive)
    }

    func handleLibraryFolderChanged() {
        cleanUpState()
    }

    func handleBookIntegrated(_ notification: Notification) {
        guard let bookId = notification.object as? Int,
              let currentBook,
              currentBook.id == bookId,
              !BookArchiveIntegrator.shared.isBookIntegrated(currentBook)
        else { return }

        cleanUpState()
    }
}
