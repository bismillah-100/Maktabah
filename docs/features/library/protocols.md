# Library Protocols & Inter-Module Contracts

Sumber kode: `Source/Features/Library/Protocols/`

---

## 1. LibraryDelegate (Protocol) - Navigasi Pembacaan

*Protocol* `LibraryDelegate` adalah kontrak utama yang menghubungkan modul **Library** ke modul **Reader** (`IbarotTextVC` di macOS atau `iOSReaderView` di iOS). 

Ketika pengguna memilih salah satu kitab dari katalog, Library tidak memanipulasi *reader* secara langsung, melainkan mendelegasikannya melalui *protocol* ini:

```swift
@MainActor
protocol LibraryDelegate: AnyObject {
    func didSelectBook(for book: BooksData, loadContent: Bool) async
}
```

### Parameter:

* `book`: Objek data `BooksData` yang memuat metadata lengkap kitab (ID, judul, kategori, jumlah jilid, status ketersediaan arsip).
* `loadContent`: Nilai *boolean* penentu apakah konten teks halaman pertama harus langsung dimuat ke *Text Engine* atau hanya menyiapkan metadata koneksi basis data buku.

---

## 2. LibraryViewDelegate (Protocol) - Seleksi Item Baris

*Protocol* `LibraryViewDelegate` digunakan untuk komunikasi antara komponen presentasi *sub-view* (misalnya baris *outline* atau sel tabel katalog) dengan manajer data katalog:

```swift
@MainActor
protocol LibraryViewDelegate: AnyObject {
    func didSelectItem(_ row: Int) async
}
```

---

## 3. SearchableLibrarySidebar (Protocol) - Integrasi Kolom Pencarian macOS

Pada platform macOS, komponen pencarian *sidebar* menggunakan `DSFSearchField`. *Protocol* `SearchableLibrarySidebar` menyediakan implementasi default untuk menghubungkan input pencarian *toolbar* atau *split view* ke `LibraryViewManager`:

```swift
#if os(macOS)
@MainActor
protocol SearchableLibrarySidebar: AnyObject {
    var searchField: DSFSearchField! { get set }
    func connectSearchField(_ field: DSFSearchField)
}
#endif
```

### Manfaat Arsitektur:
*Protocol* ini memungkinkan beberapa *controller sidebar* yang berbeda (`LibraryVC`, `SearchSidebarVC`, dan `RowiSidebarVC`) untuk menggunakan logika pengikatan kolom pencarian (*search field binding*), delegasi *focus ring*, dan penyesuaian *content inset* yang seragam (prinsip DRY).
