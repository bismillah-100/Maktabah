//
//  Search+macOS.swift
//  Maktabah
//

import Foundation

extension SearchViewModel {
    /// Load data library lalu isi `libraryViewManager` dengan kategori.
    nonisolated func loadLibraryDataForDisplay(
        libraryViewManager: LibraryViewManager?,
        onComplete: @MainActor @escaping () -> Void
    ) async {
        guard await state == .loading, let libraryViewManager else {
            await loadLibraryData()
            await onComplete()
            return
        }

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
