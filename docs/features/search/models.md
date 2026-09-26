# Data Models & State Types

Modul Search menggunakan beberapa model data untuk merepresentasikan item hasil pencarian, penampung kecocokan indeks mentah (*hits*), dan utilitas penyalinan (*copy*) maupun pengurutan data.

## Model Struktur Data

### SearchHit (Struct)

*Struct* ringan yang merepresentasikan satu baris hasil kecocokan indeks FTS mentah sebelum diuraikan konten teksnya:

```swift
struct SearchHit: Sendable, Identifiable, Hashable {
    let archive: String
    let tableName: String
    let rowId: Int
    let page: Int
    let part: Int

    var id: String { "\(archive)_\(tableName)_\(rowId)" }
}
```

- **`archive`**: ID berkas arsip (misalnya `"1"`).
- **`tableName`**: Nama tabel kitab (misalnya `"b1442"`).
- **`rowId`**: ID baris halaman di dalam tabel kitab (32-bit bawah dari `packedRowId`).
- **`page` & `part`**: Metadata posisi halaman dan juz.

---

### SearchResultItem (Struct)

*Struct* data utama hasil pencarian yang dikonsumsi oleh lapisan presentasi (UI). Mengadopsi arsitektur resolusi *lazy snippet* untuk menghemat memori saat ribuan hasil pencarian ditemukan:

```swift
struct SearchResultItem: Codable, CopyableResult, Hashable, Sendable, Identifiable {
    let archive: String
    let tableName: String
    let bookId: Int
    let bookTitle: String
    let page: Int
    let part: Int
    private nonisolated(unsafe) let rawAttributedText: NSAttributedString?

    var attributedText: NSAttributedString {
        rawAttributedText ?? NSAttributedString(string: "")
    }

    var hasResolvedSnippet: Bool {
        rawAttributedText != nil
    }

    var id: String { "\(archive)_\(tableName)_\(bookId)" }
    var uniqueId: String { id }
}
```

!!! note "Lazy Snippet & Deep Immutability"
    Properti `rawAttributedText` bersifat *immutable* (`let`) dan bernilai `nil` secara bawaan ketika hasil pencarian dipancarkan dari mesin FTS. Teks berformat `NSAttributedString` baru diurai dan disorot warnanya secara *on-demand* melalui `SearchHitResolver` ketika sel antarmuka pengguna memasuki *viewport* layar. Hal ini menjamin *deep immutability* pada `SearchResultItem` sehingga bebas dari potensi *data race* saat dibagikan lintas aktor/thread.

---

### SearchSortKey (Enum)

*Enum* yang merepresentasikan kunci parameter saat melakukan pengurutan hasil pencarian.

*   `bookTitle`: Urut berdasarkan abjad nama kitab.
*   `page`: Urut berdasarkan nomor halaman.
*   `part`: Urut berdasarkan nomor juz/bagian.

---

## Utilitas (Protocol & Helper)

### CopyableResult (Protocol)

*Protocol* yang menetapkan standar pemformatan *string* ketika pengguna menyalin (*copy*) hasil pencarian ke dalam *clipboard*. *Protocol* ini secara otomatis merangkai teks kutipan beserta judul kitab, juz, dan nomor halaman dalam format angka Arab.

Terdapat ekstensi pembantu (*helper*) khusus di macOS:

```swift
extension ReusableFunc {
    static func copyResults(
        _ items: [some CopyableResult],
        tableView: NSTableView
    )
}
```

### SearchResultsSorter (Struct)

Modul utilitas dengan metode statis `sort(_:by:ascending:)` untuk menyortir *array* `SearchResultItem` secara dinamis menyesuaikan kriteria yang diteruskan melalui `SearchSortKey`.
