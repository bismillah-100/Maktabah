//
//  ReaderState.swift
//  Maktabah
//
//  State container untuk IbarotTextVC per mode
//

import Foundation

/// Display mode untuk Author mode (karena bisa tampil info Rowi atau buku)
enum AuthorDisplayMode: Equatable, Codable {
    case rowiInfo
    case bookContent  // Tampilan dari table selection (buku biasa)
}

/// State untuk satu instance viewer (bisa untuk mode berbeda)
struct ReaderState: Codable {
    var currentBook: BooksData?
    var currentPage: Int?
    var currentID: Int?
    var currentPart: Int?
    var currentRowi: Rowi?
    var isSidebarCollapsed: Bool = false

    // Sidebar/TOC State
    var expandedNodeIDs: [Int] = []  // IDs of expanded items
    var sidebarScrollPosition: CGPoint?  // Scroll position of outline view

    /// Khusus untuk Author mode - menentukan apa yang ditampilkan
    var authorDisplayMode: AuthorDisplayMode?

    /// Scroll position (untuk restore) - ini untuk IbarotTextVC
    var scrollPosition: CGPoint?

    /// Text selection range (untuk restore)
    var selectedRange: NSRange?

    // MARK: - Search Results Persistence

    /// Untuk Author Mode - menyimpan hasil tarjamah
    var authorTarjamahResults: [TarjamahResult]?
    var authorRowiMode: String?  // "sidebar" atau "fullSearch"
    var authorSearchQuery: String?  // Query untuk full search

    /// Untuk Search Mode - menyimpan hasil search
    var searchResults: [SearchResultItem]?
    var searchQuery: String?

    /// Pemeriksaan state (ada konten yang ditampilkan).
    var hasContent: Bool {
        if let authorMode = authorDisplayMode {
            switch authorMode {
            case .rowiInfo:
                return currentRowi != nil
            case .bookContent:
                return currentBook != nil || !(authorTarjamahResults?.isEmpty ?? true)
            }
        }
        return currentBook != nil
    }

    /// Initialize empty state
    init() {
        currentBook = nil
        currentPage = nil
        currentID = nil
        currentPart = nil
        scrollPosition = nil
        selectedRange = nil
        currentRowi = nil
        isSidebarCollapsed = false
        authorDisplayMode = nil
        expandedNodeIDs = []
        sidebarScrollPosition = nil
        authorTarjamahResults = nil
        authorRowiMode = nil
        authorSearchQuery = nil
        searchResults = nil
        searchQuery = nil
    }

    mutating func edit(_ body: (inout ReaderState) -> Void) {
        body(&self)
    }

    // Fungsi toggle sederhana
    mutating func toggleSidebar(_ collapsed: Bool) {
        isSidebarCollapsed = collapsed
    }
}

/// Extension untuk mudah compare state
extension ReaderState: Equatable {
    static func == (lhs: ReaderState, rhs: ReaderState) -> Bool {
        return lhs.currentBook?.id == rhs.currentBook?.id
            && lhs.currentID == rhs.currentID
            && lhs.currentRowi?.id == rhs.currentRowi?.id
            && lhs.authorDisplayMode == rhs.authorDisplayMode
    }
}
