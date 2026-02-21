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
                let authEntries = try await BookUpdateManager.shared
                    .fetchAuthIndexEntriesIfNeeded(
                        from: authCSVURL
                    )
                let authIndexMap = Dictionary(
                    uniqueKeysWithValues: authEntries.map { ($0.authId, $0) }
                )

                let selectedContexts = selectedItems.enumerated().map { index, item in
                    SelectedBookContext(
                        index: index,
                        item: item,
                        entry: BookIndexEntry(
                            bkid: item.id,
                            bk: item.bookName,
                            category: item.category,
                            versionName: item.newVersion,
                            downloadURL: item.downloadURL,
                            fileSize: item.fileSize
                        )
                    )
                }

                for context in selectedContexts {
                    context.item.status = .downloading
                }

                let stagedUpdates = await downloadSelectedBooksInParallel(
                    selectedContexts: selectedContexts,
                    authIndexMap: authIndexMap,
                    maxConcurrentDownloads: 3
                )

                progressMessage = String(localized:
                    "Download phase completed (\(stagedUpdates.count)/\(selectedItems.count)). Starting processing..."
                )

                var completedCount = 0
                var processingCount = 0

                for context in selectedContexts {
                    guard let stagedUpdate = stagedUpdates[context.index] else {
                        continue
                    }

                    context.item.status = .processing
                    processingCount += 1
                    progressMessage = String(localized:
                        "Processing: \(context.item.bookName) (\(processingCount)/\(selectedItems.count))"
                    )

                    do {
                        let result = try await BookUpdateManager.shared
                            .applyStagedBookUpdate(stagedUpdate)
                        updateResults.append(result)

                        switch result.action {
                        case .inserted, .updated:
                            context.item.currentVersion = context.item.newVersion
                            context.item.isSelected = false
                            context.item.status = .completed
                            completedCount += 1
                        case .skipped:
                            context.item.status = .skipped
                        }
                    } catch {
                        context.item.status = .failed(error.localizedDescription)
                        refreshAvailableUpdatesState()
                        #if DEBUG
                            print(
                                "[Update] Failed to update book \(context.item.id): \(error)"
                            )
                        #endif
                    }
                }

                progressMessage = String(localized:
                    "Completed! \(completedCount)/\(selectedItems.count) books successfully updated."
                )

                try await LibraryDataManager.shared.processBookUpdates(updateResults)
                refreshAvailableUpdatesState()
            } catch {
                progressMessage = "Error: \(error.localizedDescription)"
                #if DEBUG
                    print("❌ [Perform Updates] Error: \(error)")
                #endif
            }
        }
    }

    private struct SelectedBookContext {
        let index: Int
        let item: BookUpdateItem
        let entry: BookIndexEntry
    }

    private struct DownloadTaskInput {
        let index: Int
        let entry: BookIndexEntry
    }

    private struct DownloadTaskOutput {
        let index: Int
        let stagedUpdate: BookUpdateManager.StagedBookUpdate?
        let error: Error?
    }

    @MainActor
    private func downloadSelectedBooksInParallel(
        selectedContexts: [SelectedBookContext],
        authIndexMap: [Int: AuthIndexEntry],
        maxConcurrentDownloads: Int
    ) async -> [Int: BookUpdateManager.StagedBookUpdate] {
        var stagedUpdates: [Int: BookUpdateManager.StagedBookUpdate] = [:]
        let taskInputs = selectedContexts.map {
            DownloadTaskInput(index: $0.index, entry: $0.entry)
        }

        var completedDownloads = 0

        for chunkStart in stride(
            from: 0,
            to: taskInputs.count,
            by: maxConcurrentDownloads
        ) {
            let chunkEnd = min(chunkStart + maxConcurrentDownloads, taskInputs.count)
            let chunk = Array(taskInputs[chunkStart..<chunkEnd])

            await withTaskGroup(of: DownloadTaskOutput.self) { group in
                for taskInput in chunk {
                    group.addTask {
                        do {
                            let stagedUpdate = try await BookUpdateManager.shared
                                .stageBookDownload(
                                    taskInput.entry,
                                    authIndex: authIndexMap
                                )
                            return DownloadTaskOutput(
                                index: taskInput.index,
                                stagedUpdate: stagedUpdate,
                                error: nil
                            )
                        } catch {
                            return DownloadTaskOutput(
                                index: taskInput.index,
                                stagedUpdate: nil,
                                error: error
                            )
                        }
                    }
                }

                for await output in group {
                    completedDownloads += 1
                    let item = selectedContexts[output.index].item
                    if let stagedUpdate = output.stagedUpdate {
                        stagedUpdates[output.index] = stagedUpdate
                        item.status = .downloaded
                    } else if let error = output.error {
                        item.status = .failed(error.localizedDescription)
                        #if DEBUG
                            print(
                                "[Download] Failed to download book \(item.id): \(error)"
                            )
                        #endif
                    }

                    progressMessage = String(localized:
                        "Downloading books... (\(completedDownloads)/\(selectedContexts.count))"
                    )
                }
            }
        }

        return stagedUpdates
    }

    private func refreshAvailableUpdatesState() {
        // Reassign array agar computed property di SwiftUI ikut refresh
        availableUpdates = availableUpdates
    }
}
