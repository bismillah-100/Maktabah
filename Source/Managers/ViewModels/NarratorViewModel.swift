//
//  NarratorViewModel.swift
//  Maktabah
//
//  Created by Ghoys Mawahib on 18/06/26.
//

import Combine
import Foundation

#if os(iOS)
import UIKit
#endif

// MARK: - Display Mode

enum RowiDisplayMode: Int, CaseIterable, Identifiable {
    case tilmidz = 0
    case syaikh = 1
    case takdil = 2
    case mulakhosh = 3

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .tilmidz: "التلاميذ"
        case .syaikh: "الشيوخ"
        case .takdil: "الجرح والتعديل"
        case .mulakhosh: "ملخص"
        }
    }
}

// MARK: - ViewModel

#if os(iOS)
@Observable
#endif
final class NarratorViewModel: ViewModelBase {
    // MARK: - State
    var tabaqaGroups: [TabaqaGroup] = []
    var currentRowi: Rowi?
    var displayMode: RowiDisplayMode = .mulakhosh {
        didSet {
            #if os(iOS)
            updateRowiContent()
            #endif
        }
    }
    var rowiContentText: AttributedString = .init("")
    var state: ViewModelState = .loading
    var isSearching: Bool = false
    var isPaused: Bool = false
    var sidebarTarjamahList: [TarjamahResult] = []
    var searchTarjamahList: [TarjamahResult] = []

    /// Teks search dengan debounce — dipakai iOS via .searchable binding.
    var searchText: String = "" {
        didSet {
            guard oldValue != searchText else { return }
            searchSubject.send(searchText)
        }
    }

    private(set) var lastSearchQuery: String = ""

    // MARK: - macOS Callbacks (AppKit binding)

    #if os(macOS)
    /// Dipanggil saat content teks rowi berubah.
    var onRowiContentUpdated: ((AttributedString) -> Void)?
    /// Dipanggil saat setiap batch hasil search selesai diappend.
    /// Parameter: (startIndex, count) untuk insertRows animasi.
    var onSearchBatchAppended: ((_ startIndex: Int, _ count: Int) -> Void)?
    /// Dipanggil saat search selesai / dihentikan.
    var onSearchComplete: (() -> Void)?
    /// Dipanggil saat sidebar tarjamah selesai di-load (setelah pilih rowi).
    var onSidebarTarjamahLoaded: (([TarjamahResult]) -> Void)?
    /// Dipanggil saat currentRowi berubah.
    var onCurrentRowiChanged: ((Rowi?) -> Void)?
    #endif

    // MARK: - Computed

    var nullText: String {
        "・・・"
    }

    var windowTitle: String {
        "رواة التهذيبين"
    }

    // MARK: - Private

    private let renderer = ArabicTextRenderer()
    private let dataManager: RowiDataManager = .shared
    private let tarjamahManager: TarjamahGlobalManager = .shared
    private let pauseController: PauseController = .init()
    private var searchTask: Task<Void, Never>?
    private var isStopped: Bool = false
    private let searchSubject = PassthroughSubject<String, Never>()

    // MARK: - Init

    override init() {
        super.init()
        setupSearchDebounce()
        #if os(iOS)
        setupNotifications()
        #endif
    }

