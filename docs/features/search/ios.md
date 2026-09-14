# Search iOS Implementation (SwiftUI & UIKit)

Implementasi antarmuka modul Search untuk platform iOS dan iPadOS memadukan fleksibilitas deklaratif SwiftUI (melalui komponen terisolasi di `SearchComponents.swift`) dengan kestabilan performa UIKit untuk hierarki penyaring cakupan pustaka (*Search Scope*).

Sumber kode: `Source/Features/Search/iOS/`

---

## 1. Arsitektur Komponen Visual

Arsitektur antarmuka pencarian pada iOS membagi tanggung jawab ke dalam komponen masukan terisolasi dan daftar hasil reaktif:

### A. Hierarki Komponen Pencarian

```mermaid
flowchart TD
    SMV["SearchModeView (SwiftUI Root)"]
    SVM["SearchViewModel"]
    
    SMV <-->|"Data Flow"| SVM
    
    SMV ~~~ COMP
    
    COMP["SearchComponents (InputBar, Progress, Toolbar)"]
    RLIST["SearchResultsListView"]
    
    SMV --> COMP
    SMV --> RLIST
    
    RLIST ~~~ F_WRAP
    
    F_WRAP["FilterSheet (Scope Bridge)"]
    F_VC["iOSSearchFilterViewController (UIKit)"]
    
    SMV -.->|"Present Sheet"| F_WRAP
    F_WRAP --> F_VC
    
    F_VC ~~~ NM
    
    NM["iOSNavigationManager"]
    RV["iOSReaderView (Reader Engine)"]
    ITV["iOSIbarotTextView (UITextView)"]
    
    RLIST -->|"onResultTap"| NM
    NM --> RV
    RV --> ITV

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class SMV,COMP,RLIST,F_WRAP,F_VC,RV,ITV ui;
    class SVM vm;
    class NM store;
```

### B. Taksonomi Sub-Komponen `SearchComponents.swift`

```mermaid
mindmap
  root((SearchComponents))
    Masukan & Kontrol
      SearchInputBar["Kolom input teks & kendali fokus keyboard"]
      SearchHistoryOverlay["Overlay 20 pencarian terakhir"]
      SearchProgressView["Indikator rasio progres pencarian"]
      SearchToolbar["Tombol filter cakupan & menu pengurutan"]
    Penyajian Hasil
      SearchResultsListView["LazyVStack / List performa tinggi"]
      SearchResultItem["Sel baris RTL dengan info juz & halaman"]
      AttributedString["Sorotan kuning native pada kata cocok"]
    Penyaring Cakupan
      FilterSheet["Jembatan UIViewControllerRepresentable"]
      ScopeTree["Hierarki pilihan kategori & kitab UIKit"]
```

---

## 2. Alur Interaksi: Dari Aksi Klik Hasil Pencarian ke TextView

Ketika pengguna mengetuk salah satu baris hasil pencarian di `SearchResultsListView`:

```mermaid
sequenceDiagram
    autonumber

    actor User as Pengguna
    participant Item as SearchResultItemView
    participant List as SearchResultsListView
    participant Nav as iOSNavigationManager

    User->>+Item: Ketuk baris hasil pencarian
    Item->>+List: onResultTap(result)
    List->>+Nav: openBook(book, initialContentId: result.page, searchResult: result)
    deactivate Nav
    deactivate List
    deactivate Item
```

```mermaid
sequenceDiagram
    autonumber

    participant Nav as iOSNavigationManager
    participant Rdr as iOSReaderView
    participant VM as ReaderViewModel
    participant TV as iOSIbarotTextView

    Nav->>+Rdr: Tampilkan pembaca dengan parameter pencarian
    Rdr->>+VM: loadContent(contentId: result.page, searchResult: result)
    VM->>VM: BookConnection.getContent() & render()
    VM->>VM: Hitung highlightRanges kata kunci (latar kuning)
    VM-->>-Rdr: State siap (contentText berlatar kuning)

    Rdr->>+TV: updateUIView(attributedText)
    TV->>TV: UITextView.attributedText = renderedText
    TV->>TV: scrollRangeToVisible(matchedWordRange)
    deactivate TV
    deactivate Rdr
```

---

## 3. Bedah Komponen Antarmuka Utama

### 1. `SearchModeView` (Root View)

* Menjadi kontainer utama antarmuka pencarian yang mengelola lapisan `ZStack` dan `Overlay`.
* Mengatur *toolbar* pengurutan dinamis, penyajian lembar modal (*sheets*) menuju histori pencarian tersimpan (*Saved Results*), dan pemberitahuan migrasi basis data FTS bila diperlukan.

### 2. Sub-Komponen Modular (`SearchComponents.swift`)

* **`SearchInputBar`**: Kolom input pencarian utama dengan integrasi `@FocusState` untuk manajemen *keyboard*, tombol pembersih teks instan, dan indikator status aktif.
* **`SearchHistoryOverlay`**: Hamparan mengambang yang menampilkan daftar 20 kueri pencarian terakhir saat kolom teks aktif, memudahkan pencarian berulang tanpa mengetik ulang.
* **`SearchProgressView`**: Bilah kemajuan yang menampilkan rasio pencarian secara riil (jumlah arsip/halaman yang telah dipindai dari total koleksi).
* **`SearchToolbar`**: Bilah tombol aksi untuk menyaring cakupan pustaka, mengubah mode pencarian (Frasa, Dan/Atau, Dekat), serta mengatur urutan hasil pencarian.

### 3. `SearchResultsListView` & Rendering Teks Tersorot

* Menyajikan baris hasil pencarian dengan tata letak teks Arab Kanan-ke-Kiri (RTL).
* **Kompatibilitas AttributedString**: Mengonversi `NSAttributedString` (*Foundation*) dari hasil pencarian FTS menjadi struktur nilai SwiftUI `AttributedString`, memungkinkan *rendering* sorotan warna kuning pada suku kata yang cocok secara *native* tanpa hambatan performa tata letak.

### 4. `iOSSearchFilterViewController` (Penyaring Cakupan / Scope)

* Menggunakan `UIViewControllerRepresentable` untuk memuat struktur hierarki pustaka UIKit (*hierarchical outline*).
* Menangani seleksi multi-pilihan kategori atau kitab dengan performa tinggi saat menyaring ratusan kategori secara bersamaan.
