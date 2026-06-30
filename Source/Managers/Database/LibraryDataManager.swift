//
//  LibraryDataManager.swift
//  maktab
//
//  Created by MacBook on 03/12/25.
//

import Foundation

class LibraryDataManager {
    static let shared = LibraryDataManager()
    var db: DatabaseManager = .shared
    
    private let lock = NSRecursiveLock()

    private var _allRootCategories: [CategoryData] = []
    private var _categoryMap: [Int: CategoryData] = [:]
    private var _booksById: [Int: BooksData] = [:]
    private var _archives: [Int: ArchiveInfo] = [:]
    private var _archivesBuiltFromFullData: Bool = false
        private var _authorsCache: [Int: Muallif] = [:]
    private var _isDataLoaded = false
    private var _isAuthorsLoaded = false
    private var _loadingTask: Task<Void, Never>?

    var allRootCategories: [CategoryData] {
        lock.withLock { _allRootCategories }
    }

    var categoryMap: [Int: CategoryData] {
        lock.withLock { _categoryMap }
    }

    var booksById: [Int: BooksData] {
        lock.withLock { _booksById }
    }

    var archives: [Int: ArchiveInfo] {
        lock.withLock { _archives }
    }

    var authorsCache: [Int: Muallif] {
        lock.withLock { _authorsCache }
    }

    var isDataLoaded: Bool {
        lock.withLock { _isDataLoaded }
    }

    private init() {}

    func loadData() async {
        let taskToAwait: Task<Void, Never>? = lock.withLock {
            if _isDataLoaded {
                return nil
            }
            if let existing = _loadingTask {
                return existing
            }
            let newTask = Task { [self] in
                do {
                    let results = try await Task.detached(priority: .userInitiated) { [self] in
                        let allCategories = try db.fetchAllCategories()
                        let (localRootCats, localCategoryMap) =
                            buildCategoryHierarchy(from: allCategories)
                        let localBooksById = try loadBooksAndIndex(
                            for: allCategories
                        )
                        return (localRootCats, localCategoryMap, localBooksById)
                    }.value

                    lock.withLock {
                        _allRootCategories = results.0
                        _categoryMap = results.1
                        _booksById = results.2
                    }

                    await applyBundleDownloadMetadataIfNeeded()

                    lock.withLock {
                        _isDataLoaded = true
                    }

                    // Bangun integration cache di background setelah data siap.
                    Task.detached(priority: .background) {
                        IntegrationCache.shared.buildAllIfNeeded()
                    }
                } catch {
                    #if DEBUG
                        print("Error loading data: \(error)")
                    #endif
                }

                lock.withLock {
                    _loadingTask = nil
                }
            }
            _loadingTask = newTask
            return newTask
        }

        if let task = taskToAwait {
            await task.value
        }
    }

    func reloadAllData() async {
        lock.withLock {
            _isDataLoaded = false
            _archivesBuiltFromFullData = false
        }
        await loadData()
    }

    // MARK: - Helpers for loading data
    private func buildCategoryHierarchy(from allCategories: [CategoryData]) -> (
        rootCats: [CategoryData], categoryMap: [Int: CategoryData]
    ) {
        var localCategoryMap: [Int: CategoryData] = [:]
        var localRootCats: [CategoryData] = []
        var currentRoot: CategoryData?

        // Build hierarki berdasarkan level dan urutan
        for cat in allCategories {
            localCategoryMap[cat.id] = cat

            if cat.level == 0 {
                localRootCats.append(cat)
                currentRoot = cat
            } else if cat.level == 1, let root = currentRoot {
                root.children.append(cat)
            }
        }

        return (localRootCats, localCategoryMap)
    }

    private func loadBooksAndIndex(for allCategories: [CategoryData]) throws
        -> [Int: BooksData]
    {
        var localBooksById: [Int: BooksData] = [:]

        // Fetch all books grouped by category to avoid N+1 query
        let allBooksGrouped = try db.fetchAllBooksGroupedByCategory()

        // Assign buku untuk setiap kategori
        for cat in allCategories {
            let books = allBooksGrouped[cat.id] ?? []
            cat.children.append(contentsOf: books)
            for book in books {
                if localBooksById[book.id] == nil {
                    localBooksById[book.id] = book
                }
            }
        }

        return localBooksById
    }

