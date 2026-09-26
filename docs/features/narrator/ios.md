# Narrator iOS Implementation (SwiftUI & UIKit)

Di iOS, fitur Narrator (Rijāl al-Hadīts) beradaptasi dengan lingkungan hibrida: navigasi silsilah perawi yang dalam dieksekusi menggunakan UIKit modern (`UICollectionView` dengan *Diffable Section Snapshot*), sementara presentasi profil dan lembar biografi dikelola secara deklaratif di SwiftUI.

Sumber kode: `Source/Features/Narrator/iOS/`

---

## 1. Arsitektur Komponen Visual

Arsitektur antarmuka perawi pada iOS memadukan komponen UIKit hierarkis dengan presentasi profil SwiftUI:

### A. Hierarki Komponen Hybrid

```mermaid
flowchart TD
    RSB["iOSRowiSidebarView (SwiftUI Wrapper)"]
    HVC["iOSRowiHierarchicalCollectionViewController (UIKit)"]
    DS["UICollectionViewDiffableDataSource"]
    
    RSB --> HVC
    HVC --> DS
    
    DS ~~~ DET
    
    DET["NarratorDetailView (SwiftUI Profile)"]
    CHIPS["Relationships Bar (Shuyukh / Talamidz)"]
    B_LIST["TarjamahSourcesList (Biographical Books)"]
    
    HVC -->|"onSelectRowi"| DET
    DET --> CHIPS
    DET --> B_LIST
    
    B_LIST ~~~ NM
    
    NM["iOSNavigationManager"]
    RV["iOSReaderView (Reader Engine)"]
    ITV["iOSIbarotTextView (UITextView)"]
    
    B_LIST -->|"openTarjamahBook"| NM
    NM --> RV
    RV --> ITV

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class RSB,HVC,DS,DET,CHIPS,B_LIST,RV,ITV ui;
    class NM store;
```

### B. Taksonomi Arsitektur Hybrid

```mermaid
mindmap
  root((Penjelajah Perawi iOS))
    Daftar Hierarki UIKit
      tabaqahNode["Node Induk Tabaqah (folder.fill)"]
      narratorNode["Node Anak Perawi (person.fill)"]
      loadMoreNode["Node Paginasi Asinkron (.loadMore)"]
      sectionSnapshot["NSDiffableDataSourceSectionSnapshot"]
    Profil & Biografi SwiftUI
      narratorProfile["NarratorDetailView"]
      relationshipBar["Bilah Hubungan Guru & Murid"]
      sourceBooks["Daftar Kitab Rujukan Biografi"]
    Jembatan Pembaca
      navigationManager["Injeksi @Environment navigasi"]
      readerPresentation["Pembukaan lembar bacaan iOSReaderView"]
```

---

## 2. Alur Interaksi: Dari Aksi Klik Perawi / Tarjamah ke TextView

Alur interaksi mencakup dua fase: ekspansi/paginasi daftar di sidebar, lalu pembukaan kitab tarjamah ke mesin pembaca:

### A. Routing Interaksi Klik Sidebar

```mermaid
flowchart TD
    CLICK(["Pengguna Mengetuk Baris"]) --> CHK{"Tipe Node Diklik?"}

    CHK -->|"Tombol Load More"| MORE_ACT["HVC.didSelectItemAt (.loadMore)"]
    MORE_ACT --> REQ_BATCH["NarratorViewModel.loadMoreNarrators()"]
    REQ_BATCH --> APPEND_SS["Snapshot Menyelipkan Batch Baru"]

    CHK -->|"Baris Nama Perawi"| ROWI_ACT["HVC.didSelectItemAt (Perawi)"]
    ROWI_ACT --> SHOW_DET["SwiftUI Membuka NarratorDetailView"]

    classDef ui fill:#e040fb26,stroke:#c026d3,stroke-width:2px;
    classDef vm fill:#3b82f626,stroke:#2563eb,stroke-width:2px;
    classDef store fill:#22c55e26,stroke:#16a34a,stroke-width:2px;
    classDef db fill:#f9731626,stroke:#ea580c,stroke-width:2px;
    classDef event fill:#be185d26,stroke:#9d174d,stroke-width:2px,color:#9d174d;

    class CLICK event;
    class CHK,MORE_ACT,APPEND_SS,ROWI_ACT,SHOW_DET ui;
    class REQ_BATCH vm;
```

