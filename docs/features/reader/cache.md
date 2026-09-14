## Gambaran Umum (Overview)

`BookPageCache` adalah mekanisme *in-memory* Singleton yang bertugas menampung objek `BookContent` (teks buku yang telah didekompresi dan siap dirender) serta teks yang telah diproses `ProcessedArabicContent`. Komponen ini bertumpu pada `NSCache` OS bawaan yang secara implisit mengelola kebijakan pengusiran (eviction) berdasarkan alokasi memori dan batas jumlah objek, meminimalisasi siklus baca-tulis (I/O) ke database SQLite secara repetitif.

## Spesifikasi Teknis & Parameter (Technical Specifications)

| Komponen / Parameter | Tipe | Default | Deskripsi |
| :--- | :--- | :--- | :--- |
| `cache` | `NSCache` | 2000 count | Menampung `BookContent` dengan key berbasis ID buku. |
| `processedCache` | `NSCache` | 2000 count | Menampung `ProcessedArabicContent` berdasarkan kombinasi *setting* visual (harakat, dll). |
| `lock` | `NSLock` | N/A | Mutex thread-safe untuk mengamankan operasi penambahan/pengambilan. |

## Alur Implementasi & Contoh Kode (Implementation)

Untuk mengoptimalkan pengelompokan memori per buku, `BookPageCache` memetakan ID buku (`NSNumber`) sebagai kunci utama yang mereferensikan sebuah `NSMutableDictionary`. Dictionary tersebut kemudian memetakan ID halaman ke dalam instansinya. Seluruh fungsi pembacaan diamankan oleh `NSLock`.

```swift
final class BookPageCache {
    nonisolated(unsafe) static let shared = BookPageCache()

    private let cache = NSCache<NSNumber, NSMutableDictionary>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 2000     // Batas total instansi cache
        cache.totalCostLimit = 50 * 1024 * 1024 // Batasan 50 MB memori (opsional)
    }

    func get(bookId: Int, contentId: Int) -> BookContent? {
        lock.lock()
        defer { lock.unlock() }

        let bookKey = bookId as NSNumber
        let pages = cache.object(forKey: bookKey)
        return pages?[contentId as NSNumber] as? BookContent
    }

    func set(bookId: Int, content: BookContent) {
        lock.lock()
        defer { lock.unlock() }

        let bookKey = bookId as NSNumber
        let pages = cache.object(forKey: bookKey) ?? NSMutableDictionary()

        pages[content.id as NSNumber] = content
        cache.setObject(pages, forKey: bookKey)
    }
}
```

## Penanganan Eror & Batasan (Edge Cases & Limitations)

- **Batasan Skalabilitas Dictionary**: Penyimpanan objek secara hirarkis menggunakan `NSMutableDictionary` di dalam `NSCache` dapat mengecoh kebijakan *eviction* OS, karena OS hanya melihat satu objek `NSMutableDictionary` sebagai *value*, bukan mengukur jumlah sub-elemen halaman secara parsial. Jika alokasi memory limit (`50MB`) tembus, seluruh koleksi halaman dalam satu buku akan terhapus sekaligus.
