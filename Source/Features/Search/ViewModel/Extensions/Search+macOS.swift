//
//  Search+macOS.swift
//  Maktabah
//

import Foundation

extension SearchViewModel {
    /// Load data library lalu isi `libraryViewManager` dengan kategori.
    func loadLibraryDataForDisplay(
        libraryViewManager: LibraryViewManager?,
        onComplete: @MainActor @escaping () -> Void
    ) {
        guard state == .loading, let libraryViewManager else {
            Task { [weak self] in
                self?.loadLibraryData()
                await onComplete()
            }
            return
        }
        Task.detached(priority: .userInitiated) { [weak libraryViewManager] in
            guard let libraryViewManager else { await onComplete(); return }
            await libraryViewManager.prepareData { [weak self] in
                guard let self else { onComplete(); return }
                Task.detached { [weak self] in
                    guard let self else { return }
                    await ldm.buildArchive()
                    await onComplete()
                    await MainActor.run {
                        self.state = .loaded
                    }
                }
            }
        }
    }
}
