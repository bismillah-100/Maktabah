# Contracts & Loose Coupling

Dokumentasi ini menjelaskan antarmuka abstraksi dan *protocol* komunikasi yang didefinisikan pada direktori `Source/Features/Bookmarks/Protocols/`.

---

## 1. ResultsDelegate (Protocol)

*Protocol* utama yang menjembatani interaksi antara antarmuka markah hasil pencarian dengan modul pencarian (*Search Feature*) dan pembaca (*Reader Feature*).

```swift
import Foundation

@MainActor
protocol ResultsDelegate: AnyObject {
    /// Dipanggil saat pengguna memilih atau mengeklik ganda suatu node hasil pencarian tersimpan.
    ///
    /// - Parameter savedResults: Koleksi item hasil pencarian yang dikandung oleh node terpilih.
    func didSelect(savedResults: [SavedResultsItem])
}
```

---

## 2. Bedah Spesifikasi Kontrak

| Komponen | Spesifikasi | Keterangan |
| :--- | :--- | :--- |
| **Anotasi Konkurensi** | `@MainActor` | Menjamin metode delegasi selalu dieksekusi di antrean utama (*main thread*), mencegah potensi *race condition* saat memodifikasi UI antarmuka pencarian. |
| **Batasan Tipe** | `AnyObject` | Membatasi konformitas hanya pada tipe referensi (*class-only protocol*). Hal ini memungkinkan properti delegasi disimpan sebagai `weak var delegate: ResultsDelegate?` guna mencegah *retain cycle* (kebocoran memori). |
| **Parameter** | `savedResults: [SavedResultsItem]` | Berisi daftar lengkap seluruh kecocokan (nomor arsip, ID kitab, kueri asli, judul kitab, dan mode pencarian) yang tersimpan dalam markah tersebut. |
| **Nilai Kembalian** | `Void` | Operasi bersifat *fire-and-forget* dari sudut pandang pemanggil. |

---

## 3. Alur Kerja Sistem & Titik Panggilan (*Invocation Points*)

```mermaid
flowchart TD
    ACT(["Pengguna Klik Ganda Baris Markah"]) --> OV["NSOutlineView (macOS) / iOSFolderContentList (iOS)"]
    OV --> RVM["ResultsViewManager / ResultsViewModel"]
    
    RVM ~~~ DEL
    
    DEL["ResultsDelegate (Protocol Abstrak)"]
    RVM -->|"didSelect(savedResults:)"| DEL
    
    DEL ~~~ SEARCH
    
    SEARCH["OptionSearchVC (Search Feature) / iOSNavigationManager"]
    DEL -->|"Implementasi Kontrak"| SEARCH
    
    SEARCH --> DISMISS(["Tutup Sheet / Popover"])
    SEARCH --> SE["SearchEngine (Muat Hasil Tersimpan)"]

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class ACT,DISMISS event;
    class OV,SEARCH ui;
    class RVM,DEL,SE store;
```

```mermaid
sequenceDiagram
    participant User as Pengguna
    participant Outline as NSOutlineView (macOS)
    participant RVM as ResultsViewManager
    participant Del as OptionSearchVC (Search Feature)
    participant SearchEngine as Search Engine Worker

    User->>Outline: Klik Ganda pada Baris Hasil
    Outline->>RVM: onDoubleClick()
    activate RVM
    RVM->>RVM: Validasi item as ResultNode
    RVM->>Del: delegate?.didSelect(savedResults: result.items)
    deactivate RVM
    activate Del
    Del->>Del: dismissSavedResultsPopover()
    Del->>SearchEngine: Injeksi daftar kueri & tampilkan hasil
    deactivate Del
```

### Integrasi Lintas Modul

=== "macOS (`OptionSearchVC`)"
    Pada lingkungan macOS, kontroler `OptionSearchVC` (bagian dari `Source/Features/Search/macOS/`) mengadopsi *protocol* ini:

    ```swift
    extension OptionSearchVC: ResultsDelegate {
        func didSelect(savedResults: [SavedResultsItem]) {
            // 1. Tutup popover / sheet daftar bookmark
            dismissBookmarkSheet()
            
            // 2. Muat hasil pencarian yang tersimpan ke dalam tabel hasil aktif
            searchViewModel.loadSavedResults(savedResults)
        }
    }
    ```

=== "iOS (`iOSNavigationManager`)"
    Pada platform iOS, delegasi dilakukan secara langsung melalui *Environment Object* `iOSNavigationManager` di dalam *closure* `loadResult`:

    ```swift
    private func loadResult(_ resultNode: ResultNode) {
        dismiss()
        navigationManager.searchViewModel.loadSavedResults(resultNode.items)
    }
    ```

---

## 4. Keuntungan Loose Coupling

Dengan menggunakan *protocol* `ResultsDelegate`:

*   **Pelepasan Keterikatan (*Decoupling*)**: Modul Bookmarks sama sekali tidak perlu mengetahui *class* konkret dari kontroler yang membukanya (`OptionSearchVC`, `SplitVC`, atau komponen navigasi lainnya).
*   **Kemudahan Pengujian (*Testability*)**: Implementasi *Mock Delegate* dapat diinjeksikan dalam *unit test* untuk memverifikasi apakah interaksi pada `ResultsViewManager` memicu pengiriman data `[SavedResultsItem]` yang akurat.
