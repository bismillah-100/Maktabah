//
//  BookImportViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 04/09/26.
//

import Foundation
import SwiftUI

@Observable
final class BookImportViewModel {
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
                let coreVersion = AppConfig.cachedCoreVersionDouble ?? 0.1
                let system = coreVersion < 1.0 ? id <= 32792 : id <= 151_203
                if system {
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
    func setupData() async {
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

        maxBkid = results.0
        maxAuthid = results.1
        categories = results.2
        authors = results.3
        books = results.4
        customBookIdText = "\(results.0 + 1)"
    }

    // MARK: - Selection Helpers

    func selectBook(id: Int) {
        selectedBookId = id
        if let book = books.first(where: { $0.id == id }) {
            bookName = book.book
            archiveId = book.archive
            categoryId = book.catId ?? 0
        }
        showBookPicker = false
    }

    func selectAuthor(id: Int) {
        selectedAuthorId = id
        showAuthorPicker = false
    }

    func handleImportModeChanged(newMode: Int) {
        if newMode == 2, let selectedBookId {
            customBookIdText = "\(selectedBookId)"
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

        Task {
            let count = await Task.detached(priority: .utility) {
                AnnotationManager.shared.loadAnnotations(bkId: id).count
            }.value
            await MainActor.run { [weak self] in
                self?.newIdAnnotationCount = count
            }
        }
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
                sqliteURL = tempURL
            } catch {
                #if DEBUG
                print("Error copying file: \(error.localizedDescription)")
                #endif
            }

        case let .failure(error):
            #if DEBUG
            print("Error picking file: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Import & Change ID Operations

    @MainActor
    func performImport(onImport: (URL, BookMetadata, [String: Any]?) async -> Void) async {
        guard let url = sqliteURL else { return }
        isImporting = true
        defer { isImporting = false }

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

        isImporting = true
        defer { isImporting = false }

        do {
            let (annotationsToSync, resultsToSync) = try await executeDatabaseChanges(oldId: oldId, newId: newId)
            await reloadLocalCache(oldId: oldId, newId: newId)
            uploadToCloudKit(annotationsToSync: annotationsToSync, resultsToSync: resultsToSync)

            await setupData()
            selectedBookId = newId

            NotificationCenter.default.post(
                name: .bookIdMigrated,
                object: nil,
                userInfo: ["oldId": oldId, "newId": newId]
            )

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

    private func executeDatabaseChanges(oldId: Int, newId: Int) async throws -> ([Annotation], [SyncResult]) {
        try await Task.detached(priority: .userInitiated) {
            try BookUpdateManager.shared.changeBookId(oldId: oldId, newId: newId)
            let annotations = try AnnotationManager.shared.updateAnnotationsBookId(oldId: oldId, newId: newId)
            let results = try ResultsHandler.shared.migrateBookId(from: oldId, to: newId)
            return (annotations, results)
        }.value
    }

    private func reloadLocalCache(oldId: Int, newId: Int) async {
        await LibraryDataManager.shared.reloadAllData()

        if let book = LibraryDataManager.shared.booksById[newId] {
            IntegrationCache.shared.unmarkIntegrated(bookId: oldId, archiveId: book.archive)
            IntegrationCache.shared.markIntegrated(bookId: newId, archiveId: book.archive)
        }

        BookPageCache.shared.remove(bookId: oldId)
        BookConnection.invalidateTOC(for: oldId)
        BookConnection.totalPartsCache.removeObject(forKey: NSString(string: String(oldId)))
    }

    private func uploadToCloudKit(
        annotationsToSync: [Annotation], resultsToSync: [SyncResult]
    ) {
        if !annotationsToSync.isEmpty || !resultsToSync.isEmpty {
            DispatchQueue.global(qos: .background).async {
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
}