    private func applyBundleDownloadMetadataIfNeeded() async {
        guard AppConfig.isUsingBundleMode,
              let indexURL = AppConfig.bookIndexURL else { return }

        do {
            let entries = try await BookDownloadIndexCache.shared.entries(
                indexURL: indexURL,
                urlSession: URLSession.shared
            )

            lock.withLock {
                for (bookId, entry) in entries {
                    guard let book = _booksById[bookId] else { continue }
                    book.downloadFilename = entry.filename
                    book.compressedDownloadSize = entry.sizeZst
                }
            }
        } catch {
            #if DEBUG
                print("Failed to apply bundle download metadata:", error)
            #endif
        }
    }

    func getAllAuthors() -> [(id: Int, muallif: Muallif)] {
        let (isLoaded, cachedRes) = lock.withLock {
            if _isAuthorsLoaded {
                return (true, _authorsCache.map { (id: $0.key, muallif: $0.value) })
            }
            return (false, [])
        }
        
        if isLoaded {
            return cachedRes
        }

        let fetched = DatabaseManager.shared.fetchAllAuthors()
        
        lock.withLock {
            for author in fetched {
                _authorsCache[author.id] = author.muallif
            }
            _isAuthorsLoaded = true
        }
        return fetched
    }

    func resetState() {
        lock.withLock {
            _loadingTask?.cancel()
            _loadingTask = nil
            _isDataLoaded = false
            _isAuthorsLoaded = false
            _allRootCategories.removeAll()
            _categoryMap.removeAll()
            _authorsCache.removeAll()
            _booksById.removeAll()
            _archives.removeAll()
            _archivesBuiltFromFullData = false
        }
    }

    func updateAuthorInCache(id: Int, muallif: Muallif) {
        lock.withLock {
            _authorsCache[id] = muallif
        }
    }

    func removeAuthorFromCache(id: Int) {
        lock.lock()
        _authorsCache.removeValue(forKey: id)
        lock.unlock()
    }

    func getAuthorFromCache(id: Int) -> Muallif? {
        lock.withLock {
            _authorsCache[id]
        }
    }

    func getBook(_ ids: [Int]) -> [BooksData] {
        var books = [BooksData]()
        var idsToFetch = [Int]()
        
        lock.withLock {
            for id in ids {
                if let book = _booksById[id] {
                    books.append(book)
                } else {
                    idsToFetch.append(id)
                }
            }
        }

        for id in idsToFetch {
            do {
                if let book = try db.fetchBook(byId: id) {
                    lock.withLock {
                        _booksById[id] = book
                        books.append(book)
                    }
                }
            } catch {
                #if DEBUG
                    print(error.localizedDescription)
                #endif
            }
        }

        return books
    }

    func categoryLevel(for book: BooksData) -> Int? {
        guard let catId = book.catId else { return nil }
        return lock.withLock { _categoryMap[catId]?.level }
    }

    func buildArchive() async {
        let (built, isLoaded, rootCats) = lock.withLock {
            (_archivesBuiltFromFullData, _isDataLoaded, _allRootCategories)
        }
        if built || !isLoaded { return }

        // gunakan var lokal agar thread-safe selama build
        var archives: [Int: ArchiveInfo] = [:]
        var seenTables = Set<String>() // untuk menghindari duplikat

        // rekursif kumpulkan BooksData dari node (CategoryData atau BooksData)
        func collectBooks(from node: Any) -> [BooksData] {
            var result: [BooksData] = []

            if let book = node as? BooksData {
                result.append(book)
            } else if let cat = node as? CategoryData {
                for child in cat.children {
                    result.append(contentsOf: collectBooks(from: child))
                }
            }
            return result
        }

        // iterasi semua root category dan kumpulkan buku dari seluruh subtree
        for root in rootCats {
            let books = collectBooks(from: root)
            for book in books {
                let archiveId = book.archive
                // LEWATI SEMUA ARCHIVE = 0
                if archiveId == 0 {
                    continue
                }
                let tableName = "b\(book.id)"

                // hindari memasukkan tabel yang sama berkali-kali
                if seenTables.contains("\(archiveId)|\(tableName)") {
                    continue
                }
                seenTables.insert("\(archiveId)|\(tableName)")

                if archives[archiveId] == nil {
                    archives[archiveId] = ArchiveInfo(tables: [], books: [])
                }

                archives[archiveId]?.tables.append(tableName)
                archives[archiveId]?.books.append(book)
            }
        }

        lock.withLock {
            self._archives = archives
            _archivesBuiltFromFullData = true
        }
    }

