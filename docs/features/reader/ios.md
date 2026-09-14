# Reader iOS Implementation (SwiftUI & UIKit)

Implementasi antarmuka layar pembaca pada platform iOS menggunakan integrasi antara arsitektur deklaratif **SwiftUI** (sebagai pengelola kontainer, *toolbar*, dan lembar modal) dan **UIKit** (`UITextView` melalui `UIViewRepresentable`) demi stabilitas tipografi teks Arab berharakat serta performa *rendering* yang tinggi.

Sumber kode: `Source/Features/Reader/iOS/`

---

## 1. Arsitektur Komponen Visual

Arsitektur antarmuka pembaca iOS mengombinasikan orkestrasi modal deklaratif SwiftUI dengan *rendering engine* UIKit:

### A. Hierarki Kontainer Pembaca

```mermaid
flowchart TD
    IRV["iOSReaderView (SwiftUI Root)"]
    TOP_BAR["Top Navigation Bar"]
    BOT_TB["iOSReaderBottomToolbarView"]
    
    IRV --> TOP_BAR
    IRV --> BOT_TB
    
    BOT_TB ~~~ ITVR
    
    ITVR["iOSIbarotTextView (UIViewRepresentable)"]
    COORD["Coordinator (UITextViewDelegate)"]
    UTV["UITextView (Native Text Container)"]
    
    IRV --> ITVR
    ITVR --> COORD
    COORD --> UTV
    
    UTV ~~~ RVM
    
    RVM["ReaderViewModel (@Observable)"]
    IRV <-->|"State Binding"| RVM

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class IRV,TOP_BAR,BOT_TB,ITVR,COORD,UTV ui;
    class RVM vm;
```

### B. Taksonomi Lembaran Modal (*Toolbar Sheets*)

```mermaid
mindmap
  root((Sheets iOSReaderView))
    Navigasi & Konten
      TOCView["showingTOC (Daftar Isi Bab)"]
      PageJumpSheet["showingNavigation (Lompat Halaman & Juz)"]
      TabsSheet["showingTabsList (Penjelajah Multi-Tab)"]
    Pencarian & Catatan
      SearchInBookSheet["showingSearch (Cari Dalam Kitab)"]
      AnnotationListView["showingAnnotationsList (Daftar Anotasi Kitab)"]
      AnnotationEditorSheet["showingAnnotationActionSheet (Editor Catatan)"]
    Preferensi & Informasi
      AppearanceSheet["showingOptions (Font, Tema, Harakat)"]
      BookInfoSheet["showingBookInfo (Informasi Bibliografi Kitab)"]
```

---

## 2. Alur Interaksi: Dari Aksi Klik Toolbar / Sheet ke TextView

Ketika pengguna memilih bab dari Daftar Isi (TOC), melompat ke halaman tertentu, atau mengetuk hasil pencarian dalam kitab:

```mermaid
flowchart TD
    USER(["Pengguna Memilih di Sheet / Toolbar"]) --> LOAD_PAGE["ReaderViewModel.loadPage(contentId:)"]
    
    LOAD_PAGE --> CACHE_CHECK{"Cek BookPageCache?"}
    CACHE_CHECK -->|"Hit (Cache)"| CACHE_GET["Ambil BookContent dari LRU Cache"]
    CACHE_CHECK -->|"Miss"| DB_GET[("BookConnection.getContent()")]
    DB_GET --> CACHE_SAVE["Simpan ke BookPageCache"]
    
    CACHE_GET --> RENDER["ArabicTextRenderer.render()"]
    CACHE_SAVE --> RENDER
    
    RENDER --> OBS_UPDATE["@Observable ReaderViewModel.contentText"]
    OBS_UPDATE --> BRIDGE_UPDATE["iOSIbarotTextView.updateUIView()"]
    
    BRIDGE_UPDATE --> TV_SET["UITextView.attributedText = renderedText"]
    TV_SET --> TV_SCROLL["UITextView.restoreScrollPosition()"]
    TV_SCROLL --> DISMISS(["Sheet Ditutup"])

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class USER,DISMISS event;
    class CACHE_CHECK,BRIDGE_UPDATE,TV_SET,TV_SCROLL ui;
    class CACHE_GET,CACHE_SAVE,RENDER store;
    class LOAD_PAGE,OBS_UPDATE vm;
    class DB_GET db;
```

---

## 3. Bedah Komponen & Logika Antarmuka

### A. Ekosistem Lembaran Toolbar (*Toolbar Sheets Manager*)
`iOSReaderView` mengontrol visibilitas tampilan modal melalui variabel `@State` boolean terdedikasi:

| Variabel State | Komponen Sheet | Fungsi Utama |
| :--- | :--- | :--- |
| `showingTOC` | `TOCView` | Menampilkan struktur hierarki bab (*outline*) kitab. |
| `showingOptions` | `iOSReaderAppearanceSheet` | Mengonfigurasi ukuran font Arab, famili font, visibilitas harakat, dan tema latar belakang (Sepia, Dark, Black, White). |
| `showingSearch` | `SearchInBookSheet` | Pencarian teks cepat khusus di dalam halaman-halaman kitab aktif. |
| `showingAnnotationsList` | `AnnotationListView` | Menampilkan seluruh penanda dan catatan teks yang tersimpan untuk kitab ini. |
| `showingBookInfo` | `BookInfoSheet` | Kartu informasi bibliografi, penerbit, nomor cetakan, dan tahun wafat pengarang. |
| `showingAnnotationActionSheet` | `iOSAnnotationEditorSheet` | Panel modal penyuntingan isi catatan (*note*), pergantian warna sorotan, atau penghapusan anotasi. |
| `showingNavigation` | `PageJumpSheet` | Bilah geser (*slider*) cepat dan kolom masukan nomor halaman/juz. |
| `showingTabsList` | `TabsSheet` | Menampilkan daftar kitab yang sedang dibuka secara bersamaan (*multi-tab reader*). |

### B. Jembatan `iOSIbarotTextView` (`UIViewRepresentable`)
Mengintegrasikan `UITextView` UIKit ke dalam arsitektur deklaratif SwiftUI:

* **`makeUIView`**: Menginisialisasi `UITextView` kustom dengan properti *non-editable*, *selectable*, serta mendukung perpindahan per halaman (*paging mode*) maupun pengguliran kontinu (*continuous scrolling*).
* **`updateUIView`**: Menerima injeksi `NSAttributedString` baru dari `ReaderViewModel`. Pada metode ini, lapisan warna anotasi dan sorotan kata kunci pencarian diterapkan secara dinamis berdasarkan kalkulasi rentang teks.
* **`Coordinator` (`UITextViewDelegate`)**: Menangani interaksi seleksi teks untuk memunculkan menu pembuatan *highlight/underline* baru serta mencegat ketukan pada rentang anotasi yang telah ada (`onTapAnnotation`).

### C. Penanganan Ekstensi UI & Mode Membaca Layar Penuh (*Fullscreen*)

* **Toggle Fullscreen Mode**: Pengguna dapat mengetuk bagian tengah teks untuk menyembunyikan bilah navigasi atas dan *toolbar* bawah (`isReading.toggle()`), memberikan ruang baca penuh yang imersif.
* **Geometri Layar & Rotasi**: Saat *toolbar* disembunyikan atau orientasi perangkat diputar (*Portrait* $\leftrightarrow$ *Landscape*), tata letak UIKit menyesuaikan *safe area insets* dan melakukan pemulihan posisi gulir (*scroll position restoration*) agar paragraf yang sedang dibaca tidak bergeser.
