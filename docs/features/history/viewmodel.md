# State Management (ViewModel)

Manajemen state untuk modul History dikendalikan oleh kelas tunggal `HistoryViewModel`. Komponen ini bertindak sebagai perantara (_middleman_) antara lapisan persisten (`HistoryDatabaseManager`), lapisan sinkronisasi (`CloudKitSyncManager`), dan UI yang reaktif (baik SwiftUI di iOS maupun NSCollectionView di macOS).

## `HistoryViewModel`

Berlokasi di `Source/Features/History/ViewModel/HistoryViewModel.swift`, *view model* ini menggunakan framework `Observation` (makro `@Observable`) bawaan Swift 5.9+, bukan lagi memakai `@Published` milik `Combine`.

```swift
@Observable
class HistoryViewModel: ViewModelBase {
    static let shared = HistoryViewModel()

    var entriesByBookId: [Int: ReadingEntry] = [:]
    var historyOrder: [Int] = []

    var historyBooks: [BooksData] = []
    var favoriteBooks: [BooksData] = []
    var searchText: String = ""
    
    // ... logic methods
}
```

### Properti Utama (*State*)

* `entriesByBookId`: Dictionary utama yang memetakan ID buku (Integer) ke tipe model `ReadingEntry`.
* `historyOrder`: *Array of Integers* yang menjaga urutan linear buku yang terakhir dibaca secara kronologis. Dibatasi secara eksplisit (maksimal 50 buku melalui konstanta `maxHistoryCount`).
* `historyBooks` & `favoriteBooks`: Array ini menampung `BooksData` aktual yang sudah *di-join* dari `DatabaseManager`. UI terikat (di-*bind*) langsung ke properti ini untuk me-render cover atau judul.
* `searchText`: Digunakan oleh *Search Bar* (khusus iOS/iPadOS) untuk memfilter koleksi favorit atau history secara lokal di sisi klien.

### Concurrency & Debouncing

Agar tidak menghabiskan thread utama (UI thread) saat operasi masif terjadi (seperti saat sinkronisasi CloudKit menarik ratusan rekaman modifikasi sekaligus), VM ini menggunakan `Task` asinkronus (Concurrency) yang dibatalkan (_cancelled_) jika *event* yang sama terjadi berurutan dalam periode singkat:

1. **`scheduleSave()`**  
   Melakukan *debouncing* selama 500 ms sebelum menulis modifikasi array `historyOrder` ke SQLite. Dijalankan dengan `Task.detached`.
   
2. **`scheduleReloadBooksData()`**  
   Melakukan *debouncing* 150 ms setiap ada perintah *reload UI*. Perintah ini akan menarik ulang `BooksData` berdasarkan `entriesByBookId` terbaru. Menggunakan `@MainActor` guna memastikan modifikasi referensi koleksi berjalan aman bagi SwiftUI/AppKit.

### Ekstensi Organisasional (Separation of Concerns)

Untuk menghindari file masif (*God-Object*), logika dari `HistoryViewModel` dipecah ke dalam beberapa file ekstensi:

#### 1. `History+Core.swift`
Menangani operasi sentral CRUD aplikasi.

* `addBookToHistory(_:)`: Menginisiasi record baru dan menggeser/menyisipkan buku ke `historyOrder` teratas. Menghapus ekor array jika panjangnya melebihi `maxHistoryCount` (50).
* `updateLastContentId(_:for:)`: Secara konstan diperbarui ketika pengguna menelusuri halaman buku. Metode ini memotong jalur (*bypass*) *reload UI library* sepenuhnya agar tidak membebani komputasi visual yang sedang terjadi (mengganti bendera `reloadUI` ke `false`).
* `toggleFavorite(_:)`: Membalik penanda `isFavorite` dan mencatat `favoritedAt` dengan tanggal masa kini.

#### 2. `History+Database.swift`
Menjembatani transisi pertukaran format data.

* `loadFromDatabase()`: Menarik seluruh tabel mentah dari `HistoryDatabaseManager` ke memori (`entriesByBookId` dan `historyOrder`).

#### 3. `History+CloudKit.swift`
Menangani resolusi konflik sinkronisasi.

* `applyCloudKitChanges(entriesToSave:recordIdsToDelete:)`: Fungsi *hook* yang dipanggil oleh delegasi sinkronisasi CloudKit. Mengeksekusi mutasi memori (*in-memory mutation*) untuk pembaruan (upsert) maupun penghapusan sepihak (deletion).

#### 4. `History+Migration.swift`
Skrip *legacy* sekali-jalan (One-off).

* `backfillCloudKitFieldsIfNeeded()`: Fungsi migrasi yang dipanggil saat instalasi. Menormalkan ID CloudKit (*ckRecordId*) yang lampau (dulu memakai prefix `"history_xxx"`) dan dipaksa seragam menggunakan format integer dasar menjadi ID (*ckRecordId* = ID buku).