    private func createConnections(dbPath: String, count: Int = 4) -> [DBConnectionType] {
        var connections: [DBConnectionType] = []

        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("⚠️ File tidak ditemukan: \(dbPath)")
            return []
        }

        for i in 0..<count {
            do {
                let conn = try SQLiteConnection(dbPath: dbPath)
                connections.append(conn)
            } catch {
                print("⚠️ Connection \(i+1) gagal untuk \(dbPath): \(error)")
            }
        }

        return connections
    }

    func getDatabasePath(forArchive archiveId: Int) -> String? {
        AppConfig.archiveDatabasePath(archiveId: archiveId)
    }

    func getCheckedTables(_ items: [Any]) -> Set<String> {
        var checkedTables = Set<String>()

        func traverse(_ items: [Any]) {
            for item in items {
                if let category = item as? CategoryData {
                    // Jika kategori dicentang, kita tetap harus cek anaknya
                    // (siapa tahu ada user uncheck sebagian anak)
                    traverse(category.children)
                } else if let book = item as? BooksData {
                    if book.isChecked {
                        // Format nama tabel: "b" + id
                        checkedTables.insert("b\(book.id)")
                    }
                }
            }
        }

        traverse(items)
        return checkedTables
    }

    func performSearch(
        tableToScan: Set<String> = [],
        searchEngine: SearchEngine,
        query: String,
        mode: SearchMode,
        onInitialize: @escaping @MainActor (Int) -> Void,
        onTableProgress: @escaping @MainActor (Int) -> Void,
        onRowProgress: @escaping @MainActor (String, String, Int, Int) -> Void,
        completion: @escaping @MainActor (SearchResultItem) -> Void,
        onComplete: @escaping @MainActor () -> Void
    ) async {
        let allowed = tableToScan

        let searchKeywords: [String]
        switch mode {
        case .phrase:
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                return
            }
            searchKeywords = [query.normalizeArabic()]
        case .contains, .or:
            searchKeywords = query.normalizeArabic().components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        if searchKeywords.isEmpty {
            return
        }

        let (archivesCount, allowedByArchive) = lock.withLock {
            var allowedByArchive: [Int: Set<String>] = [:]
            for tableName in allowed {
                let bookId = Int(tableName.dropFirst()) ?? 0
                if let book = _booksById[bookId] {
                    allowedByArchive[book.archive, default: []].insert(tableName)
                }
            }
            return (_archives.count, allowedByArchive)
        }

        #if DEBUG
            print(
                "Filter: Dari \(archivesCount) archive → \(allowedByArchive.keys.count) relevan")
        #endif

        var totalTables = 0

        for archiveId in allowedByArchive.keys.sorted() {
            if Task.isCancelled { return }
            
            guard let archiveInfo = archives[archiveId] else { continue }
            guard let dbPath = getDatabasePath(forArchive: archiveId) else {
                continue
            }
            let connections = createConnections(dbPath: dbPath, count: 4)

            if connections.isEmpty {
                print("⚠️ Skip archive \(archiveId): Tidak ada koneksi")
                continue
            }

            // Validasi: pastikan table ada di archive dan diizinkan (O(1) lookup per item)
            let allowedForThisArchive = allowedByArchive[archiveId] ?? []
            let relevantTablesForArchive = archiveInfo.tables.filter {
                allowedForThisArchive.contains($0)
            }
            guard !relevantTablesForArchive.isEmpty else { continue }

            totalTables += relevantTablesForArchive.count

            searchEngine.registerDB(
                archiveId: String(archiveId),
                tables: archiveInfo.tables,  // Masih kirim semua tables, filtering di worker
                connections: connections,
                batchSize: 200
            )
            #if DEBUG
                print("Worker archive \(archiveId): \(relevantTablesForArchive.count) tables")
            #endif
        }

        if totalTables == 0 || Task.isCancelled {
            return
        }

        searchEngine.checkAndResumeIfNeeded { [weak self] resumed in
            guard let self, !resumed else { return }
            if Task.isCancelled { return }

            var completedTablesGlobal = 0

            searchEngine.startSearch(
                keywords: searchKeywords,
                allowedTables: allowed.isEmpty ? nil : allowed,
                mode: mode,
                onInitialize: { totalWorkers in
                    Task { @MainActor [totalTables] in
                        // Kirim hanya total tables
                        onInitialize(totalTables)
                    }
                },
                onTableComplete: { archiveId, completedTablesInWorker in
                    completedTablesGlobal += 1
                    Task { @MainActor [completedTablesGlobal] in
                        onTableProgress(completedTablesGlobal)
                    }
                }, 
                onRowProgress: { archiveId, tableName, current, total in
                    // ✅ Forward ke UI
                    Task { @MainActor in
                        onRowProgress(archiveId, tableName, current, total)
                    }
                },
                onResult: { tableName, archive, content in
                    Task { @MainActor in
                        let bookId = Int(tableName.dropFirst()) ?? 0
                        let (bookTitle, isMultilingual, isImported) = self.lock.withLock {
                            let book = self._booksById[bookId]
                            return (book?.book ?? "", book?.isMultiLanguage ?? false, book?.isImported ?? false)
                        }

                        // Strip tags untuk imported books (lebih efisien dengan versi ringan)
                        let strippedNash = isImported ? content.nash.stripSpanTags() : content.nash
                        let normalizedNash = strippedNash.convertToArabicDigits(isMultilingual: isMultilingual)
                        let searchKeywordsConverted = searchKeywords.map { $0.convertToArabicDigits(isMultilingual: isMultilingual) }
                        let snippet = normalizedNash
                            .normalizeArabic()
                            .snippetAround(keywords: searchKeywordsConverted, contextLength: 60)
                        let highlightedSnippet = snippet.highlightedAttributedText(
                            keywords: searchKeywordsConverted)
                        completion(
                            SearchResultItem(
                                archive: archive,
                                tableName: tableName,
                                bookId: content.id,
                                bookTitle: bookTitle,
                                page: content.page,
                                part: content.part,
                                attributedText: highlightedSnippet
                            ))
                    }
                },
                onComplete: {
                    Task { @MainActor in
                        onComplete()
                    }
                }
            )
        }
    }

    // MARK: - Generic Hierarchy Filtering logic

    func filterContent(
        with searchText: String,
        displayedCategories: inout [CategoryData],
        baseCategories: [CategoryData]? = nil
    ) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let normalizedSearchText = trimmed.normalizeArabic()
        
        let base = baseCategories ?? lock.withLock { _allRootCategories }

        if trimmed.isEmpty {
            // Tampilkan semua (sesuai base)
            displayedCategories = base
        } else {
            // Filter dari base
            displayedCategories = base.compactMap { rootCategory in
                filterCategory(rootCategory, searchText: normalizedSearchText)
            }
        }

        return !trimmed.isEmpty
    }

    /// Filter hierarchy untuk search (category mode)
    func filterCategory(_ category: CategoryData, searchText: String) -> CategoryData? {
        let normalizedSearch = searchText.normalizeArabic(false)
        let categoryMatches = category.name.normalizeArabic(false).localizedStandardContains(normalizedSearch)

        // Jika kategori sendiri cocok, tampilkan semua children-nya tanpa filter
        // (misalnya: author "Imam Nawawi" cocok → semua bukunya ditampilkan)
        if categoryMatches {
            let cloned = category.copy() as! CategoryData
            cloned.children = category.children
            return cloned
        }

        // Jika kategori tidak cocok, filter children secara rekursif
        let filteredChildren = category.children.compactMap { child -> Any? in
            if let childCategory = child as? CategoryData {
                return filterCategory(childCategory, searchText: normalizedSearch)
            } else if let book = child as? BooksData {
                if book.book.normalizeArabic(false).localizedStandardContains(normalizedSearch) {
                    return book
                }
            }
            return nil
        }

        // Jika ada children yang cocok, return kategori dengan children yang terfilter
        if !filteredChildren.isEmpty {
            let cloned = category.copy() as! CategoryData
            cloned.children = filteredChildren
            return cloned
        }

        return nil
    }

    /// Filter author hierarchy untuk search (author mode) - optimized version
    func filterAuthorHierarchy(_ categories: [CategoryData], searchText: String) -> [CategoryData] {
        let normalizedSearch = searchText.normalizeArabic(false)

        // First: find exact author name matches (fast path)
        var matchedAuthors: [CategoryData] = []

        for category in categories {
            if category.name.normalizeArabic(false).localizedStandardContains(normalizedSearch) {
                // Author name matches - return ALL books under this author
                let cloned = category.copy() as! CategoryData
                cloned.children = category.children
                matchedAuthors.append(cloned)
            }
        }

        // If we found exact matches, return them immediately
        if !matchedAuthors.isEmpty {
            return matchedAuthors
        }

        // Second: no exact match - search in book titles within each author
        var result: [CategoryData] = []
        for category in categories {
            let matchingBooks = category.children.compactMap { child -> Any? in
                if let book = child as? BooksData {
                    if book.book.normalizeArabic(false).localizedStandardContains(normalizedSearch) {
                        return book
                    }
                }
                return nil
            }

            if !matchingBooks.isEmpty {
                let cloned = category.copy() as! CategoryData
                cloned.children = matchingBooks
                result.append(cloned)
            }
        }

        return result
    }

    /// Fungsi helper utama untuk memfilter hierarchy berdasarkan kondisi buku dan kategori.
    private func applyHierarchyFilter(
        to category: CategoryData,
        bookCondition: (BooksData) -> Bool,
        includeCategoryIfEmpty: (CategoryData) -> Bool = { _ in false }
    ) -> CategoryData? {
        let filteredChildren: [Any] = category.children.compactMap { child in
            if let book = child as? BooksData {
                return bookCondition(book) ? book : nil
            } else if let subCategory = child as? CategoryData {
                return applyHierarchyFilter(
                    to: subCategory,
                    bookCondition: bookCondition,
                    includeCategoryIfEmpty: includeCategoryIfEmpty
                )
            }
            return nil
        }

        // Tentukan apakah kategori ini harus disertakan
        let shouldInclude =
        !filteredChildren.isEmpty || includeCategoryIfEmpty(category)

        if shouldInclude {
            let cloned = category.copy() as! CategoryData
            cloned.children = filteredChildren
            return cloned
        }

        return nil
    }

    /// Kembalikan salinan hierarchy yang hanya berisi kitab yang belum terintegrasi.
    func filterNotIntegrated() -> [CategoryData] {
        let rootCats = lock.withLock { _allRootCategories }
        return rootCats.compactMap { root in
            applyHierarchyFilter(to: root) {
                !BookArchiveIntegrator.shared.isBookIntegrated($0)
            }
        }
    }

    /// Bangun hierarchy berdasarkan Author (Muallif)
    /// Root = Author, Children = BooksData yang ditulis oleh author tersebut
    func buildAuthorHierarchy() -> [CategoryData] {
        // Langsung fetch authors dari database, jangan rely pada cache
        let authors = DatabaseManager.shared.fetchAllAuthors()

        // Handle potential duplicate author IDs by keeping the first occurrence
        var authorMap: [Int: Muallif] = [:]
        for author in authors {
            if authorMap[author.id] == nil {
                authorMap[author.id] = author.muallif
            }
        }

        // Collect ALL books from _booksById (sumber resmi semua buku)
        let allBooks: [BooksData] = lock.withLock {
            Array(_booksById.values)
        }

        // Group books by muallif
        var booksByAuthor: [Int: [BooksData]] = [:]
        var booksWithNoAuthor: [BooksData] = []

        for book in allBooks {
            if book.muallif == 0 {
                booksWithNoAuthor.append(book)
            } else {
                booksByAuthor[book.muallif, default: []].append(book)
            }
        }

        // Debug: print author counts
        #if DEBUG
            print("=== Author Hierarchy Debug ===")
            print("Total books in _booksById: \(allBooks.count)")
            print("Total authors in Auth table: \(authors.count)")
            print("Author groups (muallif != 0): \(booksByAuthor.count)")
            print("Books with muallif=0: \(booksWithNoAuthor.count)")

            // Show sample of author IDs that have books but not in Auth table
            let authorIdsInBooks = Set(booksByAuthor.keys)
            let authorIdsInAuthTable = Set(authors.map { $0.id })
            let missingAuthorIds = authorIdsInBooks.subtracting(authorIdsInAuthTable)
            if !missingAuthorIds.isEmpty {
                print("Author IDs in books but NOT in Auth table: \(missingAuthorIds.prefix(10))")
            }
        #endif

        // Build author categories
        var authorCategories: [CategoryData] = []
        var processedAuthorIds: Set<Int> = []

        // First pass: authors that exist in the Auth table
        for (authorId, muallif) in authors {
            let books = booksByAuthor[authorId] ?? []
            guard !books.isEmpty else { continue }

            processedAuthorIds.insert(authorId)

            let authorCategory = CategoryData(
                id: authorId,
                name: muallif.nama,
                level: 0,
                order: authorId
            )
            authorCategory.children = books.sorted { $0.book < $1.book }
            authorCategories.append(authorCategory)
        }

        // Second pass: authors not in Auth table but have books
        let unprocessedBooks = booksByAuthor.filter { !processedAuthorIds.contains($0.key) }
        for (authorId, books) in unprocessedBooks.sorted(by: { $0.key < $1.key }) {
            guard !books.isEmpty else { continue }

            let authorName = authorMap[authorId]?.nama ?? "Unknown Author (\(authorId))"

            let authorCategory = CategoryData(
                id: authorId,
                name: authorName,
                level: 0,
                order: authorId
            )
            authorCategory.children = books.sorted { $0.book < $1.book }
            authorCategories.append(authorCategory)
        }

        // Third pass: books with muallif = 0
        if !booksWithNoAuthor.isEmpty {
            let noAuthorCategory = CategoryData(
                id: 0,
                name: "---",
                level: 0,
                order: Int.max
            )
            noAuthorCategory.children = booksWithNoAuthor.sorted { $0.book < $1.book }
            authorCategories.append(noAuthorCategory)
        }

        if let index = authorCategories.firstIndex(where: { $0.id == 0 }), index != authorCategories.count - 1 {
            let noAuthor = authorCategories.remove(at: index)
            authorCategories.append(noAuthor)
        }

        #if DEBUG
            print("Total author categories created: \(authorCategories.count)")
            print("Total books in author hierarchy: \(authorCategories.reduce(0) { $0 + $1.children.count })")
            print("=== End Debug ===")
        #endif

        return authorCategories
    }

    func filterByAuthor(_ authorId: Int) -> [CategoryData] {
        let rootCats = lock.withLock { _allRootCategories }
        return rootCats.compactMap { root in
            applyHierarchyFilter(to: root) {
                $0.muallif == authorId
            }
        }
    }

    func filterIntegrated(base: [CategoryData]? = nil) -> [CategoryData] {
        let rootCats = base ?? lock.withLock { _allRootCategories }
        return rootCats.compactMap { root in
            applyHierarchyFilter(to: root) {
                BookArchiveIntegrator.shared.isBookIntegrated($0)
            }
        }
    }

    func loadBookInfo(_ id: Int, completion: @escaping () -> Void?) {
        defer { completion() }
        guard let book = booksById[id],
              book.info.isEmpty, book.bithoqoh.isEmpty
        else { return }
        db.fetchBooksInfo(for: book)
    }

    /// Cek apakah Book ID memenuhi syarat untuk dihapus berdasarkan versi core
    static func shouldRemoveBook(id: Int) -> Bool {
        let coreVersion = AppConfig.cachedCoreVersionDouble ?? 0.1
        return coreVersion >= 1.0 ? id > 151203 : id > 32792
    }

    /// Cek apakah Author ID memenuhi syarat untuk dihapus berdasarkan versi core
    static func shouldRemoveAuthor(muallifId: Int) -> Bool {
        let coreVersion = AppConfig.cachedCoreVersionDouble ?? 0.1
        return coreVersion >= 1.0 ? muallifId > 3169 : muallifId > 2515
    }

    func removeBookFromMemory(id: Int, muallifId: Int) {
        lock.withLock {
            if Self.shouldRemoveBook(id: id) {
                _booksById.removeValue(forKey: id)
                for root in _allRootCategories {
                    removeBookFromHierarchy(root, bookId: id)
                }
            }

            if Self.shouldRemoveAuthor(muallifId: muallifId) {
                if !db.isAuthorUsed(authorId: muallifId) {
                    _authorsCache.removeValue(forKey: muallifId)
                }
            }
        }
    }

    private func removeBookFromHierarchy(_ category: CategoryData, bookId: Int) {
        category.children.removeAll { ($0 as? BooksData)?.id == bookId }
        for child in category.children {
            if let sub = child as? CategoryData {
                removeBookFromHierarchy(sub, bookId: bookId)
            }
        }
    }
}