    private func setupSearchDebounce() {
        searchSubject
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self else { return }
                lastSearchQuery = query
                searchRowis(query: query)
            }
            .store(in: &cancellables)
    }

    #if os(iOS)
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .didChangeHarakat)
            .sink { [weak self] _ in self?.updateRowiContent() }
            .store(in: &cancellables)
    }
    #endif

    // MARK: - Data

    @MainActor
    func loadData() async {
        defer { state = .loaded }
        guard tabaqaGroups.isEmpty else { return }
        async let booksData: () = LibraryDataManager.shared.loadData()
        async let rowiData: () = dataManager.loadData()
        _ = await (rowiData, booksData)
        tabaqaGroups = dataManager.tabaqaGroups
    }

    func searchRowis(query: String) {
        dataManager.searchRowis(query: query)
        tabaqaGroups = dataManager.tabaqaGroups
    }

    func loadMore(group: TabaqaGroup, completion: @escaping (Int?) -> Void) {
        dataManager.loadMore(group, completion: completion)
    }

    // MARK: - Rowi Selection

    /// Pilih rowi baru — triggers content update + sidebar tarjamah load.
    func selectRowi(_ rowi: Rowi) {
        guard currentRowi?.id != rowi.id else { return }
        currentRowi = rowi
        dataManager.loadRowiData(rowi)
        updateRowiContent()
        #if os(macOS)
        onCurrentRowiChanged?(rowi)
        #endif
        loadSidebarTarjamah(for: rowi)
    }

    /// Set display mode dan update content.
    func setDisplayMode(_ mode: RowiDisplayMode) {
        displayMode = mode
        updateRowiContent()
    }

    func setDisplayModeFromSegment(_ segmentIndex: Int) {
        guard let mode = RowiDisplayMode(rawValue: segmentIndex) else { return }
        setDisplayMode(mode)
    }

    // MARK: - Reset

    func reset() {
        currentRowi = nil
        sidebarTarjamahList.removeAll()
        searchTarjamahList.removeAll()
        stopSearch()
        #if os(macOS)
        rowiContentText = .init("")
        onCurrentRowiChanged?(nil)
        #elseif os(iOS)
        rowiContentText = ""
        #endif
    }

    // Restore state tanpa trigger side-effects (tarjamah load, callback).

    func restoreTarjamahLists(sidebar: [TarjamahResult], search: [TarjamahResult]) {
        sidebarTarjamahList = sidebar
        searchTarjamahList = search
    }

    // MARK: - Sidebar Tarjamah

    private func loadSidebarTarjamah(for rowi: Rowi) {
        Task.detached { [weak self] in
            guard let self else { return }
            let list = await TarjamahGlobalManager.shared.loadAllTarjamahContent(forRowa: rowi.id)
            await MainActor.run {
                self.sidebarTarjamahList = list
                #if os(macOS)
                self.onSidebarTarjamahLoaded?(list)
                #endif
            }
        }
    }

    // MARK: - Full-Text Search

    func startSearch(query: String) {
        guard !query.isEmpty else { return }
        isSearching = true
        isPaused = false
        isStopped = false
        searchTarjamahList.removeAll()

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            await tarjamahManager.searchTarjamah(
                query: query,
                limit: 100,
                pauseController: pauseController,
                stopFlag: { [weak self] in self?.isStopped ?? true },
                onBatchResult: { [weak self] newBatch in
                    guard let self else { return }

                    var resultsBatch = [TarjamahResult]()
                    await tarjamahManager.loadMultipleTarjamahContent(
                        newBatch,
                        pauseController: pauseController
                    ) { [weak self] in
                        self?.isStopped ?? true
                    } onBatchResult: { loadedResults in
                        resultsBatch.append(contentsOf: loadedResults)
                    } onProgress: { _, _ in }

                    await MainActor.run { [weak self, resultsBatch] in
                        guard let self else { return }
                        let startIndex = searchTarjamahList.count
                        searchTarjamahList.append(contentsOf: resultsBatch)
                        #if os(macOS)
                        onSearchBatchAppended?(startIndex, resultsBatch.count)
                        #endif
                    }
                },
                onComplete: { [weak self] in
                    Task { @MainActor in
                        self?.stopSearch()
                        #if os(macOS)
                        self?.onSearchComplete?()
                        #endif
                    }
                }
            )
        }
    }

    func pauseSearch() {
        pauseController.pause()
        isPaused = true
    }

    func resumeSearch() {
        pauseController.resume()
        isPaused = false
    }

    func stopSearch() {
        isStopped = true
        isSearching = false
        isPaused = false
        searchTask?.cancel()
        searchTask = nil
        pauseController.resume()
    }

    // MARK: - Content Rendering

    private func updateRowiContent() {
        guard let rowi = currentRowi else {
            #if os(macOS)
            rowiContentText = .init("")
            onRowiContentUpdated?(.init(""))
            #elseif os(iOS)
            rowiContentText = ""
            #endif
            return
        }

        switch displayMode {
        case .tilmidz: renderContent(rowi.telmez ?? nullText, for: rowi)
        case .syaikh: renderContent(rowi.sheok ?? nullText, for: rowi)
        case .takdil: renderContent(rowi.aqual ?? nullText, for: rowi)
        case .mulakhosh: renderMulakhosh(for: rowi)
        }
    }

    // MARK: - Shared

    private func renderContent(_ text: String, for rowi: Rowi) {
        let result = renderAttributed(text)
        finalizeRender(for: result)
    }

    private func mulakhoshFields(for rowi: Rowi) -> [(label: String, value: String?)] {
        [
            ("الإسم: ", rowi.name),
            ("الطبقة: ", rowi.tabaqa?.convertedTabaqa()),
            ("الولادة: ", rowi.wulida),
            ("الوفاة: ", rowi.tuwuffi),
            ("رُوي له: ", rowi.who),
            ("رتبة عند ابن حجر: ", rowi.rotba),
            ("رتبة عند الذهبي: ", rowi.rZahbi),
        ]
    }

    private func renderMulakhosh(for rowi: Rowi) {
        var result = AttributedString()

        for (label, value) in mulakhoshFields(for: rowi) {
            guard let value, !value.isEmpty else { continue }
            var labelAttr = AttributedString(label)
            #if os(macOS)
            var container = AttributeContainer(TextViewState.shared.boldAttributes)
            container.appKit.foregroundColor = .header
            labelAttr.mergeAttributes(container)
            #elseif os(iOS)
            labelAttr.foregroundColor = .header
            #endif
            result.append(labelAttr)
            result.append(renderAttributed(value))
            result.append(AttributedString("\n"))
        }

        // Hapus trailing newline
        if result.characters.last == "\n" {
            result.removeSubrange(result.characters.index(before: result.endIndex)...)
        }

        finalizeRender(for: result)
    }

    func renderAttributed(_ text: String) -> AttributedString {
        let state = TextViewState.shared
        let attributed = renderer.render(
            text: text,
            highlightColor: PlatformColor.header,
            showHarakat: state.showHarakat,
            isMultiLanguage: false
        )

        #if os(macOS)
        return (try? AttributedString(attributed.attributedString, including: \.appKit)) ?? AttributedString(text)
        #else
        return (try? AttributedString(attributed.attributedString, including: \.uiKit)) ?? AttributedString(text)
        #endif
    }

    private func finalizeRender(for result: AttributedString) {
        #if os(macOS)
        onRowiContentUpdated?(result)
        #endif
        rowiContentText = result
    }
}

// MARK: - AuthorViewModel Restoration

extension NarratorViewModel {
    /// Memulihkan status pencarian perawi (Rowi) dari `ReaderState` ke dalam properti ViewModel.
    /// - Parameter state: Objek `ReaderState` yang menyimpan status pencarian tokoh/perawi.
    func restore(from state: ReaderState) {
        if let savedRowi = state.currentRowi {
            currentRowi = savedRowi
            dataManager.loadRowiData(savedRowi)
            updateRowiContent()
        }

        if let savedAuthorQuery = state.authorSearchQuery {
            searchText = savedAuthorQuery
        }
    }

    /// Menyimpan status tokoh/perawi ke dalam referensi `ReaderState`.
    /// - Parameter state: Referensi inout `ReaderState` yang akan diperbarui.
    func updateState(_ state: inout ReaderState) {
        state.currentRowi = currentRowi
        state.authorSearchQuery = searchText
    }

    /// Membersihkan state data tokoh/perawi di dalam ViewModel.
    func cleanUpState() {
        reset()
        currentRowi = nil
        searchText = ""
        rowiContentText = .init("")
    }
}
