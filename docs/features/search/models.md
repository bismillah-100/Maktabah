# Data Models & State Types

Modul Search menggunakan beberapa model data untuk merepresentasikan item hasil pencarian dan mengelola fitur utilitas seperti penyalinan (*copy*) ke *clipboard* serta pengurutan data.

## Model Struktur Data

### SearchResultItem (Struct)

*Struct* data utama yang mewakili satu baris hasil pencarian tunggal. Mendukung `Codable`, `Hashable`, dan `Sendable` untuk memastikan *thread-safety* saat dieksekusi secara asinkron.

```swift
struct SearchResultItem: Codable, CopyableResult, Hashable, Sendable {
    let archive: String
    let tableName: String
    let bookId: Int
    let bookTitle: String
    let page: Int
    let part: Int
    nonisolated(unsafe) let attributedText: NSAttributedString
}
```

!!! note
    Properti `attributedText` ditandai dengan `nonisolated(unsafe)` karena bertipe `NSAttributedString` (tipe referensi Foundation) yang tidak mengadopsi `Sendable` secara murni, namun dipastikan aman dikonsumsi dari lapisan presentasi.

### SearchSortKey (Enum)

*Enum* yang merepresentasikan kunci parameter saat melakukan pengurutan hasil pencarian.

*   `bookTitle`: Urut berdasarkan abjad nama kitab.
*   `page`: Urut berdasarkan nomor halaman.
*   `part`: Urut berdasarkan nomor juz/bagian.
*   `content`: Urut berdasarkan urutan teks (*content*).

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
