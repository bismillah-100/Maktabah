//
//  BookImportViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 04/09/26.
//

import Foundation
import OSLog
import SwiftUI
import Synchronization

@Observable
final class BookImportViewModel: @unchecked Sendable {
    // MARK: - State Properties

    var sqliteURL: URL?
    var isImporting: Bool = false
    var importMode: Int = 0 // 0 = New, 1 = Replace, 2 = Change ID
    var selectedBookId: Int?
    var bookName: String = ""
    var categoryId: Int = 0
    var archiveId: Int = 20
    var customBookIdText: String = ""
    var newIdAnnotationCount: Int = 0
    var betaka: String = ""
    var inf: String = ""
    var tafseerNam: String = ""
    var bVerText: String = "1"

    var isNewAuthor: Bool = false
    var selectedAuthorId: Int?
    var authorName: String = ""
    var authorInf: String = ""
    var authorLng: String = ""
    var authorHigriD: String = ""
    var oVerText: String = "1"
    var isMultiLanguage: Bool = true

    var maxBkid: Int = 0
    var maxAuthid: Int = 0

    var categories: [CategoryData] = []
    var authors: [(id: Int, muallif: Muallif)] = []
    var books: [BooksData] = []

    var showBookPicker: Bool = false
    var showAuthorPicker: Bool = false
    var showFilePicker: Bool = false
    var showHelpPopover: Bool = false
    var isLoadingData: Bool = true
    var hasLoadedData: Bool = false
    var showAnnotationsPopover: Bool = false

    let converterURL = URL(
        string: "https://maktabah-web-converter-dfbmqvd2wyzupyxlb38p5y.streamlit.app"
    )

    // MARK: - Computed Properties

    var isBookIdTaken: Bool {
        guard let id = Int(customBookIdText) else { return false }
        return LibraryDataManager.shared.booksById[id] != nil
    }

    var targetBookIdForAnnotationCheck: Int? {
        switch importMode {
        case 0:
            Int(customBookIdText)
        case 1:
            selectedBookId
        case 2:
            Int(customBookIdText)
        default:
            nil
        }
    }

    var isValid: Bool {
        if importMode == 2 {
            guard let oldId = selectedBookId else { return false }
            if customBookIdText.isEmpty {
                return false
            }
            guard let newId = Int(customBookIdText), newId > 0 else { return false }
            if newId == oldId || isBookIdTaken {
                return false
            }
            return true
        }

        if sqliteURL == nil {
            return false
        }
        if importMode == 0 {
            if customBookIdText.isEmpty {
                return false
            }
            guard let id = Int(customBookIdText), id > 0 else { return false }
            if isBookIdTaken {
                if LibraryDataManager.isCoreBook(id: id) {
                    return false
                }
            }
        } else {
            if selectedBookId == nil {
                return false
            }
        }
        if bookName.isEmpty || categoryId == 0 {
            return false
        }
        if isNewAuthor {
            if authorName.isEmpty {
                return false
            }
        } else {
            if selectedAuthorId == nil {
                return false
            }
        }
        return true
    }

    // MARK: - Initial Setup

    @MainActor
    func setupData(force: Bool = false) async {
        guard !hasLoadedData || force else { return }
        isLoadingData = true
        defer { isLoadingData = false }

        let results = await Task.detached(priority: .userInitiated) {
            let maxBkid = DatabaseManager.shared.getMaxBookId()
            let maxAuthid = DatabaseManager.shared.getMaxAuthId()

            let categories = Array(LibraryDataManager.shared.categoryMap.values).sorted(by: {
                $0.id < $1.id
            })

            let authors = LibraryDataManager.shared.getAllAuthors().sorted(by: { $0.id < $1.id })
            let books = Array(LibraryDataManager.shared.booksById.values).sorted(by: { $0.book < $1.book })

            return (maxBkid, maxAuthid, categories, authors, books)
        }.value

        guard !Task.isCancelled else { return }

        maxBkid = results.0
        maxAuthid = results.1
        categories = results.2
        authors = results.3
        books = results.4
        customBookIdText = "\(results.0 + 1)"
        hasLoadedData = true
    }

