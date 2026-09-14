# UI & Platform Integration

Dokumentasi ini merangkum jembatan arsitektur dan pola integrasi antarmuka fitur Annotations pada macOS dan iOS, menghubungkan logika data bersama (*Core Engine*) dengan presentasi bawaan (*native*) di masing-masing platform.

Sumber kode:

* macOS: `Source/Features/Annotations/macOS/`
* iOS: `Source/Features/Annotations/iOS/`
* Shared Components: `Source/Features/Annotations/macOS/TagFilterSelectionView.swift`

---

## Arsitektur Integrasi Lintas Platform

Fitur Annotations berbagi logika bisnis, persistensi, dan pemodelan data yang sama (`AnnotationViewModel`, `AnnotationStore`, `AnnotationCoordinator`), namun menggunakan paradigma UI yang dioptimalkan untuk karakteristik masing-masing OS:

### A. Hierarki Integrasi Arsitektur Lintas Platform

```mermaid
flowchart TD
    CORE["Shared Core (AnnotationViewModel & Store)"]
    STORE[("Annotations.sqlite")]
    CORE --> STORE
    
    CORE ~~~ MAC
    
    MAC["macOS UI (AnnotationsVC & NSOutlineView)"]
    CORE -->|"Combine & Data Source"| MAC
    MAC -->|"AnnotationDelegate"| MRDR["macOS Reader (IbarotTextVC)"]
    
    MAC ~~~ IOS
    
    IOS["iOS UI (AnnotationListView & iOSAnnotationVC)"]
    CORE -->|"Bindings & Snapshots"| IOS
    IOS -->|"iOSNavigationManager"| IRDR["iOS Reader (iOSReaderView)"]

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class MAC,MRDR,IOS,IRDR ui;
    class CORE store;
    class STORE db;
```

### B. Taksonomi Komponen Bersama (*Shared Assets*)

```mermaid
mindmap
  root((Shared Annotations))
    Logika Inti
      AnnotationStore["In-memory cache & synchronizer"]
      AnnotationViewModel["Publisher data reaktif Combine"]
      ArabicRangeCalculator["Kalkulasi offset teks berharakat"]
    Komponen UI Bersama
      TagFilterSelectionView["Chips filter tag multiplatform (SwiftUI)"]
      AnnotationJsonSerializer["Serialisasi ekspor/impor dokumen JSON"]
    Sinkronisasi CloudKit
      PrivateZone["Custom zone sync pada iCloud"]
      ConflictResolution["Penyelesaian konflik timestamp mutasi"]
```

---

## Jembatan Integrasi Pembaca (*Reader Navigation Bridge*)

Saat pengguna memilih baris catatan, sistem menavigasi pembaca ke kitab dan halaman target:

### macOS: Delegasi AppKit

