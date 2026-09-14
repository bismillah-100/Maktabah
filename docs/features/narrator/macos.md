# macOS AppKit

Di macOS, antarmuka Narrator dipecah ke dalam ViewController terpisah menggunakan AppKit yang dikendalikan oleh SplitView.

## `RowiSidebarVC`

ViewController untuk sidebar sebelah kiri.

- Berisi **`NSOutlineView`** untuk menampilkan hierarki Tabaqah dan Perawi (Folder dan Item).
- Implementasi `NSOutlineViewDataSource` merender nama Tabaqah dan perawi di bawahnya.
- Menyuntikkan sel khusus `"LoadMoreCell"` jika Tabaqah masih memiliki perawi yang belum dimuat (`group.hasMore`).
- Memiliki `DSFSearchField` untuk menyaring perawi berdasarkan namanya dengan metode *debounce* 300ms.

## `RowiResultsVC`

ViewController utama di sebelah kanan. Memiliki multifungsi:

1.  **Profil Perawi (Sidebar Mode)**
    - Jika pengguna memilih profil dari Sidebar, UI akan berubah memperlihatkan chip tombol ("Tلاميذ", "الشيوخ", dll) untuk filter ringkasan.
    - Menampilkan tabel biografi profil perawi yang tersedia di kitab-kitab tarjamah (`NSTableView`).
2.  **Pencarian Global (Full Search Mode)**
    - Jika pengguna mencari melalui mode pencarian teks penuh (FTS), tabel beralih mode.
    - Terdapat tombol **Start/Pause/Stop** untuk mengendalikan alur pencarian FTS asinkron.
    - Tabel (`NSTableView`) dikonfigurasi untuk menerima penyisipan baris parsial (`insertRows`) secara mulus dengan animasi _fade_ ketika `onSearchBatchAppended` dari ViewModel terpicu.

!!! tip "Restorasi State"
    Keduanya terintegrasi dengan ekosistem `ReaderStateComponent`, sehingga saat pengguna menutup tab dan membukanya lagi, histori navigasi perawi dan mode jendela yang terakhir aktif akan dimuat kembali.
