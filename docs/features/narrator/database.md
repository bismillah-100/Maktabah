# Persistence & Database

Terdapat dua pengelola basis data (*Data Manager*) spesifik untuk fitur Narrator. Keduanya dikonfigurasikan agar berjalan secara asinkron (*non-blocking*) di latar belakang (*background Tasks/Threads*).

## `RowiDataManager`

Mengelola pemuatan daftar pokok perawi (*Rowa*). Berjalan di atas tabel `rowa` dari basis data `special.sqlite`.

- Menyediakan `tabaqaGroups` (Daftar perawi yang dikelompokkan berdasarkan generasi).
- Fitur utama:
    - **`loadData()`**: Mengambil data ID, Nama, dan Tabaqah dari seluruh perawi dan memetakannya ke dalam memori.
    - **`loadRowiData(_:)`**: Mengambil detail profil perawi secara bertahap (*lazy loading*) ketika perawi tersebut dipilih (Jarh, Syekh, Tilmidz, dsb.).
    - **`loadMore(_:completion:)`**: Mekanisme paginasi (*pagination*) untuk daftar Tabaqah agar UI tetap responsif saat memuat ribuan data perawi.

## `TarjamahGlobalManager`

Pengelola data untuk menangani pencarian biografi lintas kitab.

- Mengandalkan isolasi via **Actor** (`TarjamahDatabaseActor`) untuk mencegah kondisi pacu (*race conditions*) saat kueri SQLite berlangsung.
- **Connection Pooling**: Membuka koneksi `SQLiteConnectionPool` untuk setiap arsip `1-20.sqlite` di latar belakang secara *on-demand*. *Pool* disimpan di *cache* agar akses baca berikutnya lebih cepat.
- **Optimasi FTS**: Di lingkungan macOS (`#if os(macOS)`), *manager* ini memiliki logika untuk melakukan optimasi (membuat tabel FTS `special_fts.sqlite`, memadatkannya menggunakan *Zstandard Compression*, dan mengindeks dengan FTS `unicode61`).

### Alur Pencarian (FTS Stream)

Ketika mengeksekusi kueri pencarian biografi (`searchTarjamah`), mekanisme yang berjalan:
1. Membuka koneksi ke basis data FTS biografi.
2. Mengeksekusi pencarian *match query* pada indeks kata kunci nama perawi.
3. Mengembalikan hasil secara bertahap (*batch streaming*) ke `NarratorViewModel` agar antarmuka dapat menyajikan data tanpa jeda.
