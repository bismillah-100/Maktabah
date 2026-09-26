# Search macOS Implementation (AppKit)

Modul Search di lingkungan macOS menggunakan infrastruktur antarmuka AppKit terpadu dalam `SplitVC`. Komponen visual memisahkan pemilihan cakupan pustaka (*Search Scope*), kontrol parameter masukan, dan penayangan daftar hasil yang diperbarui secara asinkron dari `SearchViewModel`.

Sumber kode: `Source/Features/Search/macOS/`

---

## 1. Arsitektur Komponen Visual

Antarmuka pencarian macOS dikoordinasikan di dalam `SplitVC` dengan pemisahan panel cakupan, panel kontrol hasil, dan area pembaca:

### A. Hierarki Komponen Pencarian

```mermaid
flowchart TD
    SVC["SplitVC (NSSplitViewController)"]
    SSB["SearchSidebarVC (Scope Selector)"]
    SOV["NSOutlineView (Hierarki Pustaka)"]

    SVC --> SSB
    SSB --> SOV

    SOV ~~~ OSVC

    OSVC["OptionSearchVC (Search Controller)"]
    SVM["SearchViewModel (FTS Concurrent Worker)"]

    SVC --> OSVC
    OSVC <-->|"Combine Bindings"| SVM

    OSVC ~~~ ITVC

    ITVC["IbarotTextVC (Content Area)"]
    ITV["IbarotTextView (Highlighted Arabic Text)"]

    SVC --> ITVC
    ITVC --> ITV
    OSVC -.->|"itemDelegate (didSelectResult)"| ITVC

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class SVC,SSB,SOV,OSVC,ITVC,ITV ui;
    class SVM vm;
```

### B. Taksonomi Kontrol & Parameter `OptionSearchVC`

```mermaid
mindmap
  root((OptionSearchVC))
    Masukan Kueri
      DSFSearchField["Kolom input pencarian"]
      RecentSearches["Riwayat pencarian tersimpan"]
    Parameter Operator
      phrasal["Pencarian Frasa Eksak"]
      orNear["Operator OR & Kalimat Berdekatan"]
    Kendali Eksekusi
      startPause["Tombol Mulai / Jeda"]
      cancelBtn["Pembatalan Kueri Aktif"]
      progress["NSProgressIndicator"]
    Penyajian Hasil
      resultsTable["NSTableView"]
      highlightCell["SearchCellView (Cuplikan Kuning)"]
      contextMenu["Salin Teks Arab & Referensi"]
```

---

## 2. Alur Interaksi: Dari Aksi Klik Hasil Pencarian ke TextView

Ketika pengguna mengklik salah satu baris cuplikan hasil pencarian pada tabel `OptionSearchVC`:

```mermaid
sequenceDiagram
    autonumber

    actor User as Pengguna
    participant Tbl as NSTableView
    participant Opt as OptionSearchVC
    participant Rdr as IbarotTextVC

    User->>+Tbl: Klik baris hasil pencarian
    Tbl->>+Opt: didSelectItem(row) / tableViewSelectionDidChange()
    Opt->>+Rdr: itemDelegate?.didSelectResult(result)
    Rdr->>Rdr: displayBook(book, targetPage: result.page)
    deactivate Rdr
    deactivate Opt
    deactivate Tbl
```

```mermaid
sequenceDiagram
    autonumber

    participant Rdr as IbarotTextVC
    participant VM as ReaderViewModel
    participant DB as BookConnection
    participant TV as IbarotTextView

    Rdr->>+VM: loadContent(contentId: result.page, query: result.keyword)
    VM->>+DB: getContent(contentId)
    DB-->>-VM: sourceText mentah
    VM->>VM: ArabicTextRenderer.render() & hitung sorotan kueri
    VM-->>-Rdr: onContentReady(attributedText)

    Rdr->>+TV: textStorage.setAttributedString(attributedText)
    Rdr->>TV: layoutManager.ensureLayout()
    Rdr->>TV: scrollRangeToVisible(matchedWordRange)
    deactivate TV
```

---

## 3. Bedah Komponen Antarmuka Utama

### 1. OptionSearchVC (Class) - Search Controller

* Berperan sebagai kontroler pusat pencarian yang dapat ditempatkan di panel bawah `SplitVC` atau di dalam `OptionSearchPopover`.
* **Pemantauan Combine Asinkron**: Mengamati sinyal `searchDidReceiveResult` dan `searchProgressDidUpdate` dari `SearchViewModel` untuk memperbarui baris tabel secara bertahap tanpa memblokir antarmuka utama.
* **Kendali Eksekusi**: Tombol jeda/lanjutkan (*Pause/Resume*) dan pembatalan (*Cancel*) pencarian FTS *multithread*.
* **Menu Konteks Hasil**: Menyediakan *context menu* klik kanan "Salin" (*Copy*) yang mematuhi *protocol* `CopyableResult` untuk menyusun kutipan teks Arab beserta referensi juz dan halaman.

### 2. SearchSidebarVC (Class) - Penyaring Cakupan / Scope

* Menampilkan hierarki kategori dan kitab menggunakan `NSOutlineView` yang ditenagai oleh `LibraryViewManager`.
* Pengguna dapat memilih satu kitab, sekumpulan kategori, atau seluruh perpustakaan sebagai batasan cakupan (*scope*) kueri pencarian FTS.

### 3. SearchCellView (Class) - Render Cuplikan & Highlight

* *Subclass* `NSTableCellView` yang dirancang untuk me-*render* teks hasil dengan tipografi Arab RTL.
* Menggunakan `NSAttributedString` untuk memberikan latar belakang sorotan kuning pada setiap kata kunci yang cocok dengan kueri pengguna.

### 4. OptionSearchPopover (Class)

* Abstraksi pembungkus berbasis `NSPopover` yang memungkinkan fungsionalitas pencarian `OptionSearchVC` dipanggil secara instan dari bilah menu atau tombol *toolbar* jendela.
