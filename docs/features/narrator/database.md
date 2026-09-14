# Persistence & Database

Terdapat dua pengelola basis data (Data Manager) spesifik untuk fitur Narrator. Keduanya dikonfigurasikan agar bisa berjalan secara bebas rintangan (non-blocking) di latar belakang (Thread/Task asinkron).

## `RowiDataManager`

Mengelola pemuatan daftar pokok perawi (Rowa). Berjalan di atas tabel `rowa` dari database spesifik `special.sqlite`.

- Menyediakan `tabaqaGroups` (Daftar perawi yang dikelompokkan).
- Fitur utama:
    - **`loadData()`**: Mengambil data ID, Nama, dan Tabaqah dari seluruh perawi dan memetakannya.
    - **`loadRowiData(_:)`**: Mengambil detail spesifik (Lazy loading) profil perawi ketika perawi tersebut dipilih (Jarh, Syekh, Tilmidz, dsb).
    - **`loadMore(_:completion:)`**: Mekanisme pentalan (pagination) untuk daftar Tabaqah agar UI tidak hang memuat ribuan perawi sekaligus.

## `TarjamahGlobalManager`

Pengelola data kompleks untuk menangani pencarian biografi lintas kitab.

- Mengandalkan isolasi via **Actor** (`TarjamahDatabaseActor`) untuk menghindari kondisi balapan (race-condition) saat kueri SQLite.
- **Connection Pooling**: Membuka koneksi `SQLiteConnectionPool` untuk setiap arsip `1-20.sqlite` di latar belakang secara _on-demand_. Pool di-*cache* agar akses baca berikutnya lebih cepat.
- **Optimasi FTS**: Di lingkungan macOS (`#if os(macOS)`), manager ini memiliki logika untuk melakukan optimasi (membuat tabel FTS `special_fts.sqlite`, memadatkannya menggunakan _Zstd Compression_, dan membersihkan index FTS `unicode61`).

### Aliran Pencarian (FTS Stream)

Ketika melakukan kueri pencarian biografi (`searchTarjamah`), mekanisme yang berjalan adalah:

1. Tabel FTS Virtual `men_u_fts` dan `men_b_fts` dieksekusi.
2. Hasil tidak dikembalikan secara masif. Algoritme menggunakan `enumerated()` dan menyela eksekusi setiap 10 item untuk mengecek `pauseController`.
3. Setelah 5 item terkumpul, fungsi akan memanggil `onBatchResult` untuk melempar kumpulan hasil sementara ke ViewModel (Streaming).
4. Sembari hasil di-_stream_, `loadMultipleTarjamahContent` dipanggil asinkron untuk mengambil teks murni (Nass) dari arsip dan membuat pemformatan kata kunci (Highlight AttributedText).
