//
//  Search+iOS.swift
//  Maktabah
//

import Foundation

extension SearchViewModel {
    func setupDebouncedFilters() {
        filterSubject
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateDisplayedCategories() }
            .store(in: &cancellables)

        refreshSubject
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] in self?.updateDisplayedCategories() }
            .store(in: &cancellables)
    }

    func updateDisplayedCategories() {
        let base: [CategoryData] = AppConfig.isUsingBundleMode
            ? ldm.filterIntegrated()
            : ldm.allRootCategories

        if filterText.isEmpty {
            displayedCategories = base
        } else {
            displayedCategories = base.compactMap { ldm.filterCategory($0, searchText: filterText) }
        }
        updateTrigger += 1
    }

    // MARK: - History

    func loadHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    func addToHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = searchHistory
        current.removeAll { $0 == trimmed }
        current.insert(trimmed, at: 0)
        if current.count > 20 {
            current = Array(current.prefix(20))
        }
        searchHistory = current
        UserDefaults.standard.set(current, forKey: historyKey)
    }

    func removeFromHistory(_ query: String) {
        var current = searchHistory
        current.removeAll { $0 == query }
        searchHistory = current
        UserDefaults.standard.set(current, forKey: historyKey)
    }
}
