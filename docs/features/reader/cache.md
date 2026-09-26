## Gambaran Umum (Overview)

`BookPageCache` adalah mekanisme *in-memory cache* berbasis pola *Singleton* yang bertugas menampung objek `BookContent` (teks buku yang telah didekompresi dan siap di-*render*) serta objek teks yang telah diproses `ProcessedArabicContent`. Komponen ini memanfaatkan `NSCache` bawaan sistem operasi yang secara implisit mengelola kebijakan pengosongan (*eviction*) berdasarkan alokasi memori dan batas jumlah objek, sehingga meminimalkan siklus I/O pembacaan berulang ke *database* SQLite.

## Spesifikasi Teknis & Parameter (Technical Specifications)

| Komponen / Parameter | Tipe | Nilai Default | Deskripsi |
| :--- | :--- | :--- | :--- |
| `cache` | `NSCache` | 2000 *count* | Menampung `BookContent` dengan *key* berbasis ID buku. |
| `processedCache` | `NSCache` | 2000 *count* | Menampung `ProcessedArabicContent` berdasarkan kombinasi konfigurasi visual (harakat, dll.). |
| `lock` | `Mutex<Void>` | `Mutex(())` | Primitif sinkronisasi modern dari framework `Synchronization` untuk mengamankan pembacaan dan mutasi cache secara thread-safe lintas thread. |

## Alur Implementasi & Contoh Kode (Implementation)

Untuk mengoptimalkan pengelompokan memori per buku, `BookPageCache` memetakan ID buku (`NSNumber`) sebagai kunci utama yang mereferensikan sebuah `NSMutableDictionary`. *Dictionary* tersebut kemudian memetakan ID halaman ke *instance*-nya masing-masing. Seluruh fungsi pembacaan dan penulisan diamankan oleh `Mutex` dengan blok `withLock`.

```swift
import Foundation
import Synchronization

final class BookPageCache: @unchecked Sendable {
    static let shared = BookPageCache()

    // Key: bookId (NSNumber) -> Value: Map of pages (NSMutableDictionary)
    private let cache = NSCache<NSNumber, NSMutableDictionary>()
    private let processedCache = NSCache<NSNumber, NSMutableDictionary>()
    private let lock = Mutex<Void>(())

    private init() {
        cache.countLimit = 2000     // Batas total entri cache
        cache.totalCostLimit = 50 * 1024 * 1024 // Batas 50 MB memori (opsional)
    }

    func get(bookId: Int, contentId: Int) -> BookContent? {
        lock.withLock { _ in
            let bookKey = bookId as NSNumber
            let pages = cache.object(forKey: bookKey)
            return pages?[contentId as NSNumber] as? BookContent
        }
    }

    func set(bookId: Int, content: BookContent) {
        lock.withLock { _ in
            let bookKey = bookId as NSNumber
            let pages = cache.object(forKey: bookKey) ?? NSMutableDictionary()

            pages[content.id as NSNumber] = content
            cache.setObject(pages, forKey: bookKey)
        }
    }
}
```

## Penanganan Edge Cases & Batasan (Edge Cases & Limitations)

- **Batasan Skalabilitas Dictionary**: Penyimpanan objek secara hierarkis menggunakan `NSMutableDictionary` di dalam `NSCache` dapat memengaruhi kebijakan *eviction* sistem operasi, karena OS hanya mengenali satu objek `NSMutableDictionary` sebagai *value*, tanpa menghitung jumlah sub-elemen halaman secara individual. Apabila batas memori (`50MB`) tercapai, seluruh koleksi halaman dalam satu buku akan terhapus sekaligus dari *cache*.
