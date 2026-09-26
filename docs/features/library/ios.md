# Library iOS Implementation (SwiftUI & UIKit Bridge)

Pada platform iOS dan iPadOS, modul Library menggabungkan arsitektur deklaratif SwiftUI dengan efisiensi performa UIKit (`UICollectionView`) untuk menangani katalog ribuan kitab secara responsif pada layar ProMotion 120 FPS.

Sumber kode: `Source/Features/Library/iOS/`

---

## 1. Arsitektur Komponen Visual

Arsitektur antarmuka perpustakaan pada iOS memanfaatkan jembatan SwiftUI-UIKit untuk katalog hierarkis:

### A. Hierarki Kontainer Perpustakaan

```mermaid
flowchart TD
    ILV["iOSLibraryView (SwiftUI Root)"]
    LVM["LibraryViewModel"]
    WRAPPER["LibraryViewControllerWrapper"]
    
    ILV <-->|"State Bindings"| LVM
    ILV --> WRAPPER
    
    WRAPPER ~~~ LVC
    
    LVC["iOSLibraryViewController (UIKit)"]
    COLL["UICollectionView (Diffable Data Source)"]
    
    WRAPPER --> LVC
    LVC --> COLL
    
    COLL ~~~ NM
    
    NM["iOSNavigationManager"]
    RV["iOSReaderView (Reader Engine)"]
    ITV["iOSIbarotTextView (UITextView)"]
    
    LVC -->|"onSelectBook"| NM
    NM --> RV
    RV --> ITV

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class ILV,WRAPPER,LVC,COLL,RV,ITV ui;
    class LVM vm;
    class NM store;
```

### B. Arsitektur Sel Kustom Dwiarah (ListContentView)

```mermaid
flowchart TD
    LCV["ListContentView (Cell Container)"]
    M_STACK["mainStack (.forceLeftToRight)"]
    
    LCV --> M_STACK
    
    L_STACK["leadingStack (Checkbox & Ikon Kitab)"]
    AR_LBL["UILabel (Judul Kitab Arab, .textAlignment = .right)"]
    CHEV["UIImageView (Chevron)"]
    
    M_STACK --> L_STACK
    M_STACK --> AR_LBL
    M_STACK --> CHEV

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class LCV,M_STACK,L_STACK,AR_LBL,CHEV ui;
```

### C. Taksonomi Lembar Kerja & Mode Tampilan

```mermaid
mindmap
  root((Fitur Library iOS))
    Mode Tampilan
      categoryTree["Hierarki Kategori & Kitab (Default)"]
      authorMode["AuthorModeView (Daftar Abjad Pengarang)"]
    Lembar Operasi (Sheets)
      importSheet["Impor Kitab (.sqlite / .bok)"]
      updatesSheet["Pemeriksaan Pembaruan Katalog & Konten"]
      bulkDeleteSheet["Manajemen Penghapusan Massal Kitab"]
    Integrasi Sel
      forceLTR["Enforced LTR Container untuk Layout Konsisten"]
      diffableData["Performa Tinggi 120 FPS UICollectionView"]
```

---

## 2. Alur Interaksi: Dari Aksi Klik Baris Kitab ke TextView

Ketika pengguna mengetuk baris kitab pada `iOSLibraryViewController`:

```mermaid
sequenceDiagram
    autonumber

    actor User as Pengguna
    participant Col as UICollectionView
    participant Coord as Coordinator
    participant Nav as iOSNavigationManager

    User->>+Col: Ketuk baris kitab
    Col->>+Coord: didSelectItemAt(indexPath)
    Coord->>+Nav: openBook(book)
    deactivate Nav
    deactivate Coord
    deactivate Col
```

```mermaid
sequenceDiagram
    autonumber

    participant Nav as iOSNavigationManager
    participant Rdr as iOSReaderView
    participant VM as ReaderViewModel
    participant TV as iOSIbarotTextView

    Nav->>+Rdr: Tampilkan lembar pembaca (SwiftUI)
    Rdr->>+VM: loadBook(book) & loadContent(firstPage)
    VM->>VM: BookConnection.getContent()
    VM->>VM: ArabicTextRenderer.render()
    VM-->>-Rdr: State diperbarui (@Observable contentText)

    Rdr->>+TV: updateUIView(attributedText)
    TV->>TV: UITextView.attributedText = renderedText
    TV->>TV: Merender tipografi Arab & pastikan layout stabil
    deactivate TV
    deactivate Rdr
```

---

## 3. Bedah Komponen & Logika Antarmuka

### A. Tata Letak Sel: Force LTR StackView (ListContentView)
Aplikasi Maktabah secara global mendukung tipografi Arab (RTL). Namun, pada sel daftar kitab (`ListContentView`), elemen antarmuka dikonfigurasi secara terarah:

```swift
override var effectiveUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection {
    .leftToRight
}

init(_ configuration: ListContentConfiguration) {
    appliedConfiguration = configuration
    super.init(frame: .zero)
    semanticContentAttribute = .forceLeftToRight
    setupViews()
    apply(configuration)
}
```

* **Alasan Penggunaan Force LTR:**
  * Judul buku berbahasa Arab secara alami mengalir dari kanan ke kiri. Jika seluruh kontainer sel menggunakan mode RTL, kotak centang (*checkbox*) seleksi massal dan ikon unduhan akan terdorong ke posisi kanan, sedangkan *chevron* navigasi berpindah ke kiri.
  * Dengan menerapkan `semanticContentAttribute = .forceLeftToRight` pada `mainStack` dan `leadingStack`, posisi struktural elemen tetap konsisten: *Leading Stack* (*Checkbox* & Ikon Status) selalu di sisi kiri, dan *Chevron* di sisi kanan.
  * Teks Arab judul kitab (`UILabel`) diberi atribut `textAlignment = .right` dengan `contentHuggingPriority(.defaultLow, for: .horizontal)` sehingga teks mengisi ruang kosong dan rata ke kanan secara alami di dalam *stack* LTR tanpa merusak susunan tombol kontrol.

### B. iOSLibraryView (Struct)

* Mengikat *state* secara deklaratif ke `@Bindable var viewModel = navigationManager.libraryViewModel`.
* Mengelola presentasi modal (*sheets*):
  * **Offline Import Sheet (`OfflineImportFormView`)**: Mengimpor berkas kitab `.sqlite` mandiri dari pengelola berkas Files iOS.
  * **Update Sheet (`UpdateView`)**: Memeriksa dan mengunduh pembaruan isi kitab dari GitHub Releases.
  * **Bulk Delete Dialog**: Dialog konfirmasi penghapusan arsip lokal kitab.

### C. LibraryViewControllerWrapper (UIViewControllerRepresentable)

* Menjembatani `iOSLibraryViewController` ke SwiftUI untuk menjamin kestabilan *frame rate* 60–120 FPS saat pengguliran ribuan baris buku.
* Mengisolasi delegasi seleksi buku dan memperbarui status filter pencarian tanpa membuat ulang hierarki *view*.

### D. AuthorModeView (Struct)

* Mode penyajian katalog khusus berdasarkan daftar pengarang (*muallif*) secara kronologis tahun wafat atau abjad.
* Mengadopsi sistem *lazy loading* untuk memuat karya pengarang secara bertahap saat baris digulir.