extension LibraryDataManager {

    /// Update atau insert books berdasarkan BookUpdateResult
    /// - Parameter updateResults: Results dari book update process
    func processBookUpdates(_ updateResults: [BookUpdateResult]) async throws {
        guard !updateResults.isEmpty else { return }

        var insertedBooks: [(categoryId: Int, book: BooksData)] = []
        var updatedBookIds: Set<Int> = []

        for result in updateResults {
            let bookId = result.bookId

            switch result.action {
            case .inserted:
                // Fetch buku baru dari database
                if let book = try db.fetchBook(byId: bookId) {
                    lock.withLock {
                        // Tambahkan ke data structures
                        _booksById[bookId] = book

                        // Dapatkan category ID
                        let categoryId = result.catId

                        // Tambahkan ke category hierarchy
                        if let category = _categoryMap[categoryId] {
                            category.children.append(book)
                            insertedBooks.append((categoryId, book))
                        }
                    }

                    // Update archive
                    updateArchiveForBooks([book])
                }

            case .updated:
                // Fetch buku yang diupdate dari database
                if let book = try db.fetchBook(byId: bookId) {
                    lock.withLock {
                        // Update booksById cache
                        _booksById[bookId] = book

                        // Update di hierarchy tree
                        updateBookInHierarchy(book)
                    }

                    // Clear cache
                    BookPageCache.shared.remove(bookId: bookId)

                    // Update archive
                    updateArchiveForBooks([book])

                    updatedBookIds.insert(bookId)
                }

            case .skipped:
                // Do nothing
                break
            }
        }

        // Kirim combined notification
        if !insertedBooks.isEmpty || !updatedBookIds.isEmpty {
            NotificationCenter.default.postBooksChanged(
                insertedBooks: insertedBooks,
                updatedBookIds: updatedBookIds
            )
        }
    }

