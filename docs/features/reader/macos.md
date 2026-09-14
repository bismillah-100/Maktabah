# Reader macOS Implementation (AppKit)

Implementasi layar pembaca Maktabah pada macOS dibangun secara *native* menggunakan hierarki murni AppKit tanpa lapisan SwiftUI. Hal ini bertujuan untuk mencapai performa optimal saat me-*render* puluhan ribu baris teks Arab berharakat secara instan tanpa hambatan visual.

Sumber kode:

* Controller: `Source/Features/Reader/macOS/IbarotTextVC.swift`
* Custom TextView: `Source/UI/macOS/TextView/IbarotTextView.swift`

---

## 1. Arsitektur Komponen Visual (UI Hierarchy)

Hierarki tampilan pembaca AppKit dirancang terpisah antara pembungkus kontainer gulir (`NSScrollView`), kanvas perenderan teks kustom (`IbarotTextView`), serta subsistem tipografi teks bawaan macOS:

```mermaid
flowchart TD
    V_SPLIT["ViewerSplitVC (Main Container)"] --> ITVC["IbarotTextVC (View Controller)"]
    V_SPLIT --> TOC["SidebarVC (Table of Contents)"]

    ITVC --> SV["NSScrollView (Scrolling & Insets)"]
    SV --> ITV["IbarotTextView (Custom NSTextView)"]

    ITV --> TS["NSTextStorage (Attributed String Buffer)"]
    ITV --> LM["NSLayoutManager (Non-Contiguous Layout)"]
    ITV --> TC["NSTextContainer (Page Geometry)"]
```

---

## 2. Peta Kontrol, Menu & Popover Interaktif

Seluruh fitur interaktif yang terhubung pada `IbarotTextView` dikelompokkan ke dalam beberapa kategori kontrol:

```mermaid
mindmap
  root((IbarotTextView))
    Menu Kontekstual Klik-Kanan
      Palet Warna Cepat (AnnotationColorMenuView)
      Ubah Tipe (Highlight vs Underline)
      Salin Teks (Dengan / Tanpa Tashkil)
      Pencarian Kontekstual (In-Book / Global)
      Menu Berbagi (Share Sheet)
    Navigasi & Paging
      Bilah Geser (Slider Halaman)
      Tombol Prev dan Next
      Lompat Bab (Daftar Isi / TOC)
    Panel Popover Mandiri
      AnnotationEditorVC (Catatan & Tag)
      BookInfoPopoverVC (Metadata & Tafsir)
    Pengaturan Tampilan
      Keluarga Font Arab
      Ukuran Font Dinamis
      Tema Latar Belakang
```

---

## 3. Pipeline Pemuatan Halaman: Dari Aksi Navigasi ke TextView

Alur linier pemrosesan data ketika pengguna berpindah halaman hingga teks tampil di layar:

```mermaid
flowchart TD
    NAV_EVENT["Aksi Navigasi (Next / Prev / Slider / TOC)"] --> RVM_CALL["ReaderViewModel.loadPage(contentId)"]
    RVM_CALL --> CACHE_CHECK{"Cek BookPageCache?"}

    CACHE_CHECK -->|Hit| GET_CACHE["Ambil BookContent dari LRU Cache"]
    CACHE_CHECK -->|Miss| SQL_GET["BookConnection.getContent()"]
    SQL_GET --> DECOMP["LZString Decompression"]
    DECOMP --> SAVE_CACHE["Simpan ke BookPageCache"]

    GET_CACHE --> RENDER["ArabicTextRenderer.render(content, font, harakatMode)"]
    SAVE_CACHE --> RENDER

    RENDER --> ON_READY["IbarotTextVC.onContentReady(attributedText)"]
    ON_READY --> TEXT_STORAGE["IbarotTextView.textStorage.setAttributedString()"]
```

---

## 4. Siklus Hidup Sinkron & Restorasi Layout

Diagram status (*State Diagram*) berikut memperlihatkan perlunya eksekusi sinkron pada *Main Thread* untuk mencegah pergeseran posisi gulir (*content jumping*):

