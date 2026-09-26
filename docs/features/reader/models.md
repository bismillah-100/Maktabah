# Reader Data Models & Structures

Sumber kode: `Source/Features/Reader/Models/`

---

## 1. Model Konten Kitab & Cache

### A. BookContent (Struct) - BookContent.swift
Entitas data mentah halaman kitab yang diambil dari tabel arsip `b{id}`:

```swift
struct BookContent: Sendable {
    let id: Int           // ID baris primer tabel b{id}
    let nash: String      // Teks halaman buku (hasil dekompresi LZString)
    let page: Int         // Nomor halaman cetak buku
    let part: Int         // Nomor jilid/juz buku
    var surah: Int?       // Penanda nomor surah (khusus kitab tafsir/Quran)
    var aya: Int?         // Penanda nomor ayat (khusus kitab tafsir/Quran)
}
```

* Nilai *default* `page` dan `part` diinisialisasi ke `1` jika tidak didefinisikan secara eksplisit.
* Properti `surah` dan `aya` diisi secara kontekstual untuk mendukung sinkronisasi navigasi mushaf pada kitab-kitab tafsir.

---

### B. ProcessedArabicContent (Class) - ProcessedArabicContent.swift
Objek teks hasil pemrosesan tipografi yang siap dikonsumsi oleh *Text View* (`NSTextView` / `UITextView`):

```swift
final class ProcessedArabicContent {
    let sourceText: String
    let displayText: String
    let coloredRanges: [NSRange]
    let footnoteRanges: [NSRange]
    let replacementEvents: [HonorificReplacementEvent]
    let importedHeaderRanges: [NSRange]
    let ligatureRanges: [NSRange]
}
```

