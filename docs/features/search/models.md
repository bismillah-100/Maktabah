# Data Models & State Types

Modul Search menggunakan beberapa model data untuk merepresentasikan item hasil pencarian dan mengelola fitur utilitas seperti penyalinan (copy) ke *clipboard* serta pengurutan data.

## Model Struktur Data

### `SearchResultItem`

Struktur data utama yang mewakili satu baris hasil pencarian tunggal. Mendukung `Codable`, `Hashable`, dan `Sendable` untuk memastikan *thread-safety* saat dieksekusi secara asinkron.

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
    Properti `attributedText` ditandai dengan `nonisolated(unsafe)` karena bertipe `NSAttributedString` (tipe *reference* Foundation) yang tidak konform `Sendable` secara murni, namun dipastikan aman dikonsumsi dari lapis presentasi.

### `SearchSortKey`

Enumerasi yang merepresentasikan kunci parameter saat melakukan sortir hasil pencarian.

*   `bookTitle`: Urut berdasarkan abjad nama kitab.
*   `page`: Urut berdasarkan nomor halaman.
*   `part`: Urut berdasarkan nomor juz/bagian.
*   `content`: Urut berdasarkan rentetan teks (*content*).

## Protokol Utilitas

### `CopyableResult`

Sebuah protokol yang menetapkan standar pemformatan *string* ketika pengguna melakukan operasi salin (*copy*) hasil ke dalam *clipboard*. Secara otomatis merangkai teks pencarian beserta judul kitab, juz, dan halaman dengan penomoran angka Arab.

Terdapat ekstensi bantuan (*helper*) khusus di macOS:

```swift
extension ReusableFunc {
    static func copyResults(
        _ items: [some CopyableResult],
        tableView: NSTableView
    )
}
```

### `SearchResultsSorter`

Modul utilitas dengan metode statis `sort(_:by:ascending:)` untuk menyortir himpunan (*array*) `SearchResultItem` secara dinamis menyesuaikan kriteria yang diteruskan melalui `SearchSortKey`.
