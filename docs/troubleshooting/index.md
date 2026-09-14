# Debugging & Troubleshooting Guide

Panduan bagi pengembang (*developer*) ketika menemui kendala dalam pengembangan maupun investigasi *bug*.

## 1. Sinkronisasi CloudKit Tidak Berfungsi
**Gejala**: Data anotasi atau *bookmark* tidak muncul di perangkat lain.

* Buka Xcode dan jalankan aplikasi. Periksa log konsol untuk kata kunci: `CloudKitSyncManager` atau `CKError`.
* Pastikan akun pengembang (*developer account*) telah masuk (*login*) ke akun iCloud pada Simulator atau perangkat pengujian.
* Periksa dasbor CloudKit untuk memastikan skema *Custom Zone* telah di-*deploy* ke lingkungan *Production/Development*.

## 2. Inspeksi SQLite Lokal
**Gejala**: Ingin memeriksa struktur tabel atau data secara manual.

* Seluruh basis data pengguna tersimpan di direktori:
  `~/Library/Application Support/Maktabah/`

* Gunakan aplikasi pihak ketiga (seperti [DB Browser for SQLite](https://sqlitebrowser.org/)) untuk membuka berkas `.sqlite`.
* Jika isi tabel `b{id}` tampak seperti karakter acak, teks tersebut dikompresi menggunakan format LZString atau Zstandard (zstd).

## 3. Sorotan Teks (Highlight) Bergeser / Misaligned
**Gejala**: Pengguna menyorot kalimat tertentu, namun antarmuka menyorot rentang kata di sebelahnya.

* Masalah ini umumnya terjadi akibat ketidaksesuaian kalkulasi di `ArabicRangeCalculator`.
* Pastikan logika pemetaan `Source ↔ Display Range` memperhitungkan *edge case* karakter harakat dan tasykil berurutan (misalnya: *Syaddah* + *Fathah/Kasrah*).

## 4. Kueri FTS Sangat Lambat
**Gejala**: Pencarian global memakan waktu lebih dari 5 detik.

* Periksa apakah `SQLiteConnectionPool` berhasil mendistribusikan koneksi pembacaan secara merata.
* Pastikan tidak ada basis data yang terkunci (*database lock contention*). Periksa penggunaan `Mutex` atau `NSLock` pada modul akses data.
