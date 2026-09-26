# Narrator macOS Implementation (AppKit)

Modul Narrator (Rijāl al-Hadīts) pada macOS memanfaatkan arsitektur terintegrasi `SplitVC`, membagi layar antara penjelajah silsilah perawi (Tabaqah), panel biografi terperinci (`RowiResultsVC`), dan mesin pembaca utama (`IbarotTextVC`).

Sumber kode: `Source/Features/Narrator/macOS/`

---

## 1. Arsitektur Komponen Visual

Antarmuka ensiklopedia perawi macOS mendistribusikan navigasi silsilah, panel biografi, dan pembaca teks ke dalam struktur modular:

### A. Hierarki Komponen Perawi

```mermaid
flowchart TD
    SVC["SplitVC (NSSplitViewController)"]
    RSB["RowiSidebarVC (Hierarchy Controller)"]
    ROV["NSOutlineView (Pohon Tabaqah & Perawi)"]
    
    SVC --> RSB
    RSB --> ROV
    
    ROV ~~~ RRVC
    
    RRVC["RowiResultsVC (Biography Controller)"]
    RDM["RowiDataManager / TarjamahDataManager"]
    
    SVC --> RRVC
    RRVC <--> RDM
    
    RRVC ~~~ ITVC
    
    ITVC["IbarotTextVC (Tarjamah Viewer)"]
    ITV["IbarotTextView (Highlighted Biography Text)"]
    
    SVC --> ITVC
    ITVC --> ITV
    RRVC -.->|"delegate (didSelect tarjamahB)"| ITVC

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class SVC,RSB,ROV,RRVC,ITVC,ITV ui;
    class RDM store;
```

### B. Taksonomi Fitur & Panel Perawi

```mermaid
mindmap
  root((Ensiklopedia Perawi))
    RowiSidebarVC
      tabaqahTree["Struktur Pohon Generasi (Tabaqah)"]
      searchField["DSFSearchField (Debounce 300ms)"]
      loadMore["Paginasi Asinkron (LoadMoreCell)"]
    RowiResultsVC
      profileHeader["Kunyah, Nasab, & Jarh-Ta'dil"]
      relationChips["Chips Relasi Guru (Shuyukh) & Murid (Talamidz)"]
      tarjamahSources["Daftar Kitab Sumber Biografi (Tahdzib dsb)"]
    IbarotTextVC
      highlightText["Sorotan Teks Nama Perawi Otomatis"]
      navigation["Sinkronisasi Jilid & Halaman Tarjamah"]
```

### C. Alur Keputusan Interaksi Baris Sidebar

```mermaid
flowchart TD
    CLICK(["Pengguna Klik Baris Sidebar"]) --> CHECK{"Tipe Node Baris?"}
    
    CHECK -->|"Tombol LoadMoreCell"| MORE["Minta Batch Perawi Baru"]
    MORE --> DB_BATCH[("special.sqlite")]
    DB_BATCH --> UPDATE_TREE["Perbarui Sub-Cabang Tabaqah"]
    
    CHECK -->|"Baris Nama Perawi"| SELECT["Pilih Perawi Aktif"]
    SELECT --> LOAD_BIO["RowiResultsVC.loadNarratorBio()"]
    LOAD_BIO --> SHOW_PANEL["Buka Panel Biografi & Daftar Tarjamah"]

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class CLICK event;
    class CHECK,MORE,UPDATE_TREE,SELECT,SHOW_PANEL ui;
    class LOAD_BIO store;
    class DB_BATCH db;
```

---

## 2. Alur Interaksi: Dari Aksi Klik Sumber Tarjamah ke TextView

Ketika pengguna mengklik salah satu baris kitab tarjamah biografi perawi pada tabel `RowiResultsVC`:

```mermaid
sequenceDiagram
    autonumber

    actor User as Pengguna
    participant Res as RowiResultsVC
    participant Split as SplitVC
    participant Rdr as IbarotTextVC

    User->>+Res: Klik baris kitab tarjamah biografi
    Res->>+Split: delegate?.didSelect(tarjamahB:query:)
    Split->>+Rdr: prepareBook(tarjamahBook) & openTarjamahPage()
    deactivate Rdr
    deactivate Split
    deactivate Res
```

```mermaid
sequenceDiagram
    autonumber

    participant Rdr as IbarotTextVC
    participant VM as ReaderViewModel
    participant DB as BookConnection
    participant TV as IbarotTextView

    Rdr->>+VM: loadContent(contentId: tarjamah.page, highlightQuery: narratorName)
    VM->>+DB: getContent(contentId)
    DB-->>-VM: sourceText nass biografi
    VM->>VM: ArabicTextRenderer.render() & hitung highlight perawi
    VM-->>-Rdr: onContentReady(attributedText)

    Rdr->>+TV: textStorage.setAttributedString(attributedText)
    Rdr->>TV: layoutManager.ensureLayout()
    Rdr->>TV: scrollRangeToVisible(narratorRange)
    deactivate TV
```

---

## 3. Bedah Komponen Antarmuka Utama

### 1. RowiSidebarVC (Class) - Sidebar Hierarki & Tabaqah

* **Penyajian Struktur Pohon**: Menggunakan `NSOutlineView` untuk merender pembagian generasi perawi (*Tabaqah*) sebagai node induk dan nama perawi sebagai node anak.
* **Mekanisme Paginasi (`LoadMoreCell`)**: Jika suatu tabaqah memiliki perawi dalam jumlah besar, node terakhir menampilkan sel tombol "Load More" (`group.hasMore`) yang memicu pembacaan batch berikutnya secara asinkron dari basis data `special.sqlite`.
* **Pencarian Cepat**: Menggunakan `DSFSearchField` dengan penundaan *debounce* 300 ms untuk menyaring perawi berdasarkan nama atau laqab secara instan.

### 2. RowiResultsVC (Class) - Kontroler Biografi & Hasil
Memiliki dua mode presentasi dinamis:

* **Mode Profil Perawi (Sidebar Mode)**:
  * Menampilkan ringkasan kunyah, nasab, derajat ta'dil/jarh, serta bilah chip tombol hubungan ("التلاميذ" / Murid dan "الشيوخ" / Guru).
  * Menampilkan tabel `NSTableView` yang merangkum biografi perawi dari berbagai kitab rujukan induk (seperti *Tahdzib al-Kamal*, *Siyar A'lam an-Nubala*, atau *Tahdzib at-Tahdzib*).
* **Mode Pencarian Global (FTS Mode)**:
  * Jika kueri pencarian teks penuh diaktifkan, tabel beralih menampilkan daftar kutipan hadits/biografi dengan bilah kendali *Start/Pause/Stop*.
  * Baris baru disisipkan secara inkremental (`insertRows`) dengan animasi *fade* saat notifikasi `onSearchBatchAppended` diterima.

### 3. Restorasi State (ReaderStateComponent)

* Navigasi antar-perawi dan riwayat klik kitab tarjamah disimpan secara persisten. Ketika jendela ditutup atau mode berpindah, state terakhir perawi yang sedang diteliti dapat direstorasi seketika.
