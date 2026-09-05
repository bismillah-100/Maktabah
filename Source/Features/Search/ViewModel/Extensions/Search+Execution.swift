//
//  Search+Execution.swift
//  Maktabah
//

import Foundation

extension SearchViewModel {
    // MARK: - Search Execution

    func setSelectedBooks(_ bookIds: Set<Int>) {
        selectedBookIds = bookIds
    }

    @MainActor
    func startSearch() async {
        if query.isEmpty {
            return
        }

        let enginePaused = await searchEngine.currentlyPaused()
        if enginePaused || isPaused {
            searchEngine.resume()
            isPaused = false
            return
        }

        let engineRunning = await searchEngine.isRunning()
        if engineRunning || isSearching {
            searchEngine.pause()
            isPaused = true
            return
        }

        isSearching = true
        isPaused = false

        results = []
        totalTables = 0
        completedTables = 0
        completedRowsInTable = 0
        totalRowsInTable = 0

        let tablesToScan = resolveTablesToScan()
        if tablesToScan.isEmpty {
            stopSearch(); return
        }

        searchWork = Task.detached(priority: .userInitiated) { [weak self, tablesToScan] in
            guard let self else { return }

            let searchParams = LibrarySearchParams(
                tableToScan: tablesToScan,
                searchEngine: searchEngine,
                query: query.replacing("،", with: ","),
                mode: searchMode,
                nearDistance: nearDistance
            )
            let searchCallbacks = makeLibrarySearchCallbacks()

            await ldm.performSearch(
                params: searchParams,
                callbacks: searchCallbacks
            )
        }
    }

    func stopSearch() {
        searchEngine.stop()
        searchWork?.cancel()
        searchWork = nil
        isSearching = false
        isPaused = false
        emitComplete()
    }

    func clearResults() {
        stopSearch()
        results.removeAll()
    }

    func sortResults(by key: SearchSortKey, ascending: Bool) {
        SearchResultsSorter.sort(&results, by: key, ascending: ascending)
    }

    // MARK: - Helpers

    func resolveTablesToScan() -> Set<String> {
        if !selectedBookIds.isEmpty {
            return Set(selectedBookIds.map { "b\($0)" })
        }
        #if os(iOS)
        return ldm.getCheckedTables(displayedCategories)
        #else
        if !targetBookId.isEmpty {
            return [targetBookId]
        }
        return []
        #endif
    }

    func makeLibrarySearchCallbacks() -> LibrarySearchCallbacks {
        LibrarySearchCallbacks(
            onInitialize: { [weak self] total in self?.emitInitialize(total: total) },
            onTableProgress: { [weak self] completed in self?.emitTableProgress(completed: completed) },
            onRowProgress: { [weak self] _, tableName, current, total in
                self?.emitRowProgress(tableName: tableName, current: current, total: total)
            },
            completion: { [weak self] item in self?.emitResult(item: item) },
            onComplete: { [weak self] in self?.stopSearch() }
        )
    }

    // MARK: - Emits

    func emitInitialize(total: Int) {
        totalTables = total
        completedTables = 0
        #if os(macOS)
        searchDidInitialize.send(total)
        #endif
    }

    func emitTableProgress(completed: Int) {
        completedTables = completed
        #if os(macOS)
        searchProgressDidUpdate.send((completed: completed, totalTables))
        #endif
    }

    func emitRowProgress(tableName: String, current: Int, total: Int) {
        currentTable = tableName
        completedRowsInTable = current
        totalRowsInTable = total
        #if os(macOS)
        rowProgressDidUpdate.send((completed: current, total: total))
        #endif
    }

    func emitResult(item: SearchResultItem) {
        results.append(item)
        #if os(macOS)
        searchDidReceiveResult.send()
        #endif
    }

    func emitComplete() {
        #if os(macOS)
        completedTables = totalTables
        searchDidComplete.send()
        #endif
    }
}
