//
//  BookUpdateVM.swift
//  Maktabah
//
//  Created by MacBook on 06/02/26.
//

import Foundation
import SwiftUI

class BookUpdateViewModel: ObservableObject {
    @Published var availableUpdates: [BookUpdateItem] = []
    @Published var isLoadingList = false
    @Published var isUpdating = false
    @Published var progressMessage = ""
    @Published var updateResults: [BookUpdateResult] = []

    static let driveLink = "https://drive.google.com/uc?export=download&id="

    private let mainCSVURL = URL(
        string: driveLink + "1FYrscpCBIuIym2ZHB6QBwYfy9eswYDna"
    )!
    private let authCSVURL = URL(
        string: driveLink + "1Aekhq21Ihsxr1sAhnJSxZxA59yCxmEmq"
    )!

    // MARK: - Computed Properties

    var selectedCount: Int {
        availableUpdates.filter { $0.isSelected }.count
    }

    var totalSelectedSize: Int64 {
        availableUpdates.filter { $0.isSelected }.reduce(0) { $0 + $1.fileSize }
    }

    var totalSelectedSizeFormatted: String {
        ByteCountFormatter.string(
            fromByteCount: totalSelectedSize,
            countStyle: .file
        )
    }

    var hasUpdates: Bool {
        !availableUpdates.isEmpty
    }

    var needsUpdateCount: Int {
        availableUpdates.filter { $0.needsUpdate }.count
    }

    // MARK: - Load Available Updates

    func loadAvailableUpdates() {
        isLoadingList = true
        progressMessage = "Loading update lists...".localized

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let items = try await BookUpdateManager.shared
                    .fetchAvailableUpdates(from: mainCSVURL)

                availableUpdates = items
                progressMessage = String(localized: "Found \(needsUpdateCount) books that need to be updated")

            } catch {
                progressMessage = "Error: \(error.localizedDescription)"
                #if DEBUG
                    print("❌ [Load Updates] Error: \(error)")
                #endif
            }

            isLoadingList = false
        }
    }

    // MARK: - Select/Deselect Actions

    func selectAll() {
        for item in availableUpdates {
            item.isSelected = true
        }
    }

    func deselectAll() {
        for item in availableUpdates {
            item.isSelected = false
        }
    }

    func selectOnlyUpdates() {
        for item in availableUpdates {
            item.isSelected = item.needsUpdate
        }
    }

    // MARK: - Perform Selective Update

    func performSelectedUpdates() {
        let selectedItems = availableUpdates.filter { $0.isSelected }

        guard !selectedItems.isEmpty else {
            progressMessage = String(localized: "No books selected")
            return
        }

        isUpdating = true
        progressMessage = String(localized: "Starting \(selectedItems.count) books update...")
        updateResults.removeAll()

        Task { @MainActor [weak self] in
            defer { self?.isUpdating = false }
            guard let self else { return }

            do {
                // Download auth index sekali saja
                let authEntries = try await BookUpdateManager.shared
                    .fetchAuthIndexEntriesIfNeeded(
                        from: authCSVURL
                    )
                let authIndexMap = Dictionary(
                    uniqueKeysWithValues: authEntries.map { ($0.authId, $0) }
                )

                var completedCount = 0
                var updatedBookIds = Set<Int>()

                for item in selectedItems {
                    // Update status
                    item.status = .downloading
                    progressMessage = String(localized:
                        "Downloading: \(item.bookName) (\(completedCount + 1)/\(selectedItems.count))"
                    )

                    do {
                        // Buat entry dari item
                        let entry = BookIndexEntry(
                            bkid: item.id,
                            bk: item.bookName,
                            category: item.category,
                            versionName: item.newVersion,
                            downloadURL: item.downloadURL,
                            fileSize: item.fileSize
                        )

                        item.status = .processing

                        // Process single book
                        if let result = try await BookUpdateManager.shared
                            .processSingleBook(
                                entry,
                                authIndex: authIndexMap
                            )
                        {
                            updateResults.append(result)
                            item.status = .completed
                            completedCount += 1

                            // Collect updated book ID
                            updatedBookIds.insert(item.id)
                        } else {
                            item.status = .skipped
                        }

                    } catch {
                        item.status = .failed(error.localizedDescription)
                        #if DEBUG
                            print(
                                "❌ [Update] Failed to update book \(item.id): \(error)"
                            )
                        #endif
                    }
                }

                progressMessage = String(localized:
                    "Completed! \(completedCount)/\(selectedItems.count) books successfully updated."
                )

                try await LibraryDataManager.shared.processBookUpdates(updateResults)

            } catch {
                progressMessage = "Error: \(error.localizedDescription)"
                #if DEBUG
                    print("❌ [Perform Updates] Error: \(error)")
                #endif
            }

            isUpdating = false
        }
    }
}