    // MARK: - Selection Helpers

    func selectBook(id: Int) {
        selectedBookId = id
        if let book = books.first(where: { $0.id == id }) {
            bookName = book.book
            archiveId = book.archive
            categoryId = book.catId ?? 0
            selectedAuthorId = book.muallif
            isNewAuthor = false
            isMultiLanguage = book.isMultiLanguage
            tafseerNam = book.tafseerNam ?? ""
            betaka = book.bithoqoh
            inf = book.info
        }
        showBookPicker = false
    }

    func selectAuthor(id: Int) {
        selectedAuthorId = id
        showAuthorPicker = false
    }

    func handleImportModeChanged(newMode: Int) {
        if newMode == 2 {
            customBookIdText = selectedBookId.map(String.init) ?? ""
        } else if newMode == 0 {
            customBookIdText = maxBkid > 0 ? "\(maxBkid + 1)" : ""
        }
        updateAnnotationCount()
    }

    func handleSelectedBookIdChanged(newId: Int?) {
        if importMode == 2, let newId {
            customBookIdText = "\(newId)"
        }
        updateAnnotationCount()
    }

    func handleCustomBookIdTextChanged(newValue: String) {
        let filtered = newValue.filter(\.isNumber)
        if filtered != newValue {
            customBookIdText = filtered
        } else {
            updateAnnotationCount()
        }
    }

    func updateAnnotationCount() {
        guard let id = targetBookIdForAnnotationCheck, id > 0 else {
            newIdAnnotationCount = 0
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let count = await Task.detached(priority: .utility) {
                AnnotationStore.shared.loadAnnotations(bkId: id).count
            }.value
            guard targetBookIdForAnnotationCheck == id else { return }
            newIdAnnotationCount = count
        }
    }

    deinit {
        if let sqliteURL {
            try? FileManager.default.removeItem(at: sqliteURL)
        }
    }

    func cleanupTemporaryFile() {
        guard let url = sqliteURL else { return }
        sqliteURL = nil
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - File Import Handling

    func handlePickedFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let selectedURL = urls.first else { return }

            let shouldStopAccessing = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(selectedURL.pathExtension)

                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }

