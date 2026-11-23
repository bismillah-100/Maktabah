# Database & Persistensi Katalog

Modul Library mengandalkan **`LibraryDataManager`** sebagai lapisan akses data utama (*Data Access Layer*) untuk mengambil struktur katalog (kategori, pengarang, dan kitab). Namun, `LibraryDataManager` memiliki ketergantungan erat dengan **`DatabaseManager`** pada level *Core*.

---

## Ketergantungan Erat LibraryDataManager dan DatabaseManager

`LibraryDataManager` bertindak sebagai *repository* yang menyediakan fungsi pembacaan data (*read-only*) untuk UI dan ViewModel, sedangkan eksekusi kuerinya didelegasikan secara penuh ke koneksi yang dikelola oleh `DatabaseManager.shared`.

### Peran DatabaseManager
`DatabaseManager` merupakan komponen inti (*Core*) yang mengelola siklus hidup koneksi SQLite terhadap basis data korpus utama:

- `main.sqlite`: Menyimpan katalog buku, kategori, dan metadata inti.
- `special.sqlite`: Menyimpan data sekunder seperti daftar pengarang (*muallif*) dan singkatan.

Koneksi-koneksi ini dilindungi di dalam `DatabaseManager` untuk menjamin keamanan konkurensi (*thread-safe*) dan mencegah akses bersamaan yang berpotensi memicu *database lock*.

### Alur Eksekusi
Setiap kali `LibraryDataManager` perlu memuat atau menyegarkan (*refresh*) data katalog dari disk, komponen ini menggunakan *instance* `SQLiteDatabase` aktif dari `DatabaseManager`:

```mermaid
flowchart TD
    VM["LibraryViewModel"] -->|"Panggil loadData()"| LDM["LibraryDataManager"]
    
    subgraph Core ["Core Persistence"]
        DBM["DatabaseManager.shared"]
        SQL_Main[("main.sqlite<br/>(Katalog & Kategori)")]
        SQL_Special[("special.sqlite<br/>(Pengarang & Singkatan)")]
    end
    
    LDM -.->|"Minta Koneksi DB"| DBM
    DBM -->|"Eksekusi Query"| SQL_Main
    DBM -->|"Eksekusi Query"| SQL_Special
    
    LDM -->|"Return Models (BooksData, CategoryData)"| VM

    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;

    class VM vm;
    class LDM,DBM store;
    class SQL_Main,SQL_Special db;
```

### Mutex & Thread-Safety di LibraryDataManager
Karena data katalog sering diakses dari berbagai *thread* (misalnya dari UI saat *scrolling*, dari *Search Engine* untuk pencarian judul buku, atau saat sinkronisasi data), `LibraryDataManager` menyembunyikan *state cache in-memory* internalnya di balik proteksi `Mutex` untuk pencarian $O(1)$ yang *thread-safe*.

```swift
private struct LibraryDataState: Sendable {
    var rawCategories: [CategoryData] = []
    var rawAuthors: [Muallif] = []
    var rawBooks: [BooksData] = []
    
    // ... indeks cache untuk O(1) lookup
}

private let state = Mutex(LibraryDataState())
```

Dengan pola pemisahan ini:

1. **`DatabaseManager`** bertanggung jawab penuh atas manajemen I/O disk (pembacaan berkas SQLite yang *thread-safe*).
2. **`LibraryDataManager`** bertanggung jawab atas struktur data dan I/O memori (*caching* model data di RAM yang *thread-safe* via Mutex).

Integrasi dan pemisahan tanggung jawab ini memastikan Maktabah dapat me-*render* ribuan buku, memfilter katalog, dan mencari metadata secara cepat tanpa membebani memori maupun operasi I/O disk secara repetitif.

---

## Klasifikasi & Penghapusan Buku Non-Katalog (Bundle Mode vs Full Mode)

Untuk membedakan kitab katalog inti dari kitab tambahan (hasil **Import Manual** maupun **Pembaruan Buku**) tanpa tabel pelacak ekstra maupun batas ID *hardcoded*, `LibraryDataManager` menerapkan strategi dua mode berdasarkan `AppConfig.isUsingBundleMode`:

- **Bundle Mode (`true`)**: Menggunakan *cache* `coreIndexIds` (`Mutex<(books: Set<Int>, authors: Set<Int>)?>`) pada `BookDownloadIndexCache` yang diisi otomatis saat `index.json` dimuat (`bkid` dan `authno`), bersifat *fail-closed* bila belum tersedia.
- **Full Library Mode (`false`, 100% offline)**: Menggunakan kolom bawaan Shamela `oNum` pada tabel `0bok` (`BooksData.oNum != nil` menandakan kitab katalog inti) dan `Auth.oNum IS NULL` + pengecekan `!isAuthorUsed` untuk membersihkan pengarang yatim di `special.sqlite`.

```mermaid
flowchart TD
    Check["LibraryDataManager.isCoreBook(id:) / shouldRemoveAuthor(muallifId:)"] --> Mode{"AppConfig.isUsingBundleMode?"}
    Mode -->|"true (Bundle Mode)"| Index["BookDownloadIndexCache<br/>coreIndexIds (index.json: bkid + authno)"]
    Mode -->|"false (Full Mode - Offline)"| SQLite["0bok.oNum != nil (BooksData in-memory)<br/>Auth.oNum IS NULL (special.sqlite)"]
    Index --> Actions["Import Form Validation · Context Menu · Bulk Selection · Delete Alert"]
    SQLite --> Actions
    Actions --> Remove["BookArchiveIntegrator.executeBookRemoval<br/>Capture flags sebelum delete SQLite → drop b/t/fts → hapus 0bok & Auth yatim → update memori"]
```
