# Data Models & State Types

Bagian ini membedah struktur data utama yang menyokong modul History & Favorites. Keseluruhan modul ini menggunakan `ReadingEntry` sebagai model tunggal (*Single Source of Truth*) yang merepresentasikan metadata interaksi pengguna dengan satu buku.

## ReadingEntry (Struct)

`ReadingEntry` adalah *struct* (*value type*) utama yang menyimpan informasi terkait riwayat dan status favorit dari suatu buku. Berkas ini berlokasi di `Source/Features/History/Models/ReadingEntry.swift`.

```swift
struct ReadingEntry: Codable, Identifiable, Hashable {
    let bookId: Int
    var lastContentId: Int?
    var lastOpenedAt: Date?
    var favoritedAt: Date?
    var positionUpdatedAt: Date?
    var updatedAt: Date
    var isFavorite: Bool

    var ckRecordId: String?

    var id: Int {
        bookId
    }
    
    // ... initializers
}
```

### Penjelasan Properti

| Properti | Tipe | Deskripsi |
| --- | --- | --- |
| `bookId` | `Int` | ID buku yang mengacu ke arsip katalog Maktabah (diambil dari tabel katalog `main.sqlite`). Nilai ini menjadi *Primary Key* di database `History.sqlite`. |
| `lastContentId` | `Int?` | ID paragraf/konten (dari tabel `b{id}`) terakhir yang dibaca pengguna. Nilai ini diperbarui secara *real-time* (melalui *throttling*) saat *scrolling* di Reader. |
| `lastOpenedAt` | `Date?` | Waktu kapan buku terakhir kali dibuka. Digunakan untuk merotasi posisi elemen di komponen *Recent History*. |
| `favoritedAt` | `Date?` | Waktu kapan buku ditambahkan ke favorit. Digunakan sebagai *primary sort key* untuk *Favorites Grid* (LIFO - *Last In First Out*). |
| `positionUpdatedAt` | `Date?` | Waktu terakhir posisi baca (`lastContentId`) disimpan. Mencegah konflik saat penggabungan (*merge*) jika pengguna membaca buku di perangkat yang berbeda pada waktu bersamaan. |
| `updatedAt` | `Date` | Stempel waktu umum kapan *record* ini diperbarui. Penting untuk resolusi konflik CloudKit. |
| `isFavorite` | `Bool` | Penanda *boolean* apakah buku ada dalam daftar favorit. |
| `ckRecordId` | `String?` | ID *record* khusus untuk CloudKit. Sejak pembaruan terbaru (migrasi), ID ini dipaksa sama persis dengan `String(bookId)` untuk menghindari duplikasi rekaman di server. |
| `id` | `Int` | Implementasi dari *protocol* `Identifiable`. Nilainya sama persis dengan `bookId` dan mempermudah diferensiasi tampilan UI via SwiftUI (`ForEach`). |

### Optimasi Khusus

1. **Codable & Hashable**: *Struct* ini mengimplementasikan `Codable` agar kompatibel dengan legacy UserDefaults (jika masih digunakan pada versi lampau) serta konversi mudah ke JSON. `Hashable` membantu SwiftUI menghitung perbedaan (*diffing*) saat menyusun transisi UI (*Grid/List animation*).
2. **Kompak & Ringkas**: Model ini tidak memuat *string* judul atau nama penulis sama sekali. Ini menghemat memori dan I/O *disk*. Untuk mendapatkan *string* metadata buku, lapisan antarmuka akan meminta ViewModel (`HistoryViewModel`) melakukan operasi *join* dengan *cache* dari `DatabaseManager.shared`.

## Konvensi Status (Event Types)

Tidak ada *enum* spesifik yang didaftarkan di folder `Models/`. Notifikasi ke seluruh aplikasi didistribusikan menggunakan ekstensi bawaan `Notification.Name`. Notifikasi yang sering diamati oleh `HistoryViewModel` meliputi:

* `.bookIntegrated` - Dipancarkan ketika sebuah buku selesai diunduh dan didekompresi.
* `.booksChanged` - Dipancarkan saat katalog utama direstrukturisasi.
* `.historyDidChange` - Dipancarkan untuk memberi sinyal pada AppKit/SwiftUI bahwa perlu sinkronisasi antarlayar.
