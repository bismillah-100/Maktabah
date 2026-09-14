# Library Data Models & Structures

Sumber kode: `Source/Features/Library/Models/`

---

## 1. Model Katalog Inti

### A. `BooksData` (Class) - `BooksData.swift`
Entitas data representasi kitab di dalam katalog:

```swift
final class BooksData: Codable, Identifiable, @unchecked Sendable {
    let id: Int
    let book: String
    let normalizedBook: String
    let archive: Int
    let muallif: Int
    var catId: Int?
    var downloadFilename: String?
    var compressedDownloadSize: Int64?
    var tafseerNam: String?
    var pdfCs: Int?
    var bithoqoh: String
    var info: String
    var isChecked: Bool
}
```

* **String Interning (`StringInterner.shared.intern`)**: Menghemat jejak memori pada puluhan ribu kitab yang memiliki *string* repetitif.
* **Normalisasi Arab (`normalizedBook`)**: Dihasilkan via `book.normalizeArabic(false)` untuk mempercepat pencarian instan tanpa perlu normalisasi berulang.
* **Tipe Khusus (`pdfCs`)**:
    * `pdfCs == 3`: Menandakan kitab multibahasa (*Multi-Language*).
    * `pdfCs == 4`: Menandakan kitab hasil impor manual pengguna (*Imported Book*).
* **Konversi Angka Arab**: Properti `bithoqoh` (kartu identitas kitab) dan `info` secara otomatis mengonversi angka Latin ke angka Arab (`convertToArabicDigits()`).

---

### B. `CategoryData` (Class) - `CategoryData.swift`
Representasi hierarki kategori bertingkat (*nested category tree*):

```swift
class CategoryData: @unchecked Sendable {
    let id: Int
    let name: String
    let normalizedName: String
    let level: Int
    let order: Int
    var isChecked: Bool
    var children: [Any] = [] // Berisi CategoryData atau BooksData
}
```

* **Struktur Heterogen**: Properti `children` dapat menampung sub-kategori (`CategoryData`) maupun buku (`BooksData`).
* **Pengumpulan Rekursif**: Menyediakan fungsi `allBooks` dan `allSubcategories` yang menjelajahi seluruh turunan hierarki secara rekursif.

---

### C. `Muallif` (Struct) - `Muallif.swift`
Model pengarang kitab yang diambil dari `special.sqlite`:

```swift
struct Muallif: Decodable, Sendable {
    let nama: String        // Kolom DB: "auth"
    let info: String        // Kolom DB: "inf" (biografi ringkas)
    let namaLengkap: String // Kolom DB: "Lng"
}
```

---

## 2. Model Pembaruan & Staging (`BookUpdateModels.swift`)

Model-model ini mengendalikan siklus pembacaan `index.json` dari GitHub Releases serta status pembaruan:

### A. Index Entries

* **`BookIndexEntry`**: Metadata entri buku dari server (ID kitab `bkid`, nama berkas `bk`, kategori, versi `versionName / ver`, URL unduhan, dan ukuran berkas `fileSize / size`).
* **`AuthIndexEntry`**: Metadata entri pembaruan data pengarang (`authId`, versi pengarang `oVer`, URL unduhan).
* **`BookMetadata`**: Kapsulasi skema internal kitab untuk kebutuhan verifikasi sebelum integrasi ke arsip.

### B. `UpdateStatus` (Enum) - Status Pembaruan
Enum penanda alur hidup proses pembaruan kitab:

```swift
enum UpdateStatus: Equatable, Sendable {
    case pending         // Menunggu giliran
    case checking        // Pengecekan versi lokal vs server
    case new             // Kitab baru yang belum pernah diunduh
    case needsUpdate     // Versi server lebih baru dari versi lokal
    case upToDate        // Versi lokal sudah mutakhir
    case downloading     // Proses unduh berkas sedang berjalan
    case downloaded      // Berkas selesai diunduh, menunggu integrasi
    case processing      // Sedang proses injeksi tabel & FTS5
    case completed       // Pembaruan selesai
    case failed(String)  // Terjadi kegagalan
    case skipped         // Dilewati oleh pengguna
}
```

---

## 3. UI State & Filter Enums

### A. `LibraryFilterMode` (Enum) - `LibraryFilterMode.swift`
Segmented filter untuk antarmuka katalog:

* `.all` (0): Seluruh kitab di perpustakaan.
* `.favorites` (1): Kitab yang ditandai sebagai favorit.
* `.history` (2): Kitab yang pernah dibuka di riwayat bacaan.
* `.downloaded` (3): Kitab yang berkas arsipnya sudah tersedia secara luring di perangkat.

### B. `LibraryUpdate` (Enum) - `LibraryUpdate.swift`
Instruksi mutasi delta untuk `NSOutlineView` di macOS:

* `.reloadData`: *Refresh* total *outline*.
* `.reloadItem(Any?, reloadChildren: Bool)`: *Refresh* node tertentu.
* `.expandItem(Any?)`: Membuka percabangan node kategori.
* `.insertItems(IndexSet, parent: Any?)`: Animasi sisip baris baru.
* `.removeItems(IndexSet, parent: Any?)`: Animasi hapus baris.
* `.moveItem(from: Int, to: Int, parent: Any?)`: Animasi perpindahan posisi baris.