### B. Alur Buka Sumber Tarjamah ke TextView

```mermaid
sequenceDiagram
    autonumber

    actor User as Pengguna
    participant Tarj as TarjamahDetailView
    participant Nav as iOSNavigationManager
    participant Rdr as iOSReaderView

    User->>+Tarj: Ketuk sumber kitab tarjamah
    Tarj->>+Nav: openBook(tarjamahBook, initialContentId: page)
    Nav->>+Rdr: Tampilkan lembar pembaca (SwiftUI)
    deactivate Rdr
    deactivate Nav
    deactivate Tarj
```

```mermaid
sequenceDiagram
    autonumber

    participant Rdr as iOSReaderView
    participant VM as ReaderViewModel
    participant DB as BookConnection
    participant TV as iOSIbarotTextView

    Rdr->>+VM: loadContent(contentId: page, narratorName: name)
    VM->>+DB: getContent(contentId)
    DB-->>-VM: sourceText biografi
    VM->>VM: ArabicTextRenderer.render() & hitung sorotan perawi
    VM-->>-Rdr: State diperbarui (@Observable contentText)

    Rdr->>+TV: updateUIView(attributedText)
    TV->>TV: UITextView.attributedText = renderedBiographyText
    TV->>TV: Melompat ke paragraf biografi
    deactivate TV
```

---

## 3. Bedah Komponen & Logika Antarmuka

### 1. iOSRowiHierarchicalCollectionViewController (Class)
*Class* turunan dari `BaseHierarchicalListViewController` yang bertugas menampilkan struktur hierarki generasi perawi:

* **Diffable Section Snapshot**: Menggunakan `NSDiffableDataSourceSectionSnapshot` untuk mengelola hubungan bertingkat antara Tabaqah (Induk) dan Perawi (Anak).
* **Mekanisme "Load More" Paginasi**:
  * Untuk tabaqah dengan ratusan perawi, daftar tidak memuat seluruh rekaman sekaligus ke memori.
  * Sistem menyuntikkan sel interaktif khusus dengan identifikasi `.loadMore(tabaqahId)` di posisi akhir section snapshot.
  * Ketika sel ini diketuk, kontroler meminta batch berikutnya ke `special.sqlite`, lalu menyisipkan elemen-elemen baru tepat sebelum tombol "Load More".
* **Indentation Level Visual**: Mengatur `indentationLevel` bawaan UIKit untuk menghasilkan indentasi visual yang presisi tanpa peretasan margin (*margin hack*).

### 2. iOSRowiSidebarView (Struct)
Komponen pembungkus bertipe `UIViewControllerRepresentable`:

* **Pengikatan Coordinator**: Menjembatani delegasi ketukan seleksi perawi di `UICollectionView` menuju ekosistem SwiftUI `NarratorDetailView`.
* **Integrasi `.searchable()`**: Mendeteksi status `.isSearching` dan mengirim kueri pencarian teks secara langsung ke `NarratorViewModel` untuk penyaringan instan (*instant filtering*).

### 3. NarratorDetailView (Struct) & Tarjamah Source Navigation

* Menampilkan kartu biografi komprehensif: nama lengkap, nasab, laqab, tahun wafat, serta derajat jarh wa ta'dil.
* Menyediakan daftar kitab tarjamah yang memuat biografi perawi tersebut. Setiap baris kitab memuat nomor juz dan halaman, yang saat diketuk akan langsung memanggil `navigationManager.openBook` untuk membuka halaman primer kitab biografi terkait.
