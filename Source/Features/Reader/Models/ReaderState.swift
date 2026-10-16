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
    case bookContent // Tampilan dari table selection (buku biasa)
}

struct CleanedTextResult {
    let text: String
    let coloredRanges: [NSRange] // Range dalam string 'text'
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
    var expandedNodeIDs: [Int] = [] // IDs of expanded items
    var sidebarScrollPosition: CGPoint? // Scroll position of outline view

    /// Khusus untuk Author mode - menentukan apa yang ditampilkan
    var authorDisplayMode: AuthorDisplayMode?

    /// Scroll position (untuk restore) - ini untuk IbarotTextVC
    var scrollPosition: CGPoint?

    /// Text selection range (untuk restore)
    var selectedRange: NSRange?

    // MARK: - Search Results Persistence

    /// Untuk Author Mode - menyimpan hasil tarjamah
    var authorTarjamahResults: [TarjamahResult]?
    var authorRowiMode: String? // "sidebar" atau "fullSearch"
    var authorSearchQuery: String? // Query untuk full search

    /// Untuk Search Mode - menyimpan hasil search
    var searchResults: [SearchResultItem]?
    var searchQuery: String?
    var searchModeRaw: Int?
    var searchNearDistance: Int?

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

    enum CodingKeys: String, CodingKey {
        case currentBook, currentPage, currentID, currentPart, currentRowi
        case isSidebarCollapsed, expandedNodeIDs, sidebarScrollPosition
        case authorDisplayMode, scrollPosition, selectedRange
        case authorTarjamahResults, authorRowiMode, authorSearchQuery
        case searchResults, searchQuery, searchModeRaw, searchNearDistance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentBook = try container.decodeIfPresent(BooksData.self, forKey: .currentBook)
        currentPage = try container.decodeIfPresent(Int.self, forKey: .currentPage)
        currentID = try container.decodeIfPresent(Int.self, forKey: .currentID)
        currentPart = try container.decodeIfPresent(Int.self, forKey: .currentPart)
        currentRowi = try container.decodeIfPresent(Rowi.self, forKey: .currentRowi)
        isSidebarCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isSidebarCollapsed) ?? false
        expandedNodeIDs = try container.decodeIfPresent([Int].self, forKey: .expandedNodeIDs) ?? []
        sidebarScrollPosition = try container.decodeIfPresent(CGPoint.self, forKey: .sidebarScrollPosition)
        authorDisplayMode = try container.decodeIfPresent(AuthorDisplayMode.self, forKey: .authorDisplayMode)
        scrollPosition = try container.decodeIfPresent(CGPoint.self, forKey: .scrollPosition)
        selectedRange = try container.decodeIfPresent(NSRange.self, forKey: .selectedRange)
        authorTarjamahResults = try container.decodeIfPresent([TarjamahResult].self, forKey: .authorTarjamahResults)
        authorRowiMode = try container.decodeIfPresent(String.self, forKey: .authorRowiMode)
        authorSearchQuery = try container.decodeIfPresent(String.self, forKey: .authorSearchQuery)
        searchResults = try container.decodeIfPresent([SearchResultItem].self, forKey: .searchResults)
        searchQuery = try container.decodeIfPresent(String.self, forKey: .searchQuery)
        searchModeRaw = try container.decodeIfPresent(Int.self, forKey: .searchModeRaw)
        searchNearDistance = try container.decodeIfPresent(Int.self, forKey: .searchNearDistance)
    }

    mutating func edit(_ body: (inout ReaderState) -> Void) {
        body(&self)
    }

    /// Fungsi toggle sederhana
    mutating func toggleSidebar(_ collapsed: Bool) {
        isSidebarCollapsed = collapsed
    }
}

/// Extension untuk mudah compare state
extension ReaderState: Equatable {
    static func == (lhs: ReaderState, rhs: ReaderState) -> Bool {
        lhs.currentBook?.id == rhs.currentBook?.id
            && lhs.currentID == rhs.currentID
            && lhs.currentPage == rhs.currentPage
            && lhs.currentPart == rhs.currentPart
            && lhs.currentRowi?.id == rhs.currentRowi?.id
            && lhs.authorDisplayMode == rhs.authorDisplayMode
    }
}

/// Menyimpan seluruh state (Viewer, Search, Narrator) milik satu tab
struct TabStateSnapshot: Codable {
    var currentModeRaw: Int
    var viewerState: ReaderState
    var searchState: ReaderState
    var authorState: ReaderState

    var currentMode: AppMode {
        AppMode(rawValue: currentModeRaw) ?? .viewer
    }
}

/// Menyimpan daftar seluruh tab yang terbuka pada jendela utama beserta tab yang aktif
struct WindowTabsSession: Codable {
    var selectedTabIndex: Int
    var tabs: [TabStateSnapshot]
}
