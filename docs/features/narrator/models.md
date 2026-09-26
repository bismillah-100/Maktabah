# Models

Model data pada fitur Narrator merepresentasikan struktur perawi hadis, pengelompokan berdasarkan Tabaqah, dan biografi.

## Rowi (Struct)

Merepresentasikan seorang perawi hadis (dari tabel `rowa`).

- **Properti Utama**:
    - `id`: ID perawi.
    - `name`, `isoName`: Nama asli dan nama yang disesuaikan.
    - `tabaqa`: Tingkatan perawi.
    - `rotba`, `rZahbi`: Penilaian (Jarh wa Ta'dil) dari Ibnu Hajar dan Imam Adz-Dzahabi.
    - `sheok`, `telmez`: Daftar guru (Syekh) dan murid (Tilmidz).
    - `who`: Daftar kitab yang meriwayatkan hadis darinya (Kutub as-Sittah dsb).
    - `wulida`, `tuwuffi`: Tahun lahir dan wafat.

!!! note "Normalisasi String"
    Properti seperti `sheok`, `telmez`, dan `who` otomatis diformat dan dinormalisasi (termasuk mengganti singkatan kode kitab) melalui *property observers* saat objek diinisialisasi atau diperbarui nilainya.

## TabaqaGroup (Struct)

Mengelompokkan daftar perawi berdasarkan *Tabaqah* (tingkatan zaman/generasi).

- **Properti Utama**:
    - `code`: Kode tabaqah (contoh: "F", "G").
    - `name`: Nama tabaqah (contoh: "الصحابي").
    - `rowis`: Seluruh perawi di tabaqah ini.
    - `displayedRowis`: Perawi yang sedang ditampilkan (mendukung *pagination* / *load more*).

## TarjamahMen (Struct)

Merepresentasikan entri pencarian biografi dari tabel `men_b` dan `men_u`.

- **Properti Utama**:
    - `name`: Nama perawi dalam biografi.
    - `bk`: ID Buku (Kitab biografi).
    - `id`: ID baris data biografi pada arsip kitab.
    - `bookTitle`, `archive`: (Diambil dari memori) Judul kitab dan ID arsip.

## TarjamahResult (Struct)

*Struct* lengkap hasil pencarian biografi yang siap dirender di UI. Termasuk potongan teks asli (Nass).

- **Properti Utama**:
    - `tarjamah`: Objek `TarjamahMen` asalnya.
    - `content`: Teks asli tanpa pemformatan kaya.
    - `attributedText`: Teks berformat `NSAttributedString` dengan penyorotan (*highlight*) kata kunci pencarian.

## Enums

### RowiDisplayMode (Enum)

Enum untuk mengatur apa yang sedang dilihat pengguna dari profil seorang perawi:

- `.tilmidz` (التلاميذ): Menampilkan daftar murid.
- `.syaikh` (الشيوخ): Menampilkan daftar guru.
- `.takdil` (الجرح والتعديل): Menampilkan penilaian ulama kritikus hadis.
- `.mulakhosh` (ملخص): Menampilkan ringkasan (nama, tabaqah, lahir/wafat, dsb).