* **`sourceText` vs `displayText`**: `sourceText` menyimpan teks Arab asli dari basis data, sedangkan `displayText` merupakan teks yang telah disesuaikan (misalnya: normalisasi harakat, penggantian simbol honorifik atau ligatur).
* **`coloredRanges`**: Rentang karakter yang memerlukan warna khusus (seperti teks matan hadis, ayat Al-Qur'an, atau tanda baca khusus).
* **`footnoteRanges`**: Rentang penanda catatan kaki (*hasyiyah / ta'liq*) di bagian bawah halaman.
* **`replacementEvents`**: Riwayat penggantian frasa honorifik Islam (misalnya *Shallallahu 'alaihi wa sallam*, *Radhiyallahu 'anhu*) dengan glif font ligatur terpadu.

---

### C. CleanedTextKey (Struct) - CleanedTextKey.swift
Kunci *in-memory cache* untuk membedakan varian *rendering* dari halaman yang sama:

```swift
struct CleanedTextKey: Hashable {
    let showHarakat: Bool
    let isMultiLanguage: Bool
    let isImported: Bool
}
```

Dengan menjadikan kombinasi *boolean* ini sebagai kunci *hash*, `BookPageCache` dapat menyimpan dan mengambil teks terformat tanpa perlu menghitung ulang (*re-parsing*) saat pengguna mengubah preferensi tampilan harakat.

---

## 2. IbarotTextOptions (Struct) - Opsi Perenderan Teks

*Struct* parameter yang diteruskan ke *protocol* `TextViewRenderable`:

```swift
struct IbarotTextOptions {
    var content: BookContent? = nil
    var color: PlatformColor? = nil        // NSColor di macOS, UIColor di iOS
    var isMultiLanguage: Bool? = nil
    var isImported: Bool? = nil
    var keepScrollPosition: Bool? = nil
}
```

* **`keepScrollPosition`**: Menentukan apakah posisi gulir layar (*scroll offset*) dipertahankan saat teks dimuat ulang (*reload*), misalnya ketika pengguna mengubah ukuran font atau visibilitas harakat agar posisi baca tidak melompat ke atas.

---

## 3. Daftar Isi / Table of Contents (TOC)

### A. TOC (Struct) - TOC.swift
Representasi baris data mentah dari tabel daftar isi `t{id}` pada berkas arsip SQLite:

```swift
struct TOC {
    let bab: String    // Judul bab / sub-bab (kolom 'tit')
    let level: Int     // Kedalaman hierarki judul (kolom 'lvl')
    let sub: Int       // Penanda sub-elemen
    let id: Int        // Merujuk ke b{id}.id baris konten terkait
}
```

---

### B. TOCNode (Class) - TOCNode.swift
Transformasi hierarkis *node* daftar isi untuk disajikan ke `NSOutlineView` atau SwiftUI `OutlineGroup`:

```swift
final class TOCNode: Identifiable, @unchecked Sendable {
    let bab: String
    let level: Int
    let sub: Int
    let id: Int
    var children: [TOCNode] = []
    var endID: Int = .max
}
```

* **`endID`**: Menandai batas akhir rentang halaman/baris untuk bab tersebut. Digunakan oleh *reader* untuk mendeteksi bab yang sedang aktif dibaca berdasarkan `currentContentId`.
* **Konversi Angka Arab**: Nilai `bab` otomatis dinormalisasi angka Latin-nya menjadi angka Arab (`convertToArabicDigits()`).

---

## 4. ReaderState (Struct) - State Navigasi & Pemulihan Sesi

`ReaderState` merangkum seluruh status tampilan pembaca aktif, memungkinkan pemulihan posisi sesi (*session restoration*):

```swift
struct ReaderState: Codable, Equatable {
    var currentBook: BooksData?
    var currentPage: Int?
    var currentID: Int?
    var currentPart: Int?
    var currentRowi: Rowi?
    var isSidebarCollapsed: Bool = false

    // Navigasi & Scroll
    var scrollPosition: CGPoint?
    var selectedRange: NSRange?
    var expandedNodeIDs: [Int] = []
    var sidebarScrollPosition: CGPoint?

    // Author & Search Integration
    var authorDisplayMode: AuthorDisplayMode?
    var authorTarjamahResults: [TarjamahResult]?
    var searchResults: [SearchResultItem]?
    var searchQuery: String?
}
```

* **`AuthorDisplayMode`**:
    * `.rowiInfo`: Menampilkan biografi perawi hadis (*tarjamah rowi*).
    * `.bookContent`: Menampilkan teks kitab karya pengarang tersebut.
* **`hasContent`**: Properti terhitung untuk memvalidasi apakah layar pembaca sedang memuat naskah aktif atau dalam status kosong (*placeholder*).

---

## 5. BackgroundColor (Enum) & BackgroundOptions - Tema Latar Belakang

Model tema visual pembaca yang diseragamkan untuk platform macOS (AppKit) dan iOS (SwiftUI):

### A. BackgroundColor (Enum) - BackgroundColor.swift

```swift
enum BackgroundColor: Int, CaseIterable, Identifiable {
    case white
    case sepia
    case gray
    case darkSepia
    case black

    var id: Int { rawValue }

    var isDark: Bool { rawValue > 1 }

    /// PlatformColor (NSColor / UIColor) yang otomatis menyesuaikan mode terang/gelap sistem
    var nsColor: PlatformColor { ... }

    /// SwiftUI Color yang otomatis menyesuaikan mode terang/gelap sistem
    var color: Color { ... }
}
```

* **`isDark`**: Penanda boolean terhitung (`rawValue > 1`) untuk menentukan apakah tema latar belakang tergolong gelap (`gray`, `darkSepia`, `black`), digunakan oleh komponen navigasi dan teks untuk membalik warna kontras.
* **`nsColor` & `color`**: Properti terhitung yang mengembalikan warna lintas platform (`PlatformColor` untuk AppKit/UIKit dan `Color` untuk SwiftUI) menggunakan palet warna terpusat dari aset aplikasi (`Assets.xcassets`).

### B. BackgroundOptions (Class) - BackgroundOptions.swift

Komponen kontrol kustom (`NSControl`) untuk rendering pilihan tema warna latar belakang lingkaran pada macOS. Sebelumnya berada pada modul Annotations dan kini dipindahkan ke `Source/Features/Reader/Models/BackgroundOptions.swift`.