    /// Update single book di hierarchy tree
    private func updateBookInHierarchy(_ updatedBook: BooksData) {
        // Cari book di tree dan replace
        for category in _allRootCategories {
            if replaceBookInCategory(category, with: updatedBook) {
                break
            }
        }
    }

    private func replaceBookInCategory(_ category: CategoryData, with book: BooksData) -> Bool {
        // Cek children langsung
        for (index, child) in category.children.enumerated() {
            if let existingBook = child as? BooksData, existingBook.id == book.id {
                category.children[index] = book
                return true
            } else if let subCategory = child as? CategoryData {
                if replaceBookInCategory(subCategory, with: book) {
                    return true
                }
            }
        }
        return false
    }

    /// Update archive untuk beberapa buku
    private func updateArchiveForBooks(_ books: [BooksData]) {
        lock.withLock {
            for book in books {
                let archiveId = book.archive
                guard archiveId != 0 else { continue }

                let tableName = "b\(book.id)"

                if _archives[archiveId] == nil {
                    _archives[archiveId] = ArchiveInfo(tables: [], books: [])
                }

                // Remove old entry if exists
                if let index = _archives[archiveId]?.tables.firstIndex(of: tableName) {
                    _archives[archiveId]?.tables.remove(at: index)
                    if let booksCount = _archives[archiveId]?.books.count, index < booksCount {
                        _archives[archiveId]?.books.remove(at: index)
                    }
                }

                // Add new entry
                _archives[archiveId]?.tables.append(tableName)
                _archives[archiveId]?.books.append(book)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let booksChanged = Notification.Name("booksChanged")
    static let bookIntegrated = Notification.Name("bookIntegrated")
}

// MARK: - Type-safe Posting Helper

extension NotificationCenter {
    func postBooksChanged(
        insertedBooks: [(categoryId: Int, book: BooksData)],
        updatedBookIds: Set<Int>
    ) {
        let payload = BooksChangedNotification(
            insertedBooks: insertedBooks,
            updatedBookIds: updatedBookIds
        )
        post(name: .booksChanged, object: payload)
    }
}