* **Protocol**: [`AnnotationDelegate`](file:///Volumes/Dokumen/Downloads/Shamela/Repositories/Maktabah/Source/Features/Annotations/Protocols/AnnotationDelegate.swift).
* **Alur**: `NSOutlineView` mendeteksi pergantian baris $\rightarrow$ `AnnotationsOutlineDelegate.outlineViewSelectionDidChange` $\rightarrow$ memanggil `dataSource.delegate?.didSelect(annotation:)` $\rightarrow$ ditangkap oleh `IbarotTextVC` yang dihubungkan melalui `SplitVC`.
* **Aksi**: Reader memuat kitab target jika belum terbuka, membuka halaman via `contentId`, dan menggeser *viewport* teks ke `highlightRange`.

### iOS: SwiftUI Coordinator & Navigation Manager

* **Alur**: Pengguna mengetuk sel $\rightarrow$ `iOSAnnotationViewController.didSelectItemAt` $\rightarrow$ memicu *closure* `onAnnotationSelected` $\rightarrow$ diterima oleh `AnnotationViewControllerWrapper.Coordinator.handleSelection(_:)`.
* **Pemeriksaan Kitab**: *Coordinator* memeriksa ketersediaan kitab via `LibraryDataManager.shared.getBook([ann.bkId])`:
    * Jika tersedia: Menjalankan `iOSNavigationManager.openBook(book, initialContentId: Int(ann.contentId), targetAnnotation: ann)`.
    * Jika belum diunduh: Mengirimkan `Notification.Name.annotationMissingBook` untuk memunculkan modal peringatan di level SwiftUI `AnnotationListView`.

---

## Komponen Bersama (*Multiplatform Component*)

### `TagFilterSelectionView`
Meskipun tersimpan di direktori `Source/Features/Annotations/macOS/`, komponen ini dirancang *multiplatform* dengan kompilasi kondisional (`#if os(macOS)` dan `#if os(iOS)`):

* **macOS**: Ditampilkan di dalam *popover* pemilihan tag dengan batasan lebar 220–300 pt.
* **iOS**: Dipresentasikan sebagai lembar modal adaptif (`UISheetPresentationController`) dengan *detents* `.medium()` dan `.large()`.
* **Fitur**: Pencarian nama tag secara instan, pemilihan mode logika AND/OR, penyediaan tag yang tersedia (*available tags provider*), serta tombol aksi *Select All* / *Deselect All*.

---

## Ekspor, Impor & Pertukaran Data

1. **Pertukaran Data JSON (macOS & iOS)**:
    * Menggunakan `AnnotationJsonSerializer` untuk serialisasi format dokumen JSON mandiri (`AnnotationJsonDocument`).
    * Di iOS, antarmuka ekspor/impor terintegrasi pada *toolbar* `AnnotationListView` via SwiftUI `.fileExporter` dan `.fileImporter` lengkap dengan dialog konfirmasi penanganan duplikat (*overwrite* atau *skip*).
    * Di macOS, proses ekspor dan impor diakses melalui menu berbagi pada *toolbar* `AnnotationsVC`.
2. **Ekspor RTF (Khusus macOS)**:
    * Komponen `AnnotationRTFExporter` menyusun anotasi terpilih ke dalam format RTF (*Rich Text Format*).
    * Menjaga atribut tipografi teks Arab, nomor jilid/halaman, catatan kaki, serta warna sorotan teks untuk siap disalin ke *clipboard* atau dicetak.

---

## Integrasi Ekstensi Widget

Modul anotasi menyediakan data untuk target Widget Extension:

* **Timeline Provider**: Mengakses kutipan dan catatan harian langsung dari basis data SQLite terbagi via Shared App Group (`group.com.maktabah`).
* **PlatformColor**: Konversi warna heksadesimal yang *platform-agnostic* menjamin representasi visual sorotan dan garis bawah seragam di widget Home Screen maupun Lock Screen.

---

## Tabel Perbandingan UX Lintas Platform

| Fitur | macOS (AppKit) | iOS (SwiftUI + UIKit) |
| :--- | :--- | :--- |
| **Bentuk Tampilan** | Popover tersemat atau Panel melayang (`NSPanel`) | Tab / Navigation View hierarkis |
| **Mesin Daftar** | `NSOutlineView` (Expandable rows) | `UICollectionView` (Hierarchical section snapshot) |
| **Kalkulasi Tinggi** | `AnnotationRowHeightCalculator` manual | Auto-layout via `UIContentConfiguration` |
| **Aksi Geser (Swipe)** | Trailing swipe action untuk Hapus (`NSTableViewRowAction`) | Trailing swipe action untuk Hapus (`trailingSwipeActionsConfigurationProvider`) |
| **Pengeditan Anotasi** | Langsung di sidebar via `AnnotationMenu` & `AnnotationEditorVC` | Di dalam Reader view via `iOSAnnotationEditorSheet` |
| **Filter Tag** | Bilah horizontal di titlebar accessory (`NSTitlebarAccessoryViewController`) | Supplementary header view dengan teknik inversi matriks LTR/RTL |
