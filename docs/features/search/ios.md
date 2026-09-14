# iOS SwiftUI & UIKit

Implementasi antarmuka modul Search untuk platform seluler iOS dan iPadOS dikonstruksi utamanya melalui kombinasi kerangka kerja SwiftUI reaktif, dengan melampirkan beberapa jembatan UIKit untuk memenuhi kebutuhan representasi *tree/list* hierarki pustaka.

## Komponen Antarmuka Utama

### 1. `SearchModeView`

Tampilan akar (*root view*) hierarki pencarian di perangkat genggam yang mengatur komposisi berlapis (*ZStack* dan *Overlay*). 

*   **Integrasi Penuh SwiftUI:** Mengelola *toolbar* sortir dinamis, penyajian lembaran modal (*sheets*) navigasi ke histori carian (*Saved Results*), hingga menampung peringatan (*banner*) migrasi basis data (FTS Migration Overlay).
*   **Aksi Pilihan:** Merespons rute ketukan hasil (di *SearchResultsListView*) menuju *Reader / TextVC* via delegasi aksi (diinisiasi ke `navigationManager.openBook()`).

### 2. `SearchComponents.swift`

Koleksi sub-komponen antarmuka modular:

*   **`SearchInputBar`**: Tata letak *textfield* masukan utama dengan dukungan properti fokus (*keyboard focus state*) dan tombol lintas cepat (Hapus kata).
*   **`SearchHistoryOverlay`**: Hamparan (*overlay*) transparan berisi rentetan 20 riwayat pencarian terakhir pengguna untuk memfasilitasi repetisi pencarian yang efisien.
*   **`SearchProgressView` & `SearchToolbar`**: Komponen pendukung estetika yang menampilkan rasio pencarian (berapa tabel/baris dari seluruh koleksi) dan tombol *Filter*.

### 3. `SearchResultsListView`

Perantara kerangka tampilan pengulangan baris `SearchResultItem` ke dalam sel list.

*   Menyajikan kolom informasi: teks kitab, juz (*part*), dan halaman (*page*) menggunakan modifikasi tulisan kanan-ke-kiri (RTL) ala Arab.
*   **Kompatibilitas Teks Tersorot:** Secara cerdas mentransformasi `NSAttributedString` klasik (*Foundation*) menjadi obyek terbungkus murni tipe nilai SwiftUI yakni struktur `AttributedString`, sehingga rendering kuning pada kata kunci selaras terpoles secara *native* di SwiftUI text rendering.

### 4. `iOSSearchFilterViewController`

Modul pustaka/kategori memiliki tuntutan visualisasi hierarki tingkat (*outline/tree view*) bertingkat untuk pemilihan area *Scope* pencarian. Alih-alih diusahakan seluruhnya di *SwiftUI List*, struktur ini dibangun lebih tangguh di level lapisan `UIKit` dan ditanamkan balik menuju komposisi induk menggunakan jembatan abstraksi semacam `UIViewControllerRepresentable`.