```mermaid
stateDiagram-v2
    [*] --> Idle : Halaman Ditampilkan
    Idle --> LoadingContent : Navigasi Dipicu
    LoadingContent --> Rendering : Teks Decompress & Format

    state SynchronousMainThreadExecution {
        [*] --> MutasiTextStorage : setAttributedString()
        MutasiTextStorage --> ForceLayout : layoutManager.ensureLayout()
        ForceLayout --> RestoreScroll : restoreScrollPosition()
        RestoreScroll --> [*]
    }

    Rendering --> SynchronousMainThreadExecution : onContentReady Dipanggil
    SynchronousMainThreadExecution --> Idle : Tampilan Stabil (Tanpa Content Jump)
```

---

## 5. Bedah Komponen & Logika Antarmuka

### A. Orkestrasi Sinkron dengan `IbarotTextVC`
`IbarotTextVC` mengontrol alur presentasi tanpa bergantung pada observer asinkron:

```swift
func bindViewModel() {
    viewModel.onContentReady = { [weak self] attributedText in
        guard let self = self else { return }
        self.textView.textStorage?.setAttributedString(attributedText)
        self.textView.layoutManager?.ensureLayout(for: self.textView.textContainer!)
        self.restoreScrollPosition()
    }
}
```

* **Mencegah Content Jumping**: Karena `textStorage` diperbarui secara sinkron pada siklus *RunLoop* yang sama, posisi gulir `NSScrollView` tidak terdistorsi saat berganti halaman.

### B. `IbarotTextView` (Class) - Subkelas `NSTextView`
Mengoptimalkan *rendering* teks Arab berukuran besar:

| Fitur / Modifikasi | Tujuan Teknis |
| :--- | :--- |
| `allowsNonContiguousLayout = true` | **Optimasi Memori**: Hanya menghitung glif dan baris yang berada dalam area *viewport* aktif. |
| `baseWritingDirection = .rightToLeft` | Memastikan pergerakan kursor dan seleksi teks berjalan alami dari kanan ke kiri (RTL). |

### C. Pencegatan Event Klik & Anotasi (`mouseDown`)
`IbarotTextView` menangkap *event* klik untuk memeriksa apakah pengguna mengetuk anotasi yang sudah ada (apabila pengaturan `UserDefaults.enableAnnotationClick` aktif):

```mermaid
flowchart TD
    CLICK["User Klik pada IbarotTextView (mouseDown)"] --> COORD["Konversi Titik: characterIndexForInsertion(at: point)"]
    COORD --> CHECK{"Apakah Berada di Rentang Anotasi?"}

    CHECK -->|"Ya (Ada Annotation ID)"| SHOW_POP["Tampilkan Popover AnnotationEditorVC"]
    SHOW_POP --> SYNC_POP["Sajikan Editor Catatan & Warna Anotasi"]

    CHECK -->|Tidak| SUPER_EVENT["super.mouseDown(with: event)"]
    SUPER_EVENT --> SELECT_MODE["Mode Seleksi Teks Normal"]
```

```swift
override func mouseDown(with event: NSEvent) {
    let point = self.convert(event.locationInWindow, from: nil)
    let charIndex = self.characterIndexForInsertion(at: point)

    if let annotationId = findAnnotation(at: charIndex) {
        showAnnotationEditor(id: annotationId, at: point)
    } else {
        super.mouseDown(with: event)
    }
}
```

### D. Menu Kontekstual Lengkap (`menu(for event:)`)
Ketika pengguna mengklik kanan pada teks atau melakukan seleksi:

* **Palet Warna Cepat (`AnnotationColorMenuView`)**: Menyajikan bulatan warna sorotan langsung di menu klik kanan tanpa harus membuka modal editor.
* **Toggle Underline & Highlight**: Mengubah gaya penandaan antara garis bawah atau latar warna.
* **Opsi Salin Teks**:
  * *Copy with Tashkil*: Menyalin teks lengkap beserta harakat.
  * *Copy without Tashkil*: Menghapus tanda harakat secara instan melalui `ArabicTextRenderer.stripHarakat()` sebelum dimasukkan ke *clipboard*.
* **Pencarian Kontekstual**: Opsi mencari frasa yang diseleksi di dalam kitab aktif (*In-Book Search*) atau di seluruh katalog perpustakaan (*Global FTS*).
* **Menu Penampilan Teks**: Menyesuaikan ukuran font, famili font Arab (*Traditional Arabic*, *Scheherazade*, *Amiri*), dan tema latar belakang (*Sepia*, *Dark Sepia*, *White*, *Black*).
