//
//  Search+Restoration.swift
//  Maktabah
//

import Foundation

extension SearchViewModel {
    // MARK: - SearchViewModel Restoration

    /// Memulihkan status pencarian dari `ReaderState` ke dalam properti ViewModel.
    /// - Parameter state: Objek `ReaderState` yang menyimpan status sebelumnya.
    /// - Returns: Boolean yang menandakan apakah ada data hasil pencarian yang berhasil dipulihkan.
    func restore(from state: ReaderState) {
        // Hanya restore jika hasil saat ini kosong untuk menghindari overwrite saat pencarian aktif
        guard results.isEmpty,
              let savedResults = state.searchResults,
              !savedResults.isEmpty
        else {
            return
        }

        // Memulihkan query teks pencarian jika tersedia
        if let savedQuery = state.searchQuery {
            query = savedQuery
        }
        if let raw = state.searchModeRaw, let mode = SearchMode(rawValue: raw) {
            searchMode = mode
        }
        if let dist = state.searchNearDistance {
            nearDistance = dist
        }

        // Memasukkan kembali daftar hasil pencarian yang tersimpan
        results = savedResults
    }

    /// Menyimpan status pencarian saat ini ke dalam referensi `ReaderState`.
    /// - Parameter state: Referensi inout `ReaderState` yang akan diperbarui.
    func updateState(_ state: inout ReaderState) {
        state.searchResults = results
        state.searchQuery = query
        state.searchModeRaw = searchMode.rawValue
        state.searchNearDistance = nearDistance
    }

    /// Membersihkan seluruh data pencarian di dalam ViewModel.
    func cleanUpState() {
        clearResults()
        query = ""
    }

    // MARK: - Helper Setters

    func resetProgress() {
        totalTables = 0
        completedTables = 0
        totalRowsInTable = 0
        completedRowsInTable = 0
        currentTable = ""
    }

    func setSearchMode(_ mode: SearchMode) {
        searchMode = mode
    }

    func setSearchModeFromSegment(_ segmentIndex: Int) {
        switch segmentIndex {
        case 0: searchMode = .phrase
        case 1: searchMode = .contains
        case 2: searchMode = .or
        case 3: searchMode = .near
        default: break
        }
    }

    func setTargetBook(_ bookId: String) {
        targetBookId = bookId
    }
}
