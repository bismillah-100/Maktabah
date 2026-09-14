# macOS AppKit

Modul Search di lingkungan desktop macOS menggunakan infrastruktur antarmuka murni AppKit. Ini memisahkan berbagai fungsionalitas visual ke dalam sejumlah *View Controller* khusus yang berkomunikasi dengan `SearchViewModel` melalui *binding reactive* Combine.

## Komponen Antarmuka Utama

### 1. `OptionSearchVC`

Berperan sebagai *Controller* pusat (di *popover* atau *split view*) yang mewadahi fungsional input kolom pencarian, mode parameter (seperti Frasa, Or, Near), dan menampung keluaran hasil di tabel.

*   **Pemantauan *Combine*:** Menyelaraskan *state* seperti pembaruan tabel (`NSTableView`) serta pemuatan bilah progresi (`NSProgressIndicator`) secara asinkron dari notifikasi *Publisher* `SearchViewModel` (`searchDidReceiveResult` dan `searchProgressDidUpdate`).
*   **Kendali Jeda:** Mewadahi tombol Stop/Resume yang menunda sementara rotasi utilitas *thread*.
*   **Menu Konteks (Salin):** Menangani NSMenu "Salin" (*Copy*) khusus yang memanggil protokol `CopyableResult` untuk merangkai format data yang disalin ke papan klip.
*   **Manajemen Migrasi:** Mengekspos opsi panel pemutakhiran (FTS *Migration*) jika arsip FTS3/4 SQLite konvensional perlu ditransformasi ke format baru.

### 2. `SearchSidebarVC`

Mengelola antarmuka *sidebar* sisi yang diperuntukkan bagi navigasi hierarki perpustakaan sebagai cakupan/filter sumber (*Search Scope*).

*   Menggunakan `NSOutlineView` guna mengonstruksi tatanan direktori pohon kitab/kategori.
*   Dibekingi oleh `LibraryViewManager` sehingga pembaruan pustaka otomatis direfleksikan tanpa penanganan data baru.

### 3. `SearchCellView` (dan `.xib`)

Representasi visual *row* (`NSTableCellView`) yang memetakan satuan baris. Sel ini dikonfigurasi guna mampu menggambar tipe data kaya `NSAttributedString` untuk menampilkan sorotan berwarna kuning/hitam pada suku kata kitab yang cocok (*highlighting*).

### 4. `OptionSearchPopover`

Abstraksi penampung (*wrapper*) berbasis `NSPopover` yang mengatur inisialisasi dan tata presentasi apung `OptionSearchVC` jika dipanggil lewat menu bar atau komponen interaksi yang ringkas.
