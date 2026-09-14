# LibraryViewModel, State & Combine Architecture

Sumber kode:

* `Source/Features/Library/ViewModel/LibraryViewModel.swift`
* `Source/Features/Library/ViewModel/Extensions/`
    * `ObserversLibrary.swift`
    * `FilterLibrary.swift`
    * `PaginationLibrary.swift`
    * `SelectionLibrary.swift`
    * `BulkActionLibrary.swift`

---

## 1. Arsitektur State `@Observable`

`LibraryViewModel` mengadopsi kerangka kerja observasi modern Swift (`@Observable`) dan mengimplementasikan protokol `ViewModelBase`. ViewModel ini bertindak sebagai koordinator state terpusat untuk katalog kitab di kedua platform.

```swift
@Observable
final class LibraryViewModel: ViewModelBase {
    // Singletons
    let dataManager: LibraryDataManager = .shared
    let historyManager: HistoryViewModel = .shared

    // State Display
    var displayedCategories: [CategoryData] = []
    var rootCategories: [CategoryData] = []
    var filterMode: LibraryFilterMode = .all
    var viewMode: LibraryViewMode = .category      // .category vs .author
    var showOnlyDownloaded: Bool = false
    var searchQuery: String = ""

    // Multi-Selection & Bulk Operations
    var selectedBookIds: Set<Int> = []
    var isSelectionMode = false
    var isBulkDownloading = false
    var availableUpdateCount: Int = 0

    // Lifecycle State
    var state: ViewModelState = .loading
    let reloadTask = Mutex<Task<Void, Never>?>(nil)
}
```

---

## 2. Event Streaming & Notifikasi Combine

Pengamatan mutasi sistem dikelola secara terpisah di `ObserversLibrary.swift` untuk menjaga prinsip *Single Responsibility*:

```text
[ NotificationCenter / Background Events ]
             │
             ├── .libraryFolderChanged ────────► Reload Library Task (Mutex Protected)
             │
             ├── .bookIntegrated (iOS) ────────► Update Displayed Categories
             │
             ├── .booksChanged ────────────────► Refresh Categories & Trigger Update Check
             │
             └── refreshSubject (Combine) ─────► Debounce 300ms ──► Apply Filter
```

### A. Debounced Streams (`refreshSubject`)
Saat katalog dimutasi beruntun (misalnya pengunduhan batch banyak kitab), event dipancarkan ke `refreshSubject` dan di-*debounce* selama 300 milidetik pada `RunLoop.main` sebelum memicu pembangunan ulang hierarki kategori:

```swift
refreshSubject
    .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
    .sink { [weak self] in
        MainActor.assumeIsolated { [weak self] in
            guard let self else { return }
            rootCategories = Array(dataManager.allRootCategories)
            if viewMode == .author {
                _authorHierarchy = dataManager.buildAuthorHierarchy()
            }
            applyFilter(filterMode)
        }
    }
    .store(in: &cancellables)
```

### B. Proteksi Konkurensi Reload Task (`Mutex`)
Saat pengguna mengubah folder perpustakaan (`.libraryFolderChanged`), mutasi state dilindungi oleh `Mutex<Task<Void, Never>?>`:

```swift
reloadTask.withLock { currentTask in
    if currentTask == nil {
        currentTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await refreshLibrary()
            reloadTask.withLock { $0 = nil }
        }
    }
}
```
Pola ini mencegah beberapa reload task saling bertabrakan saat event folder didispatch berulang kali.

---

## 3. Fitur View-Model Extensions

Untuk menjaga keterbacaan, fungsionalitas `LibraryViewModel` dipecah menjadi modul extension:

* **`FilterLibrary.swift`**: Menangani logika filter pencarian kitab (`searchQuery`), penyaringan kitab yang telah diunduh (`showOnlyDownloaded`), dan mode tampilan (`.category` vs `.author`). Pencarian teks memanfaatkan debounce task 300ms untuk membatalkan kueri lama saat pengguna masih mengetik.
* **`PaginationLibrary.swift`**: Mengatur lazy loading dan batching item pada mode daftar pengarang (*Author Hierarchy*) untuk mencegah lag memori pada ribuan pengarang.
* **`SelectionLibrary.swift`**: Menyimpan dan memvalidasi `Set<Int>` ID buku yang dipilih pengguna untuk operasi multi-seleksi.
* **`BulkActionLibrary.swift`**: Mengkoordinasikan penghapusan massal (*bulk deletion*), pengunduhan massal (*bulk download*), serta pembaruan katalog massal.
