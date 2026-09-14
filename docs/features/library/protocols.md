# Library Protocols & Inter-Module Contracts

Sumber kode: `Source/Features/Library/Protocols/`

---

## 1. Navigasi Pembacaan (`LibraryDelegate`)

Protokol `LibraryDelegate` adalah kontrak utama yang menghubungkan modul **Library** ke modul **Reader** (`IbarotTextVC` di macOS atau `iOSReaderView` di iOS). 

Ketika pengguna memilih salah satu kitab dari katalog, Library tidak memanipulasi reader secara langsung, melainkan mendelegasikannya melalui protokol ini:

```swift
@MainActor
protocol LibraryDelegate: AnyObject {
    func didSelectBook(for book: BooksData, loadContent: Bool) async
}
```

### Parameter:
* `book`: Objek data `BooksData` yang memuat metadata lengkap kitab (ID, judul, kategori, jumlah jilid, status ketersediaan arsip).
* `loadContent`: Boolean penentu apakah konten teks halaman pertama harus langsung dimuat ke Text Engine atau hanya menyiapkan metadata koneksi database buku.

---

## 2. Seleksi Item Baris (`LibraryViewDelegate`)

Protokol `LibraryViewDelegate` digunakan untuk komunikasi antara komponen presentasi sub-view (misalnya outline baris atau tabel sel katalog) dengan manajer data katalog:

```swift
@MainActor
protocol LibraryViewDelegate: AnyObject {
    func didSelectItem(_ row: Int) async
}
```

---

## 3. Integrasi Kolom Pencarian macOS (`SearchableLibrarySidebar`)

Pada platform macOS, komponen pencarian sidebar menggunakan kustom `DSFSearchField`. Protokol `SearchableLibrarySidebar` menyediakan abstraksi default implementation untuk menghubungkan input pencarian toolbar atau split view ke `LibraryViewManager`:

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
Protokol ini memungkinkan beberapa controller sidebar berbeda (`LibraryVC`, `SearchSidebarVC`, dan `RowiSidebarVC`) untuk menggunakan logika pengikatan kolom pencarian (*search field binding*), delegasi fokus ring, dan penyesuaian *content inset* yang seragam (DRY principle).
