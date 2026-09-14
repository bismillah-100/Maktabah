# Persistence & Database

Modul **Search** secara konseptual merupakan modul representasi (*Presentation & Query Orchestration*). Oleh karena itu, modul ini tidak mendefinisikan struktur penyimpanan berkas atau lapisan basis datanya secara eksplisit di dalam direktori `Search`. 

Alih-alih mengelola SQLite secara langsung, pencarian mengandalkan API basis data yang disediakan secara terpusat oleh lapis **Core**.

## Eksekusi ke Modul Core

Interaksi kueri teks mengeksekusi layanan dengan menggunakan komponen sebagai berikut:

### 1. `SearchEngine` (FTS)

Berperan sebagai tulang punggung (motor utama) pencarian. `SearchEngine` menaungi operasi SQLite FTS5 (*Full Text Search*) secara konkuren di beragam koleksi arsip. Kueri FTS5 didelegasikan oleh `SearchViewModel` menuju instruksi *pause/resume/stop* milik unit pencari ini.

### 2. `LibraryDataManager`

Manajer sinkronisasi katalog yang bertugas mendeteksi pustaka, ketersediaan arsip, dan menetapkan filter seleksi kategori buku. Parameter pencarian (`LibrarySearchParams`) diserahkan menuju fungsi penjelajah tabel agar manajer dapat menyelaraskan pencarian FTS ke ruang arsip yang valid.

### 3. `BookConnection`

Konektor SQLite ini digunakan untuk mengambil teks kitab secara langsung ke dalam memori aplikasi. Modul Search menginisialisasi modul ini khususnya saat memulihkan riwayat "Saved Results", guna mengekstraksi dekompresi teks baris tertentu (melalui utilitas `LZString` dekompresi).

## Batas Manajemen (*Bookmarks*)

Hasil markah atau simpanan pengguna (*Saved Results*) tidak disimpan melalui ekstensi direktori ini. Modul *Bookmarks* dan utilitas *CloudKit* menangani pengarsipan (*persistence*) berkas SQLite hasil carian secara terpisah. Modul *Search* bertindak semata-mata sebagai konsumen (*consumer*) yang me-render ulasan cadangan tersebut.