                try FileManager.default.copyItem(at: selectedURL, to: tempURL)
                cleanupTemporaryFile()
                sqliteURL = tempURL
            } catch {
                Logger.library.error("Error copying file: \(error.localizedDescription, privacy: .public)")
            }

        case let .failure(error):
            Logger.library.error("Error picking file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Import & Change ID Operations

    @MainActor
    func performImport(onImport: (URL, BookMetadata, [String: Any]?) async -> Void) async {
        guard let url = sqliteURL else { return }
        isImporting = true
        defer {
            isImporting = false
            cleanupTemporaryFile()
        }

        let finalBookId = importMode == 0 ? (Int(customBookIdText) ?? (maxBkid + 1)) : (selectedBookId ?? 0)
        var finalAuthId: Int? = nil
        var authorRow: [String: Any]? = nil

        if isNewAuthor {
            finalAuthId = maxAuthid + 1
            authorRow = [
                "authid": finalAuthId!,
                "auth": authorName,
                "inf": authorInf,
                "Lng": authorLng,
                "HigriD": authorHigriD,
                "oVer": Int(oVerText) ?? 1,
            ]
        } else {
            finalAuthId = selectedAuthorId
        }

        let metadata = BookMetadata(
            bkid: finalBookId,
            cat: categoryId == 0 ? nil : categoryId,
            bk: bookName,
            archive: archiveId,
            betaka: betaka.isEmpty ? nil : betaka,
            authno: finalAuthId,
            inf: inf.isEmpty ? nil : inf,
            tafseerNam: tafseerNam.isEmpty ? nil : tafseerNam,
            bVer: Int(bVerText) ?? 1,
            link: nil,
            pdfCs: isMultiLanguage ? 3 : 0
        )

        await onImport(url, metadata, authorRow)
    }

    @MainActor
    func performChangeBookId() async {
        guard let oldId = selectedBookId else { return }
        guard let newId = Int(customBookIdText), newId > 0 else { return }
        let targetArchiveId = LibraryDataManager.shared.booksById[oldId]?.archive ?? archiveId

        isImporting = true
        defer { isImporting = false }

        do {
            let (migratedArchiveId, annotationsToSync, resultsToSync) = try await executeDatabaseChanges(
                oldId: oldId,
                newId: newId,
                archiveId: targetArchiveId
            )
            let event = BookLifecycleEvent.idChanged(
                oldId: oldId,
                newId: newId,
                oldArchiveId: migratedArchiveId,
                newArchiveId: migratedArchiveId
            )
            await reloadLocalCache(event: event)
            uploadToCloudKit(annotationsToSync: annotationsToSync, resultsToSync: resultsToSync)

            await setupData(force: true)
            selectedBookId = newId

            await BookLifecycleCoordinator.shared.emit(event)

            ReusableFunc.showAlert(
                title: "Success",
                message: "Book ID has been successfully changed from \(oldId) to \(newId), and annotations have been migrated."
            )
        } catch {
            ReusableFunc.showAlert(
                title: "Error changing ID",
                message: error.localizedDescription
            )
        }
    }

    private func executeDatabaseChanges(
        oldId: Int,
        newId: Int,
        archiveId: Int
    ) async throws -> (archiveId: Int, annotations: [Annotation], results: [SyncResult]) {
        let output = Mutex<(archiveId: Int, annotations: [Annotation], results: [SyncResult])?>(nil)
        try await BookArchiveSingleFlight.shared.run(archiveId: archiveId, bookId: oldId) {
            let value = try await Task.detached(priority: .userInitiated) {
                let migratedArchiveId = try BookUpdateManager.shared.changeBookIdAndReturnArchive(oldId: oldId, newId: newId)
                do {
                    let annotations = try AnnotationStore.shared.updateAnnotationsBookId(
                        oldId: oldId,
                        newId: newId,
                        uploadToCloudKit: false,
                        notifyTreeBuilder: false
                    )
                    do {
                        let results = try ResultsHandler.shared.migrateBookId(from: oldId, to: newId)
                        return (migratedArchiveId, annotations, results)
                    } catch {
                        _ = try? AnnotationStore.shared.updateAnnotationsBookId(
                            oldId: newId,
                            newId: oldId,
                            uploadToCloudKit: false
                        )
                        throw error
                    }
                } catch {
                    BookUpdateManager.shared.rollbackChangeBookId(
                        oldId: oldId,
                        newId: newId,
                        archiveId: migratedArchiveId
                    )
                    throw error
                }
            }.value
            output.withLock { $0 = value }
        }
        return output.withLock { $0 } ?? (archiveId, [], [])
    }

    private func reloadLocalCache(event: BookLifecycleEvent) async {
        BookCacheCoordinator.shared.invalidateSynchronously(for: event)
        await LibraryDataManager.shared.reloadAllData()
        await LibraryDataManager.shared.buildArchive()
    }

    private func uploadToCloudKit(
        annotationsToSync: [Annotation], resultsToSync: [SyncResult]
    ) {
        Task.detached(priority: .background) {
            if !annotationsToSync.isEmpty {
                CloudKitSyncManager.shared.upload(
                    annotations: annotationsToSync
                )
            }
            if !resultsToSync.isEmpty {
                CloudKitSyncManager.shared.uploadResultsData(
                    folders: [], results: resultsToSync
                )
            }
        }
    }
}
